///|
/// 把不可信字节或十六进制文本解码成值类型时抛出的错误。
///
/// 负载只带数据、不带文案，便于调用方自行组织诊断信息；解释器在边界处
/// 再把它映射成 EVM 层的错误。
#derive(Debug)
pub suberror DecodeError {
  /// 定宽值收到的字节数不对。
  InvalidLength(expected~ : Int32, actual~ : Int32)
  /// 十六进制串里出现了 `[0-9a-fA-F]` 之外的码元。
  InvalidHexChar(code~ : Int32)
  /// 要求整字节的解码器收到了奇数位十六进制串。
  InvalidHexLength(length~ : Int32)
}

///|
pub extend DecodeError with Debug::{to_repr}
