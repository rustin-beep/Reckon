// EEST state test 的强类型模型。
//
// 只建模 B06/B08 需要的部分：`config`（只取 chainid）、`env`、`pre`、`post`、
// `transaction`。字段语义的事实来源是 EEST v5.4.0 stable（commit `4f68564`）的
// 抽样与 evmone `probes/difftest/statetest.hpp`：
//
//   - `to: ""` 表示合约创建，不是 `null`；
//   - `gasLimit` / `value` / `data` 是数组，由 `indexes` 选择；
//   - `accessLists` 是「数组的数组」，按 `indexes.data` 选择；
//   - `txbytes` 不一定存在（evmone 注释 `Not always available`）；
//   - `expectException` 是 `|` 分隔的备选串。
//
// 本包是纯解析：不碰文件系统，不执行 EVM，不比对 state root。

// ---------------------------------------------------------------------------
// 错误
// ---------------------------------------------------------------------------

///|
/// fixture 加载期的错误。
///
/// 所有路径都带 JSON 路径（如 `pre.0xabc….nonce`）或字段名，便于把失败定位到
/// fixture 的具体位置；`DecodeError` / `ParseError` 不向外泄漏，一律在这里归类。
pub suberror FixtureError {
  /// JSON 文本本身不合法（含重复键、嵌套过深）。
  JsonParse(message~ : String)
  /// 必需字段缺失。
  FieldMissing(path~ : String, field~ : String)
  /// 字段类型不符。
  FieldType(path~ : String, field~ : String, expected~ : String)
  /// 十六进制文本不合法。
  HexInvalid(path~ : String, field~ : String, reason~ : String)
  /// 定宽字段的字节数不对。
  LengthInvalid(
    path~ : String,
    field~ : String,
    expected~ : Int32,
    actual~ : Int32,
  )
  /// 数量字段超出目标宽度（`U256` 转 `UInt64` 前的高位非零）。
  IntegerTooLarge(path~ : String, field~ : String)
  /// `indexes` 的值落在对应数组范围外。
  IndexOutOfRange(
    path~ : String,
    field~ : String,
    value~ : Int32,
    limit~ : Int32,
  )
  /// `accessLists` 的条数与 `indexes.data` 的取值域不匹配。
  AccessListArity(path~ : String, lists~ : Int32, inputs~ : Int32)
  /// 文档里没有请求的 fork。
  ForkNotFound(fork~ : String, available~ : Array[String])
  /// 顶层是空对象。
  EmptyDocument
  /// 账户地址重复（`pre` / `post.state` 内）。
  DuplicateAccount(path~ : String, address~ : String)
}

///|
pub impl Show for FixtureError with fn to_string(self) -> String {
  match self {
    JsonParse(message~) => "json: \{message}"
    FieldMissing(path~, field~) => "\{path}: missing field `\{field}`"
    FieldType(path~, field~, expected~) =>
      "\{path}: field `\{field}` expected \{expected}"
    HexInvalid(path~, field~, reason~) =>
      "\{path}: field `\{field}` is not valid hex (\{reason})"
    LengthInvalid(path~, field~, expected~, actual~) =>
      "\{path}: field `\{field}` expected \{expected} bytes, got \{actual}"
    IntegerTooLarge(path~, field~) =>
      "\{path}: field `\{field}` does not fit in 64 bits"
    IndexOutOfRange(path~, field~, value~, limit~) =>
      "\{path}: index `\{field}` = \{value} out of range (limit \{limit})"
    AccessListArity(path~, lists~, inputs~) =>
      "\{path}: accessLists has \{lists} entries but indexes.data domain is \{inputs}"
    ForkNotFound(fork~, available~) =>
      "fork `\{fork}` not present; available: \{join_comma(available)}"
    EmptyDocument => "document has no test entries"
    DuplicateAccount(path~, address~) =>
      "\{path}: account \{address} appears twice"
  }
}

///|
pub extend FixtureError with Show::{to_string, output}

///|
fn join_comma(items : Array[String]) -> String {
  let buf = StringBuilder()
  let mut first = true
  for item in items {
    if !first {
      buf.write_string(", ")
    }
    buf.write_string(item)
    first = false
  }
  buf.to_string()
}

// ---------------------------------------------------------------------------
// 基础结构
// ---------------------------------------------------------------------------

///|
/// `indexes`：从 `gasLimit` / `value` / `data` 三个数组里各选一个元素。
#derive(Debug)
pub(all) struct Indexes {
  data : Int32
  gas : Int32
  value : Int32
}

///|
pub impl Show for Indexes with fn to_string(self) -> String {
  "data=\{self.data},gas=\{self.gas},value=\{self.value}"
}

///|
pub extend Indexes with Show::{to_string, output}

///|
/// 一个 access list 元组：地址 + 存储键列表。
#derive(Debug)
pub(all) struct AccessTuple {
  address : @types.Address
  storage_keys : Array[@types.Hash32]
}

///|
/// 两个元组是否等价（地址相同、键序列逐项相同）。
///
/// 顺序敏感：RLP 里 `storageKeys` 是数组，重编码必须保持原序。
pub fn AccessTuple::same(self : AccessTuple, other : AccessTuple) -> Bool {
  if self.address != other.address {
    return false
  }
  if self.storage_keys.length() != other.storage_keys.length() {
    return false
  }
  for i in 0..<self.storage_keys.length() {
    if self.storage_keys[i] != other.storage_keys[i] {
      return false
    }
  }
  true
}

///|
/// 块环境（`env`）。数量字段已校验过 `U256` 的高位，超过 64 位直接报错。
#derive(Debug)
pub(all) struct BlockEnv {
  coinbase : @types.Address
  gas_limit : UInt64
  number : UInt64
  timestamp : UInt64
  random : @types.Hash32
  difficulty : @types.U256
  base_fee : @types.U256
  excess_blob_gas : UInt64
}

///|
/// 一个账户的 alloc 条目（`pre` 与 `post.state` 共用）。
///
/// `storage` 的键值在 EEST 里写成**数量**（如 `"0x01"`、`"0xff"`），不是 32 字节
/// 哈希——抽样 5 个 fixture 与 `fixtures/.meta` 一致。这里按 `U256` 保存，
/// 与将来 `state/` 的槽位类型一致。
#derive(Debug)
pub(all) struct AccountAlloc {
  nonce : UInt64
  balance : @types.U256
  code : Bytes
  storage : Array[(@types.U256, @types.U256)]
}

///|
/// 账户表。保序（按 JSON 出现顺序），并提供按地址查找。
#derive(Debug)
pub(all) struct Alloc {
  entries : Array[(@types.Address, AccountAlloc)]
}

///|
pub fn Alloc::length(self : Alloc) -> Int32 {
  self.entries.length()
}

///|
pub fn Alloc::lookup(self : Alloc, address : @types.Address) -> AccountAlloc? {
  let mut i = 0
  while i < self.entries.length() {
    let (addr, account) = self.entries[i]
    if addr == address {
      return Some(account)
    }
    i = i + 1
  }
  None
}

// ---------------------------------------------------------------------------
// 交易
// ---------------------------------------------------------------------------

///|
/// 交易类型。type 4（EIP-7702）只在 JSON 模板层识别，txbytes 解码一律返回
/// `UnsupportedType(4)`，留给 P02。
#derive(Debug)
pub(all) enum TxType {
  Legacy
  Type1
  Type2
  Type3
  Type4
}

///|
pub impl Show for TxType with fn to_string(self) -> String {
  match self {
    Legacy => "legacy"
    Type1 => "type1"
    Type2 => "type2"
    Type3 => "type3"
    Type4 => "type4"
  }
}

///|
pub extend TxType with Show::{to_string, output}

///|
/// `transaction`：一个模板 + 三组可索引数组。
///
/// `gasLimit` / `value` / `data` 是数组；`accessLists` 是「数组的数组」，
/// 与 `data` 同索引域（见 `statetest.hpp` 的 `access_lists.at(indexes.input)`）。
#derive(Debug)
pub(all) struct TxTemplate {
  tx_type : TxType
  nonce : @types.U256
  /// legacy / type1 的 `gasPrice`；其余类型为零值，读取方应看 `tx_type`。
  gas_price : @types.U256
  /// type2 / type3 的 `maxPriorityFeePerGas`。
  max_priority_fee_per_gas : @types.U256
  /// type2 / type3 的 `maxFeePerGas`。
  max_fee_per_gas : @types.U256
  gas_limits : Array[@types.U256]
  /// `None` 表示合约创建（JSON 里的 `""`）。
  to : @types.Address?
  values : Array[@types.U256]
  datas : Array[Bytes]
  /// `None` 表示 fixture 没有该字段（legacy）；`Some([])` 表示空列表。
  access_lists : Array[Array[AccessTuple]]?
  /// type3 的 `maxFeePerBlobGas`。
  max_fee_per_blob_gas : @types.U256
  /// type3 的 `blobVersionedHashes`（扁平数组，不是数组的数组）。
  blob_versioned_hashes : Array[@types.Hash32]
  sender : @types.Address
  secret_key : @types.U256
}

// ---------------------------------------------------------------------------
// post
// ---------------------------------------------------------------------------

///|
/// `post[fork]` 的一个条目。
#derive(Debug)
pub(all) struct PostEntry {
  /// 期望的 state root。B06 只保存，不算 MPT。
  state_hash : @types.Hash32
  /// 期望的 logs hash。B06 只保存。
  logs_hash : @types.Hash32
  state : Alloc
  /// 展开后的交易字节。字段缺失或空串时为 `None`（evmone：`Not always available`）。
  txbytes : Bytes?
  /// `txbytes` 字段本身是否存在（区分「缺失」与「空串」，给 B09 统计用）。
  txbytes_field_present : Bool
  indexes : Indexes
  /// `expectException` 按 `|` 切开后的备选串；空数组表示期望交易合法。
  expect_exception : Array[String]
}

// ---------------------------------------------------------------------------
// fixture
// ---------------------------------------------------------------------------

///|
/// 一个 EEST state test（JSON 顶层的一个键）。
#derive(Debug)
pub(all) struct Fixture {
  /// 测试名，即 JSON 顶层的键。
  name : String
  chain_id : @types.U256
  env : BlockEnv
  pre : Alloc
  /// 保序的 `(fork, entries)`。
  post : Array[(String, Array[PostEntry])]
  tx : TxTemplate
}

///|
/// `post` 里出现的 fork 名，按字典序。
pub fn Fixture::forks(self : Fixture) -> Array[String] {
  let out : Array[String] = []
  for (fork, _) in self.post {
    out.push(fork)
  }
  out.sort()
  out
}

///|
/// 取某个 fork 的条目；`None` 表示该 fixture 不含这个 fork。
pub fn Fixture::post_for(self : Fixture, fork : String) -> Array[PostEntry]? {
  for (name, entries) in self.post {
    if name == fork {
      return Some(entries)
    }
  }
  None
}

// ---------------------------------------------------------------------------
// 展开后的 case
// ---------------------------------------------------------------------------

///|
/// 一个 `(fixture, fork, post entry)` 展开后的扁平 case。
///
/// 所有随 `indexes` 变化或与交易字段直接对应的值都在这里：后续 tx 解码与
/// JSON 核对都用这一份视图，避免两处各取一次索引。
#derive(Debug)
pub(all) struct Case {
  fixture_name : String
  fork : String
  /// 在 `post[fork]` 数组里的下标，报错时用来定位。
  entry_index : Int32
  indexes : Indexes
  tx_type : TxType
  nonce : @types.U256
  gas_price : @types.U256
  max_priority_fee_per_gas : @types.U256
  max_fee_per_gas : @types.U256
  gas_limit : @types.U256
  value : @types.U256
  data : Bytes
  access_list : Array[AccessTuple]
  to : @types.Address?
  max_fee_per_blob_gas : @types.U256
  blob_versioned_hashes : Array[@types.Hash32]
  txbytes : Bytes?
  txbytes_field_present : Bool
  expect_exception : Array[String]
}
