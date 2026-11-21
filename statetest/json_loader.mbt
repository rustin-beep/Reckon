// JSON -> 模型。
//
// 严格解析的边界：
//   - 只认已知字段，未知字段忽略（EEST 会持续加字段）；
//   - 必需字段缺失、类型不符、长度不符、十六进制非法一律报 `FixtureError`；
//   - 32 字节字段（hash / storage key / storage value / secretKey / blob hash）先
//     `hex_decode` 再校验长度，不用会接受短输入的 `U256::from_bytes_be` 当长度校验；
//   - 数量字段用 `U256::from_hex`（允许奇数位），转 `UInt64` 前必须检查高三个 limb。

///|
/// 解析一份 EEST state test 文档。
///
/// 一个 JSON 文件可以含多个 test（顶层多个键），每个 test 独立返回；顺序按测试名
/// 排序，保证同一份输入在不同后端的输出一致。
pub fn parse_document(text : String) -> Array[Fixture] raise FixtureError {
  let root = @json.parse(text, max_nesting_depth=64, reject_duplicate_keys=true) catch {
    e => raise FixtureError::JsonParse(message="\{e}")
  }
  let map = match root {
    Json::Object(m) => m
    _ =>
      raise FixtureError::FieldType(
        path="$",
        field="<document>",
        expected="object",
      )
  }
  if map.length() == 0 {
    raise FixtureError::EmptyDocument
  }
  let names : Array[String] = []
  for name in map.keys() {
    names.push(name)
  }
  names.sort()
  let out : Array[Fixture] = []
  for name in names {
    match map.get(name) {
      Some(value) => out.push(parse_fixture(name, value))
      None => ()
    }
  }
  if out.length() == 0 {
    raise FixtureError::EmptyDocument
  }
  out
}

// ---------------------------------------------------------------------------
// 取值辅助
// ---------------------------------------------------------------------------

///|
fn child_path(prefix : String, field : String) -> String {
  if prefix.length() == 0 {
    field
  } else {
    "\{prefix}.\{field}"
  }
}

///|
fn field_of(
  obj : Map[String, Json],
  path : String,
  name : String,
) -> Json raise FixtureError {
  match obj.get(name) {
    Some(v) => v
    None => raise FixtureError::FieldMissing(path~, field=name)
  }
}

///|
fn optional_field(obj : Map[String, Json], name : String) -> Json? {
  obj.get(name)
}

///|
fn as_object(
  j : Json,
  path : String,
  field : String,
) -> Map[String, Json] raise FixtureError {
  match j {
    Json::Object(m) => m
    _ => raise FixtureError::FieldType(path~, field~, expected="object")
  }
}

///|
fn as_array(
  j : Json,
  path : String,
  field : String,
) -> Array[Json] raise FixtureError {
  match j {
    Json::Array(a) => a
    _ => raise FixtureError::FieldType(path~, field~, expected="array")
  }
}

///|
fn as_string(
  j : Json,
  path : String,
  field : String,
) -> String raise FixtureError {
  match j {
    Json::String(s) => s
    _ => raise FixtureError::FieldType(path~, field~, expected="string")
  }
}

///|
/// JSON number 当非负下标用。`indexes` 的取值域很小，但 `Double` 有精度上限，
/// 所以显式拒绝非整数与超出 `Int32` 的值，而不是静默截断。
fn as_index(
  j : Json,
  path : String,
  field : String,
) -> Int32 raise FixtureError {
  match j {
    Json::Number(d, repr~) => {
      ignore(repr)
      if d.is_nan() || d < 0.0 || d > 2147483647.0 || d != d.floor() {
        raise FixtureError::FieldType(
          path~,
          field~,
          expected="non-negative integer",
        )
      }
      d.to_int()
    }
    _ => raise FixtureError::FieldType(path~, field~, expected="number")
  }
}

///|
/// 数量字段：`0x` 前缀可选，允许奇数位（以太坊数量字段的写法）。
fn as_quantity(
  j : Json,
  path : String,
  field : String,
) -> @types.U256 raise FixtureError {
  let s = as_string(j, path, field)
  let parsed = @types.U256::from_hex(s) catch {
    _ =>
      raise FixtureError::HexInvalid(
        path~,
        field~,
        reason="quantity must be hex",
      )
  }
  parsed
}

///|
/// `U256` 转 `UInt64`：高位非零即报错，绝不截断。
fn as_u64(j : Json, path : String, field : String) -> UInt64 raise FixtureError {
  let v = as_quantity(j, path, field)
  if v.limb(1) != 0UL || v.limb(2) != 0UL || v.limb(3) != 0UL {
    raise FixtureError::IntegerTooLarge(path~, field~)
  }
  v.limb(0)
}

///|
fn as_hex_bytes(
  j : Json,
  path : String,
  field : String,
) -> Bytes raise FixtureError {
  let s = as_string(j, path, field)
  let decoded = @types.hex_decode(s) catch {
    _ =>
      raise FixtureError::HexInvalid(
        path~,
        field~,
        reason="expected even-length hex with optional 0x prefix",
      )
  }
  decoded
}

///|
fn as_hash32(
  j : Json,
  path : String,
  field : String,
) -> @types.Hash32 raise FixtureError {
  let b = as_hex_bytes(j, path, field)
  if b.length() != 32 {
    raise FixtureError::LengthInvalid(
      path~,
      field~,
      expected=32,
      actual=b.length(),
    )
  }
  let h = @types.Hash32::from_bytes(b[:]) catch {
    _ =>
      raise FixtureError::LengthInvalid(
        path~,
        field~,
        expected=32,
        actual=b.length(),
      )
  }
  h
}

///|
fn as_address(
  j : Json,
  path : String,
  field : String,
) -> @types.Address raise FixtureError {
  let b = as_hex_bytes(j, path, field)
  if b.length() != 20 {
    raise FixtureError::LengthInvalid(
      path~,
      field~,
      expected=20,
      actual=b.length(),
    )
  }
  let a = @types.Address::from_bytes(b[:]) catch {
    _ =>
      raise FixtureError::LengthInvalid(
        path~,
        field~,
        expected=20,
        actual=b.length(),
      )
  }
  a
}

// ---------------------------------------------------------------------------
// 各段解析
// ---------------------------------------------------------------------------

///|
fn parse_fixture(name : String, root : Json) -> Fixture raise FixtureError {
  let obj = as_object(root, name, "<test>")
  let chain_id = {
    let config_path = child_path(name, "config")
    let config = as_object(field_of(obj, name, "config"), config_path, "config")
    as_quantity(
      field_of(config, config_path, "chainid"),
      config_path,
      "chainid",
    )
  }
  let env = parse_env(obj, name)
  let pre = parse_alloc(field_of(obj, name, "pre"), child_path(name, "pre"))
  let post = parse_post(obj, name)
  let tx = parse_tx(obj, name)
  { name, chain_id, env, pre, post, tx, }
}

///|

///|
/// `env`。
///
/// `currentRandom` 与 `currentExcessBlobGas` 允许缺失，缺省为零：前者是 merge 之后
/// 才有的字段（pre-merge fork 只有 `currentDifficulty`），后者是 Cancun 才引入的。
/// 这两个字段缺失时补零值可以让老 fork 的 fixture 也能加载，而不是整份 parse 失败
/// ——B06 只跑 Cancun/Prague，但 B09 扫全 corpus 时会碰到 pre-merge 文件。
/// 其余六个字段（coinbase/gasLimit/number/timestamp/difficulty/baseFee）仍然必需。
fn parse_env(
  obj : Map[String, Json],
  name : String,
) -> BlockEnv raise FixtureError {
  let path = child_path(name, "env")
  let env = as_object(field_of(obj, name, "env"), path, "env")
  {
    coinbase: as_address(
      field_of(env, path, "currentCoinbase"),
      path,
      "currentCoinbase",
    ),
    gas_limit: as_u64(
      field_of(env, path, "currentGasLimit"),
      path,
      "currentGasLimit",
    ),
    number: as_u64(field_of(env, path, "currentNumber"), path, "currentNumber"),
    timestamp: as_u64(
      field_of(env, path, "currentTimestamp"),
      path,
      "currentTimestamp",
    ),
    random: parse_env_hash32_or_zero(env, path, "currentRandom"),
    difficulty: as_quantity(
      field_of(env, path, "currentDifficulty"),
      path,
      "currentDifficulty",
    ),
    base_fee: as_quantity(
      field_of(env, path, "currentBaseFee"),
      path,
      "currentBaseFee",
    ),
    excess_blob_gas: parse_env_u64_or_zero(env, path, "currentExcessBlobGas"),
  }
}

///|
fn parse_env_hash32_or_zero(
  env : Map[String, Json],
  path : String,
  field : String,
) -> @types.Hash32 raise FixtureError {
  match optional_field(env, field) {
    None => @types.Hash32::zero()
    Some(value) => as_hash32(value, path, field)
  }
}

///|
fn parse_env_u64_or_zero(
  env : Map[String, Json],
  path : String,
  field : String,
) -> UInt64 raise FixtureError {
  match optional_field(env, field) {
    None => 0UL
    Some(value) => as_u64(value, path, field)
  }
}

///|
/// `pre` 或 `post.state`：地址 -> 账户。
fn parse_alloc(j : Json, path : String) -> Alloc raise FixtureError {
  let obj = as_object(j, path, "<alloc>")
  let entries : Array[(@types.Address, AccountAlloc)] = []
  let seen : Map[@types.Address, Unit] = Map([])
  let keys : Array[String] = []
  for key in obj.keys() {
    keys.push(key)
  }
  keys.sort()
  for key in keys {
    let address = {
      let decoded = @types.Address::from_hex(key) catch {
        _ =>
          raise FixtureError::HexInvalid(
            path~,
            field=key,
            reason="account key must be 20-byte hex",
          )
      }
      decoded
    }
    if seen.contains(address) {
      raise FixtureError::DuplicateAccount(path~, address=address.to_hex())
    }
    seen.set(address, ())
    let account_path = "\{path}.\{key}"
    let account_json = match obj.get(key) {
      Some(v) => v
      None => continue
    }
    let account_obj = as_object(account_json, account_path, "<account>")
    let storage_obj = as_object(
      field_of(account_obj, account_path, "storage"),
      child_path(account_path, "storage"),
      "storage",
    )
    let storage : Array[(@types.U256, @types.U256)] = []
    let slot_keys : Array[String] = []
    for slot in storage_obj.keys() {
      slot_keys.push(slot)
    }
    slot_keys.sort()
    for slot in slot_keys {
      let slot_value = match storage_obj.get(slot) {
        Some(v) => v
        None => continue
      }
      let storage_path = "\{account_path}.storage"
      let slot_key = as_quantity(
        @json.Json::string(slot),
        storage_path,
        "storageKey",
      )
      let slot_value_u256 = as_quantity(
        slot_value, storage_path, "storageValue",
      )
      storage.push((slot_key, slot_value_u256))
    }
    let account = {
      nonce: as_u64(
        field_of(account_obj, account_path, "nonce"),
        account_path,
        "nonce",
      ),
      balance: as_quantity(
        field_of(account_obj, account_path, "balance"),
        account_path,
        "balance",
      ),
      code: as_hex_bytes(
        field_of(account_obj, account_path, "code"),
        account_path,
        "code",
      ),
      storage,
    }
    entries.push((address, account))
  }
  { entries, }
}

///|
fn parse_post(
  obj : Map[String, Json],
  name : String,
) -> Array[(String, Array[PostEntry])] raise FixtureError {
  let path = child_path(name, "post")
  let post_obj = as_object(field_of(obj, name, "post"), path, "post")
  let forks : Array[String] = []
  for fork in post_obj.keys() {
    forks.push(fork)
  }
  forks.sort()
  let out : Array[(String, Array[PostEntry])] = []
  for fork in forks {
    let fork_path = "\{path}.\{fork}"
    let entries_json = match post_obj.get(fork) {
      Some(v) => v
      None => continue
    }
    let arr = as_array(entries_json, fork_path, "<entries>")
    let entries : Array[PostEntry] = []
    for i in 0..<arr.length() {
      entries.push(parse_post_entry(arr[i], "\{fork_path}[\{i}]"))
    }
    out.push((fork, entries))
  }
  out
}

///|
fn parse_post_entry(j : Json, path : String) -> PostEntry raise FixtureError {
  let obj = as_object(j, path, "<postEntry>")
  let state = parse_alloc(
    field_of(obj, path, "state"),
    child_path(path, "state"),
  )
  let indexes_json = as_object(
    field_of(obj, path, "indexes"),
    child_path(path, "indexes"),
    "indexes",
  )
  let indexes_path = child_path(path, "indexes")
  let indexes = {
    data: as_index(
      field_of(indexes_json, indexes_path, "data"),
      indexes_path,
      "data",
    ),
    gas: as_index(
      field_of(indexes_json, indexes_path, "gas"),
      indexes_path,
      "gas",
    ),
    value: as_index(
      field_of(indexes_json, indexes_path, "value"),
      indexes_path,
      "value",
    ),
  }
  let (txbytes, txbytes_field_present) = match optional_field(obj, "txbytes") {
    None => (None, false)
    Some(value) => {
      let s = as_string(value, path, "txbytes")
      if s.length() == 0 || s == "0x" {
        (None, true)
      } else {
        let decoded = @types.hex_decode(s) catch {
          _ =>
            raise FixtureError::HexInvalid(
              path~,
              field="txbytes",
              reason="expected even-length hex",
            )
        }
        (Some(decoded), true)
      }
    }
  }
  let expect_exception = match optional_field(obj, "expectException") {
    None => []
    Some(value) => split_pipe(as_string(value, path, "expectException"))
  }
  {
    state_hash: as_hash32(field_of(obj, path, "hash"), path, "hash"),
    logs_hash: as_hash32(field_of(obj, path, "logs"), path, "logs"),
    state,
    txbytes,
    txbytes_field_present,
    indexes,
    expect_exception,
  }
}

///|
/// `expectException` 是 `|` 分隔的备选串；本任务只保存与切分，不判语义。
fn split_pipe(s : String) -> Array[String] {
  let out : Array[String] = []
  let mut buf = StringBuilder()
  for ch in s {
    if ch == '|' {
      out.push(buf.to_string())
      buf = StringBuilder()
    } else {
      buf.write_char(ch)
    }
  }
  out.push(buf.to_string())
  out
}

///|
/// `transaction`。类型由字段集合推断——EEST 的 `transaction` 没有 `type` 字段：
///
///   - `authorizationList` -> type 4（EIP-7702，本任务不解码）
///   - `maxFeePerBlobGas`   -> type 3
///   - `maxFeePerGas`       -> type 2
///   - `accessLists`        -> type 1
///   - 否则                 -> legacy
fn parse_tx(
  obj : Map[String, Json],
  name : String,
) -> TxTemplate raise FixtureError {
  let path = child_path(name, "transaction")
  let tx = as_object(field_of(obj, name, "transaction"), path, "transaction")
  let has = fn(key) { optional_field(tx, key) is Some(_) }
  let tx_type = if has("authorizationList") {
    Type4
  } else if has("maxFeePerBlobGas") {
    Type3
  } else if has("maxFeePerGas") {
    Type2
  } else if has("accessLists") {
    Type1
  } else {
    Legacy
  }
  let has_price = match tx_type {
    Legacy | Type1 => true
    _ => false
  }
  let has_1559 = match tx_type {
    Type2 | Type3 | Type4 => true
    _ => false
  }
  let has_access_list = match tx_type {
    Type1 | Type2 | Type3 | Type4 => true
    _ => false
  }
  let has_blob = match tx_type {
    Type3 => true
    _ => false
  }
  let gas_price = if has_price {
    as_quantity(field_of(tx, path, "gasPrice"), path, "gasPrice")
  } else {
    @types.U256::zero()
  }
  let max_priority_fee_per_gas = if has_1559 {
    as_quantity(
      field_of(tx, path, "maxPriorityFeePerGas"),
      path,
      "maxPriorityFeePerGas",
    )
  } else {
    @types.U256::zero()
  }
  let max_fee_per_gas = if has_1559 {
    as_quantity(field_of(tx, path, "maxFeePerGas"), path, "maxFeePerGas")
  } else {
    @types.U256::zero()
  }
  let access_lists = if has_access_list {
    Some(parse_access_lists(field_of(tx, path, "accessLists"), path))
  } else {
    None
  }
  let max_fee_per_blob_gas = if has_blob {
    as_quantity(
      field_of(tx, path, "maxFeePerBlobGas"),
      path,
      "maxFeePerBlobGas",
    )
  } else {
    @types.U256::zero()
  }
  let blob_versioned_hashes = if has_blob {
    let arr = as_array(
      field_of(tx, path, "blobVersionedHashes"),
      path,
      "blobVersionedHashes",
    )
    let hashes : Array[@types.Hash32] = []
    for i in 0..<arr.length() {
      hashes.push(as_hash32(arr[i], path, "blobVersionedHashes[\{i}]"))
    }
    hashes
  } else {
    []
  }
  {
    tx_type,
    nonce: as_quantity(field_of(tx, path, "nonce"), path, "nonce"),
    gas_price,
    max_priority_fee_per_gas,
    max_fee_per_gas,
    gas_limits: parse_quantity_array(
      field_of(tx, path, "gasLimit"),
      path,
      "gasLimit",
    ),
    to: parse_to(field_of(tx, path, "to"), path),
    values: parse_quantity_array(field_of(tx, path, "value"), path, "value"),
    datas: parse_data_array(field_of(tx, path, "data"), path),
    access_lists,
    max_fee_per_blob_gas,
    blob_versioned_hashes,
    sender: as_address(field_of(tx, path, "sender"), path, "sender"),
    secret_key: as_hash32_like(field_of(tx, path, "secretKey"), path),
  }
}

///|
/// `to`：`""` 表示合约创建，其余必须是 20 字节地址。
fn parse_to(j : Json, path : String) -> @types.Address? raise FixtureError {
  let s = as_string(j, path, "to")
  if s.length() == 0 {
    None
  } else {
    Some(as_address(j, path, "to"))
  }
}

///|
fn parse_quantity_array(
  j : Json,
  path : String,
  field : String,
) -> Array[@types.U256] raise FixtureError {
  let arr = as_array(j, path, field)
  let out : Array[@types.U256] = []
  for i in 0..<arr.length() {
    out.push(as_quantity(arr[i], path, "\{field}[\{i}]"))
  }
  out
}

///|
fn parse_data_array(j : Json, path : String) -> Array[Bytes] raise FixtureError {
  let arr = as_array(j, path, "data")
  let out : Array[Bytes] = []
  for i in 0..<arr.length() {
    out.push(as_hex_bytes(arr[i], path, "data[\{i}]"))
  }
  out
}

///|
fn parse_access_lists(
  j : Json,
  path : String,
) -> Array[Array[AccessTuple]] raise FixtureError {
  let arr = as_array(j, path, "accessLists")
  let out : Array[Array[AccessTuple]] = []
  for i in 0..<arr.length() {
    let list_path = "\{path}.accessLists[\{i}]"
    let inner = as_array(arr[i], list_path, "<accessList>")
    let tuples : Array[AccessTuple] = []
    for k in 0..<inner.length() {
      tuples.push(parse_access_tuple(inner[k], "\{list_path}[\{k}]"))
    }
    out.push(tuples)
  }
  out
}

///|
fn parse_access_tuple(
  j : Json,
  path : String,
) -> AccessTuple raise FixtureError {
  let obj = as_object(j, path, "<accessTuple>")
  let keys_json = as_array(
    field_of(obj, path, "storageKeys"),
    path,
    "storageKeys",
  )
  let keys : Array[@types.Hash32] = []
  for i in 0..<keys_json.length() {
    keys.push(as_hash32(keys_json[i], path, "storageKeys[\{i}]"))
  }
  {
    address: as_address(field_of(obj, path, "address"), path, "address"),
    storage_keys: keys,
  }
}

///|
/// `secretKey` 是 32 字节十六进制，但语义是标量而不是哈希；用 `Hash32` 做长度
/// 校验后再取 `U256`，避免两套长度检查。
fn as_hash32_like(j : Json, path : String) -> @types.U256 raise FixtureError {
  let h = as_hash32(j, path, "secretKey")
  @types.U256::from_bytes_be(h.as_bytes()) catch {
    _ =>
      raise FixtureError::HexInvalid(
        path~,
        field="secretKey",
        reason="expected 32-byte scalar",
      )
  }
}
