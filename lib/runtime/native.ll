declare ptr @malloc(i64)
declare i32 @putchar(i32)
declare i32 @printf(ptr, ...)
declare i64 @write(i32, ptr, i64)
declare void @exit(i32)

@_sole.argc = internal global i64 0
@_sole.argv = internal global ptr null
@_sole.arg_error = private constant [36 x i8] c"sole: argument index out of bounds\0A\00"

define void @_sole.init(i32 %argc, ptr %argv) {
entry:
  %count = sext i32 %argc to i64
  store i64 %count, ptr @_sole.argc
  store ptr %argv, ptr @_sole.argv
  ret void
}

define i64 @_sole.arg_count() {
entry:
  %count = load i64, ptr @_sole.argc
  ret i64 %count
}

define ptr @_sole.arg(i64 %index) {
entry:
  %count = load i64, ptr @_sole.argc
  %valid = icmp ult i64 %index, %count
  br i1 %valid, label %ok, label %bad
bad:
  %ignored = call i64 @write(i32 2, ptr @_sole.arg_error, i64 35)
  call void @exit(i32 1)
  unreachable
ok:
  %arguments = load ptr, ptr @_sole.argv
  %slot = getelementptr ptr, ptr %arguments, i64 %index
  %argument = load ptr, ptr %slot
  ret ptr %argument
}

@_sole.signed = private constant [6 x i8] c"%lld\0A\00"
@_sole.unsigned = private constant [6 x i8] c"%llu\0A\00"
@_sole.float = private constant [7 x i8] c"%.17g\0A\00"
@_sole.true = private constant [4 x i8] c"true"
@_sole.false = private constant [5 x i8] c"false"

define ptr @_sole.alloc64(i64 %size) {
entry:
  %empty = icmp eq i64 %size, 0
  %amount = select i1 %empty, i64 1, i64 %size
  %data = call ptr @malloc(i64 %amount)
  %valid = icmp ne ptr %data, null
  br i1 %valid, label %ok, label %bad
bad:
  call void @llvm.trap()
  unreachable
ok:
  ret ptr %data
}

define void @_sole.print_str(ptr %data, i64 %length) {
entry:
  br label %test
test:
  %i = phi i64 [ 0, %entry ], [ %next, %body ]
  %more = icmp ult i64 %i, %length
  br i1 %more, label %body, label %end
body:
  %p = getelementptr i8, ptr %data, i64 %i
  %byte = load i8, ptr %p
  %char = zext i8 %byte to i32
  call i32 @putchar(i32 %char)
  %next = add i64 %i, 1
  br label %test
end:
  call i32 @putchar(i32 10)
  ret void
}

define void @_sole.print_bool(i1 %value) {
entry:
  %data = select i1 %value, ptr @_sole.true, ptr @_sole.false
  %size = select i1 %value, i64 4, i64 5
  call void @_sole.print_str(ptr %data, i64 %size)
  ret void
}

define void @_sole.print_int(i64 %value, i1 %signed) {
entry:
  %format = select i1 %signed, ptr @_sole.signed, ptr @_sole.unsigned
  call i32 (ptr, ...) @printf(ptr %format, i64 %value)
  ret void
}

define void @_sole.print_float(double %value) {
entry:
  call i32 (ptr, ...) @printf(ptr @_sole.float, double %value)
  ret void
}
