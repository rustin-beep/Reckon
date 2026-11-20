# Reference

上游参考项目。第三方源码不 vendor 进本仓库。

| 项目 | URL | 用途 |
|---|---|---|
| evmone | https://github.com/ethereum/evmone | state test runner、`--state-diff`、baseline/advanced 双解释器 |
| geth | https://github.com/ethereum/go-ethereum | `TestInterpreterDiff` 双循环差分；`cmd/evm statetest` |
| revm | https://github.com/bluealloy/revm | 库/框架分层、`Host`/`Inspector`/`PrecompileProvider` |
| execution-specs (EELS) | https://github.com/ethereum/execution-specs | 可执行规范；`ethereum-spec-evm` t8n/b11r/state-test runner |
| execution-spec-tests (EEST) | https://github.com/ethereum/execution-spec-tests | 官方 fixture；v5.4.0 stable |
| goevmlab | https://github.com/holiman/goevmlab | tracediff、generic-fuzzer、语料生成器 |
| ethbit | https://github.com/skmtkytr/ethbit | MoonBit 三后端以太坊工具包（MIT）；keccak/RLP/secp256k1/tx 可参考 |
| mooncry | https://github.com/cc06b/mooncry | MoonBit 密码学原语（含 Keccak-256、P-256） |

## 本地参考树

开发机上另有一份 vendored 上游源码（124 MB，**不入库、不属于本仓库**），放在 Vitro 仓库的
`.tmp_moonbit/probes/evmanatomy/` 下；换机器时按下列 commit 重新克隆即可：

- `ipsilon-evmone-0a50c91`（evmone）
- `bluealloy-revm-61eb0f2`（revm）
- `ethereum-go-ethereum-c299edf`（geth）
- `alloy-rs-ruint-7c34694`（ruint）

需要时直接读该目录；新项目不复制第三方源码。
