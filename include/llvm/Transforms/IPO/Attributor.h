//===- Attributor.h - Function Attribute Inference Utilities ----*- C++ -*-===//
//
//                     The LLVM Compiler Infrastructure
//
// This file is distributed under the University of Illinois Open Source
// License. See LICENSE.TXT for details.
//
//===----------------------------------------------------------------------===//
//
// This file provides declarations for attribute inference utilities used
// by the Attributor pass.
//
//===----------------------------------------------------------------------===//

#ifndef LLVM_TRANSFORMS_IPO_ATTRIBUTOR_H
#define LLVM_TRANSFORMS_IPO_ATTRIBUTOR_H

#include "llvm/ADT/SmallPtrSet.h"
#include "llvm/IR/Function.h"

namespace llvm {

class Argument;

/// Infer attributes for a function argument by analyzing the function body.
/// Returns true if any attribute was changed.
bool inferArgumentAttrFromBody(Argument &Arg);

/// Check if a function always returns (willreturn attribute).
bool functionWillReturn(const Function &F);

/// Get the set of functions directly called from a function.
void getDirectCallees(const Function &F,
                      SmallPtrSetImpl<Function *> &Callees);

} // end namespace llvm

#endif
