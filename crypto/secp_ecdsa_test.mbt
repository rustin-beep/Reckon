// ECDSA 公共 API 测试：RFC 6979 向量、geth ecrecover 向量、malleable 恢复、
// 非法输入。全部只走公开接口（黑盒），向量来源在每个用例上注明。

///|
fn u256_hex(s : String) -> @types.U256 raise {
  @types.U256::from_hex(s)
}

///|
fn sig_hex(r : String, s : String, recid : Int32) -> @crypto.Signature raise {
  @crypto.Signature::from_bytes(@types.hex_decode(r + s)[:], recid)
}

///|
fn priv_one() -> @types.U256 {
  @types.U256::one()
}

///|
test "RFC 6979 向量 1：d=1, SHA256(\"Satoshi Nakamoto\")" {
  // 向量来源：bitcoin/secp256k1 社区流传的 RFC 6979 已知答案，已被独立实现复现；
  // 本次又用纯 Python HMAC-SHA256 实现重算过（见 B05 报告）。
  let digest = @types.hex_decode(
    "a0dc65ffca799873cbea0ac274015b9526505daaaed385155425f7337704883e",
  )
  let sig = @crypto.secp_sign(digest[:], priv_one())
  assert_eq(
    @types.hex_encode(sig.r().to_bytes_be()[:]),
    "934b1ea10a4b3c1757e2b0c017d0b6143ce3c9a7e6a4a49860d7a6ab210ee3d8",
  )
  assert_eq(
    @types.hex_encode(sig.s().to_bytes_be()[:]),
    "2442ce9d2b916064108014783e923ec36b49743e2ffa1c4496f01a512aafd9e5",
  )
  assert_eq(sig.recid(), 1)
  assert_true(sig.is_low_s())
}

///|
test "ETH 向量 2：testPrivHex + keccak256(\"foo\") + 地址" {
  // 私钥与地址来自 geth `crypto/crypto_test.go` 的 testPrivHex / testAddrHex；
  // r/s 由独立 RFC 6979 oracle 生成（k 见报告）。
  let key = u256_hex(
    "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
  )
  let digest = @crypto.keccak256(b"foo"[:])
  assert_eq(
    digest.to_hex(),
    "0x41b1a0649752af1b28b3dc29a1556eee781e4a4c3a1f7f53f90fa834de098c4d",
  )
  let sig = @crypto.secp_sign(digest.as_bytes(), key)
  assert_eq(
    @types.hex_encode(sig.r().to_bytes_be()[:]),
    "d155e94305af7e07dd8c32873e5c03cb95c9e05960ef85be9c07f671da58c737",
  )
  assert_eq(
    @types.hex_encode(sig.s().to_bytes_be()[:]),
    "18c19adc397a211aa9e87e519e2038c5a3b658618db335f74f800b8e0cfeef44",
  )
  assert_eq(sig.recid(), 1)
  // 公钥与地址
  let pubkey = @crypto.secp_generate_public_key(key)
  assert_eq(
    @types.hex_encode(pubkey.x().to_bytes_be()[:]),
    "7db227d7094ce215c3a0f57e1bcc732551fe351f94249471934567e0f5dc1bf7",
  )
  assert_eq(
    @types.hex_encode(pubkey.y().to_bytes_be()[:]),
    "95962b8cccb87a2eb56b29fbe37d614e2f4c3c45b789ae4f1f51f4cb21972ffd",
  )
  assert_eq(
    @crypto.secp_public_key_to_address(pubkey).to_hex(),
    "0x970e8128ab834e8eac17ab8e3812f010678cf791",
  )
}

///|
test "geth TestEcrecover 向量 3：recover 回公钥与地址" {
  // 向量来自 geth `crypto/signature_test.go` 的 TestEcrecover（r||s||v = ...01）。
  let digest = @types.hex_decode(
    "ce0677bb30baa8cf067c88db9811f4333d131bf8bcf12fe7065d211dce971008",
  )
  let sig = sig_hex(
    "90f27b8b488db00b00606796d2987f6a5f59ae62ea05effe84fef5b8b0e54998", "4a691139ad57a3f0b906637673aa2f63d1f55cb1a69199d4009eea23ceaddc93",
    1,
  )
  let pubkey = @crypto.secp_recover(digest[:], sig)
  assert_eq(
    @types.hex_encode(pubkey.x().to_bytes_be()[:]),
    "e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
  assert_eq(
    @types.hex_encode(pubkey.y().to_bytes_be()[:]),
    "0a2b2667f7e725ceea70c673093bf67663e0312623c8e091b13cf2c0f11ef652",
  )
  assert_eq(
    @crypto.secp_public_key_to_address(pubkey).to_hex(),
    "0xa19d069d48d2e9392ec2bb41ecab0a72119d633b",
  )
  // 同一签名直接验签通过
  assert_true(@crypto.secp_verify(digest[:], pubkey, sig))
  // 压缩形式
  assert_eq(
    @types.hex_encode(pubkey.to_compressed_bytes()[:]),
    "02e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
}

///|
test "签名确定性 + 验签 + 恢复回原公钥" {
  let key = u256_hex(
    "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
  )
  let digest = @crypto.keccak256(b"deterministic"[:])
  let s1 = @crypto.secp_sign(digest.as_bytes(), key)
  let s2 = @crypto.secp_sign(digest.as_bytes(), key)
  assert_eq(
    @types.hex_encode(s1.to_bytes()[:]),
    @types.hex_encode(s2.to_bytes()[:]),
  )
  assert_eq(s1.recid(), s2.recid())
  let pubkey = @crypto.secp_generate_public_key(key)
  assert_true(@crypto.secp_verify(digest.as_bytes(), pubkey, s1))
  let recovered = @crypto.secp_recover(digest.as_bytes(), s1)
  assert_eq(
    @types.hex_encode(recovered.to_uncompressed_bytes()[:]),
    @types.hex_encode(pubkey.to_uncompressed_bytes()[:]),
  )
  // 签名输出必须 low-s
  assert_true(s1.is_low_s())
  assert_true(s1.recid() == 0 || s1.recid() == 1)
}

///|
test "high-s malleable：s' = n - s、recid ^= 1 恢复同一公钥" {
  let key = u256_hex(
    "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
  )
  let digest = @crypto.keccak256(b"malleable"[:])
  let sig = @crypto.secp_sign(digest.as_bytes(), key)
  let pubkey = @crypto.secp_generate_public_key(key)
  // n - s
  let n_minus_s = u256_hex(
      "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364141",
    ) -
    sig.s()
  let high = sig_hex(
    @types.hex_encode(sig.r().to_bytes_be()[:]),
    @types.hex_encode(n_minus_s.to_bytes_be()[:]),
    sig.recid() ^ 1,
  )
  assert_true(!high.is_low_s())
  // ECRECOVER 语义：high-s 不拒绝，恢复出同一公钥
  let recovered = @crypto.secp_recover(digest.as_bytes(), high)
  assert_eq(
    @types.hex_encode(recovered.to_uncompressed_bytes()[:]),
    @types.hex_encode(pubkey.to_uncompressed_bytes()[:]),
  )
  // verify 按数学定义也接受 high-s
  assert_true(@crypto.secp_verify(digest.as_bytes(), pubkey, high))
}

///|
test "digest = 2^256-1 触发标量归约路径" {
  let key = u256_hex(
    "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  )
  let digest = @types.U256::max_value().to_bytes_be()
  let sig = @crypto.secp_sign(digest[:], key)
  let pubkey = @crypto.secp_generate_public_key(key)
  assert_true(@crypto.secp_verify(digest[:], pubkey, sig))
  let recovered = @crypto.secp_recover(digest[:], sig)
  assert_eq(
    @types.hex_encode(recovered.to_uncompressed_bytes()[:]),
    @types.hex_encode(pubkey.to_uncompressed_bytes()[:]),
  )
}

///|
test "非法输入：私钥范围、标量范围、recid、摘要长度" {
  let digest = @crypto.keccak256(b"invalid"[:])
  let n_hex = "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364141"
  // 私钥 0 / n
  let mut hits = 0
  for bad_key in [@types.U256::zero(), u256_hex(n_hex)] {
    try ignore(@crypto.secp_sign(digest.as_bytes(), bad_key)) catch {
      _ => hits = hits + 1
    } noraise {
      _ => ()
    }
  }
  assert_eq(hits, 2)
  // 摘要 31 / 33 字节
  let mut dh = 0
  for n in [31, 33] {
    let buf = FixedArray::make(n, b'\x00')
    try ignore(@crypto.secp_sign(Bytes::from_array(buf)[:], priv_one())) catch {
      _ => dh = dh + 1
    } noraise {
      _ => ()
    }
  }
  assert_eq(dh, 2)
  // r/s = 0、r/s = n、recid = 4
  let zeros = @types.hex_decode("00".repeat(64))
  let mut sh = 0
  try ignore(@crypto.Signature::from_bytes(zeros[:], 0)) catch {
    _ => sh = sh + 1
  } noraise {
    _ => ()
  }
  let ns = @types.hex_decode(n_hex + n_hex)
  try ignore(@crypto.Signature::from_bytes(ns[:], 0)) catch {
    _ => sh = sh + 1
  } noraise {
    _ => ()
  }
  let ok = @types.hex_decode("01".repeat(32) + "01".repeat(32))
  try ignore(@crypto.Signature::from_bytes(ok[:], 4)) catch {
    _ => sh = sh + 1
  } noraise {
    _ => ()
  }
  assert_eq(sh, 3)
  // recid 2/3 的 x = r + n 必须按裸 256 位加法判界：r = n-1 时 x >= p，必须报错
  let sig_overflow = sig_hex(
    "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364140",
    "01".repeat(32),
    2,
  )
  let mut rh = 0
  try ignore(@crypto.secp_recover(digest.as_bytes(), sig_overflow)) catch {
    _ => rh = rh + 1
  } noraise {
    _ => ()
  }
  assert_eq(rh, 1)
  // 正例：r = 2 时 x = n + 2 < p 且落在曲线上（r < p - n 只有 ~2^-128 的概率，
  // 这个小 r 是构造出来的），recid 2 必须能恢复并验签
  let sig_lucky = sig_hex("00".repeat(31) + "02", "02".repeat(32), 2)
  let lucky_key = @crypto.secp_recover(digest.as_bytes(), sig_lucky)
  assert_true(@crypto.secp_verify(digest.as_bytes(), lucky_key, sig_lucky))
}

///|
/// `SecpError` 变体名（黑盒侧，需要包限定）。
fn secp_tag(e : @crypto.SecpError) -> String {
  match e {
    @crypto.SecpError::InvalidPrivateKey => "InvalidPrivateKey"
    @crypto.SecpError::InvalidScalar => "InvalidScalar"
    @crypto.SecpError::InvalidDigestLength(_) => "InvalidDigestLength"
    @crypto.SecpError::InvalidPublicKey => "InvalidPublicKey"
    @crypto.SecpError::InvalidSignatureLength(_) => "InvalidSignatureLength"
    @crypto.SecpError::InvalidRecoveryId(_) => "InvalidRecoveryId"
    @crypto.SecpError::NotInvertible => "NotInvertible"
    @crypto.SecpError::RecoveryFailed => "RecoveryFailed"
  }
}

///|
/// 断言抛出指定变体；不抛或抛错变体都 abort。
fn expect_secp(f : () -> Unit raise @crypto.SecpError, want : String) -> Unit {
  let mut got = ""
  try f() catch {
    e => got = secp_tag(e)
  } noraise {
    _ => ()
  }
  if got != want {
    abort(
      "期望 \{want}，实际 \{if got == "" { "未抛错" } else { got }}",
    )
  }
}

///|
test "verify 对篡改 s、错 digest、错公钥一律返回 false" {
  let key = u256_hex(
    "289c2857d4598e37fb9647507e47a309d6133539bf21a8b9cb6df88fd5232032",
  )
  let other_key = u256_hex(
    "1234567890abcdef1234567890abcdef1234567890abcdef1234567890abcdef",
  )
  let digest = @crypto.keccak256(b"verify-negative"[:])
  let other_digest = @crypto.keccak256(b"verify-negative-other"[:])
  let pubkey = @crypto.secp_generate_public_key(key)
  let other_pubkey = @crypto.secp_generate_public_key(other_key)
  let sig = @crypto.secp_sign(digest.as_bytes(), key)
  // 基线：真签名必须通过
  assert_true(@crypto.secp_verify(digest.as_bytes(), pubkey, sig))
  // 1) 篡改 s := s - 1（仍在 [1, n-1]，不会触发范围错误）
  let tampered_s = sig.s() - @types.U256::one()
  let tampered = @crypto.Signature::from_bytes(
    @types.hex_decode(
      @types.hex_encode(sig.r().to_bytes_be()[:]) +
      @types.hex_encode(tampered_s.to_bytes_be()[:]),
    )[:],
    sig.recid(),
  )
  assert_true(!@crypto.secp_verify(digest.as_bytes(), pubkey, tampered))
  // 2) 换 digest
  assert_true(!@crypto.secp_verify(other_digest.as_bytes(), pubkey, sig))
  // 3) 换公钥
  assert_true(!@crypto.secp_verify(digest.as_bytes(), other_pubkey, sig))
}

///|
test "错误变体契约：越界坐标、签名长度、recid、零标量、坏私钥" {
  let digest = @crypto.keccak256(b"variant"[:])
  // 公钥坐标 x >= p → InvalidPublicKey（不是专门的域元素错误）
  let x_ge_p = @types.hex_decode(
    "02fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f",
  )
  expect_secp(
    () => ignore(@crypto.PublicKey::parse(x_ge_p[:])),
    "InvalidPublicKey",
  )
  // 63 字节签名 → InvalidSignatureLength
  let short = @types.hex_decode("00".repeat(63))
  expect_secp(
    () => ignore(@crypto.Signature::from_bytes(short[:], 0)),
    "InvalidSignatureLength",
  )
  // recid = 4 → InvalidRecoveryId
  let ok = @types.hex_decode("01".repeat(64))
  expect_secp(
    () => ignore(@crypto.Signature::from_bytes(ok[:], 4)),
    "InvalidRecoveryId",
  )
  // r = 0 → InvalidScalar
  let zeros = @types.hex_decode("00".repeat(64))
  expect_secp(
    () => ignore(@crypto.Signature::from_bytes(zeros[:], 0)),
    "InvalidScalar",
  )
  // 私钥 0 / n → InvalidPrivateKey
  expect_secp(
    () => ignore(@crypto.secp_sign(digest.as_bytes(), @types.U256::zero())),
    "InvalidPrivateKey",
  )
  let n_hex = "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364141"
  let n_key = u256_hex(n_hex)
  expect_secp(
    () => ignore(@crypto.secp_sign(digest.as_bytes(), n_key)),
    "InvalidPrivateKey",
  )
  // 摘要 31 / 33 字节 → InvalidDigestLength
  for n in [31, 33] {
    let buf = FixedArray::make(n, b'\x00')
    expect_secp(
      () => ignore(@crypto.secp_sign(Bytes::from_array(buf)[:], priv_one())),
      "InvalidDigestLength",
    )
  }
  // recid 2 的 x = r + n 越界 → RecoveryFailed
  let sig_overflow = sig_hex(
    "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364140",
    "01".repeat(32),
    2,
  )
  expect_secp(
    () => ignore(@crypto.secp_recover(digest.as_bytes(), sig_overflow)),
    "RecoveryFailed",
  )
}

///|
test "verify 在 u1G + u2Q = O 时返回 false（不得去调仿射转换）" {
  // 构造一个「和恰为无穷远」的合法输入：Q = -G，digest 的标量 z 与 r 相等，
  // 则 u1G + u2Q = (z/s)G + (r/s)(-G) = O。这条路径若改成抛 NotInvertible
  // 或返回 true，都会让攻击者用 1 字节输入打穿验签口径。
  let neg_g = @types.hex_decode(
    "04" +
    "79be667ef9dcbbac55a06295ce870b07029bfcdb2dce28d959f2815b16f81798" +
    "b7c52588d95c3b9aa25b0403f1eef75702e84bb7597aabe663b82f6f04ef2777",
  )
  let pubkey = @crypto.PublicKey::parse(neg_g[:])
  let digest = @types.hex_decode("00".repeat(31) + "2a")
  let sig = sig_hex("00".repeat(31) + "2a", "00".repeat(31) + "01", 0)
  assert_true(!@crypto.secp_verify(digest[:], pubkey, sig))
}
