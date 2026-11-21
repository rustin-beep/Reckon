// 纯函数流水线：load -> expand -> decode -> check -> Summary。
//
// 不碰文件系统、不执行 EVM；所有失败都落进 `Summary.errors`，不中断整批扫描。
// `--fork` 不存在是整个文档级的错误（`FixtureError::ForkNotFound`），因为那时
// 一个 case 都选不出来。

// ---------------------------------------------------------------------------
// 汇总
// ---------------------------------------------------------------------------

///|
/// 一次 `run_document` 的计数结果。
///
/// `txbytes_present` 统计「字段存在且非空」的 case 数；解码失败的也算 present
/// （字节确实在，只是解不开），同时进 `errors`。
#derive(Debug)
pub(all) struct Summary {
  cases : Int32
  legacy : Int32
  type1 : Int32
  type2 : Int32
  type3 : Int32
  unsupported : Int32
  txbytes_present : Int32
  txbytes_missing : Int32
  resign_ok : Int32
  resign_mismatch : Int32
  resign_skipped : Int32
  resign_expected_invalid : Int32
  sender_ok : Int32
  sender_mismatch : Int32
  error_count : Int32
  errors : Array[String]
}

///|
pub fn Summary::new() -> Summary {
  {
    cases: 0,
    legacy: 0,
    type1: 0,
    type2: 0,
    type3: 0,
    unsupported: 0,
    txbytes_present: 0,
    txbytes_missing: 0,
    resign_ok: 0,
    resign_mismatch: 0,
    resign_skipped: 0,
    resign_expected_invalid: 0,
    sender_ok: 0,
    sender_mismatch: 0,
    error_count: 0,
    errors: [],
  }
}

///|
/// 成功判据：没有 mismatch、没有解码错误、没有 unsupported。
pub fn Summary::is_clean(self : Summary) -> Bool {
  self.error_count == 0 && self.resign_mismatch == 0 && self.unsupported == 0
}

///|
/// 记一条错误（`class` 是分类标签，`detail` 是具体信息）。
fn push_error(
  summary : Summary,
  case : Case,
  class : String,
  detail : String,
) -> Summary {
  let line = "case=\{case.fixture_name} fork=\{case.fork} entry=\{case.entry_index} indexes=\{case.indexes} class=\{class} \{detail}"
  let errors = summary.errors.copy()
  errors.push(line)
  { ..summary, error_count: summary.error_count + 1, errors, }
}

// ---------------------------------------------------------------------------
// 展开
// ---------------------------------------------------------------------------

///|
/// 按 `indexes` 从模板里选出一笔具体的交易。
pub fn expand_case(
  fixture : Fixture,
  fork : String,
  entries : Array[PostEntry],
  entry_index : Int32,
) -> Case raise FixtureError {
  let entry = entries[entry_index]
  let tx = fixture.tx
  let path = "\{fixture.name}#\{fork}#\{entry_index}"
  let data_index = entry.indexes.data
  let gas_index = entry.indexes.gas
  let value_index = entry.indexes.value
  if data_index >= tx.datas.length() {
    raise FixtureError::IndexOutOfRange(
      path~,
      field="indexes.data",
      value=data_index,
      limit=tx.datas.length(),
    )
  }
  if gas_index >= tx.gas_limits.length() {
    raise FixtureError::IndexOutOfRange(
      path~,
      field="indexes.gas",
      value=gas_index,
      limit=tx.gas_limits.length(),
    )
  }
  if value_index >= tx.values.length() {
    raise FixtureError::IndexOutOfRange(
      path~,
      field="indexes.value",
      value=value_index,
      limit=tx.values.length(),
    )
  }
  let access_list = select_access_list(tx, data_index, path)
  {
    fixture_name: fixture.name,
    fork,
    entry_index,
    indexes: entry.indexes,
    tx_type: tx.tx_type,
    nonce: tx.nonce,
    gas_price: tx.gas_price,
    max_priority_fee_per_gas: tx.max_priority_fee_per_gas,
    max_fee_per_gas: tx.max_fee_per_gas,
    gas_limit: tx.gas_limits[gas_index],
    value: tx.values[value_index],
    data: tx.datas[data_index],
    access_list,
    to: tx.to,
    max_fee_per_blob_gas: tx.max_fee_per_blob_gas,
    blob_versioned_hashes: tx.blob_versioned_hashes,
    txbytes: entry.txbytes,
    txbytes_field_present: entry.txbytes_field_present,
    expect_exception: entry.expect_exception,
  }
}

///|
/// `accessLists` 选择规则（对应 evmone `access_lists.at(indexes.input)`）：
///   - 字段缺失或为空 -> 空列表；
///   - 只有一条 -> 全部 `data` 共用这一条（evmone 的 `.at()` 在 `data > 0` 时会越界，
///     EEST 不会产出这种组合，这里按共用处理）；
///   - 条数等于 `data` 数组长度 -> 按 `indexes.data` 取；
///   - 其余 -> `AccessListArity`。
fn select_access_list(
  tx : TxTemplate,
  data_index : Int32,
  path : String,
) -> Array[AccessTuple] raise FixtureError {
  match tx.access_lists {
    None => []
    Some(lists) =>
      if lists.length() == 0 {
        []
      } else if lists.length() == 1 {
        lists[0]
      } else if lists.length() == tx.datas.length() {
        lists[data_index]
      } else {
        raise FixtureError::AccessListArity(
          path~,
          lists=lists.length(),
          inputs=tx.datas.length(),
        )
      }
  }
}

// ---------------------------------------------------------------------------
// 单个 case
// ---------------------------------------------------------------------------

///|
/// `decode_tx` 的结果。不复用 `Result`：`ResignOutcome::Ok` 与 `Result::Ok`
/// 在同一个 `match` 里会互相遮蔽。
priv enum DecodeOutcome {
  Decoded(DecodedTx)
  Failed(TxError)
}

///|
fn count_type(summary : Summary, tx_type : TxType) -> Summary {
  match tx_type {
    Legacy => { ..summary, legacy: summary.legacy + 1, }
    Type1 => { ..summary, type1: summary.type1 + 1, }
    Type2 => { ..summary, type2: summary.type2 + 1, }
    Type3 => { ..summary, type3: summary.type3 + 1, }
    Type4 => { ..summary, unsupported: summary.unsupported + 1, }
  }
}

///|
fn run_case(fixture : Fixture, case : Case, summary : Summary) -> Summary {
  let mut s = { ..summary, cases: summary.cases + 1, }
  let raw = match case.txbytes {
    None =>
      return {
        ..s,
        txbytes_missing: s.txbytes_missing + 1,
        resign_skipped: s.resign_skipped + 1,
      }
    Some(b) => b
  }
  s = { ..s, txbytes_present: s.txbytes_present + 1, }
  let decoded : DecodeOutcome = Decoded(decode_tx(raw[:])) catch {
    e => Failed(e)
  }
  let tx = match decoded {
    Failed(UnsupportedType(_)) =>
      return { ..s, unsupported: s.unsupported + 1, }
    Failed(e) => return push_error(s, case, "decode", e.to_string())
    Decoded(tx) => tx
  }
  s = count_type(s, tx.tx_type)
  // JSON 向量 vs 解码字段：与签名无关，先查。
  let field_diffs = check_fields(case, tx, fixture.chain_id)
  for diff in field_diffs {
    s = push_error(s, case, "fields", diff)
  }
  // 签名是否构得上「一个可恢复的签名」。invalid fixture 会在这里失败。
  let recovered = recover_sender(tx)
  let has_expectation = case.expect_exception.length() > 0
  let signature_usable = match recovered {
    Some(_) => true
    None => false
  }
  if !signature_usable {
    if has_expectation {
      return { ..s, resign_expected_invalid: s.resign_expected_invalid + 1, }
    }
    return push_error(
      s, case, "recover", "signature cannot be recovered and the case declares no expectException",
    )
  }
  // sender：key -> 地址、recover -> 地址，两者都必须等于 fixture 的 sender。
  let key_address = address_from_secret_key(fixture.tx.secret_key)
  let key_ok = match key_address {
    Some(a) => a == fixture.tx.sender
    None => false
  }
  let recover_ok = match recovered {
    Some(a) => a == fixture.tx.sender
    None => false
  }
  if key_ok && recover_ok {
    s = { ..s, sender_ok: s.sender_ok + 1, }
  } else {
    s = { ..s, sender_mismatch: s.sender_mismatch + 1, }
    if !key_ok {
      s = push_error(
        s,
        case,
        "sender",
        "secretKey does not derive fixture sender \{fixture.tx.sender.to_hex()}",
      )
    }
    if !recover_ok {
      s = push_error(
        s,
        case,
        "sender",
        "recover(signature) does not match fixture sender \{fixture.tx.sender.to_hex()}",
      )
    }
  }
  // 重签 + 逐字节比对。
  match resign(tx, raw[:], fixture.tx.secret_key) {
    ResignOutcome::Ok => { ..s, resign_ok: s.resign_ok + 1, }
    ResignOutcome::Mismatch(offset~, expected~, actual~) => {
      let s = { ..s, resign_mismatch: s.resign_mismatch + 1, }
      push_error(
        s,
        case,
        "resign",
        "byte \{offset}: re-encoded \{expected} vs txbytes \{actual}",
      )
    }
    ResignOutcome::Skipped => { ..s, resign_skipped: s.resign_skipped + 1, }
    ResignOutcome::ExpectedInvalid(reason~) => {
      let s = { ..s, resign_expected_invalid: s.resign_expected_invalid + 1, }
      // 已在上面的 recover 分支处理过；这里保留以防 decode 之后签名判定变化。
      push_error(s, case, "resign", "unexpected: \{reason}")
    }
    ResignOutcome::Invalid(reason~) =>
      push_error(s, case, "resign", "sign failed: \{reason}")
  }
}

// ---------------------------------------------------------------------------
// 文档级入口
// ---------------------------------------------------------------------------

///|
/// 跑一份文档里的所有 fixture，只保留 `fork` 下的 case。
///
/// `fork` 在整个文档里都不存在时抛 `ForkNotFound`（带可用 fork 列表）；
/// 单个 fixture 不含该 fork 只表示「它不贡献 case」，不是错误。
pub fn run_document(
  fixtures : Array[Fixture],
  fork : String,
) -> Summary raise FixtureError {
  let available : Array[String] = []
  let mut fork_present = false
  for fixture in fixtures {
    for name in fixture.forks() {
      if !contains_string(available, name) {
        available.push(name)
      }
    }
    match fixture.post_for(fork) {
      Some(_) => fork_present = true
      None => ()
    }
  }
  if !fork_present {
    available.sort()
    raise FixtureError::ForkNotFound(fork~, available~)
  }
  let mut summary = Summary::new()
  for fixture in fixtures {
    match fixture.post_for(fork) {
      None => ()
      Some(entries) =>
        for i in 0..<entries.length() {
          let case = expand_case(fixture, fork, entries, i)
          summary = run_case(fixture, case, summary)
        }
    }
  }
  summary
}

///|
fn contains_string(items : Array[String], needle : String) -> Bool {
  for item in items {
    if item == needle {
      return true
    }
  }
  false
}
