///|
fn dec_raw_parameter(base : @lib.Parameter, raw : Bytes) -> @lib.Parameter {
  { ..base, processor: @lib.Processor::Dec, data: raw, }
}

///|
fn dec_low_point_document() -> @lib.Document raise @lib.C3dError {
  let raw = b"\x80\x00\x01\x00"
  let scale = @lib.encoded_f32(raw, 0, Dec)
  let base = @lib.Document::new(
    ["P"],
    [],
    [
      {
        number: 1,
        points: [@lib.Marker::new(10.0 * scale, 0.0, 0.0)],
        analog: [],
      },
    ],
    scale=1.0,
  )
  let parameters = base.parameters.set(
    "POINT",
    dec_raw_parameter(base.parameters.require("POINT", "SCALE"), raw),
    override_locked=true,
  )
  let header = { ..base.header, processor: @lib.Processor::Dec, scale, }
  let layout = @lib.resolve_layout(header, parameters)
  { ..base, header, parameters, layout, }
}

///|
test "VAX low exponent POINT scale survives default writes crop and JSON" {
  let document = dec_low_point_document()
  let scale = document.layout.point_scale
  let decoded = @lib.read(@lib.write(document))
  assert_eq(decoded.header.processor, Dec)
  assert_eq(decoded.layout.point_scale, scale)
  assert_eq(
    decoded.parameters.require("POINT", "SCALE").data,
    b"\x80\x00\x01\x00",
  )
  assert_eq(decoded.frames[0].points[0].x, document.frames[0].points[0].x)
  let cropped = document.crop(0, 1)
  assert_eq(cropped.layout.point_scale, scale)
  assert_eq(@lib.read(@lib.write(cropped)).layout.point_scale, scale)
  let imported = @lib.import_json(@lib.document_json(document).stringify())
  assert_eq(imported.layout.point_scale, scale)
  assert_eq(@lib.read(@lib.write(imported)).frames[0].points[0].x, 10.0 * scale)
}

///|
test "integer XYZ conversion uses the target quantized scale" {
  let document = dec_low_point_document()
  for processor in [@lib.Processor::Intel, @lib.Processor::Mips] {
    let decoded = @lib.read(@lib.write(document, processor~))
    let target_scale = @lib.quantize_f32(document.layout.point_scale, processor)
    assert_eq(decoded.layout.point_scale, target_scale)
    assert_eq(decoded.frames[0].points[0].x, 10.0 * target_scale)
    assert_eq(decoded.header.processor, processor)
  }
}

///|
test "floating analog conversion uses the serialized target calibration" {
  let raw = b"\x80\x00\x01\x00"
  let scale = @lib.encoded_f32(raw, 0, Dec)
  let physical = 100.0 * scale
  let channel : @lib.Channel = {
    label: "A",
    description: "low exponent calibration",
    unit: "V",
    scale: 1.0,
    offset: 0.0,
  }
  let base = @lib.Document::new(
    ["P"],
    [channel],
    [
      {
        number: 1,
        points: [@lib.Marker::new(1.0, 2.0, 3.0)],
        analog: [[physical]],
      },
    ],
    scale=-1.0,
    analog_subsamples=1,
  )
  let parameters = base.parameters.set(
    "ANALOG",
    dec_raw_parameter(base.parameters.require("ANALOG", "SCALE"), raw),
    override_locked=true,
  )
  let header = { ..base.header, processor: @lib.Processor::Dec, }
  let layout = @lib.resolve_layout(header, parameters)
  let document = { ..base, header, parameters, layout, }
  let preserved = @lib.read(@lib.write(document))
  assert_eq(preserved.layout.analog_channels[0].scale, scale)
  assert_eq(preserved.frames[0].analog[0][0], physical)
  let cropped = document.crop(0, 1)
  assert_eq(cropped.layout.analog_channels[0].scale, scale)
  let imported = @lib.import_json(@lib.document_json(document).stringify())
  assert_eq(imported.layout.analog_channels[0].scale, scale)
  for processor in [@lib.Processor::Intel, @lib.Processor::Mips] {
    let target_scale = @lib.quantize_f32(scale, processor)
    let expected_raw = @lib.quantize_f32(physical / target_scale, processor)
    let decoded = @lib.read(@lib.write(document, processor~))
    assert_eq(decoded.layout.analog_channels[0].scale, target_scale)
    assert_eq(decoded.frames[0].analog[0][0], expected_raw * target_scale)
  }
}

///|
test "target rounding that breaks the analog rate ratio is rejected at write" {
  let channel : @lib.Channel = {
    label: "A",
    description: "",
    unit: "V",
    scale: 1.0,
    offset: 0.0,
  }
  let base = @lib.Document::new(
    ["P"],
    [channel],
    [
      {
        number: 1,
        points: [@lib.Marker::new(1.0, 2.0, 3.0)],
        analog: [[1.0, 2.0]],
      },
    ],
    point_rate=1.0,
    scale=1.0,
    analog_subsamples=2,
  )
  let point_raw = b"\x80\x00\x02\x00"
  let parameters = base.parameters.set(
    "POINT",
    dec_raw_parameter(base.parameters.require("POINT", "RATE"), point_raw),
    override_locked=true,
  )
  let parameters = parameters.set(
    "ANALOG",
    dec_raw_parameter(
      base.parameters.require("ANALOG", "RATE"),
      b"\x00\x01\x02\x00",
    ),
    override_locked=true,
  )
  let header = {
    ..base.header,
    processor: @lib.Processor::Dec,
    point_rate: @lib.encoded_f32(point_raw, 0, Dec),
  }
  let layout = @lib.resolve_layout(header, parameters)
  let document = { ..base, header, parameters, layout, }
  assert_eq(@lib.read(@lib.write(document)).layout.analog_subsamples, 2)
  expect_error(() => @lib.write(document, processor=Intel))
  expect_error(() => @lib.write(document, processor=Mips))
}
