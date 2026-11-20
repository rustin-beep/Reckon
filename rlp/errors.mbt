// 规范 RLP（以太坊的 Recursive Length Prefix）编解码。
//
// 解码强制规范形式：如果交易解码器接受非规范 RLP，就会接受没有任何 EVM 客户端
// 会产出的字节——这正是 `txbytes` 重签必须排除的分歧来源。

///|
pub suberror RlpError {
  EmptyInput
  UnexpectedEnd(needed~ : Int32, available~ : Int32)
  /// The same value has a shorter canonical encoding.
  NonCanonical(reason~ : String)
  TrailingBytes(count~ : Int32)
  ExpectedStr
  ExpectedList
  LengthOverflow
}
