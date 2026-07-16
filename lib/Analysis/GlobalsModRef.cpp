//===- GlobalsModRef.cpp - Simple Globals-Based Mod/Ref Analysis ----------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a simple mod/ref analysis based on global variables.
// It tracks how globals are used (read vs. written) and checks aliasing
// properties for global variables.
//
//===----------------------------------------------------------------------===//

#include "llvm/Analysis/GlobalsModRef.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Constants.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/GlobalVariable.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "globalsmodref"

STATISTIC(NumGlobalsTracked, "Number of globals tracked");

char GlobalsModRef::ID = 0;

INITIALIZE_PASS_BEGIN(GlobalsModRef, "globalsmodref",
                      "Simple Globals Mod/Ref Analysis", false, true)
INITIALIZE_PASS_END(GlobalsModRef, "globalsmodref",
                    "Simple Globals Mod/Ref Analysis", false, true)

GlobalsModRef::GlobalsModRef() : ImmutablePass(ID) {
  initializeGlobalsModRefPass(*PassRegistry::getPassRegistry());
}

bool GlobalsModRef::runOnModule(Module &M) {
  for (Module::global_iterator I = M.global_begin(), E = M.global_end();
       I != E; ++I) {
    analyzeGlobal(*I);
  }
  return false;
}

void GlobalsModRef::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.setPreservesAll();
}

GlobalsModRef::GlobalInfo
GlobalsModRef::getGlobalInfo(const GlobalVariable &GV) const {
  DenseMap<const GlobalVariable *, GlobalInfo>::const_iterator It =
      Globals.find(&GV);
  if (It != Globals.end())
    return It->second;
  GlobalInfo Info = {false, false, false};
  return Info;
}

void GlobalsModRef::analyzeGlobal(GlobalVariable &GV) {
  if (GV.isConstant()) {
    GlobalInfo Info = {true, false, true};
    Globals[&GV] = Info;
    ++NumGlobalsTracked;
    return;
  }

  GlobalInfo Info = {false, false, false};

  for (Value::user_iterator UI = GV.user_begin(), UE = GV.user_end();
       UI != UE; ++UI) {
    if (Instruction *I = dyn_cast<Instruction>(*UI)) {
      if (LoadInst *LI = dyn_cast<LoadInst>(I)) {
        if (LI->getPointerOperand() == &GV)
          Info.IsRead = true;
      } else if (StoreInst *SI = dyn_cast<StoreInst>(I)) {
        if (SI->getPointerOperand() == &GV)
          Info.IsWritten = true;
      } else if (GetElementPtrInst *GEP = dyn_cast<GetElementPtrInst>(I)) {
        Info.IsRead = true;
        Info.IsWritten = true;
      } else {
        Info.IsRead = true;
        Info.IsWritten = true;
      }
    } else if (ConstantExpr *CE = dyn_cast<ConstantExpr>(*UI)) {
      Info.IsRead = true;
      Info.IsWritten = true;
    }
  }

  Globals[&GV] = Info;
  ++NumGlobalsTracked;
}

GlobalVariable *GlobalsModRef::getUnderlyingGlobal(Value *V) {
  V = V->stripPointerCasts();
  return dyn_cast<GlobalVariable>(V);
}

bool GlobalsModRef::onlyReadsGlobals(Instruction *I) {
  if (LoadInst *LI = dyn_cast<LoadInst>(I)) {
    GlobalVariable *GV = getUnderlyingGlobal(LI->getPointerOperand());
    if (GV && Globals.count(GV)) {
      return Globals[GV].IsRead && !Globals[GV].IsWritten;
    }
  }
  return false;
}

bool GlobalsModRef::functionOnlyReadsGlobals(Function &F) {
  for (Function::iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    for (BasicBlock::iterator I = BB->begin(), IE = BB->end(); I != IE; ++I) {
      if (StoreInst *SI = dyn_cast<StoreInst>(I)) {
        GlobalVariable *GV = getUnderlyingGlobal(SI->getPointerOperand());
        if (GV && Globals.count(GV))
          return false;
      }
    }
  }
  return true;
}
