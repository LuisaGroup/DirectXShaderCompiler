//===- Attributor.cpp - Function Attribute Inference ----------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass infers function attributes (readonly, readnone, nocapture) by
// analyzing the function body. It examines how arguments are used and whether
// the function accesses memory.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/IPO.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/AliasAnalysis.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/Analysis/CaptureTracking.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/IR/Attributes.h"
#include "llvm/Transforms/IPO/Attributor.h"
using namespace llvm;

#define DEBUG_TYPE "attributor"

STATISTIC(NumReadNone,   "Number of functions marked readnone");
STATISTIC(NumReadOnly,   "Number of functions marked readonly");
STATISTIC(NumNoCapture,  "Number of arguments marked nocapture");
STATISTIC(NumReturned,   "Number of arguments marked returned");

namespace {
  class Attributor : public FunctionPass {
  public:
    static char ID;
    Attributor() : FunctionPass(ID) {
      initializeAttributorPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<CallGraphWrapperPass>();
      AU.addPreserved<CallGraphWrapperPass>();
    }

  private:
    bool inferMemoryAttrs(Function &F);
    bool inferArgumentAttrs(Function &F);
    bool doesNotAccessMemory(Function &F, SmallPtrSet<Function *, 8> &Visited);
    bool onlyReadsMemory(Function &F, SmallPtrSet<Function *, 8> &Visited);
    bool isNoCapture(Argument &Arg);
  };
}

char Attributor::ID = 0;
INITIALIZE_PASS_BEGIN(Attributor, "attributor",
                      "Function attribute inference", false, false)
INITIALIZE_PASS_DEPENDENCY(CallGraphWrapperPass)
INITIALIZE_PASS_END(Attributor, "attributor",
                    "Function attribute inference", false, false)

Pass *llvm::createAttributorPass() {
  return new Attributor();
}

/// Check whether a function does not access memory at all.
bool Attributor::doesNotAccessMemory(Function &F,
                                     SmallPtrSet<Function *, 8> &Visited) {
  if (!Visited.insert(&F).second)
    return true; // Already visiting, assume yes to break cycles.

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      if (isa<LoadInst>(I) || isa<StoreInst>(I))
        return false;
      if (isa<AtomicCmpXchgInst>(I) || isa<AtomicRMWInst>(I))
        return false;

      // Check for memory intrinsics.
      if (MemIntrinsic *MI = dyn_cast<MemIntrinsic>(I))
        return false;

      // Check calls.
      CallSite CS(I);
      if (!CS.getInstruction())
        continue;

      Function *Callee = CS.getCalledFunction();
      if (!Callee || Callee->isDeclaration()) {
        // Can't analyze external function, assume it accesses memory.
        return false;
      }
      if (!doesNotAccessMemory(*Callee, Visited))
        return false;
    }
  }

  return true;
}

/// Check whether a function only reads memory.
bool Attributor::onlyReadsMemory(Function &F,
                                 SmallPtrSet<Function *, 8> &Visited) {
  if (!Visited.insert(&F).second)
    return true;

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      if (isa<StoreInst>(I))
        return false;
      if (isa<AtomicCmpXchgInst>(I) || isa<AtomicRMWInst>(I))
        return false;
      if (isa<MemSetInst>(I) || isa<MemTransferInst>(I))
        return false;

      CallSite CS(I);
      if (!CS.getInstruction())
        continue;

      Function *Callee = CS.getCalledFunction();
      if (!Callee || Callee->isDeclaration()) {
        return false;
      }
      if (!onlyReadsMemory(*Callee, Visited))
        return false;
    }
  }

  return true;
}

/// Check if an argument is not captured (stored or escaped) by the function.
bool Attributor::isNoCapture(Argument &Arg) {
  // Use LLVM's capture tracking.
  SmallPtrSet<const Value *, 8> Captured;
  return !PointerMayBeCaptured(&Arg, true, true);
}

/// Infer memory access attributes (readonly/readnone).
bool Attributor::inferMemoryAttrs(Function &F) {
  bool Changed = false;

  // Check readnone.
  SmallPtrSet<Function *, 8> Visited;
  if (doesNotAccessMemory(F, Visited)) {
    if (!F.doesNotAccessMemory()) {
      F.setDoesNotAccessMemory();
      ++NumReadNone;
      Changed = true;
    }
  } else {
    // Check readonly.
    Visited.clear();
    if (onlyReadsMemory(F, Visited)) {
      if (!F.onlyReadsMemory()) {
        F.setOnlyReadsMemory();
        ++NumReadOnly;
        Changed = true;
      }
    }
  }

  return Changed;
}

/// Infer argument attributes (nocapture, returned).
bool Attributor::inferArgumentAttrs(Function &F) {
  bool Changed = false;

  // Only for functions with definitions.
  if (F.isDeclaration())
    return false;

  for (Function::arg_iterator Arg = F.arg_begin(), E = F.arg_end();
       Arg != E; ++Arg) {
    // Check nocapture. Capture tracking only applies to pointer arguments.
    if (!Arg->hasNoCaptureAttr() && Arg->getType()->isPointerTy() &&
        isNoCapture(*Arg)) {
      AttrBuilder B;
      B.addAttribute(Attribute::NoCapture);
      AttributeSet Attrs = AttributeSet::get(F.getContext(),
                                             Arg->getArgNo() + 1, B);
      Arg->addAttr(Attrs);
      ++NumNoCapture;
      Changed = true;
    }
  }

  return Changed;
}

bool Attributor::runOnFunction(Function &F) {
  bool Changed = false;

  Changed |= inferMemoryAttrs(F);
  Changed |= inferArgumentAttrs(F);

  return Changed;
}
