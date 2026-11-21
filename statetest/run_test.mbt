// 端到端流水线测试：parse -> expand -> decode -> check -> Summary。
//
// 全部数据来自本文件的合成 JSON（`json_loader_test.mbt` 的 `base_doc()`），
// 只有 `txbytes` 是 EEST v5.4.0 stable 的真实字节——重签必须逐字节一致，
// 用真实字节才有意义。

///|
fn run_summary(doc : String, fork : String) -> @statetest.Summary {
  let fixtures = @statetest.parse_document(doc) catch {
    e => abort("parse failed: \{e.to_string()}")
  }
  @statetest.run_document(fixtures, fork) catch {
    e => abort("unexpected error: \{e.to_string()}")
  }
}

///|
fn has_error(summary : @statetest.Summary, needle : StringView) -> Bool {
  for line in summary.errors {
    if line.contains(needle) {
      return true
    }
  }
  false
}

///|
fn run_error(doc : String, fork : String) -> @statetest.FixtureError? {
  let fixtures = @statetest.parse_document(doc) catch {
    e => abort("parse failed: \{e.to_string()}")
  }
  try {
    let _ = @statetest.run_document(fixtures, fork)
    None
  } catch {
    e => Some(e)
  }
}

///|
test "run_document counts a clean Cancun case" {
  let summary = run_summary(base_doc(), "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.legacy, 1)
  assert_eq(summary.type1, 0)
  assert_eq(summary.type2, 0)
  assert_eq(summary.type3, 0)
  assert_eq(summary.unsupported, 0)
  assert_eq(summary.txbytes_present, 1)
  assert_eq(summary.txbytes_missing, 0)
  assert_eq(summary.resign_ok, 1)
  assert_eq(summary.resign_mismatch, 0)
  assert_eq(summary.resign_skipped, 0)
  assert_eq(summary.expected_invalid, 0)
  assert_eq(summary.sender_ok, 1)
  assert_eq(summary.sender_mismatch, 0)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.is_clean(), true)
}

///|
test "run_document skips a case without txbytes" {
  let doc = with_change(
    old="\"txbytes\": \"0xf860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0\"",
    new="\"txbytes\": \"0x\"",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.txbytes_present, 0)
  assert_eq(summary.txbytes_missing, 1)
  assert_eq(summary.resign_skipped, 1)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.is_clean(), true)
}

///|
test "run_document reports a resign mismatch" {
  // 改掉 txbytes 里 gasLimit 的最后一个字节：签名本身仍有效（r/s 没动），
  // 但用原签名重编码后与 txbytes 不同，必须报 mismatch 而不是静默通过。
  let doc = with_change(old="834c4b40", new="834c4b41")
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.resign_ok, 0)
  assert_eq(summary.resign_mismatch, 1)
  assert_true(summary.error_count > 0)
  assert_true(has_error(summary, "class=resign"))
  assert_eq(summary.is_clean(), false)
}

///|
test "run_document reports a sender mismatch" {
  // 把 sender 换成另一个地址：key 与 recover 都对不上。
  let doc = with_change(
    old="\"sender\": \"0x766b923079c2900993bafa89b07d66423481776e\"",
    new="\"sender\": \"0x0000000000000000000000000000000000000001\"",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.sender_ok, 0)
  assert_eq(summary.sender_mismatch, 1)
  assert_true(summary.error_count >= 2)
  assert_true(has_error(summary, "class=sender"))
  assert_eq(summary.is_clean(), false)
}

///|
test "run_document reports a field mismatch" {
  // JSON 的 gasLimit 与 txbytes 不一致。
  let doc = with_change(
    old="\"gasLimit\": [\"0x4c4b40\"],",
    new="\"gasLimit\": [\"0x4c4b41\"],",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.resign_ok, 1)
  assert_true(summary.error_count > 0)
  assert_true(has_error(summary, "class=fields"))
  assert_true(has_error(summary, "gasLimit"))
}

///|
test "run_document reports unsupported type 4" {
  // txbytes 换成 0x04 开头的 envelope。
  let doc = with_change(
    old="\"txbytes\": \"0xf860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0\"",
    new="\"txbytes\": \"0x04c0\"",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.unsupported, 1)
  assert_eq(summary.resign_ok, 0)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.is_clean(), false)
}

///|
test "run_document records an indexes-out-of-range case as an error" {
  // 展开失败不该把整批带下去：记一条 class=expand 错误，其余 case 继续。
  let doc = with_change(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 3, \"gas\": 0, \"value\": 0}",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.error_count, 1)
  assert_true(has_error(summary, "class=expand"))
  assert_true(has_error(summary, "indexes.data"))
  assert_true(has_error(summary, "limit 1"))
  assert_eq(summary.is_clean(), false)
}

///|
test "run_document records access list arity mismatch as an error" {
  // type2 模板 + 两条 accessLists，但 data 只有一条。
  let with_fees = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",",
  )
  let doc = with_fees.replace_all(
    old="\"data\": [\"0x\"],",
    new="\"data\": [\"0x\"],\n  \"accessLists\": [[], []],",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.error_count, 1)
  assert_true(has_error(summary, "class=expand"))
  assert_true(has_error(summary, "accessLists"))
}

///|
test "run_document reports an unknown fork with the available list" {
  match run_error(base_doc(), "Osaka") {
    Some(@statetest.ForkNotFound(fork~, available~)) => {
      assert_eq(fork, "Osaka")
      assert_eq(available.length(), 1)
      assert_eq(available[0], "Cancun")
    }
    Some(other) => abort("expected ForkNotFound, got \{other.to_string()}")
    None => abort("expected ForkNotFound, got Ok")
  }
}

///|
test "expand_case picks access list by indexes.data" {
  // type2 模板 + 两条 data + 两条 accessLists：indexes.data = 1 必须选第二条。
  let with_fees = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",",
  )
  let doc = with_fees
    .replace_all(
      old="\"data\": [\"0x\"],",
      new="\"data\": [\"0x\", \"0xdead\"],",
    )
    .replace_all(
      old="\"gasLimit\": [\"0x4c4b40\"],",
      new="\"gasLimit\": [\"0x4c4b40\"],\n  \"accessLists\": [\n    [{\"address\": \"0x0000000000000000000000000000000000000001\", \"storageKeys\": []}],\n    [{\"address\": \"0x0000000000000000000000000000000000000002\", \"storageKeys\": []}]\n  ],",
    )
  let doc1 = doc.replace_all(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 1, \"gas\": 0, \"value\": 0}",
  )
  let fixtures = @statetest.parse_document(doc1)
  let fixture = fixtures[0]
  let entries = fixture.post_for("Cancun").unwrap()
  let case = @statetest.expand_case(fixture, "Cancun", entries, 0)
  assert_eq(case.data.length(), 2)
  assert_eq(case.access_list.length(), 1)
  assert_eq(
    case.access_list[0].address.to_hex(),
    "0x0000000000000000000000000000000000000002",
  )
}

///|
test "summary of 128 type3 cases stays clean" {
  // 与真实 fixture 同规模：128 个 entry，全部 type3。这里只造 8 个，
  // 目的是验证「多 entry」不会互相污染。
  let mut entries = ""
  for i in 0..<8 {
    if i > 0 {
      entries = entries + ","
    }
    entries = entries +
      "{\"hash\":\"0x0000000000000000000000000000000000000000000000000000000000000001\",\"logs\":\"0x0000000000000000000000000000000000000000000000000000000000000002\",\"indexes\":{\"data\":0,\"gas\":0,\"value\":0},\"state\":{},\"txbytes\":\"0x\"}"
  }
  let doc = with_change(
    old="\"Cancun\": [",
    new="\"Cancun\": [" + entries + ", ",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 9)
  assert_eq(summary.txbytes_missing, 8)
  assert_eq(summary.resign_skipped, 8)
  assert_eq(summary.resign_ok, 1)
  assert_eq(summary.error_count, 0)
}

///|
/// 在 `base_doc()` 里给 post entry 插入一条 `expectException`。
fn with_expectation(doc : String, value : String) -> String {
  doc.replace_all(
    old="\"txbytes\":",
    new="\"expectException\": \"" + value + "\",\n      \"txbytes\":",
  )
}

///|
/// 把 legacy 向量换成 high-s + yParity 翻转的版本。
///
/// 这组字节由独立 Python oracle 生成（s -> n-s，legacy v 37 -> 38）：
/// `recover` 仍能还原出 fixture 的 sender，但用 low-s 重签再编码必然对不上，
/// 所以它是「resign 不一致而 sender 正常」的最小构造。
let high_s_txbytes : String = "f860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808026a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa0ccc9a7d4a3066462aa7ab6d821325805df93b5e346fdb239fb13c20c1d953881"

///|
let low_s_txbytes : String = "f860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0"

///|
test "run_document treats a high-s resign mismatch as expected when declared" {
  let doc = with_expectation(
    with_change(old=low_s_txbytes, new=high_s_txbytes),
    "TransactionException.INVALID_SIGNATURE",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  // recover 仍成功，sender 一致——所以这确实是「只有签名层面对不上」的 case。
  assert_eq(summary.sender_ok, 1)
  assert_eq(summary.sender_mismatch, 0)
  assert_eq(summary.expected_invalid, 1)
  assert_eq(summary.resign_mismatch, 0)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.is_clean(), true)
  assert_eq(summary.expected.length(), 1)
  assert_true(summary.expected[0].contains("class=resign"))
}

///|
test "run_document treats an invalid legacy v as expected when declared" {
  // v = 37 -> 29：既不是 27/28 也不是 >= 35，decode 阶段就拒绝。
  let invalid_v = low_s_txbytes.replace_all(old="808025a0", new="80801da0")
  let doc = with_expectation(
    with_change(old=low_s_txbytes, new=invalid_v),
    "TransactionException.INVALID_SIGNATURE_VRS",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.expected_invalid, 1)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.resign_ok, 0)
  assert_eq(summary.is_clean(), true)
  assert_eq(summary.expected.length(), 1)
  assert_true(summary.expected[0].contains("class=decode"))
  assert_true(summary.expected[0].contains("legacy tx v="))
}

///|
test "run_document does not compare tx chainId with config chainId" {
  // EEST 的 transaction 没有 chainId 字段；`tx.chainId != config.chainid` 是
  // consensus 判定（C12），不是 JSON 向量核对。把 config 改成 0x02 不应报错。
  let doc = with_change(
    old="\"chainid\": \"0x01\"",
    new="\"chainid\": \"0x02\"",
  )
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.cases, 1)
  assert_eq(summary.error_count, 0)
  assert_eq(summary.resign_ok, 1)
  assert_eq(summary.is_clean(), true)
}

///|
test "run_document without expectException still fails on an invalid v" {
  // 同一份坏字节，去掉 expectException 就必须是错误（对照组）。
  let invalid_v = low_s_txbytes.replace_all(old="808025a0", new="80801da0")
  let doc = with_change(old=low_s_txbytes, new=invalid_v)
  let summary = run_summary(doc, "Cancun")
  assert_eq(summary.error_count, 1)
  assert_eq(summary.expected_invalid, 0)
  assert_true(has_error(summary, "class=decode"))
  assert_eq(summary.is_clean(), false)
}
