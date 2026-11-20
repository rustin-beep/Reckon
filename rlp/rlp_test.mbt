// RLP 测试：以太坊规范里的规范向量、非规范编码的拒绝，以及随机树的编解码往返。

///|
fn bhex(b : Bytes) -> String {
  @types.hex_encode(b[:])
}

///|
fn utf8_bytes(s : String) -> Bytes {
  // ASCII-only helper for the test vectors.
  let out = FixedArray::make(s.length(), b'\x00')
  for i in 0..<s.length() {
    out[i] = s[i].to_byte()
  }
  Bytes::from_array(out)
}

///|
fn hex(s : String) -> Bytes raise {
  @types.hex_decode(s)
}

///|
test "rlp canonical vectors" {
  assert_eq(bhex(@rlp.encode(@rlp.Item::Str(utf8_bytes("dog")))), "83646f67")
  assert_eq(
    bhex(
      @rlp.encode(
        @rlp.Item::List([
          @rlp.Item::Str(utf8_bytes("cat")),
          @rlp.Item::Str(utf8_bytes("dog")),
        ]),
      ),
    ),
    "c88363617483646f67",
  )
  assert_eq(bhex(@rlp.encode(@rlp.Item::Str(b""))), "80")
  assert_eq(bhex(@rlp.encode(@rlp.Item::List([]))), "c0")
  assert_eq(bhex(@rlp.encode_uint(@types.U256::zero())), "80")
  assert_eq(bhex(@rlp.encode_uint(@types.U256::from_u64(15UL))), "0f")
  assert_eq(bhex(@rlp.encode_uint(@types.U256::from_u64(1024UL))), "820400")
  // [[], [[]], [[], [[]]]]
  let nested = @rlp.Item::List([
    @rlp.Item::List([]),
    @rlp.Item::List([@rlp.Item::List([])]),
    @rlp.Item::List([
      @rlp.Item::List([]),
      @rlp.Item::List([@rlp.Item::List([])]),
    ]),
  ])
  assert_eq(bhex(@rlp.encode(nested)), "c7c0c1c0c3c0c1c0")
  // 56-byte string switches to the long form
  let lorem = utf8_bytes(
    "Lorem ipsum dolor sit amet, consectetur adipisicing elit",
  )
  assert_eq(
    bhex(@rlp.encode(@rlp.Item::Str(lorem))),
    "b8384c6f72656d20697073756d20646f6c6f722073697420616d65742c20636f6e7365637465747572206164697069736963696e6720656c6974",
  )
}

///|
test "rlp decode roundtrip" {
  let dog = @rlp.decode(hex("83646f67")[:])
  assert_eq(bhex(dog.as_bytes()), "646f67")
  let nested = @rlp.decode(hex("c7c0c1c0c3c0c1c0")[:])
  assert_eq(nested.as_list().length(), 3)
  assert_eq(bhex(@rlp.encode(nested)), "c7c0c1c0c3c0c1c0")
}

///|
test "rlp rejects non-canonical encodings" {
  // single byte below 0x80 wrapped in a one-byte string header
  try ignore(@rlp.decode(hex("8100")[:])) catch {
    @rlp.RlpError::NonCanonical(_) => ()
    _ => fail("expected NonCanonical")
  } noraise {
    _ => fail("expected NonCanonical")
  }
  // long string form for a payload shorter than 56 bytes
  try ignore(@rlp.decode(hex("b801ff")[:])) catch {
    @rlp.RlpError::NonCanonical(_) => ()
    _ => fail("expected NonCanonical")
  } noraise {
    _ => fail("expected NonCanonical")
  }
  // trailing bytes after a complete item
  try ignore(@rlp.decode(hex("8080")[:])) catch {
    @rlp.RlpError::TrailingBytes(_) => ()
    _ => fail("expected TrailingBytes")
  } noraise {
    _ => fail("expected TrailingBytes")
  }
  // truncated payload
  try ignore(@rlp.decode(hex("83646f")[:])) catch {
    @rlp.RlpError::UnexpectedEnd(_) => ()
    _ => fail("expected UnexpectedEnd")
  } noraise {
    _ => fail("expected UnexpectedEnd")
  }
  // length with a leading zero byte
  try ignore(@rlp.decode(hex("b90038" + "00".repeat(56))[:])) catch {
    @rlp.RlpError::NonCanonical(_) => ()
    _ => fail("expected NonCanonical")
  } noraise {
    _ => fail("expected NonCanonical")
  }
}

///|
test "rlp integer decoding" {
  let v = @rlp.decode(hex("820400")[:])
  assert_eq(v.as_uint(), @types.U256::from_u64(1024UL))
  let zero = @rlp.decode(hex("80")[:])
  assert_eq(zero.as_uint(), @types.U256::zero())
  // leading zero byte in an integer is non-canonical
  let bad = @rlp.decode(hex("820004")[:])
  try ignore(bad.as_uint()) catch {
    @rlp.RlpError::NonCanonical(_) => ()
    _ => fail("expected NonCanonical")
  } noraise {
    _ => fail("expected NonCanonical")
  }
}

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
fn Rng::item(self : Rng, depth : Int32) -> @rlp.Item {
  let pick = self.next() % 10UL
  if depth > 0 && pick < 3UL {
    let n = (self.next() % 4UL).to_int()
    let children : Array[@rlp.Item] = []
    for _ in 0..<n {
      children.push(self.item(depth - 1))
    }
    @rlp.Item::List(children)
  } else {
    let n = (self.next() % 70UL).to_int()
    let buf = FixedArray::make(n, b'\x00')
    for i in 0..<n {
      buf[i] = (self.next() % 256UL).to_byte()
    }
    @rlp.Item::Str(Bytes::from_array(buf))
  }
}

///|
test "rlp random tree roundtrip" {
  let rng : Rng = { state: 0x5EED1234UL, }
  for _ in 0..<100 {
    let item = rng.item(3)
    let encoded = @rlp.encode(item)
    let decoded = @rlp.decode(encoded[:])
    assert_eq(bhex(@rlp.encode(decoded)), bhex(encoded))
  }
}

///|
test "rlp decode never panics on random bytes" {
  // Untrusted input must only ever raise, never abort the process: a panic here
  // would take down the whole state-test run.
  let rng : Rng = { state: 0xABCDEF01UL, }
  for _ in 0..<300 {
    let n = (rng.next() % 40UL).to_int()
    let buf = FixedArray::make(n, b'\x00')
    for i in 0..<n {
      buf[i] = (rng.next() % 256UL).to_byte()
    }
    let data = Bytes::from_array(buf)
    try ignore(@rlp.decode(data[:])) catch {
      _ => ()
    } noraise {
      _ => ()
    }
  }
}
