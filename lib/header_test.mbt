///|
test "C3D header exact offsets and IEEE processor check" {
  let header = @lib.Header::new(2, 100.0)
  let params = @lib.write_parameters(@lib.Parameters::empty())
  let data = @lib.write_header(header) + params
  assert_eq(@lib.u16(data, 2), 2)
  assert_eq(@lib.f32(data, 12), Float::from_double(-0.01).to_double())
  assert_eq(@lib.u16(data, 16), 3)
  assert_eq(@lib.f32(data, 20), 100.0)
  let decoded = @lib.read_header(data)
  assert_eq(decoded.point_count, 2)
  assert_eq(decoded.scale, Float::from_double(header.scale).to_double())
  let other = data.to_array()
  other[515] = 85
  expect_error(() => @lib.read_header(Bytes::from_array(other)))
}

///|
test "POINT frame count overrides raw header video range" {
  let header = {
    ..@lib.Header::new(0, 100.0),
    first_frame: 100,
    last_frame: 200,
  }
  let params = @lib.Parameters::empty().put_int("POINT", "FRAMES", 3)
  let (first, count) = @lib.resolve_frame_range(
    header,
    params,
    @lib.Limits::default(),
  )
  assert_eq(first, 1)
  assert_eq(count, 3)
}

///|
test "trial long frame fields and conflicting counts" {
  let params = @lib.Parameters::empty()
    .set("POINT", @lib.Parameter::unsigned("FRAMES", 65535))
    .put_real("POINT", "LONG_FRAMES", 70000.0)
    .set("TRIAL", @lib.Parameter::unsigneds("ACTUAL_START_FIELD", [1, 0]))
    .set("TRIAL", @lib.Parameter::unsigneds("ACTUAL_END_FIELD", [4464, 1]))
  let (_, count) = @lib.resolve_frame_range(
    @lib.Header::new(0, 100.0),
    params,
    @lib.Limits::default(),
  )
  assert_eq(count, 70000)
  expect_error(() => {
    @lib.resolve_frame_range(
      @lib.Header::new(0, 100.0),
      params.put_int("POINT", "FRAMES", 4),
      @lib.Limits::default(),
    )
  })
}
