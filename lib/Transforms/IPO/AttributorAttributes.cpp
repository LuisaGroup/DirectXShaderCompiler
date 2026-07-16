//===- AttributorAttributes.cpp - Attribute Inference Utilities -----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file provides helper utilities for the Attributor pass. It defines
// attribute inference utilities used to deduce function and argument
// attributes.
//
//===----------------------------------------------------------------------===//

#include "llvm/ADT/Statistic.h"
#include "llvm/Transforms/IPO/Attributor.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/Attributes.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalAlias.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "attributor-attrs"

STATISTIC(NumNoAlias,    "Number of noalias arguments inferred");
STATISTIC(NumNonNull,    "Number of nonnull arguments inferred");

/// Check if a value is used only for comparison (can determine nonnull).
static bool isUsedInComparison(Value *V) {
  for (Value::user_iterator UI = V->user_begin(), UE = V->user_end();
       UI != UE; ++UI) {
    if (ICmpInst *Cmp = dyn_cast<ICmpInst>(*UI)) {
      if (Cmp->getPredicate() == ICmpInst::ICMP_NE ||
          Cmp->getPredicate() == ICmpInst::ICMP_EQ) {
        // Compared against null.
        if (isa<ConstantPointerNull>(Cmp->getOperand(0)) ||
            isa<ConstantPointerNull>(Cmp->getOperand(1)))
          return true;
      }
    }
  }
  return false;
}

/// Check if an argument can be marked noalias by analyzing the function body.
/// An argument can be marked noalias if it is a pointer that is not used in
/// ways that would alias with other pointers.
static bool canBeNoAlias(Argument &Arg) {
  // Only pointer arguments can be noalias.
  if (!Arg.getType()->isPointerTy())
    return false;

  // Check all uses of the argument in the function.
  for (Value::user_iterator UI = Arg.user_begin(), UE = Arg.user_end();
       UI != UE; ++UI) {
    Instruction *User = dyn_cast<Instruction>(*UI);
    if (!User)
      continue;

    // Loads and stores are fine.
    if (isa<LoadInst>(User) || isa<StoreInst>(User))
      continue;

    // GEPs are fine.
    if (isa<GetElementPtrInst>(User))
      continue;

    // Bitcasts are fine.
    if (isa<BitCastInst>(User))
      continue;

    // PHI nodes - check if the PHI is used in a way that preserves noalias.
    if (isa<PHINode>(User))
      continue;

    // Calls - might alias through the call.
    if (isa<CallInst>(User) || isa<InvokeInst>(User))
      return false;

    // Any other use is suspicious.
    return false;
  }

  return true;
}

/// Infer the `nonnull` attribute for a function argument.
/// An argument is nonnull if the function would immediately cause undefined
/// behavior if it were null (e.g., it's loaded from or stored to without a
/// null check).
static bool canBeNonNull(Argument &Arg) {
  if (!Arg.getType()->isPointerTy())
    return false;

  // Check if the argument is used in a comparison against null.
  // If so, it might be null, so we can't mark it nonnull.
  if (isUsedInComparison(&Arg))
    return false;

  // Check all uses.
  for (Value::user_iterator UI = Arg.user_begin(), UE = Arg.user_end();
       UI != UE; ++UI) {
    Instruction *User = dyn_cast<Instruction>(*UI);
    if (!User)
      continue;

    // If loaded from, the pointer must be nonnull.
    if (LoadInst *LI = dyn_cast<LoadInst>(User)) {
      if (LI->getPointerOperand() == &Arg)
        return true;
    }

    // If stored to, the pointer must be nonnull.
    if (StoreInst *SI = dyn_cast<StoreInst>(User)) {
      if (SI->getPointerOperand() == &Arg)
        return true;
    }

    // GEP with this pointer as base - must be nonnull.
    if (GetElementPtrInst *GEP = dyn_cast<GetElementPtrInst>(User)) {
      if (GEP->getPointerOperand() == &Arg)
        return true;
    }
  }

  return false;
}

/// Infer attributes for a function argument and apply them.
bool llvm::inferArgumentAttrFromBody(Argument &Arg) {
  bool Changed = false;

  // Infer noalias.
  if (!Arg.hasNoAliasAttr() && canBeNoAlias(Arg)) {
    {
      AttrBuilder B;
      B.addAttribute(Attribute::NoAlias);
      AttributeSet Attrs = AttributeSet::get(Arg.getContext(),
                                             Arg.getArgNo() + 1, B);
      Arg.addAttr(Attrs);
    }
    ++NumNoAlias;
    Changed = true;
  }

  // Infer nonnull.
  if (!Arg.hasNonNullAttr() && canBeNonNull(Arg)) {
    {
      AttrBuilder B;
      B.addAttribute(Attribute::NonNull);
      AttributeSet Attrs = AttributeSet::get(Arg.getContext(),
                                             Arg.getArgNo() + 1, B);
      Arg.addAttr(Attrs);
    }
    ++NumNonNull;
    Changed = true;
  }

  return Changed;
}

/// Check if a function is `willreturn` - it always returns (doesn't loop
/// infinitely or throw).
bool llvm::functionWillReturn(const Function &F) {
  // Assume functions with side effects might not return.
  for (Function::const_iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::const_iterator I = BB->begin(), IE = BB->end();
         I != IE; ++I) {
      // Unconditional or conditional branches always continue.
      if (isa<BranchInst>(I))
        continue;

      // Return instructions always return.
      if (isa<ReturnInst>(I))
        continue;

      // Unreachable is fine.
      if (isa<UnreachableInst>(I))
        continue;

      // Switch instructions always continue.
      if (isa<SwitchInst>(I))
        continue;

      // Indirect branches might not continue.
      if (isa<IndirectBrInst>(I))
        return false;

      // Invoke instructions might unwind.
      if (isa<InvokeInst>(I))
        return false;
    }
  }

  return true;
}

/// Determine the set of functions that are always called from this function.
void llvm::getDirectCallees(const Function &F,
                            SmallPtrSetImpl<Function *> &Callees) {
  for (Function::const_iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::const_iterator I = BB->begin(), IE = BB->end();
         I != IE; ++I) {
      if (const CallInst *CI = dyn_cast<CallInst>(I)) {
        if (Function *Callee = CI->getCalledFunction())
          Callees.insert(Callee);
      }
    }
  }
}
