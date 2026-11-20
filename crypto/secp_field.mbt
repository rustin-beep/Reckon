// secp256k1 基域 F_p 算术：p = 2^256 - 2^32 - 977，曲线 y^2 = x^3 + 7。
//
// 表示：4×UInt64 limb，小端序（`l0` 最低位），与 `types.U256` 同构。域元素
// 始终保持 canonical（值 < p）；越界输入在解析处直接报错，不做静默取模。
//
// 乘法：MoonBit 的 `UInt64 *` 只给低 64 位，没有 64×64→128 原语，所以把
// 4×64 拆成 8×32 做 8×8 教科书乘法（64 次 32×32 乘法，64 位累加器刚好不溢出），
// 再用 p 的伪梅森形式 `2^256 ≡ 2^32 + 977 (mod p)` 折叠归约。这条路径比
// 4×64 Comba（每对 limb 要 4 次 32×32 再拼 128 位）少一半的进位处理，
// 阶段 0 探针的实测见 B05 报告。
//
// 本文件不做常数时间：所有分支都依赖操作数（见 `secp_ecdsa.mbt` 的说明）。

///|
/// 基域元素，值恒在 `[0, p)`。
#derive(Debug)
struct Fe {
  l0 : UInt64
  l1 : UInt64
  l2 : UInt64
  l3 : UInt64
}

///|
/// 基域模数 p = 2^256 - 2^32 - 977。
let fe_p : Fe = {
  l0: 0xFFFFFFFEFFFFFC2FUL,
  l1: 0xFFFFFFFFFFFFFFFFUL,
  l2: 0xFFFFFFFFFFFFFFFFUL,
  l3: 0xFFFFFFFFFFFFFFFFUL,
}

///|
/// `2^256 mod p` 的修正量 c = 2^32 + 977。
let fe_c : UInt64 = 0x1000003D1UL

///|
/// `(p+1)/4`：p ≡ 3 (mod 4)，开平方用 `rhs^((p+1)/4)`。
let fe_sqrt_exp : Fe = {
  l0: 0xFFFFFFFFBFFFFF0CUL,
  l1: 0xFFFFFFFFFFFFFFFFUL,
  l2: 0xFFFFFFFFFFFFFFFFUL,
  l3: 0x3FFFFFFFFFFFFFFFUL,
}

///|
fn fe_zero() -> Fe {
  { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
fn fe_one() -> Fe {
  { l0: 1UL, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
fn fe_is_zero(a : Fe) -> Bool {
  a.l0 == 0UL && a.l1 == 0UL && a.l2 == 0UL && a.l3 == 0UL
}

///|
fn fe_equal(a : Fe, b : Fe) -> Bool {
  a.l0 == b.l0 && a.l1 == b.l1 && a.l2 == b.l2 && a.l3 == b.l3
}

///|
/// 无符号比较：`a < b` 返回 -1，相等 0，`a > b` 返回 1。
fn fe_cmp(a : Fe, b : Fe) -> Int32 {
  if a.l3 != b.l3 {
    return if a.l3 < b.l3 { -1 } else { 1 }
  }
  if a.l2 != b.l2 {
    return if a.l2 < b.l2 { -1 } else { 1 }
  }
  if a.l1 != b.l1 {
    return if a.l1 < b.l1 { -1 } else { 1 }
  }
  if a.l0 != b.l0 {
    return if a.l0 < b.l0 { -1 } else { 1 }
  }
  0
}

// ---------------------------------------------------------------------------
// 加减
// ---------------------------------------------------------------------------

///|
/// 单 limb 带进位相加。两次加法的进位不可能同时为 1：若 `a + b` 溢出，
/// 则 `a + b ≥ 2^64`，而 `s = a + b - 2^64 ≤ 2^64 - 2`，再加 1 不会溢出。
fn adc(a : UInt64, b : UInt64, carry : UInt64) -> (UInt64, UInt64) {
  let s = a + b
  let t = s + carry
  let c = (if s < a { 1UL } else { 0UL }) | (if t < s { 1UL } else { 0UL })
  (t, c)
}

///|
/// 单 limb 带借位相减。
fn sbb(a : UInt64, b : UInt64, borrow : UInt64) -> (UInt64, UInt64) {
  let d = a - b
  let e = d - borrow
  let c = (if a < b { 1UL } else { 0UL }) | (if d < borrow { 1UL } else { 0UL })
  (e, c)
}

///|
/// 4 limb 相加，返回（和 mod 2^256，进位）。
fn add4(a : Fe, b : Fe) -> (Fe, UInt64) {
  let (r0, c0) = adc(a.l0, b.l0, 0UL)
  let (r1, c1) = adc(a.l1, b.l1, c0)
  let (r2, c2) = adc(a.l2, b.l2, c1)
  let (r3, c3) = adc(a.l3, b.l3, c2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, c3)
}

///|
/// 4 limb 相减，返回（差 mod 2^256，借位）。
fn sub4(a : Fe, b : Fe) -> (Fe, UInt64) {
  let (r0, b0) = sbb(a.l0, b.l0, 0UL)
  let (r1, b1) = sbb(a.l1, b.l1, b0)
  let (r2, b2) = sbb(a.l2, b.l2, b1)
  let (r3, b3) = sbb(a.l3, b.l3, b2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, b3)
}

///|
/// 减去小常数 `c`（调用方保证 `a >= c`）。
fn fe_sub_small(a : Fe, c : UInt64) -> Fe {
  let (r0, b0) = sbb(a.l0, c, 0UL)
  let (r1, b1) = sbb(a.l1, 0UL, b0)
  let (r2, b2) = sbb(a.l2, 0UL, b1)
  let (r3, _) = sbb(a.l3, 0UL, b2)
  { l0: r0, l1: r1, l2: r2, l3: r3, }
}

///|
/// 加上小常数 `c`，超出 2^256 的进位丢弃（即模 2^256）。
fn fe_add_small(a : Fe, c : UInt64) -> Fe {
  let (r0, c0) = adc(a.l0, c, 0UL)
  let (r1, c1) = adc(a.l1, 0UL, c0)
  let (r2, c2) = adc(a.l2, 0UL, c1)
  let (r3, _) = adc(a.l3, 0UL, c2)
  { l0: r0, l1: r1, l2: r2, l3: r3, }
}

///|
/// 模 p 加法。两个加数都 < p，和 < 2p，最多减一次 p。
fn fe_add(a : Fe, b : Fe) -> Fe {
  let (s, carry) = add4(a, b)
  // 两种越界都归到同一个修正：p = 2^256 - c，所以 `x - p ≡ x + c (mod 2^256)`。
  //   - 进位：a + b = 2^256 + s，结果 = s + c，且 s < 2^256 - c 不会回绕；
  //   - 无进位但 s >= p：结果 = s - p = s + c - 2^256，恰好由丢弃进位完成。
  if carry != 0UL || fe_cmp(s, fe_p) >= 0 {
    fe_add_small(s, fe_c)
  } else {
    s
  }
}

///|
/// 模 p 减法。借位时加回 p，等价于减去 `c`（`p = 2^256 - c`）。
fn fe_sub(a : Fe, b : Fe) -> Fe {
  let (d, borrow) = sub4(a, b)
  if borrow != 0UL {
    // a - b = d - 2^256，加上 p 得 d - c；因结果落在 (0, p) 内，回绕恰好正确。
    fe_sub_small(d, fe_c)
  } else {
    d
  }
}

///|
fn fe_neg(a : Fe) -> Fe {
  fe_sub(fe_zero(), a)
}

// ---------------------------------------------------------------------------
// 乘法与归约
// ---------------------------------------------------------------------------

///|
/// 把 4×64 拆成 8 个 32 位 limb（小端序），供 8×8 教科书乘法使用。
fn fe_limbs32(a : Fe) -> FixedArray[UInt64] {
  [
    a.l0 & 0xFFFFFFFFUL,
    a.l0 >> 32,
    a.l1 & 0xFFFFFFFFUL,
    a.l1 >> 32,
    a.l2 & 0xFFFFFFFFUL,
    a.l2 >> 32,
    a.l3 & 0xFFFFFFFFUL,
    a.l3 >> 32,
  ]
}

///|
/// 把 64 位槽归一化成 32 位 limb；最顶槽的进位保留在下一个槽里。
fn fe_normalize32(r : FixedArray[UInt64]) -> Unit {
  let mut carry = 0UL
  for i in 0..<r.length() {
    let cur = r[i] + carry
    r[i] = cur & 0xFFFFFFFFUL
    carry = cur >> 32
  }
}

///|
/// 把最高非零槽（`r[8]`/`r[9]`）按 `2^256 ≡ 2^32 + 977` 折回低槽。
/// 返回是否发生折叠；每折一次值严格变小，循环必然终止。
fn fe_fold_top(r : FixedArray[UInt64]) -> Bool {
  let mut i = r.length() - 1
  while i >= 8 {
    if r[i] != 0UL {
      let top = r[i]
      r[i] = 0UL
      let lo = top * 977UL
      r[i - 8] = r[i - 8] + (lo & 0xFFFFFFFFUL)
      r[i - 7] = r[i - 7] + (lo >> 32) + top
      return true
    }
    i = i - 1
  }
  false
}

///|
/// 与 p 比较（`r[0..7]` 已是 32 位 limb，更高槽为 0）。
fn fe_ge_p(r : FixedArray[UInt64]) -> Bool {
  // p 的 32 位 limb（低 → 高）：FFFFFC2F, FFFFFFFE, FFFFFFFF × 6。
  for idx in 0..<8 {
    let i = 7 - idx
    let want = if i == 0 {
      0xFFFFFC2FUL
    } else if i == 1 {
      0xFFFFFFFEUL
    } else {
      0xFFFFFFFFUL
    }
    if r[i] != want {
      return r[i] > want
    }
  }
  true
}

///|
/// 9 槽值减去 p（调用方保证 `r >= p`）。
fn fe_sub_p(r : FixedArray[UInt64]) -> Unit {
  // p 的 32 位 limb：FFFFFC2F, FFFFFFFE, FFFFFFFF ×6
  let mut borrow = 0UL
  // 槽是 32 位 limb，必须掩掉 sbb 在「借位且差为 0」时留下的高位。
  let (d0, b0) = sbb(r[0], 0xFFFFFC2FUL, borrow)
  r[0] = d0 & 0xFFFFFFFFUL
  borrow = b0
  let (d1, b1) = sbb(r[1], 0xFFFFFFFEUL, borrow)
  r[1] = d1 & 0xFFFFFFFFUL
  borrow = b1
  for i in 2..<8 {
    let (d, b) = sbb(r[i], 0xFFFFFFFFUL, borrow)
    r[i] = d & 0xFFFFFFFFUL
    borrow = b
  }
  // r[8] 只可能因减法借位而减少；调用方已保证 r >= p，不会借到负数。
  r[8] = r[8] - borrow
}

///|
/// 512 位乘积（16 个 32 位 limb）按 `2^256 ≡ 2^32 + 977` 归约到 p 域。
fn fe_reduce_p(t : FixedArray[UInt64]) -> Fe {
  // 第一次折叠：高 8 个 limb 各自贡献 `hi * 2^256 ≡ hi * (2^32 + 977)`。
  // 累加值上界 ~2^289（多出的 33 位进 r[8]/r[9]），64 位槽不会溢出。
  let r = FixedArray::make(10, 0UL)
  for i in 0..<8 {
    r[i] = t[i]
  }
  for idx in 0..<8 {
    let k = 7 - idx
    let hi = t[8 + k]
    r[k] = r[k] + hi * 977UL
    r[k + 1] = r[k + 1] + hi
  }
  fe_normalize32(r)
  // 折叠残留的高位，直到值不足 2^256。
  while fe_fold_top(r) {
    fe_normalize32(r)
  }
  // 此时值 < 2^256 < 2p，最多减一次 p。
  if fe_ge_p(r) {
    fe_sub_p(r)
  }
  {
    l0: r[0] | (r[1] << 32),
    l1: r[2] | (r[3] << 32),
    l2: r[4] | (r[5] << 32),
    l3: r[6] | (r[7] << 32),
  }
}

///|
/// 8×8 个 32 位 limb 的教科书乘法，输出 16 个 32 位 limb。
///
/// 每步 `xi * y[j] + t[idx] + carry` 的上界是 `(2^32-1)^2 + 2*(2^32-1) = 2^64-1`，
/// 64 位累加器刚好不溢出，因此不需要额外的 128 位中间量。
fn mul_8x8(
  x : FixedArray[UInt64],
  y : FixedArray[UInt64],
) -> FixedArray[UInt64] {
  let t = FixedArray::make(16, 0UL)
  for i in 0..<8 {
    let xi = x[i]
    let mut carry = 0UL
    for j in 0..<8 {
      let idx = i + j
      let cur = t[idx] + xi * y[j] + carry
      t[idx] = cur & 0xFFFFFFFFUL
      carry = cur >> 32
    }
    t[i + 8] = carry
  }
  t
}

///|
/// 模 p 乘法。
fn fe_mul(a : Fe, b : Fe) -> Fe {
  fe_reduce_p(mul_8x8(fe_limbs32(a), fe_limbs32(b)))
}

///|
fn fe_sqr(a : Fe) -> Fe {
  fe_mul(a, a)
}

///|
/// 模 p 幂：从指数最高位起平方乘。
fn fe_pow(a : Fe, e : Fe) -> Fe {
  let mut r = fe_one()
  for i in 0..<256 {
    let bit = 255 - i
    r = fe_sqr(r)
    let limb = match bit / 64 {
      0 => e.l0
      1 => e.l1
      2 => e.l2
      _ => e.l3
    }
    if ((limb >> (bit % 64)) & 1UL) == 1UL {
      r = fe_mul(r, a)
    }
  }
  r
}

// ---------------------------------------------------------------------------
// 求逆：二进制扩展欧几里得
// ---------------------------------------------------------------------------

///|
/// 4 limb 比较。
fn cmp4(a : FixedArray[UInt64], b : FixedArray[UInt64]) -> Int32 {
  for idx in 0..<4 {
    let i = 3 - idx
    if a[i] != b[i] {
      return if a[i] < b[i] { -1 } else { 1 }
    }
  }
  0
}

///|
/// 4 limb 右移一位。
fn shr1_4(a : FixedArray[UInt64]) -> Unit {
  let mut carry = 0UL
  for idx in 0..<4 {
    let i = 3 - idx
    let v = a[i]
    a[i] = (v >> 1) | (carry << 63)
    carry = v & 1UL
  }
}

///|
/// 就地 `a += b`，返回进位。
fn add4_into(a : FixedArray[UInt64], b : FixedArray[UInt64]) -> UInt64 {
  let mut carry = 0UL
  for i in 0..<4 {
    let (s, c) = adc(a[i], b[i], carry)
    a[i] = s
    carry = c
  }
  carry
}

///|
/// 就地 `a -= b`，返回借位。
fn sub4_into(a : FixedArray[UInt64], b : FixedArray[UInt64]) -> UInt64 {
  let mut borrow = 0UL
  for i in 0..<4 {
    let (d, c) = sbb(a[i], b[i], borrow)
    a[i] = d
    borrow = c
  }
  borrow
}

///|
/// 就地 `x = x / 2 (mod m)`；x 为奇数时先加 m 再右移（m 为奇数，和必为偶数）。
fn half_mod4(x : FixedArray[UInt64], m : FixedArray[UInt64]) -> Unit {
  if (x[0] & 1UL) == 0UL {
    shr1_4(x)
    return
  }
  let carry = add4_into(x, m)
  // x 现在是 257 位（carry 为第 256 位），整体右移一位。
  let mut c = carry
  for idx in 0..<4 {
    let i = 3 - idx
    let v = x[i]
    x[i] = (v >> 1) | (c << 63)
    c = v & 1UL
  }
}

///|
/// 就地 `x = x - y (mod m)`。
fn sub_mod4(
  x : FixedArray[UInt64],
  y : FixedArray[UInt64],
  m : FixedArray[UInt64],
) -> Unit {
  if cmp4(x, y) >= 0 {
    ignore(sub4_into(x, y))
  } else {
    // x - y 为负，先减（得到 2^256 + x - y），再加 m；回绕恰好等于 x - y + m。
    ignore(sub4_into(x, y))
    ignore(add4_into(x, m))
  }
}

///|
/// 4 limb 是否为 1。
fn is_one4(a : FixedArray[UInt64]) -> Bool {
  a[0] == 1UL && a[1] == 0UL && a[2] == 0UL && a[3] == 0UL
}

///|
/// 二进制扩展欧几里得：求 `a^{-1} mod m`（m 为奇素数，`0 < a < m`）。
///
/// 保持 u = a*x1、v = m*x2 (mod m) 的不变量，每轮把 u 或 v 右移到奇数再相减，
/// 直到一侧变成 1。全程只用移位/加减/比较，没有 256 次模乘。
fn inv_mod4(
  a : FixedArray[UInt64],
  m : FixedArray[UInt64],
) -> FixedArray[UInt64] {
  let u : FixedArray[UInt64] = [a[0], a[1], a[2], a[3]]
  let v : FixedArray[UInt64] = [m[0], m[1], m[2], m[3]]
  let x1 : FixedArray[UInt64] = [1UL, 0UL, 0UL, 0UL]
  let x2 : FixedArray[UInt64] = [0UL, 0UL, 0UL, 0UL]
  while !is_one4(u) && !is_one4(v) {
    while (u[0] & 1UL) == 0UL {
      shr1_4(u)
      half_mod4(x1, m)
    }
    while (v[0] & 1UL) == 0UL {
      shr1_4(v)
      half_mod4(x2, m)
    }
    if cmp4(u, v) >= 0 {
      ignore(sub4_into(u, v))
      sub_mod4(x1, x2, m)
    } else {
      ignore(sub4_into(v, u))
      sub_mod4(x2, x1, m)
    }
  }
  if is_one4(u) {
    x1
  } else {
    x2
  }
}

///|
/// 基域元素转 4 limb 数组。
fn fe_to_arr(a : Fe) -> FixedArray[UInt64] {
  [a.l0, a.l1, a.l2, a.l3]
}

///|
/// 4 limb 数组转基域元素（调用方保证值 < p）。
fn fe_of_arr(a : FixedArray[UInt64]) -> Fe {
  { l0: a[0], l1: a[1], l2: a[2], l3: a[3], }
}

///|
/// 基域求逆。`inv(0)` 抛 `NotInvertible`——零元没有逆，返回 0 会把错误静默
/// 传播到点运算里。
fn fe_inv(a : Fe) -> Fe raise SecpError {
  if fe_is_zero(a) {
    raise SecpError::NotInvertible
  }
  fe_of_arr(inv_mod4(fe_to_arr(a), fe_to_arr(fe_p)))
}

// ---------------------------------------------------------------------------
// 字节 / U256 转换
// ---------------------------------------------------------------------------

///|
fn fe_to_u256(a : Fe) -> @types.U256 {
  @types.U256::from_limbs(a.l0, a.l1, a.l2, a.l3)
}

///|
/// 32 字节大端转 4 limb（小端序）；调用方保证 `off + 32 <= length`。
fn load_be32_at(data : BytesView, off : Int32) -> FixedArray[UInt64] {
  let out : FixedArray[UInt64] = [0UL, 0UL, 0UL, 0UL]
  for i in 0..<4 {
    let mut v = 0UL
    for j in 0..<8 {
      v = (v << 8) | data[off + i * 8 + j].to_uint64()
    }
    out[3 - i] = v
  }
  out
}

///|
/// 从字节串起点读 32 字节。
fn load_be32(data : BytesView) -> FixedArray[UInt64] {
  load_be32_at(data, 0)
}

///|
fn fe_to_be_bytes(a : Fe) -> Bytes {
  fe_to_u256(a).to_bytes_be()
}

///|
/// 从 `off` 起解析 32 字节 canonical 域元素；`x >= p` 报 `InvalidPublicKey`。
///
/// 这条路径只服务公钥坐标解析（唯一调用方是 `PublicKey::parse`），所以越界
/// 在编码层就归到 `InvalidPublicKey`——不再出现「同一个越界、两个错误变体」
/// 的口径分裂。
fn fe_from_be_at(data : BytesView, off : Int32) -> Fe raise SecpError {
  if data.length() < off + 32 {
    raise SecpError::InvalidPublicKey
  }
  let a = fe_of_arr(load_be32_at(data, off))
  if fe_cmp(a, fe_p) >= 0 {
    raise SecpError::InvalidPublicKey
  }
  a
}
