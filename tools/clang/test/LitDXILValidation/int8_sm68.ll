; RUN: not %dxv %s 2>&1 | FileCheck %s

target datalayout = "e-m:e-p:32:32-i1:32-i8:8-i16:16-i32:32-i64:64-f16:16-f32:32-f64:64-n8:16:32:64"
target triple = "dxil-ms-dx"

; CHECK: error: I8 can only be used as immediate value for intrinsic or as i8* via bitcast by lifetime intrinsics.
; CHECK: Validation failed.

define void @main() {
  %1 = add i8 1, 2
  call void @dx.op.storeOutput.i8(i32 5, i32 0, i32 0, i8 0, i8 %1)
  ret void
}

declare void @dx.op.storeOutput.i8(i32, i32, i32, i8, i8) #0

attributes #0 = { nounwind }

!dx.version = !{!0}
!dx.valver = !{!1}
!dx.shaderModel = !{!2}
!dx.entryPoints = !{!3}

!0 = !{i32 1, i32 8}
!1 = !{i32 1, i32 8}
!2 = !{!"ps", i32 6, i32 8}
!3 = !{void ()* @main, !"main", !4, null, null}
!4 = !{null, !5, null}
!5 = !{!6}
!6 = !{i32 0, !"SV_Target", i8 19, i8 16, !7, i8 0, i32 1, i8 1, i32 0, i8 0, !8}
!7 = !{i32 0}
!8 = !{i32 3, i32 1}
