//===- FunctionSpecialization.cpp - Specialize Functions for Constants -----===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass specializes functions for constant arguments by cloning the
// function with the constant propagated. When a function is called with
// constant arguments, it creates a specialized version of the function
// with those constants baked in.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/IPO.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/CallGraph.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/Utils/Cloning.h"
using namespace llvm;

#define DEBUG_TYPE "function-specialization"

STATISTIC(NumSpecialized, "Number of functions specialized");
STATISTIC(NumCallsUpdated, "Number of call sites updated");

namespace {
  class FunctionSpecialization : public ModulePass {
  public:
    static char ID;
    FunctionSpecialization() : ModulePass(ID) {
      initializeFunctionSpecializationPass(*PassRegistry::getPassRegistry());
    }

    bool runOnModule(Module &M) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.addRequired<CallGraphWrapperPass>();
    }

  private:
    bool specializeCallSite(CallSite CS, Function *F);
    bool hasConstantArgs(CallSite CS, SmallVectorImpl<Constant *> &ConstArgs);
    bool isSupportedConstant(Constant *C) const;
    std::string getSpecializedName(Function *F,
                                    const SmallVectorImpl<Constant *> &ConstArgs);
  };
}

char FunctionSpecialization::ID = 0;
INITIALIZE_PASS_BEGIN(FunctionSpecialization, "function-specialization",
                      "Function Specialization", false, false)
INITIALIZE_PASS_DEPENDENCY(CallGraphWrapperPass)
INITIALIZE_PASS_END(FunctionSpecialization, "function-specialization",
                    "Function Specialization", false, false)

ModulePass *llvm::createFunctionSpecializationPass() {
  return new FunctionSpecialization();
}

bool FunctionSpecialization::isSupportedConstant(Constant *C) const {
  // Do not specialize on arbitrary global/function/blockaddress constants.  They
  // can introduce extra module-level references into the clone and were a source
  // of dangling references in downstream code generation.  Integer/null/undef
  // constants have unambiguous specialized names in this lightweight pass.
  return isa<ConstantInt>(C) || isa<ConstantPointerNull>(C) ||
         isa<UndefValue>(C);
}

/// Check if a call site has supported constant arguments, and populates
/// ConstArgs.  Unsupported constants make the call site ineligible rather than
/// being silently folded into a specialization with an ambiguous name.
bool FunctionSpecialization::hasConstantArgs(
    CallSite CS, SmallVectorImpl<Constant *> &ConstArgs) {
  bool HasConstant = false;

  for (unsigned i = 0; i < CS.getNumArgOperands(); ++i) {
    Value *Arg = CS.getArgOperand(i);
    if (Constant *C = dyn_cast<Constant>(Arg)) {
      if (!isSupportedConstant(C))
        return false;
      ConstArgs.push_back(C);
      if (!isa<UndefValue>(C))
        HasConstant = true;
    } else {
      ConstArgs.push_back(nullptr);
    }
  }

  return HasConstant;
}

/// Generate a name for the specialized function.
std::string FunctionSpecialization::getSpecializedName(
    Function *F, const SmallVectorImpl<Constant *> &ConstArgs) {
  std::string Name = F->getName().str() + ".specialized";
  for (unsigned i = 0; i < ConstArgs.size(); ++i) {
    if (ConstArgs[i]) {
      Name += "." + std::to_string(i);
      if (ConstantInt *CI = dyn_cast<ConstantInt>(ConstArgs[i])) {
        Name += "." + std::to_string(CI->getZExtValue());
      } else if (isa<ConstantPointerNull>(ConstArgs[i])) {
        Name += ".null";
      } else if (isa<UndefValue>(ConstArgs[i])) {
        Name += ".undef";
      }
    }
  }
  return Name;
}

/// Specialize a function for the given call site with constant arguments.
bool FunctionSpecialization::specializeCallSite(CallSite CS, Function *F) {
  // Don't specialize functions that are already specialized or too small.
  if (F->getName().find(".specialized") != StringRef::npos)
    return false;

  // Don't specialize varargs functions or functions whose address is observed
  // outside direct calls; cloning those can leave stale indirect-call targets.
  if (F->isVarArg() || F->hasAddressTaken())
    return false;

  SmallVector<Constant *, 8> ConstArgs;
  if (!hasConstantArgs(CS, ConstArgs))
    return false;

  // Check if all constant args are the first N args (or at least some).
  bool HasAnyConstant = false;
  for (unsigned i = 0; i < ConstArgs.size(); ++i) {
    if (ConstArgs[i]) {
      HasAnyConstant = true;
      break;
    }
  }

  if (!HasAnyConstant)
    return false;

  // Create a new name for the specialized function.
  std::string NewName = getSpecializedName(F, ConstArgs);

  // Check if this specialized version already exists.
  Function *SpecF = F->getParent()->getFunction(NewName);
  if (!SpecF) {
    // Clone the function.
    ValueToValueMapTy VMap;
    SpecF = CloneFunction(F, VMap, false, nullptr);

    // Set the new name.
    SpecF->setName(NewName);
    SpecF->setLinkage(GlobalValue::InternalLinkage);

    // Add the new function to the module.
    F->getParent()->getFunctionList().push_back(SpecF);

    // Replace the constant arguments in the cloned function.
    Function::arg_iterator DestI = SpecF->arg_begin();
    for (unsigned i = 0; i < ConstArgs.size(); ++i, ++DestI) {
      if (ConstArgs[i]) {
        // Replace uses of this argument with the constant.
        DestI->replaceAllUsesWith(ConstArgs[i]);
      }
    }

    ++NumSpecialized;
  }

  // Update the call site to call the specialized function.
  if (SpecF) {
    // Build the new args (use constants where available, original args
    // otherwise).
    SmallVector<Value *, 8> NewArgs;
    for (unsigned i = 0; i < CS.getNumArgOperands(); ++i) {
      if (ConstArgs[i])
        NewArgs.push_back(ConstArgs[i]);
      else
        NewArgs.push_back(CS.getArgOperand(i));
    }

    // Create a new call instruction.
    CallSite NewCS;
    if (CS.isCall()) {
      CallInst *OldCall = cast<CallInst>(CS.getInstruction());
      CallInst *NewCall = CallInst::Create(SpecF, NewArgs, "", OldCall);
      NewCall->setCallingConv(OldCall->getCallingConv());
      NewCall->setAttributes(OldCall->getAttributes());
      NewCall->setDebugLoc(OldCall->getDebugLoc());
      if (OldCall->isTailCall())
        NewCall->setTailCall();
      NewCS = CallSite(NewCall);
    } else {
      InvokeInst *OldInv = cast<InvokeInst>(CS.getInstruction());
      InvokeInst *NewInv = InvokeInst::Create(SpecF,
                                               OldInv->getNormalDest(),
                                               OldInv->getUnwindDest(),
                                               NewArgs, "", OldInv);
      NewInv->setCallingConv(OldInv->getCallingConv());
      NewInv->setAttributes(OldInv->getAttributes());
      NewInv->setDebugLoc(OldInv->getDebugLoc());
      NewCS = CallSite(NewInv);
    }

    // Replace uses of the old call with the new one.
    CS.getInstruction()->replaceAllUsesWith(NewCS.getInstruction());
    CS.getInstruction()->eraseFromParent();

    ++NumCallsUpdated;
    return true;
  }

  return false;
}

bool FunctionSpecialization::runOnModule(Module &M) {
  bool Changed = false;

  // Collect potential call sites for specialization.
  // We iterate over functions and look for calls with constant arguments.
  SmallVector<std::pair<CallSite, Function *>, 32> Worklist;

  for (Module::iterator F = M.begin(), E = M.end(); F != E; ++F) {
    if (F->isDeclaration())
      continue;

    for (Function::iterator BB = F->begin(), BE = F->end(); BB != BE; ++BB) {
      for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
        CallSite CS(I);
        if (!CS.getInstruction())
          continue;

        Function *Callee = CS.getCalledFunction();
        if (!Callee || Callee->isDeclaration())
          continue;

        Worklist.push_back(std::make_pair(CS, Callee));
      }
    }
  }

  // Process the worklist.
  for (unsigned i = 0; i < Worklist.size(); ++i) {
    Changed |= specializeCallSite(Worklist[i].first, Worklist[i].second);
  }

  return Changed;
}
