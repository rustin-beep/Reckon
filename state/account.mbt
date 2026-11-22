// 账户值类型：账户快照（`AccountInfo`）与 canonical 导出条目（`AccountEntry`）。
//
// 两者都只承载数据、不含策略。empty 判定按 EIP-161 的口径给出，但 `AccountInfo`
// 不带 storage，所以「storage 也为空」这一条只能由 `State` 侧合并判定——
// `AccountInfo::is_empty` 判的是 nonce/balance/code 三项。

///|
/// 账户的三个字段。`code` 存完整字节，不存 `code_hash`。
pub(all) struct AccountInfo {
  mut nonce : UInt64
  mut balance : @types.U256
  mut code : Bytes
}

///|
pub fn AccountInfo::empty() -> AccountInfo {
  { nonce: 0UL, balance: @types.U256::zero(), code: b"", }
}

///|
/// nonce/balance/code 三项全零（EIP-161 的账户级部分）。
pub fn AccountInfo::is_empty(self : AccountInfo) -> Bool {
  self.nonce == 0UL && self.balance.is_zero() && self.code.length() == 0
}

///|
/// 逐字段相等；`code` 比字节内容，不比对象身份。
pub fn AccountInfo::same(self : AccountInfo, other : AccountInfo) -> Bool {
  self.nonce == other.nonce &&
  self.balance == other.balance &&
  self.code == other.code
}

///|
/// `accounts()` 的一行：地址 + 账户快照 + 非零槽（按 key 升序）。
///
/// `storage` 是调用方私有的一份数组，与 `State` 内部存储不共享。
pub(all) struct AccountEntry {
  address : @types.Address
  info : AccountInfo
  storage : Array[(@types.U256, @types.U256)]
}

///|
/// 逐字段相等；`storage` 按给定顺序逐项比较（`accounts()` 的输出已排序）。
pub fn AccountEntry::same(self : AccountEntry, other : AccountEntry) -> Bool {
  if self.address != other.address {
    return false
  }
  if !self.info.same(other.info) {
    return false
  }
  if self.storage.length() != other.storage.length() {
    return false
  }
  for i in 0..<self.storage.length() {
    if self.storage[i].0 != other.storage[i].0 ||
      self.storage[i].1 != other.storage[i].1 {
      return false
    }
  }
  true
}
