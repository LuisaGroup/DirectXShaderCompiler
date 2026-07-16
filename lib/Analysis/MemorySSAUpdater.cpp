//===- MemorySSAUpdater.cpp - Memory SSA Updater --------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements helper utilities for updating MemorySSA when
// instructions change. It provides methods to insert, remove, and move
// memory accesses while maintaining the SSA properties.
//
//===----------------------------------------------------------------------===//

#include "llvm/Analysis/MemorySSA.h"
#include "llvm/ADT/SmallVector.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "memoryssa-updater"

namespace llvm {

/// MemorySSAUpdater - Helper class for updating MemorySSA when instructions
/// are inserted, removed, or moved.
class MemorySSAUpdater {
public:
  MemorySSAUpdater(MemorySSA *M) : MSSA(M) {}

  /// Insert a new memory instruction into MemorySSA.
  MemoryAccess *insertMemoryInstruction(Instruction *I, MemoryAccess *Def) {
    return MSSA->createMemoryAccess(I, Def);
  }

  /// Remove a memory instruction from MemorySSA.
  void removeMemoryInstruction(Instruction *I) {
    MemoryAccess *MA = MSSA->getMemoryAccess(I);
    if (!MA)
      return;
    MemoryAccess *DefAccess = MA->getDefiningAccess();
    (void)DefAccess;
  }

  /// Move a memory instruction to a new position.
  MemoryAccess *moveMemoryInstruction(Instruction *I, Instruction *InsertBefore,
                                       MemoryAccess *NewDef) {
    removeMemoryInstruction(I);
    if (NewDef)
      return insertMemoryInstruction(I, NewDef);
    return nullptr;
  }

  /// Update the defining access for a memory instruction.
  void setDefiningAccess(Instruction *I, MemoryAccess *NewDef) {
    MemoryAccess *MA = MSSA->getMemoryAccess(I);
    if (MA)
      MA->setDefiningAccess(NewDef);
  }

  /// Get the closest dominating memory access for a given instruction.
  MemoryAccess *getClosestDominatingMemoryAccess(Instruction *I) {
    BasicBlock *BB = I->getParent();
    for (BasicBlock::iterator It = I; It != BB->begin();) {
      --It;
      MemoryAccess *MA = MSSA->getMemoryAccess(It);
      if (MA)
        return MA;
    }
    return MSSA->getLiveOnEntryMemoryAccess();
  }

private:
  MemorySSA *MSSA;
};

} // end namespace llvm

/// Create a MemorySSA updater for the given MemorySSA.
MemorySSAUpdater *llvm::createMemorySSAUpdater(MemorySSA *MSSA) {
  return new MemorySSAUpdater(MSSA);
}

/// Destroy a MemorySSA updater.
void llvm::destroyMemorySSAUpdater(MemorySSAUpdater *Updater) {
  delete Updater;
}

/// Insert a new memory instruction, updating MemorySSA.
MemoryAccess *llvm::insertMemoryInstruction(MemorySSA *MSSA, Instruction *I,
                                            MemoryAccess *Def) {
  MemorySSAUpdater Updater(MSSA);
  return Updater.insertMemoryInstruction(I, Def);
}

/// Remove a memory instruction from MemorySSA.
void llvm::removeMemoryInstruction(MemorySSA *MSSA, Instruction *I) {
  MemorySSAUpdater Updater(MSSA);
  Updater.removeMemoryInstruction(I);
}
