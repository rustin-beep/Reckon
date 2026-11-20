// 十六进制文本与字节互转。
//
// 解码是严格的：只接受 `[0-9a-fA-F]`，并剥掉单个 `0x` 前缀。EEST 的 JSON
// fixture 用偶数位小写十六进制，但数量字段偶尔写成奇数位，所以另给
// `_padded` 变体（左补一个 0 位）。

///|
let hex_digits : FixedArray[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', 'a', 'b', 'c', 'd', 'e', 'f',
]

///|
fn byte_to_int(b : Byte) -> Int32 {
  b.to_int()
}

///|
/// 小写十六进制编码，不带前缀。
pub fn hex_encode(data : BytesView) -> String {
  let buf = StringBuilder()
  for i in 0..<data.length() {
    let v = byte_to_int(data[i])
    buf.write_char(hex_digits[v >> 4])
    buf.write_char(hex_digits[v & 0xf])
  }
  buf.to_string()
}

///|
fn hex_prefix_len(s : String) -> Int32 {
  if s.length() >= 2 && s[0] == '0' && (s[1] == 'x' || s[1] == 'X') {
    2
  } else {
    0
  }
}

///|
fn hex_nibble(c : UInt16) -> Int32 raise DecodeError {
  let v = c.to_int()
  if v >= 48 && v <= 57 {
    v - 48
  } else if v >= 97 && v <= 102 {
    v - 97 + 10
  } else if v >= 65 && v <= 70 {
    v - 65 + 10
  } else {
    raise DecodeError::InvalidHexChar(code=v)
  }
}

///|
/// 解码必须构成整字节的十六进制串（位数为偶数）。
pub fn hex_decode(s : String) -> Bytes raise DecodeError {
  hex_decode_inner(s, false)
}

///|
/// 允许奇数位的解码：左侧补一个 0 位（`0x1` -> `[0x01]`）。
pub fn hex_decode_padded(s : String) -> Bytes raise DecodeError {
  hex_decode_inner(s, true)
}

///|
fn hex_decode_inner(s : String, allow_odd : Bool) -> Bytes raise DecodeError {
  let start = hex_prefix_len(s)
  let digits = s.length() - start
  if digits % 2 != 0 && !allow_odd {
    raise DecodeError::InvalidHexLength(length=digits)
  }
  let pad = if digits % 2 != 0 { 1 } else { 0 }
  let total = digits + pad
  let out = FixedArray::make(total / 2, b'\x00')
  for k in 0..<(total / 2) {
    let hi = if pad == 1 && k == 0 {
      0
    } else {
      hex_nibble(s[start + 2 * k - pad])
    }
    let lo = hex_nibble(s[start + 2 * k + 1 - pad])
    out[k] = ((hi << 4) | lo).to_byte()
  }
  Bytes::from_array(out)
}

///|
/// 单个字节的小写十六进制，例如 `0x0f` -> `"0f"`。
pub fn hex_byte(b : Byte) -> String {
  let v = byte_to_int(b)
  let buf = StringBuilder()
  buf.write_char(hex_digits[v >> 4])
  buf.write_char(hex_digits[v & 0xf])
  buf.to_string()
}
