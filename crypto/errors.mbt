// secp256k1 公共 API 的统一错误类型。
//
// 约定：secp 边界只抛 `SecpError`，`DecodeError` 不外泄；`verify` 对数学上
// 不成立的签名返回 `false`，只有在参数本身非法（长度、范围）时才 raise。

///|
/// secp256k1 操作的错误。
#derive(Debug)
pub suberror SecpError {
  /// 私钥不在 `[1, n-1]`。
  InvalidPrivateKey
  /// 标量 `r`/`s` 不在 `[1, n-1]`。
  InvalidScalar
  /// 摘要不是 32 字节。
  InvalidDigestLength(actual~ : Int32)
  /// 公钥编码非法：长度、前缀、坐标越界（`x/y >= p`），或压缩点无法解出曲线上的 y。
  InvalidPublicKey
  /// 签名编码长度不是 64 字节。
  InvalidSignatureLength(actual~ : Int32)
  /// 恢复标识不在 `0..3`。
  InvalidRecoveryId(id~ : Int32)
  /// 标量为零，不可逆。
  NotInvertible
  /// 恢复失败：`R` 不在曲线上，或恢复出的公钥是无穷远点。
  RecoveryFailed
}

///|
pub extend SecpError with Debug::{to_repr}
