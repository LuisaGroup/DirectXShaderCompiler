//===- ConstraintElimination.cpp - Eliminate Constraints ------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a pass that eliminates icmp/fcmp instructions based on
// dominating conditions. It walks through basic blocks in dominator tree order,
// tracking known facts from conditions, and eliminates redundant comparisons.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/DenseMap.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "constraint-elimination"

STATISTIC(NumCmpEliminated, "Number of comparisons eliminated");
STATISTIC(NumFactsTracked,  "Number of facts tracked");

namespace {
  class ConstraintElimination : public FunctionPass {
  public:
    static char ID;
    ConstraintElimination() : FunctionPass(ID) {
      initializeConstraintEliminationPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<DominatorTreeWrapperPass>();
      AU.setPreservesCFG();
    }

  private:
    // Track known facts: maps (value, value) -> predicate (true/false).
    typedef DenseMap<std::pair<Value *, Value *>, bool> FactMap;

    void addFact(FactMap &Facts, Value *A, Value *B, bool IsEqual);
    bool isKnownTrue(FactMap &Facts, Value *A, Value *B);
    bool isKnownFalse(FactMap &Facts, Value *A, Value *B);
    void processBlock(BasicBlock *BB, FactMap &Facts);
    bool eliminateCmp(CmpInst *Cmp, FactMap &Facts);

    DominatorTree *DT;
  };
}

char ConstraintElimination::ID = 0;
INITIALIZE_PASS_BEGIN(ConstraintElimination, "constraint-elimination",
                      "Eliminate redundant comparisons", false, false)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(ConstraintElimination, "constraint-elimination",
                    "Eliminate redundant comparisons", false, false)

FunctionPass *llvm::createConstraintEliminationPass() {
  return new ConstraintElimination();
}

void ConstraintElimination::addFact(FactMap &Facts, Value *A, Value *B,
                                     bool IsEqual) {
  Facts[std::make_pair(A, B)] = IsEqual;
  Facts[std::make_pair(B, A)] = IsEqual;
  ++NumFactsTracked;
}

bool ConstraintElimination::isKnownTrue(FactMap &Facts, Value *A, Value *B) {
  FactMap::iterator It = Facts.find(std::make_pair(A, B));
  if (It != Facts.end() && It->second)
    return true;
  if (A == B)
    return true;
  return false;
}

bool ConstraintElimination::isKnownFalse(FactMap &Facts, Value *A, Value *B) {
  FactMap::iterator It = Facts.find(std::make_pair(A, B));
  if (It != Facts.end() && !It->second)
    return true;
  return false;
}

bool ConstraintElimination::eliminateCmp(CmpInst *Cmp, FactMap &Facts) {
  Value *Op0 = Cmp->getOperand(0);
  Value *Op1 = Cmp->getOperand(1);

  ICmpInst *IC = dyn_cast<ICmpInst>(Cmp);
  if (!IC)
    return false;

  ICmpInst::Predicate Pred = IC->getPredicate();
  bool Result = false;
  bool Known = false;

  switch (Pred) {
  case ICmpInst::ICMP_EQ:
    if (isKnownTrue(Facts, Op0, Op1)) { Result = true; Known = true; }
    else if (isKnownFalse(Facts, Op0, Op1)) { Result = false; Known = true; }
    break;
  case ICmpInst::ICMP_NE:
    if (isKnownFalse(Facts, Op0, Op1)) { Result = true; Known = true; }
    else if (isKnownTrue(Facts, Op0, Op1)) { Result = false; Known = true; }
    break;
  case ICmpInst::ICMP_ULE:
  case ICmpInst::ICMP_SLE:
  case ICmpInst::ICMP_UGE:
  case ICmpInst::ICMP_SGE:
    if (Op0 == Op1) { Result = true; Known = true; }
    break;
  case ICmpInst::ICMP_ULT:
  case ICmpInst::ICMP_SLT:
  case ICmpInst::ICMP_UGT:
  case ICmpInst::ICMP_SGT:
    if (Op0 == Op1) { Result = false; Known = true; }
    break;
  default:
    break;
  }

  if (Known) {
    Cmp->replaceAllUsesWith(ConstantInt::get(Cmp->getType(), Result));
    ++NumCmpEliminated;
    return true;
  }

  return false;
}

void ConstraintElimination::processBlock(BasicBlock *BB, FactMap &Facts) {
  TerminatorInst *TI = BB->getTerminator();
  if (BranchInst *BI = dyn_cast<BranchInst>(TI)) {
    if (BI->isConditional()) {
      if (ICmpInst *ICI = dyn_cast<ICmpInst>(BI->getCondition())) {
        if (ICI->getPredicate() == ICmpInst::ICMP_EQ) {
          addFact(Facts, ICI->getOperand(0), ICI->getOperand(1), true);
        } else if (ICI->getPredicate() == ICmpInst::ICMP_NE) {
          addFact(Facts, ICI->getOperand(0), ICI->getOperand(1), false);
        }
      }
    }
  }

  for (BasicBlock::iterator I = BB->begin(), E = BB->end(); I != E;) {
    Instruction *Inst = I++;
    if (CmpInst *Cmp = dyn_cast<CmpInst>(Inst)) {
      eliminateCmp(Cmp, Facts);
    }
  }

  DomTreeNode *Node = DT->getNode(BB);
  if (!Node)
    return;

  const std::vector<DomTreeNode *> &Children = Node->getChildren();
  for (unsigned i = 0; i < Children.size(); ++i) {
    FactMap ChildFacts = Facts;
    processBlock(Children[i]->getBlock(), ChildFacts);
  }
}

bool ConstraintElimination::runOnFunction(Function &F) {
  DT = &getAnalysis<DominatorTreeWrapperPass>().getDomTree();

  FactMap Facts;
  processBlock(&F.getEntryBlock(), Facts);

  return NumCmpEliminated > 0;
}
