///|
test "C3D header exact offsets and IEEE processor check" {
  let header = Header::new(2, 100.0)
  let params = write_parameters(Parameters::empty())
  let data = write_header(header) + params
  assert_eq(u16(data, 2), 2)
  assert_eq(f32(data, 12), Float::from_double(-0.01).to_double())
  assert_eq(u16(data, 16), 3)
  assert_eq(f32(data, 20), 100.0)
  let decoded = read_header(data)
  assert_eq(decoded.point_count, 2)
  assert_eq(decoded.scale, Float::from_double(header.scale).to_double())
  let other = data.to_array()
  other[515] = 85
  expect_error(() => read_header(Bytes::from_array(other)))
}

///|
test "POINT frame count overrides raw header video range" {
  let header = { ..Header::new(0, 100.0), first_frame: 100, last_frame: 200 }
  let params = Parameters::empty().put_int("POINT", "FRAMES", 3)
  let (first, count) = resolve_frame_range(header, params, Limits::default())
  assert_eq(first, 1)
  assert_eq(count, 3)
}

///|
test "trial long frame fields and conflicting counts" {
  let params = Parameters::empty()
    .set("POINT", Parameter::unsigned("FRAMES", 65535))
    .put_real("POINT", "LONG_FRAMES", 70000.0)
    .set("TRIAL", Parameter::unsigneds("ACTUAL_START_FIELD", [1, 0]))
    .set("TRIAL", Parameter::unsigneds("ACTUAL_END_FIELD", [4464, 1]))
  let (_, count) = resolve_frame_range(
    Header::new(0, 100.0),
    params,
    Limits::default(),
  )
  assert_eq(count, 70000)
  expect_error(() => {
    resolve_frame_range(
      Header::new(0, 100.0),
      params.put_int("POINT", "FRAMES", 4),
      Limits::default(),
    )
  })
}
