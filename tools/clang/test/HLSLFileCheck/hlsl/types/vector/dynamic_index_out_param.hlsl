// RUN: %dxc -T ps_6_0 -E main -Od %s | FileCheck %s
// RUN: %dxc -T ps_6_0 -E main -Od -DSINGLE %s | FileCheck %s --check-prefix=SINGLE
// RUN: %dxc -T ps_6_0 -E main %s | FileCheck %s --check-prefix=OPT

// Dynamically indexing a vector that an intrinsic writes through an out
// parameter used to crash the compiler: the vector has to be lowered to an
// array, but the call kept pointing at the erased vector, which left a
// dangling reference in the module.
//
// The array holds the integral parts written by modf, so the copy back from
// the temporary vector must produce 1.0 and -2.0.
//
// CHECK: alloca [2 x float]
// CHECK: store float 1.000000e+00
// CHECK: store float -2.000000e+00
//
// SINGLE: alloca [1 x float]
// SINGLE: store float 1.000000e+00
//
// OPT: constant [2 x float] [float 1.000000e+00, float -2.000000e+00]

#ifdef SINGLE
float main(uint I : INDEX) : SV_Target {
  float1 V;
  modf((float1)1.25, V);
  return V[I];
}
#else
float2 main(uint I : INDEX) : SV_Target {
  float2 V;
  modf(float2(1.25, -2.75), V);
  return V[I];
}
#endif
