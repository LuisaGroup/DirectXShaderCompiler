//===- CycleAnalysis.h - Cycle Analysis -------------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file declares the CycleAnalysis pass, which provides cycle information
// as a simplified wrapper around LoopInfo.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_ANALYSIS_CYCLEANALYSIS_H
#define LLVM_ANALYSIS_CYCLEANALYSIS_H

#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"

namespace llvm {

class DominatorTree;
class LoopInfo;

class CycleAnalysis : public FunctionPass {
public:
  static char ID;

  CycleAnalysis() : FunctionPass(ID), LI(nullptr), DT(nullptr) {
    initializeCycleAnalysisPass(*PassRegistry::getPassRegistry());
  }

  bool runOnFunction(Function &F) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override;

  void print(raw_ostream &OS, const Module *M = nullptr) const override;

  LoopInfo *getLoopInfo() const { return LI; }

private:
  LoopInfo *LI;
  DominatorTree *DT;
};

} // end namespace llvm

#endif
