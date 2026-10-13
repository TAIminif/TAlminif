///|
test "interchange rejects conflicting or overflowing frame numbers" {
  let text = @lib.document_json(sample_document()).stringify()
  let conflicting = text.replace(old="\"number\":1", new="\"number\":9")
  expect_error(() => @lib.import_json(conflicting))
  let overflow = text.replace(
    old="\"first_frame\":1",
    new="\"first_frame\":2147483647",
  )
  expect_error(() => @lib.import_json(overflow))
}

///|
test "every structural truncation before the data boundary is rejected" {
  let data = @lib.write(sample_document())
  let layout = @lib.Reader::new(data).layout()
  let required = layout.data_offset + layout.frame_bytes * layout.frame_count
  for length in 0..<required {
    expect_error(() => @lib.Reader::new(data[0:length].to_owned()))
  }
  assert_eq(@lib.Reader::new(data[0:required].to_owned()).remaining(), 3)
}
