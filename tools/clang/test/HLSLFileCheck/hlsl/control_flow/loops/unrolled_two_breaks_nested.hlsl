// RUN: %dxc -T cs_6_0 -E main %s | FileCheck %s

// Two breaks nested inside conditionals of a loop that gets unrolled.  The
// loop exit structurizer turns the first break into a flag; the block holding
// the second break must be guarded by that flag as well.  Otherwise an
// invocation that already left through the first break still runs the second
// exit branch, and the value carried by the second exit (2) overrides the
// value of the exit that was actually taken (7).
//
// CHECK: [[notexited:%[0-9]+]] = xor i1 {{%[0-9]+}}, true
// CHECK: [[exit2:%[0-9]+]] = phi i1 {{.*}}[[notexited]]
// CHECK: [[exit1val:%[0-9]+]] = phi i32 [ 0, {{%[0-9]+}} ], [ 7, {{%[0-9]+}} ]
// CHECK: [[exitcond:%[0-9]+]] = or i1 [[exit2]], {{%[0-9]+}}
// CHECK: {{%[0-9]+}} = select i1 [[exit2]], i32 {{%[0-9]+}}, i32 [[exit1val]]

StructuredBuffer<uint> In  : register(t0);
RWStructuredBuffer<uint> Out : register(u0);

[numthreads(64, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint tid = dtid.x;
    uint a = In[tid];
    uint u = In[63];
    uint c = 4u; // (c & 3u) < 2u is true on the first iteration
    uint r = 7u;
    [unroll] for (uint i = 0u; i < 3u; ++i) {
        [branch] if (a != 14u) {
            if (a == 0u) { break; } // exit #1
            r = 2u; // not reached when exit #1 is taken
            if ((c & 3u) < 2u) { break; } // exit #2
        }
        c = u;
    }
    Out[tid] = r;
}
