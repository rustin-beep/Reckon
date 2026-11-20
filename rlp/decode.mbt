// 规范 RLP 解码。

///|
/// 解码一个条目，要求正好消耗全部输入。
pub fn decode(data : BytesView) -> Item raise RlpError {
  let (item, next) = decode_at(data, 0)
  if next != data.length() {
    raise RlpError::TrailingBytes(count=data.length() - next)
  }
  item
}

///|
/// 从 `pos` 起读 `n` 字节的大端长度。
fn read_length(
  data : BytesView,
  pos : Int32,
  n : Int32,
) -> Int32 raise RlpError {
  if pos + n > data.length() {
    raise RlpError::UnexpectedEnd(needed=pos + n, available=data.length())
  }
  if data[pos] == b'\x00' {
    // A length with leading zero bytes is canonical only if the value fits in
    // fewer bytes, which means the long form was chosen unnecessarily.
    raise RlpError::NonCanonical(reason="length has leading zero byte")
  }
  let mut len = 0
  for i in 0..<n {
    if len > 0x7FFFFF {
      raise RlpError::LengthOverflow
    }
    len = len * 256 + data[pos + i].to_int()
  }
  len
}

///|
/// 解码从 `pos` 开始的条目，返回条目本身与其后第一个字节的位置。
fn decode_at(data : BytesView, pos : Int32) -> (Item, Int32) raise RlpError {
  if pos >= data.length() {
    raise RlpError::EmptyInput
  }
  let b = data[pos].to_int()
  if b < 0x80 {
    // a single byte below 0x80 is its own encoding
    (Item::Str(data[pos:pos + 1].to_owned()), pos + 1)
  } else if b <= 0xB7 {
    let len = b - 0x80
    if len == 1 && pos + 1 < data.length() && data[pos + 1] < b'\x80' {
      raise RlpError::NonCanonical(
        reason="single byte below 0x80 must be encoded as itself",
      )
    }
    let start = pos + 1
    let end = start + len
    if end > data.length() {
      raise RlpError::UnexpectedEnd(needed=end, available=data.length())
    }
    (Item::Str(data[start:end].to_owned()), end)
  } else if b <= 0xBF {
    let n = b - 0xB7
    let len = read_length(data, pos + 1, n)
    if len < 56 {
      raise RlpError::NonCanonical(
        reason="long string form used below 56 bytes",
      )
    }
    let start = pos + 1 + n
    let end = start + len
    if end > data.length() {
      raise RlpError::UnexpectedEnd(needed=end, available=data.length())
    }
    (Item::Str(data[start:end].to_owned()), end)
  } else if b <= 0xF7 {
    let len = b - 0xC0
    let start = pos + 1
    let end = start + len
    if end > data.length() {
      raise RlpError::UnexpectedEnd(needed=end, available=data.length())
    }
    (Item::List(decode_children(data, start, end)), end)
  } else {
    let n = b - 0xF7
    let len = read_length(data, pos + 1, n)
    if len < 56 {
      raise RlpError::NonCanonical(reason="long list form used below 56 bytes")
    }
    let start = pos + 1 + n
    let end = start + len
    if end > data.length() {
      raise RlpError::UnexpectedEnd(needed=end, available=data.length())
    }
    (Item::List(decode_children(data, start, end)), end)
  }
}

///|
fn decode_children(
  data : BytesView,
  start : Int32,
  end : Int32,
) -> Array[Item] raise RlpError {
  let items : Array[Item] = []
  let mut cur = start
  while cur < end {
    let (child, next) = decode_at(data, cur)
    if next > end {
      raise RlpError::NonCanonical(reason="child overruns list payload")
    }
    items.push(child)
    cur = next
  }
  items
}
