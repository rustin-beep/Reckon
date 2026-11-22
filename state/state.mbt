// 内存状态模型：账户集合 + 变更日志 + 快照栈。
//
// 一个 `State` 对应一笔交易的执行上下文：
//
// - `base` 在构造后冻结，只供 `original_storage`（EIP-2200 的原始值）与
//   `diff`（相对初始状态的账户级差异）读取；
// - `current` 承载本笔交易的全部写入；
// - `journal` 记旧值，`snapshots` 记日志长度，回滚就是按逆序撤销一段日志。
//
// 不做 MPT / state root / code hash 缓存；不做 warm/cold、transient、refund、
// EIP-6780 的判定（C09）。

///|
/// 状态读写的错误。
#derive(Debug)
pub suberror StateError {
  /// 构造时同一地址出现了两次。
  DuplicateAccount(address~ : @types.Address)
  /// 构造时同一账户的同一槽出现了两次。
  DuplicateStorageKey(address~ : @types.Address, key~ : @types.U256)
  /// 快照句柄已失效：已被更早的回滚作废，或已经回滚过一次。
  InvalidSnapshot
}

///|
pub extend StateError with Debug::{to_repr}

///|
/// 账户的内部形态。
///
/// 字段拆开存（而不是存一个 `AccountInfo`），这样读接口每次都能返回一份新的
/// 值对象，调用方改自己的副本不会影响 `State`。`storage` 只含非零槽——这是
/// 全包的不变量，写入、回滚、构造都维持它。
struct Rec {
  mut nonce : UInt64
  mut balance : @types.U256
  mut code : Bytes
  storage : Map[@types.U256, @types.U256]
}

///|
fn rec_empty() -> Rec {
  { nonce: 0UL, balance: @types.U256::zero(), code: b"", storage: Map([]), }
}

///|
fn rec_of(info : AccountInfo) -> Rec {
  {
    nonce: info.nonce,
    balance: info.balance,
    code: info.code,
    storage: Map([]),
  }
}

///|
fn rec_info(rec : Rec) -> AccountInfo {
  { nonce: rec.nonce, balance: rec.balance, code: rec.code, }
}

///|
/// canonical 的「不存在」判定：nonce/balance/code 全零且没有任何槽。
fn rec_is_empty(rec : Rec) -> Bool {
  rec.nonce == 0UL &&
  rec.balance.is_zero() &&
  rec.code.length() == 0 &&
  rec.storage.is_empty()
}

///|
fn copy_slots(
  src : Map[@types.U256, @types.U256],
) -> Map[@types.U256, @types.U256] {
  let dst : Map[@types.U256, @types.U256] = Map([])
  for (key, value) in src.iter() {
    dst.set(key, value)
  }
  dst
}

///|
fn rec_copy(rec : Rec) -> Rec {
  {
    nonce: rec.nonce,
    balance: rec.balance,
    code: rec.code,
    storage: copy_slots(rec.storage),
  }
}

///|
fn copy_table(src : Map[@types.Address, Rec]) -> Map[@types.Address, Rec] {
  let dst : Map[@types.Address, Rec] = Map([])
  for (address, rec) in src.iter() {
    dst.set(address, rec_copy(rec))
  }
  dst
}

///|
fn rec_slot(rec : Rec, key : @types.U256) -> @types.U256 {
  match rec.storage.get(key) {
    Some(value) => value
    None => @types.U256::zero()
  }
}

///|
fn compare_slot(
  a : (@types.U256, @types.U256),
  b : (@types.U256, @types.U256),
) -> Int32 {
  a.0.compare(b.0)
}

///|
fn compare_entry(a : AccountEntry, b : AccountEntry) -> Int32 {
  a.address.compare(b.address)
}

///|
/// 账户的非零槽，按 key 升序。
fn rec_slots(rec : Rec) -> Array[(@types.U256, @types.U256)] {
  let out : Array[(@types.U256, @types.U256)] = []
  for (key, value) in rec.storage.iter() {
    if !value.is_zero() {
      out.push((key, value))
    }
  }
  out.sort_by(compare_slot)
  out
}

///|
/// 内存状态模型。字段私有：跨包只能走方法。
pub struct State {
  /// 构造时冻结的初始状态。
  priv base : Map[@types.Address, Rec]
  /// 当前状态。
  priv current : Map[@types.Address, Rec]
  /// 变更日志。
  priv journal : Array[Change]
  /// 快照栈（LIFO）。
  priv snapshots : Array[SnapshotMark]
  /// 快照 id 分配器。
  priv mut next_id : Int32
}

///|
/// 空状态：没有账户，base 也为空。
pub fn State::new() -> State {
  { base: Map([]), current: Map([]), journal: [], snapshots: [], next_id: 0, }
}

///|
/// 从初始 alloc 构造。
///
/// 校验：重复地址、同一账户内重复槽。规范化：零值槽丢弃、empty 账户按不存在
/// 处理。深拷贝：`base` 与 `current` 各自持有一份独立的 storage 表，构造完成后
/// 调用方再改传入的数组或 `AccountInfo` 都不影响这个 `State`。
pub fn State::from_accounts(
  entries : Array[AccountEntry],
) -> State raise StateError {
  let base : Map[@types.Address, Rec] = Map([])
  // 重复地址按**输入**判，不看空账户是否被规范化掉：重复本身是调用方 bug。
  let seen_address : Map[@types.Address, Unit] = Map([])
  for i in 0..<entries.length() {
    let entry = entries[i]
    if seen_address.contains(entry.address) {
      raise StateError::DuplicateAccount(address=entry.address)
    }
    seen_address.set(entry.address, ())
    // 重复槽先查、再丢零槽：重复本身是调用方 bug，不该被规范化掩盖。
    let seen : Map[@types.U256, Unit] = Map([])
    let rec = rec_of(entry.info)
    for j in 0..<entry.storage.length() {
      let (key, value) = entry.storage[j]
      if seen.contains(key) {
        raise StateError::DuplicateStorageKey(address=entry.address, key~)
      }
      seen.set(key, ())
      if !value.is_zero() {
        rec.storage.set(key, value)
      }
    }
    if !rec_is_empty(rec) {
      base.set(entry.address, rec)
    }
  }
  { base, current: copy_table(base), journal: [], snapshots: [], next_id: 0, }
}

// ---------------------------------------------------------------------------
// 读
// ---------------------------------------------------------------------------

///|
/// 账户快照；不存在的账户返回全零。
pub fn State::basic(self : State, address : @types.Address) -> AccountInfo {
  match self.current.get(address) {
    Some(rec) => rec_info(rec)
    None => AccountInfo::empty()
  }
}

///|
/// canonical 的存在性：有 nonce、有余额、有代码或有槽，任一成立即存在。
pub fn State::exists(self : State, address : @types.Address) -> Bool {
  match self.current.get(address) {
    Some(rec) => !rec_is_empty(rec)
    None => false
  }
}

///|
/// 完整代码字节；不存在或未部署代码时是空字节串。
pub fn State::code(self : State, address : @types.Address) -> Bytes {
  match self.current.get(address) {
    Some(rec) => rec.code
    None => b""
  }
}

///|
/// 当前槽值；零槽与不存在的账户都返回 0。
pub fn State::storage(
  self : State,
  address : @types.Address,
  slot : @types.U256,
) -> @types.U256 {
  match self.current.get(address) {
    Some(rec) => rec_slot(rec, slot)
    None => @types.U256::zero()
  }
}

///|
/// 相对构造时 base 的原值（EIP-2200 的 original）；构造后新建的账户原值为 0。
pub fn State::original_storage(
  self : State,
  address : @types.Address,
  slot : @types.U256,
) -> @types.U256 {
  match self.base.get(address) {
    Some(rec) => rec_slot(rec, slot)
    None => @types.U256::zero()
  }
}

// ---------------------------------------------------------------------------
// 写
// ---------------------------------------------------------------------------

///|
/// 账户不存在时建一个空账户并记日志；已存在则什么都不做。
///
/// 写接口都先调它，因此「账户不存在时的写先隐式创建」在回滚上表现为
/// `AccountOpened` 让整个账户消失。
fn State::open_if_absent(self : State, address : @types.Address) -> Unit {
  if !self.current.contains(address) {
    self.current.set(address, rec_empty())
    self.journal.push(AccountOpened(address~))
  }
}

///|
pub fn State::set_balance(
  self : State,
  address : @types.Address,
  value : @types.U256,
) -> Unit {
  self.open_if_absent(address)
  let rec = self.current.at(address)
  let before = rec.balance
  if before != value {
    self.journal.push(BalanceSet(address~, before~))
    rec.balance = value
    self.current.set(address, rec)
  }
}

///|
pub fn State::set_nonce(
  self : State,
  address : @types.Address,
  value : UInt64,
) -> Unit {
  self.open_if_absent(address)
  let rec = self.current.at(address)
  let before = rec.nonce
  if before != value {
    self.journal.push(NonceSet(address~, before~))
    rec.nonce = value
    self.current.set(address, rec)
  }
}

///|
pub fn State::set_code(
  self : State,
  address : @types.Address,
  code : Bytes,
) -> Unit {
  self.open_if_absent(address)
  let rec = self.current.at(address)
  let before = rec.code
  if before != code {
    self.journal.push(CodeSet(address~, before~))
    rec.code = code
    self.current.set(address, rec)
  }
}

///|
/// 写槽。`value` 为 0 等价于删除该槽；账户不存在且 `value` 为 0 时是 no-op
/// （不凭空造账户）。
pub fn State::set_storage(
  self : State,
  address : @types.Address,
  slot : @types.U256,
  value : @types.U256,
) -> Unit {
  if !self.current.contains(address) && value.is_zero() {
    return
  }
  self.open_if_absent(address)
  let rec = self.current.at(address)
  let before = rec_slot(rec, slot)
  if before == value {
    return
  }
  self.journal.push(SlotSet(address~, key=slot, before~))
  if value.is_zero() {
    rec.storage.remove(slot)
  } else {
    rec.storage.set(slot, value)
  }
  self.current.set(address, rec)
}

///|
/// 建空账户；已存在则 no-op（CREATE 的地址冲突检查属于 C10/C11）。
pub fn State::create_account(self : State, address : @types.Address) -> Unit {
  self.open_if_absent(address)
}

///|
/// 删除账户；不存在则 no-op。
///
/// EIP-6780 的「仅同 tx 创建才真删」不在本层判定，由 C09 决定何时调用。
pub fn State::destroy_account(self : State, address : @types.Address) -> Unit {
  match self.current.get(address) {
    Some(rec) => {
      self.journal.push(
        AccountClosed(address~, info=rec_info(rec), slots=rec_slots(rec)),
      )
      self.current.remove(address)
    }
    None => ()
  }
}

// ---------------------------------------------------------------------------
// 快照 / 回滚
// ---------------------------------------------------------------------------

///|
/// 压一个快照，返回不透明句柄。
pub fn State::snapshot(self : State) -> Snapshot {
  let id = self.next_id
  self.next_id = id + 1
  self.snapshots.push({ id, journal_len: self.journal.length(), })
  { id, }
}

///|
/// 回滚到该快照之后的所有变更。
///
/// 嵌套快照 LIFO；回滚到某个快照会作废它以及更晚的快照，因此同一句柄不能
/// 回滚第二次，已作废的句柄一律 `InvalidSnapshot`。base 与 `original_storage`
/// 不受影响。
pub fn State::revert(
  self : State,
  snapshot : Snapshot,
) -> Unit raise StateError {
  let mut idx = -1
  for i in 0..<self.snapshots.length() {
    if self.snapshots[i].id == snapshot.id {
      idx = i
      break
    }
  }
  if idx < 0 {
    raise StateError::InvalidSnapshot
  }
  let target = self.snapshots[idx].journal_len
  while self.journal.length() > target {
    let change = self.journal.pop().unwrap()
    self.undo(change)
  }
  // 该快照及其之后的全部作废
  while self.snapshots.length() > idx {
    let _ = self.snapshots.pop()
  }
}

// ---------------------------------------------------------------------------
// canonical 导出
// ---------------------------------------------------------------------------

///|
/// 全量导出：只含非 empty 账户，storage 只含非零槽，账户按地址升序、槽按 key
/// 升序。`Map` 的迭代序不可依赖，这里显式排序，保证逐字节可复现。
pub fn State::accounts(self : State) -> Array[AccountEntry] {
  let out : Array[AccountEntry] = []
  for (address, rec) in self.current.iter() {
    if !rec_is_empty(rec) {
      out.push({ address, info: rec_info(rec), storage: rec_slots(rec), })
    }
  }
  out.sort_by(compare_entry)
  out
}
