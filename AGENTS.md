## 0. 先读什么

1. [`PLAN.md`](PLAN.md)：唯一口径来源——WBS、门、验收、ADR。与其冲突的"优化"先改 PLAN，再改代码。
2. 本文件：工程纪律、命令、已知坑。

## 1. 这个仓库是什么

用 MoonBit 写的可嵌入 EVM 执行核（库 + 薄 CLI），不是节点：不做 RPC / mempool /
consensus / MPT。验收语料是 EEST v5.4.0 的 state test，判据是账户级 `post.state` 比对。

## 2. 布局与依赖边界

| 包 | 职责 | 依赖 |
|---|---|---|
| `types/` | U256（4×UInt64 limb）、Address、Hash32、hex、DecodeError | 无 |
| `crypto/` | keccak256 | types |
| `rlp/` | canonical encode/decode | types |
| `cmd/main/` | `reckon` CLI 骨架 | core/env |
| `tools/depcheck/` | 依赖白名单闸（Go） | 无 |
| `probes/` | 本地研究材料，**不入库**（第三方源码、绝对路径；来源见本地 `probes/README.md`） | 各自独立 module |

规则：依赖只能**向下**（crypto/rlp → types），不得反向；不得跨包读私有字段；
不得为"以后可能有用"加抽象。

## 3. 命令

```bash
moon check --target all --deny-warn   # wasm / wasm-gc / js / native，warning 即失败
moon test --target wasm-gc            # 三后端显式声明；裸 `moon test` 走 preferred_target
moon test --target js                 # （本仓是 native），不能当 wasm-gc 用
moon test --target native
moon fmt && moon info                  # 产物由工具链生成，否则 CI 的 git diff 会红
moon run cmd/main -- --version
cd tools/depcheck && go test ./... && go run . ../../moon.mod
```

CI（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）顺序相同：依赖闸独立 job →
装工具链 → `check --target all --deny-warn` → `fmt`/`info` 漂移检查 → 三后端测试。

## 4. 工具链

- 当前：`moonc 0.10.22+124d61d05`、moon driver `0.1.20261119`、moonrun `0.1.20261119`
  （driver 与 runner 同 commit `738607b`；三者必须来自同一个 `binaries/<version>/` 包）。
- CI pin 在 `MOONBIT_VERSION`，**必须是带构建哈希的完整版本**：CDN 只认
  `binaries/0.10.22+124d61d05/…` 与 `cores/core-0.10.22+124d61d05.*`，裸 `0.10.22` 返回 403。
  **CI 与本地必须同版本**：`moon fmt` 的输出跨版本会漂移，「格式与接口漂移」那一步会红。
- **干净检出必须先 `moon update`**（2026-11-21 定位）：runner 上没有 registry 索引时，
  `moon check` 在依赖解析阶段直接失败——`Failed to resolve registry dependency
  moonbitlang/x … module was not found in the registry`，耗时 0 秒、exit 255，
  看起来像命令本身坏掉。CI 里已把 `moon update` 放在 check 之前。
- **`moon test` 的默认后端由 `moon.mod` 的 `preferred_target` 决定**（本仓 `native`），
  不是 wasm-gc。三后端必须逐条写 `--target`；CI 里名为「测试（wasm-gc）」的步骤
  若只写 `moon test`，实际跑的是 native（2026-11-20 发现并修正）。
- **工具链三个二进制必须同源**（`moon` / `moonc` / `moonrun` 来自同一个
  `binaries/<version>/` 包）。混装时 `moon test --target wasm-gc` 会报
  `invalid test range "\"vitro"`：driver 用 JSON 传 `--test-args`，而版本不匹配的
  moonrun 只认 legacy `file.mbt:0-8/...`。判定：`moon version --all` 三个版本/commit
  不一致即中招（本机 2026-11-20 就是 `moon.exe` 停在 0.1.20261104、moonrun 已是
  0.1.20261117）。修法：从 pin 版本的 zip 里补回 `bin/moon.exe`，旧文件留备份。
- Windows 上 `moon upgrade` 会失败：它用 Windows PowerShell 5.1 跑安装脚本，`PSModulePath`
  从 pwsh 7 继承后会加载不兼容模块，`Expand-Archive` 报 `ExtractToDirectory` 重载错误
  （上游 PR #2594 已修，尚未进入本机版本）。规避：用 pwsh 7 直接跑
  `install/powershell.ps1`。**安装器会先删 `~/.moon/lib` 再解压**，失败即工具链报废；
  修复办法是把 `cores/core-<version>.zip` 解回 `~/.moon/lib` 再 `moon bundle -a`。

## 5. 硬规则

- **依赖白名单**：只允许 `moonbitlang/*` ∪ `moonbit-community/*`。任何第三方包先过
  `tools/depcheck`，否则不许合入（PLAN R11）。
- **不 vendor 第三方源码**：上游代码只做本地参考，登记来源后用 `.gitignore` 排除。
- **`.mbti` 是生成物**：只由 `moon info` 产出，禁止手改。
- **提交**：信息 ≤ 50 行（推荐 ~30），写清"改了什么 / 为什么 / 凭什么信"；
  最终 `commit` / `push` 由用户执行。
- **不写"讨论文档"**：结论进对话或 PLAN/AGENTS，不额外造 md。

## 6. 本仓 MoonBit 事实（0.10.21 / 0.10.22）

- `Int` 是 `Int32` 的别名；`Int32::from_int` 不存在，移位直接用 `Int`。
- `derive(...)` 已废弃，用 `#derive(Debug)`；trait 方法要显式
  `pub extend T with Trait::{ … }`，否则 23 条 `[0079]` 警告。
- 跨包构造 enum 必须 `pub(all) enum`；`pub enum` 只读。
- `Bytes[a:]` 得到 `BytesView`，`.to_owned()` 转 `Bytes`。
- `.mbtx` 脚本无法 import 本模块的包；临时调试用模块内可执行包。
- **`pub struct` 的普通字段在包外可读**（0.10.22 探针实测）：`pub struct` 是「可读
  不可构造」，只有 `pub(all) struct` 才能跨包构造。所以内部 `Map`/`Array` 字段必须
  写成 `priv`（`priv base : Map[…]`、`priv mut next_id : Int32`），否则外部能拿到
  可变容器去改内部状态——`state/` 的 `State` 就是这么封的。
- **`priv struct X` 不能当字段类型**：会报 `[4046] A public definition cannot depend
  on private type`。包内类型用**默认可见性**（不写 `priv`），`moon info` 里表现为
  只列类型名的 `type X`（不导出构造子）；反过来，不写 `priv` 又不出现在公开签名里
  会吃 `missing_priv` 警告——出现在 `pub struct` 的字段里就算「出现过」，正好抵消。
- struct 的 `mut` 字段是**引用语义**：`map.get(k)` 拿到对象后改字段会写回 map。
  需要跨后端确定性时别依赖它，显式 `get` → 改 → `set` 写回（`state/` 全程这么做）。
- 带标签字段的 enum 构造子，`match` 里**必须用带标签模式**（`Variant(a~, b~)`）；
  写成位置模式报 `requires 0 positional arguments`，还会连带把字段判成 unused_field。
- 构造时给带标签字段赋值是 `field=value`（`field~=value` 非法）；`{ id, }` 要留逗号，
  否则报 `ambiguous_block`。
- `for (k, v) in map.iter()` 才是解构；`for k, v in …` 是「下标 + 元素」。
- `moon fmt` 会把源码里的 `Int` 改写成 `Int32`（`Int` 是别名），手写 `Int` 每次 fmt
  都漂移、CI 的 `git diff --exit-code` 会红。
- `moon.pkg` 里一旦有 `import { … } for "test"`，未加注解的那组**只对非 test 目标
  生效**；test 目标要把那组再写一遍（临时探针时踩到过）。
- **`String::compare` 是「长度优先」，不是字典序**（0.10.22 实测：`"ab".compare("b") == 1`、
  `"a10".compare("a9") == 1`、`["b","ab","aa"].sort()` → `b, aa, ab`）。凡是要给人看的
  排序（报告的文件序、分片切法）都别用它——`Array[String]::sort()` 用的就是它——
  显式逐字符比（`statetest/corpus.mbt` 的 `compare_paths`）。
- **`StringView::to_string()` 在 executable 包里会触发编译器 ICE**（段错误、无诊断；
  0.10.22 实测，`path[2:].to_string()` 即中招）。`StringView → String` 一律用
  `to_owned()`；`length()` / `[i]` / 切片本身没问题。
- **blackbox test 里出现 `Map[String, @json.Json]` 会 ICE**：只要该类型进签名
  （`as_object()`、`Json::value()` 都会带出它），moonc 0.10.22 段错误且不报诊断。
  生产代码（库内）用 `Map` 构造 JSON 正常，只有 `*_test.mbt` 受限——测试改用
  `@json.valid` + `parse → stringify` 往返 + 文本断言。
- 测试里带断言的 helper 要写 `-> Unit raise`：`assert_eq` / `assert_true` 本身是
  raising（`*_test.mbt` 的 `test` 块能接，普通 helper 不能）。

## 7. 工作流

读 PLAN → 认领一个 WBS 项 → 先写测试（含边界/反例）→ 实现 →
`moon fmt` / `moon info` → `moon check --target all` → 双后端 `moon test` →
必要时跑 `tools/depcheck` → 报告里给数字（通过数、警告数、复现命令），不给"应该没问题"。

## 8.纪律（下面这部分由用户亲手输入 未经允许禁止修改）
- 脚本的使用一律为`go`，少数情况按需选择。判断依据：一次性脚本或者探针允许使用非`go`语言如py,js等，如果需要入库，请写`go`。
- 未经允许禁止提交，推送横需显示给出指令才可以。github的读取需通过sluice进行读取，具体指令请键入sluice help进行获取。
- 思考和回答问题以及编码的注释请使用中文，禁止其他的语言。
- 生成物禁止手改，一律通过脚本进行重新生成。
- 废弃脚本和工具请放在下`/tmp`不入库。
- 未完成的工作部分或者缺失完成部分禁止静默，必须显式向用户进行说明。
- 要求进行工作或者回答用户问题的时候，探针和脚本先行，禁止脑测或者只是搜索资料进行回答。

