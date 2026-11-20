// RLP 条目树：只有字节串与列表，没有别的。

///|
/// 一个 RLP 条目。`Str` 同时表示“字符串”和字节数组；RLP 不区分文本与二进制。
pub(all) enum Item {
  Str(Bytes)
  List(Array[Item])
}

///|
pub fn Item::is_list(self : Item) -> Bool {
  match self {
    List(_) => true
    Str(_) => false
  }
}

///|
pub fn Item::as_bytes(self : Item) -> Bytes raise RlpError {
  match self {
    Str(b) => b
    List(_) => raise RlpError::ExpectedStr
  }
}

///|
pub fn Item::as_list(self : Item) -> Array[Item] raise RlpError {
  match self {
    List(items) => items
    Str(_) => raise RlpError::ExpectedList
  }
}

///|
/// 把字符串条目解释为无符号大端整数。
///
/// RLP 整数要求最小编码，因此前导零字节属于非规范编码，这里直接拒绝而不是默默接受。
pub fn Item::as_uint(self : Item) -> @types.U256 raise {
  let b = self.as_bytes()
  let n = b.length()
  if n > 32 {
    raise RlpError::LengthOverflow
  }
  if n > 1 && b[0] == b'\x00' {
    raise RlpError::NonCanonical(reason="integer has leading zero byte")
  }
  @types.U256::from_bytes_be(b[:])
}
