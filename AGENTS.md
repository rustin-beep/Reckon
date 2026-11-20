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
moon test                              # wasm-gc
moon test --target js
moon test --target native
moon fmt && moon info                  # 产物由工具链生成，否则 CI 的 git diff 会红
moon run cmd/main -- --version
cd tools/depcheck && go test ./... && go run . ../../moon.mod
```

CI（[`.github/workflows/ci.yml`](.github/workflows/ci.yml)）顺序相同：依赖闸独立 job →
装工具链 → `check --target all --deny-warn` → `fmt`/`info` 漂移检查 → 三后端测试。

## 4. 工具链

- 当前：`moonc 0.10.21+06da1ed44`、moon driver `0.1.20261104`、moonrun `0.1.20261117`。
- CI pin 在 `MOONBIT_VERSION`，**必须是带构建哈希的完整版本**：CDN 只认
  `binaries/0.10.21+06da1ed44/…` 与 `cores/core-0.10.21+06da1ed44.zip`，裸 `0.10.21` 返回 403。
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

## 6. 本仓 MoonBit 事实（0.10.21）

- `Int` 是 `Int32` 的别名；`Int32::from_int` 不存在，移位直接用 `Int`。
- `derive(...)` 已废弃，用 `#derive(Debug)`；trait 方法要显式
  `pub extend T with Trait::{ … }`，否则 23 条 `[0079]` 警告。
- 跨包构造 enum 必须 `pub(all) enum`；`pub enum` 只读。
- `Bytes[a:]` 得到 `BytesView`，`.to_owned()` 转 `Bytes`。
- `.mbtx` 脚本无法 import 本模块的包；临时调试用模块内可执行包。

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

