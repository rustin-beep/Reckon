// harness v0 测试：alloc 归一、账户级比对分类、执行流水线、退出码。
//
// 分两层：
//   - 阶段 1 的用例直接构造 `@state.AccountEntry` / `@statetest.Alloc`，不经过 JSON，
//     每条只钉一个语义（缺账户 / 缺槽 / 归一 / 顺序无关 / 截断）；
//   - 阶段 2 的用例复用 `json_loader_test.mbt` 的 `base_doc()`（EEST 真实形状的合成
//     文档），用 fake executor 验证 pass 路径与 skip 分支。
//
// fake executor 只存在于本文件：生产路径没有任何把 `post.state` 写回 actual 的入口。

// ---------------------------------------------------------------------------
// 构造辅助
// ---------------------------------------------------------------------------

///|
fn hex_digit_of(value : Int32) -> String {
  let digits : Array[String] = [
    "0", "1", "2", "3", "4", "5", "6", "7", "8", "9", "a", "b", "c", "d", "e", "f",
  ]
  digits[value]
}

///|
/// 0–255 的两位十六进制。
fn hex_byte_of(value : Int32) -> String {
  hex_digit_of(value / 16) + hex_digit_of(value % 16)
}

///|
fn addr(text : String) -> @types.Address {
  @types.Address::from_hex(text) catch {
    _ => abort("test address is not valid hex: \{text}")
  }
}

///|
fn word(text : String) -> @types.U256 {
  @types.U256::from_hex(text) catch {
    _ => abort("test word is not valid hex: \{text}")
  }
}

///|
/// 地址 `0x00..00<index>`：末字节取 `index`，便于批量造账户。
fn indexed_addr(index : Int32) -> @types.Address {
  let mut text = "0x"
  for _ in 0..<38 {
    text = text + "0"
  }
  addr(text + hex_byte_of(index))
}

///|
fn info_of(
  nonce : UInt64,
  balance : @types.U256,
  code : Bytes,
) -> @state.AccountInfo {
  { nonce, balance, code, }
}

///|
fn entry_of(
  address : @types.Address,
  info : @state.AccountInfo,
  storage : Array[(@types.U256, @types.U256)],
) -> @state.AccountEntry {
  { address, info, storage, }
}

///|
fn alloc_of(
  entries : Array[(@types.Address, @statetest.AccountAlloc)],
) -> @statetest.Alloc {
  { entries, }
}

///|
fn alloc_account(
  nonce : UInt64,
  balance : @types.U256,
  code : Bytes,
  storage : Array[(@types.U256, @types.U256)],
) -> @statetest.AccountAlloc {
  { nonce, balance, code, storage, }
}

///|
/// 把 expected alloc 原样写进 state：先删掉 expected 里没有的账户，再逐字段写入。
///
/// 只有测试能用这种做法——它是「假装执行器已经正确执行完毕」，生产路径没有这个开关。
fn apply_alloc(state : @state.State, alloc : @statetest.Alloc) -> Unit {
  for entry in state.accounts() {
    match alloc.lookup(entry.address) {
      None => state.destroy_account(entry.address)
      Some(_) => ()
    }
  }
  for (address, account) in alloc.entries {
    state.set_nonce(address, account.nonce)
    state.set_balance(address, account.balance)
    state.set_code(address, account.code)
    for (key, value) in account.storage {
      state.set_storage(address, key, value)
    }
  }
}

///|
fn parse_one(doc : String) -> @statetest.Fixture {
  let fixtures = @statetest.parse_document(doc) catch {
    e => abort("parse failed: \{e.to_string()}")
  }
  fixtures[0]
}

///|
fn harness_of(
  doc : String,
  execute : (@statetest.Case, @state.State) -> Unit,
) -> @statetest.HarnessSummary {
  let fixtures = @statetest.parse_document(doc) catch {
    e => abort("parse failed: \{e.to_string()}")
  }
  @statetest.run_harness(fixtures, "Cancun", execute)
}

///|
fn no_op(_case : @statetest.Case, _state : @state.State) -> Unit {
  ()
}

// ---------------------------------------------------------------------------
// 阶段 1：alloc 归一
// ---------------------------------------------------------------------------

///|
test "canonical_accounts 丢掉 empty 账户与零槽并按地址排序" {
  let dirty = alloc_of([
    (indexed_addr(3), alloc_account(0UL, word("0x00"), b"", [])),
    (
      indexed_addr(2),
      alloc_account(1UL, word("0x00"), b"", [(word("0x01"), word("0x00"))]),
    ),
    (
      indexed_addr(1),
      alloc_account(0UL, word("0x00"), b"\x01", [(word("0x05"), word("0x07"))]),
    ),
  ])
  let canonical = @statetest.canonical_accounts(dirty) catch {
    _ => abort("canonical form failed")
  }
  // 3 号账户是 empty：不导出。
  assert_eq(canonical.length(), 2)
  assert_eq(canonical[0].address, indexed_addr(1))
  assert_eq(canonical[1].address, indexed_addr(2))
  // 2 号账户的零槽被丢掉，账户本身因 nonce 非零而保留。
  assert_eq(canonical[1].info.nonce, 1UL)
  assert_eq(canonical[1].storage.length(), 0)
  // 1 号账户的槽保留。
  assert_eq(canonical[0].storage.length(), 1)
}

///|
test "canonical_accounts 对重复地址报错" {
  let duplicated = alloc_of([
    (indexed_addr(1), alloc_account(1UL, word("0x01"), b"", [])),
    (indexed_addr(1), alloc_account(2UL, word("0x02"), b"", [])),
  ])
  let raised = try {
    let _ = @statetest.canonical_accounts(duplicated)
    false
  } catch {
    _ => true
  }
  assert_true(raised)
}

// ---------------------------------------------------------------------------
// 阶段 1：账户级比对
// ---------------------------------------------------------------------------

///|
test "compare_accounts 完全一致时为 match" {
  let entries = [
    entry_of(indexed_addr(1), info_of(2UL, word("0x0a"), b"\x01\x02"), [
      (word("0x01"), word("0xff")),
    ]),
  ]
  let report = @statetest.compare_accounts(entries, entries.copy())
  assert_true(report.is_match())
  assert_eq(report.mismatches.length(), 0)
  assert_eq(report.missing_accounts, 0)
  assert_eq(report.extra_accounts, 0)
  assert_eq(report.nonce_mismatches, 0)
  assert_eq(report.balance_mismatches, 0)
  assert_eq(report.code_mismatches, 0)
  assert_eq(report.missing_slots, 0)
  assert_eq(report.extra_slots, 0)
  assert_eq(report.slot_value_mismatches, 0)
}

///|
test "compare_accounts 识别缺账户与多账户" {
  let full = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x01"), b""), []),
    entry_of(indexed_addr(2), info_of(1UL, word("0x01"), b""), []),
  ]
  let only_first = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x01"), b""), []),
  ]
  // expected 有 2 个、actual 只有 1 个：缺 1 个。
  let missing = @statetest.compare_accounts(full, only_first)
  assert_eq(missing.missing_accounts, 1)
  assert_eq(missing.extra_accounts, 0)
  assert_eq(missing.mismatches.length(), 1)
  assert_eq(missing.mismatches[0].address, indexed_addr(2))
  assert_eq(missing.mismatches[0].class.to_string(), "missing_account")
  assert_eq(missing.mismatches[0].actual, "absent")
  // 反过来：多 1 个。
  let extra = @statetest.compare_accounts(only_first, full)
  assert_eq(extra.extra_accounts, 1)
  assert_eq(extra.missing_accounts, 0)
  assert_eq(extra.mismatches[0].class.to_string(), "extra_account")
  assert_eq(extra.mismatches[0].expected, "absent")
}

///|
test "compare_accounts 区分 nonce / balance / code 三类字段差异" {
  let expected = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x0a"), b"\x01"), []),
  ]
  let actual = [
    entry_of(indexed_addr(1), info_of(2UL, word("0x0b"), b"\x02"), []),
  ]
  let report = @statetest.compare_accounts(expected, actual)
  assert_eq(report.nonce_mismatches, 1)
  assert_eq(report.balance_mismatches, 1)
  assert_eq(report.code_mismatches, 1)
  assert_eq(report.mismatches.length(), 3)
  assert_eq(report.mismatches[0].class.to_string(), "nonce_mismatch")
  assert_eq(report.mismatches[0].expected, "1")
  assert_eq(report.mismatches[0].actual, "2")
  assert_eq(report.mismatches[1].class.to_string(), "balance_mismatch")
  assert_eq(report.mismatches[1].expected, "0xa")
  assert_eq(report.mismatches[1].actual, "0xb")
  assert_eq(report.mismatches[2].class.to_string(), "code_mismatch")
  assert_eq(report.mismatches[2].expected, "0x01")
  assert_true(!report.is_match())
}

///|
test "compare_accounts 区分缺槽 / 多槽 / 槽值不同" {
  let with_slots = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x00"), b""), [
      (word("0x01"), word("0x11")),
      (word("0x02"), word("0x22")),
      (word("0x03"), word("0x33")),
    ]),
  ]
  let changed = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x00"), b""), [
      (word("0x02"), word("0x22")),
      (word("0x03"), word("0x99")),
      (word("0x04"), word("0x44")),
    ]),
  ]
  let report = @statetest.compare_accounts(with_slots, changed)
  assert_eq(report.missing_slots, 1)
  assert_eq(report.extra_slots, 1)
  assert_eq(report.slot_value_mismatches, 1)
  assert_eq(report.mismatches.length(), 3)
  // 输出按槽 key 升序：0x01 缺、0x03 值不同、0x04 多。
  assert_eq(report.mismatches[0].class.to_string(), "missing_slot")
  assert_eq(report.mismatches[0].slot.unwrap(), word("0x01"))
  assert_eq(report.mismatches[1].class.to_string(), "slot_value_mismatch")
  assert_eq(report.mismatches[1].slot.unwrap(), word("0x03"))
  assert_eq(report.mismatches[1].expected, "0x33")
  assert_eq(report.mismatches[1].actual, "0x99")
  assert_eq(report.mismatches[2].class.to_string(), "extra_slot")
  assert_eq(report.mismatches[2].slot.unwrap(), word("0x04"))
  assert_eq(report.mismatches[2].expected, "0x0")
}

///|
test "零槽与 empty 账户在两侧都被归一，不算 mismatch" {
  // 左侧：显式写了零槽 + 一个全零账户；右侧：两者都不存在。
  let expected_alloc = alloc_of([
    (
      indexed_addr(1),
      alloc_account(1UL, word("0x01"), b"", [(word("0x09"), word("0x00"))]),
    ),
    (indexed_addr(2), alloc_account(0UL, word("0x00"), b"", [])),
  ])
  let actual_alloc = alloc_of([
    (indexed_addr(1), alloc_account(1UL, word("0x01"), b"", [])),
  ])
  let expected = @statetest.canonical_accounts(expected_alloc) catch {
    _ => abort("canonical form failed")
  }
  let state = @state.State::from_accounts(
    @statetest.alloc_entries(actual_alloc),
  ) catch {
    _ => abort("state build failed")
  }
  let report = @statetest.compare_accounts(expected, state.accounts())
  assert_true(report.is_match())
  assert_eq(report.mismatches.length(), 0)
}

///|
test "compare_accounts 与输入顺序无关" {
  let left = [
    entry_of(indexed_addr(3), info_of(1UL, word("0x03"), b""), []),
    entry_of(indexed_addr(1), info_of(1UL, word("0x01"), b""), []),
    entry_of(indexed_addr(2), info_of(1UL, word("0x02"), b""), []),
  ]
  let right = [
    entry_of(indexed_addr(1), info_of(1UL, word("0x09"), b""), []),
    entry_of(indexed_addr(2), info_of(1UL, word("0x02"), b""), []),
    entry_of(indexed_addr(4), info_of(1UL, word("0x04"), b""), []),
  ]
  let forward = @statetest.compare_accounts(left, right)
  let reversed = @statetest.compare_accounts(left.rev(), right.rev())
  assert_eq(forward.missing_accounts, reversed.missing_accounts)
  assert_eq(forward.extra_accounts, reversed.extra_accounts)
  assert_eq(forward.balance_mismatches, reversed.balance_mismatches)
  assert_eq(forward.mismatches.length(), reversed.mismatches.length())
  // 明细也逐行一致：比较前先排序，输出与输入顺序无关。
  for i in 0..<forward.mismatches.length() {
    assert_eq(forward.mismatches[i].address, reversed.mismatches[i].address)
    assert_eq(
      forward.mismatches[i].class.to_string(),
      reversed.mismatches[i].class.to_string(),
    )
  }
}

///|
test "超长 code 的明细被截断且计数不变" {
  let long_expected : Array[Byte] = []
  let long_actual : Array[Byte] = []
  for i in 0..<200 {
    long_expected.push(b'\x01')
    long_actual.push(if i == 199 { b'\x02' } else { b'\x01' })
  }
  let expected = [
    entry_of(
      indexed_addr(1),
      info_of(0UL, word("0x00"), Bytes::from_array(long_expected)),
      [],
    ),
  ]
  let actual = [
    entry_of(
      indexed_addr(1),
      info_of(0UL, word("0x00"), Bytes::from_array(long_actual)),
      [],
    ),
  ]
  let report = @statetest.compare_accounts(expected, actual)
  assert_eq(report.code_mismatches, 1)
  assert_eq(report.mismatches.length(), 1)
  let line = report.mismatches[0]
  assert_true(line.expected.length() < 100)
  assert_true(line.expected.contains("…(200 bytes)"))
  assert_true(line.actual.contains("…(200 bytes)"))
}

///|
test "compare_accounts 的排序不落在调用方数组上" {
  // MoonBit 的 Array 是引用语义：比对函数若原地排序，会把调用方的数据打乱。
  let expected = [
    entry_of(indexed_addr(2), info_of(1UL, word("0x02"), b""), [
      (word("0x02"), word("0x22")),
      (word("0x01"), word("0x11")),
    ]),
    entry_of(indexed_addr(1), info_of(1UL, word("0x01"), b""), []),
  ]
  let actual = [entry_of(indexed_addr(2), info_of(1UL, word("0x02"), b""), [])]
  let report = @statetest.compare_accounts(expected, actual)
  assert_eq(report.missing_accounts, 1)
  assert_eq(report.missing_slots, 2)
  assert_eq(report.mismatches.length(), 3)
  // 入参仍是原顺序：2 号账户在前，其槽仍是 0x02 在前。
  assert_eq(expected[0].address, indexed_addr(2))
  assert_eq(expected[1].address, indexed_addr(1))
  assert_eq(expected[0].storage[0].0, word("0x02"))
}

// ---------------------------------------------------------------------------
// 阶段 2：执行流水线
// ---------------------------------------------------------------------------

///|
test "no-op executor 下 fail，分类等于 pre 与 post.state 的差" {
  // base_doc：pre = sender(nonce 0, 余额 b0) + 合约(nonce 1, code, 槽 0x01=0xff)；
  // post.state = sender(nonce 1, 余额 b1)。stub 不改状态，actual 就是 pre。
  let harness = harness_of(base_doc(), no_op)
  assert_eq(harness.cases, 1)
  assert_eq(harness.pass, 0)
  assert_eq(harness.fail, 1)
  assert_eq(harness.skipped_expected_invalid, 0)
  assert_eq(harness.skipped_unsupported, 0)
  assert_eq(harness.internal_errors, 0)
  assert_eq(harness.missing_accounts, 0)
  assert_eq(harness.extra_accounts, 1)
  assert_eq(harness.nonce_mismatches, 1)
  assert_eq(harness.balance_mismatches, 1)
  assert_eq(harness.code_mismatches, 0)
  assert_eq(harness.missing_slots, 0)
  assert_eq(harness.extra_slots, 0)
  assert_eq(harness.slot_value_mismatches, 0)
  // stub 没写任何东西：diff 为空。
  assert_eq(harness.diff_accounts, 0)
  assert_eq(harness.diff_slots, 0)
  assert_eq(harness.details.length(), 3)
  assert_eq(harness.details_omitted, 0)
  assert_true(harness.details[0].contains("class=extra_account"))
  assert_true(harness.details[0].contains("case="))
  assert_true(harness.details[0].contains("fork=Cancun"))
  assert_true(harness.details[0].contains("indexes=data=0,gas=0,value=0"))
}

///|
test "fake executor 把 expected post.state 写进 State 时 pass" {
  let fixture = parse_one(base_doc())
  let entries = fixture.post_for("Cancun").unwrap()
  let expected = entries[0].state
  let harness = harness_of(base_doc(), fn(_case, state) {
    apply_alloc(state, expected)
  })
  assert_eq(harness.cases, 1)
  assert_eq(harness.pass, 1)
  assert_eq(harness.fail, 0)
  assert_eq(harness.internal_errors, 0)
  assert_eq(harness.details.length(), 0)
  // 执行确实改了状态：删掉合约账户、改 sender 的 nonce 与余额。
  assert_eq(harness.diff_accounts, 2)
  assert_eq(harness.diff_slots, 1)
}

///|
test "fake executor 少写一个字段时只剩该类 mismatch" {
  let fixture = parse_one(base_doc())
  let entries = fixture.post_for("Cancun").unwrap()
  let expected = entries[0].state
  let sender = fixture.tx.sender
  let harness = harness_of(base_doc(), fn(_case, state) {
    apply_alloc(state, expected)
    // 把余额改回 0：只有 balance 这一类应当红。
    state.set_balance(sender, @types.U256::zero())
  })
  assert_eq(harness.pass, 0)
  assert_eq(harness.fail, 1)
  assert_eq(harness.balance_mismatches, 1)
  assert_eq(harness.nonce_mismatches, 0)
  assert_eq(harness.code_mismatches, 0)
  assert_eq(harness.extra_accounts, 0)
  assert_eq(harness.missing_accounts, 0)
  assert_eq(harness.details.length(), 1)
  assert_true(harness.details[0].contains("class=balance_mismatch"))
}

///|
test "expectException 的 case 只计 skip_expected，不进 pass/fail" {
  let doc = with_expectation(
    base_doc(),
    "TransactionException.INVALID_SIGNATURE",
  )
  // 即使 executor 什么都不做也不该判 fail：这条 case 不该被执行。
  let harness = harness_of(doc, no_op)
  assert_eq(harness.cases, 1)
  assert_eq(harness.skipped_expected_invalid, 1)
  assert_eq(harness.skipped_unsupported, 0)
  assert_eq(harness.pass, 0)
  assert_eq(harness.fail, 0)
  assert_eq(harness.internal_errors, 0)
  assert_eq(harness.details.length(), 0)
  assert_eq(harness.diff_accounts, 0)
}

///|
test "authorizationList 的 case 计 skip_unsupported" {
  // 加了 authorizationList 之后 transaction 就是 type 4（EIP-7702）。
  let doc = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",\n  \"accessLists\": [[]],\n  \"authorizationList\": [],",
  )
  let fixture = parse_one(doc)
  assert_eq(fixture.tx.tx_type.to_string(), "type4")
  let harness = harness_of(doc, no_op)
  assert_eq(harness.cases, 1)
  assert_eq(harness.skipped_unsupported, 1)
  assert_eq(harness.skipped_expected_invalid, 0)
  assert_eq(harness.pass, 0)
  assert_eq(harness.fail, 0)
  assert_eq(harness.internal_errors, 0)
}

///|
test "同一输入跑两次，汇总与明细逐字段一致" {
  let first = harness_of(base_doc(), no_op)
  let second = harness_of(base_doc(), no_op)
  assert_eq(first.cases, second.cases)
  assert_eq(first.pass, second.pass)
  assert_eq(first.fail, second.fail)
  assert_eq(first.skipped_expected_invalid, second.skipped_expected_invalid)
  assert_eq(first.skipped_unsupported, second.skipped_unsupported)
  assert_eq(first.internal_errors, second.internal_errors)
  assert_eq(first.missing_accounts, second.missing_accounts)
  assert_eq(first.extra_accounts, second.extra_accounts)
  assert_eq(first.nonce_mismatches, second.nonce_mismatches)
  assert_eq(first.balance_mismatches, second.balance_mismatches)
  assert_eq(first.code_mismatches, second.code_mismatches)
  assert_eq(first.missing_slots, second.missing_slots)
  assert_eq(first.extra_slots, second.extra_slots)
  assert_eq(first.slot_value_mismatches, second.slot_value_mismatches)
  assert_eq(first.diff_accounts, second.diff_accounts)
  assert_eq(first.diff_slots, second.diff_slots)
  assert_eq(first.details_omitted, second.details_omitted)
  assert_eq(first.details.length(), second.details.length())
  for i in 0..<first.details.length() {
    assert_eq(first.details[i], second.details[i])
  }
}

///|
test "一个 case 展开失败不影响同批后续 case" {
  // 第二个 entry 的 indexes.data 越界：展开阶段就失败，记 internal error。
  let doc = base_doc().replace_all(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 99, \"gas\": 0, \"value\": 0}",
  )
  let second_entry = "{\"hash\":\"0x0000000000000000000000000000000000000000000000000000000000000001\",\"logs\":\"0x0000000000000000000000000000000000000000000000000000000000000002\",\"indexes\":{\"data\":0,\"gas\":0,\"value\":0},\"state\":{}}"
  let doc = doc.replace_all(
    old="\"Cancun\": [",
    new="\"Cancun\": [" + second_entry + ",",
  )
  // 第一个 entry（插入的那个）由 fake executor 写成它的 expected（空 alloc，即删光账户）
  // → pass；第二个 entry 的 indexes.data 越界，展开阶段就失败 → internal。
  let fixture = parse_one(doc)
  let entries = fixture.post_for("Cancun").unwrap()
  assert_eq(entries.length(), 2)
  let expected = entries[0].state
  let harness = harness_of(doc, fn(_case, state) {
    apply_alloc(state, expected)
  })
  assert_eq(harness.cases, 2)
  assert_eq(harness.pass, 1)
  assert_eq(harness.fail, 0)
  assert_eq(harness.internal_errors, 1)
  assert_true(harness.details[0].contains("class=internal"))
  assert_true(harness.details[0].contains("indexes.data"))
}

///|
test "明细超过 50 条时只留前 50 条，其余只进计数" {
  // pre 为空、post.state 有 60 个账户：no-op executor 下 60 条 missing_account。
  let mut accounts = ""
  for i in 0..<60 {
    if i > 0 {
      accounts = accounts + ","
    }
    accounts = accounts +
      "\"\{indexed_addr(i).to_hex()}\": {\"nonce\": \"0x01\", \"balance\": \"0x00\", \"code\": \"0x\", \"storage\": {}}"
  }
  let doc =
    $|{
    $|"tests/many::test_many[fork_Cancun-state_test]": {
    $|"config": {"chainid": "0x01"},
    $|"env": {
    $|  "currentCoinbase": "0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba",
    $|  "currentGasLimit": "0x07270e00",
    $|  "currentNumber": "0x01",
    $|  "currentTimestamp": "0x03e8",
    $|  "currentRandom": "0x0000000000000000000000000000000000000000000000000000000000000000",
    $|  "currentDifficulty": "0x00",
    $|  "currentBaseFee": "0x07",
    $|  "currentExcessBlobGas": "0x00"
    $|},
    $|"pre": {},
    $|"transaction": {
    $|  "nonce": "0x00",
    $|  "gasPrice": "0x0a",
    $|  "gasLimit": ["0x4c4b40"],
    $|  "to": "0x1ad41edb9130201ba8476168bcbf9bafe279f89d",
    $|  "value": ["0x00"],
    $|  "data": ["0x"],
    $|  "sender": "0x766b923079c2900993bafa89b07d66423481776e",
    $|  "secretKey": "0xf792f84d3860ff35b56caae61ad41edb9130201ba8476168bcbf9bafe279f89d"
    $|},
    $|"post": {
    $|  "Cancun": [
    $|    {
    $|      "hash": "0x0000000000000000000000000000000000000000000000000000000000000001",
    $|      "logs": "0x0000000000000000000000000000000000000000000000000000000000000002",
    $|      "indexes": {"data": 0, "gas": 0, "value": 0},
    $|      "state": {\{accounts}}
    $|    }
    $|  ]
    $|}
    $|}
    $|}
  let harness = harness_of(doc, no_op)
  assert_eq(harness.cases, 1)
  assert_eq(harness.fail, 1)
  assert_eq(harness.missing_accounts, 60)
  assert_eq(harness.details.length(), 50)
  assert_eq(harness.details_omitted, 10)
}

// ---------------------------------------------------------------------------
// 阶段 3 的出口：退出码（纯函数）
// ---------------------------------------------------------------------------

///|
fn tx_summary_of(doc : String) -> @statetest.Summary {
  let fixtures = @statetest.parse_document(doc) catch {
    e => abort("parse failed: \{e.to_string()}")
  }
  @statetest.run_document(fixtures, "Cancun") catch {
    e => abort("unexpected error: \{e.to_string()}")
  }
}

///|
test "exit_code：stub 的 state fail 默认不红，--strict 才红" {
  let tx = tx_summary_of(base_doc())
  let harness = harness_of(base_doc(), no_op)
  assert_eq(harness.fail, 1)
  assert_eq(@statetest.exit_code(tx, harness, false), 0)
  assert_eq(@statetest.exit_code(tx, harness, true), 1)
}

///|
test "exit_code：pass 的 case 在 strict 下也是 0" {
  let fixture = parse_one(base_doc())
  let expected = fixture.post_for("Cancun").unwrap()[0].state
  let tx = tx_summary_of(base_doc())
  let harness = harness_of(base_doc(), fn(_case, state) {
    apply_alloc(state, expected)
  })
  assert_eq(harness.pass, 1)
  assert_eq(@statetest.exit_code(tx, harness, false), 0)
  assert_eq(@statetest.exit_code(tx, harness, true), 0)
}

///|
test "exit_code：internal error 无条件红" {
  let doc = with_change(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 9, \"gas\": 0, \"value\": 0}",
  )
  let tx = tx_summary_of(doc)
  let harness = harness_of(doc, no_op)
  assert_eq(harness.internal_errors, 1)
  assert_eq(@statetest.exit_code(tx, harness, false), 1)
  assert_eq(@statetest.exit_code(tx, harness, true), 1)
}

///|
test "exit_code：tx 流水线不干净时红，与 harness 无关" {
  // gasLimit 与 txbytes 不一致：tx 流水线自己就红。
  let doc = with_change(
    old="\"gasLimit\": [\"0x4c4b40\"],",
    new="\"gasLimit\": [\"0x4c4b41\"],",
  )
  let tx = tx_summary_of(doc)
  let harness = harness_of(doc, no_op)
  assert_true(!tx.is_clean())
  assert_eq(@statetest.exit_code(tx, harness, false), 1)
}
