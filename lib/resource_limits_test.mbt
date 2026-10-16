///|
fn[A] expect_resource_limit(action : () -> A raise @lib.C3dError) -> Unit raise {
  try action() catch {
    error => assert_eq(error.kind(), "resource_limit")
  } noraise {
    _ => fail("expected resource limit")
  }
}

///|
test "JSON metadata limits apply to supplied and generated core parameters" {
  let limits = { ..@lib.Limits::default(), max_parameters: 1, }
  let original = @lib.document_json(sample_document())
  expect_resource_limit(() => @lib.parse_document_json(original, limits~))
  expect_resource_limit(() => {
    @lib.parse_document_json(
      { "point_labels": ["P"], "analog_channels": [], "frames": [] },
      limits~,
    )
  })
  let no_text = { ..@lib.Limits::default(), max_text_bytes: 0, }
  expect_resource_limit(() => @lib.parse_document_json(original, limits=no_text))
  expect_resource_limit(() => @lib.write(sample_document(), limits=no_text))
  let data = @lib.write(sample_document())
  expect_resource_limit(() => @lib.read(data, limits=no_text))
}

///|
test "JSON input byte budget counts UTF8 rather than UTF16 length" {
  let text = "{\"point_labels\":[\"点😀\"],\"analog_channels\":[],\"frames\":[],\"point_unit\":\"\"}" +
    @lib.utf8_text(Bytes::make(512, 32))
  let bytes = @lib.utf8_bytes(text).length()
  assert_true(bytes > text.length())
  let exact = { ..@lib.Limits::default(), max_file_bytes: bytes, }
  let imported = @lib.import_json(text, limits=exact)
  assert_eq(imported.layout.point_labels, ["点😀"])
  expect_resource_limit(() => {
    @lib.import_json(text, limits={ ..exact, max_file_bytes: bytes - 1, })
  })
}

///|
test "relaxed limits survive JSON construction and metadata rebuild" {
  let limits = { ..@lib.Limits::default(), max_subsamples: 2049, }
  let channel : @lib.Channel = {
    label: "A",
    description: "",
    unit: "",
    scale: 1.0,
    offset: 0.0,
  }
  let frame : @lib.Frame = {
    number: 1,
    points: [],
    analog: [Array::make(2049, 1.0)],
  }
  let original = @lib.Document::new(
    [],
    [channel],
    [frame],
    analog_subsamples=2049,
    limits~,
  )
  let imported = @lib.parse_document_json(@lib.document_json(original), limits~)
  assert_eq(imported.layout.analog_subsamples, 2049)
  assert_eq(imported.frames[0].analog[0].length(), 2049)
  let decoded = @lib.read(@lib.write(imported, limits~), limits~)
  assert_eq(decoded.frames, imported.frames)
  expect_error(() => @lib.parse_document_json(@lib.document_json(original)))
}

///|
test "parameter text budget includes identifiers descriptions and character bytes" {
  let value = { ..@lib.Parameter::text("Y", "点"), description: b"b", }
  let parameters = @lib.Parameters::empty()
    .add_group("X", description="a")
    .set("X", value)
  // X + a + Y + b + the three UTF-8 bytes of 点.
  let exact = { ..@lib.Limits::default(), max_text_bytes: 7, }
  let file = @lib.write_parameter_file(parameters, limits=exact)
  assert_eq(@lib.read_parameter_file(file, limits=exact), parameters)
  assert_eq(
    @lib.parse_parameters_json(@lib.parameters_json(parameters), limits=exact),
    parameters,
  )
  let small = { ..exact, max_text_bytes: 6, }
  expect_resource_limit(() => {
    @lib.write_parameter_file(parameters, limits=small)
  })
  expect_resource_limit(() => @lib.read_parameter_file(file, limits=small))
  expect_resource_limit(() => {
    @lib.parse_parameters_json(@lib.parameters_json(parameters), limits=small)
  })
  let numeric = @lib.Parameters::empty().set(
    "X",
    @lib.Parameter::reals("Y", Array::make(255, 1.0)),
  )
  @lib.validate_parameters(numeric, limits={
    ..@lib.Limits::default(),
    max_text_bytes: 2,
  })
}

///|
test "semantic text budget covers every decoded metadata field in UTF8 bytes" {
  let original = sample_document()
  let layout = {
    ..original.layout,
    point_labels: ["点"],
    point_descriptions: ["😀"],
    point_unit: "u",
    analog_channels: [
      { label: "a", description: "b", unit: "c", scale: 1.0, offset: 0.0, },
    ],
  }
  let event : @lib.Event = {
    ..@lib.Event::new(0.0, "d"),
    context: "e",
    description: "f",
    subject: "g",
  }
  // 3 + 4 + 1 + 3 channel bytes + 4 event bytes = 15.
  let exact = { ..@lib.Limits::default(), max_text_bytes: 15, }
  @lib.validate_semantic_text(layout, [event], exact)
  expect_resource_limit(() => {
    @lib.validate_semantic_text(layout, [event], {
      ..exact,
      max_text_bytes: 14,
    })
  })
}
