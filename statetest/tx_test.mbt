// txbytes 解码与重签测试。
//
// 4 组向量来自 EEST v5.4.0 stable（commit `4f68564f47c7e577ad6cbb570858316f5ff0e7bb`）：
//   legacy  `tests/cancun/eip1153_tstore/test_basic_tload_after_store.json`
//           （`test_basic_tload.py::test_basic_tload_after_store[fork_Cancun-state_test]`）
//   type1   `tests/cancun/eip4844_blobs/test_blobhash_opcode_contexts_tx_types.json`
//           （`[fork_Cancun-tx_type_1-state_test]`）
//   type2   同上（`[fork_Cancun-tx_type_2-state_test]`）
//   type3   `tests/cancun/eip4844_blobs/test_blob_gas_subtraction_tx.json`
//           （`…tx_max_fee_per_gas_14-access_list`，含非空 accessList 与 6 个 blob hash）
//
// `tx_hash` / `signing_hash` / `r` / `s` 由独立的 Python oracle 复算后写死
// （pycryptodome 的 keccak256 + 手写 canonical RLP + 手写 RFC 6979 low-s 签名），
// 不是从本实现的输出里抄回来的。

///|
struct Rng {
  mut state : UInt64
}

///|
fn Rng::next(self : Rng) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state
}

///|
fn bytes_from_hex(s : String) -> Bytes {
  let out = @types.hex_decode(s) catch {
    _ => abort("test vector is not valid hex")
  }
  out
}

///|
fn u256_from_hex(s : String) -> @types.U256 {
  let out = @types.U256::from_hex(s) catch {
    _ => abort("test vector is not a valid quantity")
  }
  out
}

///|
/// 求值一个可能 raise 的表达式，把错误留成 `Some`。
fn capture_tx_error(
  f : () -> Unit raise @statetest.TxError,
) -> @statetest.TxError? {
  try {
    f()
    None
  } catch {
    e => Some(e)
  }
}

///|
struct TxVector {
  label : String
  tx_type : @statetest.TxType
  txbytes : String
  tx_hash : String
  signing_hash : String
  chain_id : String
  y_parity : Int32
  r : String
  s : String
  secret_key : String
  nonce : String
  gas_limit : String
  to : String
}

///|
let tx_vectors : FixedArray[TxVector] = [
  {
    label: "legacy (EIP-155, chainId=1)",
    tx_type: @statetest.Legacy,
    txbytes: "f860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0",
    tx_hash: "3ad309551563594d167a561998a8cc1b3cc36b3103be609865b58e8e97c2dc96",
    signing_hash: "85219b4a34154d8c31c28acba9daeed0b31c5d6c10aeae80b24f51bb7fce9a27",
    chain_id: "01",
    y_parity: 0,
    r: "49c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318fa",
    s: "3336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0",
    secret_key: "f792f84d3860ff35b56caae61ad41edb9130201ba8476168bcbf9bafe279f89d",
    nonce: "00",
    gas_limit: "4c4b40",
    to: "1ad41edb9130201ba8476168bcbf9bafe279f89d",
  },
  {
    label: "type1 (EIP-2930)",
    tx_type: @statetest.Type1,
    txbytes: "01f86201800a8307a12094e196a2e4919626e6b0295a20d55a96270bcfe3c88080c001a0aa9caf322beb69597dc13419cbb63a5de96e0072a711405d26602e3fac08f909a0491d2db23400927a61b585ba993324b1e72e9a68ab0db4db73fbd44aae4b54db",
    tx_hash: "cd9e5224620bedb39e026257d2dea2609adbd08c38e7ad00f0b58811dc58acd5",
    signing_hash: "1a54680dd03902c46624a6d378126c409a02d8d04440bf6ba985b6b84cd00acc",
    chain_id: "01",
    y_parity: 1,
    r: "aa9caf322beb69597dc13419cbb63a5de96e0072a711405d26602e3fac08f909",
    s: "491d2db23400927a61b585ba993324b1e72e9a68ab0db4db73fbd44aae4b54db",
    secret_key: "135bc786697482615a015f64e196a2e4919626e6b0295a20d55a96270bcfe3c8",
    nonce: "00",
    gas_limit: "07a120",
    to: "e196a2e4919626e6b0295a20d55a96270bcfe3c8",
  },
  {
    label: "type2 (EIP-1559)",
    tx_type: @statetest.Type2,
    txbytes: "02f863018080078307a12094d02514373ea7e8f86e42cb768b69e77c38e353f78080c001a0da3b3eb4dd73620a43b06b050387f6c71fdba0f91353b86a78e621b43296d75fa01c99409665b9a1267b9a736d2f88328de03ec5efe5b876fc6de3c62f398cc411",
    tx_hash: "86dbe8fe02a7bee22ee55a6983faf6eb87c74d5b4c637dd10024bcaf385a688a",
    signing_hash: "ad498b085437270d99661a8af64e7eb937066f275a12ef3c5188a8843fa9f629",
    chain_id: "01",
    y_parity: 1,
    r: "da3b3eb4dd73620a43b06b050387f6c71fdba0f91353b86a78e621b43296d75f",
    s: "1c99409665b9a1267b9a736d2f88328de03ec5efe5b876fc6de3c62f398cc411",
    secret_key: "5572cfd376c9569fbe2bd573d02514373ea7e8f86e42cb768b69e77c38e353f7",
    nonce: "00",
    gas_limit: "07a120",
    to: "d02514373ea7e8f86e42cb768b69e77c38e353f7",
  },
  {
    label: "type3 (EIP-4844, accessList + 6 blobs)",
    tx_type: @statetest.Type3,
    txbytes: "03f901880180800e8307a120947b9a3a31b12c210a9022536a502ec9d5f2eac05e8080f85bf859940000000000000000000000000000000000000064f842a00000000000000000000000000000000000000000000000000000000000000064a000000000000000000000000000000000000000000000000000000000000000c801f8c6a00100000000000000000000000000000000000000000000000000000000000000a00100000000000000000000000000000000000000000000000000000000000001a00100000000000000000000000000000000000000000000000000000000000002a00100000000000000000000000000000000000000000000000000000000000003a00100000000000000000000000000000000000000000000000000000000000004a0010000000000000000000000000000000000000000000000000000000000000501a0b2fcf2341719f3da59893194888790fc1d88d2a79e2bd8bde079a03dbc35d620a062fb84415b792902624240a1adec1e7f54a77898649bc5d36baad6f812b46683",
    tx_hash: "eda6e548359c0acbae25ff71b387e84bacd883f67057d96c2e23d7357baa2490",
    signing_hash: "1e0335aea147275c976fbb4ce50f9dce3c4c10c23781d0e16ae8bb3c83bd33c6",
    chain_id: "01",
    y_parity: 1,
    r: "b2fcf2341719f3da59893194888790fc1d88d2a79e2bd8bde079a03dbc35d620",
    s: "62fb84415b792902624240a1adec1e7f54a77898649bc5d36baad6f812b46683",
    secret_key: "746c1f85394191ee14f33c927b9a3a31b12c210a9022536a502ec9d5f2eac05e",
    nonce: "00",
    gas_limit: "07a120",
    to: "7b9a3a31b12c210a9022536a502ec9d5f2eac05e",
  },
]

///|
test "decode_tx real vectors: header, hashes, signature" {
  for vector in tx_vectors {
    let raw = bytes_from_hex(vector.txbytes)
    let tx = @statetest.decode_tx(raw[:])
    assert_eq(tx.tx_type.to_string(), vector.tx_type.to_string())
    assert_eq(tx.tx_hash.to_hex(), "0x" + vector.tx_hash)
    assert_eq(tx.signing_hash.to_hex(), "0x" + vector.signing_hash)
    assert_eq(
      tx.chain_id.unwrap().to_hex(),
      u256_from_hex(vector.chain_id).to_hex(),
    )
    assert_eq(tx.y_parity, vector.y_parity)
    assert_eq(tx.r.to_hex(), u256_from_hex(vector.r).to_hex())
    assert_eq(tx.s.to_hex(), u256_from_hex(vector.s).to_hex())
    assert_eq(tx.nonce.to_hex(), u256_from_hex(vector.nonce).to_hex())
    assert_eq(tx.gas_limit.to_hex(), u256_from_hex(vector.gas_limit).to_hex())
    assert_eq(tx.to.unwrap().to_hex(), "0x" + vector.to)
  }
}

///|
test "decode_tx real vectors: resign is byte identical" {
  for vector in tx_vectors {
    let raw = bytes_from_hex(vector.txbytes)
    let tx = @statetest.decode_tx(raw[:])
    match @statetest.resign(tx, raw[:], u256_from_hex(vector.secret_key)) {
      @statetest.ResignOutcome::Ok => ()
      other =>
        abort(
          "\{vector.label}: expected byte-identical resign, got \{other.to_string()}",
        )
    }
    // 独立断言：secp_sign 的 r / s / yParity 与 txbytes 里的值一致。
    let sig = @crypto.secp_sign(
      tx.signing_hash.as_bytes(),
      u256_from_hex(vector.secret_key),
    ) catch {
      _ => abort("\{vector.label}: secp_sign failed")
    }
    assert_eq(sig.r().to_hex(), tx.r.to_hex())
    assert_eq(sig.s().to_hex(), tx.s.to_hex())
    assert_eq(sig.recid() & 1, tx.y_parity)
  }
}

///|
test "decode_tx real vectors: recover sender" {
  for vector in tx_vectors {
    let raw = bytes_from_hex(vector.txbytes)
    let tx = @statetest.decode_tx(raw[:])
    let recovered = @statetest.recover_sender(tx)
    let expected = @statetest.address_from_secret_key(
      u256_from_hex(vector.secret_key),
    )
    assert_true(recovered is Some(_))
    assert_eq(recovered.unwrap(), expected.unwrap())
  }
}

///|
test "decode_tx type3 fields" {
  let vector = tx_vectors[3]
  let tx = @statetest.decode_tx(bytes_from_hex(vector.txbytes)[:])
  assert_eq(tx.access_list.length(), 1)
  assert_eq(
    tx.access_list[0].address.to_hex(),
    "0x0000000000000000000000000000000000000064",
  )
  assert_eq(tx.access_list[0].storage_keys.length(), 2)
  assert_eq(tx.blob_versioned_hashes.length(), 6)
  assert_eq(
    tx.max_fee_per_blob_gas.unwrap().to_hex(),
    u256_from_hex("01").to_hex(),
  )
  assert_true(tx.gas_price is None)
  assert_eq(tx.max_fee_per_gas.unwrap().to_hex(), u256_from_hex("0e").to_hex())
}

///|
test "resign reports the first differing byte" {
  let vector = tx_vectors[0]
  let raw = bytes_from_hex(vector.txbytes)
  let tx = @statetest.decode_tx(raw[:])
  // 改掉最后一个字节（s 的末位），重签必定不同。
  let tampered = FixedArray::make(raw.length(), b'\x00')
  for i in 0..<raw.length() {
    tampered[i] = raw[i]
  }
  let last = raw.length() - 1
  tampered[last] = raw[last] ^ b'\xff'
  match
    @statetest.resign(
      tx,
      Bytes::from_array(tampered)[:],
      u256_from_hex(vector.secret_key),
    ) {
    @statetest.ResignOutcome::Mismatch(offset~, ..) => assert_eq(offset, last)
    other => abort("expected a mismatch, got \{other.to_string()}")
  }
}

// ---------------------------------------------------------------------------
// envelope 边界
// ---------------------------------------------------------------------------

///|
test "decode_tx rejects unsupported and unknown envelopes" {
  // 0x04 = EIP-7702，识别但不支持。
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(bytes_from_hex("04c0")[:]))
    }) {
    Some(@statetest.UnsupportedType(type_byte~)) => assert_eq(type_byte, 4)
    Some(other) =>
      abort("expected UnsupportedType(4), got \{other.to_string()}")
    None => abort("expected UnsupportedType(4), got Ok")
  }
  // 0x00 与 0x05..0x7f 都不是合法 envelope。
  for target in [0x00, 0x05, 0x7f] {
    let byte = FixedArray::make(1, target.to_byte())
    match
      capture_tx_error(fn() -> Unit raise @statetest.TxError {
        ignore(@statetest.decode_tx(Bytes::from_array(byte)[:]))
      }) {
      Some(@statetest.UnknownEnvelope(first~)) => assert_eq(first, target)
      Some(other) => abort("expected UnknownEnvelope, got \{other.to_string()}")
      None => abort("expected UnknownEnvelope, got Ok")
    }
  }
  // 0x80..0xbf 是 RLP 字节串，不是交易。
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(bytes_from_hex("80")[:]))
    }) {
    Some(@statetest.UnknownEnvelope(_)) => ()
    Some(other) => abort("expected UnknownEnvelope, got \{other.to_string()}")
    None => abort("expected UnknownEnvelope, got Ok")
  }
  // 空输入。
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(b""[:]))
    }) {
    Some(@statetest.EmptyInput) => ()
    Some(other) => abort("expected EmptyInput, got \{other.to_string()}")
    None => abort("expected EmptyInput, got Ok")
  }
}

///|
test "decode_tx rejects truncation and trailing bytes" {
  let raw = bytes_from_hex(tx_vectors[0].txbytes)
  let truncated = raw[:raw.length() - 1].to_owned()
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(truncated[:]))
    }) {
    Some(@statetest.Rlp(_)) => ()
    Some(other) =>
      abort("expected Rlp error on truncation, got \{other.to_string()}")
    None => abort("expected Rlp error on truncation, got Ok")
  }
  let padded = FixedArray::make(raw.length() + 1, b'\x00')
  for i in 0..<raw.length() {
    padded[i] = raw[i]
  }
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(Bytes::from_array(padded)[:]))
    }) {
    Some(@statetest.Rlp(_)) => ()
    Some(other) =>
      abort("expected Rlp error on trailing byte, got \{other.to_string()}")
    None => abort("expected Rlp error on trailing byte, got Ok")
  }
}

///|
test "decode_tx rejects wrong field counts" {
  // legacy 少一个字段（8 个）。
  let eight : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("25")),
    @rlp.Item::Str(bytes_from_hex("01")),
  ]
  let raw = @rlp.encode(@rlp.Item::List(eight))
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(raw[:]))
    }) {
    Some(@statetest.FieldCount(expected~, actual~)) => {
      assert_eq(expected, 9)
      assert_eq(actual, 8)
    }
    Some(other) => abort("expected FieldCount, got \{other.to_string()}")
    None => abort("expected FieldCount, got Ok")
  }
}

///|
test "decode_tx rejects non-canonical integers" {
  // gasPrice 写成 0x00 0x0a（前导零）。
  let fields : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("000a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("25")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let raw = @rlp.encode(@rlp.Item::List(fields))
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(raw[:]))
    }) {
    Some(@statetest.NonCanonicalInt(field~)) => assert_eq(field, "gasPrice")
    Some(other) => abort("expected NonCanonicalInt, got \{other.to_string()}")
    None => abort("expected NonCanonicalInt, got Ok")
  }
}

///|
test "decode_tx rejects bad to and bad blob hash" {
  // to 是 19 字节。
  let fields : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(19, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("25")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let raw = @rlp.encode(@rlp.Item::List(fields))
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(raw[:]))
    }) {
    Some(@statetest.BadTo(length~)) => assert_eq(length, 19)
    Some(other) => abort("expected BadTo, got \{other.to_string()}")
    None => abort("expected BadTo, got Ok")
  }
  // type3 的 blob hash 是 31 字节。
  let blob_fields : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0e")),
    @rlp.Item::Str(bytes_from_hex("07a120")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::List([]),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::List([@rlp.Item::Str(Bytes::make(31, b'\x01'))]),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let body = @rlp.encode(@rlp.Item::List(blob_fields))
  let typed = FixedArray::make(body.length() + 1, b'\x03')
  for i in 0..<body.length() {
    typed[1 + i] = body[i]
  }
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(Bytes::from_array(typed)[:]))
    }) {
    Some(@statetest.BadBlobHash(index~, length~)) => {
      assert_eq(index, 0)
      assert_eq(length, 31)
    }
    Some(other) => abort("expected BadBlobHash, got \{other.to_string()}")
    None => abort("expected BadBlobHash, got Ok")
  }
}

///|
test "decode_tx legacy v without EIP-155" {
  // v = 27 -> 无 chainId，yParity = 0；signing payload 是 6 个字段。
  let fields : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("1b")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let tx = @statetest.decode_tx(@rlp.encode(@rlp.Item::List(fields))[:])
  assert_true(tx.chain_id is None)
  assert_eq(tx.y_parity, 0)
  // 6 字段的 signing payload。
  let expected = @crypto.keccak256(
    @rlp.encode(
      @rlp.Item::List([
        @rlp.Item::Str(bytes_from_hex("00")),
        @rlp.Item::Str(bytes_from_hex("0a")),
        @rlp.Item::Str(bytes_from_hex("4c4b40")),
        @rlp.Item::Str(Bytes::make(20, b'\x11')),
        @rlp.Item::Str(bytes_from_hex("00")),
        @rlp.Item::Str(Bytes::make(0, b'\x00')),
      ]),
    )[:],
  )
  assert_eq(tx.signing_hash.to_hex(), expected.to_hex())
  // v = 28 -> yParity = 1。
  let fields28 : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("1c")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let tx28 = @statetest.decode_tx(@rlp.encode(@rlp.Item::List(fields28))[:])
  assert_eq(tx28.y_parity, 1)
  assert_eq(tx28.signing_hash.to_hex(), expected.to_hex())
  // v = 29 既不是 27/28 也不是 >= 35。
  let fields29 : Array[@rlp.Item] = [
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(bytes_from_hex("0a")),
    @rlp.Item::Str(bytes_from_hex("4c4b40")),
    @rlp.Item::Str(Bytes::make(20, b'\x11')),
    @rlp.Item::Str(bytes_from_hex("00")),
    @rlp.Item::Str(Bytes::make(0, b'\x00')),
    @rlp.Item::Str(bytes_from_hex("1d")),
    @rlp.Item::Str(bytes_from_hex("01")),
    @rlp.Item::Str(bytes_from_hex("02")),
  ]
  let raw29 = @rlp.encode(@rlp.Item::List(fields29))
  match
    capture_tx_error(fn() -> Unit raise @statetest.TxError {
      ignore(@statetest.decode_tx(raw29[:]))
    }) {
    Some(@statetest.BadLegacyV(_)) => ()
    Some(other) => abort("expected BadLegacyV, got \{other.to_string()}")
    None => abort("expected BadLegacyV, got Ok")
  }
}

///|
test "decode_tx random bytes never abort" {
  // 300 组确定性 LCG 字节（长度 0..600）：只要能返回 Ok/Err 就说明没有 abort。
  // 这条测试的价值在「跑完不崩」，不在分类。
  let rng : Rng = { state: 20261120UL, }
  let mut accepted = 0
  for _ in 0..<300 {
    let len = (rng.next() % 601UL).to_int()
    let bytes = FixedArray::make(len, b'\x00')
    for i in 0..<len {
      bytes[i] = (rng.next() % 256UL).to_byte()
    }
    let ok = try {
      let _ = @statetest.decode_tx(Bytes::from_array(bytes)[:])
      true
    } catch {
      _ => false
    }
    if ok {
      accepted = accepted + 1
    }
  }
  // 随机 9 字段 legacy 撞上合法结构的概率极低，但不为零；这里只记录，不设阈值。
  ignore(accepted)
}
