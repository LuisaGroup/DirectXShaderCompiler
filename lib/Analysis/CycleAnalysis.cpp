//===- CycleAnalysis.cpp - Cycle Analysis Pass ----------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a cycle analysis pass that provides simplified cycle
// information as a wrapper around LoopInfo. It identifies cycles in the
// control flow graph.
//
//===----------------------------------------------------------------------===//

#include "llvm/Analysis/CycleAnalysis.h"
#include "llvm/IR/Dominators.h"
#include "llvm/Analysis/LoopInfo.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "cycle-analysis"

char CycleAnalysis::ID = 0;

INITIALIZE_PASS_BEGIN(CycleAnalysis, "cycle-analysis",
                      "Cycle Analysis", true, true)
INITIALIZE_PASS_DEPENDENCY(LoopInfoWrapperPass)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(CycleAnalysis, "cycle-analysis",
                    "Cycle Analysis", true, true)

bool CycleAnalysis::runOnFunction(Function &F) {
  LI = &getAnalysis<LoopInfoWrapperPass>().getLoopInfo();
  DT = &getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  return false;
}

void CycleAnalysis::getAnalysisUsage(AnalysisUsage &AU) const {
  AU.setPreservesAll();
  AU.addRequired<DominatorTreeWrapperPass>();
  AU.addRequired<LoopInfoWrapperPass>();
}

void CycleAnalysis::print(raw_ostream &OS, const Module *M) const {
  if (!LI)
    return;

  OS << "Cycle Analysis for function";
  if (M && M->size() > 0) {
    // Print function name if we can infer it.
  }
  OS << "\n";

  for (LoopInfo::iterator I = LI->begin(), E = LI->end(); I != E; ++I) {
    Loop *L = *I;
    OS << "  Cycle (Loop) at depth " << L->getLoopDepth()
       << " header: " << L->getHeader()->getName() << "\n";
    OS << "    " << L->getBlocks().size() << " blocks\n";
    OS << "    " << L->getSubLoops().size() << " sub-cycles\n";

    SmallVector<BasicBlock *, 8> ExitBlocks;
    L->getExitBlocks(ExitBlocks);
    OS << "    " << ExitBlocks.size() << " exit blocks\n";
  }
}
