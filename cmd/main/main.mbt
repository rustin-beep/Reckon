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
    $|  statetest <fixture> [--fork <name>]
    $|                        load a single EEST state test fixture
    $|                        (default fork: Cancun)
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
  println("usage: reckon statetest <fixture.json> [--fork <name>]")
}

///|
fn main {
  let args = @env.args()
  let cmd = if args.length() > 1 { args[1] } else { "" }
  match cmd {
    "" | "help" | "--help" | "-h" => usage()
    "--version" | "-V" => println("reckon \{version}")
    "statetest" => run_statetest(args)
    "run" | "trace" | "bench" => {
      println("reckon \{cmd}: not implemented yet (see PLAN.md P0 B07-B08)")
      @env.exit(2)
    }
    _ => {
      println("reckon: unknown command '\{cmd}'")
      usage()
      @env.exit(2)
    }
  }
}

// ---------------------------------------------------------------------------
// statetest
// ---------------------------------------------------------------------------

///|
fn run_statetest(args : Array[String]) -> Unit {
  let mut path = ""
  let mut fork = "Cancun"
  let mut i = 2
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
    } else if arg == "-h" || arg == "--help" {
      usage_error("<fixture.json> [--fork <name>]")
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
    usage_error("missing <fixture>")
    @env.exit(2)
    return
  }
  let text = @fs.read_file_to_string(path) catch {
    @fs.IOError(message) => {
      println("reckon statetest: cannot read \{path}: \{message}")
      @env.exit(2)
    }
  }
  let fixtures = @statetest.parse_document(text) catch {
    e => {
      println("reckon statetest: \{path}: \{e.to_string()}")
      @env.exit(2)
      return
    }
  }
  let summary = @statetest.run_document(fixtures, fork) catch {
    e => {
      println("reckon statetest: \{path}: \{e.to_string()}")
      @env.exit(2)
      return
    }
  }
  print_summary(path, fork, summary)
  if summary.is_clean() {
    @env.exit(0)
  } else {
    @env.exit(1)
  }
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
