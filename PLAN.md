# MoonBit EVM 执行核：工程实施计划

> as_of: 2026-11-20
> corpus 基准：EEST `tests-v5.4.0`（commit `4f68564f47c7e577ad6cbb570858316f5ff0e7bb`）

---

## 0. 计划口径

| 项 | 定值 |
|---|---|
| 产品形态 | **库 + 薄 CLI**；不是节点，不做 RPC/mempool/consensus/MPT |
| **依赖边界** | **有且仅有 `moonbitlang/*` 与 `moonbit-community/*`**；官方成员个人包、其余第三方一律不依赖（含 `cc06b/mooncry`、`moonbitstack/mooncrypt`、`skmtkytr/ethbit`、`CAIMEOX/evmasm`） |
| revision 面 | Cancun / Prague / Osaka |
| 主验收 corpus | EEST **v5.4.0 stable**（`--until=Prague`）：44,039 条 state test，其中 Cancun 16,847 + Prague 18,869 = **35,716** 条 |
| 扩展验收 corpus | EEST v5.4.0 **develop**（Osaka）：分阶段接入，不与 stable 混算 |
| 状态比对口径 | `post.state` 全量 alloc（抽样实测 `pre ⊆ state`），账户级比对；**不宣称 state-root pass** |
| 非目标（v1） | blockchain tests、主网 replay、MPT、节点、RPC、mempool、L2 定制 Handler |
| 估算口径 | 人日，含测试/报告；agent 并行压缩日历，不压缩审阅/探针/差分 |

### 0.1 已核实的 corpus 事实

| 项 | 实测值 | 来源 |
|---|---|---|
| stable 构建范围 | `--until=Prague` | `fixtures/.meta/fixtures.ini` |
| stable 大小 | 257,344,946 B | release asset |
| case 总数 | 176,149 | `fixtures/.meta/index.json` |
| state test 总数 | 44,039 | 同上 |
| Cancun state test | 16,847 | 同上 |
| Prague state test | 18,869 | 同上 |
| 现代 fork 合计 | 35,716 | 16,847 + 18,869 |
| `post.state` | 必填 `Alloc`；抽样 `pre ⊆ state` | 抽样 3 个 fixture |
| `expectException` | 字符串，如 `TransactionException.TYPE_3_TX_ZERO_BLOBS` | 抽样 |
| `txbytes` | 198–458 B；需精确重签 | 抽样 |
| Osaka | 只在 develop；stable 的 forks 列表无 Osaka | `fixtures.ini` + `index.json` |

---

## 1. 原计划 → 工作包映射

| 原计划 | 新工作包 | 处置 |
|---|---|---|
| 二、fork 选型：Cancun 基线 + Prague/Osaka 补丁 | ADR-2；P1 / P2 / P3 | 保留；stable 实测只到 Prague，Osaka 走 develop 分阶段 |
| 三、四层架构 + 双执行器 | 包划分；C13 Reference / C14 Fast / C15 diff | 保留；**双执行器提前到 P1**，不放到 M2 |
| 四、性能预算：栈/U256/dispatch | P5 X01–X07 | 保留；作为 P5 验收项，不前置 |
| 五、验证四层 L1–L4 | P4；验证矩阵 L0–L5 | 保留并补 L0（官方 fixture）与 L5（可选主网） |
| 六、里程碑 M0–M4 | G0–G5 | 重排：harness 先行、Prague/Osaka 独立成段、差分/三臂独立成段 |
| 七、风险与退出条件 | 风险登记册 R1–R10；预编译分组门 | 扩写：补 BLS12-381/P256/modexp，不只 bn254 #7 |
| 八、能/不能宣称 | 第 8 节「声明边界（工程口径）」 | 保留为验收口径，去掉叙事化表述 |

### 1.1 与 M0–M4 的对应

| 原里程碑 | 新门 | 差异 |
|---|---|---|
| M0 keccak + u256 + 20 opcode → 第一条 state-diff | **G0** harness + 一条 Cancun family | 改为 harness 先行；tx 解码/重签进入 M0 范围 |
| M1 全 opcode + gas + journal + CALL/CREATE | **G1** Cancun 核心 | 明确 tx 层（0/1/2/3/4）与 `txbytes` 检查 |
| M2 Reference/Fast 双执行器 | **C13/C14/C15（P1 内）** | 提前；Prague/Osaka 增量必须建在 diff 通过的核上 |
| M3 trace + goevmlab | **G4** 差分/模糊 | EIP-3155 trace v0 在 C15；三臂 trace 在 X05 |
| M4 性能调优 + bench | **G5** 三臂/性能 | 增加三臂逐字节与分歧定性 |

---

## 2. 架构与包划分

模块名 **`vitro/reckon`**（mooncakes 用户名 `vitro`）；下表路径就是模块内的目录，也是
`moon.pkg` 里引用的包路径（如 `vitro/reckon/types`）。初稿写作 `evm/xxx` 的前缀已废弃：
MoonBit 一个模块内的包路径就是目录本身。按真实依赖边界切包，不照搬 revm 的十来个 crate。

| 包 | 职责 | 依赖 | 状态（2026-11-20） |
|---|---|---|---|
| `types/` | U256（4×UInt64 limb；BigInt 仅测试期 oracle）、Address/Hash32/hex、错误 | — | **已落地**（B02） |
| `crypto/` | keccak256、secp256k1、modexp、ripemd160、blake2f、sha256；bn254/BLS12-381/P256 为可选子模块。**官方范围只提供 sha256 / ripemd160（`moonbitlang/x/crypto`），其余全部自研**——见 A.5 | types | keccak256 **已落地**（B03）；其余待做 |
| `rlp/` | canonical RLP encode/decode | types | **已落地**（B04） |
| `state/` | Account/Storage、Journal（snapshot/revert）、warm/cold、transient、refund、selfdestruct | types | 计划（B07） |
| `interpreter/` | 栈/内存/gas/dispatch/帧/CALL/CREATE | types, state, crypto | 计划（P1 C01–C12） |
| `precompiles/` | `PrecompileProvider` + 分组实现 | crypto, types | 计划 |
| `host/` | `Host` trait、BlockEnv/TxEnv、`Inspector`、EIP-3155 trace | types, state | 计划（C08） |
| `facade/` | `Evm`、`ExecutionResult`、`State` diff、`Spec` revision 表 | 全部 | 计划 |
| `statetest/` | fixture runner（薄 CLI `cmd/main` 调用） | facade, rlp, crypto | 计划（B06/B08） |
| `bench/` | benchmark runner（evmone-bench 兼容格式） | facade | 计划（X01） |
| `cmd/main/` | `reckon` CLI 骨架 | core/env | **已落地**（B01） |
| `tools/depcheck/` | 依赖白名单闸（**Go**，非 MoonBit 包） | — | **已落地** |

### 2.1 API 骨架

```moonbit
pub trait Host {
  basic(Address) -> AccountInfo
  code(Address) -> Bytes
  storage(Address, U256) -> U256
  original_storage(Address, U256) -> U256
  block_hash(UInt64) -> Bytes32
}

pub fn Evm::transact(self, tx : Tx, env : BlockEnv) -> Result[ExecutionResult, EvmError]

pub struct ExecutionResult {
  status : Status          // success / revert / halt
  gas_used : UInt64
  gas_refunded : UInt64
  logs : Array[Log]
  output : Bytes
  state_diff : StateDiff
}

pub trait Inspector {
  step(...); call(...); create(...); log(...); precompile(...)
}

pub trait PrecompileProvider {
  run(address : Address, input : Bytes, gas : UInt64) -> Option[Result[Bytes, EvmError]]
}
```

**四个扩展点**：`Host`、`Inspector`、`PrecompileProvider`、`Spec`。
v1 不做全流程可替换 `Handler`；固定执行循环，降低三臂分歧面。

### 2.2 状态与提交语义

- `Host` 同步接口；异步 RPC/缓存由嵌入方包在 Host 外。
- 核心返回 `StateDiff`，不直接改宿主状态；嵌入方原子 commit。
- Journal 负责 snapshot/revert、warm/cold、transient、refund、selfdestruct（EIP-6780）。
- v1 不实现 MPT；state root 仅作为未来 blockchain tests 的扩展位。

---

## 3. 工作分解（WBS）

### P0 基线（20–31 人日）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| B01 | 仓库/模块/CI 脚手架 | `moon.mod`、包骨架、fmt/check/test、CI 分片 | — | 1–2 |
| B02 | 类型层 | U256 limb + BigInt 变体、Address/Hash/Bytes、hex、边界测试 | B01 | 3–4 |
| B03 | keccak256 | **自研**（`moonbitlang/x/crypto` 实测只有 sha1/224/256/384/512、md4/md5、ripemd160、sm3、aes、chacha、hmac，**无 keccak/sha3**）；空输入/长输入/已知向量/地址派生向量 | B01 | 2–3 |
| B04 | RLP | canonical encode/decode + 往返/fuzz | B02 | 1–2 |
| B05 | secp256k1 | **自研**（官方范围无 secp256k1）：域/标量运算、Jacobian 点加/倍/标量乘、RFC 6979、low-s、recover、地址推导。探针实测：标量乘 269 行，完整 ecrecover +185~290 行；性能 1–2ms/次，热路径需换 4×64 limb 定点域运算 | B02 | 6–9 |
| B06 | fixture loader | JSON schema、indexed 展开、tx 解码 | B02/B04 | 2–3 |
| B07 | state model v0 | Account/Storage、journal 接口 | B02 | 2–3 |
| B08 | harness v0 | run fixture → state diff → pass/fail | B06/B07 | 2–3 |
| B09 | corpus/report | EEST pin、分片、报告骨架 | B08 | 1–2 |

**G0**（harness 门，**不含执行正确性**）：`reckon statetest <fixture>` 能加载 → 解码 tx（含 `txbytes` 重签）→ 跑完 1 个 Cancun family **不崩**，输出账户级 diff 结构 + pass/fail 计数；报告可复现。

> 口径修正（2026-11-20）：原稿 G0 写「账户级全绿」，但 P0 工作包内没有 interpreter（C01–C12 全在 P1），无法执行 tx。G0 只判 harness 通路，执行正确性由 G1 判。

### P1 Cancun 核心（44–58 人日）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| C01 | 栈 | 扁平 `FixedArray[UInt64]`、sp、越界/溢出 | B02 | 3 |
| C02 | 内存 | byte 数组、expansion gas、MCOPY | C01 | 2–3 |
| C03 | gas | 静态表、内存扩展、warm/cold、63/64、stipend、refund | C01/C02 | 4–5 |
| C04 | dispatch | 256 分支 match、jumpdest 分析 | C01 | 2–3 |
| C05 | 算术/位运算 | U256 全套、signed、shift、EXP、SIGNEXTEND | C04 | 3–4 |
| C06 | 环境/块/存储/日志 | calldata/code/storage/log/blockhash/basefee/blobhash | C03/C04 | 3–4 |
| C07 | 控制流/终止 | JUMP/JUMPI/STOP/RETURN/REVERT/INVALID | C04 | 1–2 |
| C08 | `Host` 接口 | basic/code/storage/original/block_hash | B07 | 2–3 |
| C09 | Journal | snapshot/revert、warm/cold、transient、EIP-6780 | C08 | 4–5 |
| C10 | CALL 族 | depth 1024、value、static、gas forwarding、precompile 调用 | C09 | 4–5 |
| C11 | CREATE/CREATE2 | 地址推导、initcode、code deposit、EIP-3541/3860 | C09 | 3–4 |
| C12 | tx 层 | legacy/2930/1559/4844 解码+校验+intrinsic gas+blob 字段 | B04/B05 | 4–5 |
| C13 | Reference executor | 规范直译、可读、慢 | C01–C12 | 4–5 |
| C14 | Fast baseline | 扁平栈/零分配，先不加超级指令 | C01–C12 | 3–4 |
| C15 | diff + trace v0 | pc/op/gas/stack/mem/depth/returndata/refund/logs/state | C13/C14 | 2–3 |

**G1**：Cancun 非预编译 state test ≥99% 账户级通过，**且剩余项逐条归因、未解释数 = 0**；Reference/Fast diff = 0；`txbytes` 重签一致。

> 归因口径：每条失败必须落到五类之一——①已知未实现（预编译/opcode，带 ID）②fixture 语义未覆盖（带 EIP）③本实现缺陷（带 issue）④oracle 口径差异（带证据）⑤待查。**「待查」进门禁即红**。

### P2 Prague 增量（10–15 人日，BLS 另计）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| P01 | revision 表 | Cancun→Prague 差异表 | G1 | 1–2 |
| P02 | EIP-7702 | authorization list、delegation、code resolution、gas | P01 | 4–5 |
| P03 | EIP-7623 | calldata cost | P01 | 1 |
| P04 | EIP-7691 / 7840 | blob 参数与 blob schedule | P01 | 1–2 |
| P05 | EIP-2935 | historical block hashes（若 state test 覆盖） | P01 | 1–2 |
| P06 | Prague 回归 | 分组报告 | P02–P05 | 2–3 |
| P07 | EIP-2537 BLS12-381 | 0x0b–0x11；**可选门** | P01 | 20–30 |

**G2**：Prague 非加密 state test ≥99%，**且剩余项逐条归因、未解释数 = 0**；7702/7623 全绿；bn254/BLS/KZG/P256 按组报通过率；**P07（BLS12-381）的做/不做在此拍板，最晚 G1 通过后 10 个工作日内定，逾期默认不做**。

### P3 Osaka 增量（15–20 人日，develop corpus）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| O01 | revision 表 | Prague→Osaka 差异表 | G2 | 1 |
| O02 | EIP-7939 | CLZ opcode | O01 | 1 |
| O03 | EIP-7951 | P256VERIFY（0x100）；**自研**（官方范围无 P-256 实现） | O01 | 8–11 |
| O04 | EIP-7883/7823 | modexp 重定价/上限 | O01 | 1–2 |
| O05 | EIP-7825 | tx gas cap 2²⁴ | O01 | 1 |
| O06 | EIP-7918 | blob reserve price（tx/env） | O01 | 1 |
| O07 | Osaka 回归 | develop corpus 分组报告 | O02–O06 | 2–3 |

**G3**：Osaka 非加密 state test ≥99%，**且剩余项逐条归因**（develop corpus 必须 pin 到具体 commit，写在报告 `as_of`；未 pin 则 G3 不成立）。

### P4 外部差分与模糊（14–22 人日）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| D01 | evmone adapter | `evmone test --state-diff` 对拍 | G1 | 2–3 |
| D02 | EELS adapter | `ethereum-spec-evm` 第三方 oracle | G1 | 2–3 |
| D03 | expectException 映射 | EELS 枚举 → 本地判定表 | G1 | 2–3 |
| D04 | txbytes 重签 | RFC 6979/low-s/typed envelope 一致性 | B05/C12 | 1–2 |
| D05 | goevmlab 接入 | tracediff + generic-fuzzer | D01 | 4–6 |
| D06 | 分桶/最小化/登记 | known divergence 台账 | D05 | 2–3 |
| D07 | 报告生成器 | 分组通过率/分母/异常覆盖 | D03–D06 | 1–2 |

**G4**：三方差分零未解释分歧；fuzz 首轮报告；所有 known divergence 有归因。

### P5 三臂与性能（20–29 人日）

| ID | 工作包 | 产出 / 验收 | 依赖 | 人日 |
|---|---|---|---|---|
| X01 | bench harness | evmone-bench 兼容、校验和逐位一致 | G1 | 2–3 |
| X02 | native 优化 | dispatch/栈/U256/gas 热点 | X01 | 5–7 |
| X03 | js BigInt U256 | 全量可跑 + 性能画像 | X01 | 4–6 |
| X04 | wasm-gc 臂 | 构建 + wasm-opt + host glue | X01 | 3–4 |
| X05 | 三臂 trace diff | EIP-3155 逐字节；分歧分桶 | X03/X04 | 3–4 |
| X06 | 分歧定性 | 编译器 bug / 实现 bug / spec 歧义；上游 issue 流程 | X05 | 2–3 |
| X07 | per-opcode 报告 | gas/成本/Mgas/s 四维 | X02–X05 | 1–2 |

**G5**：**X01 指定的 evmone-bench 兼容 benchmark 全集**上，native 单臂**几何均值** ≥300 Mgas/s（不是单条最高值）；每条 bench 须报「校验和逐位一致 + 中位数 + 5 进程」；三臂 EIP-3155 trace divergence = 0 或全部分类；per-opcode 报告发布。

> 口径修正（2026-11-20）：原稿只写「native 目标负载 ≥300」，未绑 benchmark 集合与统计口径，无法判定达标。

### P6 可选扩展（不进 v1 验收）

| ID | 工作包 | 说明 | 人日 |
|---|---|---|---|
| E01 | blockchain tests | header/withdrawals/system contracts/MPT | 15–25 |
| E02 | 主网块 replay | archive node / 状态证明 | 10–20 |
| E03 | 嵌入 demo | 浏览器 wasm-gc / dApp 钱包 | 5–10 |
| E04 | Inspector 工具 | call tree / coverage | 5–8 |
| E05 | advanced interpreter | 超级指令/块级预扣 | 8–12 |

---

## 4. 里程碑、关键路径、工作量

### 4.1 门

| 门 | 内容 | 前置 | 验收 |
|---|---|---|---|
| G0 | harness 可复现 | P0 | 1 个 Cancun family 账户级绿 |
| G1 | Cancun 核心 | P1 | 非预编译 ≥99%，ref/fast diff=0 |
| G2 | Prague 核心 | P2 | 非加密 ≥99%，预编译分组报告 |
| G3 | Osaka 核心 | P3 | 非加密 ≥99%（develop） |
| G4 | 差分/模糊 | P4 | 零未解释分歧 |
| G5 | 三臂/性能 | P5 | ≥300 Mgas/s，三臂分歧分类 |

### 4.2 关键路径

```
B02/B03/B05 → B06/B07/B08 → C01–C12 → C13/C14/C15 → G1
→ P01–P06 → G2 → D01/D03/D04 → X01–X05 → G5
```

### 4.3 工作量汇总

| 阶段 | 核心（无 bn254/BLS） | 含加密组 |
|---|---:|---:|
| P0 | 20–31 | 20–31 |
| P1 | 44–58 | 44–58 |
| P2 | 10–15 | +35–50 |
| P3 | 15–20 | 15–20 |
| P4 | 14–22 | 14–22 |
| P5 | 20–29 | 20–29 |
| **合计** | **123–175** | **158–225** |

**MVP 路径**（只到 G1 + evmone 对拍 + bench）：
P0 + P1 + D01 + X01 ≈ **68–95 人日**，单臂 native、Cancun only、预编译只做 0x01–0x05/0x09。

**范围旋钮**：

| 范围 | 内容 | 人日 |
|---|---|---:|
| MVP | P0 + P1 + D01 + X01 | 68–95 |
| 完整证据面 | P0–P5（无 bn254/BLS） | 123–175 |
| 加加密组 | +bn254（15–20）+ BLS12-381（20–30） | 158–225 |

### 4.4 本季度交付边界（日历约束，2026-11-20 定）

单人的有效工作日 ≈ 60–75 天/季度；「agent 并行压缩日历」压缩的是工具等待，不是人的日历。按 WBS 逐项相加：

| 范围 | 人日 | 与一季度的关系 |
|---|---:|---|
| P0 全（20–31） | 20–31 | 可完成 |
| P0 + P1 至 C12（interpreter 主干） | 55–77 | **刚好踩线** |
| MVP（P0+P1+D01+X01） | 68–95 | **超一季度** |
| 完整证据面（P0–P5） | 123–175 | 需 2–3 个季度 |

据此：

| 项 | 判定 |
|---|---|
| 本季度目标 | **P0 全 + P1 的 C01–C12**（能执行真实交易，未达 99%） |
| G1（≥99% + 归因） | **顺延到下一季度初** |
| 本季度不承诺 | P2/P3/P4/P5 全部；三臂；bench |
| 证据面口径 | 本季度只出「跑通 N 个 Cancun fixture + `txbytes` 重签一致」，**不出通过率** |
| 跨季度 | 报告按 `as_of` 增量追加，不改写旧报告 |

**推论**：§8 声明边界里的条目（除 `txbytes` 重签率外）本赛季均不可用。

---

## 5. 验证矩阵

| 层 | 对象 | 判据 | 门 |
|---|---|---|---|
| L0 | EEST stable/develop state tests | 账户级 `post.state` 比对；`txbytes`；`expectException` | G1–G3 |
| L1 | evmone `test --state-diff` | 执行摘要 + state diff 零未解释分歧 | G4 |
| L2 | EELS `ethereum-spec-evm` | 抽样/差分一致 | G4 |
| L3 | goevmlab tracediff + generic-fuzzer | 无新增分歧；分歧最小化登记 | G4 |
| L4 | js / wasm-gc / native | **三臂内部**：EIP-3155 自定格式逐字节一致（ADR-7）。**对外不做字节比较**——evmone/EELS 的字段序、hex 大小写、gas 表示均不同，L1/L2 只做归一化字段比对 | G5 |
| L5 | 主网块 replay | 可选；需 MPT/归档节点 | P6 |

**报告固定字段**：fixture tag + commit、fork、format、pass/total、`txbytes` 覆盖、`expectException` 覆盖、per-precompile-group、三臂 divergence、bench 校验和。

### 5.1 差分轴

Reference vs Fast、以及三臂之间，至少比较：

- `pc`、`op`、`gas_left`
- 栈全量（或栈顶 N + 栈高）
- 内存（全量或 hash；分歧时回放全量）
- `depth`、`return_data`
- `status`（success/revert/halt）
- `refund`
- `logs`
- `state_diff`（账户/storage/nonce/balance/code）

---

## 6. 预编译分组与决策门

| 组 | 地址 | 内容 | Cancun+Prague 用例 | 占比 | 决策 |
|---|---|---|---:|---:|---|
| A | 0x01–0x05, 0x09 | ecrecover/sha256/ripemd/identity/modexp/blake2f | ≥1,600 | ≥4.5% | **必做**；ecrecover 另被 txbytes/7702 依赖 |
| B | 0x06–0x08 | bn254 ecadd/ecmul/pairing | 2,432 | 6.81% | 可选门；G2 拍板 |
| C | 0x0a–0x11 | KZG point eval + EIP-2537 BLS12-381 | 1,338 | 3.75% | 可选门；G2 拍板 |
| D | 0x100 | P256VERIFY（Osaka） | 13 | 0.03% | **自研**（官方范围无 P-256）；G3 拍板 |

- **加密悬崖并集**（B+C+D）：3,770 条，占 **10.56%**（按 test id 子串近似，去重后略低）。
- 没有 B/C/D 时，只报「非加密 state test 通过率」，不宣称 full Prague。
- 纯 MoonBit 实现是三臂自洽的前提；FFI 只作为 native 回退，并登记边界。

### 6.1 预编译实现顺序

1. 0x01 ecrecover（B05 已含 secp256k1）
2. 0x02/0x03/0x04（sha256/ripemd160/identity）
3. 0x05 modexp（大整数，非配对）
4. 0x09 blake2f
5. 0x06–0x08 bn254（可选门 B）
6. 0x0a–0x11 KZG + BLS12-381（可选门 C）
7. 0x100 P256（Osaka，可选门 D）

---

## 7. 风险登记册

| ID | 风险 | 触发 | 缓解 | 退出 |
|---|---|---|---|---|
| R1 | BLS12-381 悬崖 | P2 结束仍无 | `PrecompileProvider` 可选模块；按组报率 | 不做 C 组，不宣称 full Prague |
| R2 | bn254 悬崖 | 同上 | 同上 | 不做 B 组 |
| R3 | js 臂与 limb 核分歧 | 三臂 diff 非零 | **v1 三臂统一 limb**（ADR-3 修订）；BigInt 版仅作测试期第二实现交叉验证，不进生产路径 | 分歧定性；js 只承诺正确性、不承诺性能 |
| R11 | 依赖面违规 | 出现 `moonbitlang/*`、`moonbit-community/*` 之外的 import | CI 白名单闸 + `moon.mod` diff 审阅 | 门禁红，禁止合入 |
| R12 | 日历超支（单人 vs 人日） | G1 前累计超 60 工作日 | 按 §4.4 砍到 MVP；P2–P5 顺延 | 不压缩审阅与差分 |
| R4 | txbytes 重签不一致 | G1 前 | RFC 6979/low-s 向量；自研 secp256k1 的 recover 分支单测 | 未过不开 G1 |
| R5 | fixture 漂移 | 新 release | pin tag/commit；报告 as_of | 旧报告不改写，新增 as_of |
| R6 | evmone oracle 差异 | modexp/ecrecover | GMP 构建；known divergence 台账 | 无未登记差异 |
| R7 | 性能不达标 | X02 后 <150 Mgas/s | profile；砍超级指令；保正确性 | 目标 300，底线 150 |
| R8 | 三臂编译器 bug | X05 | 上游 issue 流程 | 不静默降级 |
| R9 | scope 蔓延（节点/MPT） | 需求插入 | v1 非目标；变更走 ADR | 不进入 v1 |
| R10 | 全量 CI 过慢 | 单 PR >30 min | 分片/缓存/nightly | 单 PR 子集，nightly 全量 |

---

## 8. 声明边界（工程口径）

| 可声明 | 前置条件 |
|---|---|
| Cancun/Prague 非加密 state test 通过率（分母 35,716） | G1/G2 |
| 各预编译组通过率 | 对应组完成 |
| `txbytes` 重签一致率 | B05/C12/D04 |
| 三臂 EIP-3155 trace divergence 数 | G5 |
| Mgas/s + per-opcode cost | X01/X07，校验和逐位一致 |

| 不可声明 | 原因 |
|---|---|
| full Prague / full Osaka | 缺 BLS12-381/P256 组 |
| state-root pass | 未做 MPT，只做 alloc-level |
| production L2 EVM | 无审计/无节点集成 |
| 最快 / 比 revm 强 | 未做同负载同硬件对照 |

---

## 9. 交付物清单

- MoonBit 包：`types`/`crypto`/`rlp`/`state`/`interpreter`/`precompiles`/`host`/`facade`。
- CLI：`reckon statetest`、`reckon run`、`reckon trace`、`reckon bench`。
- 报告：`conformance.json`、`bench.json`、`divergence.json`。
- ADR 台账（第 10 节）。
- API 文档 + 嵌入示例（native / wasm-gc / js）。

---

## 10. 决策点（ADR）

| ADR | 决策 | 备选/理由 |
|---|---|---|
| ADR-1 | 库，不是节点 | 节点会引入 RPC/共识/MPT，稀释三臂证据 |
| ADR-2 | revision：Cancun/Prague（stable）+ Osaka（develop） | stable 实测 `--until=Prague`；Osaka 在 develop |
| ADR-3 | **v1 三臂统一 4×UInt64 limb**；js 只承诺正确性、不承诺性能；BigInt 版仅作测试期第二实现交叉验证，不进任何生产路径 | 双实现会让「三臂一致」退化成「两套实现互相一致」，叙事与 bug 面双输（2026-11-20 修订，原稿为 js 走 BigInt） |
| ADR-4 | Reference 先写、Fast 后优化、diff 为门 | geth `TestInterpreterDiff` 先例 |
| ADR-5 | `PrecompileProvider` 分组可选 | 加密悬崖 10.56%，不能绑死主线 |
| ADR-6 | v1 不做 MPT；只做 alloc-level | `post.state` 已够账户级判分 |
| ADR-7 | EIP-3155 JSONL，字段序/hex 大小写固定 | 三臂逐字节比对的前提 |
| ADR-8 | corpus pin：EEST v5.4.0 / `4f68564` | 报告可复现 |
| ADR-9 | blockchain/主网 replay 延后 P6 | 需要 MPT/归档节点，成本高 |
| ADR-10 | 公开 API pre-1.0，不承诺稳定 | 先让扩展点经真实嵌入方验证 |

---

## 附录 A：已核实的外部事实（2026-11-20）

### A.1 EEST v5.4.0

> 路径相对 `fixtures/eest/`；tar 内路径解包后加 `probe/` 前缀。

- `fixtures/.meta/fixtures.ini`：
  - `command_line_args = ... --until=Prague --fill-static-tests ...`
  - `ref = refs/tags/tests-v5.4.0`
  - `commit = 4f68564f47c7e577ad6cbb570858316f5ff0e7bb`
- `fixtures/.meta/index.json`：
  - `test_count = 176149`
  - `state_test = 44039`
  - forks 列表无 Osaka
- `post.state` 抽样：
  - `fixtures/state_tests/cancun/eip1153_tstore/test_basic_tload_after_store.json`
  - `fixtures/state_tests/prague/eip7702_set_code_tx/test_valid_tx_invalid_chain_id.json`
  - `fixtures/state_tests/static/state_tests/stCreateTest/CreateOOGFromEOARefunds.json`
  - 三者均满足 `pre ⊆ state`，新账户在 `state` 中。

### A.2 oracle

- evmone：`tools/evmone/main.cpp` 的 `test` 子命令；`--state-diff` 在第 177 行。
- geth：`core/vm/interpreter_gen_test.go` 的 `TestInterpreterDiff`；比较 `ret/gas/err/refund/root/logs`。
- EELS：官方 README 明写 `ethereum-spec-evm` 是 t8n/b11r/state-test runner。
- goevmlab：315★；2026-10-04 有推送；`fuzzing/` 含 auth7702/blake/bls12381/bn254/ecrecover/kzg4844/modexp/secp256r1 等生成器族；主入口 `cmd/generic-fuzzer` + `cmd/generic-generator`。

### A.3 MoonBit 生态

- mooncakes 全量 3,875 个模块：0 个 EVM 解释器。
> 以下仅为调研记录，**均不在依赖白名单内**（2026-11-20 依赖边界收紧为 `moonbitlang/*` ∪ `moonbit-community/*`）。

- 相邻包：`CAIMEOX/evmasm`（汇编器，repo 404）、`poteto0/endor`（Ethereum SDK）、`cc06b/mooncry`（含 Keccak-256/P-256）、`moonbitstack/mooncrypt`、`PingGuoMiaoMiao/LunarKeccak256`、`snorfyang/moonupgradeguard`。
- `skmtkytr/ethbit`：MIT，三后端（wasm-gc/native/js）钱包工具包；已有 keccak/RLP/secp256k1/RFC6979/tx 0/1/2/3/ABI/EIP-712/BIP-32/39/JSON-RPC；无 7702；pre-1.0；2026-04-29 后停更。
- EVM-in-language 赛道：Zig 至少 4 个实现；Cryptuon `zig-evm` 宣称 141 opcodes/full set。

### A.4 加密占比（Cancun+Prague state test，35,716 分母）

| 组 | 用例 | 占比 |
|---|---:|---:|
| bn254（eip196/197/198 + ecadd/ecmul/ecpair 族） | 2,432 | 6.81% |
| BLS12-381（EIP-2537） | 982 | 2.75% |
| KZG point evaluation | 356 | 1.00% |
| P-256（EIP-7951） | 13 | 0.04% |
| **并集** | **3,770** | **10.56%** |
| modexp | 992 | 2.78% |
| ecrecover | 238 | 0.67% |
| ripemd160 | 142 | 0.40% |
| blake2f | 234 | 0.66% |

> 口径：按 test id 子串近似；去重后略低。分母 = 35,716（Cancun+Prague），与 §0 一致。

**pre-Cancun 8,323 条的处置（2026-11-20 实测）**：这 8,323 条来自**仅 84 个 fixture 文件**在老 fork（Frontier/Homestead/Byzantium/ConstantinopleFix/Istanbul/Berlin/London/Paris/Shanghai）下的展开，其中 **78 个（92.9%）也出现在现代 fork 里**。因此：

- 它们**不是新增覆盖**，是同一批 fixture 的旧 fork 期望；
- 跑它们需要 revision 表支持 9 个老 fork，成本远大于收益；
- **决定：v1 不纳入门禁**，仅在 P6 可选；`§8` 不宣称 pre-Cancun 覆盖。

### A.5 依赖边界核查（2026-11-20，`moonbitlang/x@0.5.7` 解包实测）

允许范围 = `moonbitlang/*` ∪ `moonbit-community/*`；官方成员个人包与其余第三方**一律不用**。

| 需要 | 官方范围内实况 | 结论 |
|---|---|---|
| keccak256 | `x/crypto` 有 sha1/224/256/384/512、md4/md5、ripemd160、sm3、aes、chacha、hmac、simd —— **无 keccak/sha3** | 自研 |
| sha256（0x02） | `x/crypto/sha256.mbt` | **直接用** |
| ripemd160（0x03） | `x/crypto/ripemd160.mbt` | **直接用** |
| secp256k1 | 无 | 自研 |
| blake2f（0x09） | 无 | 自研（规格简单，约 150–250 行） |
| modexp（0x05） | `core/bigint` 有 | 自研薄封装 |
| bn254（0x06–0x08） | 无 | 自研 |
| BLS12-381（0x0a–0x11） | 无 | 自研 |
| P-256（0x100） | 无 | 自研 |

**由此产生的修正**：B03「复用/自研」→ 自研；B05「vendor ethbit」→ 自研；O03「复用 mooncry」→ 自研；工作量 P0 20–31、P3 14–20（§4.3 已回填）。

---

## 附录 B：复现命令

```bash
# 0) 在仓库根目录执行；fixture 位于 fixtures/eest/
cd fixtures/eest

# 1) 解析 fixtures.ini / index.json
tar -xzf fixtures_stable.tar.gz -C probe fixtures/.meta/fixtures.ini fixtures/.meta/index.json
python -I -c "
import json
d=json.load(open('probe/fixtures/.meta/index.json',encoding='utf-8'))
print(d['test_count'])
print(sum(1 for c in d['test_cases'] if c['format']=='state_test'))
"

# 2) 抽样检查 post.state
tar -xzf fixtures_stable.tar.gz -C probe \
  fixtures/state_tests/cancun/eip1153_tstore/test_basic_tload_after_store.json
python -I -c "
import json
d=json.load(open('probe/fixtures/state_tests/cancun/eip1153_tstore/test_basic_tload_after_store.json',encoding='utf-8'))
for name,t in d.items():
    pre=set(t['pre'])
    for fork,entries in t['post'].items():
        for e in entries:
            print(name, fork, pre <= set(e['state']), sorted(e.keys()))
"
```

---

## 附录 C：待拍板清单

| 编号 | 事项 | 选项 | 建议 |
|---|---|---|---|
| Q1 | js U256 策略 | ~~BigInt 全量 / limb 全量 / 双跑~~ **已定：三臂统一 limb** | 见 ADR-3 修订（2026-11-20） |
| Q2 | BLS12-381 | 做 / 不做 / 延后 | G2 前不做承诺；按组报率 |
| Q3 | bn254 | 做 / 不做 | 与 BLS 同门决策 |
| Q4 | MPT | v1 不做 / 提前 | v1 不做 |
| Q5 | blockchain tests | P6 / 提前 | P6 |
| Q6 | API 稳定承诺 | pre-1.0 / 1.0 | pre-1.0 |
