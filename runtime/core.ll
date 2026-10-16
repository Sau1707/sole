declare ptr @_sole.alloc64(i64)
declare void @llvm.trap()

define internal void @_sole.copy(ptr %dest, ptr %src, i64 %size) noinline optnone {
entry:
  br label %test
test:
  %i = phi i64 [ 0, %entry ], [ %next, %body ]
  %more = icmp ult i64 %i, %size
  br i1 %more, label %body, label %end
body:
  %s = getelementptr i8, ptr %src, i64 %i
  %d = getelementptr i8, ptr %dest, i64 %i
  %byte = load i8, ptr %s
  store i8 %byte, ptr %d
  %next = add i64 %i, 1
  br label %test
end:
  ret void
}

define ptr @_sole.cstr(ptr %data, i64 %length) {
entry:
  %valid = icmp ult i64 %length, 9223372036854775807
  br i1 %valid, label %ok, label %bad
bad:
  call void @llvm.trap()
  unreachable
ok:
  %size = add i64 %length, 1
  %result = call ptr @_sole.alloc64(i64 %size)
  call void @_sole.copy(ptr %result, ptr %data, i64 %length)
  %end = getelementptr i8, ptr %result, i64 %length
  store i8 0, ptr %end
  ret ptr %result
}

define ptr @_sole.concat(ptr %a, i64 %alen, ptr %b, i64 %blen) {
entry:
  %length = add i64 %alen, %blen
  %overflow = icmp ult i64 %length, %alen
  %huge = icmp uge i64 %length, 9223372036854775807
  %invalid = or i1 %overflow, %huge
  br i1 %invalid, label %bad, label %ok
bad:
  call void @llvm.trap()
  unreachable
ok:
  %size = add i64 %length, 1
  %result = call ptr @_sole.alloc64(i64 %size)
  call void @_sole.copy(ptr %result, ptr %a, i64 %alen)
  %tail = getelementptr i8, ptr %result, i64 %alen
  call void @_sole.copy(ptr %tail, ptr %b, i64 %blen)
  %end = getelementptr i8, ptr %result, i64 %length
  store i8 0, ptr %end
  ret ptr %result
}

define i1 @_sole.str_eq(ptr %a, i64 %alen, ptr %b, i64 %blen) {
entry:
  %same = icmp eq i64 %alen, %blen
  br i1 %same, label %test, label %no
test:
  %i = phi i64 [ 0, %entry ], [ %next, %advance ]
  %done = icmp eq i64 %i, %alen
  br i1 %done, label %yes, label %body
body:
  %ap = getelementptr i8, ptr %a, i64 %i
  %bp = getelementptr i8, ptr %b, i64 %i
  %av = load i8, ptr %ap
  %bv = load i8, ptr %bp
  %equal = icmp eq i8 %av, %bv
  br i1 %equal, label %advance, label %no
advance:
  %next = add i64 %i, 1
  br label %test
yes:
  ret i1 true
no:
  ret i1 false
}

define i64 @_sole.cstrlen(ptr %data) {
entry:
  br label %test
test:
  %i = phi i64 [ 0, %entry ], [ %next, %body ]
  %p = getelementptr i8, ptr %data, i64 %i
  %byte = load i8, ptr %p
  %done = icmp eq i8 %byte, 0
  br i1 %done, label %end, label %body
body:
  %next = add i64 %i, 1
  br label %test
end:
  ret i64 %i
}

define {ptr, i64} @_sole.number_str(i64 %value, i1 %negative) {
entry:
  %data = call ptr @_sole.alloc64(i64 32)
  %last = getelementptr i8, ptr %data, i64 31
  store i8 0, ptr %last
  %negated = sub i64 0, %value
  %magnitude = select i1 %negative, i64 %negated, i64 %value
  br label %digits
digits:
  %n = phi i64 [ %magnitude, %entry ], [ %quotient, %digits ]
  %i = phi i64 [ 31, %entry ], [ %previous, %digits ]
  %remainder = urem i64 %n, 10
  %digit = trunc i64 %remainder to i8
  %ascii = add i8 %digit, 48
  %previous = sub i64 %i, 1
  %position = getelementptr i8, ptr %data, i64 %previous
  store i8 %ascii, ptr %position
  %quotient = udiv i64 %n, 10
  %more = icmp ne i64 %quotient, 0
  br i1 %more, label %digits, label %sign
sign:
  br i1 %negative, label %minus, label %end
minus:
  %with_sign = sub i64 %previous, 1
  %sign_position = getelementptr i8, ptr %data, i64 %with_sign
  store i8 45, ptr %sign_position
  br label %end
end:
  %start = phi i64 [ %previous, %sign ], [ %with_sign, %minus ]
  %pointer = getelementptr i8, ptr %data, i64 %start
  %length = sub i64 31, %start
  %v0 = insertvalue {ptr, i64} poison, ptr %pointer, 0
  %v1 = insertvalue {ptr, i64} %v0, i64 %length, 1
  ret {ptr, i64} %v1
}

define ptr @_sole.array_new() {
entry:
  %array = call ptr @_sole.alloc64(i64 24)
  store ptr null, ptr %array
  %length = getelementptr {ptr, i64, i64}, ptr %array, i32 0, i32 1
  %capacity = getelementptr {ptr, i64, i64}, ptr %array, i32 0, i32 2
  store i64 0, ptr %length
  store i64 0, ptr %capacity
  ret ptr %array
}

define void @_sole.append(ptr %array, ptr %item, i64 %item_size) {
entry:
  %lp = getelementptr {ptr, i64, i64}, ptr %array, i32 0, i32 1
  %cp = getelementptr {ptr, i64, i64}, ptr %array, i32 0, i32 2
  %length = load i64, ptr %lp
  %capacity = load i64, ptr %cp
  %full = icmp eq i64 %length, %capacity
  br i1 %full, label %grow, label %write
grow:
  %double = mul i64 %capacity, 2
  %empty = icmp eq i64 %capacity, 0
  %next_cap = select i1 %empty, i64 8, i64 %double
  %larger = icmp ugt i64 %next_cap, %capacity
  %limit = udiv i64 9223372036854775807, %next_cap
  %fits = icmp ule i64 %item_size, %limit
  %valid = and i1 %larger, %fits
  br i1 %valid, label %allocate, label %bad
bad:
  call void @llvm.trap()
  unreachable
allocate:
  %bytes = mul i64 %next_cap, %item_size
  %data = call ptr @_sole.alloc64(i64 %bytes)
  %old_data = load ptr, ptr %array
  %used = mul i64 %length, %item_size
  call void @_sole.copy(ptr %data, ptr %old_data, i64 %used)
  store ptr %data, ptr %array
  store i64 %next_cap, ptr %cp
  br label %write
write:
  %buffer = load ptr, ptr %array
  %offset = mul i64 %length, %item_size
  %dest = getelementptr i8, ptr %buffer, i64 %offset
  call void @_sole.copy(ptr %dest, ptr %item, i64 %item_size)
  %next_len = add i64 %length, 1
  store i64 %next_len, ptr %lp
  ret void
}

define {ptr, i64} @_sole.join(ptr %array) {
entry:
  %lp = getelementptr {ptr, i64, i64}, ptr %array, i32 0, i32 1
  %length = load i64, ptr %lp
  %data = load ptr, ptr %array
  br label %measure
measure:
  %i = phi i64 [ 0, %entry ], [ %next, %size ]
  %total = phi i64 [ 0, %entry ], [ %sum, %size ]
  %more = icmp ult i64 %i, %length
  br i1 %more, label %size, label %allocate
size:
  %sp = getelementptr {ptr, i64}, ptr %data, i64 %i, i32 1
  %n = load i64, ptr %sp
  %sum = add i64 %total, %n
  %overflow = icmp ult i64 %sum, %total
  %next = add i64 %i, 1
  br i1 %overflow, label %bad, label %measure
bad:
  call void @llvm.trap()
  unreachable
allocate:
  %fits = icmp ult i64 %total, 9223372036854775807
  br i1 %fits, label %ok, label %bad
ok:
  %bytes = add i64 %total, 1
  %result = call ptr @_sole.alloc64(i64 %bytes)
  br label %copy
copy:
  %j = phi i64 [ 0, %ok ], [ %jnext, %body ]
  %offset = phi i64 [ 0, %ok ], [ %offset_next, %body ]
  %remaining = icmp ult i64 %j, %length
  br i1 %remaining, label %body, label %end
body:
  %item = getelementptr {ptr, i64}, ptr %data, i64 %j
  %value = load {ptr, i64}, ptr %item
  %src = extractvalue {ptr, i64} %value, 0
  %count = extractvalue {ptr, i64} %value, 1
  %dest = getelementptr i8, ptr %result, i64 %offset
  call void @_sole.copy(ptr %dest, ptr %src, i64 %count)
  %offset_next = add i64 %offset, %count
  %jnext = add i64 %j, 1
  br label %copy
end:
  %terminator = getelementptr i8, ptr %result, i64 %total
  store i8 0, ptr %terminator
  %v0 = insertvalue {ptr, i64} poison, ptr %result, 0
  %v1 = insertvalue {ptr, i64} %v0, i64 %total, 1
  ret {ptr, i64} %v1
}
