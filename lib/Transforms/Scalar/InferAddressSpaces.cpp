//===- InferAddressSpace.cpp - Infer address spaces -----------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This pass attempts to propagate non-flat address spaces from pointer origins
// through addrspacecast instructions to loads, stores, GEPs and bitcasts.
//
//===----------------------------------------------------------------------===//

#include "llvm/Transforms/Scalar.h"
#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/DataLayout.h"
#include "llvm/IR/DerivedTypes.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instruction.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"

using namespace llvm;

#define DEBUG_TYPE "infer-address-spaces"

STATISTIC(NumInferred, "Number of pointer uses inferred to a specific address space");

namespace {
class InferAddressSpaces : public FunctionPass {
  unsigned FlatAddrSpace;

public:
  static char ID;

  InferAddressSpaces() : FunctionPass(ID), FlatAddrSpace(0) {
    initializeInferAddressSpacesPass(*PassRegistry::getPassRegistry());
  }

  explicit InferAddressSpaces(unsigned AS) : FunctionPass(ID), FlatAddrSpace(AS) {
    initializeInferAddressSpacesPass(*PassRegistry::getPassRegistry());
  }

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.setPreservesCFG();
  }

  bool runOnFunction(Function &F) override {
    if (F.isDeclaration())
      return false;

    bool Changed = false;
    DataLayout DL = F.getParent()->getDataLayout();

    // Walk all instructions, find addrspacecast from non-zero to zero addrspace
    SmallVector<AddrSpaceCastInst *, 16> Casts;
    for (BasicBlock &BB : F) {
      for (Instruction &I : BB) {
        if (auto *ASC = dyn_cast<AddrSpaceCastInst>(&I)) {
          Value *Src = ASC->getOperand(0);
          PointerType *SrcTy = cast<PointerType>(Src->getType());
          PointerType *DstTy = cast<PointerType>(ASC->getType());
          unsigned SrcAS = SrcTy->getAddressSpace();
          unsigned DstAS = DstTy->getAddressSpace();
          if (SrcAS != 0 && DstAS == FlatAddrSpace) {
            Casts.push_back(ASC);
          }
        }
      }
    }

    // For each cast, try to propagate source address space to users
    for (auto *ASC : Casts) {
      Value *Src = ASC->getOperand(0);
      PointerType *SrcTy = cast<PointerType>(Src->getType());
      unsigned SrcAS = SrcTy->getAddressSpace();

      if (SrcAS == FlatAddrSpace)
        continue;

      // Try to replace uses of the cast with the original pointer
      while (!ASC->use_empty()) {
        Use &U = *ASC->use_begin();
        Instruction *UserInst = cast<Instruction>(U.getUser());
        unsigned OpNo = U.getOperandNo();

        if (auto *LI = dyn_cast<LoadInst>(UserInst)) {
          if (LI->getPointerAddressSpace() == SrcAS) {
            LI->setOperand(OpNo, Src);
          } else {
            // Create a new load with the source pointer
            LoadInst *NewLI = new LoadInst(Src, "", LI->isVolatile(), LI->getAlignment(), LI);
            NewLI->setDebugLoc(LI->getDebugLoc());
            LI->replaceAllUsesWith(NewLI);
            LI->eraseFromParent();
          }
          Changed = true;
          NumInferred++;
          continue;
        }

        if (auto *SI = dyn_cast<StoreInst>(UserInst)) {
          StoreInst *NewSI = new StoreInst(SI->getValueOperand(), Src,
                                            SI->isVolatile(), SI->getAlignment(), SI);
          NewSI->setDebugLoc(SI->getDebugLoc());
          SI->eraseFromParent();
          Changed = true;
          NumInferred++;
          continue;
        }

        if (auto *GEP = dyn_cast<GetElementPtrInst>(UserInst)) {
          SmallVector<Value *, 8> Indices(GEP->idx_begin(), GEP->idx_end());
          GetElementPtrInst *NewGEP = GetElementPtrInst::Create(
            GEP->getSourceElementType(), Src, Indices, "", GEP);
          NewGEP->setDebugLoc(GEP->getDebugLoc());
          GEP->replaceAllUsesWith(NewGEP);
          GEP->eraseFromParent();
          Changed = true;
          NumInferred++;
          continue;
        }

        if (auto *BC = dyn_cast<BitCastInst>(UserInst)) {
          PointerType *DstTy = cast<PointerType>(BC->getDestTy());
          PointerType *NewTy = PointerType::get(DstTy->getElementType(), SrcAS);
          BitCastInst *NewBC = new BitCastInst(Src, NewTy, "", BC);
          NewBC->setDebugLoc(BC->getDebugLoc());
          BC->replaceAllUsesWith(NewBC);
          BC->eraseFromParent();
          Changed = true;
          NumInferred++;
          continue;
        }

        // If we can't handle this user, skip
        break;
      }
    }

    return Changed;
  }
};
} // end anonymous namespace

char InferAddressSpaces::ID = 0;

INITIALIZE_PASS(InferAddressSpaces, DEBUG_TYPE, "Infer address spaces",
                false, false)

FunctionPass *llvm::createInferAddressSpacesPass(unsigned AddressSpace) {
  return new InferAddressSpaces(AddressSpace);
}
