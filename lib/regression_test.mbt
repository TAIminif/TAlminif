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

///|
test "rebuilding and writing standard fields retain annotations and locks" {
  let original = sample_document().with_events([@lib.Event::new(0.0, "start")])
  let mut parameters = original.parameters
  for
    (group, name) in [
      ("POINT", "DATA_START"),
      ("POINT", "LABELS"),
      ("ANALOG", "SCALE"),
      ("EVENT", "USED"),
    ] {
    let value = parameters.require(group, name)
    parameters = parameters.set(group, {
      ..value,
      locked: true,
      description: b"annotation",
    })
  }
  let source = { ..original, parameters, }
  let changed = @lib.read(@lib.write(source.crop(0, 2), processor=@lib.Mips))
  for
    (group, name) in [
      ("POINT", "DATA_START"),
      ("POINT", "LABELS"),
      ("ANALOG", "SCALE"),
      ("EVENT", "USED"),
    ] {
    let value = changed.parameters.require(group, name)
    assert_true(value.locked)
    assert_eq(value.description, b"annotation")
  }
}
