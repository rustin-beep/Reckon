// Keccak-256（以太坊使用的、标准化之前的变体）。
//
// Keccak-f[1600]，rate 1088 位（136 字节），capacity 512 位，域分隔符 0x01
// （SHA3 用 0x06），摘要 32 字节。
//
// 移植自 `probes/keccak`，那里的置换已在 native / wasm-gc / js 三臂验证过。
// 置换未改；接口改为接收 `BytesView`、返回 `Hash32`。

///|
/// Keccak-256 的 rate（字节）。
let keccak_rate : Int32 = 136

///|
/// 旋转偏移，按 `x + 5*y` 索引。
let keccak_rotc : FixedArray[Int32] = [
  0, 1, 62, 28, 27, // y = 0
   36, 44, 6, 55, 20, // y = 1
   3, 10, 43, 25, 39, // y = 2
   41, 45, 15, 21, 8, // y = 3
   18, 2, 61, 56, 14, // y = 4
]

///|
/// 24 round constants.
let keccak_rc : FixedArray[UInt64] = [
  0x0000000000000001UL, 0x0000000000008082UL, 0x800000000000808AUL, 0x8000000080008000UL,
  0x000000000000808BUL, 0x0000000080000001UL, 0x8000000080008081UL, 0x8000000000008009UL,
  0x000000000000008AUL, 0x0000000000000088UL, 0x0000000080008009UL, 0x000000008000000AUL,
  0x000000008000808BUL, 0x800000000000008BUL, 0x8000000000008089UL, 0x8000000000008003UL,
  0x8000000000008002UL, 0x8000000000000080UL, 0x000000000000800AUL, 0x800000008000000AUL,
  0x8000000080008081UL, 0x8000000000008080UL, 0x0000000080000001UL, 0x8000000080008008UL,
]

///|
fn rotl64(x : UInt64, n : Int32) -> UInt64 {
  // MoonBit shifts are mod 64, so n = 0 also works: x | x == x.
  (x << n) | (x >> (64 - n))
}

///|
/// 对 25 个 lane 原地做 Keccak-f[1600]。
fn keccak_f1600(a : FixedArray[UInt64]) -> Unit {
  let c = FixedArray::make(5, 0UL)
  let d = FixedArray::make(5, 0UL)
  let b = FixedArray::make(25, 0UL)
  for round in 0..<24 {
    // theta
    for x in 0..<5 {
      c[x] = a[x] ^ a[x + 5] ^ a[x + 10] ^ a[x + 15] ^ a[x + 20]
    }
    for x in 0..<5 {
      d[x] = c[(x + 4) % 5] ^ rotl64(c[(x + 1) % 5], 1)
    }
    for y in 0..<5 {
      for x in 0..<5 {
        a[x + 5 * y] = a[x + 5 * y] ^ d[x]
      }
    }
    // rho + pi
    for y in 0..<5 {
      for x in 0..<5 {
        let idx = x + 5 * y
        let nx = y
        let ny = (2 * x + 3 * y) % 5
        b[nx + 5 * ny] = rotl64(a[idx], keccak_rotc[idx])
      }
    }
    // chi
    for y in 0..<5 {
      for x in 0..<5 {
        let i = x + 5 * y
        a[i] = b[i] ^
          (
            (b[(x + 1) % 5 + 5 * y] ^ 0xFFFFFFFFFFFFFFFFUL) &
            b[(x + 2) % 5 + 5 * y]
          )
      }
    }
    // iota
    a[0] = a[0] ^ keccak_rc[round]
  }
}

///|
/// 计算 `data` 的 Keccak-256 摘要。
pub fn keccak256(data : BytesView) -> @types.Hash32 {
  let len = data.length()
  let q = keccak_rate - len % keccak_rate
  let pad_len = len + q
  let padded = FixedArray::make(pad_len, b'\x00')
  for i in 0..<len {
    padded[i] = data[i]
  }
  // pad10*1 with the Keccak domain byte 0x01
  padded[len] = b'\x01'
  padded[pad_len - 1] = padded[pad_len - 1] | b'\x80'

  let a = FixedArray::make(25, 0UL)
  let mut off = 0
  while off < pad_len {
    // one 136-byte block = 17 little-endian lanes
    for i in 0..<17 {
      let mut lane = 0UL
      for j in 0..<8 {
        lane = lane | (padded[off + i * 8 + j].to_uint64() << (8 * j))
      }
      a[i] = a[i] ^ lane
    }
    keccak_f1600(a)
    off = off + keccak_rate
  }

  let out = FixedArray::make(32, b'\x00')
  for i in 0..<4 {
    let lane = a[i]
    for j in 0..<8 {
      out[i * 8 + j] = (lane >> (8 * j)).to_byte()
    }
  }
  @types.Hash32::from_fixed_unchecked(out)
}
