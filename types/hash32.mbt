// 32 字节哈希（keccak 摘要；存储槽的键用 U256 表示）。

///|
/// 32 字节哈希摘要。
///
/// 命名为 `Hash32` 而非 `Hash`，避免与内建 `Hash` trait 在下游代码里歧义。
#derive(Debug)
pub struct Hash32 {
  bytes : Bytes
}

///|
pub fn Hash32::from_bytes(data : BytesView) -> Hash32 raise DecodeError {
  if data.length() != 32 {
    raise DecodeError::InvalidLength(expected=32, actual=data.length())
  }
  { bytes: data.to_owned(), }
}

///|
/// 从定长数组构造，长度不符时抛 `DecodeError`（与 `from_bytes` 一致）。
pub fn Hash32::from_fixed(data : FixedArray[Byte]) -> Hash32 raise DecodeError {
  if data.length() != 32 {
    raise DecodeError::InvalidLength(expected=32, actual=data.length())
  }
  { bytes: Bytes::from_array(data), }
}

///|
/// 调用方已保证恰好 32 字节时的快路径（如 keccak 输出），长度不符直接 abort。
pub fn Hash32::from_fixed_unchecked(data : FixedArray[Byte]) -> Hash32 {
  if data.length() != 32 {
    abort("Hash32::from_fixed_unchecked: expected 32 bytes")
  }
  { bytes: Bytes::from_array(data), }
}

///|
pub fn Hash32::from_hex(s : String) -> Hash32 raise DecodeError {
  Hash32::from_bytes(hex_decode(s)[:])
}

///|
pub fn Hash32::zero() -> Hash32 {
  { bytes: Bytes::make(32, b'\x00'), }
}

///|
pub fn Hash32::to_bytes(self : Hash32) -> Bytes {
  self.bytes
}

///|
pub fn Hash32::as_bytes(self : Hash32) -> BytesView {
  self.bytes[:]
}

///|
/// 带 `0x` 前缀的小写十六进制。
pub fn Hash32::to_hex(self : Hash32) -> String {
  "0x" + hex_encode(self.bytes[:])
}

///|
pub impl Eq for Hash32 with fn equal(self, other) -> Bool {
  self.bytes == other.bytes
}

///|
pub impl Compare for Hash32 with fn compare(self, other) -> Int32 {
  self.bytes.compare(other.bytes)
}

///|
pub impl Hash for Hash32 with fn hash_combine(self, hasher) -> Unit {
  hasher.combine_bytes(self.bytes)
}

///|
pub impl Show for Hash32 with fn to_string(self) -> String {
  self.to_hex()
}

///|
pub extend Hash32 with Eq::{equal, not_equal}

///|
pub extend Hash32 with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
pub extend Hash32 with Hash::{hash, hash_combine}

///|
pub extend Hash32 with Show::{to_string, output}

///|
pub extend Hash32 with Debug::{to_repr}
