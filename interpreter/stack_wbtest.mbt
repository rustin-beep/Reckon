// 白盒：limb 快路径、`sp` / `data` 不变量、错误路径的 limb 级原子性。
//
// 白盒测试是独立编译单元，helper 要单独定义（不复用 `stack_test.mbt` 的）。

///|
fn wlimbs(l0 : UInt64, l1 : UInt64, l2 : UInt64, l3 : UInt64) -> @types.U256 {
  @types.U256::from_limbs(l0, l1, l2, l3)
}

///|
/// 抓一份 `data` 快照，用来验证「报错不改栈内容」。
fn snapshot(stack : Stack) -> Array[UInt64] {
  let out : Array[UInt64] = []
  for i in 0..<stack.data.length() {
    out.push(stack.data[i])
  }
  out
}

///|
fn assert_data_unchanged(
  before : Array[UInt64],
  stack : Stack,
  label : String,
) -> Unit raise {
  assert_eq(before.length(), stack.data.length(), msg="\{label}: data 长度")
  for i in 0..<before.length() {
    assert_eq(stack.data[i], before[i], msg="\{label}: data[\{i}] 被改动")
  }
}

///|
/// 只比前 `depth * 4` 个 limb：两套接口的活跃区必须逐 limb 相同。
fn assert_same_stack(a : Stack, b : Stack, label : String) -> Unit raise {
  assert_eq(a.depth(), b.depth(), msg="\{label}: depth")
  for i in 0..<(a.depth() * 4) {
    assert_eq(a.data[i], b.data[i], msg="\{label}: data[\{i}]")
  }
}

///|
fn expect_underflow(
  label : String,
  f : () -> Unit raise StackError,
  want_needed : Int32,
  want_available : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    StackError::Underflow(needed~, available~) => {
      seen = true
      assert_eq(needed, want_needed, msg="\{label}: needed")
      assert_eq(available, want_available, msg="\{label}: available")
    }
    _ => fail("\{label}: 期望 Underflow")
  } noraise {
    _ => ()
  }
  assert_true(seen, msg="\{label}: 期望抛 Underflow，实际成功")
}

///|
fn expect_overflow(
  label : String,
  f : () -> Unit raise StackError,
  want_limit : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    StackError::Overflow(limit~) => {
      seen = true
      assert_eq(limit, want_limit, msg="\{label}: limit")
    }
    _ => fail("\{label}: 期望 Overflow")
  } noraise {
    _ => ()
  }
  assert_true(seen, msg="\{label}: 期望抛 Overflow，实际成功")
}

///|
fn expect_invalid_depth(
  label : String,
  f : () -> Unit raise StackError,
  want_depth : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    StackError::InvalidDepth(depth~) => {
      seen = true
      assert_eq(depth, want_depth, msg="\{label}: depth")
    }
    _ => fail("\{label}: 期望 InvalidDepth")
  } noraise {
    _ => ()
  }
  assert_true(seen, msg="\{label}: 期望抛 InvalidDepth，实际成功")
}

///|
/// 测试语料：四个 limb 都不同、且没有对称性，跨 limb 复制错了能立刻看出来。
fn corpus() -> Array[(UInt64, UInt64, UInt64, UInt64)] {
  [
    (0UL, 0UL, 0UL, 0UL),
    (1UL, 0UL, 0UL, 0UL),
    (0xFFFFFFFFFFFFFFFFUL, 0UL, 0UL, 0UL),
    (
      0x1111111111111111UL, 0x2222222222222222UL, 0x3333333333333333UL, 0x4444444444444444UL,
    ),
    (0UL, 0xFFFFFFFFFFFFFFFFUL, 0UL, 0xFFFFFFFFFFFFFFFFUL),
    (
      0xDEADBEEFCAFEBABEUL, 0x0123456789ABCDEFUL, 0xFEDCBA9876543210UL, 0x5A5A5A5A5A5A5A5AUL,
    ),
  ]
}

// ---------------------------------------------------------------------------
// 错误文本
// ---------------------------------------------------------------------------

///|
test "StackError 的文本格式稳定" {
  // 变体只能在包内构造，所以这条放白盒；C04/C15 依赖这个格式。
  assert_eq(
    StackError::Underflow(needed=2, available=1).to_string(),
    "栈下溢：需要 2 项，当前 1 项",
  )
  assert_eq(
    StackError::Overflow(limit=1024).to_string(),
    "栈上溢：上限 1024 项",
  )
  assert_eq(StackError::InvalidDepth(depth=-1).to_string(), "非法深度：-1")
}

// ---------------------------------------------------------------------------
// 两套接口同语义
// ---------------------------------------------------------------------------

///|
test "limb 快路径与 U256 接口逐步同语义" {
  let via_u256 = Stack::new()
  let via_limbs = Stack::new()
  let values = corpus()
  for i in 0..<values.length() {
    let (l0, l1, l2, l3) = values[i]
    via_u256.push(wlimbs(l0, l1, l2, l3))
    via_limbs.push_limbs(l0, l1, l2, l3)
    assert_same_stack(via_u256, via_limbs, "push 第 \{i} 项")
  }
  // set_top
  via_u256.set_top(wlimbs(7UL, 8UL, 9UL, 10UL))
  via_limbs.set_top_limbs(7UL, 8UL, 9UL, 10UL)
  assert_same_stack(via_u256, via_limbs, "set_top")
  // dup / swap
  via_u256.dup(3)
  via_limbs.dup(3)
  assert_same_stack(via_u256, via_limbs, "dup(3)")
  via_u256.swap(2)
  via_limbs.swap(2)
  assert_same_stack(via_u256, via_limbs, "swap(2)")
  // pop / drop
  let a = via_u256.pop()
  let (b0, b1, b2, b3) = via_limbs.pop_limbs()
  assert_eq(a.limb(0), b0)
  assert_eq(a.limb(1), b1)
  assert_eq(a.limb(2), b2)
  assert_eq(a.limb(3), b3)
  assert_same_stack(via_u256, via_limbs, "pop")
  via_u256.drop()
  via_limbs.drop()
  assert_same_stack(via_u256, via_limbs, "drop")
  // clear
  via_u256.clear()
  via_limbs.clear()
  assert_same_stack(via_u256, via_limbs, "clear")
}

///|
test "peek_limbs 与 peek 逐 limb 一致" {
  let stack = Stack::new()
  let values = corpus()
  for i in 0..<values.length() {
    let (l0, l1, l2, l3) = values[i]
    stack.push_limbs(l0, l1, l2, l3)
  }
  for d in 0..<values.length() {
    let (l0, l1, l2, l3) = stack.peek_limbs(d)
    let word = stack.peek(d)
    assert_eq(word.limb(0), l0, msg="peek(\{d}) l0")
    assert_eq(word.limb(1), l1, msg="peek(\{d}) l1")
    assert_eq(word.limb(2), l2, msg="peek(\{d}) l2")
    assert_eq(word.limb(3), l3, msg="peek(\{d}) l3")
  }
}

// ---------------------------------------------------------------------------
// 快路径的错误路径同样原子
// ---------------------------------------------------------------------------

///|
test "push_limbs 满栈溢出不改 data 也不改 sp" {
  let stack = Stack::new()
  for i in 0..<1024 {
    stack.push_limbs(i.to_uint64(), 0UL, 0UL, 0UL)
  }
  let before = snapshot(stack)
  expect_overflow(
    "第 1025 次 push_limbs",
    () => stack.push_limbs(1UL, 2UL, 3UL, 4UL),
    1024,
  )
  assert_eq(stack.sp, 1024, msg="溢出后 sp")
  assert_data_unchanged(before, stack, "push_limbs 溢出")
}

///|
test "快路径在空栈上的下溢不改 data" {
  let stack = Stack::new()
  let before = snapshot(stack)
  expect_underflow("pop_limbs", () => ignore(stack.pop_limbs()), 1, 0)
  expect_underflow("peek_limbs(0)", () => ignore(stack.peek_limbs(0)), 1, 0)
  expect_underflow(
    "set_top_limbs",
    () => stack.set_top_limbs(1UL, 2UL, 3UL, 4UL),
    1,
    0,
  )
  assert_eq(stack.sp, 0, msg="下溢后 sp")
  assert_data_unchanged(before, stack, "空栈快路径")
}

///|
test "peek_limbs 的负深度与越界" {
  let stack = Stack::new()
  stack.push_limbs(1UL, 2UL, 3UL, 4UL)
  let before = snapshot(stack)
  expect_invalid_depth("peek_limbs(-1)", () => ignore(stack.peek_limbs(-1)), -1)
  expect_underflow("peek_limbs(1)", () => ignore(stack.peek_limbs(1)), 2, 1)
  expect_underflow("peek_limbs(9)", () => ignore(stack.peek_limbs(9)), 10, 1)
  assert_eq(stack.sp, 1, msg="报错后 sp")
  assert_data_unchanged(before, stack, "peek_limbs 报错")
}

///|
test "dup 溢出不写目标槽" {
  let stack = Stack::new()
  for i in 0..<1024 {
    stack.push_limbs(i.to_uint64(), 0UL, 0UL, 0UL)
  }
  let before = snapshot(stack)
  expect_overflow("满栈 dup(1)", () => stack.dup(1), 1024)
  assert_eq(stack.sp, 1024, msg="溢出后 sp")
  assert_data_unchanged(before, stack, "dup 溢出")
}

///|
test "swap 越界不交换半截" {
  let stack = Stack::new()
  stack.push_limbs(1UL, 2UL, 3UL, 4UL)
  stack.push_limbs(5UL, 6UL, 7UL, 8UL)
  let before = snapshot(stack)
  expect_underflow("swap(2) 于深度 2", () => stack.swap(2), 3, 2)
  assert_eq(stack.sp, 2, msg="报错后 sp")
  assert_data_unchanged(before, stack, "swap 越界")
}

// ---------------------------------------------------------------------------
// 内部不变量
// ---------------------------------------------------------------------------

///|
test "item_limb / set_item_limb 只动目标 limb" {
  let stack = Stack::new()
  stack.push_limbs(0x10UL, 0x20UL, 0x30UL, 0x40UL)
  stack.push_limbs(0x50UL, 0x60UL, 0x70UL, 0x80UL)
  // 第 0 项是栈底，第 1 项是栈顶。
  assert_eq(stack.item_limb(0, 0), 0x10UL)
  assert_eq(stack.item_limb(0, 3), 0x40UL)
  assert_eq(stack.item_limb(1, 0), 0x50UL)
  assert_eq(stack.item_limb(1, 2), 0x70UL)
  stack.set_item_limb(0, 1, 0xABUL)
  assert_eq(stack.item_limb(0, 0), 0x10UL, msg="l0 不变")
  assert_eq(stack.item_limb(0, 1), 0xABUL, msg="l1 被改")
  assert_eq(stack.item_limb(0, 2), 0x30UL, msg="l2 不变")
  assert_eq(stack.item_limb(0, 3), 0x40UL, msg="l3 不变")
  assert_eq(stack.item_limb(1, 1), 0x60UL, msg="栈顶不受影响")
  // 通过公开接口也看得到这次改写。
  assert_eq(stack.peek(1).limb(1), 0xABUL)
}

///|
test "sp 与 data 的形态不变量" {
  let stack = Stack::new()
  assert_eq(stack.data.length(), 4096, msg="1024 项 × 4 limb")
  let ops : Array[Int32] = [3, 1, 4, 1, 5, 9, 2, 6]
  for i in 0..<ops.length() {
    stack.push_limbs(ops[i].to_uint64(), 0UL, 0UL, 0UL)
    assert_eq(stack.sp, i + 1, msg="第 \{i} 次 push 后 sp")
  }
  for i in 0..<ops.length() {
    stack.drop()
    assert_eq(stack.sp, ops.length() - 1 - i, msg="第 \{i} 次 drop 后 sp")
  }
  assert_eq(stack.sp, 0)
  // clear 只清 sp，旧 limb 留在 data 里——这是约定（公开接口读不到）。
  stack.push_limbs(0xCAFEUL, 0UL, 0UL, 0UL)
  stack.clear()
  assert_eq(stack.sp, 0)
  assert_eq(stack.data[0], 0xCAFEUL, msg="clear 不擦除 data")
  expect_underflow(
    "clear 后 peek_limbs",
    () => ignore(stack.peek_limbs(0)),
    1,
    0,
  )
}
