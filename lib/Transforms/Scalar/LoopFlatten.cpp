//===- LoopFlatten.cpp - Flatten Nested Loops into Single Loops -----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass flattens nested loops into single loops when possible. It detects
// simple inner loops with induction variables and merges them, effectively
// converting a double-loop into a single loop with a wider trip count.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/Analysis/ScalarEvolutionExpressions.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/LoopUtils.h"
using namespace llvm;

#define DEBUG_TYPE "loop-flatten"

STATISTIC(NumFlattened, "Number of nested loops flattened");

namespace {
  class LoopFlatten : public FunctionPass {
  public:
    static char ID;
    LoopFlatten() : FunctionPass(ID) {
      initializeLoopFlattenPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.addRequired<LoopInfoWrapperPass>();
      AU.addRequired<ScalarEvolution>();
      AU.setPreservesCFG();
    }

  private:
    bool flattenLoop(Loop *L, LoopInfo &LI, ScalarEvolution &SE,
                     DominatorTree &DT);
    bool isSimpleIV(PHINode *Phi, const SCEV *&TripCount,
                    ScalarEvolution &SE, LoopInfo &LI);
  };
}

char LoopFlatten::ID = 0;
INITIALIZE_PASS_BEGIN(LoopFlatten, "loop-flatten",
                      "Flatten nested loops", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_DEPENDENCY(LoopInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(ScalarEvolution)
INITIALIZE_PASS_END(LoopFlatten, "loop-flatten",
                    "Flatten nested loops", false, false)

FunctionPass *llvm::createLoopFlattenPass() {
  return new LoopFlatten();
}

/// Check if a PHI node is a simple induction variable (starts at 0, increments
/// by 1, compares against a loop-invariant).
bool LoopFlatten::isSimpleIV(PHINode *Phi, const SCEV *&TripCount,
                              ScalarEvolution &SE, LoopInfo &LI) {
  BasicBlock *Header = Phi->getParent();
  Loop *L = LI.getLoopFor(Header);
  if (!L)
    return false;

  // Check the PHI structure.
  Value *InitVal = nullptr;
  Value *StepVal = nullptr;
  for (unsigned i = 0; i < Phi->getNumIncomingValues(); ++i) {
    BasicBlock *IncomingBB = Phi->getIncomingBlock(i);
    if (L->contains(IncomingBB)) {
      StepVal = Phi->getIncomingValue(i);
    } else {
      InitVal = Phi->getIncomingValue(i);
    }
  }

  if (!InitVal || !StepVal)
    return false;

  // Check that init value is zero.
  ConstantInt *CInit = dyn_cast<ConstantInt>(InitVal);
  if (!CInit || !CInit->isZero())
    return false;

  // Check the step is add of constant 1.
  Instruction *StepInst = dyn_cast<Instruction>(StepVal);
  if (!StepInst || StepInst->getOpcode() != Instruction::Add)
    return false;

  if (StepInst->getOperand(0) != Phi &&
      StepInst->getOperand(1) != Phi)
    return false;

  ConstantInt *StepConst = nullptr;
  if (StepInst->getOperand(0) == Phi)
    StepConst = dyn_cast<ConstantInt>(StepInst->getOperand(1));
  else
    StepConst = dyn_cast<ConstantInt>(StepInst->getOperand(0));

  if (!StepConst || !StepConst->isOne())
    return false;

  // Find the comparison that uses this PHI to determine trip count.
  for (Value::user_iterator UI = Phi->user_begin(), UE = Phi->user_end();
       UI != UE; ++UI) {
    ICmpInst *Cmp = dyn_cast<ICmpInst>(*UI);
    if (!Cmp || Cmp->getParent() != Header)
      continue;

    if (Cmp->getOperand(0) == Phi) {
      TripCount = SE.getSCEV(Cmp->getOperand(1));
      if (TripCount && !isa<SCEVCouldNotCompute>(TripCount))
        return true;
    } else if (Cmp->getOperand(1) == Phi) {
      TripCount = SE.getSCEV(Cmp->getOperand(0));
      if (TripCount && !isa<SCEVCouldNotCompute>(TripCount))
        return true;
    }
  }

  return false;
}

/// Attempt to flatten a nested loop (inner loop inside outer loop).
bool LoopFlatten::flattenLoop(Loop *L, LoopInfo &LI, ScalarEvolution &SE,
                               DominatorTree &DT) {
  (void)L;
  (void)LI;
  (void)SE;
  (void)DT;

  // The previous implementation moved inner-loop basic blocks in the function
  // list but did not rewrite branches, PHI nodes, LoopInfo, DominatorTree, or
  // ScalarEvolution.  That produced malformed SSA/CFG and downstream invalid
  // SPIR-V.  Until a complete loop-flattening transform is implemented, keep the
  // pass as a conservative no-op rather than emitting broken IR.
  return false;
}

bool LoopFlatten::runOnFunction(Function &F) {
  LoopInfo &LI = getAnalysis<LoopInfoWrapperPass>().getLoopInfo();
  ScalarEvolution &SE = getAnalysis<ScalarEvolution>();
  DominatorTree &DT = getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  bool Changed = false;

  // Flatten top-level loops.
  for (LoopInfo::iterator I = LI.begin(), E = LI.end(); I != E; ++I) {
    Changed |= flattenLoop(*I, LI, SE, DT);
  }

  return Changed;
}
