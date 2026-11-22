// 账户值类型的测试。

///|
test "account info empty 的三项口径" {
  let e = @state.AccountInfo::empty()
  assert_true(e.is_empty())
  assert_eq(e.nonce, 0UL)
  assert_true(e.balance.is_zero())
  assert_eq(e.code.length(), 0)
  // 任一项非零都不再是 empty
  let by_nonce : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::zero(),
    code: b"",
  }
  assert_true(!by_nonce.is_empty())
  let by_balance : @state.AccountInfo = {
    nonce: 0UL,
    balance: @types.U256::one(),
    code: b"",
  }
  assert_true(!by_balance.is_empty())
  let by_code : @state.AccountInfo = {
    nonce: 0UL,
    balance: @types.U256::zero(),
    code: b"\x00",
  }
  assert_true(!by_code.is_empty())
}

///|
test "account info same 逐字段比较" {
  let a : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::one(),
    code: b"\x01\x02",
  }
  let b : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::one(),
    code: b"\x01\x02",
  }
  assert_true(a.same(b))
  assert_true(a.same(a))
  let other_nonce : @state.AccountInfo = {
    nonce: 2UL,
    balance: @types.U256::one(),
    code: b"\x01\x02",
  }
  assert_true(!a.same(other_nonce))
  let other_balance : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::zero(),
    code: b"\x01\x02",
  }
  assert_true(!a.same(other_balance))
  let other_code : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::one(),
    code: b"\x01\x03",
  }
  assert_true(!a.same(other_code))
  // 长度不同也算不同
  let short_code : @state.AccountInfo = {
    nonce: 1UL,
    balance: @types.U256::one(),
    code: b"\x01",
  }
  assert_true(!a.same(short_code))
}

///|
test "account entry same 对顺序敏感" {
  let a : @state.AccountEntry = {
    address: @types.Address::zero(),
    info: @state.AccountInfo::empty(),
    storage: [(@types.U256::one(), @types.U256::from_u64(2UL))],
  }
  let same : @state.AccountEntry = {
    address: @types.Address::zero(),
    info: @state.AccountInfo::empty(),
    storage: [(@types.U256::one(), @types.U256::from_u64(2UL))],
  }
  assert_true(a.same(same))
  let different_key : @state.AccountEntry = {
    address: @types.Address::zero(),
    info: @state.AccountInfo::empty(),
    storage: [(@types.U256::from_u64(3UL), @types.U256::from_u64(2UL))],
  }
  assert_true(!a.same(different_key))
  let longer : @state.AccountEntry = {
    address: @types.Address::zero(),
    info: @state.AccountInfo::empty(),
    storage: [
      (@types.U256::one(), @types.U256::from_u64(2UL)),
      (@types.U256::from_u64(3UL), @types.U256::from_u64(4UL)),
    ],
  }
  assert_true(!a.same(longer))
}
