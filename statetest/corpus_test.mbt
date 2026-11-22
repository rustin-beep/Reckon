// corpus 层测试：分片、合计、退出码等价性、JSON 报告骨架。
//
// 报告是证据链的一环，所以这里不只断言「字段在」，还断言：
//   - 报告是**合法 JSON**，且能 `parse → stringify(indent=2)` **逐字节还原**
//     （既证明语法合法，也证明格式稳定、转义可逆）；
//   - 键值与整数形态按渲染文本钉住（`"cases": 3` 而不是 `3.0`）；
//   - 同一输入两次 `report_json` 逐字节一致；
//   - 合计版退出码与单文件 `exit_code` 逐一等价（两套判据不许打架）。
//
// 不在测试里用 `Map[String, @json.Json]`：本机 moonc 0.10.22 在 blackbox test 包里
// 只要把该类型写进签名（`as_object()` / `Json::value()`）就段错误、且不给诊断。
// 生产代码（`corpus.mbt`）用 Map 构造 JSON 没有问题，只有测试侧受限，故改用
// 「往返 + 文本断言」。

///|
fn assert_paths(actual : Array[String], expected : Array[String]) -> Unit raise {
  assert_eq(actual.length(), expected.length())
  for i in 0..<expected.length() {
    assert_eq(actual[i], expected[i])
  }
}

///|
fn row_of(
  path : String,
  cases : Int32,
  pass : Int32,
  fail : Int32,
) -> @statetest.FileReport {
  {
    path,
    cases,
    tx_errors: 0,
    resign_mismatches: 0,
    unsupported: 0,
    txbytes_present: cases,
    txbytes_missing: 0,
    expected_invalid: pass,
    pass,
    fail,
    skip_expected: 0,
    skip_unsupported: 0,
    internal_errors: 0,
  }
}

///|
/// 断言报告是合法 JSON 且是 `stringify(indent=2)` 的不动点。
fn assert_canonical_json(text : String) -> Unit raise {
  assert_true(@json.valid(text))
  let parsed = @json.parse(text) catch {
    _ => abort("report is not valid json")
  }
  assert_eq(parsed.stringify(indent=2), text)
}

// ---------------------------------------------------------------------------
// 分片
// ---------------------------------------------------------------------------

///|
test "shard_pick 按排序结果均分且不重不漏" {
  let all = ["c.json", "a.json", "d.json", "b.json"]
  let first = @statetest.shard_pick(all, 0, 2)
  let second = @statetest.shard_pick(all, 1, 2)
  assert_paths(first, ["a.json", "c.json"])
  assert_paths(second, ["b.json", "d.json"])
  // 不重不漏：两片拼起来正好是排序后的全集。
  let union = first.copy()
  for path in second {
    union.push(path)
  }
  union.sort()
  assert_paths(union, ["a.json", "b.json", "c.json", "d.json"])
}

///|
test "shard_pick 用字典序，不是 String::compare 的长度优先序" {
  // 实测 MoonBit 0.10.22 的 `String::Compare` 长度优先（`"ab".compare("b") == 1`），
  // 直接 `sort()` 会把 `static/z.json` 排到 `cancun/...` 前面。报告的文件序
  // 必须是字典序，这条测试就是防回归的那一颗钉子。
  assert_paths(@statetest.shard_pick(["b.json", "aa.json"], 0, 1), [
    "aa.json", "b.json",
  ])
  assert_paths(
    @statetest.shard_pick(
      ["static/z.json", "cancun/eip1153.json", "cancun/eip4844.json"],
      0,
      1,
    ),
    ["cancun/eip1153.json", "cancun/eip4844.json", "static/z.json"],
  )
}

///|
test "shard_pick 单片返回全部，越界返回空" {
  let all = ["b.json", "a.json"]
  assert_paths(@statetest.shard_pick(all, 0, 1), ["a.json", "b.json"])
  assert_paths(@statetest.shard_pick(all, 0, 0), ["a.json", "b.json"])
  assert_paths(@statetest.shard_pick(all, 2, 2), [])
  assert_paths(@statetest.shard_pick(all, -1, 2), [])
}

///|
test "shard_pick 不改动调用方数组" {
  let all = ["c.json", "a.json"]
  let _ = @statetest.shard_pick(all, 0, 2)
  assert_eq(all[0], "c.json")
  assert_eq(all[1], "a.json")
}

// ---------------------------------------------------------------------------
// 合计与退出码
// ---------------------------------------------------------------------------

///|
test "totals_of 把每个文件的计数逐项相加" {
  let totals = @statetest.totals_of([
    row_of("a.json", 3, 1, 2),
    row_of("b.json", 4, 0, 4),
  ])
  assert_eq(totals.files, 2)
  assert_eq(totals.cases, 7)
  assert_eq(totals.pass, 1)
  assert_eq(totals.fail, 6)
  assert_eq(totals.txbytes_present, 7)
  assert_eq(totals.tx_errors, 0)
}

///|
test "FileReport::of 摘出的 cases 与 harness 的 cases 一致" {
  let doc = base_doc()
  let tx = tx_summary_of(doc)
  let harness = harness_of(doc, no_op)
  assert_eq(tx.cases, harness.cases)
  let row = @statetest.FileReport::of("f.json", tx, harness)
  assert_eq(row.cases, 1)
  assert_eq(row.fail, 1)
  assert_eq(row.pass, 0)
  assert_eq(row.tx_errors, 0)
  assert_eq(row.txbytes_present, 1)
  assert_eq(row.expected_invalid, 0)
}

///|
test "合计版退出码与单文件 exit_code 等价（stub 下 fail 默认不红）" {
  let doc = base_doc()
  let tx = tx_summary_of(doc)
  let harness = harness_of(doc, no_op)
  let totals = @statetest.totals_of([
    @statetest.FileReport::of("f.json", tx, harness),
  ])
  assert_eq(totals.exit_code(false), @statetest.exit_code(tx, harness, false))
  assert_eq(totals.exit_code(true), @statetest.exit_code(tx, harness, true))
  assert_eq(totals.exit_code(false), 0)
  assert_eq(totals.exit_code(true), 1)
}

///|
test "合计版退出码与单文件 exit_code 等价（tx 不干净）" {
  let doc = with_change(
    old="\"gasLimit\": [\"0x4c4b40\"],",
    new="\"gasLimit\": [\"0x4c4b41\"],",
  )
  let tx = tx_summary_of(doc)
  let harness = harness_of(doc, no_op)
  let totals = @statetest.totals_of([
    @statetest.FileReport::of("f.json", tx, harness),
  ])
  assert_true(!tx.is_clean())
  assert_eq(totals.exit_code(false), 1)
  assert_eq(totals.exit_code(false), @statetest.exit_code(tx, harness, false))
}

///|
test "合计版退出码：internal / unsupported / resign 各自都红" {
  let internal = { ..@statetest.CorpusTotals::new(), internal_errors: 1, }
  assert_eq(internal.exit_code(false), 1)
  let unsupported = { ..@statetest.CorpusTotals::new(), unsupported: 1, }
  assert_eq(unsupported.exit_code(false), 1)
  let resign = { ..@statetest.CorpusTotals::new(), resign_mismatches: 1, }
  assert_eq(resign.exit_code(false), 1)
  let only_fail = { ..@statetest.CorpusTotals::new(), fail: 1, }
  assert_eq(only_fail.exit_code(false), 0)
  assert_eq(only_fail.exit_code(true), 1)
}

// ---------------------------------------------------------------------------
// JSON 报告
// ---------------------------------------------------------------------------

///|
test "report_json 合法、可还原，并带 corpus pin 与 stub 自述" {
  let text = @statetest.report_json("Cancun", [row_of("a.json", 3, 1, 2)])
  assert_canonical_json(text)
  assert_true(text.contains("\"tag\": \"tests-v5.4.0\""))
  assert_true(
    text.contains("\"commit\": \"4f68564f47c7e577ad6cbb570858316f5ff0e7bb\""),
  )
  assert_true(text.contains("\"format\": \"state_test\""))
  assert_true(text.contains("\"fork\": \"Cancun\""))
  assert_true(
    text.contains("\"executor\": \"stub (no interpreter; G0 harness only)\""),
  )
  assert_true(text.contains("\"execution\": \"not_run\""))
  assert_true(text.contains("\"state_root\": \"not_checked\""))
  assert_true(text.contains("\"logs\": \"not_checked\""))
  assert_true(text.contains("\"path\": \"a.json\""))
  // 整数形态：`"cases": 3` 而不是 `3.0`。
  assert_true(text.contains("\"cases\": 3"))
  assert_true(text.contains("\"fail\": 2"))
  // totals 折了同一个文件。
  assert_true(text.contains("\"files\": 1"))
  assert_true(text.contains("\"pass\": 1"))
}

///|
test "report_json 同一输入两次逐字节一致" {
  let rows = [row_of("b.json", 2, 0, 2), row_of("a.json", 1, 1, 0)]
  let first = @statetest.report_json("Cancun", rows)
  let second = @statetest.report_json("Cancun", rows)
  assert_eq(first, second)
  assert_canonical_json(first)
}

///|
test "report_json 转义反斜杠与引号" {
  // 路径实际内容：dir\sub"quoted.json
  let path = "dir\\sub\"quoted.json"
  let text = @statetest.report_json("Cancun", [row_of(path, 1, 0, 1)])
  // 转义后必须是合法 JSON，且 `parse → stringify` 能原样还原（转义可逆）。
  assert_canonical_json(text)
  // JSON 文本里应出现 `\\` 与 `\"` 的转义形态。
  assert_true(text.contains("dir\\\\sub\\\"quoted.json"))
}

///|
test "report_json 空文件列表时 totals 全零" {
  let text = @statetest.report_json("Cancun", [])
  assert_canonical_json(text)
  assert_true(text.contains("\"files\": 0"))
  assert_true(text.contains("\"cases\": 0"))
  assert_true(text.contains("\"fail\": 0"))
  // 空数组要渲染成 `[]`。
  assert_true(text.contains("\"files\": []"))
}
