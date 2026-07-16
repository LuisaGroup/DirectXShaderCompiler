//===- LowerConstantIntrinsics.cpp - Lower Constant Intrinsics ------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass lowers @llvm.objectsize intrinsic. It replaces the intrinsic with
// a constant result when the operand is known at compile time.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/IntrinsicInst.h"
#include "llvm/IR/Intrinsics.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Operator.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "lower-constant-intrinsics"

STATISTIC(NumObjectSize, "Number of @llvm.objectsize calls lowered");

namespace {
  class LowerConstantIntrinsics : public FunctionPass {
  public:
    static char ID;
    LowerConstantIntrinsics() : FunctionPass(ID) {
      initializeLowerConstantIntrinsicsPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.setPreservesCFG();
    }

  private:
    bool lowerObjectSize(IntrinsicInst *II);
  };
}

char LowerConstantIntrinsics::ID = 0;
INITIALIZE_PASS_BEGIN(LowerConstantIntrinsics, "lower-constant-intrinsics",
                      "Lower constant intrinsics", false, false)
INITIALIZE_PASS_END(LowerConstantIntrinsics, "lower-constant-intrinsics",
                    "Lower constant intrinsics", false, false)

FunctionPass *llvm::createLowerConstantIntrinsicsPass() {
  return new LowerConstantIntrinsics();
}

/// Lower @llvm.objectsize intrinsic.
/// @llvm.objectsize.i64(p, type) returns the size of the object pointed to by
/// p, or 0/-1 if unknown (depending on type).
bool LowerConstantIntrinsics::lowerObjectSize(IntrinsicInst *II) {
  const DataLayout &DL = II->getModule()->getDataLayout();
  Value *Ptr = II->getArgOperand(0);

  // getArgOperand(1) is the "type" (0=min, 1=max) as i1.
  // Use dyn_cast for safety; if not ConstantInt, treat as min (0).
  bool MaxType = false;
  if (ConstantInt *CI = dyn_cast<ConstantInt>(II->getArgOperand(1)))
    MaxType = CI->isZero() ? false : true;

  // If the pointer is to a global variable with known size.
  if (GlobalVariable *GV = dyn_cast<GlobalVariable>(Ptr->stripPointerCasts())) {
    Type *ElemTy = GV->getType()->getElementType();
    if (ElemTy->isSized()) {
      uint64_t Size = DL.getTypeAllocSize(ElemTy);
      Constant *C = ConstantInt::get(II->getType(), Size);
      II->replaceAllUsesWith(C);
      II->eraseFromParent();
      ++NumObjectSize;
      return true;
    }
  }

  // If the pointer is from an alloca, we know the size.
  if (AllocaInst *AI = dyn_cast<AllocaInst>(Ptr->stripPointerCasts())) {
    Type *AllocTy = AI->getAllocatedType();
    if (AllocTy->isSized()) {
      uint64_t Size = DL.getTypeAllocSize(AllocTy);
      Constant *C = ConstantInt::get(II->getType(), Size);
      II->replaceAllUsesWith(C);
      II->eraseFromParent();
      ++NumObjectSize;
      return true;
    }
  }

  // For other cases, we can't determine the size.
  // Return the "unknown" value: 0 for min, -1 for max.
  if (!MaxType) {
    // Min type: return 0 for unknown.
    Constant *C = ConstantInt::get(II->getType(), 0);
    II->replaceAllUsesWith(C);
    II->eraseFromParent();
    ++NumObjectSize;
    return true;
  }

  return false;
}

bool LowerConstantIntrinsics::runOnFunction(Function &F) {
  bool Changed = false;

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE;) {
      Instruction *Inst = I++;
      IntrinsicInst *II = dyn_cast<IntrinsicInst>(Inst);
      if (!II)
        continue;

      // Only handle @llvm.objectsize.
      if (II->getIntrinsicID() == Intrinsic::objectsize)
        Changed |= lowerObjectSize(II);
    }
  }

  return Changed;
}
