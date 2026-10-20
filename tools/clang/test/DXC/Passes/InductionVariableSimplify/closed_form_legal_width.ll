; RUN: opt %s -indvars -S | FileCheck %s

; BinomialCoefficient evaluates a closed-form loop exit value at W+T bits
; (33 bits for a 32-bit, K=2 coefficient such as the running sum of an
; induction variable). DXIL only supports 1/8/16/32/64-bit integer types, so
; the calculation width is rounded up to the next legal width instead of
; materializing an illegal type like i33, which DXIL validation rejects with
; "Int type 'i33' has an invalid width".

target datalayout = "e-m:e-p:32:32-i1:32-i8:32-i16:32-i32:32-i64:64-f16:32-f32:32-f64:64-n8:16:32:64"
target triple = "dxil-ms-dx"

; The loop below comes from reducing the following HLSL pattern:
;   uint l3 = DispatchThreadID.x;
;   int l11 = 0;
;   uint l12 = l3 % 4u;
;   int l16 = (int)l12 + 1;
;   for (int l17 = 0; l17 < l16; l17 += 1) { l11 = l11 + l17; }
; IndVarSimplify rewrites the exit value to its closed form n*(n+1)/2 and
; deletes the loop.

; CHECK-LABEL: @sum_exit_value
; CHECK-NOT: i33
; CHECK: mul i64
; CHECK: lshr i64
; CHECK: trunc i64
define i32 @sum_exit_value(i32 %tid) {
entry:
  %bound = and i32 %tid, 3
  br label %loop

loop:
  %sum = phi i32 [ 0, %entry ], [ %sum.next, %loop ]
  %iv = phi i32 [ 0, %entry ], [ %iv.next, %loop ]
  %sum.next = add nsw i32 %sum, %iv
  %iv.next = add nsw i32 %iv, 1
  %exitcond = icmp slt i32 %iv, %bound
  br i1 %exitcond, label %loop, label %exit

exit:
  ret i32 %sum.next
}
