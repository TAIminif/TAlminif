///|
test "semantic JSON preserves samples and extension metadata" {
  let original = sample_document().with_events([@lib.Event::new(0.01, "step")])
  let original = {
    ..original,
    parameters: original.parameters.put_text("CUSTOM", "TAG", "中文"),
  }
  let imported = @lib.import_json(@lib.document_json(original).stringify())
  assert_eq(imported.frames, original.frames)
  assert_eq(imported.events, original.events)
  assert_eq(imported.parameters.require("CUSTOM", "TAG").text_values(), [
    "中文",
  ])
  assert_eq(@lib.read(@lib.write(imported)).layout.point_labels, ["L", "R"])
}

///|
test "JSON input rejects wrong shapes unknown fields and oversized samples" {
  expect_error(() => @lib.import_json("{bad"))
  expect_error(() => {
    @lib.parse_marker_json({ "x": 1, "y": 2, "z": 3, "typo": true })
  })
  expect_error(() => @lib.parse_marker_json({ "x": "oops", "y": 2, "z": 3 }))
  let original = @lib.document_json(sample_document())
  expect_error(() => {
    @lib.parse_document_json(original, limits={
      ..@lib.Limits::default(),
      max_frames: 1,
    })
  })
}
