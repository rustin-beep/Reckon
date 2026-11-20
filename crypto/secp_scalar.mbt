// secp256k1 标量域 F_n 算术：n 是曲线群的阶。
//
// 与基域同构：4×UInt64 limb（小端序），值恒在 `[0, n)`。
//
// n 没有 p 那种「2^256 减去一个小常数」的伪梅森形式，2^256 - n 有 129 位，
// 因此这里不做 Montgomery/Barrett 热优化：乘法先出 512 位乘积，再用逐位
// 长除法归约（`n` 每次签名/验签只用几次，正确优先）。加减走 `n = 2^256 - delta`
// 的常数修正，没有分支以外的技巧。

///|
/// 标量域元素，值恒在 `[0, n)`。
#derive(Debug)
struct Fn {
  l0 : UInt64
  l1 : UInt64
  l2 : UInt64
  l3 : UInt64
}

///|
/// 群阶 n。
let fn_n : Fn = {
  l0: 0xBFD25E8CD0364141UL,
  l1: 0xBAAEDCE6AF48A03BUL,
  l2: 0xFFFFFFFFFFFFFFFEUL,
  l3: 0xFFFFFFFFFFFFFFFFUL,
}

///|
/// `n/2`（向下取整）：low-s 判定的上界。
let fn_half : Fn = {
  l0: 0xDFE92F46681B20A0UL,
  l1: 0x5D576E7357A4501DUL,
  l2: 0xFFFFFFFFFFFFFFFFUL,
  l3: 0x7FFFFFFFFFFFFFFFUL,
}

///|
/// `2^256 - n`，用于把「和溢出 2^256」修正回模 n。
let fn_delta : Fn = {
  l0: 0x402DA1732FC9BEBFUL,
  l1: 0x4551231950B75FC4UL,
  l2: 0x0000000000000001UL,
  l3: 0x0000000000000000UL,
}

///|
/// n 的 32 位 limb（低 → 高），逐位归约时比较用。
let fn_n_limbs32 : FixedArray[UInt64] = [
  0xD0364141UL, 0xBFD25E8CUL, 0xAF48A03BUL, 0xBAAEDCE6UL, 0xFFFFFFFEUL, 0xFFFFFFFFUL,
  0xFFFFFFFFUL, 0xFFFFFFFFUL,
]

///|
fn fn_zero() -> Fn {
  { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
fn fn_is_zero(a : Fn) -> Bool {
  a.l0 == 0UL && a.l1 == 0UL && a.l2 == 0UL && a.l3 == 0UL
}

///|
fn fn_equal(a : Fn, b : Fn) -> Bool {
  a.l0 == b.l0 && a.l1 == b.l1 && a.l2 == b.l2 && a.l3 == b.l3
}

///|
fn fn_cmp(a : Fn, b : Fn) -> Int32 {
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

///|
fn fn_add4(a : Fn, b : Fn) -> (Fn, UInt64) {
  let (r0, c0) = adc(a.l0, b.l0, 0UL)
  let (r1, c1) = adc(a.l1, b.l1, c0)
  let (r2, c2) = adc(a.l2, b.l2, c1)
  let (r3, c3) = adc(a.l3, b.l3, c2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, c3)
}

///|
fn fn_sub4(a : Fn, b : Fn) -> (Fn, UInt64) {
  let (r0, b0) = sbb(a.l0, b.l0, 0UL)
  let (r1, b1) = sbb(a.l1, b.l1, b0)
  let (r2, b2) = sbb(a.l2, b.l2, b1)
  let (r3, b3) = sbb(a.l3, b.l3, b2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, b3)
}

///|
/// 模 n 加法。两加数 < n，和 < 2n；溢出 2^256 时结果 = s + delta。
fn fn_add(a : Fn, b : Fn) -> Fn {
  let (s, carry) = fn_add4(a, b)
  if carry != 0UL {
    let (r, _) = fn_add4(s, fn_delta)
    r
  } else if fn_cmp(s, fn_n) >= 0 {
    let (r, _) = fn_sub4(s, fn_n)
    r
  } else {
    s
  }
}

///|
/// 模 n 减法。借位时加回 n，即减去 delta。
fn fn_sub(a : Fn, b : Fn) -> Fn {
  let (d, borrow) = fn_sub4(a, b)
  if borrow != 0UL {
    let (r, _) = fn_sub4(d, fn_delta)
    r
  } else {
    d
  }
}

///|
fn fn_neg(a : Fn) -> Fn {
  fn_sub(fn_zero(), a)
}

///|
/// 把 4×64 拆成 8 个 32 位 limb（小端序）。
fn fn_limbs32(a : Fn) -> FixedArray[UInt64] {
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
/// 9 槽值与 n 比较（`r[8]` 是第 256 位）。
fn fn_ge_n(r : FixedArray[UInt64]) -> Bool {
  if r[8] != 0UL {
    return true
  }
  for idx in 0..<8 {
    let i = 7 - idx
    if r[i] != fn_n_limbs32[i] {
      return r[i] > fn_n_limbs32[i]
    }
  }
  true
}

///|
/// 9 槽值减去 n（调用方保证 `r >= n`）。
fn fn_sub_n(r : FixedArray[UInt64]) -> Unit {
  let mut borrow = 0UL
  for i in 0..<8 {
    // 槽是 32 位 limb，必须掩掉 sbb 在「借位且差为 0」时留下的高位。
    let (d, b) = sbb(r[i], fn_n_limbs32[i], borrow)
    r[i] = d & 0xFFFFFFFFUL
    borrow = b
  }
  r[8] = r[8] - borrow
}

///|
/// 512 位乘积（16 个 32 位 limb）对 n 取模：逐位长除法。
///
/// 每次迭代把余数左移一位并带进当前位，维持 `r < n`；`n` 接近 2^256，
/// 第 256 位单独用 `r[8]` 表示，比较与减法都在 9 槽上做。
fn fn_reduce_n(t : FixedArray[UInt64]) -> Fn {
  let r = FixedArray::make(9, 0UL)
  for idx in 0..<512 {
    let bit_idx = 511 - idx
    let bit = (t[bit_idx / 32] >> (bit_idx % 32)) & 1UL
    let mut carry = bit
    for j in 0..<9 {
      let shifted = (r[j] << 1) | carry
      carry = shifted >> 32
      r[j] = shifted & 0xFFFFFFFFUL
    }
    if fn_ge_n(r) {
      fn_sub_n(r)
    }
  }
  {
    l0: r[0] | (r[1] << 32),
    l1: r[2] | (r[3] << 32),
    l2: r[4] | (r[5] << 32),
    l3: r[6] | (r[7] << 32),
  }
}

///|
fn fn_mul(a : Fn, b : Fn) -> Fn {
  fn_reduce_n(mul_8x8(fn_limbs32(a), fn_limbs32(b)))
}

///|
fn fn_to_arr(a : Fn) -> FixedArray[UInt64] {
  [a.l0, a.l1, a.l2, a.l3]
}

///|
fn fn_of_arr(a : FixedArray[UInt64]) -> Fn {
  { l0: a[0], l1: a[1], l2: a[2], l3: a[3], }
}

///|
/// 标量域求逆。`inv(0)` 抛 `NotInvertible`。
fn fn_inv(a : Fn) -> Fn raise SecpError {
  if fn_is_zero(a) {
    raise SecpError::NotInvertible
  }
  fn_of_arr(inv_mod4(fn_to_arr(a), fn_to_arr(fn_n)))
}

///|
fn fn_to_u256(a : Fn) -> @types.U256 {
  @types.U256::from_limbs(a.l0, a.l1, a.l2, a.l3)
}

///|
fn fn_from_u256(u : @types.U256) -> Fn {
  { l0: u.limb(0), l1: u.limb(1), l2: u.limb(2), l3: u.limb(3), }
}

///|
fn fn_to_be_bytes(a : Fn) -> Bytes {
  fn_to_u256(a).to_bytes_be()
}

///|
/// 解析 32 字节大端整数并归约到 `[0, n)`。摘要走这条路径（允许 ≥ n）。
fn fn_from_be_bytes_reduced(data : BytesView) -> Fn raise SecpError {
  if data.length() != 32 {
    raise SecpError::InvalidDigestLength(actual=data.length())
  }
  let limbs = load_be32(data)
  let t = FixedArray::make(16, 0UL)
  // load_be32 给的是 4×64 小端；展开成 8×32 再补零到 16 槽。
  t[0] = limbs[0] & 0xFFFFFFFFUL
  t[1] = limbs[0] >> 32
  t[2] = limbs[1] & 0xFFFFFFFFUL
  t[3] = limbs[1] >> 32
  t[4] = limbs[2] & 0xFFFFFFFFUL
  t[5] = limbs[2] >> 32
  t[6] = limbs[3] & 0xFFFFFFFFUL
  t[7] = limbs[3] >> 32
  fn_reduce_n(t)
}

///|
/// 从 `off` 起解析 32 字节 canonical 标量：必须落在 `[1, n-1]`，否则 `InvalidScalar`。
fn fn_from_be_at(data : BytesView, off : Int32) -> Fn raise SecpError {
  if data.length() < off + 32 {
    raise SecpError::InvalidScalar
  }
  let a = fn_of_arr(load_be32_at(data, off))
  if fn_is_zero(a) || fn_cmp(a, fn_n) >= 0 {
    raise SecpError::InvalidScalar
  }
  a
}
