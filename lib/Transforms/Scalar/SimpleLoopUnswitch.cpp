//===- SimpleLoopUnswitch.cpp - Simple Loop Unswitching Pass --------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass unswitches loops by duplicating the loop for the true/false paths
// of a condition inside the loop. If the loop contains a branch on a condition
// that is loop-invariant, the loop is cloned and the condition is hoisted.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/Analysis/ScalarEvolution.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/BasicBlockUtils.h"
#include "llvm/Transforms/Utils/Cloning.h"
#include "llvm/Transforms/Utils/LoopUtils.h"
using namespace llvm;

#define DEBUG_TYPE "simple-loop-unswitch"

STATISTIC(NumUnswitched, "Number of loops unswitched");

namespace {
  class SimpleLoopUnswitch : public FunctionPass {
  public:
    static char ID;
    SimpleLoopUnswitch() : FunctionPass(ID) {
      initializeSimpleLoopUnswitchPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.addRequired<LoopInfoWrapperPass>();
      AU.addRequired<ScalarEvolution>();
    }

  private:
    bool unswitchLoop(Loop *L);
    bool isLoopInvariant(Value *V, Loop *L);
    Value *findUnswitchCondition(Loop *L, BasicBlock *&Block);

    DominatorTree *DT;
    LoopInfo *LI;
    ScalarEvolution *SE;
  };
}

char SimpleLoopUnswitch::ID = 0;
INITIALIZE_PASS_BEGIN(SimpleLoopUnswitch, "simple-loop-unswitch",
                      "Simple loop unswitching", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_DEPENDENCY(LoopInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(ScalarEvolution)
INITIALIZE_PASS_END(SimpleLoopUnswitch, "simple-loop-unswitch",
                    "Simple loop unswitching", false, false)

Pass *llvm::createSimpleLoopUnswitchPass() {
  return new SimpleLoopUnswitch();
}

/// Check if a value is loop-invariant.
bool SimpleLoopUnswitch::isLoopInvariant(Value *V, Loop *L) {
  if (isa<Constant>(V))
    return true;

  if (Argument *Arg = dyn_cast<Argument>(V))
    return true;

  if (Instruction *I = dyn_cast<Instruction>(V)) {
    if (!L->contains(I->getParent()))
      return true;

    // Check operands recursively.
    for (unsigned i = 0; i < I->getNumOperands(); ++i) {
      if (!isLoopInvariant(I->getOperand(i), L))
        return false;
    }
    return true;
  }

  return false;
}

/// Find a condition inside the loop that is loop-invariant and can be
/// unswitched.
Value *SimpleLoopUnswitch::findUnswitchCondition(Loop *L, BasicBlock *&Block) {
  // Look for a conditional branch in the loop header or loop body.
  for (Loop::block_iterator BI = L->block_begin(), BE = L->block_end();
       BI != BE; ++BI) {
    BasicBlock *BB = *BI;
    TerminatorInst *TI = BB->getTerminator();
    BranchInst *Br = dyn_cast<BranchInst>(TI);
    if (!Br || !Br->isConditional())
      continue;

    Value *Cond = Br->getCondition();
    if (isLoopInvariant(Cond, L)) {
      Block = BB;
      return Cond;
    }
  }

  return nullptr;
}

/// Unswitch a loop by cloning it for the true/false paths of a condition.
bool SimpleLoopUnswitch::unswitchLoop(Loop *L) {
  BasicBlock *CondBlock = nullptr;
  Value *Cond = findUnswitchCondition(L, CondBlock);

  if (!Cond || !CondBlock)
    return false;

  // Clone the loop for the true path.
  const std::vector<BasicBlock *> &OrigBlocks = L->getBlocks();

  ValueToValueMapTy VMap;
  SmallVector<BasicBlock *, 8> NewBlocks;

  // Clone all blocks in the loop.
  for (unsigned i = 0; i < OrigBlocks.size(); ++i) {
    BasicBlock *NewBB = CloneBasicBlock(OrigBlocks[i], VMap, "", nullptr);
    VMap[OrigBlocks[i]] = NewBB;
    NewBlocks.push_back(NewBB);
  }

  // Remap references in the cloned blocks.
  for (unsigned i = 0; i < NewBlocks.size(); ++i) {
    BasicBlock *NewBB = NewBlocks[i];
    for (BasicBlock::iterator II = NewBB->begin(), IE = NewBB->end();
         II != IE; ++II) {
      RemapInstruction(II, VMap,
                       RF_NoModuleLevelChanges | RF_IgnoreMissingEntries);
    }
  }

  // Find the cloned condition block.
  BasicBlock *NewCondBlock = cast<BasicBlock>(VMap[CondBlock]);

  // Set the cloned branch to always take the true path.
  TerminatorInst *NewTI = NewCondBlock->getTerminator();
  BranchInst *NewBr = cast<BranchInst>(NewTI);
  NewBr->setCondition(ConstantInt::getTrue(Cond->getContext()));

  // Set the original branch to always take the false path.
  BranchInst *OrigBr = cast<BranchInst>(CondBlock->getTerminator());
  OrigBr->setCondition(ConstantInt::getFalse(Cond->getContext()));

  // Insert the cloned blocks into the function after the original loop.
  Function *F = L->getHeader()->getParent();
  BasicBlock *InsertBefore = L->getExitBlock();
  if (!InsertBefore) {
    // If no single exit block, insert after the last loop block.
    InsertBefore = L->getExitingBlock();
    if (InsertBefore)
      InsertBefore = InsertBefore->getNextNode();
  }

  for (unsigned i = 0; i < NewBlocks.size(); ++i) {
    if (InsertBefore)
      NewBlocks[i]->moveBefore(InsertBefore);
    else
      F->getBasicBlockList().push_back(NewBlocks[i]);
  }

  ++NumUnswitched;
  return true;
}

bool SimpleLoopUnswitch::runOnFunction(Function &F) {
  DT = &getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  LI = &getAnalysis<LoopInfoWrapperPass>().getLoopInfo();
  SE = &getAnalysis<ScalarEvolution>();
  bool Changed = false;

  // Process loops from innermost to outermost.
  for (LoopInfo::iterator I = LI->begin(), E = LI->end(); I != E; ++I) {
    // Process sub-loops first.
    for (Loop::iterator SI = (*I)->begin(), SEI = (*I)->end(); SI != SEI; ++SI) {
      Changed |= unswitchLoop(*SI);
    }
    Changed |= unswitchLoop(*I);
  }

  return Changed;
}
