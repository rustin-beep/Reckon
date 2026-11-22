// `State` 的读/写/导出测试（黑盒：只用公开 API）。

///|
fn addr(n : Int32) -> @types.Address {
  let bytes = FixedArray::make(20, b'\x00')
  bytes[19] = n.to_byte()
  @types.Address::from_bytes_unchecked(Bytes::from_array(bytes)[:])
}

///|
fn u(n : UInt64) -> @types.U256 {
  @types.U256::from_u64(n)
}

///|
fn mk_entry(
  a : @types.Address,
  nonce : UInt64,
  balance : UInt64,
  slots : Array[(UInt64, UInt64)],
) -> @state.AccountEntry {
  let storage : Array[(@types.U256, @types.U256)] = []
  for i in 0..<slots.length() {
    storage.push((u(slots[i].0), u(slots[i].1)))
  }
  { address: a, info: { nonce, balance: u(balance), code: b"", }, storage, }
}

// ---------------------------------------------------------------------------
// 读
// ---------------------------------------------------------------------------

///|
test "state 不存在账户的读口径" {
  let s = @state.State::new()
  let a = addr(1)
  assert_true(!s.exists(a))
  assert_true(s.basic(a).is_empty())
  assert_eq(s.basic(a).nonce, 0UL)
  assert_true(s.basic(a).balance.is_zero())
  assert_eq(s.code(a).length(), 0)
  assert_true(s.storage(a, u(1)).is_zero())
  assert_true(s.original_storage(a, u(1)).is_zero())
  assert_eq(s.accounts().length(), 0)
}

///|
test "state empty 账户按不存在处理" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [])])
  assert_true(!s.exists(a))
  assert_eq(s.accounts().length(), 0)
  assert_true(s.diff().is_empty())
}

///|
test "state 只靠槽也算存在" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [(1UL, 7UL)])])
  assert_true(s.exists(a))
  assert_eq(s.accounts().length(), 1)
  assert_eq(s.storage(a, u(1)), u(7))
}

///|
test "state from_accounts 深拷贝" {
  let a = addr(1)
  let slots : Array[(@types.U256, @types.U256)] = [(u(1), u(2))]
  let info : @state.AccountInfo = { nonce: 1UL, balance: u(3), code: b"", }
  let entries : Array[@state.AccountEntry] = [
    { address: a, info, storage: slots, },
  ]
  let s = @state.State::from_accounts(entries)
  // 改调用方手里的数组与 AccountInfo：state 必须不受影响
  slots[0] = (u(9), u(9))
  info.nonce = 42UL
  info.balance = u(99)
  assert_eq(s.basic(a).nonce, 1UL)
  assert_eq(s.basic(a).balance, u(3))
  assert_eq(s.storage(a, u(1)), u(2))
  assert_true(s.storage(a, u(9)).is_zero())
  // 反向：写 state 也不能改调用方的数组
  s.set_storage(a, u(2), u(5))
  assert_eq(slots[0].0, u(9))
  assert_eq(slots[0].1, u(9))
  assert_eq(slots.length(), 1)
}

///|
test "state from_accounts 丢弃零槽与 empty 账户" {
  let a = addr(1)
  let b = addr(2)
  let s = @state.State::from_accounts([
    mk_entry(a, 0, 0, [(1UL, 0UL), (2UL, 5UL)]),
    mk_entry(b, 0, 0, [(1UL, 0UL)]),
  ])
  let out = s.accounts()
  assert_eq(out.length(), 1)
  assert_eq(out[0].address, a)
  assert_eq(out[0].storage.length(), 1)
  assert_eq(out[0].storage[0].0, u(2))
  assert_true(!s.exists(b))
}

///|
test "state from_accounts 拒绝重复地址" {
  let entries : Array[@state.AccountEntry] = [
    mk_entry(addr(1), 1, 0, []),
    mk_entry(addr(1), 2, 0, []),
  ]
  try ignore(@state.State::from_accounts(entries)) catch {
    @state.StateError::DuplicateAccount(address~) => assert_eq(address, addr(1))
    _ => fail("expected DuplicateAccount")
  } noraise {
    _ => fail("expected DuplicateAccount")
  }
}

///|
test "state from_accounts 重复地址含空账户也算重复" {
  let entries : Array[@state.AccountEntry] = [
    mk_entry(addr(1), 0, 0, []),
    mk_entry(addr(1), 1, 0, []),
  ]
  try ignore(@state.State::from_accounts(entries)) catch {
    @state.StateError::DuplicateAccount(_) => ()
    _ => fail("expected DuplicateAccount")
  } noraise {
    _ => fail("expected DuplicateAccount")
  }
}

///|
test "state from_accounts 拒绝重复槽" {
  let a = addr(1)
  let entries : Array[@state.AccountEntry] = [
    mk_entry(a, 1, 0, [(1UL, 2UL), (1UL, 3UL)]),
  ]
  try ignore(@state.State::from_accounts(entries)) catch {
    @state.StateError::DuplicateStorageKey(address~, key~) => {
      assert_eq(address, a)
      assert_eq(key, u(1))
    }
    _ => fail("expected DuplicateStorageKey")
  } noraise {
    _ => fail("expected DuplicateStorageKey")
  }
}

///|
test "state from_accounts 先查重复槽再丢零槽" {
  let a = addr(1)
  let entries : Array[@state.AccountEntry] = [
    mk_entry(a, 1, 0, [(1UL, 0UL), (1UL, 3UL)]),
  ]
  try ignore(@state.State::from_accounts(entries)) catch {
    @state.StateError::DuplicateStorageKey(_) => ()
    _ => fail("expected DuplicateStorageKey")
  } noraise {
    _ => fail("expected DuplicateStorageKey")
  }
}

// ---------------------------------------------------------------------------
// 写
// ---------------------------------------------------------------------------

///|
test "state set_balance 隐式创建账户" {
  let s = @state.State::new()
  let a = addr(1)
  s.set_balance(a, u(10))
  assert_true(s.exists(a))
  assert_eq(s.basic(a).balance, u(10))
  s.set_balance(a, u(20))
  assert_eq(s.basic(a).balance, u(20))
}

///|
test "state set_storage 零值不造账户" {
  let s = @state.State::new()
  let a = addr(1)
  s.set_storage(a, u(1), u(0))
  assert_true(!s.exists(a))
  assert_eq(s.accounts().length(), 0)
  s.set_storage(a, u(1), u(5))
  assert_true(s.exists(a))
  assert_eq(s.storage(a, u(1)), u(5))
}

///|
test "state set_storage 清零删除槽" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [(1UL, 7UL)])])
  s.set_storage(a, u(1), u(0))
  assert_true(s.storage(a, u(1)).is_zero())
  // 唯一一个槽清零后账户变成 empty，不再导出
  assert_true(!s.exists(a))
  assert_eq(s.accounts().length(), 0)
}

///|
test "state create_account 已存在时保留内容" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 3, 100, [(1UL, 7UL)])])
  s.create_account(a)
  assert_eq(s.basic(a).nonce, 3UL)
  assert_eq(s.basic(a).balance, u(100))
  assert_eq(s.storage(a, u(1)), u(7))
}

///|
test "state destroy_account 删除与 no-op" {
  let a = addr(1)
  let b = addr(2)
  let s = @state.State::from_accounts([
    mk_entry(a, 3, 100, [(1UL, 7UL)]),
    mk_entry(b, 1, 1, []),
  ])
  s.destroy_account(a)
  assert_true(!s.exists(a))
  assert_eq(s.code(a).length(), 0)
  assert_eq(s.accounts().length(), 1)
  // 不存在时 no-op
  s.destroy_account(a)
  s.destroy_account(addr(9))
  assert_eq(s.accounts().length(), 1)
  assert_eq(s.accounts()[0].address, b)
}

///|
test "state code 返回完整字节" {
  let a = addr(1)
  let s = @state.State::new()
  s.set_code(a, b"\x60\x00\x60\x00")
  assert_eq(s.code(a).length(), 4)
  assert_true(s.code(a) == b"\x60\x00\x60\x00")
  assert_eq(s.basic(a).code.length(), 4)
}

// ---------------------------------------------------------------------------
// original_storage
// ---------------------------------------------------------------------------

///|
test "state original_storage 取构造时 base" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 0, 0, [(1UL, 7UL)])])
  assert_eq(s.original_storage(a, u(1)), u(7))
  s.set_storage(a, u(1), u(9))
  assert_eq(s.storage(a, u(1)), u(9))
  assert_eq(s.original_storage(a, u(1)), u(7))
  // base 里没有的槽原值为 0
  s.set_storage(a, u(2), u(3))
  assert_eq(s.original_storage(a, u(2)), u(0))
  // 构造后新建的账户原值全 0
  let b = addr(2)
  s.set_nonce(b, 1UL)
  s.set_storage(b, u(1), u(4))
  assert_eq(s.original_storage(b, u(1)), u(0))
}

// ---------------------------------------------------------------------------
// accounts()
// ---------------------------------------------------------------------------

///|
test "state accounts 按地址与槽排序" {
  let s = @state.State::from_accounts([
    mk_entry(addr(3), 1, 0, [(5UL, 50UL), (1UL, 10UL)]),
    mk_entry(addr(1), 1, 0, [(9UL, 90UL), (2UL, 20UL)]),
    mk_entry(addr(2), 1, 0, []),
  ])
  let out = s.accounts()
  assert_eq(out.length(), 3)
  assert_eq(out[0].address, addr(1))
  assert_eq(out[1].address, addr(2))
  assert_eq(out[2].address, addr(3))
  assert_eq(out[0].storage.length(), 2)
  assert_eq(out[0].storage[0].0, u(2))
  assert_eq(out[0].storage[1].0, u(9))
  assert_eq(out[2].storage[0].0, u(1))
  assert_eq(out[2].storage[1].0, u(5))
}

///|
test "state accounts 用 U256 全域比较序" {
  let a = addr(1)
  let hi = @types.U256::max_value()
  let mid = @types.U256::one().shl(64)
  let s = @state.State::from_accounts([mk_entry(a, 1, 0, [(0UL, 1UL)])])
  s.set_storage(a, hi, u(1))
  s.set_storage(a, mid, u(1))
  let out = s.accounts()[0].storage
  assert_eq(out.length(), 3)
  assert_true(out[0].0.is_zero())
  assert_eq(out[1].0, mid)
  assert_eq(out[2].0, hi)
}

///|
test "state accounts 写空的账户不导出" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 5, [(1UL, 7UL)])])
  s.set_nonce(a, 0UL)
  s.set_balance(a, u(0))
  s.set_storage(a, u(1), u(0))
  assert_true(!s.exists(a))
  assert_eq(s.accounts().length(), 0)
  assert_true(s.basic(a).is_empty())
}

///|
test "state accounts 每次返回独立副本" {
  let a = addr(1)
  let s = @state.State::from_accounts([mk_entry(a, 1, 0, [(1UL, 7UL)])])
  let first = s.accounts()
  first[0].storage[0] = (u(1), u(99))
  first[0].info.nonce = 77UL
  let second = s.accounts()
  assert_eq(second[0].storage[0].1, u(7))
  assert_eq(second[0].info.nonce, 1UL)
}
