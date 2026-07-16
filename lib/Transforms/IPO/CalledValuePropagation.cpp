//===- CalledValuePropagation.cpp - Propagate Called Values ----------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass propagates information about called values. It tracks which
// functions are called and marks indirect call sites with the target
// function information.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/IPO.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "called-value-propagation"

STATISTIC(NumIndirectCalls, "Number of indirect calls marked");

namespace {
  class CalledValuePropagation : public ModulePass {
  public:
    static char ID;
    CalledValuePropagation() : ModulePass(ID) {
      initializeCalledValuePropagationPass(*PassRegistry::getPassRegistry());
    }

    bool runOnModule(Module &M) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<CallGraphWrapperPass>();
    }

  private:
    bool analyzeFunction(Function &F);
    bool propagateCallSite(CallSite CS);

    SmallPtrSet<Function *, 32> CalledFunctions;
  };
}

char CalledValuePropagation::ID = 0;
INITIALIZE_PASS_BEGIN(CalledValuePropagation, "called-value-propagation",
                      "Called Value Propagation", false, false)
INITIALIZE_PASS_DEPENDENCY(CallGraphWrapperPass)
INITIALIZE_PASS_END(CalledValuePropagation, "called-value-propagation",
                    "Called Value Propagation", false, false)

ModulePass *llvm::createCalledValuePropagationPass() {
  return new CalledValuePropagation();
}

/// Analyze a function to determine which functions it calls directly.
bool CalledValuePropagation::analyzeFunction(Function &F) {
  bool Changed = false;

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      CallSite CS(I);
      if (!CS.getInstruction())
        continue;

      if (Function *Callee = CS.getCalledFunction()) {
        // Direct call: add to the set of called functions.
        CalledFunctions.insert(Callee);
        // If Callee is a declaration, mark it as used.
        if (Callee->isDeclaration() && !Callee->hasFnAttribute(Attribute::NoInline))
          Changed = true;
      } else {
        // Indirect call: try to propagate called values.
        Changed |= propagateCallSite(CS);
      }
    }
  }

  return Changed;
}

/// Try to propagate information about an indirect call site.
bool CalledValuePropagation::propagateCallSite(CallSite CS) {
  Value *Callee = CS.getCalledValue();

  // If the callee is a bitcast of a function, fold to direct call.
  if (BitCastInst *BCI = dyn_cast<BitCastInst>(Callee)) {
    if (Function *F = dyn_cast<Function>(BCI->getOperand(0))) {
      CS.setCalledFunction(F);
      ++NumIndirectCalls;
      return true;
    }
  }

  // If the callee is a constant expression bitcast of a function.
  if (ConstantExpr *CE = dyn_cast<ConstantExpr>(Callee)) {
    if (CE->getOpcode() == Instruction::BitCast) {
      if (Function *F = dyn_cast<Function>(CE->getOperand(0))) {
        CS.setCalledFunction(F);
        ++NumIndirectCalls;
        return true;
      }
    }
  }

  // If the callee is a PHI node where all incoming values are the same
  // function, fold to direct call.
  if (PHINode *PN = dyn_cast<PHINode>(Callee)) {
    Function *CommonFunc = nullptr;
    bool AllSame = true;
    for (unsigned i = 0; i < PN->getNumIncomingValues(); ++i) {
      Function *F = dyn_cast<Function>(PN->getIncomingValue(i));
      if (!F) { AllSame = false; break; }
      if (CommonFunc && F != CommonFunc) { AllSame = false; break; }
      CommonFunc = F;
    }
    if (AllSame && CommonFunc) {
      CS.setCalledFunction(CommonFunc);
      ++NumIndirectCalls;
      return true;
    }
  }

  // If the callee is a SelectInst where both sides are the same function.
  if (SelectInst *SI = dyn_cast<SelectInst>(Callee)) {
    Function *F1 = dyn_cast<Function>(SI->getTrueValue());
    Function *F2 = dyn_cast<Function>(SI->getFalseValue());
    if (F1 && F1 == F2) {
      CS.setCalledFunction(F1);
      ++NumIndirectCalls;
      return true;
    }
  }

  return false;
}

bool CalledValuePropagation::runOnModule(Module &M) {
  bool Changed = false;

  // Collect all called functions.
  for (Module::iterator F = M.begin(), E = M.end(); F != E; ++F) {
    if (!F->isDeclaration())
      Changed |= analyzeFunction(*F);
  }

  return Changed;
}
