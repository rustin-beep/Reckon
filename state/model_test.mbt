// 参考模型随机对拍：固定种子 LCG 生成 200 步操作，每一步都比对
// `State::accounts()` 与参考模型的 canonical 导出。
//
// 参考模型是**测试期**实现（不是生产代码）：状态 = `Map[Address, RefAccount]`，
// 只存非空账户与零值以上的槽；`snapshot` 整表深拷贝，`revert` 恢复拷贝。
// 回滚固定 LIFO，与生产侧的快照栈语义一致。
//
// 不用时间、不用系统随机，三后端结果必须一致。

///|
priv struct Lcg {
  mut state : UInt64
}

///|
fn Lcg::next(self : Lcg) -> UInt64 {
  self.state = self.state * 6364136223846793005UL + 1442695040888963407UL
  self.state
}

///|
priv struct RefAccount {
  nonce : UInt64
  balance : @types.U256
  code : Bytes
  slots : Map[@types.U256, @types.U256]
}

///|
fn ref_deep_copy(
  model : Map[@types.Address, RefAccount],
) -> Map[@types.Address, RefAccount] {
  let out : Map[@types.Address, RefAccount] = Map([])
  for (address, rec) in model.iter() {
    let slots : Map[@types.U256, @types.U256] = Map([])
    for (key, value) in rec.slots.iter() {
      slots.set(key, value)
    }
    out.set(address, {
      nonce: rec.nonce,
      balance: rec.balance,
      code: rec.code,
      slots,
    })
  }
  out
}

///|
fn ref_set(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
  rec : RefAccount,
) -> Unit {
  // 与生产侧一致：写空即等于删掉
  let empty = rec.nonce == 0UL &&
    rec.balance.is_zero() &&
    rec.code.length() == 0 &&
    rec.slots.is_empty()
  if empty {
    model.remove(address)
  } else {
    model.set(address, rec)
  }
}

///|
fn ref_set_balance(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
  value : @types.U256,
) -> Unit {
  match model.get(address) {
    None =>
      if !value.is_zero() {
        ref_set(model, address, {
          nonce: 0UL,
          balance: value,
          code: b"",
          slots: Map([]),
        })
      }
    Some(rec) =>
      ref_set(model, address, {
        nonce: rec.nonce,
        balance: value,
        code: rec.code,
        slots: rec.slots,
      })
  }
}

///|
fn ref_set_nonce(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
  value : UInt64,
) -> Unit {
  match model.get(address) {
    None =>
      if value != 0UL {
        ref_set(model, address, {
          nonce: value,
          balance: @types.U256::zero(),
          code: b"",
          slots: Map([]),
        })
      }
    Some(rec) =>
      ref_set(model, address, {
        nonce: value,
        balance: rec.balance,
        code: rec.code,
        slots: rec.slots,
      })
  }
}

///|
fn ref_set_code(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
  code : Bytes,
) -> Unit {
  match model.get(address) {
    None =>
      if code.length() != 0 {
        ref_set(model, address, {
          nonce: 0UL,
          balance: @types.U256::zero(),
          code,
          slots: Map([]),
        })
      }
    Some(rec) =>
      ref_set(model, address, {
        nonce: rec.nonce,
        balance: rec.balance,
        code,
        slots: rec.slots,
      })
  }
}

///|
fn ref_set_storage(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
  slot : @types.U256,
  value : @types.U256,
) -> Unit {
  match model.get(address) {
    None =>
      if !value.is_zero() {
        let slots : Map[@types.U256, @types.U256] = Map([])
        slots.set(slot, value)
        ref_set(model, address, {
          nonce: 0UL,
          balance: @types.U256::zero(),
          code: b"",
          slots,
        })
      }
    Some(rec) => {
      // 槽表按值复制：旧表可能被某个快照引用，不能原地改
      let slots : Map[@types.U256, @types.U256] = Map([])
      for (key, old) in rec.slots.iter() {
        if key != slot {
          slots.set(key, old)
        }
      }
      if !value.is_zero() {
        slots.set(slot, value)
      }
      ref_set(model, address, {
        nonce: rec.nonce,
        balance: rec.balance,
        code: rec.code,
        slots,
      })
    }
  }
}

///|
fn ref_destroy(
  model : Map[@types.Address, RefAccount],
  address : @types.Address,
) -> Unit {
  model.remove(address)
}

///|
fn ref_compare_slot(
  a : (@types.U256, @types.U256),
  b : (@types.U256, @types.U256),
) -> Int32 {
  a.0.compare(b.0)
}

///|
fn model_compare_entry(
  a : @state.AccountEntry,
  b : @state.AccountEntry,
) -> Int32 {
  a.address.compare(b.address)
}

///|
fn ref_export(
  model : Map[@types.Address, RefAccount],
) -> Array[@state.AccountEntry] {
  let out : Array[@state.AccountEntry] = []
  for (address, rec) in model.iter() {
    let slots : Array[(@types.U256, @types.U256)] = []
    for (key, value) in rec.slots.iter() {
      if !value.is_zero() {
        slots.push((key, value))
      }
    }
    slots.sort_by(ref_compare_slot)
    out.push({
      address,
      info: { nonce: rec.nonce, balance: rec.balance, code: rec.code, },
      storage: slots,
    })
  }
  out.sort_by(model_compare_entry)
  out
}

///|
fn assert_export(
  got : Array[@state.AccountEntry],
  want : Array[@state.AccountEntry],
  step : Int32,
) -> Unit raise {
  if got.length() != want.length() {
    fail("step \{step}: 账户数 \{got.length()} != \{want.length()}")
  }
  for i in 0..<got.length() {
    assert_true(
      got[i].same(want[i]),
      msg="step \{step}: 第 \{i} 个账户导出不一致",
    )
  }
}

///|
fn model_addr(n : Int32) -> @types.Address {
  let bytes = FixedArray::make(20, b'\x00')
  bytes[19] = n.to_byte()
  @types.Address::from_bytes_unchecked(Bytes::from_array(bytes)[:])
}

///|
test "参考模型 200 步随机对拍" {
  let addrs : Array[@types.Address] = []
  for i in 1..<7 {
    addrs.push(model_addr(i))
  }
  let slots : Array[@types.U256] = [
    @types.U256::zero(),
    @types.U256::one(),
    @types.U256::from_u64(2UL),
    @types.U256::max_value(),
  ]
  let values : Array[@types.U256] = [
    @types.U256::zero(),
    @types.U256::one(),
    @types.U256::from_u64(2UL),
    @types.U256::from_u64(3UL),
    @types.U256::from_u64(7UL),
    @types.U256::from_u64(100UL),
    @types.U256::from_u64(255UL),
    @types.U256::max_value(),
  ]
  let codes : Array[Bytes] = [b"", b"\x60\x00", b"\x60\x00\x60\x01"]
  let lcg : Lcg = { state: 20261121UL, }
  let s = @state.State::new()
  let mut model : Map[@types.Address, RefAccount] = Map([])
  let prod_snaps : Array[@state.Snapshot] = []
  let ref_snaps : Array[Map[@types.Address, RefAccount]] = []
  // 计数用来兜住「随机序列退化成空转」：对拍本身在两边都空时也会通过
  let mut snap_count = 0
  let mut revert_count = 0
  let mut max_accounts = 0
  for step in 0..<200 {
    let r = lcg.next()
    let op = (r % 8UL).to_int()
    let a = addrs[((r >> 8) % 6UL).to_int()]
    let slot = slots[((r >> 16) % 4UL).to_int()]
    let value = values[((r >> 24) % 8UL).to_int()]
    let code = codes[((r >> 32) % 3UL).to_int()]
    if op == 0 {
      s.set_balance(a, value)
      ref_set_balance(model, a, value)
    } else if op == 1 {
      let nonce = (r >> 40) % 5UL
      s.set_nonce(a, nonce)
      ref_set_nonce(model, a, nonce)
    } else if op == 2 {
      s.set_code(a, code)
      ref_set_code(model, a, code)
    } else if op == 3 {
      s.set_storage(a, slot, value)
      ref_set_storage(model, a, slot, value)
    } else if op == 4 {
      s.create_account(a)
      // canonical 视图里建空账户没有可见效果
    } else if op == 5 {
      s.destroy_account(a)
      ref_destroy(model, a)
    } else if op == 6 {
      prod_snaps.push(s.snapshot())
      ref_snaps.push(ref_deep_copy(model))
      snap_count = snap_count + 1
    } else if prod_snaps.length() > 0 {
      // 回滚固定 LIFO
      let snapshot = prod_snaps.pop().unwrap()
      s.revert(snapshot)
      let saved = ref_snaps.pop().unwrap()
      model = ref_deep_copy(saved)
      revert_count = revert_count + 1
    }
    assert_export(s.accounts(), ref_export(model), step)
    if s.accounts().length() > max_accounts {
      max_accounts = s.accounts().length()
    }
  }
  // 收尾：把所有还挂着的快照逐个回滚，每一步仍然对拍
  let mut count = 0
  while prod_snaps.length() > 0 && count < 300 {
    let snapshot = prod_snaps.pop().unwrap()
    s.revert(snapshot)
    let saved = ref_snaps.pop().unwrap()
    model = ref_deep_copy(saved)
    assert_export(s.accounts(), ref_export(model), 200 + count)
    count = count + 1
  }
  assert_eq(prod_snaps.length(), 0)
  // 这条测试必须真的覆盖到快照、回滚与多账户
  assert_true(snap_count >= 10, msg="快照次数 \{snap_count}")
  assert_true(revert_count >= 10, msg="回滚次数 \{revert_count}")
  assert_true(max_accounts >= 3, msg="最大账户数 \{max_accounts}")
}
