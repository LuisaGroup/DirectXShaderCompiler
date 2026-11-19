// RUN: %dxc -T cs_6_0 -E main %s | FileCheck %s --check-prefix=SELECT
// RUN: %dxc -T cs_6_0 -E main -DDIRECT %s | FileCheck %s --check-prefix=DIRECT
// RUN: %dxc -T cs_6_0 -E main -DDEEP %s | FileCheck %s --check-prefix=DEEP

// A static const struct that is initialized from another static const struct
// keeps its initializer, no matter how deep the chain is: replacing the uses
// of one global creates new uses of the global it is initialized from, so the
// replacement has to run from the outermost global inwards.
//
// SELECT: bufferStore.f32({{.*}}float 5.000000e+00
// DIRECT: bufferStore.f32({{.*}}float 3.000000e+00
// DEEP: bufferStore.f32({{.*}}float 1.200000e+01

#ifdef DEEP
struct A { float2x2 m; float pad; };
struct B { A a; };
struct C { B b; };
struct D { C c; };
static const A a = {float2x2(1, 2, 3, 4), 9.0f};
static const B b = {a};
static const C c = {b};
static const D d = {c};
#else
struct A { float2x2 m; };
struct B { A a; };
struct C { B b; };
static const A a = {float2x2(1, 2, 3, 4)};
static const B b = {a};
static const C c = {b};
#endif

RWStructuredBuffer<float> output : register(u0);

[numthreads(1, 1, 1)]
void main() {
#ifdef DEEP
  // d.c.b.a.m[1][0] is 3 and d.c.b.a.pad is 9.
  output[0] = d.c.b.a.m[1][0] + d.c.b.a.pad;
#elif defined(DIRECT)
  // c.b.a.m[1][0] is 3, so this stores 3.
  output[0] = c.b.a.m[1][0];
#else
  // c.b.a.m[1][0] is 3, so this stores 5.
  output[0] = c.b.a.m[1][0] == 3.0f ? 5.0f : 7.0f;
#endif
}
