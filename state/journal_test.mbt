// 快照 / 回滚语义（黑盒）。helper（`addr` / `u` / `mk_entry`）在 state_test.mbt。

///|
fn expect_invalid(f : () -> Unit raise @state.StateError) -> Unit raise {
  try f() catch {
    @state.StateError::InvalidSnapshot => ()
    _ => fail("expected InvalidSnapshot")
  } noraise {
    _ => fail("expected InvalidSnapshot")
  }
}

///|
test "revert 恢复 balance" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 100, [])])
  let snap = s.snapshot()
  s.set_balance(a, u(999))
  assert_eq(s.basic(a).balance, u(999))
  s.revert(snap)
  assert_eq(s.basic(a).balance, u(100))
}

///|
test "revert 恢复 nonce" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 7, 0, [])])
  let snap = s.snapshot()
  s.set_nonce(a, 8UL)
  assert_eq(s.basic(a).nonce, 8UL)
  s.revert(snap)
  assert_eq(s.basic(a).nonce, 7UL)
}

///|
test "revert 恢复 code" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 0, [])])
  let snap = s.snapshot()
  s.set_code(a, b"\x60\x00")
  assert_eq(s.code(a).length(), 2)
  s.revert(snap)
  assert_eq(s.code(a).length(), 0)
  // 已有代码时回滚到旧代码
  s.set_code(a, b"\x60\x01")
  let snap2 = s.snapshot()
  s.set_code(a, b"\x60\x02")
  s.revert(snap2)
  assert_true(s.code(a) == b"\x60\x01")
}

///|
test "revert 恢复槽：新增/覆盖/清零" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.set_storage(a, u(1), u(9)) // 覆盖
  s.set_storage(a, u(2), u(3)) // 新增
  s.set_storage(a, u(1), u(0)) // 清零
  assert_true(s.storage(a, u(1)).is_zero())
  assert_eq(s.storage(a, u(2)), u(3))
  s.revert(snap)
  assert_eq(s.storage(a, u(1)), u(7))
  assert_true(s.storage(a, u(2)).is_zero())
  assert_eq(s.accounts()[0].storage.length(), 1)
}

///|
test "revert 同一账户多字段多次写" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 100, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.set_balance(a, u(1))
  s.set_balance(a, u(2))
  s.set_nonce(a, 5UL)
  s.set_code(a, b"\xff")
  s.set_storage(a, u(1), u(70))
  s.set_storage(a, u(1), u(71))
  s.revert(snap)
  assert_eq(s.basic(a).balance, u(100))
  assert_eq(s.basic(a).nonce, 1UL)
  assert_eq(s.code(a).length(), 0)
  assert_eq(s.storage(a, u(1)), u(7))
  assert_eq(s.accounts()[0].storage.length(), 1)
}

///|
test "revert 撤销隐式创建" {
  let a = addr(1)
  let s = @state.State::new()
  let snap = s.snapshot()
  s.set_balance(a, u(10))
  s.set_storage(a, u(1), u(2))
  assert_true(s.exists(a))
  s.revert(snap)
  assert_true(!s.exists(a))
  assert_eq(s.accounts().length(), 0)
  assert_true(s.basic(a).is_empty())
  assert_true(s.storage(a, u(1)).is_zero())
}

///|
test "revert 恢复被销毁的账户" {
  let a = addr(1)
  let s = @state.State::from_accounts([
    mk_entry(a, 3, 100, [(1UL, 7UL), (2UL, 8UL)]),
  ])
  s.set_code(a, b"\x60\x01")
  let snap = s.snapshot()
  s.destroy_account(a)
  assert_true(!s.exists(a))
  s.revert(snap)
  assert_true(s.exists(a))
  assert_eq(s.basic(a).nonce, 3UL)
  assert_eq(s.basic(a).balance, u(100))
  assert_true(s.code(a) == b"\x60\x01")
  assert_eq(s.storage(a, u(1)), u(7))
  assert_eq(s.storage(a, u(2)), u(8))
  assert_eq(s.accounts()[0].storage.length(), 2)
}

///|
test "revert 嵌套快照 LIFO" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 100, [])])
  let snap_a = s.snapshot()
  s.set_balance(a, u(1))
  let snap_b = s.snapshot()
  s.set_balance(a, u(2))
  s.set_nonce(a, 5UL)
  // 回滚 B：只剩 A 之后的写入
  s.revert(snap_b)
  assert_eq(s.basic(a).balance, u(1))
  assert_eq(s.basic(a).nonce, 0UL)
  // A 之后继续写，再回滚 A：回到初始
  s.set_balance(a, u(3))
  s.set_storage(a, u(1), u(4))
  s.revert(snap_a)
  assert_eq(s.basic(a).balance, u(100))
  assert_true(s.storage(a, u(1)).is_zero())
}

///|
test "revert 失效快照与重复回滚" {
  let s = @state.State::new()
  let a = addr(1)
  let snap_a = s.snapshot()
  let snap_b = s.snapshot()
  s.set_balance(a, u(1))
  s.revert(snap_b)
  // 同一句柄回滚两次
  expect_invalid(() => s.revert(snap_b))
  // 回滚到更早的快照后，晚的句柄一律失效
  s.revert(snap_a)
  expect_invalid(() => s.revert(snap_b))
  expect_invalid(() => s.revert(snap_a))
}

///|
test "revert 拒绝另一个 State 的快照" {
  // 两个实例各拍一个快照：若 id 按实例从 0 起，两边会撞号
  let a = addr(1)
  let s1 = @state.State::new()
  let s2 = @state.State::new()
  let foreign = s1.snapshot()
  let own = s2.snapshot()
  s2.set_balance(a, u(7))
  expect_invalid(() => s2.revert(foreign))
  // 外来句柄不得改动本实例的数据，也不得弹掉本实例的快照
  assert_eq(s2.basic(a).balance, u(7))
  s2.revert(own)
  assert_eq(s2.basic(a).balance, u(0))
  assert_true(!s2.exists(a))
}

///|
test "revert 深句柄（journal_len 更大）也不损坏本实例" {
  let a = addr(1)
  let s1 = @state.State::new()
  let s2 = @state.State::new()
  // 外来句柄的 journal_len 比本实例整条日志还长
  s1.set_balance(a, u(1))
  s1.set_nonce(a, 1UL)
  s1.set_storage(a, u(1), u(1))
  let deep = s1.snapshot()
  let own = s2.snapshot()
  s2.set_balance(a, u(9))
  expect_invalid(() => s2.revert(deep))
  assert_eq(s2.basic(a).balance, u(9))
  assert_eq(s2.accounts().length(), 1)
  // 本实例自己的句柄仍然能用
  s2.revert(own)
  assert_eq(s2.basic(a).balance, u(0))
  assert_true(!s2.exists(a))
}

///|
test "两个 State 的合法快照互不干扰" {
  let a = addr(1)
  let s1 = @state.State::new()
  let s2 = @state.State::new()
  let k1 = s1.snapshot()
  let k2 = s2.snapshot()
  s1.set_balance(a, u(1))
  s2.set_balance(a, u(2))
  s2.revert(k2)
  assert_eq(s2.basic(a).balance, u(0))
  assert_eq(s1.basic(a).balance, u(1))
  s1.revert(k1)
  assert_eq(s1.basic(a).balance, u(0))
}

///|
test "revert 空快照是 no-op" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 100, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.revert(snap)
  assert_eq(s.basic(a).nonce, 1UL)
  assert_eq(s.basic(a).balance, u(100))
  assert_eq(s.storage(a, u(1)), u(7))
  assert_eq(s.accounts().length(), 1)
}

///|
test "revert 不影响 base 与 original_storage" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.set_storage(a, u(1), u(9))
  s.set_storage(a, u(2), u(5))
  s.revert(snap)
  assert_eq(s.original_storage(a, u(1)), u(7))
  assert_true(s.original_storage(a, u(2)).is_zero())
  // 跨快照反复写，original 恒定
  for _ in 0..<3 {
    let inner = s.snapshot()
    s.set_storage(a, u(1), u(70))
    s.revert(inner)
    assert_eq(s.original_storage(a, u(1)), u(7))
  }
}

///|
test "revert 销毁后重建再回滚" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.destroy_account(a)
  s.create_account(a)
  s.set_nonce(a, 9UL)
  assert_eq(s.basic(a).nonce, 9UL)
  assert_true(s.storage(a, u(1)).is_zero())
  s.revert(snap)
  assert_eq(s.basic(a).nonce, 3UL)
  assert_eq(s.storage(a, u(1)), u(7))
}
