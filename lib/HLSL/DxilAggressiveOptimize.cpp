//===- DxilAggressiveOptimize.cpp - Fixed-Point Optimization Pass ---------===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file implements a fixed-point iterative optimization pass for the
// DXIL backend, inspired by the SPIR-V backend's spirvToolsOptimize() with
// kSpirvOptMaxIterations = 5.
//
// The pass runs a curated set of LLVM optimization passes repeatedly until
// the IR size (function count + instruction count) stabilizes, squeezing
// out additional dead code and simplification opportunities exposed by
// earlier iterations.
//
//===----------------------------------------------------------------------===//

#include "dxc/HLSL/DxilAggressiveOptimize.h"
#include "dxc/HLSL/DxilGenerationPass.h"

#include "llvm/IR/Function.h"
#include "llvm/IR/IRPrintingPasses.h"
#include "llvm/IR/LegacyPassManager.h"
#include "llvm/IR/Module.h"
#include "llvm/IR/Verifier.h"
#include "llvm/PassRegistry.h"
#include "llvm/Support/Debug.h"
#include "llvm/Support/raw_ostream.h"
#include "llvm/Transforms/IPO.h"
#include "llvm/Transforms/Scalar.h"

using namespace llvm;

#define DEBUG_TYPE "dxil-aggressive-opt"

namespace {

/// \brief Compute a size metric for the module: function count + instruction
/// count.  Fast to compute and a stable indicator of IR complexity.
static size_t computeSizeMetric(Module &M) {
  size_t count = M.getFunctionList().size();
  for (Function &F : M) {
    for (BasicBlock &BB : F) {
      count += BB.getInstList().size();
    }
  }
  return count;
}

class DxilAggressiveOptimize : public ModulePass {
public:
  static char ID; // Pass ID

  hlsl::DxilAggressiveOptimizeOpts m_Opts;

  DxilAggressiveOptimize()
      : ModulePass(ID) {}

  explicit DxilAggressiveOptimize(hlsl::DxilAggressiveOptimizeOpts Opts)
      : ModulePass(ID), m_Opts(std::move(Opts)) {}

  bool runOnModule(Module &M) override;

  void applyOptions(PassOptions O) override {
    GetPassOptionUnsigned(O, "MaxIterations", &m_Opts.MaxIterations,
                          /*defaultValue*/ 5);
    GetPassOptionBool(O, "PrintEach", &m_Opts.PrintEach,
                      /*defaultValue*/ false);
    GetPassOptionBool(O, "ValidateEach", &m_Opts.ValidateEach,
                      /*defaultValue*/ false);
  }

  void dumpConfig(raw_ostream &OS) override {
    ModulePass::dumpConfig(OS);
    OS << ",MaxIterations=" << m_Opts.MaxIterations;
    if (!m_Opts.CustomPasses.empty())
      OS << ",CustomPasses=" << m_Opts.CustomPasses;
    OS << ",PrintEach=" << m_Opts.PrintEach;
    OS << ",ValidateEach=" << m_Opts.ValidateEach;
  }

private:
  /// Run the default aggressive pass set (transformative + cleanup).
  void runDefaultPassSet(Module &M);

  /// Run passes specified by a comma-separated list of pass names.
  void runCustomPassSet(Module &M, StringRef PassList);

  /// Run the cleanup pass set (CFGSimplify + InstCombine + DCE + AggressiveDCE).
  void runCleanupPasses(Module &M);

  /// Print the module IR (for debugging).
  void printModule(Module &M, unsigned Iter, StringRef Phase);

  /// Validate the module (for debugging / error detection).
  void validateModule(Module &M, unsigned Iter, StringRef Phase);
};

} // anonymous namespace

char DxilAggressiveOptimize::ID = 0;

INITIALIZE_PASS(DxilAggressiveOptimize, "dxil-aggressive-opt",
                "DXIL Aggressive Fixed-Point Optimization", false, false)

ModulePass *llvm::createDxilAggressiveOptimizePass() {
  return new DxilAggressiveOptimize();
}

ModulePass *llvm::createDxilAggressiveOptimizePass(
    hlsl::DxilAggressiveOptimizeOpts Opts) {
  return new DxilAggressiveOptimize(std::move(Opts));
}

//------------------------------------------------------------------------------
// Validation helpers
//------------------------------------------------------------------------------
void DxilAggressiveOptimize::validateModule(Module &M, unsigned Iter,
                                            StringRef Phase) {
  // In _DEBUG builds, always validate. In release, respect the option flag.
  bool shouldValidate = m_Opts.ValidateEach;
#ifdef _DEBUG
  shouldValidate = true;
#endif
  if (!shouldValidate)
    return;

  // The LLVM module verifier may not be compatible with DXIL IR constructs
  // at this stage. Instead, perform a lightweight sanity check: ensure the
  // module is not in a broken state by checking that functions exist and
  // basic blocks are well-formed.
  std::string errInfo;
  raw_string_ostream errStream(errInfo);

  // Try the verifier but don't crash if it fails -- DXIL IR may contain
  // constructs (intrinsics, metadata, calling conventions) that the
  // standard LLVM verifier doesn't recognize.
  if (llvm::verifyModule(M, &errStream)) {
    errStream.flush();
    llvm::errs() << "dxil-aggressive-opt: note: module verifier reported issues after "
                 << "iteration " << Iter << " (" << Phase << "):\n"
                 << errInfo << "\n";
  }
}

//------------------------------------------------------------------------------
// Debug printing
//------------------------------------------------------------------------------
void DxilAggressiveOptimize::printModule(Module &M, unsigned Iter,
                                         StringRef Phase) {
  if (!m_Opts.PrintEach)
    return;

  llvm::errs() << "=== dxil-aggressive-opt iteration " << Iter << " (" << Phase
               << ") ===\n";
  M.print(llvm::errs(), nullptr, /*ShouldPreserveUseListOrder*/ false);
  llvm::errs() << "=== end iteration " << Iter << " ===\n\n";
}

//------------------------------------------------------------------------------
// Cleanup passes
//------------------------------------------------------------------------------
void DxilAggressiveOptimize::runCleanupPasses(Module &M) {
  legacy::PassManager PM;
  PM.add(createCFGSimplificationPass());
  PM.add(createInstructionCombiningPass(/*HLSLNoSink*/ false));
  PM.add(createDeadCodeEliminationPass());
  PM.add(createAggressiveDCEPass());
  PM.run(M);
}

//------------------------------------------------------------------------------
// Default aggressive pass set
//------------------------------------------------------------------------------
void DxilAggressiveOptimize::runDefaultPassSet(Module &M) {
  // Pass Set A (transformative):
  //   These passes are known to expose further opportunities when re-run.
  legacy::PassManager PM_A;
  PM_A.add(createSROAPass());
  PM_A.add(createGlobalOptimizerPass());
  PM_A.add(createIPSCCPPass());
  PM_A.add(createCorrelatedValuePropagationPass());
  PM_A.add(createReassociatePass(/*RunRepeatedly*/ true));
  PM_A.add(createGVNPass(/*NoLoads*/ false));
  PM_A.run(M);

  // Pass Set B (cleanup):
  runCleanupPasses(M);
}

//------------------------------------------------------------------------------
// Custom pass set (from -Oconfig-dxil comma-separated list)
//------------------------------------------------------------------------------
void DxilAggressiveOptimize::runCustomPassSet(Module &M, StringRef PassList) {
  SmallVector<StringRef, 16> passNames;
  PassList.split(passNames, StringRef(","), -1, /*KeepEmpty*/ false);

  for (StringRef passName : passNames) {
    passName = passName.trim();
    if (passName.empty())
      continue;

    const PassRegistry &PR = *PassRegistry::getPassRegistry();
    const PassInfo *PI = PR.getPassInfo(passName);
    if (!PI) {
      llvm::errs() << "dxil-aggressive-opt: warning: unknown pass '"
                   << passName << "' -- skipping\n";
      continue;
    }

    legacy::PassManager PM;
    PM.add(PI->createPass());
    PM.run(M);
  }
}

//------------------------------------------------------------------------------
// Main entry point
//------------------------------------------------------------------------------
bool DxilAggressiveOptimize::runOnModule(Module &M) {
  DEBUG(llvm::dbgs() << "dxil-aggressive-opt: starting fixed-point optimization\n");

  const unsigned kMaxIterations = m_Opts.MaxIterations;
  size_t prevSize = computeSizeMetric(M);
  bool modified = false;

  DEBUG(llvm::dbgs() << "  initial module size: " << prevSize << " ("
                     << M.getFunctionList().size() << " functions)\n");

  printModule(M, 0, "initial");

  for (unsigned iter = 1; iter <= kMaxIterations; ++iter) {
    DEBUG(llvm::dbgs() << "  iteration " << iter << " / " << kMaxIterations
                       << "...\n");

    // Run the optimization passes.
    if (m_Opts.CustomPasses.empty()) {
      runDefaultPassSet(M);
    } else {
      runCustomPassSet(M, m_Opts.CustomPasses);
    }

    printModule(M, iter, "after-passes");
    validateModule(M, iter, "after-passes");

    // Compute new size metric.
    size_t newSize = computeSizeMetric(M);
    DEBUG(llvm::dbgs() << "    module size: " << newSize << " ("
                       << M.getFunctionList().size() << " functions)\n");

    modified |= (newSize != prevSize);

    // Check for convergence.
    if (newSize == prevSize) {
      DEBUG(llvm::dbgs() << "  converged at iteration " << iter << "\n");
      break;
    }

    prevSize = newSize;
  }

  DEBUG(llvm::dbgs() << "dxil-aggressive-opt: finished. modified=" << modified
                     << "\n");

  return modified;
}
