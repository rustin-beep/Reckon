// U256 测试。每条算术性质都与 BigInt oracle（`@bigint`）对拍；按 ADR-3，
// 第二实现只允许出现在测试里，绝不进入生产路径。

///|
let two256 : @bigint.BigInt = @bigint.BigInt::from_int(1).shl(256)

///|
fn to_bi(x : @types.U256) -> @bigint.BigInt {
  @bigint.BigInt::from_octets(x.to_bytes_be()[:])
}

///|
fn from_bi(b : @bigint.BigInt) -> @types.U256 raise {
  @types.U256::from_bytes_be(b.mod(two256).to_octets(length=32)[:])
}

///|
test "u256 bigint conversion roundtrip" {
  let rng : Rng = { state: 5UL, }
  for _ in 0..<20 {
    let x = rng.next_u256()
    assert_eq(from_bi(to_bi(x)), x)
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
fn Rng::next_u256(self : Rng) -> @types.U256 {
  let l0 = self.next()
  let l1 = self.next()
  let l2 = self.next()
  let l3 = self.next()
  @types.U256::from_limbs(l0, l1, l2, l3)
}

///|
test "u256 constants and hex" {
  assert_eq(@types.U256::zero().to_hex(), "0".repeat(64))
  assert_eq(@types.U256::one().to_hex(), "0".repeat(63) + "1")
  assert_eq(@types.U256::max_value().to_hex(), "f".repeat(64))
  assert_eq(@types.U256::from_u64(255UL).to_hex(), "0".repeat(62) + "ff")
  assert_eq(@types.U256::from_u64(0UL).is_zero(), true)
  assert_eq(@types.U256::from_u64(1UL).is_zero(), false)
}

///|
test "u256 hex parse" {
  let a = @types.U256::from_hex("0xdeadBEEF")
  assert_eq(a.to_u64(), 0xDEADBEEFUL)
  // odd digit count is accepted for quantities
  let b = @types.U256::from_hex("0x1")
  assert_eq(b, @types.U256::one())
  // uppercase prefix is accepted
  let c = @types.U256::from_hex("0X0F")
  assert_eq(c.to_u64(), 15UL)
  // full-width roundtrip
  let max = @types.U256::max_value()
  assert_eq(@types.U256::from_hex(max.to_hex()), max)
}

///|
test "u256 hex parse rejects bad input" {
  try ignore(@types.U256::from_hex("0xzz")) catch {
    _ => ()
  } noraise {
    _ => fail("expected InvalidHexChar")
  }
  try ignore(@types.U256::from_hex("0x" + "f".repeat(65))) catch {
    _ => ()
  } noraise {
    _ => fail("expected InvalidLength")
  }
}

///|
test "u256 bytes roundtrip" {
  let rng : Rng = { state: 7UL, }
  for _ in 0..<20 {
    let x = rng.next_u256()
    let bytes = x.to_bytes_be()
    assert_eq(bytes.length(), 32)
    assert_eq(@types.U256::from_bytes_be(bytes[:]), x)
  }
}

///|
test "u256 bit_length" {
  assert_eq(@types.U256::zero().bit_length(), 0)
  assert_eq(@types.U256::one().bit_length(), 1)
  assert_eq(@types.U256::from_u64(255UL).bit_length(), 8)
  assert_eq(@types.U256::from_u64(256UL).bit_length(), 9)
  assert_eq(@types.U256::max_value().bit_length(), 256)
}

///|
test "u256 byte_at" {
  let x = @types.U256::from_hex(
    "0x00112233445566778899aabbccddeeff00112233445566778899aabbccddeeff",
  )
  assert_eq(x.byte_at(0).to_u64(), 0x00UL)
  assert_eq(x.byte_at(1).to_u64(), 0x11UL)
  assert_eq(x.byte_at(31).to_u64(), 0xFFUL)
  assert_eq(x.byte_at(32), @types.U256::zero())
}

///|
test "u256 arithmetic matches bigint oracle" {
  let rng : Rng = { state: 0x1234_5678_9ABC_DEF0UL, }
  for _ in 0..<150 {
    let a = rng.next_u256()
    let b = rng.next_u256()
    let ba = to_bi(a)
    let bb = to_bi(b)
    assert_eq(to_bi(a + b), ba.add(bb).mod(two256))
    assert_eq(to_bi(a - b), ba.sub(bb).add(two256).mod(two256))
    assert_eq(to_bi(a * b), ba.mul(bb).mod(two256))
    assert_eq(to_bi(a.land(b)), ba.land(bb))
    assert_eq(to_bi(a.lor(b)), ba.lor(bb))
    assert_eq(to_bi(a.lxor(b)), ba.lxor(bb))
    if !b.is_zero() {
      assert_eq(to_bi(a / b), ba.div(bb))
      assert_eq(to_bi(a % b), ba.mod(bb))
    }
  }
}

///|
test "u256 division edge cases" {
  let zero = @types.U256::zero()
  let one = @types.U256::one()
  let max = @types.U256::max_value()
  assert_eq(max / zero, zero)
  assert_eq(max % zero, zero)
  assert_eq(max / one, max)
  assert_eq(max % one, zero)
  assert_eq(zero / max, zero)
  assert_eq(one / @types.U256::from_u64(2UL), zero)
  assert_eq(one % @types.U256::from_u64(2UL), one)
}

///|
test "u256 addmod mulmod match bigint oracle" {
  let rng : Rng = { state: 0xDEAD_BEEF_CAFE_BABEUL, }
  for _ in 0..<80 {
    let a = rng.next_u256()
    let b = rng.next_u256()
    let m = rng.next_u256()
    let ba = to_bi(a)
    let bb = to_bi(b)
    let bm = to_bi(m)
    if !m.is_zero() {
      assert_eq(to_bi(a.addmod(b, m)), ba.add(bb).mod(bm))
      assert_eq(to_bi(a.mulmod(b, m)), ba.mul(bb).mod(bm))
    } else {
      assert_eq(a.addmod(b, m), @types.U256::zero())
      assert_eq(a.mulmod(b, m), @types.U256::zero())
    }
  }
}

///|
test "u256 addmod small modulus" {
  // (2^256-1) + (2^256-1) mod 1 must be 0, not 2^256-3.
  let max = @types.U256::max_value()
  let one = @types.U256::one()
  assert_eq(max.addmod(max, one), @types.U256::zero())
  // 2^256 ≡ 1 (mod 3), so (2^256-1) + 1 ≡ 1.
  let three = @types.U256::from_u64(3UL)
  assert_eq(max.addmod(one, three), one)
  assert_eq(max.addmod(max, three), @types.U256::zero())
}

///|
test "u256 exp matches bigint oracle" {
  let rng : Rng = { state: 99UL, }
  for _ in 0..<30 {
    let a = rng.next_u256()
    let e = @types.U256::from_u64(rng.next() % 40UL)
    let expected = to_bi(a).pow(to_bi(e)).mod(two256)
    assert_eq(to_bi(a.exp(e)), expected)
  }
  assert_eq(@types.U256::zero().exp(@types.U256::zero()), @types.U256::one())
}

///|
test "u256 shifts match bigint oracle" {
  let rng : Rng = { state: 4242UL, }
  for _ in 0..<40 {
    let a = rng.next_u256()
    let n = (rng.next() % 300UL).to_int()
    let ba = to_bi(a)
    if n >= 256 {
      assert_eq(a.shl(n), @types.U256::zero())
      assert_eq(a.shr(n), @types.U256::zero())
    } else {
      assert_eq(to_bi(a.shl(n)), ba.shl(n).mod(two256))
      assert_eq(to_bi(a.shr(n)), ba.shr(n))
    }
  }
  // limb-boundary cases that a naive implementation gets wrong
  let one = @types.U256::one()
  assert_eq(one.shl(0), one)
  assert_eq(one.shl(63).to_u64(), 0x8000000000000000UL)
  assert_eq(one.shl(64).limb(1), 1UL)
  assert_eq(one.shl(192).limb(3), 1UL)
  assert_eq(one.shl(256), @types.U256::zero())
  assert_eq(@types.U256::max_value().shr(255).to_u64(), 1UL)
}
