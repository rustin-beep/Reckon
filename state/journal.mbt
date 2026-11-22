// 变更日志与快照句柄。
//
// 日志只记「回滚所需的最小信息」：被覆盖前的旧值，或整账户的旧内容。回滚按
// **逆序**撤销，所以创建与销毁能自然配对（先撤销后写入的值，再撤销账户本身）。
//
// C09 会在这里追加 warm/cold、transient、refund、selfdestruct 的分支；因此日志
// 用 enum，不用字符串或闭包——新增分支时编译器会逼着把 `undo` 补全。

///|
/// 一条变更记录。
enum Change {
  /// 余额被覆盖，`before` 是覆盖前的值。
  BalanceSet(address~ : @types.Address, before~ : @types.U256)
  /// nonce 被覆盖。
  NonceSet(address~ : @types.Address, before~ : UInt64)
  /// code 被覆盖。
  CodeSet(address~ : @types.Address, before~ : Bytes)
  /// 单个槽被覆盖；`before` 为 0 表示写入前该槽不存在。
  SlotSet(address~ : @types.Address, key~ : @types.U256, before~ : @types.U256)
  /// 账户因写入而隐式创建（回滚时整账户消失）。
  AccountOpened(address~ : @types.Address)
  /// 账户被销毁；`info` 与 `slots` 是销毁前的完整内容，供回滚重建。
  AccountClosed(
    address~ : @types.Address,
    info~ : AccountInfo,
    slots~ : Array[(@types.U256, @types.U256)],
  )
}

///|
/// 快照 id 的全局分配器。
///
/// 句柄必须**只对产生它的 `State` 有效**：id 在进程内唯一，外来句柄在本实例的
/// 快照栈里必然找不到，`revert` 直接走 `InvalidSnapshot`。若按实例从 0 起发号，
/// 两个 `State` 的首个句柄会撞号，异实例 `revert` 就会静默回滚错误的数据（甚至
/// 只毁掉对方的快照栈而不报错）。
priv struct SnapshotIds {
  mut next : UInt64
}

///|
let snapshot_ids : SnapshotIds = { next: 0UL, }

///|
fn next_snapshot_id() -> UInt64 {
  let id = snapshot_ids.next
  snapshot_ids.next = id + 1UL
  id
}

///|
/// 快照句柄。字段私有：只能由 `State::snapshot` 产生（外部无法伪造），
/// 且 id 全局唯一，因此只对产生它的那个 `State` 有效。
pub struct Snapshot {
  priv id : UInt64
}

///|
/// 快照栈里的一项：句柄 id + 当时的日志长度。
struct SnapshotMark {
  id : UInt64
  journal_len : Int32
}

///|
/// 撤销一条变更。
///
/// 前提：调用方已按逆序处理日志（`revert` 从尾部往前弹），因此撤销
/// `AccountOpened` 时，该账户上后续写入的日志条目都已经撤销完毕。
fn State::undo(self : State, change : Change) -> Unit {
  match change {
    BalanceSet(address~, before~) => {
      let rec = self.current.at(address)
      rec.balance = before
      self.current.set(address, rec)
    }
    NonceSet(address~, before~) => {
      let rec = self.current.at(address)
      rec.nonce = before
      self.current.set(address, rec)
    }
    CodeSet(address~, before~) => {
      let rec = self.current.at(address)
      rec.code = before
      self.current.set(address, rec)
    }
    SlotSet(address~, key~, before~) => {
      let rec = self.current.at(address)
      if before.is_zero() {
        rec.storage.remove(key)
      } else {
        rec.storage.set(key, before)
      }
      self.current.set(address, rec)
    }
    AccountOpened(address~) => self.current.remove(address)
    AccountClosed(address~, info~, slots~) => {
      let rec = rec_of(info)
      for i in 0..<slots.length() {
        let (key, value) = slots[i]
        if !value.is_zero() {
          rec.storage.set(key, value)
        }
      }
      self.current.set(address, rec)
    }
  }
}
