//===- MemorySSA.cpp - Memory SSA Construction ----------------------------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements Memory SSA construction. It tracks memory state through
// basic blocks using phi nodes at join points and def/use chains for memory
// operations.
//
//===----------------------------------------------------------------------===//

#include "llvm/Analysis/MemorySSA.h"
#include "llvm/ADT/DepthFirstIterator.h"
#include "llvm/ADT/PostOrderIterator.h"
#include "llvm/ADT/Statistic.h"
#include "llvm/IR/BasicBlock.h"
#include "llvm/IR/Dominators.h"
#include "llvm/IR/Function.h"
#include "llvm/IR/CFG.h"
#include "llvm/IR/Instructions.h"
#include "llvm/IR/Module.h"
#include "llvm/Pass.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
using namespace llvm;

#define DEBUG_TYPE "memoryssa"

STATISTIC(NumMemoryPhis, "Number of Memory PHI nodes created");
STATISTIC(NumMemoryDefs, "Number of Memory defs created");

char MemorySSAWrapperPass::ID = 0;

INITIALIZE_PASS_BEGIN(MemorySSAWrapperPass, "memoryssa",
                      "Memory SSA", false, true)
INITIALIZE_PASS_DEPENDENCY(DominatorTreeWrapperPass)
INITIALIZE_PASS_END(MemorySSAWrapperPass, "memoryssa",
                    "Memory SSA", false, true)

//===----------------------------------------------------------------------===//
// MemorySSA implementation
//===----------------------------------------------------------------------===//

MemorySSA::MemorySSA(Function &Fn, DominatorTree &DomTree)
    : F(Fn), DT(DomTree), LiveOnEntry(nullptr) {
  // Create the live-on-entry memory access (represents memory before any
  // instructions in the function).
  LiveOnEntry = new MemoryAccess(MemoryAccess::Def, nullptr, nullptr);
  buildMemorySSA();
}

MemorySSA::~MemorySSA() {
  delete LiveOnEntry;
  for (DenseMap<const Instruction *, MemoryAccess *>::iterator I = AccessMap.begin(),
        E = AccessMap.end(); I != E; ++I) {
    delete I->second;
  }
  AccessMap.clear();

  // Clean up phi nodes.
  for (DenseMap<const BasicBlock *, MemoryAccessPhi *>::iterator
           I = BlockPhis.begin(),
           E = BlockPhis.end();
       I != E; ++I) {
    delete I->second;
  }
  BlockPhis.clear();
}

MemoryAccess *MemorySSA::getMemoryAccess(const Instruction *I) const {
  DenseMap<const Instruction *, MemoryAccess *>::const_iterator It =
      AccessMap.find(I);
  if (It != AccessMap.end())
    return It->second;
  return nullptr;
}

MemoryAccess *MemorySSA::createMemoryAccess(Instruction *I, MemoryAccess *Def) {
  MemoryAccess::AccessType Ty;
  if (isa<LoadInst>(I))
    Ty = MemoryAccess::Load;
  else if (isa<StoreInst>(I))
    Ty = MemoryAccess::Store;
  else if (isa<AtomicCmpXchgInst>(I) || isa<AtomicRMWInst>(I))
    Ty = MemoryAccess::Def;
  else if (isa<CallInst>(I))
    Ty = MemoryAccess::Call;
  else
    Ty = MemoryAccess::Def;

  MemoryAccess *MA = new MemoryAccess(Ty, I, Def);
  AccessMap[I] = MA;
  ++NumMemoryDefs;
  return MA;
}

void MemorySSA::buildMemorySSA() {
  // Walk basic blocks in dominator tree pre-order.
  for (df_iterator<DomTreeNode *> DI = df_begin(DT.getRootNode()),
       DE = df_end(DT.getRootNode()); DI != DE; ++DI) {
    BasicBlock *BB = (*DI)->getBlock();

    // Determine the defining access for this block.
    MemoryAccess *BlockDefAccess = LiveOnEntry;
    DomTreeNode *IDom = (*DI)->getIDom();
    if (IDom) {
      BasicBlock *IDomBB = IDom->getBlock();
      DenseMap<const BasicBlock *, MemoryAccess *>::iterator It =
          BlockDefs.find(IDomBB);
      if (It != BlockDefs.end())
        BlockDefAccess = It->second;
    }

    // Check if we need a phi node (multiple predecessors).
    unsigned NumPreds = 0;
    for (pred_iterator PI = pred_begin(BB), PE = pred_end(BB); PI != PE; ++PI)
      ++NumPreds;

    if (NumPreds > 1) {
      // Create a memory phi node.
      MemoryAccessPhi *Phi = new MemoryAccessPhi(BB);
      BlockPhis[BB] = Phi;
      ++NumMemoryPhis;

      // Add incoming values from predecessors.
      for (pred_iterator PI = pred_begin(BB), PE = pred_end(BB); PI != PE;
           ++PI) {
        BasicBlock *Pred = *PI;
        MemoryAccess *PredAccess = LiveOnEntry;
        DenseMap<const BasicBlock *, MemoryAccess *>::iterator PredIt =
            BlockDefs.find(Pred);
        if (PredIt != BlockDefs.end())
          PredAccess = PredIt->second;
        Phi->addIncoming(Pred, PredAccess);
      }

      BlockDefAccess = Phi;
    }

    // Process instructions in this block.
    for (BasicBlock::iterator I = BB->begin(), E = BB->end(); I != E; ++I) {
      if (I->mayReadFromMemory() || I->mayWriteToMemory()) {
        BlockDefAccess = createMemoryAccess(I, BlockDefAccess);
      }
    }

    // Store the last memory access in this block.
    BlockDefs[BB] = BlockDefAccess;
  }
}

void MemorySSA::print(raw_ostream &OS) const {
  OS << "MemorySSA for function: " << F.getName() << "\n";

  for (Function::const_iterator BB = F.begin(), BE = F.end(); BB != BE; ++BB) {
    OS << BB->getName() << ":\n";

    // Print phi nodes.
    DenseMap<const BasicBlock *, MemoryAccessPhi *>::const_iterator PhiIt =
        BlockPhis.find(BB);
    if (PhiIt != BlockPhis.end()) {
      MemoryAccessPhi *Phi = PhiIt->second;
      OS << "  MemoryPhi(" << Phi->getNumIncomingValues() << ")\n";
    }

    // Print memory accesses for instructions.
    for (BasicBlock::const_iterator I = BB->begin(), IE = BB->end(); I != IE;
         ++I) {
      MemoryAccess *MA = nullptr;
      for (DenseMap<const Instruction *, MemoryAccess *>::const_iterator
               AI = AccessMap.begin(),
               AE = AccessMap.end();
           AI != AE; ++AI) {
        if (AI->first == &*I) {
          MA = AI->second;
          break;
        }
      }
      if (MA) {
        OS << "  ";
        switch (MA->getAccessType()) {
        case MemoryAccess::Load:  OS << "MemoryLoad";  break;
        case MemoryAccess::Store: OS << "MemoryStore"; break;
        case MemoryAccess::Def:   OS << "MemoryDef";   break;
        case MemoryAccess::Call:  OS << "MemoryCall";  break;
        default:                  OS << "MemoryAccess"; break;
        }
        OS << " for " << *I << "\n";
      }
    }
  }
}

//===----------------------------------------------------------------------===//
// MemorySSAWrapperPass implementation
//===----------------------------------------------------------------------===//

MemorySSAWrapperPass::~MemorySSAWrapperPass() {
  delete MSSA;
}

bool MemorySSAWrapperPass::runOnFunction(Function &F) {
  releaseMemory();
  DominatorTree &DT = getAnalysis<DominatorTreeWrapperPass>().getDomTree();
  MSSA = new MemorySSA(F, DT);
  return false;
}

void MemorySSAWrapperPass::releaseMemory() {
  delete MSSA;
  MSSA = nullptr;
}
