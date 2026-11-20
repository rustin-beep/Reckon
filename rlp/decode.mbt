// 规范 RLP 解码。

///|
/// 嵌套深度上限。EVM 的交易/收据结构不超过 4 层；给 128 是留足余量，同时远低于
/// native 后端的栈阈（实测 500 层可过、1000 层崩），把不可信输入挡在爆栈之前。
let max_depth : Int32 = 128

///|
/// 解码一个条目，要求正好消耗全部输入。
pub fn decode(data : BytesView) -> Item raise RlpError {
  let (item, next) = decode_at(data, 0, 0)
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
  if n > data.length() - pos {
    raise RlpError::UnexpectedEnd(needed=n, available=data.length() - pos)
  }
  if data[pos] == b'\x00' {
    // 长度字段带前导零只可能出现在“本可以用更短形式”的编码里，属非规范。
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
/// 校验 `[start, start + len)` 落在输入内，并返回结束位置。
///
/// 用减法判断而不是 `start + len > length`：后者在 `len` 接近 `Int32` 上限时会
/// 溢出成负数，绕过检查（评审 P3-1）。
fn payload_end(
  data : BytesView,
  start : Int32,
  len : Int32,
) -> Int32 raise RlpError {
  let available = data.length() - start
  if len > available {
    raise RlpError::UnexpectedEnd(needed=len, available~)
  }
  start + len
}

///|
/// 解码从 `pos` 开始的条目，返回条目本身与其后第一个字节的位置。
/// `depth` 是当前嵌套层数，超过 `max_depth` 直接拒绝。
fn decode_at(
  data : BytesView,
  pos : Int32,
  depth : Int32,
) -> (Item, Int32) raise RlpError {
  if depth > max_depth {
    raise RlpError::DepthLimitExceeded(max=max_depth)
  }
  if pos >= data.length() {
    raise RlpError::EmptyInput
  }
  let b = data[pos].to_int()
  if b < 0x80 {
    // 小于 0x80 的单字节就是它自己的编码
    (Item::Str(data[pos:pos + 1].to_owned()), pos + 1)
  } else if b <= 0xB7 {
    let len = b - 0x80
    if len == 1 && pos + 1 < data.length() && data[pos + 1] < b'\x80' {
      raise RlpError::NonCanonical(
        reason="single byte below 0x80 must be encoded as itself",
      )
    }
    let start = pos + 1
    let end = payload_end(data, start, len)
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
    let end = payload_end(data, start, len)
    (Item::Str(data[start:end].to_owned()), end)
  } else if b <= 0xF7 {
    let len = b - 0xC0
    let start = pos + 1
    let end = payload_end(data, start, len)
    (Item::List(decode_children(data, start, end, depth)), end)
  } else {
    let n = b - 0xF7
    let len = read_length(data, pos + 1, n)
    if len < 56 {
      raise RlpError::NonCanonical(reason="long list form used below 56 bytes")
    }
    let start = pos + 1 + n
    let end = payload_end(data, start, len)
    (Item::List(decode_children(data, start, end, depth)), end)
  }
}

///|
fn decode_children(
  data : BytesView,
  start : Int32,
  end : Int32,
  depth : Int32,
) -> Array[Item] raise RlpError {
  let items : Array[Item] = []
  let mut cur = start
  while cur < end {
    let (child, next) = decode_at(data, cur, depth + 1)
    if next > end {
      raise RlpError::NonCanonical(reason="child overruns list payload")
    }
    items.push(child)
    cur = next
  }
  items
}
