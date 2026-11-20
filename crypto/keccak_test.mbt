// Keccak-256 已知答案测试。
//
// 期望摘要来自独立实现（pycryptodome 的 `Crypto.Hash.keccak`），覆盖所有块边界：
// 空输入、不足一个 rate、恰好一个 rate、多一个字节、多块。

///|
fn pattern(n : Int32) -> Bytes {
  let out = FixedArray::make(n, b'\x00')
  for i in 0..<n {
    out[i] = ((i * 7 + 11) % 256).to_byte()
  }
  Bytes::from_array(out)
}

///|
test "keccak256 known answers" {
  let cases : Array[(Int32, String)] = [
    (0, "c5d2460186f7233c927e7db2dcc703c0e500b653ca82273b7bfad8045d85a470"),
    (1, "60811857dd566889ff6255277d82526f2d9b3bbcb96076be22a5860765ac3d06"),
    (2, "1a7465acf22d8e3a382f76382110ee76bcdbe8bb18408f7561442e0916919a30"),
    (3, "1266684278052a8d32eca2a636e7b3fd8c55691d0428499ff607b5d6a878d5df"),
    (55, "0c09f983eeee007de1d90925738ce0c05ef1e9debd06572b80ff1a94bc2ccb46"),
    (56, "291d90ea34eb23c05a67693845c9253d31d57a282ee69bd26ad706722bb27ef9"),
    (135, "47a414666f08a4658719043e5045638ef1ff99cb09400eff6289e6dc80c0970a"),
    (136, "91bac0515ccd2811f7b65984a2971e3d6093ccb9fac349b14c048499c2832e81"),
    (137, "2f6ff8190b36c8fb07cd335ea4f242fdca62380df126f23aba320b8e74be3d63"),
    (271, "67cd16d4b81d9371024e85c926ca78b79b5ff4447847f21f42678d7adc3a1c8b"),
    (272, "490d7f50c63ba285913a6e03deb33641fa06e0870a192f253c10fdc8e556e7c8"),
    (300, "6bb5f45c7de136620b928d7a8cdb07c32038adc023d6934a8ed91abc976375cf"),
  ]
  for c in cases {
    let (n, expected) = c
    let digest = @crypto.keccak256(pattern(n)[:])
    assert_eq(@types.hex_encode(digest.as_bytes()), expected)
  }
}

///|
test "keccak256 ascii vectors" {
  assert_eq(
    @crypto.keccak256(b"abc"[:]).to_hex(),
    "0x4e03657aea45a94fc7d47ba826c8d667c0d1e6e33a64a036ec44f58fa12d6c45",
  )
  assert_eq(
    @crypto.keccak256(b"The quick brown fox jumps over the lazy dog"[:]).to_hex(),
    "0x4d741b6f1eb29cb2a9b9911c82f56fa8d73b04959d3d9d222895df6c0b28aa15",
  )
}
