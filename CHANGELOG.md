# 变更记录

记录对使用者可见的变化。pre-1.0 阶段不承诺 API 稳定（见 PLAN.md ADR-10）。

## [未发布] 0.1.0 — 2026-11-20

### 新增

- `types`：`U256`（4×UInt64 limb，加法/减法/乘法/除法/取模/`addmod`/`mulmod`/`exp`/
  移位/`BYTE`、大端字节与十六进制互转）、`Address`（20 字节）、`Hash32`（32 字节）、
  `hex` 编解码、`DecodeError`。
- `crypto`：`keccak256`（自研 Keccak-f[1600]，rate 136 字节，域分隔符 0x01）。
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

- 模块名定为 `vitro/reckon`（mooncakes 用户名 `vitro`），包路径为模块内目录，
  PLAN 初稿的 `evm/` 前缀废弃。
- 依赖闸语言由 shell 改为 Go：闸门不得依赖被它守的 MoonBit 工具链，且规则要能被单元测试锁住。
- 换行统一为 LF（`.gitattributes`，`* text=auto eol=lf`）。

### 验证

- `moon check --target all --deny-warn`：0 error / 0 warning。
- `moon test`：32/32（wasm-gc）；`--target js`：32/32；`--target native`：32/32。
- 从索引物化的干净检出可构建并通过同一套测试。
- keccak256：13 组基础向量 + 31 组块边界/多块向量（pycryptodome 独立生成，
  覆盖 135/136/137、271/272/273、407/408/409、543/544/545）。
- U256：随机 150 组四则、80 组 `addmod`/`mulmod`、40 组移位；另加固化对拍——
  6 个极值 × 256 位移位全扫（3072 组）、极值网格 6×6×5（含四则与 `addmod`/`mulmod`）、
  5 个大指数 `exp`（最大到 `2^256-1`），全部由 `@bigint` 给出期望值。
