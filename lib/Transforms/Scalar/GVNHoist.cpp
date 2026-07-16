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
#include "llvm/ADT/SmallVector.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/ValueTracking.h"
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
    DominatorTree *DT;
    bool hoistFromBlock(BasicBlock *BB);
    bool isHoistCandidate(Instruction *Inst, Instruction *InsertPt) const;
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

bool GVNHoist::isHoistCandidate(Instruction *Inst,
                                  Instruction *InsertPt) const {
  if (isa<TerminatorInst>(Inst) || isa<PHINode>(Inst))
    return false;

  // Only speculate pure register computations.  Loads are intentionally rejected:
  // even a non-volatile load can observe different memory when moved above the
  // branch that selected the original block.
  if (Inst->mayReadOrWriteMemory() || !isSafeToSpeculativelyExecute(Inst))
    return false;

  // Every instruction operand must be available at the hoist point.  This is the
  // missing safety check that made hoisting out of if/then blocks create IR whose
  // operands were defined only inside one arm of the branch.
  for (Use &U : Inst->operands())
    if (Instruction *OpI = dyn_cast<Instruction>(U.get()))
      if (!DT->dominates(OpI, InsertPt))
        return false;

  return true;
}

bool GVNHoist::hoistFromBlock(BasicBlock *BB) {
  bool Changed = false;

  // Look for a simple diamond: BB conditionally branches to two single-entry
  // blocks that both branch to the same merge block.
  BranchInst *BI = dyn_cast<BranchInst>(BB->getTerminator());
  if (!BI || !BI->isConditional())
    return false;

  BasicBlock *TrueBB = BI->getSuccessor(0);
  BasicBlock *FalseBB = BI->getSuccessor(1);
  if (TrueBB->getSinglePredecessor() != BB ||
      FalseBB->getSinglePredecessor() != BB)
    return false;

  BranchInst *TrueTerm = dyn_cast<BranchInst>(TrueBB->getTerminator());
  BranchInst *FalseTerm = dyn_cast<BranchInst>(FalseBB->getTerminator());
  if (!TrueTerm || !FalseTerm || TrueTerm->isConditional() ||
      FalseTerm->isConditional() ||
      TrueTerm->getSuccessor(0) != FalseTerm->getSuccessor(0))
    return false;

  Instruction *InsertPt = BB->getTerminator();
  SmallVector<Instruction *, 8> TrueInsts;
  for (BasicBlock::iterator I = TrueBB->begin(), E = TrueBB->end(); I != E;
       ++I)
    if (isHoistCandidate(I, InsertPt))
      TrueInsts.push_back(I);

  for (BasicBlock::iterator I = FalseBB->begin(), E = FalseBB->end(); I != E;) {
    Instruction *FalseInst = I++;
    if (!isHoistCandidate(FalseInst, InsertPt))
      continue;

    for (Instruction *TrueInst : TrueInsts) {
      if (TrueInst == FalseInst || !TrueInst->getParent())
        continue;
      if (!TrueInst->isIdenticalToWhenDefined(FalseInst))
        continue;
      if (!isHoistCandidate(TrueInst, InsertPt))
        continue;

      TrueInst->removeFromParent();
      TrueInst->insertBefore(InsertPt);
      FalseInst->replaceAllUsesWith(TrueInst);
      FalseInst->eraseFromParent();
      ++NumHoisted;
      Changed = true;
      break;
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
