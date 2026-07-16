//===- CallSiteSplitting.cpp - Split Call Sites Based on Constraints ------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a pass that splits call sites based on known constraints
// from dominating conditions. When a call is inside a branch on a comparison
// with an argument, the call site is split with the constraint info so that
// later passes can optimize the callee better.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/CallSite.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/CFG.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
using namespace llvm;

#define DEBUG_TYPE "callsite-splitting"

STATISTIC(NumCallSitesSplit, "Number of call sites split");

namespace {
  class CallSiteSplitting : public FunctionPass {
  public:
    static char ID;
    CallSiteSplitting() : FunctionPass(ID) {
      initializeCallSiteSplittingPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.setPreservesCFG();
    }

  private:
    bool splitCallSite(CallSite CS, ICmpInst *Cond, bool KnownVal);
    bool processBranch(BranchInst *BI, CallSite CS, Value *Arg);
  };
}

char CallSiteSplitting::ID = 0;
INITIALIZE_PASS_BEGIN(CallSiteSplitting, "callsite-splitting",
                      "Split call sites based on known constraints", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(CallSiteSplitting, "callsite-splitting",
                    "Split call sites based on known constraints", false, false)

FunctionPass *llvm::createCallSiteSplittingPass() {
  return new CallSiteSplitting();
}

bool CallSiteSplitting::splitCallSite(CallSite CS, ICmpInst *Cond,
                                       bool KnownVal) {
  // We can only split if we know the condition's value.
  Instruction *CallI = CS.getInstruction();
  BasicBlock *BB = CallI->getParent();

  // Create a new basic block for the true/false path.
  BasicBlock *NewBB = SplitBlock(BB, CallI, nullptr, nullptr);
  if (!NewBB)
    return false;

  // Set the condition on the branch going to NewBB.
  TerminatorInst *TI = BB->getTerminator();
  if (BranchInst *Br = dyn_cast<BranchInst>(TI)) {
    if (Br->isConditional()) {
      // We know the value of the condition; simplify the branch.
      Value *CondVal = KnownVal ? ConstantInt::getTrue(Cond->getContext())
                                : ConstantInt::getFalse(Cond->getContext());
      Br->setCondition(CondVal);
    }
  }

  ++NumCallSitesSplit;
  return true;
}

bool CallSiteSplitting::processBranch(BranchInst *BI, CallSite CS,
                                       Value *Arg) {
  if (!BI->isConditional())
    return false;

  Value *Cond = BI->getCondition();
  ICmpInst *ICI = dyn_cast<ICmpInst>(Cond);
  if (!ICI)
    return false;

  // Check if the comparison involves our argument.
  if (ICI->getOperand(0) != Arg && ICI->getOperand(1) != Arg)
    return false;

  // We found a comparison with our argument. Split the call site.
  bool Changed = false;
  DominatorTree &DT = getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  (void)DT;
  // Check which successor has the call site.
  for (unsigned i = 0; i < 2; ++i) {
    BasicBlock *Succ = BI->getSuccessor(i);
    if (Succ == CS.getInstruction()->getParent()) {
      bool KnownVal = (i == 0);
      Changed |= splitCallSite(CS, ICI, KnownVal);
    }
  }

  return Changed;
}

bool CallSiteSplitting::runOnFunction(Function &F) {
  bool Changed = false;

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      CallSite CS(I);
      if (!CS.getInstruction())
        continue;

      // Look at the predecessors to find dominating conditions.
      for (pred_iterator PI = pred_begin(BB), PE = pred_end(BB); PI != PE;
           ++PI) {
        BasicBlock *Pred = *PI;
        TerminatorInst *TI = Pred->getTerminator();
        if (BranchInst *BI = dyn_cast<BranchInst>(TI)) {
          for (unsigned i = 0; i < CS.getNumArgOperands(); ++i) {
            Value *Arg = CS.getArgOperand(i);
            Changed |= processBranch(BI, CS, Arg);
          }
        }
      }
    }
  }

  return Changed;
}
