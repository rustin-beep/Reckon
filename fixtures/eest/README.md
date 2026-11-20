# EEST fixtures

本目录存放 [execution-spec-tests](https://github.com/ethereum/execution-spec-tests)
语料。**语料不进版本库**（257 MB tarball，可按 pin 复现），进库的只有这份说明。

## Pin

| 项 | 值 |
|---|---|
| release | `tests-v5.4.0` |
| commit | `4f68564f47c7e577ad6cbb570858316f5ff0e7bb` |
| 构建范围 | `--until=Prague`（stable 不含 Osaka） |
| state test | 44,039（Cancun 16,847 + Prague 18,869） |

## 获取

```bash
cd fixtures/eest
curl -fL -o fixtures_stable.tar.gz \
  https://github.com/ethereum/execution-spec-tests/releases/download/tests-v5.4.0/fixtures_stable.tar.gz

tar -xzf fixtures_stable.tar.gz -C probe fixtures/.meta/fixtures.ini fixtures/.meta/index.json
tar -tzf fixtures_stable.tar.gz > listing.txt
```

## 本地布局（全部被 .gitignore 忽略）

| 路径 | 内容 |
|---|---|
| `fixtures_stable.tar.gz` | release asset，257,344,946 B |
| `probe/fixtures/.meta/fixtures.ini` | `--until=Prague`、`ref=refs/tags/tests-v5.4.0` |
| `probe/fixtures/.meta/index.json` | `test_count=176149`、`state_test=44039` |
| `listing.txt` | tar 条目清单 |

复现命令与抽样校验见 [`../../PLAN.md`](../../PLAN.md) 附录 B。
