// 群运算测试：已知常量、BIP-340 x-only 向量、BigInt 仿射 oracle 对拍、编解码边界。
//
// BIP-340 向量来源：bitcoin/bips `bip-0340/test-vectors.csv`（master），
// 只取前三条 seckey → x-only pubkey 的对应关系；x-only 承诺只比较 x 坐标。

///|
/// 不做范围校验的标量构造（测试零元、n 等边界用）。
fn fn_raw_hex(s : String) -> Fn raise {
  fn_of_arr(load_be32_at(@types.hex_decode(s)[:], 0))
}

///|
fn fn_one() -> Fn {
  fn_of_arr([1UL, 0UL, 0UL, 0UL])
}

///|
fn big_of_fe2(a : Fe) -> @bigint.BigInt {
  @bigint.BigInt::from_octets(fe_to_be_bytes(a)[:])
}

///|
/// 曲线上的点，供 BigInt 仿射 oracle 用。
enum BigPoint {
  BigInf
  BigAff(@bigint.BigInt, @bigint.BigInt)
}

///|
let big_p : @bigint.BigInt = big_of_fe2(fe_p)

///|
/// BigInt 取模并归一到非负（MoonBit 的 `%` 对负数给负余数）。
fn big_mod(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  let r = a % m
  if r < @bigint.BigInt::from_int(0) {
    r + m
  } else {
    r
  }
}

///|
fn big_mod_inv(a : @bigint.BigInt, m : @bigint.BigInt) -> @bigint.BigInt {
  big_mod(a, m).pow(m - @bigint.BigInt::from_int(2), modulus=m)
}

///|
fn big_point_add(p : BigPoint, q : BigPoint) -> BigPoint {
  match (p, q) {
    (BigInf, _) => q
    (_, BigInf) => p
    (BigAff(x1, y1), BigAff(x2, y2)) =>
      if x1 == x2 {
        if big_mod(y1 + y2, big_p) == @bigint.BigInt::from_int(0) {
          BigInf
        } else {
          // 倍点：λ = 3x² / 2y
          let lam = big_mod(
            @bigint.BigInt::from_int(3) *
            x1 *
            x1 *
            big_mod_inv(@bigint.BigInt::from_int(2) * y1, big_p),
            big_p,
          )
          let x3 = big_mod(lam * lam - x1 - x1, big_p)
          BigAff(x3, big_mod(lam * (x1 - x3) - y1, big_p))
        }
      } else {
        let lam = big_mod((y2 - y1) * big_mod_inv(x2 - x1, big_p), big_p)
        let x3 = big_mod(lam * lam - x1 - x2, big_p)
        BigAff(x3, big_mod(lam * (x1 - x3) - y1, big_p))
      }
  }
}

///|
fn big_point_mul(k : @bigint.BigInt, p : BigPoint) -> BigPoint {
  let mut acc = BigInf
  let mut addend = p
  let mut e = k
  let zero = @bigint.BigInt::from_int(0)
  while e > zero {
    if e.land(@bigint.BigInt::from_int(1)) == @bigint.BigInt::from_int(1) {
      acc = big_point_add(acc, addend)
    }
    addend = big_point_add(addend, addend)
    e = e.shr(1)
  }
  acc
}

///|
fn check_affine(
  p : Jac,
  want_x : @bigint.BigInt,
  want_y : @bigint.BigInt,
) -> Unit raise {
  if jac_is_infinity(p) {
    abort("期望有限点，实际是无穷远")
  }
  let (x, y) = jac_to_affine(p)
  if big_of_fe2(x) != want_x || big_of_fe2(y) != want_y {
    abort(
      "仿射坐标不匹配: \{@types.hex_encode(fe_to_be_bytes(x)[:])}, \{@types.hex_encode(fe_to_be_bytes(y)[:])}",
    )
  }
}

///|
test "生成元与已知常量" {
  // G 在曲线上
  assert_true(on_curve(fe_gx, fe_gy))
  // 2G 已知常量
  let two = fn_raw_hex(
    "0000000000000000000000000000000000000000000000000000000000000002",
  )
  let g2 = scalar_mult_g(two)
  assert_true(!jac_is_infinity(g2))
  let (x2, y2) = jac_to_affine(g2)
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(x2)[:]),
    "c6047f9441ed7d6d3045406e95c07cd85c778e4b8cef3ca7abac09b95c709ee5",
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(y2)[:]),
    "1ae168fea63dc339a3c58419466ceaeef7f632653266d0e1236431a950cfe52a",
  )
  // nG = O，(n-1)G = -G
  let n_scalar = fn_of_arr([
    0xBFD25E8CD0364141UL, 0xBAAEDCE6AF48A03BUL, 0xFFFFFFFFFFFFFFFEUL, 0xFFFFFFFFFFFFFFFFUL,
  ])
  assert_true(jac_is_infinity(scalar_mult_g(n_scalar)))
  let nm1 = fn_sub(n_scalar, fn_one())
  let pm = scalar_mult_g(nm1)
  let (xn, yn) = jac_to_affine(pm)
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(xn)[:]),
    @types.hex_encode(fe_to_be_bytes(fe_gx)[:]),
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(yn)[:]),
    @types.hex_encode(fe_to_be_bytes(fe_neg(fe_gy))[:]),
  )
}

///|
test "无穷远与特殊点的加法/倍点" {
  let g = jac_of_affine(fe_gx, fe_gy)
  // P + O = P
  let a = jac_add_mixed(jac_infinity(), fe_gx, fe_gy)
  let (ax, ay) = jac_to_affine(a)
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(ax)[:]),
    @types.hex_encode(fe_to_be_bytes(fe_gx)[:]),
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(ay)[:]),
    @types.hex_encode(fe_to_be_bytes(fe_gy)[:]),
  )
  // O + O = O
  assert_true(jac_is_infinity(jac_add(jac_infinity(), jac_infinity())))
  // P + (-P) = O
  let neg_g = jac_of_affine(fe_gx, fe_neg(fe_gy))
  assert_true(jac_is_infinity(jac_add(g, neg_g)))
  // y = 0 的点倍点后为 O
  let y_zero = jac_of_affine(fe_gx, fe_zero())
  assert_true(jac_is_infinity(jac_double(y_zero)))
  // 倍点与「加自己」一致
  let dbl = jac_double(g)
  let add_self = jac_add(g, g)
  let (dx, dy) = jac_to_affine(dbl)
  let (sx, sy) = jac_to_affine(add_self)
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(dx)[:]),
    @types.hex_encode(fe_to_be_bytes(sx)[:]),
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(dy)[:]),
    @types.hex_encode(fe_to_be_bytes(sy)[:]),
  )
}

///|
test "BIP-340 三组 x-only 向量" {
  let cases : Array[(String, String)] = [
    (
      "0000000000000000000000000000000000000000000000000000000000000003", "f9308a019258c31049344f85f89d5229b531c845836f99b08601f113bce036f9",
    ),
    (
      "b7e151628aed2a6abf7158809cf4f3c762e7160f38b4da56a784d9045190cfef", "dff1d77f2a671c5f36183726db2341be58feae1da2deced843240f7b502ba659",
    ),
    (
      "c90fdaa22168c234c4c6628b80dc1cd129024e088a67cc74020bbea63b14e5c9", "dd308afec5777e13121fa72b9cc1b7cc0139715309b086c960e18fd969774eb8",
    ),
  ]
  for c in cases {
    let (sk, want) = c
    let p = scalar_mult_g(fn_raw_hex(sk))
    assert_true(!jac_is_infinity(p))
    let (x, _) = jac_to_affine(p)
    assert_eq(@types.hex_encode(fe_to_be_bytes(x)[:]), want)
  }
}

///|
test "BigInt 仿射 oracle 对拍：标量 0/1/2/3/5/n-1/n" {
  let scalars : Array[String] = [
    "0000000000000000000000000000000000000000000000000000000000000000", "0000000000000000000000000000000000000000000000000000000000000001",
    "0000000000000000000000000000000000000000000000000000000000000002", "0000000000000000000000000000000000000000000000000000000000000003",
    "0000000000000000000000000000000000000000000000000000000000000005", "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364140",
    "fffffffffffffffffffffffffffffffeBAAEDCE6AF48A03BBFD25E8CD0364141",
  ]
  for s in scalars {
    let k = fn_raw_hex(s)
    let got = scalar_mult_g(k)
    let want = big_point_mul(
      @bigint.BigInt::from_octets(@types.hex_decode(s)[:]),
      BigAff(big_of_fe2(fe_gx), big_of_fe2(fe_gy)),
    )
    match want {
      BigInf => assert_true(jac_is_infinity(got))
      BigAff(wx, wy) => check_affine(got, wx, wy)
    }
  }
}

///|
test "任意点的标量乘与混合加法一致" {
  // 用 5G 当任意点
  let k5 = fn_raw_hex(
    "0000000000000000000000000000000000000000000000000000000000000005",
  )
  let p5 = scalar_mult_g(k5)
  let (qx, qy) = jac_to_affine(p5)
  // 3*(5G) == 15G
  let k3 = fn_raw_hex(
    "0000000000000000000000000000000000000000000000000000000000000003",
  )
  let k15 = fn_raw_hex(
    "000000000000000000000000000000000000000000000000000000000000000f",
  )
  let got = scalar_mult(k3, qx, qy)
  let want = scalar_mult_g(k15)
  let (gx, gy) = jac_to_affine(got)
  let (wx, wy) = jac_to_affine(want)
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(gx)[:]),
    @types.hex_encode(fe_to_be_bytes(wx)[:]),
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(gy)[:]),
    @types.hex_encode(fe_to_be_bytes(wy)[:]),
  )
}

///|
test "压缩/非压缩解析回环与已知解压" {
  // 02e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a
  // 解出 y = 0a2b2667f7e725ceea70c673093bf67663e0312623c8e091b13cf2c0f11ef652
  let compressed = @types.hex_decode(
    "02e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
  let pk = PublicKey::parse(compressed[:])
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(pk.x)[:]),
    "e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(pk.y)[:]),
    "0a2b2667f7e725ceea70c673093bf67663e0312623c8e091b13cf2c0f11ef652",
  )
  // 序列化回环：压缩 33 字节、非压缩 65 字节
  assert_eq(
    @types.hex_encode(pk.to_compressed_bytes()[:]),
    @types.hex_encode(compressed[:]),
  )
  let uncompressed = pk.to_uncompressed_bytes()
  assert_eq(uncompressed.length(), 65)
  let pk2 = PublicKey::parse(uncompressed[:])
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(pk2.x)[:]),
    @types.hex_encode(fe_to_be_bytes(pk.x)[:]),
  )
  assert_eq(
    @types.hex_encode(fe_to_be_bytes(pk2.y)[:]),
    @types.hex_encode(fe_to_be_bytes(pk.y)[:]),
  )
}

///|
test "坏公钥编码全部拒绝" {
  // 33 字节但前缀是 04
  let bad_prefix = @types.hex_decode(
    "04e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
  // x >= p（p 本身）
  let x_ge_p = @types.hex_decode(
    "02fffffffffffffffffffffffffffffffffffffffffffffffffffffffefffffc2f",
  )
  // x = 5 时 x^3+7 非二次剩余
  let non_residue = @types.hex_decode(
    "020000000000000000000000000000000000000000000000000000000000000005",
  )
  // 长度不对（32 字节）
  let short = @types.hex_decode(
    "e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a",
  )
  let bads : Array[Bytes] = [bad_prefix, x_ge_p, non_residue, short]
  for b in bads {
    let mut hit = false
    try ignore(PublicKey::parse(b[:])) catch {
      _ => hit = true
    } noraise {
      _ => ()
    }
    if !hit {
      abort("坏公钥未被拒绝: \{@types.hex_encode(b[:])}")
    }
  }
  // 非压缩点不在曲线上
  let off_curve = @types.hex_decode(
    "04e32df42865e97135acfb65f3bae71bdc86f4d49150ad6a440b6f15878109880a" +
    "0a2b2667f7e725ceea70c673093bf67663e0312623c8e091b13cf2c0f11ef653",
  )
  let mut hit2 = false
  try ignore(PublicKey::parse(off_curve[:])) catch {
    _ => hit2 = true
  } noraise {
    _ => ()
  }
  if !hit2 {
    abort("不在曲线上的非压缩点未被拒绝")
  }
}

///|
test "recid 计算：bit0 取 y 奇偶，bit1 取 R.x >= n" {
  // n + 1 < p（p - n ≈ 2^128），可用于触发 bit1
  let x_ge_n = fe_add(fe_of_n(), fe_one())
  // y = 1（奇数）
  assert_eq(recid_of(x_ge_n, fe_one()), 3)
  // y = 2（偶数）
  assert_eq(recid_of(x_ge_n, { l0: 2UL, l1: 0UL, l2: 0UL, l3: 0UL, }), 2)
  // R.x = n - 1 < n：bit1 不置位
  let x_lt_n = fe_sub(fe_of_n(), fe_one())
  assert_eq(recid_of(x_lt_n, fe_one()), 1)
  assert_eq(recid_of(x_lt_n, { l0: 2UL, l1: 0UL, l2: 0UL, l3: 0UL, }), 0)
}
