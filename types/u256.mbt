// 无符号 256 位字：EVM 的机器字。
//
// 表示：四个 64 位 limb，小端序（`l0` 最低位）。
// 所有算术都按 2^256 取模回绕，这正是 EVM 字的语义，因此任何运算都不向调用方
// 报告溢出。

///|
/// 256 位无符号整数。
#derive(Debug)
pub struct U256 {
  l0 : UInt64
  l1 : UInt64
  l2 : UInt64
  l3 : UInt64
}

///|
pub fn U256::from_limbs(
  l0 : UInt64,
  l1 : UInt64,
  l2 : UInt64,
  l3 : UInt64,
) -> U256 {
  { l0, l1, l2, l3, }
}

///|
pub fn U256::zero() -> U256 {
  { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
pub fn U256::one() -> U256 {
  { l0: 1UL, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
/// 2^256 - 1, the largest representable word.
pub fn U256::max_value() -> U256 {
  {
    l0: 0xFFFFFFFFFFFFFFFFUL,
    l1: 0xFFFFFFFFFFFFFFFFUL,
    l2: 0xFFFFFFFFFFFFFFFFUL,
    l3: 0xFFFFFFFFFFFFFFFFUL,
  }
}

///|
pub fn U256::from_u64(v : UInt64) -> U256 {
  { l0: v, l1: 0UL, l2: 0UL, l3: 0UL, }
}

///|
/// `self` 的低 64 位（截断）。
pub fn U256::to_u64(self : U256) -> UInt64 {
  self.l0
}

///|
/// 第 `i` 个 limb（`0..=3`），从最低位开始。
pub fn U256::limb(self : U256, i : Int32) -> UInt64 {
  match i {
    0 => self.l0
    1 => self.l1
    2 => self.l2
    3 => self.l3
    _ => abort("U256::limb: index out of range")
  }
}

///|
pub fn U256::is_zero(self : U256) -> Bool {
  self.l0 == 0UL && self.l1 == 0UL && self.l2 == 0UL && self.l3 == 0UL
}

///|
/// 有效位数；`0` 返回 0。
pub fn U256::bit_length(self : U256) -> Int32 {
  if self.l3 != 0UL {
    256 - self.l3.clz()
  } else if self.l2 != 0UL {
    192 - self.l2.clz()
  } else if self.l1 != 0UL {
    128 - self.l1.clz()
  } else if self.l0 != 0UL {
    64 - self.l0.clz()
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// 比较
// ---------------------------------------------------------------------------

///|
pub impl Eq for U256 with fn equal(self, other) -> Bool {
  self.l0 == other.l0 &&
  self.l1 == other.l1 &&
  self.l2 == other.l2 &&
  self.l3 == other.l3
}

///|
pub impl Compare for U256 with fn compare(self, other) -> Int32 {
  if self.l3 != other.l3 {
    if self.l3 < other.l3 {
      -1
    } else {
      1
    }
  } else if self.l2 != other.l2 {
    if self.l2 < other.l2 {
      -1
    } else {
      1
    }
  } else if self.l1 != other.l1 {
    if self.l1 < other.l1 {
      -1
    } else {
      1
    }
  } else if self.l0 != other.l0 {
    if self.l0 < other.l0 {
      -1
    } else {
      1
    }
  } else {
    0
  }
}

// ---------------------------------------------------------------------------
// 哈希
// ---------------------------------------------------------------------------

///|
/// 四个 limb 依次混入；只要求「相等即同哈希」，不要求与 `compare` 同序。
pub impl Hash for U256 with fn hash_combine(self, hasher) -> Unit {
  hasher.combine_uint64(self.l0)
  hasher.combine_uint64(self.l1)
  hasher.combine_uint64(self.l2)
  hasher.combine_uint64(self.l3)
}

// ---------------------------------------------------------------------------
// 加法 / 减法
// ---------------------------------------------------------------------------

///|
fn add_limb(a : UInt64, b : UInt64, carry : UInt64) -> (UInt64, UInt64) {
  let s = a + b
  let c0 = if s < a { 1UL } else { 0UL }
  let t = s + carry
  let c1 = if t < s { 1UL } else { 0UL }
  (t, c0 + c1)
}

///|
fn sub_limb(a : UInt64, b : UInt64, borrow : UInt64) -> (UInt64, UInt64) {
  let d = a - b
  let b0 = if a < b { 1UL } else { 0UL }
  let e = d - borrow
  let b1 = if d < borrow { 1UL } else { 0UL }
  (e, b0 + b1)
}

///|
/// 返回 `(和 mod 2^256, 进位)`。
pub fn U256::overflowing_add(self : U256, other : U256) -> (U256, UInt64) {
  let (r0, c0) = add_limb(self.l0, other.l0, 0UL)
  let (r1, c1) = add_limb(self.l1, other.l1, c0)
  let (r2, c2) = add_limb(self.l2, other.l2, c1)
  let (r3, c3) = add_limb(self.l3, other.l3, c2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, c3)
}

///|
/// 返回 `(差 mod 2^256, 借位)`。
pub fn U256::overflowing_sub(self : U256, other : U256) -> (U256, UInt64) {
  let (r0, b0) = sub_limb(self.l0, other.l0, 0UL)
  let (r1, b1) = sub_limb(self.l1, other.l1, b0)
  let (r2, b2) = sub_limb(self.l2, other.l2, b1)
  let (r3, b3) = sub_limb(self.l3, other.l3, b2)
  ({ l0: r0, l1: r1, l2: r2, l3: r3, }, b3)
}

///|
pub impl Add for U256 with fn add(self, other) -> U256 {
  let (sum, _) = self.overflowing_add(other)
  sum
}

///|
pub impl Sub for U256 with fn sub(self, other) -> U256 {
  let (diff, _) = self.overflowing_sub(other)
  diff
}

///|
/// 补码取负：`0 - self`。
pub fn U256::neg(self : U256) -> U256 {
  U256::zero() - self
}

// ---------------------------------------------------------------------------
// 乘法
// ---------------------------------------------------------------------------

///|
/// 把 `a * b` 累加到 `t` 的第 `start` 个 limb 起。
///
/// 64x64 -> 128 用四个 32 位部分积拼出来，因为 MoonBit 的 `UInt64 *` 只给低 64 位。
fn mul_add_limb(
  t : FixedArray[UInt64],
  start : Int32,
  a : UInt64,
  b : UInt64,
) -> Unit {
  let a0 = a.to_uint().to_uint64()
  let a1 = (a >> 32).to_uint().to_uint64()
  let b0 = b.to_uint().to_uint64()
  let b1 = (b >> 32).to_uint().to_uint64()
  let p00 = a0 * b0
  let p01 = a0 * b1
  let p10 = a1 * b0
  let p11 = a1 * b1
  let mid = (p00 >> 32) + (p01 & 0xFFFFFFFFUL) + (p10 & 0xFFFFFFFFUL)
  let lo = (mid << 32) | (p00 & 0xFFFFFFFFUL)
  let hi = p11 + (p01 >> 32) + (p10 >> 32) + (mid >> 32)
  add_at(t, start, lo)
  add_at(t, start + 1, hi)
}

///|
/// 从 `start` 起把 `v` 的进位在 `t` 中传播（超出数组末尾的进位静默丢弃）。
fn add_at(t : FixedArray[UInt64], start : Int32, v : UInt64) -> Unit {
  let n = t.length()
  let mut j = start
  let mut carry = v
  while carry != 0UL && j < n {
    let s = t[j] + carry
    carry = if s < t[j] { 1UL } else { 0UL }
    t[j] = s
    j = j + 1
  }
}

///|
/// 完整 256x256 -> 512 乘积，八个 limb，小端序。
fn mul_full(a : U256, b : U256) -> FixedArray[UInt64] {
  let t = FixedArray::make(8, 0UL)
  mul_add_limb(t, 0, a.l0, b.l0)
  mul_add_limb(t, 1, a.l0, b.l1)
  mul_add_limb(t, 2, a.l0, b.l2)
  mul_add_limb(t, 3, a.l0, b.l3)
  mul_add_limb(t, 1, a.l1, b.l0)
  mul_add_limb(t, 2, a.l1, b.l1)
  mul_add_limb(t, 3, a.l1, b.l2)
  mul_add_limb(t, 4, a.l1, b.l3)
  mul_add_limb(t, 2, a.l2, b.l0)
  mul_add_limb(t, 3, a.l2, b.l1)
  mul_add_limb(t, 4, a.l2, b.l2)
  mul_add_limb(t, 5, a.l2, b.l3)
  mul_add_limb(t, 3, a.l3, b.l0)
  mul_add_limb(t, 4, a.l3, b.l1)
  mul_add_limb(t, 5, a.l3, b.l2)
  mul_add_limb(t, 6, a.l3, b.l3)
  t
}

///|
pub impl Mul for U256 with fn mul(self, other) -> U256 {
  let t = mul_full(self, other)
  U256::from_limbs(t[0], t[1], t[2], t[3])
}

// ---------------------------------------------------------------------------
// 除法
// ---------------------------------------------------------------------------

///|
/// 逐位恢复除法。慢但显然正确；C05 会把热路径换成 Knuth-D 风格实现，
/// 保留这一版作为 oracle。
fn udivmod(a : U256, b : U256) -> (U256, U256) {
  if b.is_zero() {
    // EVM: division and modulo by zero both yield zero.
    (U256::zero(), U256::zero())
  } else if a < b {
    (U256::zero(), a)
  } else {
    let mut q = U256::zero()
    let mut r = U256::zero()
    for k in 0..<256 {
      let i = 255 - k
      let carry = r.l3 >> 63
      r = r.shl(1)
      let bit = (a.limb(i / 64) >> (i % 64)) & 1UL
      if bit == 1UL {
        r = r | U256::one()
      }
      if carry != 0UL || r >= b {
        r = r - b
        q = q.set_bit(i)
      }
    }
    (q, r)
  }
}

///|
fn U256::set_bit(self : U256, i : Int32) -> U256 {
  let limb = i / 64
  let bit = 1UL << (i % 64)
  match limb {
    0 => { l0: self.l0 | bit, l1: self.l1, l2: self.l2, l3: self.l3, }
    1 => { l0: self.l0, l1: self.l1 | bit, l2: self.l2, l3: self.l3, }
    2 => { l0: self.l0, l1: self.l1, l2: self.l2 | bit, l3: self.l3, }
    _ => { l0: self.l0, l1: self.l1, l2: self.l2, l3: self.l3 | bit, }
  }
}

///|
pub impl Div for U256 with fn div(self, other) -> U256 {
  let (q, _) = udivmod(self, other)
  q
}

///|
pub impl Mod for U256 with fn mod(self, other) -> U256 {
  let (_, r) = udivmod(self, other)
  r
}

///|
/// `(self + other) % m`，中间值 257 位；`m = 0` 时返回 0。
pub fn U256::addmod(self : U256, other : U256, m : U256) -> U256 {
  if m.is_zero() {
    U256::zero()
  } else {
    let (sum, carry) = self.overflowing_add(other)
    let wide = FixedArray::make(5, 0UL)
    wide[0] = sum.l0
    wide[1] = sum.l1
    wide[2] = sum.l2
    wide[3] = sum.l3
    wide[4] = carry
    reduce_wide(wide, 257, m)
  }
}

///|
/// `(self * other) % m`，中间值 512 位；`m = 0` 时返回 0。
pub fn U256::mulmod(self : U256, other : U256, m : U256) -> U256 {
  if m.is_zero() {
    U256::zero()
  } else {
    reduce_wide(mul_full(self, other), 512, m)
  }
}

///|
/// 把小端序 limb 数组（有效位 `nbits`）对 `m` 取模。
///
/// 每次迭代都维持 `r < m` 的不变量，所以移位之后一次回绕减法就够。
fn reduce_wide(limbs : FixedArray[UInt64], nbits : Int32, m : U256) -> U256 {
  let mut r = U256::zero()
  for k in 0..<nbits {
    let i = nbits - 1 - k
    let carry = r.l3 >> 63
    r = r.shl(1)
    if ((limbs[i / 64] >> (i % 64)) & 1UL) == 1UL {
      r = r | U256::one()
    }
    if carry != 0UL || r >= m {
      r = r - m
    }
  }
  r
}

///|
/// `self ** e mod 2^256`，平方乘。
pub fn U256::exp(self : U256, e : U256) -> U256 {
  let mut result = U256::one()
  let mut base = self
  let mut exp = e
  while !exp.is_zero() {
    if (exp.l0 & 1UL) == 1UL {
      result = result * base
    }
    exp = exp.shr(1)
    if !exp.is_zero() {
      base = base * base
    }
  }
  result
}

// ---------------------------------------------------------------------------
// 位运算
// ---------------------------------------------------------------------------

///|
pub impl BitAnd for U256 with fn land(self, other) -> U256 {
  {
    l0: self.l0 & other.l0,
    l1: self.l1 & other.l1,
    l2: self.l2 & other.l2,
    l3: self.l3 & other.l3,
  }
}

///|
pub impl BitOr for U256 with fn lor(self, other) -> U256 {
  {
    l0: self.l0 | other.l0,
    l1: self.l1 | other.l1,
    l2: self.l2 | other.l2,
    l3: self.l3 | other.l3,
  }
}

///|
pub impl BitXOr for U256 with fn lxor(self, other) -> U256 {
  {
    l0: self.l0 ^ other.l0,
    l1: self.l1 ^ other.l1,
    l2: self.l2 ^ other.l2,
    l3: self.l3 ^ other.l3,
  }
}

///|
pub fn U256::lnot(self : U256) -> U256 {
  {
    l0: self.l0 ^ 0xFFFFFFFFFFFFFFFFUL,
    l1: self.l1 ^ 0xFFFFFFFFFFFFFFFFUL,
    l2: self.l2 ^ 0xFFFFFFFFFFFFFFFFUL,
    l3: self.l3 ^ 0xFFFFFFFFFFFFFFFFUL,
  }
}

///|
/// 逻辑左移；`n >= 256` 返回 0。
pub fn U256::shl(self : U256, n : Int32) -> U256 {
  if n <= 0 {
    self
  } else if n >= 256 {
    U256::zero()
  } else {
    let limb_shift = n / 64
    let bit_shift = n % 64
    let src : FixedArray[UInt64] = [self.l0, self.l1, self.l2, self.l3]
    let out : FixedArray[UInt64] = [0UL, 0UL, 0UL, 0UL]
    for k in 0..<4 {
      let dst = k + limb_shift
      if dst < 4 {
        let mut v = src[k] << bit_shift
        if n % 64 != 0 && k > 0 {
          v = v | (src[k - 1] >> (64 - n % 64))
        }
        out[dst] = v
      }
    }
    U256::from_limbs(out[0], out[1], out[2], out[3])
  }
}

///|
/// 逻辑右移；`n >= 256` 返回 0。
pub fn U256::shr(self : U256, n : Int32) -> U256 {
  if n <= 0 {
    self
  } else if n >= 256 {
    U256::zero()
  } else {
    let limb_shift = n / 64
    let bit_shift = n % 64
    let src : FixedArray[UInt64] = [self.l0, self.l1, self.l2, self.l3]
    let out : FixedArray[UInt64] = [0UL, 0UL, 0UL, 0UL]
    for k in 0..<4 {
      let srci = k + limb_shift
      if srci < 4 {
        let mut v = src[srci] >> bit_shift
        if n % 64 != 0 && srci < 3 {
          v = v | (src[srci + 1] << (64 - n % 64))
        }
        out[k] = v
      }
    }
    U256::from_limbs(out[0], out[1], out[2], out[3])
  }
}

///|
/// EVM `BYTE`：从最高位起数第 `i` 个字节；`i >= 32` 返回 0。
pub fn U256::byte_at(self : U256, i : Int32) -> U256 {
  if i < 0 || i >= 32 {
    U256::zero()
  } else {
    let limb = 3 - i / 8
    let shift = (7 - i % 8) * 8
    U256::from_u64((self.limb(limb) >> shift) & 0xFFUL)
  }
}

// ---------------------------------------------------------------------------
// 字节 / 十六进制转换
// ---------------------------------------------------------------------------

///|
/// 大端 32 字节编码。
pub fn U256::to_bytes_be(self : U256) -> Bytes {
  let out = FixedArray::make(32, b'\x00')
  for k in 0..<4 {
    let be = self.limb(k).to_be_bytes()
    for j in 0..<8 {
      out[(3 - k) * 8 + j] = be[j]
    }
  }
  Bytes::from_array(out)
}

///|
/// 解码大端字节串，长度不超过 32 字节。
pub fn U256::from_bytes_be(data : BytesView) -> U256 raise DecodeError {
  let n = data.length()
  if n > 32 {
    raise DecodeError::InvalidLength(expected=32, actual=n)
  }
  let buf = FixedArray::make(32, b'\x00')
  for k in 0..<n {
    buf[32 - n + k] = data[k]
  }
  let limbs : FixedArray[UInt64] = [0UL, 0UL, 0UL, 0UL]
  for k in 0..<4 {
    let mut v = 0UL
    for j in 0..<8 {
      v = (v << 8) | buf[k * 8 + j].to_uint64()
    }
    limbs[k] = v
  }
  // `buf` is big-endian, so `limbs[0]` holds the most significant limb.
  U256::from_limbs(limbs[3], limbs[2], limbs[1], limbs[0])
}

///|
/// 小写十六进制，恰好 64 位，不带 `0x` 前缀。
pub fn U256::to_hex(self : U256) -> String {
  hex_encode(self.to_bytes_be()[:])
}

///|
/// 解析十六进制，`0x` 前缀可选，奇数位左补一个 0 位（以太坊数量字段的写法）。
pub fn U256::from_hex(s : String) -> U256 raise DecodeError {
  U256::from_bytes_be(hex_decode_padded(s)[:])
}

///|
pub impl Show for U256 with fn to_string(self) -> String {
  self.to_hex()
}

// ---------------------------------------------------------------------------
// 显式方法提升（trait impl 方法的隐式提升已废弃；这些声明让
// `u.add(v)` / `u.compare(v)` 继续可用）。
// ---------------------------------------------------------------------------

///|
pub extend U256 with Add::{add}

///|
pub extend U256 with Sub::{sub}

///|
pub extend U256 with Mul::{mul}

///|
pub extend U256 with Div::{div}

///|
pub extend U256 with Mod::{mod}

///|
pub extend U256 with Eq::{equal, not_equal}

///|
pub extend U256 with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
pub extend U256 with Hash::{hash, hash_combine}

///|
pub extend U256 with BitAnd::{land}

///|
pub extend U256 with BitOr::{lor}

///|
pub extend U256 with BitXOr::{lxor}

///|
pub extend U256 with Show::{to_string, output}

///|
pub extend U256 with Debug::{to_repr}
