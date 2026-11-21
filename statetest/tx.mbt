// `txbytes` 解码：legacy（含 EIP-155）与 type 1/2/3。
//
// 只做**结构与规范性**校验：
//   - 首字节决定 envelope；`0x04`（EIP-7702）返回 `UnsupportedType(4)`，留给 P02；
//   - 字段数必须精确匹配该类型的定义；
//   - 整数字段走 `Item::as_uint` 的等价检查（拒绝前导零、超过 32 字节）；
//   - `to` 只接受空串（创建）或 20 字节；
//   - `r` / `s` 按 256 位整数原样保存，**不**在这里拒绝 `0` 或 `>= n`——
//     invalid fixture 会用到，语义判定留给 resign 阶段；
//   - `v` / `yParity` 也先保存原值；只有 legacy 的 `v` 需要解释，非法时返回
//     `BadLegacyV`。
//
// 语义判定（low-s、intrinsic gas、nonce/balance）不在本文件，属 C12。

///|
/// txbytes 解码错误。
pub suberror TxError {
  /// 输入为空。
  EmptyInput
  /// envelope 首字节不认识（`0x00`、`0x05..0x7f`、`0x80..0xbf`）。
  UnknownEnvelope(first~ : Int32)
  /// 识别但不支持的类型，目前只有 `0x04`（EIP-7702）。
  UnsupportedType(type_byte~ : Int32)
  /// 内层 RLP 解码失败（含非规范编码、尾随字节、截断）。
  Rlp(message~ : String)
  /// 字段数与该类型定义不符。
  FieldCount(expected~ : Int32, actual~ : Int32)
  /// 期望字节串，得到列表。
  FieldNotStr(field~ : String)
  /// 期望列表，得到字节串。
  FieldNotList(field~ : String)
  /// 整数字段带前导零字节（非规范）。
  NonCanonicalInt(field~ : String)
  /// 整数字段超过 32 字节。
  IntegerTooLarge(field~ : String)
  /// `to` 既不是空串也不是 20 字节。
  BadTo(length~ : Int32)
  /// access list 结构不合法。
  BadAccessList(reason~ : String)
  /// blob versioned hash 不是 32 字节。
  BadBlobHash(index~ : Int32, length~ : Int32)
  /// legacy `v` 既不是 27/28 也不是 `>= 35`。
  BadLegacyV(v~ : @types.U256)
  /// `yParity` 超出单字节范围。
  BadYParity(v~ : @types.U256)
}

///|
pub impl Show for TxError with fn to_string(self) -> String {
  match self {
    EmptyInput => "empty txbytes"
    UnknownEnvelope(first~) => "unknown tx envelope 0x\{hex2(first)}"
    UnsupportedType(type_byte~) => "unsupported tx type \{type_byte}"
    Rlp(message~) => "rlp: \{message}"
    FieldCount(expected~, actual~) =>
      "tx has \{actual} fields, expected \{expected}"
    FieldNotStr(field~) => "tx field `\{field}` is not a byte string"
    FieldNotList(field~) => "tx field `\{field}` is not a list"
    NonCanonicalInt(field~) => "tx field `\{field}` has a leading zero byte"
    IntegerTooLarge(field~) => "tx field `\{field}` exceeds 256 bits"
    BadTo(length~) => "tx `to` is \{length} bytes, expected 0 or 20"
    BadAccessList(reason~) => "tx accessList is invalid: \{reason}"
    BadBlobHash(index~, length~) =>
      "tx blobVersionedHashes[\{index}] is \{length} bytes, expected 32"
    BadLegacyV(v~) => "legacy tx v=\{v} is neither 27/28 nor >= 35"
    BadYParity(v~) => "tx yParity=\{v} does not fit in one byte"
  }
}

///|
pub extend TxError with Show::{to_string, output}

///|
fn hex2(v : Int32) -> String {
  let digits = "0123456789abcdef"
  let hi = v / 16 % 16
  let lo = v % 16
  "\{digits[hi]}\{digits[lo]}"
}

///|
/// `RlpError` 没有 `Show`（它只带数据、不带文案），这里在边界处补一层文案。
fn describe_rlp_error(e : @rlp.RlpError) -> String {
  match e {
    EmptyInput => "empty input"
    UnexpectedEnd(needed~, available~) =>
      "unexpected end: need \{needed} bytes, \{available} available"
    NonCanonical(reason~) => "non-canonical: \{reason}"
    TrailingBytes(count~) => "trailing \{count} bytes"
    ExpectedStr => "expected a byte string"
    ExpectedList => "expected a list"
    LengthOverflow => "length overflows Int32"
    DepthLimitExceeded(max~) => "nesting depth exceeds \{max}"
  }
}

// ---------------------------------------------------------------------------
// 解码结果
// ---------------------------------------------------------------------------

///|
/// 解码后的一笔交易。
///
/// `fields` 保留原始 RLP 条目（含 `v`/`yParity`、`r`、`s` 的原始编码），
/// 这样重编码时除签名外的每个字节都与输入一致，逐字节比对才有意义。
pub(all) struct DecodedTx {
  tx_type : TxType
  /// legacy pre-EIP-155 为 `None`。
  chain_id : @types.U256?
  nonce : @types.U256
  /// legacy / type1。
  gas_price : @types.U256?
  /// type2 / type3。
  max_priority_fee_per_gas : @types.U256?
  /// type2 / type3。
  max_fee_per_gas : @types.U256?
  gas_limit : @types.U256
  /// `None` 表示合约创建。
  to : @types.Address?
  value : @types.U256
  data : Bytes
  access_list : Array[AccessTuple]
  /// type3。
  max_fee_per_blob_gas : @types.U256?
  /// type3。
  blob_versioned_hashes : Array[@types.Hash32]
  /// legacy 的 `v` 或 typed 的 `yParity` 原始值。
  v : @types.U256
  /// 解释后的恢复标识：legacy 由 `v` 推出，typed 直接取 `yParity`。
  y_parity : Int32
  r : @types.U256
  s : @types.U256
  tx_hash : @types.Hash32
  /// 未签名的 RLP 载荷的 keccak。legacy 非法 `v` 时不会返回（解码期即报错）。
  signing_hash : @types.Hash32
  /// 原始 RLP 条目；长度与类型匹配（9 / 11 / 12 / 14）。
  fields : Array[@rlp.Item]
}

// ---------------------------------------------------------------------------
// 字段取值
// ---------------------------------------------------------------------------

///|
fn as_list(item : @rlp.Item, field : String) -> Array[@rlp.Item] raise TxError {
  match item {
    @rlp.Item::List(items) => items
    @rlp.Item::Str(_) => raise TxError::FieldNotList(field~)
  }
}

///|
fn as_str(item : @rlp.Item, field : String) -> Bytes raise TxError {
  match item {
    @rlp.Item::Str(b) => b
    @rlp.Item::List(_) => raise TxError::FieldNotStr(field~)
  }
}

///|
/// 整数字段：拒绝前导零（非规范）与超过 32 字节。
fn as_uint(item : @rlp.Item, field : String) -> @types.U256 raise TxError {
  let b = as_str(item, field)
  if b.length() > 32 {
    raise TxError::IntegerTooLarge(field~)
  }
  if b.length() > 1 && b[0] == b'\x00' {
    raise TxError::NonCanonicalInt(field~)
  }
  let v = @types.U256::from_bytes_be(b[:]) catch {
    _ => raise TxError::IntegerTooLarge(field~)
  }
  v
}

///|
fn as_to(item : @rlp.Item) -> @types.Address? raise TxError {
  let b = as_str(item, "to")
  if b.length() == 0 {
    None
  } else if b.length() == 20 {
    let address = @types.Address::from_bytes(b[:]) catch {
      _ => raise TxError::BadTo(length=b.length())
    }
    Some(address)
  } else {
    raise TxError::BadTo(length=b.length())
  }
}

///|
fn as_bytes(item : @rlp.Item, field : String) -> Bytes raise TxError {
  as_str(item, field)
}

///|
fn as_access_list(item : @rlp.Item) -> Array[AccessTuple] raise TxError {
  let entries = as_list(item, "accessList")
  let out : Array[AccessTuple] = []
  for i in 0..<entries.length() {
    let pair = as_list(entries[i], "accessList[\{i}]")
    if pair.length() != 2 {
      raise TxError::BadAccessList(
        reason="entry \{i} has \{pair.length()} items, expected 2",
      )
    }
    let address = {
      let b = as_bytes(pair[0], "accessList[\{i}].address")
      if b.length() != 20 {
        raise TxError::BadAccessList(
          reason="entry \{i} address is \{b.length()} bytes",
        )
      }
      let a = @types.Address::from_bytes(b[:]) catch {
        _ =>
          raise TxError::BadAccessList(
            reason="entry \{i} address is \{b.length()} bytes",
          )
      }
      a
    }
    let keys_json = as_list(pair[1], "accessList[\{i}].storageKeys")
    let keys : Array[@types.Hash32] = []
    for k in 0..<keys_json.length() {
      let b = as_bytes(keys_json[k], "accessList[\{i}].storageKeys[\{k}]")
      if b.length() != 32 {
        raise TxError::BadAccessList(
          reason="entry \{i} storage key \{k} is \{b.length()} bytes",
        )
      }
      let h = @types.Hash32::from_bytes(b[:]) catch {
        _ =>
          raise TxError::BadAccessList(
            reason="entry \{i} storage key \{k} is \{b.length()} bytes",
          )
      }
      keys.push(h)
    }
    out.push({ address, storage_keys: keys, })
  }
  out
}

///|
fn as_blob_hashes(item : @rlp.Item) -> Array[@types.Hash32] raise TxError {
  let items = as_list(item, "blobVersionedHashes")
  let out : Array[@types.Hash32] = []
  for i in 0..<items.length() {
    let b = as_bytes(items[i], "blobVersionedHashes[\{i}]")
    if b.length() != 32 {
      raise TxError::BadBlobHash(index=i, length=b.length())
    }
    let h = @types.Hash32::from_bytes(b[:]) catch {
      _ => raise TxError::BadBlobHash(index=i, length=b.length())
    }
    out.push(h)
  }
  out
}

///|
/// typed 的 `yParity`：单字节范围。
fn as_y_parity(item : @rlp.Item) -> (@types.U256, Int32) raise TxError {
  let v = as_uint(item, "yParity")
  if v.limb(1) != 0UL || v.limb(2) != 0UL || v.limb(3) != 0UL {
    raise TxError::BadYParity(v~)
  }
  let lo = v.limb(0)
  if lo > 255UL {
    raise TxError::BadYParity(v~)
  }
  (v, lo.to_int())
}

// ---------------------------------------------------------------------------
// legacy `v` 解释
// ---------------------------------------------------------------------------

///|
/// legacy 的 `v`：
///   - `27` / `28` -> 无 chainId，`yParity = v - 27`；
///   - `>= 35`     -> `chainId = (v - 35) / 2`，`yParity = (v - 35) % 2`。
fn legacy_v(v : @types.U256) -> (@types.U256?, Int32) raise TxError {
  let v27 = @types.U256::from_u64(27UL)
  let v28 = @types.U256::from_u64(28UL)
  let v35 = @types.U256::from_u64(35UL)
  if v == v27 {
    (None, 0)
  } else if v == v28 {
    (None, 1)
  } else if v >= v35 {
    let (offset, _) = v.overflowing_sub(v35)
    let chain_id = offset.shr(1)
    let parity = (offset & @types.U256::one()).to_u64().to_int()
    (Some(chain_id), parity)
  } else {
    raise TxError::BadLegacyV(v~)
  }
}

// ---------------------------------------------------------------------------
// 重编码 / signing payload
// ---------------------------------------------------------------------------

///|
/// 最简大端编码的整数条目；零编码为空串。
fn uint_item(v : @types.U256) -> @rlp.Item {
  @rlp.Item::Str(@rlp.uint_bytes(v))
}

///|
/// 未签名的 RLP 载荷（`Item::List`）。
///
/// legacy pre-155 是 6 个字段；EIP-155 追加 `chainId, 0, 0`；typed 是去掉
/// 末尾三个字段（`yParity` / `r` / `s`）后的全部字段。
pub fn DecodedTx::unsigned_item(self : DecodedTx) -> @rlp.Item {
  let n = self.fields.length()
  let unsigned_count = n - 3
  let items : Array[@rlp.Item] = []
  for i in 0..<unsigned_count {
    items.push(self.fields[i])
  }
  match self.tx_type {
    Legacy =>
      match self.chain_id {
        None => ()
        Some(chain_id) => {
          items.push(uint_item(chain_id))
          items.push(@rlp.Item::Str(Bytes::make(0, b'\x00')))
          items.push(@rlp.Item::Str(Bytes::make(0, b'\x00')))
        }
      }
    _ => ()
  }
  @rlp.Item::List(items)
}

///|
/// signing hash：`keccak(unsigned 载荷)`，typed 前置一个类型字节。
pub fn DecodedTx::compute_signing_hash(self : DecodedTx) -> @types.Hash32 {
  let payload = @rlp.encode(self.unsigned_item())
  match self.tx_type {
    Legacy => @crypto.keccak256(payload[:])
    _ => {
      let type_byte = match self.tx_type {
        Type1 => b'\x01'
        Type2 => b'\x02'
        Type3 => b'\x03'
        _ => b'\x00'
      }
      let buf = FixedArray::make(payload.length() + 1, b'\x00')
      buf[0] = type_byte
      for i in 0..<payload.length() {
        buf[1 + i] = payload[i]
      }
      @crypto.keccak256(Bytes::from_array(buf)[:])
    }
  }
}

///|
/// 用给定的 `(r, s)` 重新编码整笔交易，签名以外的字节与解码输入一致。
///
/// legacy 的 `v` 与 typed 的 `yParity` 都用原始条目，不做规范化；这样逐字节
/// 比对能把「原始 `v` 编码非规范」也算作差异。
pub fn DecodedTx::encode_with(
  self : DecodedTx,
  r : @types.U256,
  s : @types.U256,
) -> Bytes {
  let n = self.fields.length()
  let items : Array[@rlp.Item] = []
  for i in 0..<(n - 3) {
    items.push(self.fields[i])
  }
  items.push(self.fields[n - 3])
  items.push(uint_item(r))
  items.push(uint_item(s))
  let body = @rlp.encode(@rlp.Item::List(items))
  match self.tx_type {
    Legacy => body
    _ => {
      let type_byte = match self.tx_type {
        Type1 => b'\x01'
        Type2 => b'\x02'
        Type3 => b'\x03'
        _ => b'\x00'
      }
      let buf = FixedArray::make(body.length() + 1, b'\x00')
      buf[0] = type_byte
      for i in 0..<body.length() {
        buf[1 + i] = body[i]
      }
      Bytes::from_array(buf)
    }
  }
}

// ---------------------------------------------------------------------------
// 解码入口
// ---------------------------------------------------------------------------

///|
/// 解码一笔交易的 wire 字节。
pub fn decode_tx(raw : BytesView) -> DecodedTx raise TxError {
  if raw.length() == 0 {
    raise TxError::EmptyInput
  }
  let first = raw[0].to_int()
  if first >= 0xC0 {
    decode_legacy(raw)
  } else if first == 0x04 {
    raise TxError::UnsupportedType(type_byte=first)
  } else if first >= 0x01 && first <= 0x03 {
    decode_typed(raw, first)
  } else {
    raise TxError::UnknownEnvelope(first~)
  }
}

///|
fn rlp_root(raw : BytesView) -> @rlp.Item raise TxError {
  let item = @rlp.decode(raw) catch {
    e => raise TxError::Rlp(message=describe_rlp_error(e))
  }
  item
}

///|
fn decode_legacy(raw : BytesView) -> DecodedTx raise TxError {
  let fields = as_list(rlp_root(raw), "<tx>")
  if fields.length() != 9 {
    raise TxError::FieldCount(expected=9, actual=fields.length())
  }
  let nonce = as_uint(fields[0], "nonce")
  let gas_price = as_uint(fields[1], "gasPrice")
  let gas_limit = as_uint(fields[2], "gasLimit")
  let to = as_to(fields[3])
  let value = as_uint(fields[4], "value")
  let data = as_bytes(fields[5], "data")
  let empty_access : Array[AccessTuple] = []
  let empty_blob_hashes : Array[@types.Hash32] = []
  let v = as_uint(fields[6], "v")
  let r = as_uint(fields[7], "r")
  let s = as_uint(fields[8], "s")
  let (chain_id, y_parity) = legacy_v(v)
  let tx = {
    tx_type: Legacy,
    chain_id,
    nonce,
    gas_price: Some(gas_price),
    max_priority_fee_per_gas: None,
    max_fee_per_gas: None,
    gas_limit,
    to,
    value,
    data,
    access_list: empty_access,
    max_fee_per_blob_gas: None,
    blob_versioned_hashes: empty_blob_hashes,
    v,
    y_parity,
    r,
    s,
    tx_hash: @crypto.keccak256(raw),
    signing_hash: @types.Hash32::zero(),
    fields,
  }
  { ..tx, signing_hash: tx.compute_signing_hash(), }
}

///|
fn decode_typed(raw : BytesView, type_byte : Int32) -> DecodedTx raise TxError {
  let fields = as_list(rlp_root(raw[1:]), "<tx>")
  let expected = match type_byte {
    1 => 11
    2 => 12
    _ => 14
  }
  if fields.length() != expected {
    raise TxError::FieldCount(expected~, actual=fields.length())
  }
  let tx_type = match type_byte {
    1 => Type1
    2 => Type2
    _ => Type3
  }
  let chain_id = as_uint(fields[0], "chainId")
  let nonce = as_uint(fields[1], "nonce")
  let (gas_price, max_priority_fee_per_gas, max_fee_per_gas, gas_limit_idx) = match
    tx_type {
    Type1 => (Some(as_uint(fields[2], "gasPrice")), None, None, 3)
    _ =>
      (
        None,
        Some(as_uint(fields[2], "maxPriorityFeePerGas")),
        Some(as_uint(fields[3], "maxFeePerGas")),
        4,
      )
  }
  let gas_limit = as_uint(fields[gas_limit_idx], "gasLimit")
  let to = as_to(fields[gas_limit_idx + 1])
  let value = as_uint(fields[gas_limit_idx + 2], "value")
  let data = as_bytes(fields[gas_limit_idx + 3], "data")
  let access_list = as_access_list(fields[gas_limit_idx + 4])
  let has_blob = match tx_type {
    Type3 => true
    _ => false
  }
  let max_fee_per_blob_gas = if has_blob {
    Some(as_uint(fields[gas_limit_idx + 5], "maxFeePerBlobGas"))
  } else {
    None
  }
  let empty_blob_hashes : Array[@types.Hash32] = []
  let blob_versioned_hashes = if has_blob {
    as_blob_hashes(fields[gas_limit_idx + 6])
  } else {
    empty_blob_hashes
  }
  let parity_index = fields.length() - 3
  let (v, y_parity) = as_y_parity(fields[parity_index])
  let r = as_uint(fields[parity_index + 1], "r")
  let s = as_uint(fields[parity_index + 2], "s")
  let tx = {
    tx_type,
    chain_id: Some(chain_id),
    nonce,
    gas_price,
    max_priority_fee_per_gas,
    max_fee_per_gas,
    gas_limit,
    to,
    value,
    data,
    access_list,
    max_fee_per_blob_gas,
    blob_versioned_hashes,
    v,
    y_parity,
    r,
    s,
    tx_hash: @crypto.keccak256(raw),
    signing_hash: @types.Hash32::zero(),
    fields,
  }
  { ..tx, signing_hash: tx.compute_signing_hash(), }
}
