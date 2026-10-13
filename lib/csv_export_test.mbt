///|
test "CSV preserves quoted labels missing markers and analog timestamps" {
  let original = sample_document()
  let document = original.rename_point(0, "左,\"heel\"")
  let reader = @lib.Reader::new(@lib.write(document))
  let points = @lib.points_csv(reader)
  assert_true(points.contains("\"左,\"\"heel\"\"\""))
  assert_true(points.contains("false,,,,,"))
  let analog = @lib.analog_csv(reader)
  assert_true(analog.contains("1,1,0.005,0,force,N,2"))
  expect_error(() => @lib.points_csv(reader, maximum_bytes=16))
}
