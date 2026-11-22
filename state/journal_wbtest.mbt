// 白盒：变更日志长度与快照栈的不变量。
//
// 白盒测试是独立编译单元，helper 要单独定义（不复用 state_test.mbt 的）。

///|
fn waddr(n : Int32) -> @types.Address {
  let bytes = FixedArray::make(20, b'\x00')
  bytes[19] = n.to_byte()
  @types.Address::from_bytes_unchecked(Bytes::from_array(bytes)[:])
}

///|
fn wu(n : UInt64) -> @types.U256 {
  @types.U256::from_u64(n)
}

///|
fn wentry(
  a : @types.Address,
  nonce : UInt64,
  balance : UInt64,
  slots : Array[(UInt64, UInt64)],
) -> AccountEntry {
  let storage : Array[(@types.U256, @types.U256)] = []
  for i in 0..<slots.length() {
    storage.push((wu(slots[i].0), wu(slots[i].1)))
  }
  { address: a, info: { nonce, balance: wu(balance), code: b"", }, storage, }
}

///|
test "journal 初始为空、快照栈为空" {
  let s = State::new()
  assert_eq(s.journal.length(), 0)
  assert_eq(s.snapshots.length(), 0)
  assert_eq(s.base.length(), 0)
  assert_eq(s.current.length(), 0)
}

///|
test "journal 每个写操作一条，隐式创建另记一条" {
  let s = State::new()
  let a = waddr(1)
  s.set_balance(a, wu(1))
  // AccountOpened + BalanceSet
  assert_eq(s.journal.length(), 2)
  s.set_nonce(a, 1UL)
  assert_eq(s.journal.length(), 3)
  s.set_code(a, b"\x01")
  assert_eq(s.journal.length(), 4)
  s.set_storage(a, wu(1), wu(2))
  assert_eq(s.journal.length(), 5)
  // 已存在 → no-op
  s.create_account(a)
  assert_eq(s.journal.length(), 5)
  s.destroy_account(a)
  assert_eq(s.journal.length(), 6)
}

///|
test "journal 跳过 no-op 写" {
  let a = waddr(1)
  let s = State::from_accounts([wentry(a, 3, 100, [(1UL, 7UL)])])
  s.set_balance(a, wu(100))
  s.set_nonce(a, 3UL)
  s.set_storage(a, wu(1), wu(7))
  s.set_storage(a, wu(2), wu(0))
  s.set_storage(waddr(9), wu(1), wu(0))
  assert_eq(s.journal.length(), 0)
  // empty 账户上清零槽也是 no-op
  let b = waddr(2)
  s.create_account(b)
  assert_eq(s.journal.length(), 1)
  s.set_storage(b, wu(1), wu(0))
  assert_eq(s.journal.length(), 1)
}

///|
test "snapshot 记录当时的日志长度" {
  let s = State::new()
  let a = waddr(1)
  s.set_balance(a, wu(1))
  assert_eq(s.journal.length(), 2)
  let snap = s.snapshot()
  assert_eq(s.snapshots.length(), 1)
  assert_eq(s.snapshots[0].journal_len, 2)
  // 句柄 id 与栈内 mark 的 id 必须一致（id 来自全局分配器，不再是 0/1 这样的序号）
  assert_eq(snap.id, s.snapshots[0].id)
  s.set_nonce(a, 1UL)
  assert_eq(s.journal.length(), 3)
  s.revert(snap)
  assert_eq(s.journal.length(), 2)
  assert_eq(s.snapshots.length(), 0)
}

///|
test "revert 把快照栈截断到目标之前" {
  let s = State::new()
  let snap_a = s.snapshot()
  let snap_b = s.snapshot()
  let snap_c = s.snapshot()
  // 全局分配器：同一实例内 id 也严格递增
  assert_true(snap_a.id < snap_b.id)
  assert_true(snap_b.id < snap_c.id)
  assert_eq(s.snapshots.length(), 3)
  s.revert(snap_a)
  assert_eq(s.snapshots.length(), 0)
}

///|
test "base 与 current 不共享记录与 storage" {
  let a = waddr(1)
  let s = State::from_accounts([wentry(a, 3, 100, [(1UL, 7UL)])])
  let base_rec = s.base.get(a).unwrap()
  let current_rec = s.current.get(a).unwrap()
  assert_true(!physical_equal(base_rec, current_rec))
  assert_true(!physical_equal(base_rec.storage, current_rec.storage))
  // 写 current 不动 base
  s.set_storage(a, wu(1), wu(9))
  s.set_balance(a, wu(1))
  assert_eq(s.base.get(a).unwrap().storage.get(wu(1)).unwrap(), wu(7))
  assert_eq(s.base.get(a).unwrap().balance, wu(100))
  assert_eq(s.current.get(a).unwrap().storage.get(wu(1)).unwrap(), wu(9))
}

///|
test "current 的 storage 只存非零槽" {
  let a = waddr(1)
  let s = State::new()
  s.set_storage(a, wu(1), wu(5))
  assert_eq(s.current.get(a).unwrap().storage.length(), 1)
  s.set_storage(a, wu(1), wu(0))
  assert_eq(s.current.get(a).unwrap().storage.length(), 0)
  let snap = s.snapshot()
  s.set_storage(a, wu(2), wu(6))
  s.revert(snap)
  assert_eq(s.current.get(a).unwrap().storage.length(), 0)
}
