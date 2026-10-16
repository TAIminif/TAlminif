///|
test "zero analog channels ignore stale optional analog metadata while preserving its raw parameters" {
  let original = @lib.read(@lib.write(sample_document().select_analog([])))
  let stale = {
    ..original,
    parameters: original.parameters
    .put_text("ANALOG", "RATE", "not numeric, unused")
    .put_text("ANALOG", "FORMAT", "unknown unused encoding")
    .put_real("ANALOG", "GEN_SCALE", 0.0)
    .put_text_series("ANALOG", "LABELS", Array::makei(511, i => "OLD\{i + 1}"))
    .put_text_series("ANALOG", "DESCRIPTIONS", Array::make(511, "old channel"))
    .put_text_series("ANALOG", "UNITS", Array::make(511, "unused"))
    .put_text("ANALOG", "SCALE", "unused calibration")
    .put_text("ANALOG", "SCALE2", "unused continuation")
    .put_text("ANALOG", "GAIN", "unused gain")
    .put_text("ANALOG", "RANGE", "unused range")
    .put_int_series("ANALOG", "OFFSET", Array::make(511, 10)),
  }
  let decoded = @lib.read(@lib.write(stale))
  assert_eq(decoded.frames, original.frames)
  assert_eq(decoded.layout.analog_channels, [])
  assert_eq(decoded.layout.analog_subsamples, 0)
  assert_eq(decoded.layout.analog_rate, 0.0)
  assert_eq(decoded.layout.analog_global_scale, 1.0)
  assert_false(decoded.layout.analog_unsigned)
  assert_eq(decoded.select_analog([]).frames, decoded.frames)
  for
    name in [
      "RATE", "FORMAT", "GEN_SCALE", "LABELS", "LABELS2", "LABELS3", "DESCRIPTIONS3",
      "UNITS3", "SCALE", "SCALE2", "OFFSET3",
    ] {
    assert_eq(
      decoded.parameters.require("ANALOG", name),
      stale.parameters.require("ANALOG", name),
    )
  }
  let conflicting = {
    ..stale,
    header: {
      ..stale.header,
      analog_values_per_frame: 2,
      analog_subsamples: 2,
    },
  }
  expect_error(() => @lib.validate_document(conflicting))
  let negative = {
    ..stale,
    header: { ..stale.header, analog_values_per_frame: -1, },
  }
  expect_error(() => @lib.validate_document(negative))
}

///|
test "analog only trials ignore unused point label series but still reject conflicting point counts" {
  let original = sample_document().select_points([])
  let stale = {
    ..original,
    parameters: original.parameters
    .put_text_series("POINT", "LABELS", Array::makei(511, i => "OLD\{i + 1}"))
    .put_text_series("POINT", "DESCRIPTIONS", Array::make(511, "unused point")),
  }
  let decoded = @lib.read(@lib.write(stale))
  assert_eq(decoded.layout.point_count, 0)
  assert_eq(decoded.layout.point_labels, [])
  assert_eq(decoded.layout.point_descriptions, [])
  assert_eq(decoded.frames, original.frames)
  assert_eq(decoded.layout.analog_channels, original.layout.analog_channels)
  for
    name in [
      "LABELS", "LABELS2", "LABELS3", "DESCRIPTIONS", "DESCRIPTIONS2", "DESCRIPTIONS3",
    ] {
    assert_eq(
      decoded.parameters.require("POINT", name),
      stale.parameters.require("POINT", name),
    )
  }
  let conflicting = { ..stale, header: { ..stale.header, point_count: 1, }, }
  expect_error(() => @lib.validate_document(conflicting))
  let negative = { ..stale, header: { ..stale.header, point_count: -1, }, }
  expect_error(() => @lib.validate_document(negative))
}
