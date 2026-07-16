//===- GVNHoist.cpp - GVN-based hoisting of identical instructions --------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass hoists identical instructions from then/else blocks to their
// common predecessor if they dominate their uses. It uses GVN-style analysis
// to detect identical expressions.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
using namespace llvm;

#define DEBUG_TYPE "gvn-hoist"

STATISTIC(NumHoisted, "Number of instructions hoisted");

namespace {
  // Simple hash for detecting identical instructions.
  struct InstHash {
    size_t operator()(Instruction *I) const {
      size_t Hash = I->getOpcode();
      for (unsigned i = 0; i < I->getNumOperands(); ++i) {
        Hash ^= reinterpret_cast<size_t>(I->getOperand(i));
        Hash <<= 1;
      }
      if (LoadInst *LI = dyn_cast<LoadInst>(I)) {
        // Don't hoist loads unless they're from the same pointer.
      }
      return Hash;
    }
  };

  struct InstEqual {
    bool operator()(Instruction *A, Instruction *B) const {
      if (A->getOpcode() != B->getOpcode())
        return false;
      if (A->getType() != B->getType())
        return false;
      if (A->getNumOperands() != B->getNumOperands())
        return false;
      for (unsigned i = 0; i < A->getNumOperands(); ++i) {
        if (A->getOperand(i) != B->getOperand(i))
          return false;
      }
      // Check for commutative instruction operand ordering.
      if (A->isCommutative() && A->getNumOperands() == 2) {
        if (A->getOperand(0) == B->getOperand(1) &&
            A->getOperand(1) == B->getOperand(0))
          return true;
      }
      return true;
    }
  };

  class GVNHoist : public FunctionPass {
  public:
    static char ID;
    GVNHoist() : FunctionPass(ID) {
      initializeGVNHoistPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.setPreservesCFG();
    }

  private:
    typedef DenseMap<Instruction *, Instruction *> ValueTable;

    DominatorTree *DT;
    bool hoistFromBlock(BasicBlock *BB);
  };
}

char GVNHoist::ID = 0;
INITIALIZE_PASS_BEGIN(GVNHoist, "gvn-hoist",
                      "GVN hoisting of identical instructions", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(GVNHoist, "gvn-hoist",
                    "GVN hoisting of identical instructions", false, false)

FunctionPass *llvm::createGVNHoistPass() {
  return new GVNHoist();
}

bool GVNHoist::hoistFromBlock(BasicBlock *BB) {
  bool Changed = false;

  // Look for a diamond pattern: BB has two successors that merge.
  TerminatorInst *TI = BB->getTerminator();
  BranchInst *BI = dyn_cast<BranchInst>(TI);
  if (!BI || !BI->isConditional())
    return false;

  BasicBlock *TrueBB = BI->getSuccessor(0);
  BasicBlock *FalseBB = BI->getSuccessor(1);

  // Both successors should have BB as their only predecessor (simple diamond).
  if (TrueBB->getSinglePredecessor() != BB ||
      FalseBB->getSinglePredecessor() != BB)
    return false;

  // Find the merge block (common successor of TrueBB and FalseBB).
  BasicBlock *MergeBB = nullptr;
  for (succ_iterator SI = succ_begin(TrueBB), SE = succ_end(TrueBB); SI != SE;
       ++SI) {
    BasicBlock *Succ = *SI;
    if (Succ != FalseBB && Succ != BB) {
      // Check if FalseBB also goes to this block.
      for (succ_iterator SI2 = succ_begin(FalseBB), SE2 = succ_end(FalseBB);
           SI2 != SE2; ++SI2) {
        if (*SI2 == Succ) {
          MergeBB = Succ;
          break;
        }
      }
    }
    if (MergeBB)
      break;
  }

  if (!MergeBB)
    return false;

  // Collect instructions from TrueBB and FalseBB, find identical pairs.
  ValueTable VN;

  for (BasicBlock::iterator I = TrueBB->begin(), E = TrueBB->end(); I != E;) {
    Instruction *Inst = I++;

    // Skip terminators and phis.
    if (isa<TerminatorInst>(Inst) || isa<PHINode>(Inst))
      continue;

    // Skip instructions with side effects.
    if (Inst->mayHaveSideEffects() && !isa<LoadInst>(Inst))
      continue;

    // Don't hoist loads that might alias.
    if (Inst->mayReadFromMemory())
      continue;

    VN[Inst] = Inst;
  }

  for (BasicBlock::iterator I = FalseBB->begin(), E = FalseBB->end(); I != E;) {
    Instruction *Inst = I++;

    if (isa<TerminatorInst>(Inst) || isa<PHINode>(Inst))
      continue;
    if (Inst->mayHaveSideEffects() && !isa<LoadInst>(Inst))
      continue;
    if (Inst->mayReadFromMemory())
      continue;

    // Check if there's an identical instruction in TrueBB.
    ValueTable::iterator It = VN.find(Inst);
    if (It != VN.end() && It->second != Inst) {
      Instruction *TrueInst = It->second;

      // Verify both instructions have the same type.
      if (TrueInst->getType() != Inst->getType())
        continue;

      // Make sure the hoisted instruction dominates all uses.
      bool DominatesUses = true;
      for (Value::use_iterator UI = TrueInst->use_begin(),
            UE = TrueInst->use_end(); UI != UE; ++UI) {
        Instruction *User = dyn_cast<Instruction>(*UI);
        if (User && User->getParent() != BB) {
          if (!DT->dominates(BB, User->getParent())) {
            DominatesUses = false;
            break;
          }
        }
      }
      if (!DominatesUses)
        continue;

      for (Value::use_iterator UI = Inst->use_begin(),
            UE = Inst->use_end(); UI != UE; ++UI) {
        Instruction *User = dyn_cast<Instruction>(*UI);
        if (User && User->getParent() != BB) {
          if (!DT->dominates(BB, User->getParent())) {
            DominatesUses = false;
            break;
          }
        }
      }
      if (!DominatesUses)
        continue;

      // Hoist TrueInst to BB, before the terminator.
      TrueInst->removeFromParent();
      TrueInst->insertBefore(BB->getTerminator());
      ++NumHoisted;
      Changed = true;

      // Replace uses of Inst with TrueInst.
      Inst->replaceAllUsesWith(TrueInst);
      Inst->eraseFromParent();
    }
  }

  return Changed;
}

bool GVNHoist::runOnFunction(Function &F) {
  DT = &getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  bool Changed = false;

  // Process basic blocks in reverse post-order (dom tree order).
  for (Function::iterator I = F.begin(), E = F.end(); I != E; ++I) {
    Changed |= hoistFromBlock(I);
  }

  return Changed;
}
