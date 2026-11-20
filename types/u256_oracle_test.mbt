// U256 大规模对拍：移位全扫、模运算网格、大指数。
//
// 这些用例来自审阅探针（3072 组移位、480 组模运算、大指数 exp），现在固化进
// 测试套件，随 CI 一起跑——探针不能只留在审阅者本地。
// 期望值全部由 `@bigint` 第二实现给出（ADR-3：仅测试期）。

///|
let oracle_two256 : @bigint.BigInt = @bigint.BigInt::from_int(1).shl(256)

///|
fn oracle_of(x : @types.U256) -> @bigint.BigInt {
  @bigint.BigInt::from_octets(x.to_bytes_be()[:])
}

///|
fn oracle_values() -> Array[@types.U256] raise {
  [
    @types.U256::zero(),
    @types.U256::one(),
    @types.U256::max_value(),
    @types.U256::one().shl(255),
    @types.U256::one().shl(255) + @types.U256::one(),
    @types.U256::from_hex(
      "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
    ),
  ]
}

///|
test "U256 移位全扫：6 个极值 × 0..255 × 左右移" {
  for v in oracle_values() {
    let bv = oracle_of(v)
    for n in 0..<256 {
      assert_eq(oracle_of(v.shl(n)), bv.shl(n).mod(oracle_two256))
      assert_eq(oracle_of(v.shr(n)), bv.shr(n))
    }
  }
}

///|
test "U256 模运算网格：极值 × 极值 × 模数" {
  let mods : Array[@types.U256] = [
    @types.U256::max_value(),
    @types.U256::one().shl(255),
    @types.U256::one().shl(192) + @types.U256::one(),
    @types.U256::from_u64(3UL),
    @types.U256::from_u64(7UL),
  ]
  for a in oracle_values() {
    for b in oracle_values() {
      let ba = oracle_of(a)
      let bb = oracle_of(b)
      assert_eq(oracle_of(a + b), ba.add(bb).mod(oracle_two256))
      assert_eq(oracle_of(a * b), ba.mul(bb).mod(oracle_two256))
      if !b.is_zero() {
        assert_eq(oracle_of(a / b), ba.div(bb))
        assert_eq(oracle_of(a % b), ba.mod(bb))
      }
      for m in mods {
        let bm = oracle_of(m)
        assert_eq(oracle_of(a.addmod(b, m)), ba.add(bb).mod(bm))
        assert_eq(oracle_of(a.mulmod(b, m)), ba.mul(bb).mod(bm))
      }
    }
  }
}

///|
test "U256 exp 大指数" {
  let bases : Array[@types.U256] = [
    @types.U256::from_u64(3UL),
    @types.U256::from_u64(2UL),
    @types.U256::max_value(),
  ]
  let exponents : Array[@types.U256] = [
    @types.U256::zero(),
    @types.U256::one().shl(32),
    @types.U256::from_u64(0xFFFFFFFFFFFFFFFFUL),
    @types.U256::one().shl(255),
    @types.U256::max_value(),
  ]
  for a in bases {
    for e in exponents {
      // 必须带模数：不带模的 3^(2^255) 会尝试构造天文数字。
      let expected = oracle_of(a).pow(oracle_of(e), modulus=oracle_two256)
      assert_eq(oracle_of(a.exp(e)), expected)
    }
  }
}
