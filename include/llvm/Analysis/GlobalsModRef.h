//===- GlobalsModRef.h - Simple Globals Mod/Ref Analysis --------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file declares a simple mod/ref analysis based on global variables.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_ANALYSIS_GLOBALSMODREF_H
#define LLVM_ANALYSIS_GLOBALSMODREF_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"

namespace llvm {

class GlobalVariable;
class Instruction;
class Value;

class GlobalsModRef : public ImmutablePass {
public:
  static char ID;

  GlobalsModRef();

  bool runOnModule(Module &M) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override;

  /// Information about a global variable.
  struct GlobalInfo {
    bool IsRead;
    bool IsWritten;
    bool IsConstant;
  };

  /// Get the information about a specific global.
  GlobalInfo getGlobalInfo(const GlobalVariable &GV) const;

  /// Analyze a global variable.
  void analyzeGlobal(GlobalVariable &GV);

  /// Check if a value refers to a global variable.
  GlobalVariable *getUnderlyingGlobal(Value *V);

  /// Check if an instruction only reads from globals.
  bool onlyReadsGlobals(Instruction *I);

  /// Check if a function only reads from globals.
  bool functionOnlyReadsGlobals(Function &F);

private:
  DenseMap<const GlobalVariable *, GlobalInfo> Globals;
};

} // end namespace llvm

#endif
