// secp256k1 上的 ECDSA：RFC 6979 确定性签名（low-s）、验签、公钥恢复、地址推导。
//
// 语义契约（与 EVM 生态一致）：
//   - `sign` 产出 low-s（`s <= n/2`），归一化时同步翻转 recid；
//   - `verify` 按 ECDSA 数学定义接受完整 `s ∈ [1, n-1]`，不内建 low-s 策略；
//   - `recover` 是 malleable 的（对应 ECRECOVER 预编译）：high-s 且 recid 翻转
//     必须恢复出同一个公钥；
//   - `r`/`s` 严格在 `[1, n-1]`，越界报错，不静默取模；
//   - digest 必须恰好 32 字节，不隐式哈希；`z = digest mod n`。
//
// 明确不承诺常数时间：本实现的分支与查表都依赖操作数（域元素、标量、标量乘的
// 比特），存在时序/缓存侧信道。它面向的是公开数据的验签与交易重签，
// 不用于在可被观测的环境里保护长期私钥。

///|
/// 曲线上的公钥点（仿射坐标）。
#derive(Debug)
pub struct PublicKey {
  x : Fe
  y : Fe
}

///|
/// ECDSA 签名：`r`、`s` 与恢复标识 `recid`。
///
/// `recid` 取 SEC1 的 0..3：bit0 是 `R.y` 的奇偶性，bit1 表示 `R.x = r + n`。
/// EVM 调用方只用到 0/1。
#derive(Debug)
pub struct Signature {
  r : @types.U256
  s : @types.U256
  recid : Int32
}

// ---------------------------------------------------------------------------
// 内部转换与校验
// ---------------------------------------------------------------------------

///|
/// 私钥转标量：必须落在 `[1, n-1]`。
fn fn_from_private_key(d : @types.U256) -> Fn raise SecpError {
  if d.is_zero() {
    raise SecpError::InvalidPrivateKey
  }
  let f = fn_from_u256(d)
  if fn_cmp(f, fn_n) >= 0 {
    raise SecpError::InvalidPrivateKey
  }
  f
}

///|
/// 签名标量转 `Fn`：必须落在 `[1, n-1]`。
fn fn_from_signature_scalar(v : @types.U256) -> Fn raise SecpError {
  if v.is_zero() {
    raise SecpError::InvalidScalar
  }
  let f = fn_from_u256(v)
  if fn_cmp(f, fn_n) >= 0 {
    raise SecpError::InvalidScalar
  }
  f
}

///|
/// 基域元素当标量用：先归约到 `[0, n)`（x 坐标天然 < p < 2n）。
fn fn_from_fe_reduced(x : Fe) -> Fn {
  let a = fn_of_arr(fe_to_arr(x))
  if fn_cmp(a, fn_n) >= 0 {
    let (r, _) = fn_sub4(a, fn_n)
    r
  } else {
    a
  }
}

///|
/// 把 n 当基域元素（`n < p`）。
fn fe_of_n() -> Fe {
  fe_of_arr(fn_to_arr(fn_n))
}

///|
/// SEC1 的恢复标识：bit0 = `R.y` 的奇偶性，bit1 = `R.x >= n`（即 `R.x = r + n`）。
///
/// bit1 分支在 secp256k1 上概率约 `2^-128`（`p - n ≈ 2^128`），实际不会出现；
/// 但它决定 `sign` 是否要回 `recid = 2/3`，所以逻辑必须写对，单独抽出来便于白盒覆盖。
fn recid_of(rx : Fe, ry : Fe) -> Int32 {
  let mut recid = if (ry.l0 & 1UL) == 1UL { 1 } else { 0 }
  if fe_cmp(rx, fe_of_n()) >= 0 {
    recid = recid | 2
  }
  recid
}

// ---------------------------------------------------------------------------
// HMAC-SHA256（RFC 6979 的唯一外部依赖）
// ---------------------------------------------------------------------------

///|
fn hmac_sha256(
  key : FixedArray[Byte],
  msg : FixedArray[Byte],
) -> FixedArray[Byte] {
  @xcrypto.hmac(
    @xcrypto.SHA256::new(),
    Bytes::from_array(key)[:],
    Bytes::from_array(msg)[:],
  )
}

///|
/// RFC 6979 的种子串 `V || sep || int2octets(x) || bits2octets(h1)`。
fn rfc6979_seed(
  v : FixedArray[Byte],
  sep : Byte,
  x_octets : BytesView,
  h_octets : BytesView,
) -> FixedArray[Byte] {
  let out = FixedArray::make(97, b'\x00')
  for i in 0..<32 {
    out[i] = v[i]
  }
  out[32] = sep
  for i in 0..<32 {
    out[33 + i] = x_octets[i]
    out[65 + i] = h_octets[i]
  }
  out
}

// ---------------------------------------------------------------------------
// 签名
// ---------------------------------------------------------------------------

///|
/// RFC 6979 确定性签名（HMAC-SHA256），产出 low-s。
///
/// `private_key` 必须在 `[1, n-1]`；`digest` 必须恰好 32 字节。重试循环按
/// RFC 6979 §3.2 继续推进 `K`/`V`（`r = 0` 或 `s = 0` 时），不做隐式哈希。
pub fn secp_sign(
  digest : BytesView,
  private_key : @types.U256,
) -> Signature raise SecpError {
  let d = fn_from_private_key(private_key)
  let z = fn_from_be_bytes_reduced(digest)
  let x_octets = fn_to_be_bytes(d)
  let h_octets = fn_to_be_bytes(z)
  let mut v = FixedArray::make(32, b'\x01')
  let mut k = FixedArray::make(32, b'\x00')
  k = hmac_sha256(k, rfc6979_seed(v, b'\x00', x_octets[:], h_octets[:]))
  v = hmac_sha256(k, v)
  k = hmac_sha256(k, rfc6979_seed(v, b'\x01', x_octets[:], h_octets[:]))
  v = hmac_sha256(k, v)
  while true {
    v = hmac_sha256(k, v)
    let cand = fn_of_arr(load_be32(Bytes::from_array(v)[:]))
    if !fn_is_zero(cand) && fn_cmp(cand, fn_n) < 0 {
      let rp = scalar_mult_g(cand)
      // cand ∈ [1, n-1] 保证 cand*G != O。
      let (rx, ry) = jac_to_affine(rp)
      let r = fn_from_fe_reduced(rx)
      if !fn_is_zero(r) {
        let s = fn_mul(fn_inv(cand), fn_add(z, fn_mul(r, d)))
        if !fn_is_zero(s) {
          let mut recid = recid_of(rx, ry)
          let mut s_norm = s
          if fn_cmp(s, fn_half) > 0 {
            s_norm = fn_sub(fn_n, s)
            recid = recid ^ 1
          }
          return { r: fn_to_u256(r), s: fn_to_u256(s_norm), recid, }
        }
      }
    }
    // RFC 6979 §3.2(h.3)：K = HMAC_K(V || 0x00)，V = HMAC_K(V)。
    let retry = FixedArray::make(33, b'\x00')
    for i in 0..<32 {
      retry[i] = v[i]
    }
    k = hmac_sha256(k, retry)
    v = hmac_sha256(k, v)
  } nobreak {
    abort("secp_sign: RFC 6979 循环不可能退出")
  }
}

// ---------------------------------------------------------------------------
// 验签与恢复
// ---------------------------------------------------------------------------

///|
/// ECDSA 验签。数学上不成立返回 `false`；参数越界/长度不对抛 `SecpError`。
///
/// 按定义接受完整 `s ∈ [1, n-1]`（high-s 也返回 `true`），low-s 策略由调用方
/// 用 `Signature::is_low_s` 自行施加。
pub fn secp_verify(
  digest : BytesView,
  public_key : PublicKey,
  signature : Signature,
) -> Bool raise SecpError {
  let z = fn_from_be_bytes_reduced(digest)
  let r = fn_from_signature_scalar(signature.r)
  let s = fn_from_signature_scalar(signature.s)
  let w = fn_inv(s)
  let u1 = fn_mul(z, w)
  let u2 = fn_mul(r, w)
  let p1 = scalar_mult_g(u1)
  let p2 = scalar_mult(u2, public_key.x, public_key.y)
  let sum = jac_add(p1, p2)
  if jac_is_infinity(sum) {
    return false
  }
  let (x, _) = jac_to_affine(sum)
  fn_equal(fn_from_fe_reduced(x), r)
}

///|
/// 公钥恢复（SEC1，recid 0..3）。
///
/// 对应 ECRECOVER 预编译的语义：`s` 接受完整 `[1, n-1]`，high-s 不拒绝。
/// `R` 不在曲线上或恢复出无穷远点时抛 `RecoveryFailed`。
pub fn secp_recover(
  digest : BytesView,
  signature : Signature,
) -> PublicKey raise SecpError {
  if signature.recid < 0 || signature.recid > 3 {
    raise SecpError::InvalidRecoveryId(id=signature.recid)
  }
  let z = fn_from_be_bytes_reduced(digest)
  let r = fn_from_signature_scalar(signature.r)
  let s = fn_from_signature_scalar(signature.s)
  // x = r + (recid >> 1) * n，必须 < p。
  //
  // 这里不能用 `fe_add`：它按 p 取模，会把 `x >= p` 的越界折叠成一个合法值，
  // 让 recid 2/3 的边界检查形同虚设。必须用裸 256 位加法看进位。
  let mut x = fe_of_arr(fn_to_arr(r))
  if signature.recid >= 2 {
    let (sum, carry) = add4(x, fe_of_n())
    if carry != 0UL || fe_cmp(sum, fe_p) >= 0 {
      raise SecpError::RecoveryFailed
    }
    x = sum
  }
  let y = match decompress_y(x, (signature.recid & 1) == 1) {
    Some(y) => y
    None => raise SecpError::RecoveryFailed
  }
  // Q = r^{-1} * (s*R - z*G)
  let r_inv = fn_inv(r)
  let a = fn_mul(s, r_inv)
  let b = fn_neg(fn_mul(z, r_inv))
  let p1 = scalar_mult(a, x, y)
  let p2 = scalar_mult_g(b)
  let q = jac_add(p1, p2)
  if jac_is_infinity(q) {
    raise SecpError::RecoveryFailed
  }
  let (qx, qy) = jac_to_affine(q)
  if !on_curve(qx, qy) {
    raise SecpError::RecoveryFailed
  }
  { x: qx, y: qy, }
}

// ---------------------------------------------------------------------------
// 公钥
// ---------------------------------------------------------------------------

///|
/// 由私钥推导公钥。私钥必须在 `[1, n-1]`。
pub fn secp_generate_public_key(
  private_key : @types.U256,
) -> PublicKey raise SecpError {
  let d = fn_from_private_key(private_key)
  let p = scalar_mult_g(d)
  if jac_is_infinity(p) {
    raise SecpError::InvalidPrivateKey
  }
  let (x, y) = jac_to_affine(p)
  { x, y, }
}

///|
/// 公钥的 x 坐标。
pub fn PublicKey::x(self : PublicKey) -> @types.U256 {
  fe_to_u256(self.x)
}

///|
/// 公钥的 y 坐标。
pub fn PublicKey::y(self : PublicKey) -> @types.U256 {
  fe_to_u256(self.y)
}

///|
/// 非压缩编码：`0x04 || x || y`，65 字节。
pub fn PublicKey::to_uncompressed_bytes(self : PublicKey) -> Bytes {
  let out = FixedArray::make(65, b'\x00')
  out[0] = b'\x04'
  let xb = fe_to_be_bytes(self.x)
  let yb = fe_to_be_bytes(self.y)
  for i in 0..<32 {
    out[1 + i] = xb[i]
    out[33 + i] = yb[i]
  }
  Bytes::from_array(out)
}

///|
/// 压缩编码：`0x02/0x03 || x`，33 字节。
pub fn PublicKey::to_compressed_bytes(self : PublicKey) -> Bytes {
  let out = FixedArray::make(33, b'\x00')
  out[0] = if (self.y.l0 & 1UL) == 1UL { b'\x03' } else { b'\x02' }
  let xb = fe_to_be_bytes(self.x)
  for i in 0..<32 {
    out[1 + i] = xb[i]
  }
  Bytes::from_array(out)
}

///|
/// 解析 SEC1 公钥编码：33 字节（02/03 前缀）或 65 字节（04 前缀）。
///
/// `x`/`y` 必须 `< p`；压缩点必须能解出曲线上的 `y`；非压缩点必须落在曲线上。
pub fn PublicKey::parse(data : BytesView) -> PublicKey raise SecpError {
  let len = data.length()
  if len == 33 {
    let prefix = data[0]
    if prefix != b'\x02' && prefix != b'\x03' {
      raise SecpError::InvalidPublicKey
    }
    let x = fe_from_be_at(data, 1)
    match decompress_y(x, prefix == b'\x03') {
      Some(y) => { x, y, }
      None => raise SecpError::InvalidPublicKey
    }
  } else if len == 65 {
    if data[0] != b'\x04' {
      raise SecpError::InvalidPublicKey
    }
    let x = fe_from_be_at(data, 1)
    let y = fe_from_be_at(data, 33)
    if !on_curve(x, y) {
      raise SecpError::InvalidPublicKey
    }
    { x, y, }
  } else {
    raise SecpError::InvalidPublicKey
  }
}

///|
/// 公钥推导以太坊地址：`keccak256(x || y)[12..32]`。
///
/// 不失败：`PublicKey` 的构造路径已保证它是曲线上的有限点，且 keccak 输出固定 32 字节。
pub fn secp_public_key_to_address(public_key : PublicKey) -> @types.Address {
  let buf = FixedArray::make(64, b'\x00')
  let xb = fe_to_be_bytes(public_key.x)
  let yb = fe_to_be_bytes(public_key.y)
  for i in 0..<32 {
    buf[i] = xb[i]
    buf[32 + i] = yb[i]
  }
  let digest = keccak256(Bytes::from_array(buf)[:]).as_bytes()
  let out = FixedArray::make(20, b'\x00')
  for i in 0..<20 {
    out[i] = digest[12 + i]
  }
  @types.Address::from_bytes_unchecked(Bytes::from_array(out)[:])
}

// ---------------------------------------------------------------------------
// 签名
// ---------------------------------------------------------------------------

///|
/// 签名的 `r`。
pub fn Signature::r(self : Signature) -> @types.U256 {
  self.r
}

///|
/// 签名的 `s`。
pub fn Signature::s(self : Signature) -> @types.U256 {
  self.s
}

///|
/// 恢复标识（0..3）。
pub fn Signature::recid(self : Signature) -> Int32 {
  self.recid
}

///|
/// 是否 low-s（`s <= n/2`）。给交易层（C12）与 EIP-7702（P02）做策略判定用；
/// `verify`/`recover` 自身不施加这条策略。
pub fn Signature::is_low_s(self : Signature) -> Bool {
  let f = fn_from_u256(self.s)
  fn_cmp(f, fn_half) <= 0
}

///|
/// `r || s` 的 64 字节大端编码（不含 recid）。
pub fn Signature::to_bytes(self : Signature) -> Bytes {
  let out = FixedArray::make(64, b'\x00')
  let rb = self.r.to_bytes_be()
  let sb = self.s.to_bytes_be()
  for i in 0..<32 {
    out[i] = rb[i]
    out[32 + i] = sb[i]
  }
  Bytes::from_array(out)
}

///|
/// 解析 `r || s`（64 字节）并附带 `recid`；范围与 recid 都严格校验。
pub fn Signature::from_bytes(
  data : BytesView,
  recid : Int32,
) -> Signature raise SecpError {
  if data.length() != 64 {
    raise SecpError::InvalidSignatureLength(actual=data.length())
  }
  if recid < 0 || recid > 3 {
    raise SecpError::InvalidRecoveryId(id=recid)
  }
  let r = fn_from_be_at(data, 0)
  let s = fn_from_be_at(data, 32)
  { r: fn_to_u256(r), s: fn_to_u256(s), recid, }
}
