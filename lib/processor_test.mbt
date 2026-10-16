///|
fn processor_bytes(
  value : Double,
  processor : @lib.Processor,
) -> Bytes raise @lib.C3dError {
  let out = @buffer.Buffer::Buffer()
  @lib.put_encoded_f32(out, value, processor)
  out.to_bytes()
}

///|
test "C3D processor identifiers and signed endian golden values" {
  assert_eq(@lib.processor_from_id(84), @lib.Processor::Intel)
  assert_eq(@lib.processor_from_name("DEC/VAX"), @lib.Processor::Dec)
  assert_eq(@lib.processor_from_name("SGI"), @lib.Processor::Mips)
  assert_eq(@lib.Processor::Dec.processor_id(), 85)
  assert_eq(@lib.Processor::Mips.name(), "mips")
  expect_error(() => @lib.processor_from_id(87))
  expect_error(() => @lib.processor_from_name("native"))
  assert_eq(@lib.encoded_u16(b"\x80\x01", 0, Mips), 32769)
  assert_eq(@lib.encoded_i16(b"\x80\x01", 0, Mips), -32767)
  assert_eq(@lib.encoded_i16(b"\x01\x80", 0, Dec), -32767)
  assert_eq(@lib.encoded_u32(b"\x12\x34\x56\x78", 0, Mips), 0x12345678U)
  expect_error(() => @lib.encoded_f32(b"\x00\x00\x00", 0, Intel))
  let section = @buffer.Buffer::Buffer()
  for _ in 0..<512 {
    section.write_byte(0)
  }
  section.write_bytes(b"\x00\x50\x01\x55"[:])
  assert_eq(@lib.read_processor(section.to_bytes(), 2), Dec)
  expect_error(() => @lib.read_processor(section.to_bytes(), 3))
  expect_error(() => @lib.read_processor(section.to_bytes(), 0))
}

///|
test "C3D floating golden byte patterns for all three processors" {
  let golden : Array[(@lib.Processor, Bytes, Bytes)] = [
    (Intel, b"\x00\x00\x80\x3f", b"\x00\x00\x20\xc0"),
    (Mips, b"\x3f\x80\x00\x00", b"\xc0\x20\x00\x00"),
    (Dec, b"\x80\x40\x00\x00", b"\x20\xc1\x00\x00"),
  ]
  for (processor, one, minus_two_half) in golden {
    assert_eq(@lib.encoded_f32(one, 0, processor), 1.0)
    assert_eq(@lib.encoded_f32(minus_two_half, 0, processor), -2.5)
    assert_eq(processor_bytes(1.0, processor), one)
    assert_eq(processor_bytes(-2.5, processor), minus_two_half)
  }
}

///|
test "VAX low exponent fractions remain exact binary64 values" {
  let minimum = 0x37f0000000000000UL.reinterpret_as_double() // 2^-128
  let step = 0x3680000000000000UL.reinterpret_as_double() // 2^-151
  let one = b"\x80\x00\x00\x00"
  let next = b"\x80\x00\x01\x00"
  let max_low = b"\xff\x00\xff\xff"
  assert_eq(@lib.encoded_f32(one, 0, Dec), minimum)
  assert_eq(@lib.encoded_f32(next, 0, Dec), minimum + step)
  assert_eq(@lib.encoded_f32(max_low, 0, Dec), 2.0 * minimum - step)
  assert_eq(processor_bytes(minimum + step, Dec), next)
  assert_eq(processor_bytes(2.0 * minimum - step, Dec), max_low)
  assert_eq(
    @lib.encoded_f32(b"\x00\x01\x01\x00", 0, Dec),
    2.0 * (minimum + step),
  )
  expect_error(() => processor_bytes(minimum * 0.5, Dec))
}

///|
test "VAX reserved operands and dirty zero follow the architecture" {
  assert_eq(@lib.encoded_f32(b"\x00\x00\x00\x00", 0, Dec), 0.0)
  assert_eq(@lib.encoded_f32(b"\x7f\x00\xff\xff", 0, Dec), 0.0)
  assert_eq(processor_bytes(-0.0, Dec), b"\x00\x00\x00\x00")
  expect_error(() => @lib.encoded_f32(b"\x00\x80\x00\x00", 0, Dec))
  expect_error(() => @lib.encoded_f32(b"\x7f\x80\xff\xff", 0, Dec))
  expect_error(() => {
    processor_bytes(Float::reinterpret_from_uint(0x7f800000U).to_double(), Dec)
  })
  expect_error(() => {
    processor_bytes(Float::reinterpret_from_uint(0x7fc00000U).to_double(), Dec)
  })
}

///|
test "all VAX normal exponents retain 24 significant bits through binary64" {
  for exponent in 1..<256 {
    for fraction in [0, 1, 0x3fffff, 0x7fffff] {
      for sign in [0, 32768] {
        let out = @buffer.Buffer::Buffer()
        @lib.put_u16(out, sign | (exponent << 7) | (fraction >> 16))
        @lib.put_u16(out, fraction & 65535)
        let raw = out.to_bytes()
        let decoded = @lib.encoded_f32(raw, 0, Dec)
        assert_eq(processor_bytes(decoded, Dec), raw)
      }
    }
  }
}

///|
test "VAX round-to-even carries and overflow are checked before writing" {
  let half_ulp = 0x3e70000000000000UL.reinterpret_as_double() // 2^-24
  assert_eq(processor_bytes(1.0 + half_ulp, Dec), b"\x80\x40\x00\x00")
  assert_eq(processor_bytes(1.0 + 3.0 * half_ulp, Dec), b"\x80\x40\x02\x00")
  assert_eq(processor_bytes(2.0 - half_ulp, Dec), b"\x00\x41\x00\x00")
  let highest = b"\xff\x7f\xff\xff"
  let maximum = @lib.encoded_f32(highest, 0, Dec)
  assert_eq(processor_bytes(maximum, Dec), highest)
  let threshold = 0x47dffffff0000000UL.reinterpret_as_double() // top-bin midpoint
  expect_error(() => processor_bytes(threshold, Dec))
  expect_error(() => processor_bytes(maximum * 2.0, Dec))
}

///|
test "numeric parameter transcoding preserves raw IEEE payload bits" {
  let source = b"\x00\x00\x00\x80\x45\x23\xc1\x7f"
  let big = @lib.transcode_parameter_data(4, source, Intel, Mips)
  assert_eq(big, b"\x80\x00\x00\x00\x7f\xc1\x23\x45")
  assert_eq(@lib.transcode_parameter_data(4, big, Mips, Intel), source)
  assert_eq(
    @lib.transcode_parameter_data(2, b"\xff\xff\x00\x80", Intel, Mips),
    b"\xff\xff\x80\x00",
  )
  assert_eq(
    @lib.transcode_parameter_data(4, b"\x80\x40\x00\x00", Dec, Mips),
    b"\x3f\x80\x00\x00",
  )
  assert_eq(@lib.transcode_parameter_data(-1, b"C3D", Dec, Mips), b"C3D")
  expect_error(() => @lib.transcode_parameter_data(2, b"\x01", Intel, Mips))
  expect_error(() => @lib.transcode_parameter_data(4, source, Intel, Dec))
}
