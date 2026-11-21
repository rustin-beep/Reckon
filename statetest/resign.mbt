// `secretKey` / `sender` / `recover` / 重签的一致性校验。
//
// 三段独立判定，任何一段失败都能单独归因：
//   1. `secretKey -> 公钥 -> 地址` 必须等于 fixture 的 `sender`；
//   2. `Signature(r||s, yParity)` + `recover(signing_hash)` 必须恢复出同一个 `sender`；
//   3. `secp_sign(signing_hash)` 得到的 low-s 签名重新编码后必须与 `txbytes` 逐字节相同。
//
// 本文件不判「这算不算错误」：`expectException` 的豁免统一在 `run.mbt` 处理，
// 这里只回答「一致 / 不一致 / 签不出来」。

///|
/// 重签结果。
///
/// 只有能恢复的签名才会走到这里（调用方已用 `recover_sender` 判过），所以没有
/// 「预期无效」这一类。
pub(all) enum ResignOutcome {
  /// 重编码后与 `txbytes` 逐字节一致。
  Ok
  /// 不一致；`offset` 是第一个不同字节的位置。
  ///
  /// `reencoded` 是用 fixture 私钥重签后重编码的字节，`original` 是 txbytes 的原始
  /// 字节——两者都只截取差异点起的 8 字节。
  Mismatch(offset~ : Int32, reencoded~ : String, original~ : String)
  /// 私钥非法，签不出来。
  Invalid(reason~ : String)
}

///|
pub impl Show for ResignOutcome with fn to_string(self) -> String {
  match self {
    Ok => "ok"
    Mismatch(offset~, reencoded~, original~) =>
      "mismatch at byte \{offset}: re-encoded \{reencoded}, txbytes \{original}"
    Invalid(reason~) => "invalid signature: \{reason}"
  }
}

///|
pub extend ResignOutcome with Show::{to_string, output}

///|
/// `SecpError` 没有 `Show`，在边界处补文案。
pub fn describe_secp_error(e : @crypto.SecpError) -> String {
  match e {
    InvalidPrivateKey => "private key not in [1, n-1]"
    InvalidScalar => "signature scalar not in [1, n-1]"
    InvalidDigestLength(actual~) => "digest is \{actual} bytes, expected 32"
    InvalidPublicKey => "invalid public key encoding"
    InvalidSignatureLength(actual~) =>
      "signature is \{actual} bytes, expected 64"
    InvalidRecoveryId(id~) => "recovery id \{id} not in 0..3"
    NotInvertible => "scalar is zero"
    RecoveryFailed => "public key recovery failed"
  }
}

// ---------------------------------------------------------------------------
// 地址推导
// ---------------------------------------------------------------------------

///|
/// `secretKey -> 地址`。私钥非法时返回 `None`（不是 panic）。
pub fn address_from_secret_key(secret_key : @types.U256) -> @types.Address? {
  let public_key = @crypto.secp_generate_public_key(secret_key) catch {
    _ => return None
  }
  Some(@crypto.secp_public_key_to_address(public_key))
}

///|
/// 从解码结果恢复签名者地址。
///
/// `r` / `s` 越界、`yParity` 非法、`R` 不在曲线上都会返回 `None`——这些正是
/// invalid fixture 的形态。
pub fn recover_sender(tx : DecodedTx) -> @types.Address? {
  let sig_bytes = FixedArray::make(64, b'\x00')
  let rb = tx.r.to_bytes_be()
  let sb = tx.s.to_bytes_be()
  for i in 0..<32 {
    sig_bytes[i] = rb[i]
    sig_bytes[32 + i] = sb[i]
  }
  let signature = @crypto.Signature::from_bytes(
    Bytes::from_array(sig_bytes)[:],
    tx.y_parity,
  ) catch {
    _ => return None
  }
  let public_key = @crypto.secp_recover(tx.signing_hash.as_bytes(), signature) catch {
    _ => return None
  }
  Some(@crypto.secp_public_key_to_address(public_key))
}

// ---------------------------------------------------------------------------
// 重签
// ---------------------------------------------------------------------------

///|
/// 用 `secret_key` 重签并逐字节比对 `raw`。
pub fn resign(
  tx : DecodedTx,
  raw : BytesView,
  secret_key : @types.U256,
) -> ResignOutcome {
  let signature = @crypto.secp_sign(tx.signing_hash.as_bytes(), secret_key) catch {
    e => return ResignOutcome::Invalid(reason="sign: \{describe_secp_error(e)}")
  }
  let reencoded = tx.encode_with(signature.r(), signature.s())
  compare_bytes(reencoded[:], raw)
}

///|
/// 逐字节比较；不一致时给出第一个差异位置与两侧的十六进制片段（各 8 字节）。
///
/// 参数命名按语义：`reencoded` 是用 fixture 私钥重签后重编码的字节，`original` 是
/// txbytes 的原始字节。比较结果里也沿用这一对名字，避免出现「expected 其实是重算值」
/// 这类反读。
fn compare_bytes(reencoded : BytesView, original : BytesView) -> ResignOutcome {
  let n = reencoded.length()
  let m = original.length()
  let limit = if n < m { n } else { m }
  let mut i = 0
  while i < limit {
    if reencoded[i] != original[i] {
      return ResignOutcome::Mismatch(
        offset=i,
        reencoded=fragment_hex(reencoded, i),
        original=fragment_hex(original, i),
      )
    }
    i = i + 1
  }
  if n == m {
    ResignOutcome::Ok
  } else {
    // 前缀一致但长度不同：差异从较短一侧的末尾开始。
    ResignOutcome::Mismatch(
      offset=limit,
      reencoded=fragment_hex(reencoded, limit),
      original=fragment_hex(original, limit),
    )
  }
}

///|
fn fragment_hex(data : BytesView, start : Int32) -> String {
  let end = if start + 8 < data.length() { start + 8 } else { data.length() }
  if start >= data.length() {
    "<end>"
  } else {
    @types.hex_encode(data[start:end])
  }
}

// ---------------------------------------------------------------------------
// JSON 向量 vs 解码字段
// ---------------------------------------------------------------------------

///|
/// 核对 fixture 里被 `indexes` 选中的向量与解码出的字段，返回不一致项的描述。
///
/// 只比「两边都有明确值」的字段：legacy pre-EIP-155 没有 `chainId`，就不要求
/// 它与 `config.chainid` 相等；`accessLists` 字段缺失时也不比。
///
/// **不比 `chainId` 与 `config.chainid`**：EEST 的 `transaction` 没有 `chainId` 字段
/// （chainId 只在 `config` 里），所以这不是「JSON 向量 vs 解码字段」的核对，而是
/// 「交易是否属于本链」的 consensus 判定——`test_valid_tx_invalid_chain_id` 这类
/// fixture 的交易刻意用别的 chainId 签名且仍然合法，放在这里会误报。该判定属 C12。
pub fn check_fields(case : Case, tx : DecodedTx) -> Array[String] {
  let diffs : Array[String] = []
  if case.nonce != tx.nonce {
    diffs.push("nonce: json=\{case.nonce} tx=\{tx.nonce}")
  }
  if case.gas_limit != tx.gas_limit {
    diffs.push("gasLimit: json=\{case.gas_limit} tx=\{tx.gas_limit}")
  }
  if case.value != tx.value {
    diffs.push("value: json=\{case.value} tx=\{tx.value}")
  }
  if !bytes_equal(case.data, tx.data) {
    diffs.push(
      "data: json=\{@types.hex_encode(case.data[:])} tx=\{@types.hex_encode(tx.data[:])}",
    )
  }
  if !same_optional_address(case.to, tx.to) {
    diffs.push(
      "to: json=\{show_opt_address(case.to)} tx=\{show_opt_address(tx.to)}",
    )
  }
  match tx.gas_price {
    Some(price) =>
      if case.gas_price != price {
        diffs.push("gasPrice: json=\{case.gas_price} tx=\{price}")
      }
    None => ()
  }
  match tx.max_priority_fee_per_gas {
    Some(v) =>
      if case.max_priority_fee_per_gas != v {
        diffs.push(
          "maxPriorityFeePerGas: json=\{case.max_priority_fee_per_gas} tx=\{v}",
        )
      }
    None => ()
  }
  match tx.max_fee_per_gas {
    Some(v) =>
      if case.max_fee_per_gas != v {
        diffs.push("maxFeePerGas: json=\{case.max_fee_per_gas} tx=\{v}")
      }
    None => ()
  }
  if !same_access_list(case.access_list, tx.access_list) {
    diffs.push(
      "accessList: json=\{describe_access_list(case.access_list)} tx=\{describe_access_list(tx.access_list)}",
    )
  }
  match tx.max_fee_per_blob_gas {
    Some(v) =>
      if case.max_fee_per_blob_gas != v {
        diffs.push(
          "maxFeePerBlobGas: json=\{case.max_fee_per_blob_gas} tx=\{v}",
        )
      }
    None => ()
  }
  if !same_hash_list(case.blob_versioned_hashes, tx.blob_versioned_hashes) {
    diffs.push("blobVersionedHashes differ")
  }
  diffs
}

///|
fn bytes_equal(a : Bytes, b : Bytes) -> Bool {
  a == b
}

///|
fn same_optional_address(a : @types.Address?, b : @types.Address?) -> Bool {
  match (a, b) {
    (None, None) => true
    (Some(x), Some(y)) => x == y
    _ => false
  }
}

///|
fn show_opt_address(a : @types.Address?) -> String {
  match a {
    Some(x) => x.to_hex()
    None => "<create>"
  }
}

///|
fn same_hash_list(a : Array[@types.Hash32], b : Array[@types.Hash32]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

///|
fn same_access_list(a : Array[AccessTuple], b : Array[AccessTuple]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if !a[i].same(b[i]) {
      return false
    }
  }
  true
}

///|
fn describe_access_list(list : Array[AccessTuple]) -> String {
  let buf = StringBuilder()
  buf.write_string("[\{list.length()} tuples]")
  buf.to_string()
}
