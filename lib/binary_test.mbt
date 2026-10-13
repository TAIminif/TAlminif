///|
fn[A] expect_error(action : () -> A raise @lib.C3dError) -> Unit raise {
  try action() catch {
    _ => ()
  } noraise {
    _ => fail("expected C3dError")
  }
}

///|
test "little endian golden values and bounds" {
  let data = b"\x00\x80\xff\xff\x00\x00\x80\x3f"
  assert_eq(@lib.u16(data, 0), 32768)
  assert_eq(@lib.i16(data, 0), -32768)
  assert_eq(@lib.i16(data, 2), -1)
  assert_eq(@lib.f32(data, 4), 1.0)
  expect_error(() => @lib.u32(data, 5))
  expect_error(() => @lib.u8(data, -1))
}

///|
test "size arithmetic and bounded text" {
  assert_eq(@lib.checked_mul(4, 512, "blocks"), 2048)
  expect_error(() => @lib.checked_mul(2147483647, 2, "overflow"))
  expect_error(() => @lib.checked_add(2147483647, 1, "overflow"))
  assert_eq(@lib.ascii(b"POINT"), "POINT")
  expect_error(() => @lib.ascii(b"\xff"))
  assert_eq(@lib.utf8_text(@lib.utf8_bytes("标记点")), "标记点")
  expect_error(() => @lib.utf8_text(b"\xff"))
}

///|
test "numeric narrowing and hex byte interchange" {
  assert_eq(@lib.hex_bytes(@lib.parse_hex("00Ff80")), "00ff80")
  expect_error(() => @lib.parse_hex("abc"))
  expect_error(() => @lib.parse_hex("xx"))
  expect_error(() => @lib.parse_hex("0102", max_bytes=1))
  assert_eq(@lib.round_int(12.49, 0, 20, "sample"), 12)
  expect_error(() => @lib.exact_int(12.5, 0, 20, "count"))
  expect_error(() => @lib.round_int(70000.0, 0, 65535, "header"))
}
