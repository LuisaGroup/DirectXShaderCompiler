//===- NewGVN.cpp - New Global Value Numbering Implementation -------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a new global value numbering (GVN) pass. It uses value
// numbering to detect redundant expressions and replace them with previously
// computed values, eliminating redundant computation.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/DepthFirstIterator.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Value.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "newgvn"

STATISTIC(NumGVNRedundant, "Number of redundancies eliminated");
STATISTIC(NumGVNLoads,     "Number of loads eliminated");

namespace {
  // Forward declare.
  class NewGVN;

  /// Value numbering class: assigns and looks up value numbers for
  /// instructions.
  class ValueNumberer {
  public:
    ValueNumberer() : NextVN(1) {}

    unsigned getOrAssignValueNumber(Value *V);
    unsigned getValueNumber(Value *V) const;
    bool hasValueNumber(Value *V) const;

  private:
    DenseMap<Value *, unsigned> VNMap;
    unsigned NextVN;
  };

  class NewGVN : public FunctionPass {
  public:
    static char ID;
    NewGVN() : FunctionPass(ID) {
      initializeNewGVNPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.setPreservesCFG();
    }

  private:
    bool processBlock(BasicBlock *BB);
    bool eliminateRedundant(Instruction *I);
    unsigned computeCongruentClass(Instruction *I);

    DominatorTree *DT;
    ValueNumberer VN;
    DenseMap<unsigned, Instruction *> LeaderTable;
  };
}

char NewGVN::ID = 0;
INITIALIZE_PASS_BEGIN(NewGVN, "newgvn",
                      "New Global Value Numbering", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(NewGVN, "newgvn",
                    "New Global Value Numbering", false, false)

FunctionPass *llvm::createNewGVNPass() {
  return new NewGVN();
}

unsigned ValueNumberer::getOrAssignValueNumber(Value *V) {
  DenseMap<Value *, unsigned>::iterator It = VNMap.find(V);
  if (It != VNMap.end())
    return It->second;
  unsigned VN = NextVN++;
  VNMap[V] = VN;
  return VN;
}

unsigned ValueNumberer::getValueNumber(Value *V) const {
  DenseMap<Value *, unsigned>::const_iterator It = VNMap.find(V);
  if (It != VNMap.end())
    return It->second;
  return 0;
}

bool ValueNumberer::hasValueNumber(Value *V) const {
  return VNMap.count(V) > 0;
}

/// Compute a value number for an instruction based on its operands.
unsigned NewGVN::computeCongruentClass(Instruction *I) {
  // Constants always get the same value number as themselves.
  if (isa<Constant>(I))
    return VN.getOrAssignValueNumber(I);

  // For instructions, compute a hash from the opcode and the value numbers
  // of operands. This groups congruent instructions together.
  unsigned Opcode = I->getOpcode();
  unsigned Hash = Opcode;

  for (unsigned i = 0; i < I->getNumOperands(); ++i) {
    Value *Op = I->getOperand(i);
    unsigned OpVN = 0;
    if (VN.hasValueNumber(Op))
      OpVN = VN.getValueNumber(Op);
    else if (isa<Constant>(Op))
      OpVN = VN.getOrAssignValueNumber(Op);
    else
      OpVN = reinterpret_cast<size_t>(Op);
    Hash = (Hash << 5) ^ (Hash >> 3) ^ OpVN;
  }

  return Hash;
}

/// Try to eliminate a redundant instruction.
bool NewGVN::eliminateRedundant(Instruction *I) {
  // Skip terminators, phis, and instructions with side effects.
  if (isa<TerminatorInst>(I) || isa<PHINode>(I))
    return false;

  if (I->mayHaveSideEffects() && !isa<LoadInst>(I))
    return false;

  // Compute the value number for this instruction.
  unsigned VN = computeCongruentClass(I);

  // Look for a leader (existing instruction with the same value number that
  // dominates this instruction).
  DenseMap<unsigned, Instruction *>::iterator LeaderIt = LeaderTable.find(VN);
  if (LeaderIt != LeaderTable.end()) {
    Instruction *Leader = LeaderIt->second;
    if (Leader != I && DT->dominates(Leader->getParent(), I->getParent())) {
      // Check that the leader is still live and has the same type.
      if (Leader->getType() == I->getType() && !Leader->isTerminator()) {
        // Replace I with Leader.
        I->replaceAllUsesWith(Leader);
        // Note: we leave I as dead for later DCE to clean up.
        if (isa<LoadInst>(I))
          ++NumGVNLoads;
        else
          ++NumGVNRedundant;
        return true;
      }
    }
  }

  // No leader yet, make this instruction the leader for this value number.
  LeaderTable[VN] = I;
  return false;
}

bool NewGVN::processBlock(BasicBlock *BB) {
  bool Changed = false;

  for (BasicBlock::iterator I = BB->begin(), E = BB->end(); I != E;) {
    Instruction *Inst = I++;
    Changed |= eliminateRedundant(Inst);
  }

  return Changed;
}

bool NewGVN::runOnFunction(Function &F) {
  DT = &getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  bool Changed = false;

  // Process blocks in dominator tree pre-order.
  for (df_iterator<DomTreeNode *> DI = df_begin(DT->getRootNode()),
       DE = df_end(DT->getRootNode()); DI != DE; ++DI) {
    Changed |= processBlock((*DI)->getBlock());
  }

  return Changed;
}
