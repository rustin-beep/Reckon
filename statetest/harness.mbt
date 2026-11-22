// harness v0：fixture → State → 执行回调 → 账户级比对 → 计数。
//
// 定位（PLAN §3 的 G0 口径）：P0 没有 interpreter，本文件的使命是把
// 「执行 → 比对 → 计数 → 可复现报告」这条通路打通，**不判执行正确性**。因此：
//
//   - 执行通过显式回调 `execute : (Case, State) -> Unit` 注入；CLI 传 no-op，
//     并**无条件**在输出里标注 `execution=stub`；
//   - expected 与 actual 都过一遍 `State::from_accounts(..).accounts()`，empty 账户、
//     零槽、排序规则由 `state` 统一给出，不在这里另造一套规范；
//   - 只比账户级（nonce / balance / code 字节 / 非零槽）。`post.hash`（state root，
//     无 MPT）与 `post.logs`（无日志执行）不参与比对；
//   - `expectException`（C12/D03）与 type 4 / EIP-7702（P02）只计 skip，不判语义。
//
// 生产路径绝不读 `post.state` 反填 actual：唯一能改 actual 的地方是调用方传进来的
// `execute`，只有 `*_test.mbt` 里的 fake executor 才会把它当输入。
//
// 确定性：遍历顺序取自 fixture 数组与 `post[fork]` 数组（都是保序的），`accounts()`
// 与 `diff()` 自带排序，明细按比较顺序追加。同一输入两次运行的输出逐字节相同。

// ---------------------------------------------------------------------------
// 限额
// ---------------------------------------------------------------------------

///|
/// 明细里 code 字节的摘要上限（字节）。超过即截断，只影响可读性，不影响计数。
let max_code_excerpt_bytes : Int32 = 32

///|
/// `details` 的条数上限。超出的部分只进计数（`details_omitted`），不占内存。
let max_detail_lines : Int32 = 50

///|
/// 0–15 的十六进制文本。`U256` 的最小十六进制表示要掐掉前导零，而字符串切片在
/// 三后端上的可用写法不统一，这里用查表避开切片。
let nibble_hex : Array[String] = [
  "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
]

// ---------------------------------------------------------------------------
// 差异分类
// ---------------------------------------------------------------------------

///|
/// 账户级比对的差异类别。账户级与字段级分开，是因为前者说明「账户集合不同」，
/// 后者说明「账户在、值不对」——归因方向完全不同。
#derive(Debug)
pub(all) enum MismatchClass {
  /// expected 有、actual 没有。
  MissingAccount
  /// actual 有、expected 没有。
  ExtraAccount
  Nonce
  Balance
  Code
  /// expected 有该槽、actual 无（或为 0）。
  MissingSlot
  /// actual 有该槽、expected 无（或为 0）。
  ExtraSlot
  /// 两侧都有该槽但值不同。
  SlotValue
}

///|
pub impl Show for MismatchClass with fn to_string(self) -> String {
  match self {
    MissingAccount => "missing_account"
    ExtraAccount => "extra_account"
    Nonce => "nonce_mismatch"
    Balance => "balance_mismatch"
    Code => "code_mismatch"
    MissingSlot => "missing_slot"
    ExtraSlot => "extra_slot"
    SlotValue => "slot_value_mismatch"
  }
}

///|
pub extend MismatchClass with Show::{to_string, output}

///|
/// 一条差异明细。`expected` / `actual` 已经是**可直接打印**的短文本（code 超过
/// `max_code_excerpt_bytes` 就截断），这里不再保留原始字节，避免大 code 撑爆明细。
#derive(Debug)
pub(all) struct Mismatch {
  address : @types.Address
  class : MismatchClass
  /// 仅槽级差异有值。
  slot : @types.U256?
  expected : String
  actual : String
}

///|
/// 一次账户级比对的结果：8 类计数 + 明细。
///
/// 计数是**字段/槽级**的：一个账户的 nonce 与 balance 都不对，就是 two 条。
/// 明细条数与计数一致（不像 `HarnessSummary.details` 那样截断）。
#derive(Debug)
pub(all) struct CompareReport {
  missing_accounts : Int32
  extra_accounts : Int32
  nonce_mismatches : Int32
  balance_mismatches : Int32
  code_mismatches : Int32
  missing_slots : Int32
  extra_slots : Int32
  slot_value_mismatches : Int32
  mismatches : Array[Mismatch]
}

///|
/// 两侧完全一致时为真。
pub fn CompareReport::is_match(self : CompareReport) -> Bool {
  self.missing_accounts == 0 &&
  self.extra_accounts == 0 &&
  self.nonce_mismatches == 0 &&
  self.balance_mismatches == 0 &&
  self.code_mismatches == 0 &&
  self.missing_slots == 0 &&
  self.extra_slots == 0 &&
  self.slot_value_mismatches == 0
}

// ---------------------------------------------------------------------------
// 文本摘要
// ---------------------------------------------------------------------------

///|
/// `U256` 的最小十六进制表示（不带前导零，零写 `0x0`）。
fn u256_brief(value : @types.U256) -> String {
  let bytes = value.to_bytes_be()
  let mut start = 0
  while start < 32 && bytes[start] == 0 {
    start = start + 1
  }
  if start == 32 {
    return "0x0"
  }
  let head = bytes[start]
  if head < 16 {
    // 首字节的高半字节是 0：只拼低半字节，其余字节整段转十六进制。
    "0x\{nibble_hex[head.to_int()]}\{@types.hex_encode(bytes[start + 1:])}"
  } else {
    "0x\{@types.hex_encode(bytes[start:])}"
  }
}

///|
/// code 的十六进制摘要；超过 `max_code_excerpt_bytes` 就截断并标注总长。
fn code_excerpt(code : Bytes) -> String {
  let length = code.length()
  if length <= max_code_excerpt_bytes {
    return "0x\{@types.hex_encode(code[:])}"
  }
  let head = code[:max_code_excerpt_bytes]
  "0x\{@types.hex_encode(head)}…(\{length} bytes)"
}

///|
/// 账户摘要：明细里回答「这个账户当时长什么样」。
fn account_brief(entry : @state.AccountEntry) -> String {
  "nonce=\{entry.info.nonce} balance=\{u256_brief(entry.info.balance)} code=\{code_excerpt(entry.info.code)} slots=\{entry.storage.length()}"
}

// ---------------------------------------------------------------------------
// alloc 转换
// ---------------------------------------------------------------------------

///|
/// `statetest.Alloc` → `state.AccountEntry` 数组，保持输入顺序，不做任何规范化。
///
/// 规范化（去 empty 账户、去零槽、排序）全部交给 `State::from_accounts`，这样
/// expected 与 actual 共用同一条路径，比对器不会自带第二套 empty/zero 规则。
pub fn alloc_entries(alloc : Alloc) -> Array[@state.AccountEntry] {
  let out : Array[@state.AccountEntry] = []
  for (address, account) in alloc.entries {
    let storage : Array[(@types.U256, @types.U256)] = []
    for (key, value) in account.storage {
      storage.push((key, value))
    }
    let info : @state.AccountInfo = {
      nonce: account.nonce,
      balance: account.balance,
      code: account.code,
    }
    out.push({ address, info, storage, })
  }
  out
}

///|
/// expected 侧的 canonical 形态：走一遍 `State::from_accounts(..).accounts()`。
///
/// 失败只有一种来源——alloc 自身不合法（重复地址、同一账户重复槽）。JSON loader
/// 已挡住重复键，所以正常语料走不到这里；真走到就记 `internal_errors`，不算 mismatch。
pub fn canonical_accounts(
  alloc : Alloc,
) -> Array[@state.AccountEntry] raise @state.StateError {
  let state = @state.State::from_accounts(alloc_entries(alloc))
  state.accounts()
}

// ---------------------------------------------------------------------------
// 账户级比对
// ---------------------------------------------------------------------------

///|
fn compare_entry(a : @state.AccountEntry, b : @state.AccountEntry) -> Int32 {
  a.address.compare(b.address)
}

///|
fn compare_slot_pair(
  a : (@types.U256, @types.U256),
  b : (@types.U256, @types.U256),
) -> Int32 {
  a.0.compare(b.0)
}

///|
/// 取一份按 key 升序的槽副本：不原地排序调用方的数组。
fn sorted_slots(
  entry : @state.AccountEntry,
) -> Array[(@types.U256, @types.U256)] {
  let out = entry.storage.copy()
  out.sort_by(compare_slot_pair)
  out
}

///|
/// 比较两组已排序的槽，明细追加进 `mismatches`，返回
/// `(missing, extra, value)` 三个计数。
fn compare_slots(
  address : @types.Address,
  expected : Array[(@types.U256, @types.U256)],
  actual : Array[(@types.U256, @types.U256)],
  mismatches : Array[Mismatch],
) -> (Int32, Int32, Int32) {
  let mut missing = 0
  let mut extra = 0
  let mut changed = 0
  let mut i = 0
  let mut j = 0
  while i < expected.length() || j < actual.length() {
    if i >= expected.length() {
      let (key, value) = actual[j]
      extra = extra + 1
      mismatches.push({
        address,
        class: ExtraSlot,
        slot: Some(key),
        expected: "0x0",
        actual: u256_brief(value),
      })
      j = j + 1
    } else if j >= actual.length() {
      let (key, value) = expected[i]
      missing = missing + 1
      mismatches.push({
        address,
        class: MissingSlot,
        slot: Some(key),
        expected: u256_brief(value),
        actual: "0x0",
      })
      i = i + 1
    } else {
      let (expected_key, expected_value) = expected[i]
      let (actual_key, actual_value) = actual[j]
      let order = expected_key.compare(actual_key)
      if order == 0 {
        if expected_value != actual_value {
          changed = changed + 1
          mismatches.push({
            address,
            class: SlotValue,
            slot: Some(expected_key),
            expected: u256_brief(expected_value),
            actual: u256_brief(actual_value),
          })
        }
        i = i + 1
        j = j + 1
      } else if order < 0 {
        missing = missing + 1
        mismatches.push({
          address,
          class: MissingSlot,
          slot: Some(expected_key),
          expected: u256_brief(expected_value),
          actual: "0x0",
        })
        i = i + 1
      } else {
        extra = extra + 1
        mismatches.push({
          address,
          class: ExtraSlot,
          slot: Some(actual_key),
          expected: "0x0",
          actual: u256_brief(actual_value),
        })
        j = j + 1
      }
    }
  }
  (missing, extra, changed)
}

///|
/// 账户级比对。两侧都先按地址排序（不改调用方数组），再逐账户比 nonce / balance /
/// code / 槽。输入顺序无关：排序后归并，结果只取决于集合内容。
///
/// 入参应是 canonical 形态（`accounts()` 或 `canonical_accounts` 的输出）；即便如此
/// 这里仍自己排一次序，因为本函数是公开的，不能假设调用方守规矩。
pub fn compare_accounts(
  expected_entries : Array[@state.AccountEntry],
  actual_entries : Array[@state.AccountEntry],
) -> CompareReport {
  let expected = expected_entries.copy()
  let actual = actual_entries.copy()
  expected.sort_by(compare_entry)
  actual.sort_by(compare_entry)
  let mismatches : Array[Mismatch] = []
  let mut missing_accounts = 0
  let mut extra_accounts = 0
  let mut nonce_mismatches = 0
  let mut balance_mismatches = 0
  let mut code_mismatches = 0
  let mut missing_slots = 0
  let mut extra_slots = 0
  let mut slot_value_mismatches = 0
  let mut i = 0
  let mut j = 0
  while i < expected.length() || j < actual.length() {
    let order = if i >= expected.length() {
      1
    } else if j >= actual.length() {
      -1
    } else {
      expected[i].address.compare(actual[j].address)
    }
    if order < 0 {
      missing_accounts = missing_accounts + 1
      mismatches.push({
        address: expected[i].address,
        class: MissingAccount,
        slot: None,
        expected: account_brief(expected[i]),
        actual: "absent",
      })
      i = i + 1
    } else if order > 0 {
      extra_accounts = extra_accounts + 1
      mismatches.push({
        address: actual[j].address,
        class: ExtraAccount,
        slot: None,
        expected: "absent",
        actual: account_brief(actual[j]),
      })
      j = j + 1
    } else {
      let left = expected[i]
      let right = actual[j]
      if left.info.nonce != right.info.nonce {
        nonce_mismatches = nonce_mismatches + 1
        mismatches.push({
          address: left.address,
          class: Nonce,
          slot: None,
          expected: left.info.nonce.to_string(),
          actual: right.info.nonce.to_string(),
        })
      }
      if left.info.balance != right.info.balance {
        balance_mismatches = balance_mismatches + 1
        mismatches.push({
          address: left.address,
          class: Balance,
          slot: None,
          expected: u256_brief(left.info.balance),
          actual: u256_brief(right.info.balance),
        })
      }
      if left.info.code != right.info.code {
        code_mismatches = code_mismatches + 1
        mismatches.push({
          address: left.address,
          class: Code,
          slot: None,
          expected: code_excerpt(left.info.code),
          actual: code_excerpt(right.info.code),
        })
      }
      let (missing, extra, changed) = compare_slots(
        left.address,
        sorted_slots(left),
        sorted_slots(right),
        mismatches,
      )
      missing_slots = missing_slots + missing
      extra_slots = extra_slots + extra
      slot_value_mismatches = slot_value_mismatches + changed
      i = i + 1
      j = j + 1
    }
  }
  {
    missing_accounts,
    extra_accounts,
    nonce_mismatches,
    balance_mismatches,
    code_mismatches,
    missing_slots,
    extra_slots,
    slot_value_mismatches,
    mismatches,
  }
}

// ---------------------------------------------------------------------------
// 汇总
// ---------------------------------------------------------------------------

///|
/// 一次 `run_harness` 的计数结果。
///
/// 前六个是 **case 级**（每个 case 只进一个桶）；中间八个是账户/字段/槽级的
/// mismatch 计数，与 case 级的 `fail` 不能相加。`diff_accounts` / `diff_slots` 是
/// 所有执行过的 case 的 `State::diff()` 之和，回答「执行回调到底改了什么」。
#derive(Debug)
pub(all) struct HarnessSummary {
  /// 选中的 case 总数（含 skip 与 internal error）。
  cases : Int32
  pass : Int32
  fail : Int32
  skipped_expected_invalid : Int32
  skipped_unsupported : Int32
  internal_errors : Int32
  missing_accounts : Int32
  extra_accounts : Int32
  nonce_mismatches : Int32
  balance_mismatches : Int32
  code_mismatches : Int32
  missing_slots : Int32
  extra_slots : Int32
  slot_value_mismatches : Int32
  diff_accounts : Int32
  diff_slots : Int32
  /// 明细行，最多 `max_detail_lines` 条。
  details : Array[String]
  /// 因上限被省略的明细条数（计数仍然完整）。
  details_omitted : Int32
}

///|
pub fn HarnessSummary::new() -> HarnessSummary {
  {
    cases: 0,
    pass: 0,
    fail: 0,
    skipped_expected_invalid: 0,
    skipped_unsupported: 0,
    internal_errors: 0,
    missing_accounts: 0,
    extra_accounts: 0,
    nonce_mismatches: 0,
    balance_mismatches: 0,
    code_mismatches: 0,
    missing_slots: 0,
    extra_slots: 0,
    slot_value_mismatches: 0,
    diff_accounts: 0,
    diff_slots: 0,
    details: [],
    details_omitted: 0,
  }
}

// ---------------------------------------------------------------------------
// 明细行
// ---------------------------------------------------------------------------

///|
/// 明细行骨架：`case=<name> fork=<fork> indexes=<...> class=<...> <detail>`。
fn detail_line(
  fixture_name : String,
  fork : String,
  indexes : String,
  class : String,
  detail : String,
) -> String {
  "case=\{fixture_name} fork=\{fork} indexes=\{indexes} class=\{class} \{detail}"
}

///|
fn mismatch_line(case : Case, mismatch : Mismatch) -> String {
  let slot = match mismatch.slot {
    Some(key) => " slot=\{u256_brief(key)}"
    None => ""
  }
  detail_line(
    case.fixture_name,
    case.fork,
    case.indexes.to_string(),
    mismatch.class.to_string(),
    "address=\{mismatch.address.to_hex()}\{slot} expected=\{mismatch.expected} actual=\{mismatch.actual}",
  )
}

///|
fn push_detail(summary : HarnessSummary, line : String) -> HarnessSummary {
  if summary.details.length() >= max_detail_lines {
    return { ..summary, details_omitted: summary.details_omitted + 1, }
  }
  let details = summary.details.copy()
  details.push(line)
  { ..summary, details, }
}

///|
/// 记一条 harness 自身的问题（展开失败、alloc 转换失败），计入 `internal_errors`。
fn record_internal(summary : HarnessSummary, line : String) -> HarnessSummary {
  let counted = { ..summary, internal_errors: summary.internal_errors + 1, }
  push_detail(counted, line)
}

///|
/// `state` 的错误只有三种，这里翻成中文可读的短语（`StateError` 没有 `Show`）。
fn describe_state_error(error : @state.StateError) -> String {
  match error {
    DuplicateAccount(address~) => "duplicate account \{address.to_hex()}"
    DuplicateStorageKey(address~, key~) =>
      "duplicate storage key \{u256_brief(key)} for \{address.to_hex()}"
    InvalidSnapshot => "invalid snapshot handle"
  }
}

// ---------------------------------------------------------------------------
// 流水线
// ---------------------------------------------------------------------------

///|
/// `State::from_accounts` 的结果；`StateError` 不是 suberror 之外的东西，单独装桶
/// 才能在同一个 `match` 里和成功路径共存。
priv enum BuildOutcome {
  Built(@state.State)
  BuildFailed(@state.StateError)
}

///|
/// expected alloc → canonical 账户表的结果。
priv enum CanonicalOutcome {
  Canonical(Array[@state.AccountEntry])
  CanonicalFailed(@state.StateError)
}

///|
/// 该 tx 类型是否属于「还没做」：v0 只有 EIP-7702 的 type 4。
///
/// 不用 `==` 判等：`TxType` 没有 `Eq` 实例，而这里也不该为了一次比较去加一个。
fn is_unsupported_type(tx_type : TxType) -> Bool {
  match tx_type {
    Type4 => true
    Legacy | Type1 | Type2 | Type3 => false
  }
}

///|
/// 跑一张 fixture 表在 `fork` 下的全部 case。
///
/// 每个**执行过的** case 都新建一个 `State`（从 `fixture.pre` 构造），调用
/// `execute(case, state)`，再与 `post[fork][i].state` 的 canonical 形态比对。
/// `execute` 不允许抛错：v0 只允许它写状态，返回 `Unit`。
///
/// case 级失败与 harness 自身失败都不中断整批：一个 case 记一笔，继续下一个。
pub fn run_harness(
  fixtures : Array[Fixture],
  fork : String,
  execute : (Case, @state.State) -> Unit,
) -> HarnessSummary {
  let mut summary = HarnessSummary::new()
  for fixture in fixtures {
    match fixture.post_for(fork) {
      None => ()
      Some(entries) =>
        for index in 0..<entries.length() {
          summary = { ..summary, cases: summary.cases + 1, }
          let outcome : ExpandOutcome = Expanded(
            expand_case(fixture, fork, entries, index),
          ) catch {
            e => ExpandFailed(e)
          }
          match outcome {
            ExpandFailed(e) =>
              summary = record_internal(
                summary,
                detail_line(
                  fixture.name,
                  fork,
                  entries[index].indexes.to_string(),
                  "internal",
                  "expand: \{e.to_string()}",
                ),
              )
            Expanded(case) =>
              if case.expect_exception.length() > 0 {
                // 该拒绝的交易：不执行、不比对。语义判定属 C12/D03。
                // 与 type 4 同时命中时按这里归类——fixture 自己声明该被拒绝，
                // 那就连「支不支持这种 tx」都轮不到判。
                summary = {
                  ..summary,
                  skipped_expected_invalid: summary.skipped_expected_invalid + 1,
                }
              } else if is_unsupported_type(case.tx_type) {
                // EIP-7702 的授权列表要 P02 才解得了；这里只承认「没做」。
                summary = {
                  ..summary,
                  skipped_unsupported: summary.skipped_unsupported + 1,
                }
              } else {
                summary = run_one(
                  fixture,
                  case,
                  entries[index],
                  execute,
                  summary,
                )
              }
          }
        }
    }
  }
  summary
}

///|
/// 单个 case 的执行 + 比对。`fixture.pre` → `State` 失败直接记 internal error：
/// 那是 fixture 自身不合法（重复账户/重复槽），不是执行结果。
fn run_one(
  fixture : Fixture,
  case : Case,
  entry : PostEntry,
  execute : (Case, @state.State) -> Unit,
  summary : HarnessSummary,
) -> HarnessSummary {
  let built : BuildOutcome = Built(
    @state.State::from_accounts(alloc_entries(fixture.pre)),
  ) catch {
    e => BuildFailed(e)
  }
  let state = match built {
    BuildFailed(e) =>
      return record_internal(
        summary,
        detail_line(
          case.fixture_name,
          case.fork,
          case.indexes.to_string(),
          "internal",
          "pre: \{describe_state_error(e)}",
        ),
      )
    Built(state) => state
  }
  execute(case, state)
  let actual = state.accounts()
  let diff = state.diff()
  let mut diff_slots = 0
  for account in diff.accounts {
    diff_slots = diff_slots + account.storage.length()
  }
  let canonical : CanonicalOutcome = Canonical(canonical_accounts(entry.state)) catch {
    e => CanonicalFailed(e)
  }
  let expected = match canonical {
    CanonicalFailed(e) =>
      return record_internal(
        summary,
        detail_line(
          case.fixture_name,
          case.fork,
          case.indexes.to_string(),
          "internal",
          "post.state: \{describe_state_error(e)}",
        ),
      )
    Canonical(entries) => entries
  }
  let report = compare_accounts(expected, actual)
  let passed = report.is_match()
  let counted = {
    ..summary,
    pass: summary.pass + (if passed { 1 } else { 0 }),
    fail: summary.fail + (if passed { 0 } else { 1 }),
    missing_accounts: summary.missing_accounts + report.missing_accounts,
    extra_accounts: summary.extra_accounts + report.extra_accounts,
    nonce_mismatches: summary.nonce_mismatches + report.nonce_mismatches,
    balance_mismatches: summary.balance_mismatches + report.balance_mismatches,
    code_mismatches: summary.code_mismatches + report.code_mismatches,
    missing_slots: summary.missing_slots + report.missing_slots,
    extra_slots: summary.extra_slots + report.extra_slots,
    slot_value_mismatches: summary.slot_value_mismatches +
    report.slot_value_mismatches,
    diff_accounts: summary.diff_accounts + diff.accounts.length(),
    diff_slots: summary.diff_slots + diff_slots,
  }
  let mut out = counted
  for mismatch in report.mismatches {
    out = push_detail(out, mismatch_line(case, mismatch))
  }
  out
}

// ---------------------------------------------------------------------------
// 退出码
// ---------------------------------------------------------------------------

///|
/// 退出码判定的纯函数（`main` 里不再散落条件）。只返回 0/1：2 表示用法或 IO 错误，
/// 由 CLI 在解析参数、读文件时直接给，不经过这里。
///
/// - tx 流水线不干净（error / resign mismatch / unsupported）→ 1；
/// - harness 自身出错（internal）→ 1；
/// - `strict` 时 state fail 也算红（G1 起用）；默认**不算**——P0 是 stub，
///   「执行未实现」不能把 CI 打红。
pub fn exit_code(
  tx : Summary,
  harness : HarnessSummary,
  strict : Bool,
) -> Int32 {
  if !tx.is_clean() {
    return 1
  }
  if harness.internal_errors > 0 {
    return 1
  }
  if strict && harness.fail > 0 {
    return 1
  }
  0
}
