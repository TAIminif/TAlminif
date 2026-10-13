///|
test "interchange rejects conflicting or overflowing frame numbers" {
  let text = document_json(sample_document()).stringify()
  let conflicting = text.replace(old="\"number\":1", new="\"number\":9")
  expect_error(() => import_json(conflicting))
  let overflow = text.replace(
    old="\"first_frame\":1",
    new="\"first_frame\":2147483647",
  )
  expect_error(() => import_json(overflow))
}

///|
test "every structural truncation before the data boundary is rejected" {
  let data = write(sample_document())
  let layout = Reader::new(data).layout()
  let required = layout.data_offset + layout.frame_bytes * layout.frame_count
  for length in 0..<required {
    expect_error(() => Reader::new(data[0:length].to_owned()))
  }
  assert_eq(Reader::new(data[0:required].to_owned()).remaining(), 3)
}
