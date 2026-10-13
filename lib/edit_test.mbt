///|
test "crop synchronizes analog frames events and numbering" {
  let original = sample_document().with_events([
    @lib.Event::new(0.0, "before"),
    @lib.Event::new(0.01, "start"),
    @lib.Event::new(0.029, "inside"),
    @lib.Event::new(0.03, "end"),
  ])
  let cropped = original.crop(1, 3)
  assert_eq(cropped.frames.length(), 2)
  assert_eq(cropped.frames[0].number, 1)
  assert_eq(cropped.frames[0].analog, [[3.0, 4.0]])
  assert_eq(cropped.events.map(e => e.label), ["start", "inside"])
  assert_eq(cropped.events[0].time, 0.0)
  assert_eq(@lib.read(@lib.write(cropped)).frames.length(), 2)
  assert_eq(original.frames.length(), 3)
  let absolute = original.crop(1, 3, rebase=false)
  assert_eq(@lib.read(@lib.write(absolute)).frames[0].number, 2)
  assert_eq(absolute.events[0].time, 0.01)
}

///|
test "selection rewrites required metadata and preserves extension parameters" {
  let original = sample_document()
  let original = {
    ..original,
    parameters: original.parameters.put_text("CUSTOM", "INFO", "retain"),
  }
  let selected = original.select_points([1]).select_analog([])
  let decoded = @lib.read(@lib.write(selected))
  assert_eq(decoded.layout.point_labels, ["R"])
  assert_eq(decoded.layout.analog_channels.length(), 0)
  assert_eq(decoded.frames[1].points[0].x, 7.0)
  assert_eq(decoded.parameters.require("CUSTOM", "INFO").text_values(), [
    "retain",
  ])
  expect_error(() => original.select_points([0, 0]))
  expect_error(() => original.select_analog([2]))
}

///|
test "storage conversion rejects overflow and preserves calibrated values" {
  let original = sample_document()
  let integer = original.convert_storage(0.01)
  let decoded = @lib.read(@lib.write(integer))
  assert_true((decoded.frames[2].points[0].x - 10.0).abs() < 0.01)
  assert_eq(decoded.frames[2].analog, [[5.0, 6.0]])
  expect_error(() => original.convert_storage(0.00000001))
}

///|
test "known force platform references prevent silent channel corruption" {
  let original = sample_document()
  let original = {
    ..original,
    parameters: original.parameters.put_int("FORCE_PLATFORM", "USED", 1),
  }
  expect_error(() => original.select_analog([]))
}
