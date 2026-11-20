// secp256k1 群运算：y^2 = x^3 + 7，Jacobian 坐标。
//
// 约定：Z = 0 表示无穷远点 O；仿射点用 (x, y) 表示，不单独建类型。
// 公式取自 EFD 的 a = 0 版本：
//   - 倍点 dbl-2009-l：2M + 5S
//   - 混合加法 madd-2007-bl（第二个点 Z = 1）：7M + 4S
//   - 通用加法 add-2007-bl：12M + 4S
// 先写显然正确的双倍-加法，窗口/预计算留给阶段 4（见 B05 报告的性能节）。

///|
/// Jacobian 点：仿射坐标是 `(X/Z^2, Y/Z^3)`，`Z = 0` 表示无穷远。
#derive(Debug)
struct Jac {
  x : Fe
  y : Fe
  z : Fe
}

///|
/// 生成元 G 的 x 坐标。
let fe_gx : Fe = {
  l0: 0x59F2815B16F81798UL,
  l1: 0x029BFCDB2DCE28D9UL,
  l2: 0x55A06295CE870B07UL,
  l3: 0x79BE667EF9DCBBACUL,
}

///|
/// 生成元 G 的 y 坐标。
let fe_gy : Fe = {
  l0: 0x9C47D08FFB10D4B8UL,
  l1: 0xFD17B448A6855419UL,
  l2: 0x5DA4FBFC0E1108A8UL,
  l3: 0x483ADA7726A3C465UL,
}

///|
/// 曲线常数 b = 7。
let fe_seven : Fe = { l0: 7UL, l1: 0UL, l2: 0UL, l3: 0UL, }

///|
fn jac_infinity() -> Jac {
  { x: fe_one(), y: fe_one(), z: fe_zero(), }
}

///|
fn jac_is_infinity(p : Jac) -> Bool {
  fe_is_zero(p.z)
}

///|
fn jac_of_affine(x : Fe, y : Fe) -> Jac {
  { x, y, z: fe_one(), }
}

///|
/// 倍点（a = 0）：dbl-2009-l。
fn jac_double(p : Jac) -> Jac {
  if fe_is_zero(p.z) || fe_is_zero(p.y) {
    return jac_infinity()
  }
  let a = fe_sqr(p.x) // X^2
  let b = fe_sqr(p.y) // Y^2
  let c = fe_sqr(b) // B^2
  let t = fe_sub(fe_sub(fe_sqr(fe_add(p.x, b)), a), c) // (X+B)^2 - A - C
  let d = fe_add(t, t) // D = 2t
  let e = fe_add(a, fe_add(a, a)) // E = 3A
  let f = fe_sqr(e)
  let x3 = fe_sub(f, fe_add(d, d))
  // 8C = ((C+C)+(C+C))+(...)
  let c2 = fe_add(c, c)
  let c4 = fe_add(c2, c2)
  let c8 = fe_add(c4, c4)
  let y3 = fe_sub(fe_mul(e, fe_sub(d, x3)), c8)
  let z3 = fe_mul(fe_add(p.y, p.y), p.z)
  { x: x3, y: y3, z: z3, }
}

///|
/// 混合加法：`p` 为 Jacobian，`(qx, qy)` 为 Z = 1 的仿射点。madd-2007-bl。
fn jac_add_mixed(p : Jac, qx : Fe, qy : Fe) -> Jac {
  if fe_is_zero(p.z) {
    return jac_of_affine(qx, qy)
  }
  let z1z1 = fe_sqr(p.z)
  let u2 = fe_mul(qx, z1z1)
  let s2 = fe_mul(fe_mul(qy, p.z), z1z1)
  let h = fe_sub(u2, p.x)
  if fe_is_zero(h) {
    if fe_equal(s2, p.y) {
      return jac_double(p)
    }
    return jac_infinity()
  }
  let hh = fe_sqr(h)
  let i = fe_add(hh, hh)
  let i = fe_add(i, i) // I = 4HH
  let j = fe_mul(h, i)
  let r = fe_sub(s2, p.y)
  let r = fe_add(r, r) // r = 2(S2-Y1)
  let v = fe_mul(p.x, i)
  let x3 = fe_sub(fe_sub(fe_sqr(r), j), fe_add(v, v))
  let yj = fe_mul(p.y, j)
  let y3 = fe_sub(fe_mul(r, fe_sub(v, x3)), fe_add(yj, yj))
  let z3 = fe_sub(fe_sub(fe_sqr(fe_add(p.z, h)), z1z1), hh)
  { x: x3, y: y3, z: z3, }
}

///|
/// 通用 Jacobian 加法：add-2007-bl。
fn jac_add(p : Jac, q : Jac) -> Jac {
  if fe_is_zero(p.z) {
    return q
  }
  if fe_is_zero(q.z) {
    return p
  }
  let z1z1 = fe_sqr(p.z)
  let z2z2 = fe_sqr(q.z)
  let u1 = fe_mul(p.x, z2z2)
  let u2 = fe_mul(q.x, z1z1)
  let s1 = fe_mul(fe_mul(p.y, q.z), z2z2)
  let s2 = fe_mul(fe_mul(q.y, p.z), z1z1)
  let h = fe_sub(u2, u1)
  if fe_is_zero(h) {
    if fe_equal(s1, s2) {
      return jac_double(p)
    }
    return jac_infinity()
  }
  let i = fe_sqr(fe_add(h, h))
  let j = fe_mul(h, i)
  let r = fe_sub(s2, s1)
  let r = fe_add(r, r)
  let v = fe_mul(u1, i)
  let x3 = fe_sub(fe_sub(fe_sqr(r), j), fe_add(v, v))
  let y3 = fe_sub(
    fe_mul(r, fe_sub(v, x3)),
    fe_add(fe_mul(s1, j), fe_mul(s1, j)),
  )
  let z3 = fe_mul(fe_sub(fe_sub(fe_sqr(fe_add(p.z, q.z)), z1z1), z2z2), h)
  { x: x3, y: y3, z: z3, }
}

///|
/// Jacobian 转仿射。`p` 是无穷远点时 `fe_inv(0)` 会抛 `NotInvertible`。
fn jac_to_affine(p : Jac) -> (Fe, Fe) raise SecpError {
  let zi = fe_inv(p.z)
  let zi2 = fe_sqr(zi)
  (fe_mul(p.x, zi2), fe_mul(p.y, fe_mul(zi2, zi)))
}

///|
/// 标量乘：从标量最高位起做双倍-加法。
fn scalar_mult(k : Fn, qx : Fe, qy : Fe) -> Jac {
  let mut acc = jac_infinity()
  for i in 0..<256 {
    let bit = 255 - i
    acc = jac_double(acc)
    let limb = match bit / 64 {
      0 => k.l0
      1 => k.l1
      2 => k.l2
      _ => k.l3
    }
    if ((limb >> (bit % 64)) & 1UL) == 1UL {
      acc = jac_add_mixed(acc, qx, qy)
    }
  }
  acc
}

///|
/// 生成元标量乘。
fn scalar_mult_g(k : Fn) -> Jac {
  scalar_mult(k, fe_gx, fe_gy)
}

///|
/// 点是否在曲线 `y^2 = x^3 + 7` 上。
fn on_curve(x : Fe, y : Fe) -> Bool {
  let lhs = fe_sqr(y)
  let rhs = fe_add(fe_mul(fe_sqr(x), x), fe_seven)
  fe_equal(lhs, rhs)
}

///|
/// 由 x 解出 y（`p ≡ 3 mod 4`，`y = rhs^((p+1)/4)`）。
///
/// 返回 `None` 表示 rhs 不是二次剩余；`y = 0` 时只有偶数奇偶性成立
/// （secp256k1 群阶为奇素数，实际不存在 y = 0 的点）。
fn decompress_y(x : Fe, odd : Bool) -> Fe? {
  let rhs = fe_add(fe_mul(fe_sqr(x), x), fe_seven)
  let y = fe_pow(rhs, fe_sqrt_exp)
  if !fe_equal(fe_sqr(y), rhs) {
    return None
  }
  let y_odd = (y.l0 & 1UL) == 1UL
  if fe_is_zero(y) {
    if odd {
      return None
    }
    return Some(y)
  }
  if y_odd == odd {
    Some(y)
  } else {
    Some(fe_neg(y))
  }
}
