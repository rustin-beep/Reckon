# 变更记录

记录对使用者可见的变化。pre-1.0 阶段不承诺 API 稳定（见 PLAN.md ADR-10）。

## [未发布] 0.1.0 — 2026-11-20

### 新增

- `types`：`U256`（4×UInt64 limb，加法/减法/乘法/除法/取模/`addmod`/`mulmod`/`exp`/
  移位/`BYTE`、大端字节与十六进制互转）、`Address`（20 字节）、`Hash32`（32 字节）、
  `hex` 编解码、`DecodeError`。
- `crypto`：`keccak256`（自研 Keccak-f[1600]，rate 136 字节，域分隔符 0x01）。
- `crypto`：`secp256k1`（自研、纯 MoonBit、三后端无 FFI）：
  - 域：`F_p`（4×64 limb + 伪梅森归约 `2^256 ≡ 2^32 + 977`）与 `F_n`（逐位归约，
    冷路径正确优先）、加/减/乘/平方/求逆（二进制扩展欧几里得）/幂/比较/32 字节编解码；
  - 群：Jacobian 点加/倍/标量乘、仿射转换、`on_curve`、SEC1 压缩/非压缩解析与序列化、
    `sqrt` 解压缩；
  - ECDSA：RFC 6979 确定性签名（HMAC-SHA256，low-s，归一化时翻转 recid）、验签、
    SEC1 `recover`（recid 0..3，malleable：不拒绝 high-s）、公钥→地址（keccak）；
  - 公开 API：`secp_sign` / `secp_verify` / `secp_recover` /
    `secp_generate_public_key` / `secp_public_key_to_address`、`PublicKey`、`Signature`
    （`is_low_s` 供 C12/P02 做策略判定）、统一错误 `SecpError`；明确**不承诺**常数时间。
- `types`：`Address::from_bytes_unchecked`（keccak 尾部截取的快路径，与
  `Hash32::from_fixed_unchecked` 同风格）。
- `rlp`：规范 RLP 编解码，包含非规范形式的拒绝（单字节 <0x80 包裹、短载荷用长格式、
  长度前导零、尾随字节、截断）。
- `cmd/main`：`reckon` CLI 骨架，`--version` / `--help` 可用，四个子命令占位。
- `tools/depcheck`：Go 实现的依赖白名单闸（PLAN R11），带表驱动单元测试。
- CI：官方安装脚本 + 版本钉（`0.10.21+06da1ed44`）；依赖闸独立 job；
  `moon fmt` / `moon info` 漂移检查；wasm-gc / js / native 三后端测试；
  `moon check --deny-warn`，warning 即失败。

### 修复（首轮审阅）

- 依赖闸不再按行匹配：`import` 与 `{` 分行、路径依赖、注释、字符串里的 `import`
  都按 token 扫描处理（P2-1，原实现可被纯格式化绕过）。
- `moon check --deny-warn` 进 CI：原命令带 warning 仍 exit 0，“0 warning”没有门禁（P2-2）。
- RLP 解码加嵌套深度上限（128 层）：native 上 1000 层合法嵌套会静默爆栈，
  现在超限抛 `DepthLimitExceeded`（P2-3）。
- RLP 长度校验改为减法判界：`start + len` 在 `len` 接近 `Int32` 上限时溢出，
  错误分类从 `UnexpectedEnd` 退化为 `TrailingBytes`（P3-1）。
- `Hash32::from_fixed` 改为抛 `DecodeError`，另给 `from_fixed_unchecked` 给 keccak 快路径，
  消除同类型两个构造函数行为不一致。
- `reference/README.md` 的本机参考树路径改为可移植描述；`moon-lock` 不再被忽略。

### 变更

- `crypto` 新增依赖 `moonbitlang/x@0.5.8`，只用 `SHA256` 与 `hmac` 拼 RFC 6979；
  这是 PLAN A.5 依赖边界内的官方包。包名与本包同为 `crypto`，`moon.pkg` 里用
  显式别名 `@xcrypto` 规避 duplicate alias（否则 `--deny-warn` 会红）。

- 模块名定为 `vitro/reckon`（mooncakes 用户名 `vitro`），包路径为模块内目录，
  PLAN 初稿的 `evm/` 前缀废弃。
- 依赖闸语言由 shell 改为 Go：闸门不得依赖被它守的 MoonBit 工具链，且规则要能被单元测试锁住。
- 换行统一为 LF（`.gitattributes`，`* text=auto eol=lf`）。

### 验证

- `moon check --target all --deny-warn`：0 error / 0 warning。
- `moon test`：56/56（wasm-gc）；`--target js`：56/56；`--target native`：56/56
  （B05 新增 24 条，原 32 条无回归）。
- 从索引物化的干净检出可构建并通过同一套测试。
- keccak256：13 组基础向量 + 31 组块边界/多块向量（pycryptodome 独立生成，
  覆盖 135/136/137、271/272/273、407/408/409、543/544/545）。
- U256：随机 150 组四则、80 组 `addmod`/`mulmod`、40 组移位；另加固化对拍——
  6 个极值 × 256 位移位全扫（3072 组）、极值网格 6×6×5（含四则与 `addmod`/`mulmod`）、
  5 个大指数 `exp`（最大到 `2^256-1`），全部由 `@bigint` 给出期望值。
- secp256k1（B05）：域/标量域各 7×7 边界网格 + 200 组确定性伪随机（LCG）对拍
  `@bigint`；`inv` 各 50 组对拍且 `inv(0)` 抛错；512 位归约极值（全 1、`(p-1)^2`、
  `n^2`）；群：BIP-340 三组 x-only 向量、`2G`/`nG`/`(n-1)G`、BigInt 仿射 oracle 对拍
  （标量 0/1/2/3/5/n-1/n）、压缩/非压缩回环、坏公钥 5 类拒绝；ECDSA：RFC 6979 向量 1
  （`d=1`，`k=8f8a276c…`）、ETH 向量 2（`testPrivHex` + `keccak256("foo")` + 地址
  `0x970e…f791`）、geth `TestEcrecover` 向量 3（恢复出 `0xe32df428…` 与地址
  `0xa19d…633b`）、high-s/`recid^1` malleable、`digest = 2^256-1`、非法输入 8 组。
- B05 性能（native release，中位数）：`fe_mul` 0.16 µs、点倍 3.6 µs、点加 4.4 µs、
  标量乘 1.45 ms、`sign` 2.1 ms、`verify` 4.2 ms、`recover` 4.4 ms；js 标量乘 9.5 ms
  （ADR-3：js 只承诺正确性）。BigInt 探针基线为 3.58 ms/标量乘。
