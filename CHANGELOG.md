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
  - `snapshot` / `revert`（`Snapshot` 字段私有，外部无法伪造）、`accounts`、`diff`；
  - `StateDiff` / `AccountDiff` / `StorageDiff`（字段公开，供 B08 读取）；
    `StateDiff::is_empty` / `length`；错误 `StateError`（重复地址、重复槽、失效快照）。
- 语义口径（测试逐条对应）：
  - **empty account**：nonce/balance/code 全零且无槽 → `exists=false`、不导出、
    不进 diff（EIP-161 口径；何时真正清除归 C09/C12）；
  - **zero slot**：`set_storage(...,0)` 删槽；账户不存在时零写是 no-op（不造账户）；
    导出与 diff 都不含零槽；
  - **original_storage**：相对构造时 base，构造后新建账户原值为 0；
  - **snapshot/revert**：日志只记旧值、逆序撤销，覆盖 balance/nonce/code/槽/创建/删除；
    嵌套 LIFO，回滚会作废该快照及更晚的快照，重复回滚与伪造句柄都是
    `InvalidSnapshot`；base 与 `original_storage` 不受回滚影响；
  - **排序**：`accounts()` / `diff()` 的账户按 `Address` 比较序、槽按 `U256` 比较序
    显式排序，`Map` 迭代序不外泄，输出逐字节可复现；
  - **diff**：创建 `before=None`，删除或写空 `after=None`，仅槽变化仍出现，
    清零槽 `after=None`、新写槽 `before=None`；`from_accounts` 深拷贝（base 与
    current 不共享 storage 表），输入零槽丢弃、empty 账户按不存在处理。
  - `State` 的字段用 `priv` 修饰：`pub struct` 的普通字段在包外**可读**，
    `Map` 一旦可读就能被外部改，故必须显式 `priv`。
- 测试：新增 54 条（`state` 53 + `types` 1），三后端 **166/166**；含 200 步固定种子
  LCG 参考模型对拍（整表深拷贝式快照、LIFO 回滚、每步比对 canonical 导出）。
  变异验证：回滚不清零槽 → 2 条红；日志改正序撤销 → 7 条红；diff 忽略仅槽变化 → 2 条红。

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
