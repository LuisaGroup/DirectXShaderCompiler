///////////////////////////////////////////////////////////////////////////////
//                                                                           //
// DxilAggressiveOptimize.h                                                  //
// Copyright (C) Microsoft Corporation. All rights reserved.                 //
// This file is distributed under the University of Illinois Open Source     //
// License. See LICENSE.TXT for details.                                     //
//                                                                           //
// Fixed-point iterative optimization pass for DXIL.                         //
//                                                                           //
///////////////////////////////////////////////////////////////////////////////

#pragma once

#include <string>
#include <vector>

namespace llvm {
class Module;
class ModulePass;
class PassRegistry;
class StringRef;
} // namespace llvm

namespace hlsl {

/// \brief Options controlling the aggressive fixed-point optimization pass.
struct DxilAggressiveOptimizeOpts {
  /// Maximum number of fixed-point iterations (default: 5).
  unsigned MaxIterations = 5;

  /// Comma-separated list of pass names to override the default pass set.
  std::string CustomPasses;

  /// Print IR after each iteration (for debugging).
  bool PrintEach = false;

  /// Run verifyModule() / verifyFunction() after each iteration.
  bool ValidateEach = false;
};

} // namespace hlsl

namespace llvm {

/// \brief Create and return a pass that runs a fixed-point optimization loop
/// over a curated set of LLVM passes until the IR size converges or the
/// maximum iteration count is reached.
///
/// The pass is gated on OptLevel > 1 and integrates into the DXIL backend
/// pipeline in PassManagerBuilder.
ModulePass *createDxilAggressiveOptimizePass();

/// \brief Create a pass with custom options.
ModulePass *createDxilAggressiveOptimizePass(
    hlsl::DxilAggressiveOptimizeOpts Opts);

void initializeDxilAggressiveOptimizePass(llvm::PassRegistry &);

} // namespace llvm
