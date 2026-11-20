// `reckon` CLI 骨架。
//
// B01 就把子命令挂在这里，后续工作包都有稳定入口；具体实现随各自的 harness
// 落地（B06-B08）。

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
    $|  statetest <fixture>   run a single EEST state test fixture
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
fn main {
  let args = @env.args()
  let cmd = if args.length() > 1 { args[1] } else { "" }
  match cmd {
    "" | "help" | "--help" | "-h" => usage()
    "--version" | "-V" => println("reckon \{version}")
    "statetest" | "run" | "trace" | "bench" => {
      println("reckon \{cmd}: not implemented yet (see PLAN.md P0 B06-B08)")
      @env.exit(2)
    }
    _ => {
      println("reckon: unknown command '\{cmd}'")
      usage()
      @env.exit(2)
    }
  }
}
