# Reckon

Embeddable EVM execution core in MoonBit.

Status: **P0 in progress** — B01 scaffolding, B02 types, B03 keccak256, B04 RLP,
B05 secp256k1 and B06 fixture loader landed; the interpreter (P1) has not started.

## Layout

| Path | Content |
|---|---|
| [`PLAN.md`](PLAN.md) | 工程实施计划：WBS、门、验证矩阵、风险、ADR |
| [`AGENTS.md`](AGENTS.md) | 工程纪律、命令、工具链坑、决策记录（agent 先读） |
| [`CHANGELOG.md`](CHANGELOG.md) | 变更记录 |
| [`types/`](types) | `U256` (4 x UInt64 limbs)、`Address`、`Hash32`、hex |
| [`crypto/`](crypto) | `keccak256`、`secp256k1`（域/群、ECDSA、RFC 6979、recover、地址推导） |
| [`rlp/`](rlp) | canonical RLP encode/decode |
| [`statetest/`](statetest) | EEST state test 解析：fixture 模型、tx 0/1/2/3 解码、`txbytes` 重签校验 |
| [`cmd/main/`](cmd/main) | `reckon` CLI skeleton |
| `probes/` | 本地研究探针，**不入库**（第三方源码与绝对路径，来源见本地 `probes/README.md`） |
| [`fixtures/`](fixtures/eest) | EEST v5.4.0 stable 语料（tarball + 解包元数据） |
| [`reference/`](reference) | 上游参考项目链接；不 vendor 第三方源码 |
| [`tools/depcheck/`](tools/depcheck) | Go 实现的依赖白名单闸（R11），带单元测试 |

### Progress (P0)

| ID | 工作包 | 状态 |
|---|---|---|
| B01 | 仓库/模块/CI 脚手架 | done：`moon.mod`、包骨架、fmt/check/test、CI、依赖闸 |
| B02 | 类型层 | done：U256 limb + BigInt oracle 对拍、Address/Hash32、hex |
| B03 | keccak256 | done：自研，13 组独立向量（含块边界） |
| B04 | RLP | done：canonical encode/decode + 规范性拒绝 + 随机树往返 |
| B05 | secp256k1 | done：自研（4×64 limb + 伪梅森归约、Jacobian 点运算、RFC 6979 low-s 签名、malleable recover、地址推导）；native 标量乘 1.45 ms、sign 2.1 ms |
| B06 | fixture loader | done：fixture 模型（env/pre/post/transaction/config）、`indexes` 展开、tx 0/1/2/3 解码（EIP-155 与 typed signing hash）、`txbytes` 重签 + sender/recover 校验；5 个真实 fixture 共 158 个 Cancun case 全部 resign ok / sender ok / 0 error |
| B07 | state model v0 | not started |
| B08 | harness v0 | not started |
| B09 | corpus/report | not started |

> **G0 仍未达成**：B06 只做到「fixture 加载 + tx 0/1/2/3 解码 + `txbytes` 重签校验」，
> 账户级 state diff 与 pass/fail 判定要等 B07（state model）与 B08（harness）。

### probes

| Probe | 用途 |
|---|---|
| `evmcore/` | 最小 EVM 执行层探针（bigint 256-bit 回绕、栈、内存、基础 opcode） |
| `u256/` | EVM uint256 limb 算术性能探针 |
| `keccak/` | keccak256 探针与三臂输出 |
| `secp/` | secp256k1 探针 |
| `bignum/` | BigInt 常量/编译期探针 |
| `dispatch/` `dispatch2/` `dispatch3/` | opcode dispatch 成本探针 |
| `superinsn/` | EVM 风格超级指令探针 |
| `consttest/` | 编译期 BigInt 常量探针 |
| `provep/` | proof-carrying code / gas 合约探针 |
| `difftest/` | evmone / geth statetest 差分原型与下载的树 |
| `workload/` `workload2/` | EVM 工作负载语料与运行脚本 |

## 构建与测试

工具链：moonc **0.10.21**（`moonc v0.10.21+06da1ed44`）、moon driver 0.1.20261117、
moonrun 0.1.20261117（与 driver 同 commit）。CI pin 在 `.github/workflows/ci.yml` 的 `MOONBIT_VERSION`，必须是**带构建哈希的完整版本**
（CDN 只认 `0.10.21+06da1ed44` 这种 key，裸 `0.10.21` 返回 403）。

```bash
moon check --target all --deny-warn   # 全后端，warning 即失败
moon test --target wasm-gc            # 三后端都必须显式给 --target
moon test --target js
moon test --target native
moon run cmd/main -- --version
cd tools/depcheck && go test ./... && go run . ../../moon.mod   # R11 依赖白名单
```

`moon test` 不带 `--target` 时走 `moon.mod` 的 `preferred_target`（本仓是 **native**），
不是 wasm-gc——三后端要逐一显式声明。

CI 会额外跑 `moon fmt` 与 `moon info`，并要求 `git diff --exit-code` 为空：
`.mbti` 与格式都由工具链生成，手改即红。

CI 使用官方安装脚本（`cli.moonbitlang.com/install/unix.sh`）并 pin 版本，不引第三方 action。
依赖闸用 Go：硬要求只有两条——闸门不能依赖被它守的 MoonBit 工具链（工具链坏过一次，
闸门必须照跑），判定规则要能被单元测试锁住。Go 单文件 + 标准库 + `go test` 同时满足，
且不引入包管理依赖树。

## 研究探针（不入库）

`probes/` 是研究阶段的探针（u256 / keccak / secp / dispatch / workload 等），
**只保存在本地，不进版本库**：里面混有第三方源码（Apache-2.0 / LGPL-3.0 / GPL-3.0 / BUSL-1.1）、
npm 构建产物以及本机绝对路径。来源、许可证与重新获取方式记在本地 `probes/README.md`。
转正某个探针前：先清掉第三方输入与绝对路径，再单独提交。

## 关键决策

- **库，不是节点**：不做 RPC / mempool / consensus / MPT；状态由 `Host` 提供。
- **四个扩展点**：`Host`、`Inspector`、`PrecompileProvider`、`Spec`。
- **corpus pin**：EEST `tests-v5.4.0`（commit `4f68564`），stable 只到 Prague（35,716 条 Cancun+Prague state test）；Osaka 走 develop，分阶段接入。
- **三臂**：js / wasm-gc / native，**统一 4×UInt64 limb**（js 只承诺正确性、不承诺性能）；BigInt 版仅作测试期第二实现交叉验证，不进生产路径。
- **依赖边界**：**有且仅有 `moonbitlang/*` 与 `moonbit-community/*`**。官方范围只提供 sha256 / ripemd160，keccak / secp256k1 / blake2f / bn254 / BLS12-381 / P-256 全部自研（见 `PLAN.md` 附录 A.5）。
- **CLI**：`reckon statetest` / `reckon run` / `reckon trace` / `reckon bench`。
- **双执行器**：Reference（规范直译）先写，Fast（扁平栈/零分配）后优化，diff 为门。

## 语料

`fixtures/eest/` 内是 v5.4.0 stable：

- `fixtures_stable.tar.gz`（257,344,946 B）
- `probe/fixtures/.meta/fixtures.ini`（`--until=Prague`）
- `probe/fixtures/.meta/index.json`（176,149 case / 44,039 state test）
- `listing.txt`（tar 条目）

复现命令见 [`PLAN.md`](PLAN.md) 附录 B。

## 运行探针

每个 probe 的 `moon.mod` 独立；进入对应目录后按 MoonBit 常规命令运行：

```bash
cd probes/evmcore
moon check
moon run src
```

部分 probe 是脚本/输出集（如 `keccak/`、`difftest/`），按其目录内文件说明使用。
