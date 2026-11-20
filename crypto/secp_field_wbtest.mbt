// 基域 F_p 与标量域 F_n 的边界网格 + 确定性伪随机对拍。
//
// **仅测试期 oracle**：所有期望值由 `@bigint` 第二实现给出。这是 ADR-3 允许的
// 唯一 BigInt 用法——生产代码（`crypto/*.mbt` 的非测试文件）零 `@bigint`，
// 验收命令里有专门的一条 grep 守着。

///|
/// 4×64 limb 拼 BigInt（避开已废弃的 `from_string`）。
fn big_from_limbs(
  l0 : UInt64,
  l1 : UInt64,
  l2 : UInt64,
  l3 : UInt64,
) -> @bigint.BigInt {
  @bigint.BigInt::from_uint64(l3).shl(192) +
  @bigint.BigInt::from_uint64(l2).shl(128) +
  @bigint.BigInt::from_uint64(l1).shl(64) +
  @bigint.BigInt::from_uint64(l0)
}

///|
let oracle_p : @bigint.BigInt = big_from_limbs(
  0xFFFFFFFEFFFFFC2FUL, 0xFFFFFFFFFFFFFFFFUL, 0xFFFFFFFFFFFFFFFFUL, 0xFFFFFFFFFFFFFFFFUL,
)

///|
let oracle_n : @bigint.BigInt = big_from_limbs(
  0xBFD25E8CD0364141UL, 0xBAAEDCE6AF48A03BUL, 0xFFFFFFFFFFFFFFFEUL, 0xFFFFFFFFFFFFFFFFUL,
)

///|
fn big_of_fe(a : Fe) -> @bigint.BigInt {
  @bigint.BigInt::from_octets(fe_to_be_bytes(a)[:])
}

///|
fn big_of_fn(a : Fn) -> @bigint.BigInt {
  @bigint.BigInt::from_octets(fn_to_be_bytes(a)[:])
}

///|
/// 64 字节大端拆成 16 个 32 位 limb（小端序），给归约极值用例喂输入。
fn limbs32_of_big(b : @bigint.BigInt) -> FixedArray[UInt64] {
  let bytes = b.to_octets(length=64)
  let out = FixedArray::make(16, 0UL)
  for i in 0..<16 {
    let mut v = 0UL
    for j in 0..<4 {
      v = (v << 8) | bytes[64 - (i + 1) * 4 + j].to_uint64()
    }
    out[i] = v
  }
  out
}

///|
/// 固定种子 LCG（禁止时间/系统随机，保证三后端与历史运行一致）。
struct FeLcg {
  mut state : UInt64
}

///|
fn FeLcg::next(self : FeLcg) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state
}

///|
/// 生成 < 2^255 的域元素（最高位清零，必然 < p 且 < n）。
fn FeLcg::fe(self : FeLcg) -> Fe {
  {
    l0: self.next(),
    l1: self.next(),
    l2: self.next(),
    l3: self.next() & 0x7FFFFFFFFFFFFFFFUL,
  }
}

///|
fn fe_grid() -> Array[Fe] {
  let two : Fe = { l0: 2UL, l1: 0UL, l2: 0UL, l3: 0UL, }
  [
    fe_zero(),
    fe_one(),
    two,
    fe_sub(fe_p, fe_one()),
    fe_sub(fe_p, two),
    {
      l0: 0xFFFFFFFFFFFFFFFFUL,
      l1: 0xFFFFFFFFFFFFFFFFUL,
      l2: 0xFFFFFFFFFFFFFFFFUL,
      l3: 0x7FFFFFFFFFFFFFFFUL,
    },
    { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0x8000000000000000UL, },
  ]
}

///|
fn one_fn() -> Fn {
  fn_of_arr([1UL, 0UL, 0UL, 0UL])
}

///|
fn fn_grid() -> Array[Fn] {
  let two : Fn = { l0: 2UL, l1: 0UL, l2: 0UL, l3: 0UL, }
  [
    fn_zero(),
    one_fn(),
    two,
    fn_sub(fn_n, one_fn()),
    fn_sub(fn_n, two),
    {
      l0: 0xFFFFFFFFFFFFFFFFUL,
      l1: 0xFFFFFFFFFFFFFFFFUL,
      l2: 0xFFFFFFFFFFFFFFFFUL,
      l3: 0x7FFFFFFFFFFFFFFFUL,
    },
    { l0: 0UL, l1: 0UL, l2: 0UL, l3: 0x8000000000000000UL, },
  ]
}

///|
fn check_fe(actual : Fe, expected : Fe) -> Unit {
  if !fe_equal(actual, expected) {
    abort(
      "Fe 不相等: \{@types.hex_encode(fe_to_be_bytes(actual)[:])} != \{@types.hex_encode(fe_to_be_bytes(expected)[:])}",
    )
  }
}

///|
fn check_fn(actual : Fn, expected : Fn) -> Unit {
  if !fn_equal(actual, expected) {
    abort(
      "Fn 不相等: \{@types.hex_encode(fn_to_be_bytes(actual)[:])} != \{@types.hex_encode(fn_to_be_bytes(expected)[:])}",
    )
  }
}

///|
/// 断言闭包抛 `SecpError`（任一变体），返回是否命中。
fn raises_secp(f : () -> Unit raise SecpError) -> Bool {
  let mut hit = false
  try f() catch {
    _ => hit = true
  } noraise {
    _ => ()
  }
  hit
}

///|
test "基域：边界网格 7×7 的加减乘对拍 BigInt" {
  for a in fe_grid() {
    for b in fe_grid() {
      let ba = big_of_fe(a)
      let bb = big_of_fe(b)
      assert_eq(big_of_fe(fe_add(a, b)), (ba + bb) % oracle_p)
      assert_eq(big_of_fe(fe_sub(a, b)), (ba - bb + oracle_p) % oracle_p)
      assert_eq(big_of_fe(fe_mul(a, b)), ba * bb % oracle_p)
      assert_eq(big_of_fe(fe_sqr(a)), ba * ba % oracle_p)
    }
  }
}

///|
test "基域：200 组确定性伪随机对拍 BigInt" {
  let lcg = FeLcg::{ state: 0x123456789ABCDEFUL, }
  for _ in 0..<200 {
    let a = lcg.fe()
    let b = lcg.fe()
    let ba = big_of_fe(a)
    let bb = big_of_fe(b)
    assert_eq(big_of_fe(fe_add(a, b)), (ba + bb) % oracle_p)
    assert_eq(big_of_fe(fe_sub(a, b)), (ba - bb + oracle_p) % oracle_p)
    assert_eq(big_of_fe(fe_mul(a, b)), ba * bb % oracle_p)
    assert_eq(big_of_fe(fe_neg(a)), (oracle_p - ba) % oracle_p)
  }
}

///|
/// BigInt 版求逆（Fermat；测试期 oracle 不需要性能）。
fn big_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  a.pow(m - @bigint.BigInt::from_int(2), modulus=m)
}

///|
test "基域：inv 对拍与零元拒绝" {
  let lcg = FeLcg::{ state: 0xDEADBEEFCAFEBABEUL, }
  for _ in 0..<50 {
    let raw = lcg.fe()
    // 保证非零：最低位置 1
    let a = { ..raw, l0: raw.l0 | 1UL, }
    check_fe(fe_mul(a, fe_inv(a)), fe_one())
    assert_eq(big_of_fe(fe_inv(a)), big_inv(big_of_fe(a), oracle_p))
  }
  // inv(p-1) = p-1（-1 的逆是 -1）
  let pm1 = fe_sub(fe_p, fe_one())
  check_fe(fe_inv(pm1), pm1)
  check_fe(fe_inv(fe_one()), fe_one())
  // inv(0) 必须报错，不能返回 0
  if !raises_secp(() => ignore(fe_inv(fe_zero()))) {
    abort("inv(0) 应当抛 NotInvertible")
  }
}

///|
test "基域：归约极值（含 512 位全 1 与 (p-1)^2）" {
  let max512 = @bigint.BigInt::from_int(1).shl(512) -
    @bigint.BigInt::from_int(1)
  let pm1 = oracle_p - @bigint.BigInt::from_int(1)
  let cases : Array[@bigint.BigInt] = [
    max512,
    pm1 * pm1,
    oracle_p * oracle_p,
    (oracle_p - @bigint.BigInt::from_int(2)) *
    (oracle_p - @bigint.BigInt::from_int(1)),
    @bigint.BigInt::from_int(0),
  ]
  for b in cases {
    assert_eq(big_of_fe(fe_reduce_p(limbs32_of_big(b))), b % oracle_p)
  }
}

///|
test "基域：32 字节 canonical 编解码与越界拒绝" {
  let lcg = FeLcg::{ state: 0x0F1E2D3C4B5A6978UL, }
  for _ in 0..<20 {
    let a = lcg.fe()
    check_fe(fe_from_be_at(fe_to_be_bytes(a)[:], 0), a)
  }
  // p 本身与 2^256-1 都必须被拒绝
  if !raises_secp(() => ignore(fe_from_be_at(fe_to_be_bytes(fe_p)[:], 0))) {
    abort("x = p 应当被拒绝")
  }
  if !raises_secp(() => {
      ignore(fe_from_be_at(@types.U256::max_value().to_bytes_be()[:], 0))
    }) {
    abort("x = 2^256-1 应当被拒绝")
  }
}

///|
test "标量域：边界网格 7×7 的加减乘对拍 BigInt" {
  for a in fn_grid() {
    for b in fn_grid() {
      let ba = big_of_fn(a)
      let bb = big_of_fn(b)
      assert_eq(big_of_fn(fn_add(a, b)), (ba + bb) % oracle_n)
      assert_eq(big_of_fn(fn_sub(a, b)), (ba - bb + oracle_n) % oracle_n)
      assert_eq(big_of_fn(fn_mul(a, b)), ba * bb % oracle_n)
      assert_eq(big_of_fn(fn_neg(a)), (oracle_n - ba) % oracle_n)
    }
  }
}

///|
test "标量域：200 组确定性伪随机对拍 BigInt" {
  let lcg = FeLcg::{ state: 0xABCDEF0123456789UL, }
  for _ in 0..<200 {
    let a = lcg.fe()
    let b = lcg.fe()
    let fa = fn_of_arr(fe_to_arr(a))
    let fb = fn_of_arr(fe_to_arr(b))
    let ba = big_of_fn(fa)
    let bb = big_of_fn(fb)
    assert_eq(big_of_fn(fn_add(fa, fb)), (ba + bb) % oracle_n)
    assert_eq(big_of_fn(fn_sub(fa, fb)), (ba - bb + oracle_n) % oracle_n)
    assert_eq(big_of_fn(fn_mul(fa, fb)), ba * bb % oracle_n)
  }
}

///|
test "标量域：inv 对拍、零元拒绝、n-1 自逆" {
  let lcg = FeLcg::{ state: 0x76543210FEDCBA98UL, }
  for _ in 0..<50 {
    let raw = lcg.fe()
    let fa = fn_of_arr(fe_to_arr({ ..raw, l0: raw.l0 | 1UL, }))
    check_fn(fn_mul(fa, fn_inv(fa)), one_fn())
    assert_eq(big_of_fn(fn_inv(fa)), big_inv(big_of_fn(fa), oracle_n))
  }
  let nm1 = fn_sub(fn_n, one_fn())
  check_fn(fn_inv(nm1), nm1)
  if !raises_secp(() => ignore(fn_inv(fn_zero()))) {
    abort("inv(0) 应当抛 NotInvertible")
  }
}

///|
test "标量域：n 附近与 2^256-1 的归约" {
  let max256 = @bigint.BigInt::from_int(1).shl(256) -
    @bigint.BigInt::from_int(1)
  let nm1 = oracle_n - @bigint.BigInt::from_int(1)
  let cases : Array[@bigint.BigInt] = [
    max256,
    nm1 * nm1,
    oracle_n * oracle_n,
    oracle_n * max256,
  ]
  for b in cases {
    assert_eq(big_of_fn(fn_reduce_n(limbs32_of_big(b))), b % oracle_n)
  }
}

///|
test "标量域：摘要归约与 canonical 拒绝" {
  let max256 = @bigint.BigInt::from_int(1).shl(256) -
    @bigint.BigInt::from_int(1)
  assert_eq(
    big_of_fn(
      fn_from_be_bytes_reduced(@types.U256::max_value().to_bytes_be()[:]),
    ),
    max256 % oracle_n,
  )
  // n 本身不能作为 canonical 标量
  if !raises_secp(() => ignore(fn_from_be_at(fn_to_be_bytes(fn_n)[:], 0))) {
    abort("s = n 应当被拒绝")
  }
  // 零标量同样被拒绝
  if !raises_secp(() => {
      ignore(fn_from_be_at(@types.U256::zero().to_bytes_be()[:], 0))
    }) {
    abort("s = 0 应当被拒绝")
  }
  // 摘要长度不对必须报错
  let short = @types.U256::max_value().to_bytes_be()[:31]
  if !raises_secp(() => ignore(fn_from_be_bytes_reduced(short))) {
    abort("31 字节摘要应当被拒绝")
  }
}
