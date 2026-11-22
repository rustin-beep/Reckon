// `State::diff` 的语义（黑盒）。helper 在 state_test.mbt。

///|
fn info_of(x : @state.AccountInfo?) -> @state.AccountInfo {
  match x {
    Some(info) => info
    None => abort("expected Some(AccountInfo)")
  }
}

///|
fn slot_value(x : @types.U256?) -> @types.U256 {
  match x {
    Some(v) => v
    None => abort("expected Some(U256)")
  }
}

///|
test "diff 无变化为空" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [(1UL, 7UL)])])
  let d = s.diff()
  assert_true(d.is_empty())
  assert_eq(d.length(), 0)
  // 写回原值也不算变化
  s.set_balance(a, u(100))
  s.set_storage(a, u(1), u(7))
  assert_true(s.diff().is_empty())
}

///|
test "diff 三字段各自出现" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [])])
  s.set_balance(a, u(5))
  let d = s.diff()
  assert_eq(d.length(), 1)
  assert_eq(d.accounts[0].address, a)
  assert_eq(info_of(d.accounts[0].before).balance, u(100))
  assert_eq(info_of(d.accounts[0].after).balance, u(5))
  assert_eq(d.accounts[0].storage.length(), 0)

  let s2 = @state.State::from_accounts([mk_entry(a, 3, 100, [])])
  s2.set_nonce(a, 4UL)
  let d2 = s2.diff()
  assert_eq(d2.length(), 1)
  assert_eq(info_of(d2.accounts[0].before).nonce, 3UL)
  assert_eq(info_of(d2.accounts[0].after).nonce, 4UL)

  let s3 = @state.State::from_accounts([mk_entry(a, 3, 100, [])])
  s3.set_code(a, b"\x60\x00")
  let d3 = s3.diff()
  assert_eq(d3.length(), 1)
  assert_eq(info_of(d3.accounts[0].before).code.length(), 0)
  assert_eq(info_of(d3.accounts[0].after).code.length(), 2)
}

///|
test "diff 仅槽变化仍出现" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [(1UL, 7UL)])])
  s.set_storage(a, u(1), u(9))
  let d = s.diff()
  assert_eq(d.length(), 1)
  // before/after 的账户字段可以相等
  assert_true(info_of(d.accounts[0].before).same(info_of(d.accounts[0].after)))
  assert_eq(d.accounts[0].storage.length(), 1)
  assert_eq(slot_value(d.accounts[0].storage[0].before), u(7))
  assert_eq(slot_value(d.accounts[0].storage[0].after), u(9))
}

///|
test "diff 新槽与清槽的 None 语义" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 0, [(1UL, 7UL)])])
  s.set_storage(a, u(2), u(8)) // 新槽
  s.set_storage(a, u(1), u(0)) // 清槽
  let d = s.diff()
  assert_eq(d.length(), 1)
  assert_eq(d.accounts[0].storage.length(), 2)
  // 按 key 升序：先 1（清空）后 2（新写）
  assert_eq(d.accounts[0].storage[0].key, u(1))
  assert_eq(slot_value(d.accounts[0].storage[0].before), u(7))
  assert_true(d.accounts[0].storage[0].after is None)
  assert_eq(d.accounts[0].storage[1].key, u(2))
  assert_true(d.accounts[0].storage[1].before is None)
  assert_eq(slot_value(d.accounts[0].storage[1].after), u(8))
}

///|
test "diff 创建账户" {
  let a = addr(1)
  let s = @state.State::from_accounts([])
  s.set_nonce(a, 1UL)
  s.set_storage(a, u(1), u(2))
  let d = s.diff()
  assert_eq(d.length(), 1)
  assert_true(d.accounts[0].before is None)
  let after = info_of(d.accounts[0].after)
  assert_eq(after.nonce, 1UL)
  assert_eq(d.accounts[0].storage.length(), 1)
  assert_true(d.accounts[0].storage[0].before is None)
  assert_eq(slot_value(d.accounts[0].storage[0].after), u(2))
}

///|
test "diff 销毁账户" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [(1UL, 7UL)])])
  s.destroy_account(a)
  let d = s.diff()
  assert_eq(d.length(), 1)
  assert_eq(info_of(d.accounts[0].before).nonce, 3UL)
  assert_true(d.accounts[0].after is None)
  assert_eq(d.accounts[0].storage.length(), 1)
  assert_eq(slot_value(d.accounts[0].storage[0].before), u(7))
  assert_true(d.accounts[0].storage[0].after is None)
}

///|
test "diff 写空账户等于删除" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 5, [(1UL, 7UL)])])
  s.set_nonce(a, 0UL)
  s.set_balance(a, u(0))
  s.set_storage(a, u(1), u(0))
  let d = s.diff()
  assert_eq(d.length(), 1)
  assert_true(d.accounts[0].after is None)
  assert_eq(info_of(d.accounts[0].before).balance, u(5))
  // 写空后的账户不导出
  assert_eq(s.accounts().length(), 0)
}

///|
test "diff 创建空账户不出现" {
  let s = @state.State::new()
  s.create_account(addr(1))
  s.set_balance(addr(2), u(0))
  s.set_storage(addr(3), u(1), u(0))
  assert_true(s.diff().is_empty())
  assert_eq(s.accounts().length(), 0)
}

///|
test "diff 排序与 U256 全域键序" {
  let hi = @types.U256::max_value()
  let s = @state.State::from_accounts([])
  s.set_nonce(addr(3), 1UL)
  s.set_nonce(addr(1), 1UL)
  s.set_nonce(addr(2), 1UL)
  s.set_storage(addr(1), hi, u(1))
  s.set_storage(addr(1), u(1), u(2))
  let d = s.diff()
  assert_eq(d.length(), 3)
  assert_eq(d.accounts[0].address, addr(1))
  assert_eq(d.accounts[1].address, addr(2))
  assert_eq(d.accounts[2].address, addr(3))
  assert_eq(d.accounts[0].storage.length(), 2)
  assert_eq(d.accounts[0].storage[0].key, u(1))
  assert_eq(d.accounts[0].storage[1].key, hi)
}

///|
test "diff 先改后回滚可抵消" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 100, [(1UL, 7UL)])])
  let snap = s.snapshot()
  s.set_balance(a, u(1))
  s.set_storage(a, u(2), u(2))
  s.revert(snap)
  assert_true(s.diff().is_empty())
}
