///|
fn legacy_event_header(
  processor : @lib.Processor,
  labels : Array[String],
  times : Array[Double],
  label_width : Int32,
) -> @lib.Header raise @lib.C3dError {
  let out = @buffer.Buffer::Buffer()
  for _ in 0..<274 {
    out.write_byte(0)
  }
  @lib.put_encoded_u16(out, if label_width == 4 { 12345 } else { 0 }, processor)
  @lib.put_encoded_u16(out, labels.length(), processor)
  @lib.put_encoded_u16(out, 0, processor)
  for i in 0..<18 {
    @lib.put_encoded_f32(
      out,
      if i < times.length() {
        times[i]
      } else {
        0.0
      },
      processor,
    )
  }
  for i in 0..<18 {
    out.write_byte((i % 2).to_byte())
  }
  @lib.put_encoded_u16(out, 0, processor)
  for i in 0..<18 {
    let raw = if i < labels.length() {
      @lib.ascii_bytes(labels[i])
    } else {
      b""
    }
    for j in 0..<label_width {
      out.write_byte(if j < raw.length() { raw[j] } else { 32 })
    }
  }
  while out.length() < 488 {
    out.write_byte(0)
  }
  { ..@lib.Header::new(0, 100.0, processor~), reserved: out.to_bytes(), }
}

///|
test "legacy two and four character event labels across all processors" {
  for
    processor in [
      @lib.Processor::Intel,
      @lib.Processor::Dec,
      @lib.Processor::Mips,
    ] {
    for width in [2, 4] {
      let labels = if width == 2 {
        ["R", "LO", "TO"]
      } else {
        ["RHS", "LHS", "STOP"]
      }
      let header = legacy_event_header(
        processor,
        labels,
        [0.0, 0.25, 0.5],
        width,
      )
      let events = @lib.read_header_events(header)
      assert_eq(events.map(event => event.label), labels)
      assert_eq(events.map(event => event.time), [0.0, 0.25, 0.5])
    }
  }
}

///|
test "header and EVENT stores merge while preserving richer modern metadata" {
  let header = legacy_event_header(Intel, ["RHS", "OLD"], [0.25, 0.5], 4)
  let richer = {
    ..@lib.Event::new(0.25, "RHS"),
    context: "Right",
    description: "modern context is retained",
    icon_id: -1,
  }
  let parameters = @lib.write_event_parameters(@lib.Parameters::empty(), [
    richer,
    @lib.Event::new(0.75, "NEW"),
  ])
  let events = @lib.read_events(header, parameters)
  assert_eq(events.map(event => event.label), ["RHS", "NEW", "OLD"])
  assert_eq(events[0], richer)
  let zero_used = @lib.write_event_parameters(@lib.Parameters::empty(), [])
  assert_eq(@lib.read_events(header, zero_used).map(event => event.label), [
    "RHS", "OLD",
  ])
}

///|
test "mixed event stores survive file normalization crop and JSON" {
  let base = sample_document()
  let modern = base.with_events([
    @lib.Event::new(0.0, "SAME"),
    @lib.Event::new(0.01, "NEW"),
  ])
  let stored = @lib.write(modern)
  let legacy = legacy_event_header(Intel, ["SAME", "OLD"], [0.0, 0.02], 4)
  let preserved = legacy.reserved.to_array()
  preserved[20] = 0x7a
  preserved[480] = 0xa5
  let header = {
    ..@lib.read_header(stored),
    reserved: Bytes::from_array(preserved),
  }
  let mixed = @lib.write_header(header) + stored[512:].to_owned()
  let document = @lib.read(mixed)
  assert_eq(document.events.map(event => event.label), ["SAME", "NEW", "OLD"])
  let rewritten = @lib.read(@lib.write(document))
  assert_eq(rewritten.events, document.events)
  assert_eq(rewritten.header.reserved[20], 0x7a)
  assert_eq(rewritten.header.reserved[480], 0xa5)
  let cropped = @lib.read(@lib.write(document.crop(0, 3)))
  assert_eq(cropped.events, document.events)
  let imported = @lib.import_json(@lib.document_json(document).stringify())
  assert_eq(imported.events, document.events)
}

///|
test "nonfirst trial header events normalize before deduplication and crop" {
  let base = sample_document()
  let first = 101
  let shifted = @lib.rebuild(
    base,
    base.frames.map(frame => { ..frame, number: frame.number + 100, }),
    base.layout.point_labels,
    base.layout.point_descriptions,
    base.layout.analog_channels,
    first,
    [@lib.Event::new(1.0, "SAME"), @lib.Event::new(1.025, "NEW")],
  )
  let stored = @lib.write(shifted)
  let legacy = legacy_event_header(Intel, ["SAME", "OLD"], [0.0, 0.015], 4)
  let header = { ..@lib.read_header(stored), reserved: legacy.reserved, }
  let document = @lib.read(@lib.write_header(header) + stored[512:].to_owned())
  assert_eq(document.events.map(event => event.label), ["SAME", "NEW", "OLD"])
  assert_true((document.events[2].time - 1.015).abs() < 1.0e-7)
  let cropped = document.crop(1, 3)
  assert_eq(cropped.events.map(event => event.label), ["NEW", "OLD"])
  assert_true((cropped.events[1].time - 0.005).abs() < 1.0e-7)
  let decoded = @lib.read(@lib.write(cropped))
  assert_eq(decoded.events.map(event => event.label), ["NEW", "OLD"])
}

///|
test "event REAL4 rounding carries seconds into the next minute" {
  for
    processor in [
      @lib.Processor::Intel,
      @lib.Processor::Dec,
      @lib.Processor::Mips,
    ] {
    let header = @lib.Header::new(0, 100.0, processor~)
    let parameters = @lib.write_event_parameters(
      @lib.Parameters::empty(),
      [@lib.Event::new(59.9999999, "boundary")],
      processor~,
    )
    let decoded = @lib.read_events(header, parameters)
    assert_eq(decoded[0].time, 60.0)
  }
  let tiny = @lib.encoded_f32(b"\x80\x00\x01\x00", 0, Dec)
  let parameters = @lib.write_event_parameters(
    @lib.Parameters::empty(),
    [@lib.Event::new(tiny, "tiny")],
    processor=Dec,
  )
  assert_eq(
    @lib.read_events(@lib.Header::new(0, 100.0, processor=Dec), parameters)[0].time,
    tiny,
  )
}
