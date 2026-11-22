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
- `statetest`：EEST state test 的强类型模型与**严格** JSON loader（`config` 只取
  `chainid`，其余四段 env/pre/post/transaction 全解析）。未知字段忽略，必需字段缺失、
  类型不符、定宽字段长度错、十六进制非法、数量字段溢出 64 位、`indexes` 非整数全部
  按 `FixtureError` 分类并带 JSON 路径；重复键与超过 64 层的嵌套由 `@json.parse` 拒绝。
  account `storage` 按 EEST 实际格式（**数量**，如 `"0x01"`/`"0xff"`）解析成 `U256`，
  不是 32 字节哈希——这一点与任务书初稿的描述不同，以抽样实测为准。
- `statetest`：`txbytes` 解码（legacy 含 EIP-155、type 1/2/3），输出交易字段、
  `tx hash`、`signing hash`（pre-155 6 字段 / EIP-155 追加 `chainId,0,0` / typed
  `type||rlp(unsigned)`）、`chainId`、`yParity`；`r`/`s` 原样保存不在这里做范围判定。
  type 4（EIP-7702）识别但只返回 `UnsupportedType(4)`，留给 P02。
- `statetest`：`txbytes` 重签校验——`secretKey → 地址`、`Signature + recover → 地址`
  都必须等于 fixture 的 `sender`，再用 `secp_sign` 的 low-s 签名重编码并与原始字节
  **逐字节**比对（不一致时报第一个差异字节的 offset 与两侧 hex 片段）。同时核对
  `indexes` 选中的 JSON 向量与解码字段（nonce/fees/gasLimit/value/data/to/accessList/
  maxFeePerBlobGas/blobVersionedHashes/chainId）。
- `cmd/main`：`reckon statetest <fixture> [--fork <name>]`（默认 Cancun），输出
  `cases` / `tx_types` / `txbytes` / `resign` / `sender` / `errors` 计数与分类错误行
  （最多 50 行）；退出码 0 = 干净、1 = 有 mismatch 或解码错误或 unsupported、
  2 = 用法或 IO 错误。文件读取只在 `cmd/main`，`statetest` 库不 import `fs`。
- `cmd/main`：`reckon` CLI 骨架，`--version` / `--help` 可用；`statetest` 已可用，
  `run` / `trace` / `bench` 仍是占位。
- `tools/depcheck`：Go 实现的依赖白名单闸（PLAN R11），带表驱动单元测试。
- CI：官方安装脚本 + 版本钉（`0.10.21+06da1ed44`）；依赖闸独立 job；
  `moon fmt` / `moon info` 漂移检查；wasm-gc / js / native 三后端测试；
  `moon check --deny-warn`，warning 即失败。

### 新增（B07：state model v0）

- `types`：`U256` 的 `Hash` 实现（四个 limb 依次 `combine_uint64`）+ 显式
  `pub extend U256 with Hash::{hash, hash_combine}`，供 `Map[U256, U256]` 做键；
  `types/u256_test.mbt` 加 Map 键测试（0/1/max/跨 limb 命中、相邻键不串、覆盖写与删除）。
- `state`：内存状态模型（只依赖 `types`），公开 API：
  - 值类型 `AccountInfo`（`empty`/`is_empty`/`same`）、`AccountEntry`（`same`）；
  - `State::new` / `from_accounts` / `basic` / `exists` / `code` / `storage` /
    `original_storage`；
  - `set_balance` / `set_nonce` / `set_code` / `set_storage` / `create_account` /
    `destroy_account`；
  - `snapshot` / `revert`（`Snapshot` 字段私有 + id 进程内唯一，外部无法伪造，
    且句柄**只对产生它的 `State` 有效**）、`accounts`、`diff`；
  - `StateDiff` / `AccountDiff` / `StorageDiff`（字段公开，供 B08 读取）；
    `StateDiff::is_empty` / `length`；错误 `StateError`（重复地址、重复槽、失效快照）。
- 语义口径（测试逐条对应）：
  - **empty account**：nonce/balance/code 全零且无槽 → `exists=false`、不导出、
    不进 diff（EIP-161 口径；何时真正清除归 C09/C12）；
  - **zero slot**：`set_storage(...,0)` 删槽；账户不存在时零写是 no-op（不造账户）；
    导出与 diff 都不含零槽；
  - **original_storage**：相对构造时 base，构造后新建账户原值为 0；
  - **snapshot/revert**：日志只记旧值、逆序撤销，覆盖 balance/nonce/code/槽/创建/删除；
    嵌套 LIFO，回滚会作废该快照及更晚的快照，重复回滚、伪造句柄与**异实例句柄**
    都是 `InvalidSnapshot`；base 与 `original_storage` 不受回滚影响；
  - **排序**：`accounts()` / `diff()` 的账户按 `Address` 比较序、槽按 `U256` 比较序
    显式排序，`Map` 迭代序不外泄，输出逐字节可复现；
  - **diff**：创建 `before=None`，删除或写空 `after=None`，仅槽变化仍出现，
    清零槽 `after=None`、新写槽 `before=None`；`from_accounts` 深拷贝（base 与
    current 不共享 storage 表），输入零槽丢弃、empty 账户按不存在处理。
  - `State` 的字段用 `priv` 修饰：`pub struct` 的普通字段在包外**可读**，
    `Map` 一旦可读就能被外部改，故必须显式 `priv`。
- 测试：新增 57 条（`state` 56 + `types` 1），三后端 **169/169**；含 200 步固定种子
  LCG 参考模型对拍（整表深拷贝式快照、LIFO 回滚、每步比对 canonical 导出）。
  变异验证：回滚不清零槽 → 2 条红；日志改正序撤销 → 7 条红；diff 忽略仅槽变化 → 2 条红。

### 新增（B08：harness v0）

- `statetest` 新增依赖 `vitro/reckon/state`（方向 `statetest → state → types`，不反向）；
  `statetest/harness.mbt` 落地 harness v0：
  - `run_harness(fixtures, fork, execute : (Case, @state.State) -> Unit) -> HarnessSummary`
    ——每个 case 从 `fixture.pre` 新建一个 `State`（不复用），调用显式执行回调，再与
    `post[fork][i].state` 比对。执行是**注入的回调**，没有为 v0 造只有一个实现的 trait。
  - `alloc_entries`（`Alloc` → `Array[AccountEntry]`）与 `canonical_accounts`
    （`Alloc` → `State::from_accounts(..).accounts()`）：expected 与 actual 走同一条
    canonical 路径，empty 账户、零槽、排序规则由 `state` 单方面给出，比对器不自带第二套。
  - `compare_accounts(expected, actual) -> CompareReport`：8 类分类
    （`missing_account` / `extra_account` / `nonce` / `balance` / `code` /
    `missing_slot` / `extra_slot` / `slot_value`），两侧先各自排序再归并，输入顺序无关；
    超长 code 摘要截断到 32 字节并标注总长，不影响计数。
  - `HarnessSummary`：case 级 `pass` / `fail` / `skipped_expected_invalid` /
    `skipped_unsupported` / `internal_errors`，字段/槽级 8 个 mismatch 计数，
    `state_diff=accounts/slots`（所有执行过的 case 的 `State::diff()` 之和），
    `details`（上限 50 条）+ `details_omitted`（超限条数，计数仍完整）。
  - skip 口径：`expectException` 非空 → `skipped_expected_invalid`（不执行、不比对，
    也与「pre == post」无关）；`tx_type == Type4`（EIP-7702）→ `skipped_unsupported`。
  - `exit_code(tx, harness, strict) -> Int32` 纯函数：tx 流水线不干净 / `internal_errors > 0`
    → 1；`--strict` 时再要求 `harness.fail == 0`；**默认不因 state fail 变红**（P0 是 stub）。
- `cmd/main`：`reckon statetest <fixture> [--fork <name>] [--strict]` 先跑 B06 tx 流水线，
  再跑 harness；新增输出行 `execution=stub (no interpreter; G0 harness only)`、
  `state_root=not_checked`、`logs=not_checked`、`harness=cases/pass/fail/skip_expected/
  skip_unsupported/internal_errors`、`state_diff=accounts/slots`、
  `post_diff=missing_accounts/extra_accounts/nonce/balance/code/missing_slots/extra_slots/
  slot_values`，以及 `case=… fork=… indexes=… class=…` 明细（最多 50 行，其余只报条数）。
  `--strict` 进 usage。没有 `--inject-post` 之类的反填开关：生产路径读不到 `post.state`。
- 测试：新增 22 条（`statetest/harness_test.mbt`），三后端 **191/191**。覆盖
  canonical 归一（empty 账户/零槽/排序）、重复地址报错、8 类 mismatch 的正负例、
  输入顺序无关、排序不落在调用方数组上（`Array` 引用语义）、超长 code 截断、no-op executor 的 fail 分类、**fake executor 写 expected
  → pass**、少写一个字段只剩该类 mismatch、两种 skip 分支、两次运行逐字段一致、
  单 case 展开失败不影响同批、明细 50 条上限、以及 `exit_code` 的四种组合。
- 真实 fixture（`/tmp` 解包，不入库）：
  - `cancun/eip1153_tstore/test_basic_tload_after_store.json`：cases=1 pass=0 fail=1
    skip=0 internal=0；`post_diff` = missing_accounts:1 / nonce:1 / balance:1 /
    missing_slots:1 / extra_slots:1；默认 exit 0，`--strict` exit 1。
  - `cancun/eip4844_blobs/test_invalid_tx_blob_count.json`：cases=2，两个 case 全部
    `skip_expected`（fixture 声明 `expectException`），`fail=0`、`internal=0`、exit 0。
  - `static/state_tests/stCreateTest/CreateOOGFromEOARefunds.json`：文件含 48 个 fixture
    （24 个 `fork_Cancun` + 24 个 `fork_Prague`），`--fork Cancun` 下是 **24 个 case**
    （Prague 那半边不贡献 Cancun entry），全部跑完不崩：fail=24、internal=0、
    `post_diff` = missing_accounts:10 / nonce:24 / balance:24 / extra_slots:1，
    明细 50 条 + 9 条省略；同一命令两次输出逐字节相同。
  - 口径：真实 family 上 `execution=stub`，`pass` 为 0 是预期结果（执行未实现），
    不得读成实现缺陷；G0 只判 harness 通路，执行正确性与通过率归 G1。

### 新增（B09：corpus/report）

- `statetest/corpus.mbt`：corpus 层的纯计算（不碰文件系统、不读墙钟）：
  - `shard_pick(paths, shard, shards)`：按**字典序**排序后取 `i % shards == shard`，
    同一 `i/n` 在任何机器上切出同一批文件。排序**不用** `String::compare`——它在
    0.10.22 是长度优先（`"ab".compare("b") == 1`），会把 `static/z.json` 排到
    `cancun/...` 前面；改用显式逐字符比较 `compare_paths`。
  - `FileReport::of` / `totals_of` / `CorpusTotals::add`：每文件与合计的计数
    （cases / pass / fail / skip_expected / skip_unsupported / internal_errors /
    tx_errors / resign_mismatches / unsupported / txbytes_present / txbytes_missing /
    expected_invalid）。
  - `CorpusTotals::exit_code(strict)`：与单文件 `exit_code` 同一套判据（tx 不干净 /
    internal / `strict` 下的 fail），并有等价性单测钉住，两套判据不许打架。
  - `report_json(fork, files)`：JSON 报告骨架——`corpus`（tag `tests-v5.4.0` /
    commit `4f68564` / format `state_test`）、`fork`、`executor`（stub 自述）、
    `checks`（`execution=not_run` / `state_root=not_checked` / `logs=not_checked`）、
    每文件计数、`totals`。键序固定、整数不带小数点、同一输入逐字节可复现。
- `cmd/main`：`reckon statetest <fixture-or-dir> [--fork] [--strict] [--shard <i>/<n>]
  [--report <path>]`：
  - 参数是目录时递归收集 `*.json`（排序 + 分片），语料模式输出
    `files/fork/shard` 头 + 每文件一行 `file=… cases:… pass:… fail:…` + `totals=…`
    + `report=…`；参数是单文件时保持 B08 的详细输出（明细最多 50 行）。
    语料模式**只出计数**：全语料的 mismatch 行会淹掉输出，定位靠文件行 + 报告，
    再对单文件复跑取明细。
  - 空目录（分片前就没有 `*.json`）→ exit 2；坏 `--shard`（非 `i/n`、`i >= n`）→ exit 2；
    分片后为空 → `files:0` + exit 0（合法结果，不当作错误）。
  - 退出码统一走 `CorpusTotals::exit_code`，`cmd/main` 里不再散落条件。
- 测试：新增 13 条（`statetest/corpus_test.mbt`），三后端 **204/204**。覆盖分片
  不重不漏 / 越界为空 / 不改入参、**字典序而非长度优先序**（防回归的那颗钉子）、
  合计逐项相加、`FileReport` 与两侧 `cases` 一致、合计版退出码与单文件 `exit_code`
  等价（clean / tx 不干净 / internal / unsupported / resign / 仅 fail 六种组合）、
  报告是合法 JSON 且是 `stringify(indent=2)` 的不动点、转义可逆、空列表全零。
  JSON 断言不用 `Map[String, @json.Json]`：该类型进 blackbox test 签名会让
  moonc 0.10.22 段错误（已记进 AGENTS）。
- 实测（`/tmp` 解包，不入库）：
  - `--fork Cancun` 扫 3 个文件：`totals=files:3 cases:27 pass:0 fail:25 skip_expected:2
    internal_errors:0`；`--report` 产物经独立 `python -c json.load` 复核合法。
  - `--shard 0/2` → `{eip1153_tstore, stCreateTest}`（index 0,2），`--shard 1/2` →
    `{eip4844_blobs}`（index 1），两片不重不漏。
  - 同参数两次运行 stdout 与报告逐字节相同；`--strict` → exit 1；空目录 / 坏分片 → exit 2。

### 修复（B09 审阅：语料通路）

真实语料（EEST stable 全树 2,681 文件）实测出来的四类问题，按「先能跑，再能读」的顺序修。

- **目录模式不再整批中止**（P1）：任一文件 parse 失败或没有目标 fork，原先直接
  `exit 2`，全语料一条 `totals` 都出不来。现在降级为**逐文件跳过**：`bad_files`
  计数（`no_fork` = 文档没有目标 fork，`unparsable` = 连模型都读不出来），打一行
  `bad=<kind> file=<rel> <detail>` 诊断，继续扫描；报告里每个跳过的文件都有
  `"bad"` 与 `"detail"`。默认退出码不受 `bad_files` 影响（老 fork 的 fixture 属语料
  结构），`--strict` 下 `bad_files > 0` 判红（证据要完整）。IO 真失败仍 `exit 2`，
  并打印 `incomplete=1`——已输出的 `file=` 行不完整，不能当成一次完整扫描。
- **`currentBaseFee` 缺失补零**（P1）：与 `currentRandom` / `currentExcessBlobGas`
  同口径（London 之前没有 baseFee）。实测 58 个文件**只缺这一个字段**、里面装着
  **1,508 个 Cancun case**（分母 16,847 的 8.95%）。修后全语料 Cancun `cases`
  从 15,339 变成 **16,847**，正好是 PLAN §0 的分母；`unparsable` 清零。
  给了坏值仍然报 `HexInvalid`，不吞解析错误（有测试）。
- **skip 优先级两条流水线统一**（P2）：`run.mbt` 原先先判 `UnsupportedType` 再看
  `expectException`，与 harness 侧相反。后果是同一 case 在 `unsupported` 与
  `skip_expected` 两个桶各记一次（`totals` 的 case 级相加 15,341 > cases 15,339），
  且 2 个 `TYPE_4_TX_PRE_FORK` case 把全语料 `unsupported > 0` 打进 exit 1。
  现在 tx 侧也先看 `expectException`，命中即记 `expected_invalid`（明细保留
  `class=unsupported`）；报告里该列改名 `tx_unsupported`，与 harness 侧的
  `skip_unsupported` 明确区分维度。复验：`test_set_code_type_tx_pre_fork.json`
  由 `unsupported:2 + skip_expected:2 + exit 1` 变为 `tx_unsupported:0 +
  skip_expected:2 + exit 0`。
- **报告补齐 G1 归因维度**（P2）：`FileReport` / `CorpusTotals` / `report_json`
  搬上 8 类 mismatch 计数（`missing_accounts` … `slot_value_mismatches`），
  文本输出加一行 `mismatch=`；报告顶层加 `shard {index, count}`、`strict`、
  `corpus.build = stable`——1/4 分片的报告与全量报告不再长得一样。
- **输入校验与文案**（P3）：`parse_digits` 加溢出检查（`--shard 4294967297/4`
  原先静默回绕成 `1/4`，现在 `exit 2`）；单文件参数配 `--shard` 直接报用法错误（原先
  静默忽略）；`--report` 不许落在扫描树内或与被测文件同路径（先读后写，会覆盖语料、
  也会被下一次扫描当成 fixture）；`run`/`trace`/`bench` 的占位提示指向
  `P1 C01-C13 / C15 / X01`（原先错指 P0 B07-B08）；删掉 `corpus.mbt` 里删段残留的
  空分隔注释。
- 测试：新增 7 条（`baseFee` 缺失/坏值、type 4 + `expectException` 的三条分桶断言、
  `bad_files` 的合计与 `--strict` 行为、报告里的 8 类计数与 `bad` 字段），三后端 **211/211**；`FileReport` 的 8 类
  计数、`bad_files` 拆分、报告新字段都有断言。
- 实测（全树 `--fork Cancun`，2,681 文件）：`totals=files:2681 bad_files:110
  no_fork:110 unparsable:0 cases:16847 pass:0 fail:16283 skip_expected:564
  internal_errors:0 tx_errors:0 resign_mismatch:0 tx_unsupported:0
  txbytes_present:16847`；`mismatch=missing_accounts:13490 extra_accounts:30
  nonce:17059 balance:20991 code:1 missing_slots:20731 extra_slots:4604
  slot_values:4406`；debug 构建耗时 4 分 10 秒。`--shard i/4` 四片并集 = 全集、
  cases 逐片相加 = 16,847、无重复。

### 变更（CI：四后端与多端一致性）

- **CI 矩阵从单 OS 扩到 `ubuntu-latest` + `macos-latest`**（`fail-fast: false`）。
  macOS 走同一个官方 `unix.sh` 与同一套命令，只是换 clang/libc。
- **补上 `moon test --target wasm`**：原先只跑 wasm-gc / js / native，漏了线性内存
  这条代码生成路径。本机实测 211/211 通过，CI 直接接上。
- **四后端测试计数一致性**：每个后端的 `Total tests:` 抄到文件再 `cmp`，防止
  「某个后端跑了 0 条却 exit 0」这种静默（`set -o pipefail` 保证 `tee` 不吞退出码）。
- **多端报告一致性**（这条是「多端对比」的落地）：新增合成 fixture
  `statetest/testdata/one_case.json`（2 个 case：一条正常比对、一条 `expectException`
  走 skip），四个后端各跑一遍 `reckon statetest … --report`，比对
  ① JSON 报告**逐字节**、② stdout **去 CR 后逐字节**。
  为什么不直接比 stdout：本机 od 实测 native 在 Windows 上输出 `\r\n`、js/wasm 输出
  `\n`；而报告经 `write_string_to_file` 落盘不做行尾转换，是真正可逐字节比的产物。
  本机四臂实测：报告与（去 CR 后的）stdout 全部逐字节一致。
- **修复：`@env.args()` 在 js 上多一层脚本路径**——native/wasm 是 `[程序, 子命令, …]`，
  js 是 `[运行时, 脚本, 子命令, …]`（Node 的 `process.argv` 原样）。原先
  `moon run cmd/main --target js -- --version` 会把 `main.js` 当成子命令报
  `unknown command '…/main.js'`。现在 `first_arg_index` 按「第二项是否 `.js`」跳一格，
  js 上 `--version` / `statetest` 都正常。
- **Windows 仍未接线**，三条硬理由（不是遗漏）：① 官方安装脚本在 Windows 上走
  `install/powershell.ps1`，版本钉的传参与 `unix.sh` 的 `-s <version>` 不同，未验过；
  ② `native` 目标需要 `cl.exe` 在 PATH，`windows-latest` 默认没有 VS 开发者环境；
  ③ `moon fmt` 的 `git diff --exit-code` 会碰上本仓既有的 CRLF/LF 债（HEAD 里已有
  CRLF blob）。先在真机把这三条验通再并入主门禁，见 `AGENTS.md`「工具链」。
- 测试：四后端 **211/211**；`check --target all --deny-warn` 0 error / 0 warning；
  depcheck ok。CI 的全部命令（除 macOS/Windows 专属部分）都在本机按同一顺序跑过。



### 修复（B07 审阅）

- **`Snapshot` 不绑定 `State` 实例，跨实例混用会静默损坏状态**（P2）：句柄只存
  每实例自增的 id，`revert` 只在本实例的快照栈里按 id 查找、不校验归属；两个
  `State` 都从 0 起发号，于是 A 的句柄能在 B 上撞到同 id 的活快照。探针实测三条
  静默失败路径：① 命中后回滚错误数据（B 的余额被 A 的快照点覆盖）；② 连带把
  B 自己的句柄一起弹掉；③ 外来句柄的 `journal_len` 大于 B 的日志长度时既不报错
  也不回滚，只静默毁掉 B 的快照栈。原「`Snapshot` 字段私有，外部无法伪造」的
  说法过强——私有只防伪造，不防混用。
  修法：id 改由包内全局分配器发号（`UInt64`，进程内唯一），`State` 删掉 `next_id`；
  `revert` 逻辑不动，外来句柄在本实例栈里必然找不到，直接走 `InvalidSnapshot`。
  没有采用「owner token + `physical_equal`」：那会把正确性押在「同值结构体字面量
  不共享」这一实现细节上（虽经三后端探针验证当前成立），不如整数 id 稳。
  回归测试 3 条（异实例、深句柄、两实例合法句柄互不干扰）：改前 2 条红、改后
  全绿；白盒断言从「`next_id` 等于 0/1/3」改为「句柄 id 与栈内 mark 一致」「同实例
  id 严格递增」。

### 修复（B06 审阅）

- **`expectException` 的豁免口径统一**（P2）：此前只有「签名不可恢复」这一条分支
  会把 case 归入 `expected_invalid`，decode 失败、resign 不一致、字段不符仍然计
  `error_count`，于是 invalid fixture 一多，CLI 退出码恒为 1、`is_clean` 失去判据。
  现在 `has_expectation` 在 `run_case` 开头取一次，decode / fields / recover / resign
  四类失败在 fixture 声明异常时一律计入新的 `expected_invalid` 与 `expected` 明细
  （保留原 class 标签），不再动 `error_count` 与 `resign_mismatch`。`sender` 不一致
  不豁免——那是 fixture 自身矛盾（`secretKey` 推不出 `sender`），与「这笔交易该被
  拒绝」无关。探针复验：high-s + `expectException` 由 `errors=2 / exit 1` 变为
  `expected=1 / errors=0 / exit 0`；legacy `v=29` + `expectException` 同理由
  `errors=1` 变 `exit 0`；同一份坏字节去掉 `expectException` 仍是 `exit 1`。
- **删掉 `tx.chainId == config.chainid` 这条断言**（P3）：EEST 的 `transaction` 没有
  `chainId` 字段，这不是「JSON 向量 vs 解码字段」的核对，而是「交易是否属于本链」的
  consensus 判定（C12）。`test_valid_tx_invalid_chain_id` 这类 fixture 刻意用别的
  chainId 签名且交易合法，放在 B06 会误报。
- **单个 case 展开失败不再中止整批**（P3）：`indexes` 越界、`accessLists` 条数不符
  原先直接冒到 `run_document` 让 CLI `exit 2`，与「单个 case 失败落 errors」的口径
  矛盾。现在 `expand_case` 的失败被收进 `class=expand` 错误行，`cases` 仍按 entry 数
  计数，同批其余 case 继续跑。
- **RLP 整数拒绝单字节 `0x00`**（P3）：原条件 `length > 1 && b[0] == 0` 放过了
  「零编码成单字节 0x00」，geth 的 `ErrCanonInt` 会拒。叠加 `encode_with` 保留原始
  `v`/`yParity` 条目，一个把 `yParity` 编成 `0x00` 的 typed tx 能「逐字节一致」通过，
  属假阴性。现改为 `length > 0 && b[0] == 0`，并补一条以 `nonce` 为载体的测试。
- **`env` 的 `currentRandom` / `currentExcessBlobGas` 改为可选**（P3）：两者分别是
  merge 与 Cancun 才引入的字段，pre-merge fixture 没有；缺失时补零值而不是让整份
  文档 parse 失败（B09 扫全 corpus 会碰到）。其余六个 env 字段仍必需。
- `ResignOutcome::Mismatch` 的 `expected`/`actual` 改名为 `reencoded`/`original`
  （原先「expected 其实是重算值」是反读）；同时删掉从未被构造的
  `ResignOutcome::Skipped` / `ExpectedInvalid` 两个变体——「有没有 txbytes」由
  `run_case` 提前分流，「预期无效」上移到 `Summary`。

### 修复（CI）

- **CI 从 run 3 起连续红，根因是干净检出没有 registry 索引**：`moon check` 在依赖
  解析阶段直接失败——`Failed to resolve registry dependency moonbitlang/x … module
  was not found in the registry`，耗时 0 秒、exit 255，看起来像命令本身坏掉。
  用 pin 版本的二进制在干净检出上复现：加一步 `moon update` 即恢复。CI 已在 check
  之前插入该步骤。
- 工具链 pin 从 `0.10.21+06da1ed44` 升到 `0.10.22+124d61d05`（driver/runner
  `0.1.20261119`）。`moon fmt` 的输出跨版本会漂移，CI 与本地必须同版本，否则
  「格式与接口漂移」那一步会拿两个版本互相打架。

### 修复（B05 审阅）

- `secp_verify` 的两条 `false` 分支此前零覆盖（把返回值改成 `true` 后测试仍全绿）：
  补 4 组负例——篡改 `s`、错 digest、错公钥、以及构造 `Q = -G` 且 `z == r` 使
  `u1G + u2Q = O` 的边界。两组变异（恒 `true` / 无穷远分支返回 `true`）现在都会红。
- 错误变体口径统一：删掉只为「坐标越界」存在的 `InvalidFieldElement`，公钥坐标解析
  越界一律 `InvalidPublicKey`；新增 `InvalidSignatureLength`，`Signature::from_bytes`
  长度错不再报 `InvalidScalar`。测试改为断言具体变体，不再「抛了就算」。
- 随机对拍采样改为全 256 位：去掉「最高位清零」的偏置（原实现把 `[2^255, p)` 整段
  排除在随机覆盖外），按 p / n 各自归约一次得到 canonical 值。
- 命令口径更正：`moon test` 不带 `--target` 时走 `preferred_target = native`，
  不是 wasm-gc；CI 的「测试（wasm-gc）」步骤原先只写 `moon test`，实际跑的是 native，
  现已显式 `--target wasm-gc`（用 pin 版本的官方包本地复现：61/61 通过）。
  本机此前 `--target wasm-gc` 失败是 `moon.exe` 停在 0.1.20261104、moonrun 已是
  0.1.20261117 的混装，已从 pin 包补回同源 driver。

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
- 三后端 **112/112**：`moon test --target wasm-gc` / `--target js` / `--target native`
  全部直接跑。原 61 条无回归，B06 累计新增 51 条（首轮 44 + 审阅修复 7）。
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
- B06 真实 fixture（`--fork Cancun`，全部 0 error / 0 mismatch / 0 sender mismatch）：
  `eip1153_tstore/test_basic_tload_after_store.json` 1 case（legacy）、
  `eip4844_blobs/test_blobhash_opcode_contexts_tx_types.json` 3 case（legacy/1/2）、
  `eip4844_blobs/test_invalid_tx_blob_count.json` 2 case（type3，带 `expectException`）、
  `eip4844_blobs/test_blob_gas_subtraction_tx.json` 128 case（type3，非空 accessList）、
  `static/state_tests/stCreateTest/CreateOOGFromEOARefunds.json` 24 case（legacy，
  `to=""` 创建）；合计 158 case。
- B06 测试：4 组真实 `txbytes`（legacy/1/2/3）的 `tx hash`、
  `signing hash`、`chainId`、`yParity`、`r`、`s` 全部由独立 Python oracle
  （pycryptodome keccak + 手写 RLP + 手写 RFC 6979）复算后写死并逐条断言；
  envelope/截断/尾随/字段数/非规范整数/`to` 长度/blob hash 长度/legacy `v` 各 1 组反例；
  loader 12 类错误各断言具体变体与路径；300 组 LCG 随机字节喂 `decode_tx`、
  100 组随机非 JSON 字符串喂 loader，只允许 Ok/Err（不 abort）。
