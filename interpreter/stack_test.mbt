// `Stack` 的公开 API 测试（黑盒：只用 `pub` 接口）。
//
// 覆盖四块：读接口、写接口与错误原子性、1024 项边界、随机参考模型对拍。
// limb 快路径与 `sp`/`data` 内部不变量在 `stack_wbtest.mbt`。

// ---------------------------------------------------------------------------
// 断言与辅助
// ---------------------------------------------------------------------------

///|
fn u(n : UInt64) -> @types.U256 {
  @types.U256::from_u64(n)
}

///|
fn limbs(l0 : UInt64, l1 : UInt64, l2 : UInt64, l3 : UInt64) -> @types.U256 {
  @types.U256::from_limbs(l0, l1, l2, l3)
}

///|
/// 逐 limb 比，失败时能指出是哪个 limb。
fn assert_u256(
  got : @types.U256,
  want : @types.U256,
  label : String,
) -> Unit raise {
  for k in 0..<4 {
    assert_eq(got.limb(k), want.limb(k), msg="\{label}: limb \{k}")
  }
}

///|
/// 断言 `f` 抛 `Underflow` 且两个字段都对。
fn expect_underflow(
  label : String,
  f : () -> Unit raise @interpreter.StackError,
  want_needed : Int32,
  want_available : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    @interpreter.StackError::Underflow(needed~, available~) => {
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
  f : () -> Unit raise @interpreter.StackError,
  want_limit : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    @interpreter.StackError::Overflow(limit~) => {
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
  f : () -> Unit raise @interpreter.StackError,
  want_depth : Int32,
) -> Unit raise {
  let mut seen = false
  try f() catch {
    @interpreter.StackError::InvalidDepth(depth~) => {
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
/// 把 `1..=n` 依次压栈，返回值列表（下标 0 是栈底）。
fn push_sequence(stack : @interpreter.Stack, n : Int32) -> Unit raise {
  for i in 1..<=n {
    stack.push(u(i.to_uint64()))
  }
}

// ---------------------------------------------------------------------------
// 阶段 1：构造与读接口
// ---------------------------------------------------------------------------

///|
test "空栈的读口径" {
  let stack = @interpreter.Stack::new()
  assert_eq(@interpreter.Stack::limit(), 1024)
  assert_eq(stack.depth(), 0)
  assert_true(stack.is_empty())
  assert_true(!stack.is_full())
  expect_underflow("空栈 peek(0)", () => ignore(stack.peek(0)), 1, 0)
  expect_invalid_depth("空栈 peek(-1)", () => ignore(stack.peek(-1)), -1)
  expect_underflow("空栈 peek(7)", () => ignore(stack.peek(7)), 8, 0)
}

///|
test "push / peek / depth 的基本语义" {
  let stack = @interpreter.Stack::new()
  stack.push(u(0xAAUL))
  assert_eq(stack.depth(), 1)
  assert_true(!stack.is_empty())
  assert_u256(stack.peek(0), u(0xAAUL), "单项 peek(0)")
  stack.push(u(0xBBUL))
  assert_eq(stack.depth(), 2)
  assert_u256(stack.peek(0), u(0xBBUL), "两项 peek(0)")
  assert_u256(stack.peek(1), u(0xAAUL), "两项 peek(1)")
}

///|
test "U256 四个 limb 全覆盖" {
  let cases : Array[@types.U256] = [
    @types.U256::zero(),
    @types.U256::one(),
    u(0xFFFFFFFFFFFFFFFFUL),
    limbs(1UL, 2UL, 3UL, 4UL),
    limbs(0xFFFFFFFFFFFFFFFFUL, 0UL, 0x0123456789ABCDEFUL, 0UL),
    @types.U256::max_value(),
  ]
  let stack = @interpreter.Stack::new()
  for i in 0..<cases.length() {
    stack.push(cases[i])
    assert_u256(stack.peek(0), cases[i], "第 \{i} 个值 push 后 peek")
  }
  // 反过来读，确认不是「只有栈顶对」。
  for i in 0..<cases.length() {
    assert_u256(
      stack.peek(i),
      cases[cases.length() - 1 - i],
      "第 \{i} 项（自顶）",
    )
  }
}

///|
test "set_top 只改栈顶" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  stack.set_top(limbs(9UL, 8UL, 7UL, 6UL))
  assert_eq(stack.depth(), 3)
  assert_u256(stack.peek(0), limbs(9UL, 8UL, 7UL, 6UL), "新栈顶")
  assert_u256(stack.peek(1), u(2UL), "第二项不变")
  assert_u256(stack.peek(2), u(1UL), "栈底不变")
}

///|
test "set_top 在空栈上抛 Underflow 且不改栈" {
  let stack = @interpreter.Stack::new()
  expect_underflow("空栈 set_top", () => stack.set_top(u(1UL)), 1, 0)
  assert_eq(stack.depth(), 0)
  // 之后还能正常用。
  stack.push(u(5UL))
  assert_u256(stack.peek(0), u(5UL), "错误后 push")
}

///|
test "clear 只清 sp，之后仍可 push" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  stack.clear()
  assert_eq(stack.depth(), 0)
  assert_true(stack.is_empty())
  expect_underflow("clear 后 peek", () => ignore(stack.peek(0)), 1, 0)
  stack.push(u(42UL))
  assert_eq(stack.depth(), 1)
  assert_u256(stack.peek(0), u(42UL), "clear 后 push")
}

// ---------------------------------------------------------------------------
// 阶段 2：写接口与错误原子性
// ---------------------------------------------------------------------------

///|
test "LIFO 顺序与 pop / drop" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  assert_u256(stack.pop(), u(3UL), "pop 第一项")
  assert_eq(stack.depth(), 2)
  stack.drop()
  assert_eq(stack.depth(), 1)
  assert_u256(stack.peek(0), u(1UL), "drop 之后剩下栈底")
  assert_u256(stack.pop(), u(1UL), "pop 最后一项")
  assert_true(stack.is_empty())
}

///|
test "空栈 pop / drop / set_top 都是 Underflow" {
  let stack = @interpreter.Stack::new()
  expect_underflow("pop", () => ignore(stack.pop()), 1, 0)
  expect_underflow("drop", () => stack.drop(), 1, 0)
  expect_underflow("set_top", () => stack.set_top(u(1UL)), 1, 0)
  assert_eq(stack.depth(), 0)
}

///|
test "1024 项上限：第 1025 次 push 溢出且不动栈" {
  let stack = @interpreter.Stack::new()
  for i in 0..<1024 {
    stack.push(u(i.to_uint64()))
  }
  assert_eq(stack.depth(), 1024)
  assert_true(stack.is_full())
  let top_before = stack.peek(0)
  let bottom_before = stack.peek(1023)
  expect_overflow("第 1025 次 push", () => stack.push(u(9999UL)), 1024)
  assert_eq(stack.depth(), 1024)
  assert_u256(stack.peek(0), top_before, "溢出后栈顶不变")
  assert_u256(stack.peek(1023), bottom_before, "溢出后栈底不变")
  // 弹一项后又能 push。
  stack.drop()
  stack.push(u(4096UL))
  assert_u256(stack.peek(0), u(4096UL), "腾出位置后 push")
}

///|
test "peek 越界与负深度报错，且不改栈" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 2)
  expect_underflow("peek(sp)", () => ignore(stack.peek(2)), 3, 2)
  expect_underflow("peek(sp+3)", () => ignore(stack.peek(5)), 6, 2)
  expect_invalid_depth("peek(-1)", () => ignore(stack.peek(-1)), -1)
  assert_eq(stack.depth(), 2)
  assert_u256(stack.peek(0), u(2UL), "peek 报错后栈顶不变")
  assert_u256(stack.peek(1), u(1UL), "peek 报错后第二项不变")
}

///|
test "dup 1..16 的语义" {
  for d in 1..<=16 {
    let stack = @interpreter.Stack::new()
    push_sequence(stack, 16)
    stack.dup(d)
    assert_eq(stack.depth(), 17, msg="dup(\{d}) 后深度")
    // dup 前第 d 项（1-based）是 16-d+1；现在被复制到栈顶。
    assert_u256(
      stack.peek(0),
      u((16 - d + 1).to_uint64()),
      "dup(\{d}) 的栈顶",
    )
    // 原来的 16 项整体下移一格，顺序不变。
    for i in 1..<=16 {
      assert_u256(
        stack.peek(i),
        u((16 - i + 1).to_uint64()),
        "dup(\{d}) 后第 \{i} 项（自顶）",
      )
    }
  }
}

///|
test "dup 的深度下界与上界" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  expect_invalid_depth("dup(0)", () => stack.dup(0), 0)
  expect_invalid_depth("dup(-2)", () => stack.dup(-2), -2)
  expect_underflow("dup(4) 于深度 3", () => stack.dup(4), 4, 3)
  assert_eq(stack.depth(), 3)
  assert_u256(stack.peek(0), u(3UL), "dup 报错后栈顶不变")
}

///|
test "dup 在满栈时溢出且不写" {
  let stack = @interpreter.Stack::new()
  for i in 0..<1024 {
    stack.push(u(i.to_uint64()))
  }
  let top_before = stack.peek(0)
  let second_before = stack.peek(1)
  expect_overflow("满栈 dup(1)", () => stack.dup(1), 1024)
  assert_eq(stack.depth(), 1024)
  assert_u256(stack.peek(0), top_before, "溢出后栈顶不变")
  assert_u256(stack.peek(1), second_before, "溢出后第二项不变")
}

///|
test "swap 1..16 的语义" {
  // 17 项，才能让 swap(16) 命中「栈顶与栈底」这一对。
  for d in 1..<=16 {
    let stack = @interpreter.Stack::new()
    push_sequence(stack, 17)
    stack.swap(d)
    assert_eq(stack.depth(), 17, msg="swap(\{d}) 不改变深度")
    // 交换的是原栈顶 17 与原第 d 项（自顶，1-based）。
    assert_u256(
      stack.peek(0),
      u((17 - d).to_uint64()),
      "swap(\{d}) 后的栈顶",
    )
    assert_u256(stack.peek(d), u(17UL), "swap(\{d}) 后第 \{d} 项")
    // 其余 15 项原位不动。
    for i in 1..<=16 {
      if i != d {
        assert_u256(
          stack.peek(i),
          u((17 - i).to_uint64()),
          "swap(\{d}) 后未参与交换的第 \{i} 项",
        )
      }
    }
  }
}

///|
test "swap 的深度下界与上界" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  expect_invalid_depth("swap(0)", () => stack.swap(0), 0)
  expect_invalid_depth("swap(-3)", () => stack.swap(-3), -3)
  expect_underflow("swap(3) 于深度 3", () => stack.swap(3), 4, 3)
  assert_eq(stack.depth(), 3)
  assert_u256(stack.peek(0), u(3UL), "swap 报错后栈顶不变")
  assert_u256(stack.peek(1), u(2UL), "swap 报错后第二项不变")
}

///|
test "swap 之后栈整体可继续使用" {
  let stack = @interpreter.Stack::new()
  push_sequence(stack, 3)
  stack.swap(2)
  assert_u256(stack.peek(0), u(1UL), "swap(2) 栈顶")
  assert_u256(stack.peek(2), u(3UL), "swap(2) 栈底")
  assert_u256(stack.pop(), u(1UL), "swap 后 pop")
  stack.push(u(7UL))
  assert_u256(stack.peek(0), u(7UL), "swap 后 push")
}

// ---------------------------------------------------------------------------
// 阶段 4：参考模型随机对拍
// ---------------------------------------------------------------------------

///|
/// 线性同余伪随机：只有 `UInt64` 乘加，四后端逐位一致。
struct Rng {
  mut state : UInt64
}

///|
fn Rng::next(self : Rng) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state
}

///|
fn Rng::below(self : Rng, n : UInt64) -> Int32 {
  (self.next() % n).to_int()
}

///|
fn random_u256(rng : Rng) -> @types.U256 {
  limbs(rng.next(), rng.next(), rng.next(), rng.next())
}

///|
/// 逐项比对栈与参考模型；任何不一致都带步骤号失败。
fn assert_stack(
  stack : @interpreter.Stack,
  model : Array[@types.U256],
  step : Int32,
) -> Unit raise {
  let got_depth = stack.depth()
  let want_depth = model.length()
  if got_depth != want_depth {
    fail("step \{step}: depth \{got_depth} != 模型 \{want_depth}")
  }
  assert_true(
    stack.is_empty() == (want_depth == 0),
    msg="step \{step}: is_empty",
  )
  for i in 0..<want_depth {
    assert_u256(
      stack.peek(i),
      model[want_depth - 1 - i],
      "step \{step}: 第 \{i} 项（自顶）",
    )
  }
}

///|
test "随机对拍：500 步与 Array[U256] 参考模型一致" {
  let stack = @interpreter.Stack::new()
  let model : Array[@types.U256] = []
  let rng : Rng = { state: 20261122UL, }
  for step in 0..<500 {
    let kind = rng.below(10UL)
    let depth = rng.below(18UL)
    let value = random_u256(rng)
    if kind <= 2 {
      // push
      if model.length() >= 1024 {
        expect_overflow("step \{step}: push", () => stack.push(value), 1024)
      } else {
        stack.push(value)
        model.push(value)
      }
    } else if kind == 3 {
      // pop
      if model.length() == 0 {
        expect_underflow("step \{step}: pop", () => ignore(stack.pop()), 1, 0)
      } else {
        let want = model.pop().unwrap()
        assert_u256(stack.pop(), want, "step \{step}: pop")
      }
    } else if kind == 4 {
      // drop
      if model.length() == 0 {
        expect_underflow("step \{step}: drop", () => stack.drop(), 1, 0)
      } else {
        ignore(model.pop())
        stack.drop()
      }
    } else if kind == 5 {
      // peek(depth)，depth 取 0..17，覆盖「越界」与「命中」两侧。
      if depth >= model.length() {
        expect_underflow(
          "step \{step}: peek(\{depth})",
          () => ignore(stack.peek(depth)),
          depth + 1,
          model.length(),
        )
      } else {
        assert_u256(
          stack.peek(depth),
          model[model.length() - 1 - depth],
          "step \{step}: peek(\{depth})",
        )
      }
    } else if kind == 6 {
      // set_top
      if model.length() == 0 {
        expect_underflow(
          "step \{step}: set_top",
          () => stack.set_top(value),
          1,
          0,
        )
      } else {
        model[model.length() - 1] = value
        stack.set_top(value)
      }
    } else if kind == 7 {
      // dup(depth)
      if depth < 1 {
        expect_invalid_depth(
          "step \{step}: dup(0)",
          () => stack.dup(depth),
          depth,
        )
      } else if depth > model.length() {
        expect_underflow(
          "step \{step}: dup(\{depth})",
          () => stack.dup(depth),
          depth,
          model.length(),
        )
      } else if model.length() >= 1024 {
        expect_overflow("step \{step}: dup", () => stack.dup(depth), 1024)
      } else {
        let copied = model[model.length() - depth]
        model.push(copied)
        stack.dup(depth)
      }
    } else if kind == 8 {
      // swap(depth)
      if depth < 1 {
        expect_invalid_depth(
          "step \{step}: swap(0)",
          () => stack.swap(depth),
          depth,
        )
      } else if depth >= model.length() {
        expect_underflow(
          "step \{step}: swap(\{depth})",
          () => stack.swap(depth),
          depth + 1,
          model.length(),
        )
      } else {
        let top = model.length() - 1
        let other = top - depth
        let tmp = model[top]
        model[top] = model[other]
        model[other] = tmp
        stack.swap(depth)
      }
    } else {
      // clear
      model.clear()
      stack.clear()
    }
    assert_stack(stack, model, step)
  }
  // 收尾：模型与栈都还有内容，确认不是「一路 clear 到底」的假对拍。
  assert_true(stack.depth() > 0, msg="500 步之后栈不应为空")
}
