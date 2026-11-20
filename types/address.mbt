// 20 字节账户地址。

///|
/// 20 字节的以太坊地址。
///
/// 字节长度是构造时强制的不变量，因此任何 `Address` 都可以直接编码或哈希，
/// 不需要再做校验。
#derive(Debug)
pub struct Address {
  bytes : Bytes
}

///|
pub fn Address::from_bytes(data : BytesView) -> Address raise DecodeError {
  if data.length() != 20 {
    raise DecodeError::InvalidLength(expected=20, actual=data.length())
  }
  { bytes: data.to_owned(), }
}

///|
pub fn Address::from_hex(s : String) -> Address raise DecodeError {
  Address::from_bytes(hex_decode(s)[:])
}

///|
pub fn Address::zero() -> Address {
  { bytes: Bytes::make(20, b'\x00'), }
}

///|
pub fn Address::to_bytes(self : Address) -> Bytes {
  self.bytes
}

///|
pub fn Address::as_bytes(self : Address) -> BytesView {
  self.bytes[:]
}

///|
/// 带 `0x` 前缀的小写十六进制。
pub fn Address::to_hex(self : Address) -> String {
  "0x" + hex_encode(self.bytes[:])
}

///|
pub impl Eq for Address with fn equal(self, other) -> Bool {
  self.bytes == other.bytes
}

///|
pub impl Compare for Address with fn compare(self, other) -> Int32 {
  self.bytes.compare(other.bytes)
}

///|
pub impl Hash for Address with fn hash_combine(self, hasher) -> Unit {
  hasher.combine_bytes(self.bytes)
}

///|
pub impl Show for Address with fn to_string(self) -> String {
  self.to_hex()
}

///|
pub extend Address with Eq::{equal, not_equal}

///|
pub extend Address with Compare::{compare, op_lt, op_gt, op_le, op_ge}

///|
pub extend Address with Hash::{hash, hash_combine}

///|
pub extend Address with Show::{to_string, output}

///|
pub extend Address with Debug::{to_repr}
