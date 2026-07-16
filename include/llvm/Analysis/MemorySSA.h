//===- MemorySSA.h - Memory SSA Construction -------------------*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file declares the MemorySSA analysis pass, which builds a Memory SSA
// form for tracking memory state across basic blocks, and helper utilities
// for updating it.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_ANALYSIS_MEMORYSSA_H
#define LLVM_ANALYSIS_MEMORYSSA_H

#include "llvm/ADT/DenseMap.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"

namespace llvm {
class MemoryAccessPhi;
class MemorySSAUpdater;

/// Represents a memory access (load, store, or memory intrinsic).
class MemoryAccess {
public:
  enum AccessType { Load, Store, Def, Phi, Call };

private:
  AccessType Type;
  Instruction *I;
  MemoryAccess *DefiningAccess;

public:
  MemoryAccess(AccessType Ty, Instruction *Inst, MemoryAccess *Def)
      : Type(Ty), I(Inst), DefiningAccess(Def) {}

  AccessType getAccessType() const { return Type; }
  Instruction *getInstruction() const { return I; }
  MemoryAccess *getDefiningAccess() const { return DefiningAccess; }
  void setDefiningAccess(MemoryAccess *MA) { DefiningAccess = MA; }
};

/// MemoryAccessPhi - Phi node for memory state at join points.
class MemoryAccessPhi : public MemoryAccess {
private:
  BasicBlock *BB;
  DenseMap<BasicBlock *, MemoryAccess *> IncomingValues;

public:
  MemoryAccessPhi(BasicBlock *Block)
      : MemoryAccess(Phi, nullptr, nullptr), BB(Block) {}

  void addIncoming(BasicBlock *Pred, MemoryAccess *MA) {
    IncomingValues[Pred] = MA;
  }

  MemoryAccess *getIncomingValueForBlock(BasicBlock *Pred) {
    DenseMap<BasicBlock *, MemoryAccess *>::iterator It =
        IncomingValues.find(Pred);
    if (It != IncomingValues.end())
      return It->second;
    return nullptr;
  }

  unsigned getNumIncomingValues() const { return IncomingValues.size(); }

  BasicBlock *getBlock() const { return BB; }
};

/// MemorySSA - The Memory SSA analysis result.
class MemorySSA {
public:
  MemorySSA(Function &F, DominatorTree &DT);
  ~MemorySSA();

  MemoryAccess *getMemoryAccess(const Instruction *I) const;
  MemoryAccess *getLiveOnEntryMemoryAccess() const { return LiveOnEntry; }

  MemoryAccess *createMemoryAccess(Instruction *I, MemoryAccess *Def);

  void print(raw_ostream &OS) const;

private:
  Function &F;
  DominatorTree &DT;
  MemoryAccess *LiveOnEntry;
  DenseMap<const Instruction *, MemoryAccess *> AccessMap;
  DenseMap<const BasicBlock *, MemoryAccessPhi *> BlockPhis;
  DenseMap<const BasicBlock *, MemoryAccess *> BlockDefs;

  void buildMemorySSA();
};

/// MemorySSAWrapperPass - Analysis pass wrapper for MemorySSA.
class MemorySSAWrapperPass : public FunctionPass {
public:
  static char ID;

  MemorySSAWrapperPass() : FunctionPass(ID), MSSA(nullptr) {
    initializeMemorySSAWrapperPassPass(*PassRegistry::getPassRegistry());
  }

  ~MemorySSAWrapperPass() override;

  bool runOnFunction(Function &F) override;

  void getAnalysisUsage(AnalysisUsage &AU) const override {
    AU.setPreservesAll();
    AU.addRequired<DominatorTreeWrapperPass>();
  }

  MemorySSA &getMSSA() const { return *MSSA; }

  void releaseMemory() override;

private:
  MemorySSA *MSSA;
};

// Helper functions for external use.
MemorySSAUpdater *createMemorySSAUpdater(MemorySSA *MSSA);
void destroyMemorySSAUpdater(MemorySSAUpdater *Updater);
MemoryAccess *insertMemoryInstruction(MemorySSA *MSSA, Instruction *I,
                                      MemoryAccess *Def);
void removeMemoryInstruction(MemorySSA *MSSA, Instruction *I);

} // end namespace llvm

#endif
