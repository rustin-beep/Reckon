// corpus 层（B09）：分片、跨文件汇总、JSON 报告骨架。
//
// 这一层是**纯计算**：不碰文件系统（目录遍历与写文件都在 `cmd/main`），也不读墙钟。
// 报告必须可复现——`as_of` 由 corpus pin 决定，不取运行时间，否则两次运行的结果
// 永远不一样，「可复现」就成了空话。
//
// 口径：
//   - corpus pin 是 PLAN ADR-8 的定值（EEST `tests-v5.4.0` / commit `4f68564` /
//     `build = stable`，来源 `fixtures/eest/probe/fixtures/.meta/fixtures.ini`）；
//   - 每个文件一行计数；**明细只在单文件模式打印**，多文件模式先用本报告定位到
//     文件，再对单文件复跑取明细——否则全语料的 mismatch 行会把输出淹掉；
//   - 「跑不了的文件」是覆盖缺口，不是 harness 失败：单独记 `bad_files`
//     （`no_fork` = 文档里没有目标 fork，`parse` = 连 JSON 都读不出来），
//     逐文件写进报告并打一行诊断，**不中断整批扫描**；
//   - `executor` 与 `checks` 是硬编码的 stub 标注：P0 没有 interpreter，
//     `pass = 0` 是预期结果，报告里必须自己说清，不能留给读者脑补。

// ---------------------------------------------------------------------------
// 单文件计数
// ---------------------------------------------------------------------------

///|
/// 文件为什么没跑：两条都属「应跳过」，但归因不同，报告里分开计数。
#derive(Debug)
pub(all) enum BadFile {
  /// 文档能解析，但 `post` 里没有目标 fork（老 fork 的 fixture 没有 Cancun）。
  NoFork
  /// 连 JSON / fixture 模型都读不出来（env 缺字段、十六进制非法等）。
  Unparsable
}

///|
pub impl Show for BadFile with fn to_string(self) -> String {
  match self {
    NoFork => "no_fork"
    Unparsable => "parse"
  }
}

///|
pub extend BadFile with Show::{to_string, output}

///|
/// 一个文件的运行结果，只留**计数**。
///
/// 明细（mismatch 行、expected 行）留在 `Summary` / `HarnessSummary` 里，供单文件
/// 模式打印；这里刻意不搬，避免全语料扫描时把几十万条字符串堆在内存里——只搬
/// G1 归因必需的那八个 mismatch 计数。
#derive(Debug)
pub(all) struct FileReport {
  /// 相对扫描根的路径（`/` 分隔）。不写绝对路径：报告要能进证据链，不能带本机路径。
  path : String
  /// `None` 表示跑通了；`Some(kind)` 表示被跳过，此时所有计数为 0。
  bad : BadFile?
  /// 跳过原因（跑通时为空串）。
  detail : String
  cases : Int32
  /// tx 流水线的非预期错误（decode / fields / recover / sender / expand）。
  tx_errors : Int32
  resign_mismatches : Int32
  /// tx 侧识别出的 type 4（未声明 `expectException`）。声明了异常的那些归
  /// `expected_invalid`，与 harness 侧同属 skip——这一列与 `skip_unsupported`
  /// 不是同一个维度，不能相加。
  tx_unsupported : Int32
  txbytes_present : Int32
  txbytes_missing : Int32
  /// `expectException` 覆盖且被 tx 流水线实际豁免的 case 数（B08 起不判语义）。
  expected_invalid : Int32
  pass : Int32
  fail : Int32
  skip_expected : Int32
  skip_unsupported : Int32
  internal_errors : Int32
  missing_accounts : Int32
  extra_accounts : Int32
  nonce_mismatches : Int32
  balance_mismatches : Int32
  code_mismatches : Int32
  missing_slots : Int32
  extra_slots : Int32
  slot_value_mismatches : Int32
}

///|
/// 从两条流水线的汇总里摘出计数。
///
/// `cases` 取 tx 侧：两条流水线都按「选中 fork 的 entry 数」计数（展开失败也算一个），
/// 这一点由「`FileReport::of` 摘出的 cases 与 harness 的 cases 一致」那条测试钉住。
pub fn FileReport::of(
  path : String,
  tx : Summary,
  harness : HarnessSummary,
) -> FileReport {
  {
    path,
    bad: None,
    detail: "",
    cases: tx.cases,
    tx_errors: tx.error_count,
    resign_mismatches: tx.resign_mismatch,
    tx_unsupported: tx.unsupported,
    txbytes_present: tx.txbytes_present,
    txbytes_missing: tx.txbytes_missing,
    expected_invalid: tx.expected_invalid,
    pass: harness.pass,
    fail: harness.fail,
    skip_expected: harness.skipped_expected_invalid,
    skip_unsupported: harness.skipped_unsupported,
    internal_errors: harness.internal_errors,
    missing_accounts: harness.missing_accounts,
    extra_accounts: harness.extra_accounts,
    nonce_mismatches: harness.nonce_mismatches,
    balance_mismatches: harness.balance_mismatches,
    code_mismatches: harness.code_mismatches,
    missing_slots: harness.missing_slots,
    extra_slots: harness.extra_slots,
    slot_value_mismatches: harness.slot_value_mismatches,
  }
}

///|
/// 一行「跑不了」的记录：计数全零，只带类别与原因。
pub fn FileReport::skipped(
  path : String,
  kind : BadFile,
  detail : String,
) -> FileReport {
  {
    path,
    bad: Some(kind),
    detail,
    cases: 0,
    tx_errors: 0,
    resign_mismatches: 0,
    tx_unsupported: 0,
    txbytes_present: 0,
    txbytes_missing: 0,
    expected_invalid: 0,
    pass: 0,
    fail: 0,
    skip_expected: 0,
    skip_unsupported: 0,
    internal_errors: 0,
    missing_accounts: 0,
    extra_accounts: 0,
    nonce_mismatches: 0,
    balance_mismatches: 0,
    code_mismatches: 0,
    missing_slots: 0,
    extra_slots: 0,
    slot_value_mismatches: 0,
  }
}

// ---------------------------------------------------------------------------
// 汇总
// ---------------------------------------------------------------------------

///|
/// 一次 corpus 扫描的合计。字段与 `FileReport` 一一对应，外加 `files` 与
/// 三种「没跑成」的计数。
#derive(Debug)
pub(all) struct CorpusTotals {
  files : Int32
  /// 跳过文件总数（= `no_fork_files + unparsable_files`）。
  bad_files : Int32
  no_fork_files : Int32
  unparsable_files : Int32
  cases : Int32
  tx_errors : Int32
  resign_mismatches : Int32
  tx_unsupported : Int32
  txbytes_present : Int32
  txbytes_missing : Int32
  expected_invalid : Int32
  pass : Int32
  fail : Int32
  skip_expected : Int32
  skip_unsupported : Int32
  internal_errors : Int32
  missing_accounts : Int32
  extra_accounts : Int32
  nonce_mismatches : Int32
  balance_mismatches : Int32
  code_mismatches : Int32
  missing_slots : Int32
  extra_slots : Int32
  slot_value_mismatches : Int32
}

///|
pub fn CorpusTotals::new() -> CorpusTotals {
  {
    files: 0,
    bad_files: 0,
    no_fork_files: 0,
    unparsable_files: 0,
    cases: 0,
    tx_errors: 0,
    resign_mismatches: 0,
    tx_unsupported: 0,
    txbytes_present: 0,
    txbytes_missing: 0,
    expected_invalid: 0,
    pass: 0,
    fail: 0,
    skip_expected: 0,
    skip_unsupported: 0,
    internal_errors: 0,
    missing_accounts: 0,
    extra_accounts: 0,
    nonce_mismatches: 0,
    balance_mismatches: 0,
    code_mismatches: 0,
    missing_slots: 0,
    extra_slots: 0,
    slot_value_mismatches: 0,
  }
}

///|
pub fn CorpusTotals::add(
  self : CorpusTotals,
  file : FileReport,
) -> CorpusTotals {
  let bad = match file.bad {
    None => 0
    Some(_) => 1
  }
  let no_fork = match file.bad {
    Some(NoFork) => 1
    _ => 0
  }
  let unparsable = match file.bad {
    Some(Unparsable) => 1
    _ => 0
  }
  {
    files: self.files + 1,
    bad_files: self.bad_files + bad,
    no_fork_files: self.no_fork_files + no_fork,
    unparsable_files: self.unparsable_files + unparsable,
    cases: self.cases + file.cases,
    tx_errors: self.tx_errors + file.tx_errors,
    resign_mismatches: self.resign_mismatches + file.resign_mismatches,
    tx_unsupported: self.tx_unsupported + file.tx_unsupported,
    txbytes_present: self.txbytes_present + file.txbytes_present,
    txbytes_missing: self.txbytes_missing + file.txbytes_missing,
    expected_invalid: self.expected_invalid + file.expected_invalid,
    pass: self.pass + file.pass,
    fail: self.fail + file.fail,
    skip_expected: self.skip_expected + file.skip_expected,
    skip_unsupported: self.skip_unsupported + file.skip_unsupported,
    internal_errors: self.internal_errors + file.internal_errors,
    missing_accounts: self.missing_accounts + file.missing_accounts,
    extra_accounts: self.extra_accounts + file.extra_accounts,
    nonce_mismatches: self.nonce_mismatches + file.nonce_mismatches,
    balance_mismatches: self.balance_mismatches + file.balance_mismatches,
    code_mismatches: self.code_mismatches + file.code_mismatches,
    missing_slots: self.missing_slots + file.missing_slots,
    extra_slots: self.extra_slots + file.extra_slots,
    slot_value_mismatches: self.slot_value_mismatches +
    file.slot_value_mismatches,
  }
}

///|
/// 把若干文件的计数折成合计。
pub fn totals_of(files : Array[FileReport]) -> CorpusTotals {
  let mut totals = CorpusTotals::new()
  for file in files {
    totals = totals.add(file)
  }
  totals
}

///|
/// 与 `exit_code` 同一套判据的合计版本：tx 不干净（error / resign mismatch /
/// 未声明异常的 type 4）或 harness 内部出错 → 1。
///
/// `strict` 再加两条：state fail > 0，**以及有任何文件没跑成**（覆盖缺口）。
/// 默认不因 `bad_files` 变红——用 `--fork Cancun` 扫整棵树必然碰到老 fork 的
/// fixture，那是语料结构而不是缺陷；但「证据要完整」时必须红，不能让缺口藏在
/// exit 0 后面。
///
/// 等价性由测试钉住：单文件的 `FileReport` 折成合计后，结果必须等于对该文件调用
/// `exit_code(tx, harness, strict)`。
pub fn CorpusTotals::exit_code(self : CorpusTotals, strict : Bool) -> Int32 {
  if self.tx_errors > 0 {
    return 1
  }
  if self.resign_mismatches > 0 {
    return 1
  }
  if self.tx_unsupported > 0 {
    return 1
  }
  if self.internal_errors > 0 {
    return 1
  }
  if strict {
    if self.fail > 0 {
      return 1
    }
    if self.bad_files > 0 {
      return 1
    }
  }
  0
}

// ---------------------------------------------------------------------------
// 分片
// ---------------------------------------------------------------------------

///|
/// 路径比较：**逐字符**（按码点）比，短前缀在前。
///
/// 不用 `String::compare`：MoonBit 0.10.22 的 `String::Compare` 是**长度优先**
/// （实测 `"ab".compare("b") == 1`、`"a10".compare("a9") == 1`），拿它排序会让
/// `static/z.json` 排在 `cancun/...` 前面——报告的文件序就不是人预期的那种。
/// 这里显式实现，报告与分片都不随工具链的 `Compare` 语义漂移。
fn compare_paths(a : String, b : String) -> Int32 {
  let limit = if a.length() < b.length() { a.length() } else { b.length() }
  let mut i = 0
  while i < limit {
    let left = a[i].to_int()
    let right = b[i].to_int()
    if left < right {
      return -1
    }
    if left > right {
      return 1
    }
    i = i + 1
  }
  if a.length() < b.length() {
    -1
  } else if a.length() > b.length() {
    1
  } else {
    0
  }
}

///|
/// 按路径字典序做确定性分片：第 `shard` 片（0 起）取 `i % shards == shard`。
///
/// - `shards <= 1` 返回全部（排序后）；
/// - `shard` 越界返回空数组——调用方应在解析参数时就挡掉，返回空而不是报错是为了
///   让本函数保持 total（`cmd/main` 里已经先做范围校验）。
///
/// 排序在函数内部做：调用方给的目录遍历顺序是文件系统顺序，不排序的话各分片
/// 会随机器变化，分片结果就不可复现。
pub fn shard_pick(
  paths : Array[String],
  shard : Int32,
  shards : Int32,
) -> Array[String] {
  let sorted = paths.copy()
  sorted.sort_by(compare_paths)
  if shards <= 1 {
    return sorted
  }
  let out : Array[String] = []
  let mut i = 0
  while i < sorted.length() {
    if i % shards == shard {
      out.push(sorted[i])
    }
    i = i + 1
  }
  out
}

// ---------------------------------------------------------------------------
// JSON 报告
// ---------------------------------------------------------------------------

///|
/// 报告的运行参数。**必须进报告**：1/4 分片的报告与全量报告不能长得一模一样，
/// `--strict` 与否决定同一份数据两种结论——这些靠读的人自己猜是不可接受的。
#derive(Debug)
pub(all) struct ReportOptions {
  fork : String
  shard_index : Int32
  shard_count : Int32
  strict : Bool
}

///|
pub fn ReportOptions::new(fork : String) -> ReportOptions {
  { fork, shard_index: 0, shard_count: 1, strict: false, }
}

///|
/// 计数字段的 JSON 表示。整数用 `repr` 写成 `42` 而不是 `42.0`：报告要给人读，
/// 也要能被别的脚本直接吃。
fn json_count(value : Int32) -> Json {
  Json::number(value.to_double(), repr=value.to_string())
}

///|
/// 文件行的 JSON。跑通与跳过的行**同一套键**（跳过的计数全 0），消费方不必分支。
fn file_json(file : FileReport) -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("path", Json::string(file.path))
  obj.set(
    "bad",
    match file.bad {
      None => Json::null()
      Some(kind) => Json::string(kind.to_string())
    },
  )
  obj.set("detail", Json::string(file.detail))
  obj.set("cases", json_count(file.cases))
  obj.set("pass", json_count(file.pass))
  obj.set("fail", json_count(file.fail))
  obj.set("skip_expected", json_count(file.skip_expected))
  obj.set("skip_unsupported", json_count(file.skip_unsupported))
  obj.set("internal_errors", json_count(file.internal_errors))
  obj.set("tx_errors", json_count(file.tx_errors))
  obj.set("resign_mismatches", json_count(file.resign_mismatches))
  obj.set("tx_unsupported", json_count(file.tx_unsupported))
  obj.set("txbytes_present", json_count(file.txbytes_present))
  obj.set("txbytes_missing", json_count(file.txbytes_missing))
  obj.set("expected_invalid", json_count(file.expected_invalid))
  obj.set("missing_accounts", json_count(file.missing_accounts))
  obj.set("extra_accounts", json_count(file.extra_accounts))
  obj.set("nonce_mismatches", json_count(file.nonce_mismatches))
  obj.set("balance_mismatches", json_count(file.balance_mismatches))
  obj.set("code_mismatches", json_count(file.code_mismatches))
  obj.set("missing_slots", json_count(file.missing_slots))
  obj.set("extra_slots", json_count(file.extra_slots))
  obj.set("slot_value_mismatches", json_count(file.slot_value_mismatches))
  Json::object(obj)
}

///|
fn totals_json(totals : CorpusTotals) -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("files", json_count(totals.files))
  obj.set("bad_files", json_count(totals.bad_files))
  obj.set("no_fork_files", json_count(totals.no_fork_files))
  obj.set("unparsable_files", json_count(totals.unparsable_files))
  obj.set("cases", json_count(totals.cases))
  obj.set("pass", json_count(totals.pass))
  obj.set("fail", json_count(totals.fail))
  obj.set("skip_expected", json_count(totals.skip_expected))
  obj.set("skip_unsupported", json_count(totals.skip_unsupported))
  obj.set("internal_errors", json_count(totals.internal_errors))
  obj.set("tx_errors", json_count(totals.tx_errors))
  obj.set("resign_mismatches", json_count(totals.resign_mismatches))
  obj.set("tx_unsupported", json_count(totals.tx_unsupported))
  obj.set("txbytes_present", json_count(totals.txbytes_present))
  obj.set("txbytes_missing", json_count(totals.txbytes_missing))
  obj.set("expected_invalid", json_count(totals.expected_invalid))
  obj.set("missing_accounts", json_count(totals.missing_accounts))
  obj.set("extra_accounts", json_count(totals.extra_accounts))
  obj.set("nonce_mismatches", json_count(totals.nonce_mismatches))
  obj.set("balance_mismatches", json_count(totals.balance_mismatches))
  obj.set("code_mismatches", json_count(totals.code_mismatches))
  obj.set("missing_slots", json_count(totals.missing_slots))
  obj.set("extra_slots", json_count(totals.extra_slots))
  obj.set("slot_value_mismatches", json_count(totals.slot_value_mismatches))
  Json::object(obj)
}

///|
/// 语料标识与「没判什么」的自述。这两块是报告的门面：缺了它们，`pass = 0` 会被
/// 当成实现跑挂。
fn corpus_json() -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("tag", Json::string("tests-v5.4.0"))
  obj.set("commit", Json::string("4f68564f47c7e577ad6cbb570858316f5ff0e7bb"))
  obj.set("build", Json::string("stable"))
  obj.set("format", Json::string("state_test"))
  Json::object(obj)
}

///|
fn checks_json() -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("execution", Json::string("not_run"))
  obj.set("state_root", Json::string("not_checked"))
  obj.set("logs", Json::string("not_checked"))
  Json::object(obj)
}

///|
fn shard_json(options : ReportOptions) -> Json {
  let obj : Map[String, Json] = Map([])
  obj.set("index", json_count(options.shard_index))
  obj.set("count", json_count(options.shard_count))
  Json::object(obj)
}

///|
/// 一份 corpus 扫描的 JSON 报告（骨架）。
///
/// 键按固定顺序插入（`Map` 保留插入序），因此同一输入的报告逐字节可复现；
/// `Json::stringify` 负责转义（Windows 路径里的 `\`、名字里的引号都在测试里钉住）。
///
/// 除 `files` / `totals` 外都是口径自述：`executor` 恒为 stub，`checks` 明说
/// state root / logs / 执行都没判，`shard` 与 `strict` 说明这份报告是怎么切出来的、
/// 按哪套判据读。
pub fn report_json(
  options : ReportOptions,
  files : Array[FileReport],
) -> String {
  let rows : Array[Json] = []
  for file in files {
    rows.push(file_json(file))
  }
  let report : Map[String, Json] = Map([])
  report.set("corpus", corpus_json())
  report.set("fork", Json::string(options.fork))
  report.set("shard", shard_json(options))
  report.set("strict", Json::boolean(options.strict))
  report.set("executor", Json::string("stub (no interpreter; G0 harness only)"))
  report.set("checks", checks_json())
  report.set("files", Json::array(rows))
  report.set("totals", totals_json(totals_of(files)))
  Json::object(report).stringify(indent=2)
}
