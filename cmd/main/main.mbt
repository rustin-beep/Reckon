// `reckon` CLI。
//
// B01 就把子命令挂在这里，后续工作包都有稳定入口；具体实现随各自的 harness
// 落地（B06 起 `statetest` 可用）。

///|
let version : String = "0.1.0"

///|
fn usage() -> Unit {
  let text =
    $|reckon \{version} — embeddable EVM execution core (MoonBit)
    $|
    $|usage: reckon <command> [args]
    $|
    $|commands:
    $|  statetest <fixture-or-dir> [--fork <name>] [--strict]
    $|            [--shard <i>/<n>] [--report <path>]
    $|                        run the EEST state test harness on one fixture or
    $|                        on every *.json under a directory (default fork:
    $|                        Cancun; --strict makes a state mismatch fail the
    $|                        run; --shard picks one deterministic slice of the
    $|                        file list; --report writes a JSON report)
    $|  run                   execute a transaction from JSON input
    $|  trace                 emit an EIP-3155 trace
    $|  bench                 run evmone-bench compatible benchmarks
    $|
    $|options:
    $|  -h, --help            show this message
    $|  -V, --version         show the version
    $|
  println(text)
}

///|
fn usage_error(message : String) -> Unit {
  println("reckon statetest: \{message}")
  println(
    "usage: reckon statetest <fixture-or-dir> [--fork <name>] [--strict] [--shard <i>/<n>] [--report <path>]",
  )
}

///|
fn main {
  let args = @env.args()
  let first = first_arg_index(args)
  let cmd = if args.length() > first { args[first] } else { "" }
  match cmd {
    "" | "help" | "--help" | "-h" => usage()
    "--version" | "-V" => println("reckon \{version}")
    "statetest" => run_statetest(args, first + 1)
    "run" | "trace" | "bench" => {
      println(
        "reckon \{cmd}: not implemented yet (run: P1 C01-C13; trace: C15; bench: X01)",
      )
      @env.exit(2)
    }
    _ => {
      println("reckon: unknown command '\{cmd}'")
      usage()
      @env.exit(2)
    }
  }
}

///|
/// 子命令在 `args` 里的下标。
///
/// native / wasm / wasm-gc 的 `@env.args()` 是 `[程序, 子命令, …]`；js 上是
/// `[运行时, 脚本, 子命令, …]`（Node 的 `process.argv` 原样透传），因此 js 要多跳
/// 一个 `main.js`。实测：`moon run cmd/main --target js -- zzz` 会把脚本路径当成
/// 子命令报 `unknown command '…/main.js'`。判据只看「第二项是否以 .js 结尾」——
/// 子命令名不可能是 .js 文件。
fn first_arg_index(args : Array[String]) -> Int32 {
  if args.length() > 1 && args[1].has_suffix(".js") {
    2
  } else {
    1
  }
}

// ---------------------------------------------------------------------------
// statetest
// ---------------------------------------------------------------------------

///|
fn run_statetest(args : Array[String], first : Int32) -> Unit {
  let mut path = ""
  let mut fork = "Cancun"
  let mut strict = false
  let mut shard = 0
  let mut shards = 1
  let mut report_path = ""
  let mut i = first
  let mut bad = false
  while i < args.length() && !bad {
    let arg = args[i]
    if arg == "--fork" {
      if i + 1 >= args.length() {
        usage_error("--fork requires a value")
        bad = true
      } else {
        fork = args[i + 1]
        i = i + 2
      }
    } else if arg == "--strict" {
      strict = true
      i = i + 1
    } else if arg == "--shard" {
      if i + 1 >= args.length() {
        usage_error("--shard requires <index>/<count>")
        bad = true
      } else {
        match parse_shard(args[i + 1]) {
          Some(pair) => {
            shard = pair.0
            shards = pair.1
            i = i + 2
          }
          None => {
            usage_error(
              "--shard expects <index>/<count> with 0 <= index < count, e.g. 1/4",
            )
            bad = true
          }
        }
      }
    } else if arg == "--report" {
      if i + 1 >= args.length() {
        usage_error("--report requires a path")
        bad = true
      } else {
        report_path = args[i + 1]
        i = i + 2
      }
    } else if arg == "-h" || arg == "--help" {
      usage_error(
        "<fixture-or-dir> [--fork <name>] [--strict] [--shard <i>/<n>] [--report <path>]",
      )
      bad = true
    } else if arg.has_prefix("-") {
      usage_error("unknown option '\{arg}'")
      bad = true
    } else if path != "" {
      usage_error("more than one fixture path given")
      bad = true
    } else {
      path = arg
      i = i + 1
    }
  }
  if bad {
    @env.exit(2)
    return
  }
  if path == "" {
    usage_error("missing <fixture-or-dir>")
    @env.exit(2)
    return
  }
  // 目录（递归 *.json）或单文件：目录遍历只在这里做，`statetest` 库不碰文件系统。
  let directory = @fs.is_dir(path) catch { _ => false }
  if shards > 1 && !directory {
    usage_error("--shard only applies to a directory of fixtures")
    @env.exit(2)
    return
  }
  if report_path != "" && report_conflicts(report_path, path, directory) {
    usage_error(
      "--report must not point at or inside the scanned fixtures (it would be read as a fixture next run)",
    )
    @env.exit(2)
    return
  }
  let items : Array[(String, String)] = []
  if directory {
    let rels : Array[String] = []
    collect_json_files(path, "", rels) catch {
      @fs.IOError(message) => {
        println("reckon statetest: cannot scan \{path}: \{message}")
        @env.exit(2)
      }
    }
    if rels.length() == 0 {
      println("reckon statetest: no *.json under \{path}")
      @env.exit(2)
      return
    }
    // 分片在排序后做，同一 `i/n` 在任何机器上都切出同一批文件。
    for rel in @statetest.shard_pick(rels, shard, shards) {
      items.push((path + "/" + rel, rel))
    }
  } else {
    items.push((path, base_name_of(path)))
  }
  // 语料模式由「参数是目录」决定，而不是由分片后的文件数决定：
  // 否则 `--shard 1/2` 恰好剩一个文件时输出形态会突变，脚本没法稳定解析。
  let corpus_mode = directory
  if corpus_mode {
    println("files=\{items.length()}")
    println("fork=\{fork}")
    println("shard=\{shard}/\{shards}")
    println("strict=\{strict}")
    print_stub_banner()
  }
  let rows : Array[@statetest.FileReport] = []
  for (absolute, relative) in items {
    let outcome = run_file(absolute, fork) catch {
      @fs.IOError(message) => {
        println("reckon statetest: cannot read \{absolute}: \{message}")
        if corpus_mode {
          // IO 失败是真的中止（不是「这个文件跳过」）：已打印的 file= 行不完整，
          // 必须标注，否则读者会把它当成一次完整的语料扫描。
          println(
            "incomplete=1 (aborted on IO error; the file= lines above are partial)",
          )
        }
        @env.exit(2)
        return
      }
    }
    match outcome {
      Ran(summary, harness) => {
        rows.push(@statetest.FileReport::of(relative, summary, harness))
        if corpus_mode {
          print_file_row(relative, summary, harness)
        } else {
          print_summary(absolute, fork, summary)
          print_harness(harness)
        }
      }
      SkippedNoFork(detail) =>
        if corpus_mode {
          // 老 fork 的 fixture 没有目标 fork：跳过并计数，不中断整批。
          rows.push(
            @statetest.FileReport::skipped(relative, @statetest.NoFork, detail),
          )
          println("bad=no_fork file=\{relative} \{detail}")
        } else {
          println("reckon statetest: \{absolute}: \{detail}")
          @env.exit(2)
          return
        }
      SkippedUnparsable(detail) =>
        if corpus_mode {
          rows.push(
            @statetest.FileReport::skipped(
              relative,
              @statetest.Unparsable,
              detail,
            ),
          )
          println("bad=parse file=\{relative} \{detail}")
        } else {
          println("reckon statetest: \{absolute}: \{detail}")
          @env.exit(2)
          return
        }
    }
  }
  let totals = @statetest.totals_of(rows)
  if corpus_mode {
    print_totals(totals)
  }
  if report_path != "" {
    let options = {
      ..@statetest.ReportOptions::new(fork),
      shard_index: shard,
      shard_count: shards,
      strict,
    }
    let text = @statetest.report_json(options, rows) + "\n"
    @fs.write_string_to_file(report_path, text) catch {
      @fs.IOError(message) => {
        println("reckon statetest: cannot write \{report_path}: \{message}")
        @env.exit(2)
      }
    }
    println("report=\{report_path}")
  }
  // 退出码判定是 `statetest` 里的纯函数（合计版与单文件版等价，已单测）。
  @env.exit(totals.exit_code(strict))
}

///|
/// 单文件的三种结局。`run_document` 在文档级只抛 `ForkNotFound`（case 级失败进
/// errors 桶），所以「没有目标 fork」与「读不出来」能干净地分开。
priv enum FileOutcome {
  Ran(@statetest.Summary, @statetest.HarnessSummary)
  /// 文档能解析，但 `post` 里没有目标 fork。
  SkippedNoFork(String)
  /// 连 JSON / fixture 模型都读不出来。
  SkippedUnparsable(String)
}

///|
fn run_file(absolute : String, fork : String) -> FileOutcome raise @fs.IOError {
  let text = @fs.read_file_to_string(absolute)
  let fixtures = @statetest.parse_document(text) catch {
    e => return SkippedUnparsable(e.to_string())
  }
  let summary = @statetest.run_document(fixtures, fork) catch {
    e => return SkippedNoFork(e.to_string())
  }
  // harness v0：executor 是 no-op（P0 没有 interpreter），所以先跑 tx 流水线再比对。
  let harness = @statetest.run_harness(fixtures, fork, fn(_case, _state) { () })
  Ran(summary, harness)
}

///|
/// `--report` 不能落在输入里：写进扫描树既可能覆盖 fixture，也会让下一次扫描
/// 把它当成语料。单文件模式只挡完全相同的路径。
fn report_conflicts(report : String, root : String, directory : Bool) -> Bool {
  if !directory {
    return report == root
  }
  report.has_prefix(trim_trailing_slash(root) + "/")
}

///|
fn trim_trailing_slash(path : String) -> String {
  let mut end = path.length()
  while end > 1 && (path[end - 1] == '/' || path[end - 1] == '\\') {
    end = end - 1
  }
  path[:end].to_owned()
}

///|
/// 递归收集 `*.json`，把**相对**路径写进 `out`（`/` 分隔）。排序留给调用方：
/// `shard_pick` 内部先排序，所以分片与遍历顺序无关。
fn collect_json_files(
  root : String,
  prefix : String,
  out : Array[String],
) -> Unit raise @fs.IOError {
  let dir = if prefix == "" { root } else { root + "/" + prefix }
  for name in @fs.read_dir(dir) {
    let rel = if prefix == "" { name } else { prefix + "/" + name }
    if @fs.is_dir(root + "/" + rel) {
      collect_json_files(root, rel, out)
    } else if name.has_suffix(".json") {
      out.push(rel)
    }
  }
}

///|
/// 路径最后一段（`/` 与 `\` 都认）。单文件模式下报告里只写文件名，不写绝对路径。
fn base_name_of(path : String) -> String {
  let mut cut = 0
  for i in 0..<path.length() {
    let ch = path[i]
    if ch == '/' || ch == '\\' {
      cut = i + 1
    }
  }
  path[cut:].to_owned()
}

///|
/// 解析 `--shard <index>/<count>`；不合法一律 `None`（由调用方报用法错误并 exit 2）。
fn parse_shard(text : String) -> (Int32, Int32)? {
  let mut slash = -1
  for i in 0..<text.length() {
    if text[i] == '/' {
      slash = i
    }
  }
  if slash <= 0 || slash == text.length() - 1 {
    return None
  }
  match (parse_digits(text[:slash]), parse_digits(text[slash + 1:])) {
    (Some(index), Some(count)) =>
      if count <= 0 || index < 0 || index >= count {
        None
      } else {
        Some((index, count))
      }
    _ => None
  }
}

///|
fn parse_digits(text : StringView) -> Int32? {
  if text.length() == 0 {
    return None
  }
  let mut value = 0
  for i in 0..<text.length() {
    let digit = text[i].to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    // 2147483647 / 10 = 214748364 余 7：先查乘 10 会不会溢出，再加个位。
    // 不查的话 `--shard 4294967297/4` 会静默回绕成 `1/4`。
    if value > 214748364 {
      return None
    }
    if value == 214748364 && digit > 7 {
      return None
    }
    value = value * 10 + digit
  }
  Some(value)
}

///|
fn print_summary(
  path : String,
  fork : String,
  summary : @statetest.Summary,
) -> Unit {
  println("fixture=\{path}")
  println("fork=\{fork}")
  println("cases=\{summary.cases}")
  println(
    "tx_types=legacy:\{summary.legacy} type1:\{summary.type1} type2:\{summary.type2} type3:\{summary.type3} unsupported:\{summary.unsupported}",
  )
  println(
    "txbytes=present:\{summary.txbytes_present} missing:\{summary.txbytes_missing}",
  )
  println(
    "resign=ok:\{summary.resign_ok} mismatch:\{summary.resign_mismatch} skipped:\{summary.resign_skipped} expected_invalid:\{summary.expected_invalid}",
  )
  println("sender=ok:\{summary.sender_ok} mismatch:\{summary.sender_mismatch}")
  println("errors=\{summary.error_count}")
  let limit = 50
  let total = summary.errors.length()
  let shown = if total < limit { total } else { limit }
  let mut i = 0
  while i < shown {
    println(summary.errors[i])
    i = i + 1
  }
  if total > limit {
    println("... and \{total - limit} more error(s)")
  }
  // 预期失败单独一段：它们不影响退出码，但需要能看到细分明细。
  let expected_total = summary.expected.length()
  if expected_total > 0 {
    println(
      "expected=\{expected_total} (fixture declares expectException; not counted as errors)",
    )
    let expected_limit = 20
    let expected_shown = if expected_total < expected_limit {
      expected_total
    } else {
      expected_limit
    }
    let mut k = 0
    while k < expected_shown {
      println(summary.expected[k])
      k = k + 1
    }
    if expected_total > expected_limit {
      println("... and \{expected_total - expected_limit} more expected")
    }
  }
}

///|
/// stub 自述三行。`execution=stub` 与两个 `not_checked` 是**无条件**打印的：
/// P0 没有 interpreter，G0 只判 harness 通路，不能让读者误以为执行正确性已判。
fn print_stub_banner() -> Unit {
  println("execution=stub (no interpreter; G0 harness only)")
  println("state_root=not_checked")
  println("logs=not_checked")
}

///|
/// harness 段（单文件模式）。
fn print_harness(harness : @statetest.HarnessSummary) -> Unit {
  print_stub_banner()
  println(
    "harness=cases:\{harness.cases} pass:\{harness.pass} fail:\{harness.fail} skip_expected:\{harness.skipped_expected_invalid} skip_unsupported:\{harness.skipped_unsupported} internal_errors:\{harness.internal_errors}",
  )
  println(
    "state_diff=accounts:\{harness.diff_accounts} slots:\{harness.diff_slots}",
  )
  println(
    "post_diff=missing_accounts:\{harness.missing_accounts} extra_accounts:\{harness.extra_accounts} nonce:\{harness.nonce_mismatches} balance:\{harness.balance_mismatches} code:\{harness.code_mismatches} missing_slots:\{harness.missing_slots} extra_slots:\{harness.extra_slots} slot_values:\{harness.slot_value_mismatches}",
  )
  // 库里已按 50 条截断，这里照实打印；被省略的条数单独一行，避免「少了几条」被静默。
  for line in harness.details {
    println(line)
  }
  if harness.details_omitted > 0 {
    println("... and \{harness.details_omitted} more detail(s)")
  }
}

///|
/// 多文件模式下的单文件计数行。明细只在单文件模式打印（见 `print_harness`）：
/// 全语料的 mismatch 行会把输出淹掉，定位靠这一行 + `--report`，再对单文件复跑。
fn print_file_row(
  path : String,
  summary : @statetest.Summary,
  harness : @statetest.HarnessSummary,
) -> Unit {
  let row = @statetest.FileReport::of(path, summary, harness)
  println(
    "file=\{row.path} cases:\{row.cases} pass:\{row.pass} fail:\{row.fail} skip_expected:\{row.skip_expected} skip_unsupported:\{row.skip_unsupported} internal_errors:\{row.internal_errors} tx_errors:\{row.tx_errors} resign_mismatch:\{row.resign_mismatches} tx_unsupported:\{row.tx_unsupported} txbytes_present:\{row.txbytes_present} txbytes_missing:\{row.txbytes_missing} expected_invalid:\{row.expected_invalid}",
  )
}

///|
/// 合计行，分两行：
///   - `totals=`：文件 / case 级（含 `bad_files` 的三种口径）；
///   - `mismatch=`：字段 / 槽级八类分布——G1 要「逐条归因」，这是最小必需维度。
fn print_totals(totals : @statetest.CorpusTotals) -> Unit {
  println(
    "totals=files:\{totals.files} bad_files:\{totals.bad_files} no_fork:\{totals.no_fork_files} unparsable:\{totals.unparsable_files} cases:\{totals.cases} pass:\{totals.pass} fail:\{totals.fail} skip_expected:\{totals.skip_expected} skip_unsupported:\{totals.skip_unsupported} internal_errors:\{totals.internal_errors} tx_errors:\{totals.tx_errors} resign_mismatch:\{totals.resign_mismatches} tx_unsupported:\{totals.tx_unsupported} txbytes_present:\{totals.txbytes_present} txbytes_missing:\{totals.txbytes_missing} expected_invalid:\{totals.expected_invalid}",
  )
  println(
    "mismatch=missing_accounts:\{totals.missing_accounts} extra_accounts:\{totals.extra_accounts} nonce:\{totals.nonce_mismatches} balance:\{totals.balance_mismatches} code:\{totals.code_mismatches} missing_slots:\{totals.missing_slots} extra_slots:\{totals.extra_slots} slot_values:\{totals.slot_value_mismatches}",
  )
}
