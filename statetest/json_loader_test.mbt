// JSON loader 测试：合成 JSON，每条都断言**具体错误分类与路径**，不只断言「抛了」。
//
// 模板取 EEST v5.4.0 stable 的真实形状（`tests/cancun/eip1153_tstore/
// test_basic_tload_after_store.json` 的字段集合与取值格式），但内容是本文件内的
// 合成数据——测试不得依赖 fixture tarball。

///|
fn base_doc() -> String {
  doc_with_key("tests/x.py::test_a[fork_Cancun-state_test]")
}

///|
fn doc_with_key(key : String) -> String {
  let doc =
    $|{
    $|"\{key}": {
    $|"_info": {"comment": "unknown fields must be ignored"},
    $|"config": {"chainid": "0x01", "blobSchedule": {"Cancun": {"target": "0x03"}}},
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
    $|"pre": {
    $|  "0x766b923079c2900993bafa89b07d66423481776e": {
    $|    "nonce": "0x00",
    $|    "balance": "0x6124fee993bc0000",
    $|    "code": "0x",
    $|    "storage": {}
    $|  },
    $|  "0x1ad41edb9130201ba8476168bcbf9bafe279f89d": {
    $|    "nonce": "0x01",
    $|    "balance": "0x00",
    $|    "code": "0x5b601660015560015c600155",
    $|    "storage": {"0x01": "0xff"}
    $|  }
    $|},
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
    $|      "state": {
    $|        "0x766b923079c2900993bafa89b07d66423481776e": {
    $|          "nonce": "0x01", "balance": "0x6124fee993b55c0a", "code": "0x", "storage": {}
    $|        }
    $|      },
    $|      "txbytes": "0xf860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0"
    $|    }
    $|  ]
    $|}
    $|}
    $|}
  doc
}

///|
/// 替换模板里的一处文本；目标不存在说明测试本身写错了，直接 abort。
fn with_change(old~ : StringView, new~ : StringView) -> String {
  let doc = base_doc()
  if !doc.contains(old) {
    abort("test template does not contain the pattern to replace")
  }
  doc.replace_all(old~, new~)
}

///|
fn expect_parse_error(doc : String) -> @statetest.FixtureError? {
  try {
    let _ = @statetest.parse_document(doc)
    None
  } catch {
    e => Some(e)
  }
}

// ---------------------------------------------------------------------------
// 正常路径
// ---------------------------------------------------------------------------

///|
test "loader parses the full fixture shape" {
  let fixtures = @statetest.parse_document(base_doc())
  assert_eq(fixtures.length(), 1)
  let fixture = fixtures[0]
  assert_eq(fixture.name, "tests/x.py::test_a[fork_Cancun-state_test]")
  assert_eq(
    fixture.chain_id.to_hex(),
    "0000000000000000000000000000000000000000000000000000000000000001",
  )
  // env
  assert_eq(
    fixture.env.coinbase.to_hex(),
    "0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba",
  )
  assert_eq(fixture.env.gas_limit, 120000000UL)
  assert_eq(fixture.env.number, 1UL)
  assert_eq(fixture.env.timestamp, 1000UL)
  assert_eq(
    fixture.env.base_fee.to_hex(),
    "0000000000000000000000000000000000000000000000000000000000000007",
  )
  assert_eq(fixture.env.excess_blob_gas, 0UL)
  // pre：两个账户按地址排序，storage 是数量格式
  assert_eq(fixture.pre.length(), 2)
  let target = fixture.pre.entries[0].1
  assert_eq(
    fixture.pre.entries[0].0.to_hex(),
    "0x1ad41edb9130201ba8476168bcbf9bafe279f89d",
  )
  assert_eq(target.nonce, 1UL)
  assert_eq(target.storage.length(), 1)
  assert_eq(
    target.storage[0].0.to_hex(),
    "0000000000000000000000000000000000000000000000000000000000000001",
  )
  assert_eq(
    target.storage[0].1.to_hex(),
    "00000000000000000000000000000000000000000000000000000000000000ff",
  )
  // transaction
  assert_eq(fixture.tx.tx_type.to_string(), "legacy")
  assert_eq(fixture.tx.gas_limits.length(), 1)
  assert_eq(
    fixture.tx.to.unwrap().to_hex(),
    "0x1ad41edb9130201ba8476168bcbf9bafe279f89d",
  )
  // pre 的按地址查找
  assert_true(fixture.pre.lookup(fixture.pre.entries[0].0) is Some(_))
  assert_true(fixture.pre.lookup(@types.Address::zero()) is None)
  // post
  let entries = fixture.post_for("Cancun").unwrap()
  assert_eq(entries.length(), 1)
  assert_eq(entries[0].indexes.data, 0)
  assert_eq(entries[0].txbytes_field_present, true)
  assert_true(entries[0].txbytes is Some(_))
  assert_eq(entries[0].expect_exception.length(), 0)
}

///|
test "loader keeps multiple tests sorted by name" {
  let a = doc_with_key("a")
  let b = doc_with_key("b")
  let two = "{" +
    a[1:a.length() - 1].to_owned() +
    "," +
    b[1:b.length() - 1].to_owned() +
    "}"
  let fixtures = @statetest.parse_document(two)
  assert_eq(fixtures.length(), 2)
  assert_eq(fixtures[0].name, "a")
  assert_eq(fixtures[1].name, "b")
}

///|
test "loader ignores unknown fields" {
  let doc = with_change(
    old="\"nonce\": \"0x00\",\n  \"gasPrice\"",
    new="\"nonce\": \"0x00\", \"futureField\": {\"nested\": [1, 2, 3]},\n  \"gasPrice\"",
  )
  let fixtures = @statetest.parse_document(doc)
  assert_eq(
    fixtures[0].tx.nonce.to_hex(),
    "0000000000000000000000000000000000000000000000000000000000000000",
  )
}

///|
test "loader splits expectException on pipe" {
  let doc = with_change(
    old="\"txbytes\":",
    new="\"expectException\": \"TransactionException.TYPE_3_TX_ZERO_BLOBS|TransactionException.TYPE_3_TX_BLOB_COUNT_EXCEEDED\",\n      \"txbytes\":",
  )
  let fixtures = @statetest.parse_document(doc)
  let entries = fixtures[0].post_for("Cancun").unwrap()
  assert_eq(entries[0].expect_exception.length(), 2)
  assert_eq(
    entries[0].expect_exception[0],
    "TransactionException.TYPE_3_TX_ZERO_BLOBS",
  )
  assert_eq(
    entries[0].expect_exception[1],
    "TransactionException.TYPE_3_TX_BLOB_COUNT_EXCEEDED",
  )
}

///|
test "loader treats empty txbytes as missing" {
  let doc = with_change(
    old="\"txbytes\": \"0xf860800a834c4b40941ad41edb9130201ba8476168bcbf9bafe279f89d808025a049c30c1716544ca6c1960a201ca2c2e6f829510cbe85a663508c3b8499a318faa03336582b5cf99b9d55854927decda7f8db1b2703684aee01c4be9c80b2a108c0\"",
    new="\"txbytes\": \"0x\"",
  )
  let fixtures = @statetest.parse_document(doc)
  let entries = fixtures[0].post_for("Cancun").unwrap()
  assert_true(entries[0].txbytes is None)
  assert_eq(entries[0].txbytes_field_present, true)
}

///|
test "loader reads empty to as contract creation" {
  let doc = with_change(
    old="\"to\": \"0x1ad41edb9130201ba8476168bcbf9bafe279f89d\"",
    new="\"to\": \"\"",
  )
  let fixtures = @statetest.parse_document(doc)
  assert_true(fixtures[0].tx.to is None)
}

///|
test "loader reads type2 template with access lists" {
  let with_fees = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",",
  )
  let doc = with_fees.replace_all(
    old="\"data\": [\"0x\"],",
    new="\"data\": [\"0x\"],\n  \"accessLists\": [[{\"address\": \"0x0000000000000000000000000000000000000064\", \"storageKeys\": [\"0x0000000000000000000000000000000000000000000000000000000000000064\"]}]],",
  )
  let fixtures = @statetest.parse_document(doc)
  assert_eq(fixtures[0].tx.tx_type.to_string(), "type2")
  let lists = fixtures[0].tx.access_lists.unwrap()
  assert_eq(lists.length(), 1)
  assert_eq(lists[0].length(), 1)
  assert_eq(
    lists[0][0].address.to_hex(),
    "0x0000000000000000000000000000000000000064",
  )
  assert_eq(lists[0][0].storage_keys.length(), 1)
}

///|
test "loader infers type3 from maxFeePerBlobGas" {
  let with_fees = with_change(
    old="\"gasPrice\": \"0x0a\",",
    new="\"maxPriorityFeePerGas\": \"0x00\",\n  \"maxFeePerGas\": \"0x0e\",",
  )
  let doc = with_fees.replace_all(
    old="\"data\": [\"0x\"],",
    new="\"data\": [\"0x\"],\n  \"accessLists\": [],\n  \"maxFeePerBlobGas\": \"0x01\",\n  \"blobVersionedHashes\": [\"0x0100000000000000000000000000000000000000000000000000000000000000\"],",
  )
  let fixtures = @statetest.parse_document(doc)
  assert_eq(fixtures[0].tx.tx_type.to_string(), "type3")
  assert_eq(fixtures[0].tx.blob_versioned_hashes.length(), 1)
  assert_eq(
    fixtures[0].tx.max_fee_per_blob_gas.to_hex(),
    "0000000000000000000000000000000000000000000000000000000000000001",
  )
}

///|
test "loader handles multiple data/gas/value vectors" {
  let doc = with_change(
    old="\"gasLimit\": [\"0x4c4b40\"],",
    new="\"gasLimit\": [\"0x4c4b40\", \"0x0a\", \"0x14\"],",
  )
  let doc2 = doc.replace_all(
    old="\"value\": [\"0x00\"],",
    new="\"value\": [\"0x00\", \"0x01\"],",
  )
  let doc3 = doc2.replace_all(
    old="\"data\": [\"0x\"],",
    new="\"data\": [\"0x\", \"0xdeadbeef\"],",
  )
  let fixtures = @statetest.parse_document(doc3)
  assert_eq(fixtures[0].tx.gas_limits.length(), 3)
  assert_eq(fixtures[0].tx.values.length(), 2)
  assert_eq(fixtures[0].tx.datas.length(), 2)
  assert_eq(fixtures[0].tx.datas[1].length(), 4)
}

// ---------------------------------------------------------------------------
// 错误分类
// ---------------------------------------------------------------------------

///|
test "loader rejects duplicate keys" {
  let doc = "{\"a\": 1, \"a\": 2}"
  match expect_parse_error(doc) {
    Some(@statetest.JsonParse(message~)) =>
      assert_true(message.contains("Duplicate"))
    Some(other) => abort("expected JsonParse, got \{other.to_string()}")
    None => abort("expected JsonParse, got Ok")
  }
}

///|
test "loader rejects deep nesting" {
  let buf = StringBuilder()
  for _ in 0..<80 {
    buf.write_char('[')
  }
  for _ in 0..<80 {
    buf.write_char(']')
  }
  match expect_parse_error(buf.to_string()) {
    Some(@statetest.JsonParse(message~)) =>
      assert_true(message.contains("Depth"))
    Some(other) => abort("expected JsonParse, got \{other.to_string()}")
    None => abort("expected JsonParse, got Ok")
  }
}

///|
test "loader rejects missing required field" {
  let doc = with_change(
    old="\"nonce\": \"0x00\",\n  \"gasPrice\"",
    new="\"gasPrice\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.FieldMissing(path~, field~)) => {
      assert_eq(field, "nonce")
      assert_true(path.contains("transaction"))
    }
    Some(other) => abort("expected FieldMissing, got \{other.to_string()}")
    None => abort("expected FieldMissing, got Ok")
  }
}

///|
test "loader rejects wrong field type" {
  let doc = with_change(
    old="\"currentGasLimit\": \"0x07270e00\"",
    new="\"currentGasLimit\": 123",
  )
  match expect_parse_error(doc) {
    Some(@statetest.FieldType(path~, field~, ..)) => {
      assert_eq(field, "currentGasLimit")
      assert_true(path.contains("env"))
    }
    Some(other) => abort("expected FieldType, got \{other.to_string()}")
    None => abort("expected FieldType, got Ok")
  }
}

///|
test "loader rejects bad hex" {
  let doc = with_change(
    old="\"currentCoinbase\": \"0x2adc25665018aa1fe0e6bc666dac8fc2697ff9ba\"",
    new="\"currentCoinbase\": \"0x2adc25665018aa1fe0e6bc666dac8fc2697ff9zz\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.HexInvalid(path~, field~, ..)) => {
      assert_eq(field, "currentCoinbase")
      assert_true(path.contains("env"))
    }
    Some(other) => abort("expected HexInvalid, got \{other.to_string()}")
    None => abort("expected HexInvalid, got Ok")
  }
}

///|
test "loader rejects odd-length code" {
  let doc = with_change(
    old="\"code\": \"0x5b601660015560015c600155\"",
    new="\"code\": \"0x5b601660015560015c60015\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.HexInvalid(path~, field~, ..)) => {
      assert_eq(field, "code")
      assert_true(path.contains("pre"))
    }
    Some(other) => abort("expected HexInvalid, got \{other.to_string()}")
    None => abort("expected HexInvalid, got Ok")
  }
}

///|
test "loader rejects 32-byte field with wrong length" {
  let doc = with_change(
    old="\"hash\": \"0x0000000000000000000000000000000000000000000000000000000000000001\"",
    new="\"hash\": \"0x00000000000000000000000000000000000000000000000000000000000001\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.LengthInvalid(path~, field~, expected~, actual~)) => {
      assert_eq(field, "hash")
      assert_eq(expected, 32)
      assert_eq(actual, 31)
      assert_true(path.contains("post"))
    }
    Some(other) => abort("expected LengthInvalid, got \{other.to_string()}")
    None => abort("expected LengthInvalid, got Ok")
  }
}

///|
test "loader rejects 20-byte field with wrong length" {
  let doc = with_change(
    old="\"sender\": \"0x766b923079c2900993bafa89b07d66423481776e\"",
    new="\"sender\": \"0x766b923079c2900993bafa89b07d6642348177\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.LengthInvalid(field~, expected~, actual~, ..)) => {
      assert_eq(field, "sender")
      assert_eq(expected, 20)
      assert_eq(actual, 19)
    }
    Some(other) => abort("expected LengthInvalid, got \{other.to_string()}")
    None => abort("expected LengthInvalid, got Ok")
  }
}

///|
test "loader rejects quantity that overflows u64" {
  let doc = with_change(
    old="\"currentNumber\": \"0x01\"",
    new="\"currentNumber\": \"0x010000000000000000\"",
  )
  match expect_parse_error(doc) {
    Some(@statetest.IntegerTooLarge(path~, field~)) => {
      assert_eq(field, "currentNumber")
      assert_true(path.contains("env"))
    }
    Some(other) => abort("expected IntegerTooLarge, got \{other.to_string()}")
    None => abort("expected IntegerTooLarge, got Ok")
  }
}

///|
test "loader rejects non-integer indexes" {
  let doc = with_change(
    old="\"indexes\": {\"data\": 0, \"gas\": 0, \"value\": 0}",
    new="\"indexes\": {\"data\": 0.5, \"gas\": 0, \"value\": 0}",
  )
  match expect_parse_error(doc) {
    Some(@statetest.FieldType(path~, field~, ..)) => {
      assert_eq(field, "data")
      assert_true(path.contains("indexes"))
    }
    Some(other) => abort("expected FieldType, got \{other.to_string()}")
    None => abort("expected FieldType, got Ok")
  }
}

///|
test "loader rejects garbage text" {
  for text in ["", "not json", "{", "[1,2,3]", "null", "\"str\"", "{}"] {
    match expect_parse_error(text) {
      Some(_) => ()
      None => abort("expected an error for input: \{text}")
    }
  }
}

///|
test "loader rejects 100 random non-JSON strings" {
  let rng : Rng = { state: 424242UL, }
  let alphabet = "{}[]\",:0123456789abcxyz \n\t|"
  for _ in 0..<100 {
    let len = (rng.next() % 40UL).to_int()
    let buf = StringBuilder()
    // 前缀 `x` 保证它不是合法 JSON 的开头。
    buf.write_char('x')
    for _ in 0..<len {
      let idx = (rng.next() % 30UL).to_int()
      buf.write_char(alphabet.get_char(idx % alphabet.length()).unwrap())
    }
    match expect_parse_error(buf.to_string()) {
      Some(_) => ()
      None => abort("expected an error for generated input")
    }
  }
}
