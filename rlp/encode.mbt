// 规范 RLP 编码。

///|
/// `v` 的最简大端表示占多少字节（按 RLP 整数约定，零编码为空串）。
pub fn uint_len(v : @types.U256) -> Int32 {
  (v.bit_length() + 7) / 8
}

///|
/// `v` 的最简大端字节；零变成空串。
pub fn uint_bytes(v : @types.U256) -> Bytes {
  let n = uint_len(v)
  let full = v.to_bytes_be()
  if n == 32 {
    full
  } else {
    full[32 - n:].to_owned()
  }
}

///|
/// `item` 编码后的字节数。
fn encoded_len(item : Item) -> Int32 {
  let payload = match item {
    Str(b) =>
      // a single byte below 0x80 is its own encoding: no header at all
      if b.length() == 1 && b[0] < b'\x80' {
        return 1
      } else {
        b.length()
      }
    List(items) => {
      let mut total = 0
      for child in items {
        total = total + encoded_len(child)
      }
      total
    }
  }
  payload + header_len(payload)
}

///|
/// 0x80/0xc0 风格的头。字符串用 `base = 0x80`，列表用 0xc0。
fn header_len(payload : Int32) -> Int32 {
  if payload < 56 {
    1
  } else {
    1 + int_be_len(payload)
  }
}

///|
fn int_be_len(v : Int32) -> Int32 {
  let mut n = 0
  let mut x = v
  while x > 0 {
    n = n + 1
    x = x / 256
  }
  n
}

///|
fn write_header(
  buf : FixedArray[Byte],
  pos : Int32,
  base : Int32,
  payload : Int32,
) -> Int32 {
  if payload < 56 {
    buf[pos] = (base + payload).to_byte()
    pos + 1
  } else {
    let n = int_be_len(payload)
    buf[pos] = (base + 55 + n).to_byte()
    let mut p = pos + 1 + n - 1
    let mut x = payload
    while x > 0 {
      buf[p] = (x % 256).to_byte()
      x = x / 256
      p = p - 1
    }
    pos + 1 + n
  }
}

///|
fn write_item(buf : FixedArray[Byte], pos : Int32, item : Item) -> Int32 {
  match item {
    Str(b) =>
      if b.length() == 1 && b[0] < b'\x80' {
        buf[pos] = b[0]
        pos + 1
      } else {
        let p = write_header(buf, pos, 0x80, b.length())
        for i in 0..<b.length() {
          buf[p + i] = b[i]
        }
        p + b.length()
      }
    List(items) => {
      let mut payload = 0
      for child in items {
        payload = payload + encoded_len(child)
      }
      let mut p = write_header(buf, pos, 0xc0, payload)
      for child in items {
        p = write_item(buf, p, child)
      }
      p
    }
  }
}

///|
/// `item` 的规范 RLP 编码。
pub fn encode(item : Item) -> Bytes {
  let n = encoded_len(item)
  let buf = FixedArray::make(n, b'\x00')
  let end = write_item(buf, 0, item)
  if end != n {
    abort("rlp::encode: size mismatch")
  }
  Bytes::from_array(buf)
}

///|
/// 编码字节串。
pub fn encode_str(data : BytesView) -> Bytes {
  encode(Item::Str(data.to_owned()))
}

///|
/// 编码子条目列表。
pub fn encode_list(items : Array[Item]) -> Bytes {
  encode(Item::List(items))
}

///|
/// 以最简大端形式编码无符号整数（零 -> 空串）。
pub fn encode_uint(v : @types.U256) -> Bytes {
  encode(Item::Str(uint_bytes(v)))
}
