// Address / Hash32 值类型测试：不变量、十六进制往返、作为 Map 键的可用性。

///|
test "address hex roundtrip" {
  let text = "0x" + "11".repeat(20)
  let a = @types.Address::from_hex(text)
  assert_eq(a.to_hex(), text)
  assert_eq(a.as_bytes().length(), 20)
  assert_eq(@types.Address::zero().to_hex(), "0x" + "00".repeat(20))
}

///|
test "address rejects wrong length" {
  try ignore(@types.Address::from_hex("0x1234")) catch {
    @types.DecodeError::InvalidLength(_) => ()
    _ => fail("expected InvalidLength")
  } noraise {
    _ => fail("expected InvalidLength")
  }
  // 21 bytes is also rejected, so the invariant is exact rather than a minimum
  try ignore(@types.Address::from_hex("0x" + "ff".repeat(21))) catch {
    @types.DecodeError::InvalidLength(_) => ()
    _ => fail("expected InvalidLength")
  } noraise {
    _ => fail("expected InvalidLength")
  }
}

///|
test "hash32 hex roundtrip" {
  let text = "0x" + "ab".repeat(32)
  let h = @types.Hash32::from_hex(text)
  assert_eq(h.to_hex(), text)
  assert_eq(h.as_bytes().length(), 32)
}

///|
test "address is usable as a map key" {
  let m : Map[@types.Address, Int32] = Map([])
  let a = @types.Address::from_hex("0x" + "01".repeat(20))
  let b = @types.Address::from_hex("0x" + "02".repeat(20))
  m[a] = 1
  m[b] = 2
  assert_eq(m[a], 1)
  assert_eq(m[b], 2)
  assert_eq(m.length(), 2)
}

///|
test "address ordering follows byte order" {
  let a = @types.Address::from_hex("0x" + "00".repeat(19) + "01")
  let b = @types.Address::from_hex("0x" + "00".repeat(19) + "02")
  assert_true(a < b)
  assert_true(a != b)
}
