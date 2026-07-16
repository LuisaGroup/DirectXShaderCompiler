//===- InferAlignment.cpp - Infer Alignment for Loads/Stores --------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass infers better alignment for loads/stores by tracking alignments
// through pointer arithmetic and known alignments from global variables,
// allocas, and other sources.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/Analysis/ValueTracking.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "infer-alignment"

STATISTIC(NumLoadAlignImproved, "Number of loads with improved alignment");
STATISTIC(NumStoreAlignImproved, "Number of stores with improved alignment");

namespace {
  class InferAlignment : public FunctionPass {
  public:
    static char ID;
    InferAlignment() : FunctionPass(ID) {
      initializeInferAlignmentPass(*PassRegistry::getPassRegistry());
    }

    bool runOnFunction(Function &F) override;

    void getAnalysisUsage(AnalysisUsage &AU) const override {
      AU.setPreservesCFG();
    }

  private:
    unsigned getKnownAlignment(Value *V, const DataLayout &DL);
  };
}

char InferAlignment::ID = 0;
INITIALIZE_PASS_BEGIN(InferAlignment, "infer-alignment",
                      "Infer alignment for loads and stores", false, false)
INITIALIZE_PASS_END(InferAlignment, "infer-alignment",
                    "Infer alignment for loads and stores", false, false)

FunctionPass *llvm::createInferAlignmentPass() {
  return new InferAlignment();
}

/// Recursively compute the known alignment of a pointer value.
unsigned InferAlignment::getKnownAlignment(Value *V, const DataLayout &DL) {
  if (!V)
    return 1;

  // AllocaInst
  if (AllocaInst *AI = dyn_cast<AllocaInst>(V)) {
    unsigned Align = AI->getAlignment();
    if (Align)
      return Align;
    Type *Ty = AI->getAllocatedType();
    return DL.getABITypeAlignment(Ty);
  }

  // GlobalVariable
  if (GlobalVariable *GV = dyn_cast<GlobalVariable>(V)) {
    unsigned Align = GV->getAlignment();
    if (Align)
      return Align;
    Type *Ty = GV->getType()->getElementType();
    return DL.getABITypeAlignment(Ty);
  }

  // GetElementPtrInst - alignment comes from base pointer
  if (GetElementPtrInst *GEP = dyn_cast<GetElementPtrInst>(V)) {
    return getKnownAlignment(GEP->getPointerOperand(), DL);
  }

  // Argument
  if (Argument *Arg = dyn_cast<Argument>(V)) {
    unsigned Align = Arg->getParamAlignment();
    if (Align)
      return Align;
    PointerType *PTy = dyn_cast<PointerType>(Arg->getType());
    if (PTy) {
      Type *ElemTy = PTy->getElementType();
      return DL.getABITypeAlignment(ElemTy);
    }
    return 1;
  }

  // BitCastInst - alignment comes from source
  if (BitCastInst *BCI = dyn_cast<BitCastInst>(V)) {
    return getKnownAlignment(BCI->getOperand(0), DL);
  }

  // AddrSpaceCastInst - alignment comes from source
  if (AddrSpaceCastInst *ASC = dyn_cast<AddrSpaceCastInst>(V)) {
    return getKnownAlignment(ASC->getOperand(0), DL);
  }

  // IntToPtrInst - unknown alignment
  if (isa<IntToPtrInst>(V))
    return 1;

  // ConstantExpr
  if (ConstantExpr *CE = dyn_cast<ConstantExpr>(V)) {
    if (CE->getOpcode() == Instruction::IntToPtr)
      return 1;
    if (CE->getOpcode() == Instruction::GetElementPtr)
      return getKnownAlignment(CE->getOperand(0), DL);
  }

  // For all other values, try LLVM's built-in getKnownAlignment.
  return 1;
}

bool InferAlignment::runOnFunction(Function &F) {
  const DataLayout &DL = F.getParent()->getDataLayout();
  bool Changed = false;

  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      if (LoadInst *LI = dyn_cast<LoadInst>(I)) {
        unsigned Known = getKnownAlignment(LI->getPointerOperand(), DL);
        if (Known > LI->getAlignment()) {
          LI->setAlignment(Known);
          ++NumLoadAlignImproved;
          Changed = true;
        }
      } else if (StoreInst *SI = dyn_cast<StoreInst>(I)) {
        unsigned Known = getKnownAlignment(SI->getPointerOperand(), DL);
        if (Known > SI->getAlignment()) {
          SI->setAlignment(Known);
          ++NumStoreAlignImproved;
          Changed = true;
        }
      }
    }
  }

  return Changed;
}
