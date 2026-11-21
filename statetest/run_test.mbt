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
  assert_eq(summary.resign_expected_invalid, 0)
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
test "run_document reports indexes out of range" {
  let doc = with_change(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 3, \"gas\": 0, \"value\": 0}",
  )
  match run_error(doc, "Cancun") {
    Some(@statetest.IndexOutOfRange(field~, value~, limit~, ..)) => {
      assert_eq(field, "indexes.data")
      assert_eq(value, 3)
      assert_eq(limit, 1)
    }
    Some(other) => abort("expected IndexOutOfRange, got \{other.to_string()}")
    None => abort("expected IndexOutOfRange, got Ok")
  }
}

///|
test "run_document reports access list arity mismatch" {
  // type2 模板 + 两条 accessLists，但 data 只有一条。
  let with_fees = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",",
  )
  let doc = with_fees.replace_all(
    old="\"data\": [\"0x\"],",
    new="\"data\": [\"0x\"],\n  \"accessLists\": [[], []],",
  )
  match run_error(doc, "Cancun") {
    Some(@statetest.AccessListArity(lists~, inputs~, ..)) => {
      assert_eq(lists, 2)
      assert_eq(inputs, 1)
    }
    Some(other) => abort("expected AccessListArity, got \{other.to_string()}")
    None => abort("expected AccessListArity, got Ok")
  }
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
