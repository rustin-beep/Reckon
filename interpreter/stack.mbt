// EVM 栈：1024 项深度上限，扁平 4×UInt64 布局。
//
// 布局：`data` 长 `1024 * 4`，第 i 项（从栈底 0 起）占 `data[4i .. 4i+3]`，
// limb 小端（`l0` 最低位）；`sp` 是项数，栈顶是第 `sp - 1` 项。
//
// 两条不变量，测试逐条覆盖：
//
// 1. **原子性**：每个错误分支都先校验、后写入；抛错时 `sp` 与已有项的 limb
//    都不变，调用方可以继续用这个栈。
// 2. **两套接口同语义**：公开的 `U256` 便利接口与包内 `*_limbs` 快路径是同一
//    份语义的两种入口，逐 limb 一致；后者供 C05/C14 绕开 `U256` 对象构造。
//
// `data` / `sp` 是 `priv`：`pub struct` 的普通字段在包外可读，不封住就等于把
// 裸 `FixedArray` 交出去。

///|
/// 深度上限。
let stack_limit : Int32 = 1024

///|
/// `Int32` 上界。`Underflow(needed=depth+1, …)` 里的 `+1` 只在 `depth` 取到
/// 这个值时才会溢出，此时饱和到上界，宁可少一不给出负的项数。
let int32_max : Int32 = 2147483647

///|
/// 栈操作错误。
///
/// C04 把它映射成 EVM 的 exceptional halt；这里只负责报出可供判定的三类事实，
/// 不定义 halt 本身。
#derive(Debug)
pub suberror StackError {
  /// 项数不足。`needed` 是这次操作要求的最小项数，`available` 是当前 `sp`。
  Underflow(needed~ : Int32, available~ : Int32)
  /// 超过深度上限。
  Overflow(limit~ : Int32)
  /// 深度参数非法：`peek` 从 0 起算，`dup` / `swap` 从 1 起算。
  InvalidDepth(depth~ : Int32)
}

///|
pub extend StackError with Debug::{to_repr}

///|
/// 稳定的人类可读文本，供 C04/C15 的失败输出直接引用（不做本地化分发）。
pub impl Show for StackError with fn to_string(self) -> String {
  match self {
    Underflow(needed~, available~) =>
      "栈下溢：需要 \{needed} 项，当前 \{available} 项"
    Overflow(limit~) => "栈上溢：上限 \{limit} 项"
    InvalidDepth(depth~) => "非法深度：\{depth}"
  }
}

///|
/// 让 `err.to_string()` 在包外可用（`impl` 的方法不会自动提升成普通函数）。
pub extend StackError with Show::{to_string}

///|
/// EVM 栈。`data` 只在构造时分配一次，push/pop 不再分配（返回 `U256` 时会构造一个
/// 值对象，快路径不走这里）。
pub struct Stack {
  /// 1024 项 × 4 limb，扁平存放。
  priv data : FixedArray[UInt64]
  /// 当前项数（`0..=1024`）。
  priv mut sp : Int32
}

// ---------------------------------------------------------------------------
// 构造与读接口
// ---------------------------------------------------------------------------

///|
pub fn Stack::new() -> Stack {
  { data: FixedArray::make(stack_limit * 4, 0UL), sp: 0, }
}

///|
/// 深度上限（1024），与具体实例无关。
pub fn Stack::limit() -> Int32 {
  stack_limit
}

///|
pub fn Stack::depth(self : Stack) -> Int32 {
  self.sp
}

///|
pub fn Stack::is_empty(self : Stack) -> Bool {
  self.sp == 0
}

///|
pub fn Stack::is_full(self : Stack) -> Bool {
  self.sp >= stack_limit
}

///|
/// 清空：只把 `sp` 置 0。旧 limb 不擦除——`sp` 归零后公开接口读不到它们。
pub fn Stack::clear(self : Stack) -> Unit {
  self.sp = 0
}

///|
/// 读栈顶往下第 `depth` 项（0 = 栈顶），不改栈。
pub fn Stack::peek(self : Stack, depth : Int32) -> @types.U256 raise StackError {
  let (l0, l1, l2, l3) = self.peek_limbs(depth)
  @types.U256::from_limbs(l0, l1, l2, l3)
}

// ---------------------------------------------------------------------------
// 写接口
// ---------------------------------------------------------------------------

///|
pub fn Stack::push(self : Stack, value : @types.U256) -> Unit raise StackError {
  self.push_limbs(value.l0, value.l1, value.l2, value.l3)
}

///|
/// 弹出栈顶并返回。
pub fn Stack::pop(self : Stack) -> @types.U256 raise StackError {
  let (l0, l1, l2, l3) = self.pop_limbs()
  @types.U256::from_limbs(l0, l1, l2, l3)
}

///|
/// POP：丢弃栈顶，不读 limb。
pub fn Stack::drop(self : Stack) -> Unit raise StackError {
  if self.sp == 0 {
    raise StackError::Underflow(needed=1, available=0)
  }
  self.sp = self.sp - 1
}

///|
/// 覆盖栈顶。
pub fn Stack::set_top(
  self : Stack,
  value : @types.U256,
) -> Unit raise StackError {
  self.set_top_limbs(value.l0, value.l1, value.l2, value.l3)
}

///|
/// DUPn：把栈顶往下第 `depth` 项（1 = 栈顶）复制到栈顶，深度 +1。
pub fn Stack::dup(self : Stack, depth : Int32) -> Unit raise StackError {
  if depth < 1 {
    raise StackError::InvalidDepth(depth~)
  }
  if depth > self.sp {
    raise StackError::Underflow(needed=depth, available=self.sp)
  }
  if self.sp >= stack_limit {
    raise StackError::Overflow(limit=stack_limit)
  }
  let src = (self.sp - depth) * 4
  let dst = self.sp * 4
  self.data[dst] = self.data[src]
  self.data[dst + 1] = self.data[src + 1]
  self.data[dst + 2] = self.data[src + 2]
  self.data[dst + 3] = self.data[src + 3]
  self.sp = self.sp + 1
}

///|
/// SWAPn：交换栈顶与栈顶往下第 `depth` 项（1 = 顶下第一项），深度不变。
pub fn Stack::swap(self : Stack, depth : Int32) -> Unit raise StackError {
  if depth < 1 {
    raise StackError::InvalidDepth(depth~)
  }
  if depth >= self.sp {
    raise StackError::Underflow(
      needed=saturating_plus_one(depth),
      available=self.sp,
    )
  }
  let top = (self.sp - 1) * 4
  let other = top - depth * 4
  let t0 = self.data[top]
  let t1 = self.data[top + 1]
  let t2 = self.data[top + 2]
  let t3 = self.data[top + 3]
  self.data[top] = self.data[other]
  self.data[top + 1] = self.data[other + 1]
  self.data[top + 2] = self.data[other + 2]
  self.data[top + 3] = self.data[other + 3]
  self.data[other] = t0
  self.data[other + 1] = t1
  self.data[other + 2] = t2
  self.data[other + 3] = t3
}

// ---------------------------------------------------------------------------
// 包内 limb 快路径（不导出：`moon info` 里不出现）
// ---------------------------------------------------------------------------
//
// C05/C14 的算术与位运算直接读写 limb，避免每个操作都构造一个 `U256`。
// 语义与上面的 U256 接口逐条一致，白盒测试双向对拍。

///|
fn saturating_plus_one(depth : Int32) -> Int32 {
  if depth == int32_max {
    depth
  } else {
    depth + 1
  }
}

///|
fn Stack::push_limbs(
  self : Stack,
  l0 : UInt64,
  l1 : UInt64,
  l2 : UInt64,
  l3 : UInt64,
) -> Unit raise StackError {
  if self.sp >= stack_limit {
    raise StackError::Overflow(limit=stack_limit)
  }
  let base = self.sp * 4
  self.data[base] = l0
  self.data[base + 1] = l1
  self.data[base + 2] = l2
  self.data[base + 3] = l3
  self.sp = self.sp + 1
}

///|
fn Stack::pop_limbs(
  self : Stack,
) -> (UInt64, UInt64, UInt64, UInt64) raise StackError {
  if self.sp == 0 {
    raise StackError::Underflow(needed=1, available=0)
  }
  let base = (self.sp - 1) * 4
  let out = (
    self.data[base],
    self.data[base + 1],
    self.data[base + 2],
    self.data[base + 3],
  )
  self.sp = self.sp - 1
  out
}

///|
fn Stack::peek_limbs(
  self : Stack,
  depth : Int32,
) -> (UInt64, UInt64, UInt64, UInt64) raise StackError {
  if depth < 0 {
    raise StackError::InvalidDepth(depth~)
  }
  if depth >= self.sp {
    raise StackError::Underflow(
      needed=saturating_plus_one(depth),
      available=self.sp,
    )
  }
  // 边界已经校验过，这里走标量快路径 `item_limb`。
  let item = self.sp - 1 - depth
  (
    self.item_limb(item, 0),
    self.item_limb(item, 1),
    self.item_limb(item, 2),
    self.item_limb(item, 3),
  )
}

///|
fn Stack::set_top_limbs(
  self : Stack,
  l0 : UInt64,
  l1 : UInt64,
  l2 : UInt64,
  l3 : UInt64,
) -> Unit raise StackError {
  if self.sp == 0 {
    raise StackError::Underflow(needed=1, available=0)
  }
  let item = self.sp - 1
  self.set_item_limb(item, 0, l0)
  self.set_item_limb(item, 1, l1)
  self.set_item_limb(item, 2, l2)
  self.set_item_limb(item, 3, l3)
}

///|
/// 读第 `item` 项的 limb。
///
/// **调用前提**（不做运行期校验，越界由 `FixedArray` 的边界检查兜底）：
/// `0 <= item < sp`、`0 <= limb < 4`。只给包内已经校验过索引的调用方用。
fn Stack::item_limb(self : Stack, item : Int32, limb : Int32) -> UInt64 {
  self.data[item * 4 + limb]
}

///|
/// 写第 `item` 项的 limb。调用前提同 `item_limb`。
fn Stack::set_item_limb(
  self : Stack,
  item : Int32,
  limb : Int32,
  value : UInt64,
) -> Unit {
  self.data[item * 4 + limb] = value
}
