// 账户级 diff：当前状态相对 `State` 构造时 base 的变化。
//
// 口径与 `accounts()` 一致——empty 账户等同不存在，零槽等同无槽，地址与槽都按
// 升序排列，因此 `diff()` 的输出也是逐字节可复现的。
//
// `None` 统一表示「零 / 不存在」：创建账户 `before = None`，删除或写空账户
// `after = None`，清零槽 `after = None`，新写槽 `before = None`。

///|
/// 单个槽的差异。
pub(all) struct StorageDiff {
  key : @types.U256
  before : @types.U256?
  after : @types.U256?
}

///|
/// 单个账户的差异。`before/after` 只比 nonce/balance/code，槽的差异在 `storage`。
pub(all) struct AccountDiff {
  address : @types.Address
  before : AccountInfo?
  after : AccountInfo?
  storage : Array[StorageDiff]
}

///|
/// 一次执行相对初始状态的账户级差异。字段公开，供 B08 直接读取。
pub(all) struct StateDiff {
  accounts : Array[AccountDiff]
}

///|
pub fn StateDiff::is_empty(self : StateDiff) -> Bool {
  self.accounts.length() == 0
}

///|
/// 变化的账户数（不是槽数）。
pub fn StateDiff::length(self : StateDiff) -> Int32 {
  self.accounts.length()
}

///|
fn empty_slots() -> Map[@types.U256, @types.U256] {
  Map([])
}

///|
fn compare_slot_diff(a : StorageDiff, b : StorageDiff) -> Int32 {
  a.key.compare(b.key)
}

///|
fn compare_account_diff(a : AccountDiff, b : AccountDiff) -> Int32 {
  a.address.compare(b.address)
}

///|
/// 逐槽比较两张表，按 key 升序输出真正变了的槽。
fn slot_diff(
  base : Map[@types.U256, @types.U256],
  current : Map[@types.U256, @types.U256],
) -> Array[StorageDiff] {
  let out : Array[StorageDiff] = []
  for (key, before) in base.iter() {
    let after = match current.get(key) {
      Some(value) => value
      None => @types.U256::zero()
    }
    if before != after {
      let b : @types.U256? = if before.is_zero() { None } else { Some(before) }
      let a : @types.U256? = if after.is_zero() { None } else { Some(after) }
      out.push({ key, before: b, after: a, })
    }
  }
  for (key, after) in current.iter() {
    if !base.contains(key) {
      out.push({ key, before: None, after: Some(after), })
    }
  }
  out.sort_by(compare_slot_diff)
  out
}

///|
/// 相对 base 的账户级 diff：只含真正变化的账户。
///
/// - 创建：`before = None`；删除或变成 empty：`after = None`；
/// - 只有槽变化的账户也会出现，此时 `before/after` 可以相等；
/// - base 与 current 都 empty/不存在 → 不出现。
pub fn State::diff(self : State) -> StateDiff {
  let out : Array[AccountDiff] = []
  for (address, current) in self.current.iter() {
    let becomes_empty = rec_is_empty(current)
    match self.base.get(address) {
      None =>
        if !becomes_empty {
          out.push({
            address,
            before: None,
            after: Some(rec_info(current)),
            storage: slot_diff(empty_slots(), current.storage),
          })
        }
      Some(base) => {
        let slots = slot_diff(base.storage, current.storage)
        if becomes_empty {
          out.push({
            address,
            before: Some(rec_info(base)),
            after: None,
            storage: slots,
          })
        } else {
          let before_info = rec_info(base)
          let after_info = rec_info(current)
          if !before_info.same(after_info) || slots.length() > 0 {
            out.push({
              address,
              before: Some(before_info),
              after: Some(after_info),
              storage: slots,
            })
          }
        }
      }
    }
  }
  // base 有、current 里已经没有的账户 = 删除
  for (address, base) in self.base.iter() {
    if !self.current.contains(address) {
      out.push({
        address,
        before: Some(rec_info(base)),
        after: None,
        storage: slot_diff(base.storage, empty_slots()),
      })
    }
  }
  out.sort_by(compare_account_diff)
  { accounts: out, }
}
