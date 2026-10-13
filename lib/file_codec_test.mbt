///|
fn sample_document(float_storage? : Bool = true) -> Document raise C3dError {
  let channel : Channel = {
    label: "force",
    description: "",
    unit: "N",
    scale: 0.5,
    offset: 10.0,
  }
  let frames : Array[Frame] = [
    {
      number: 1,
      points: [
        { ..Marker::new(1.0, 2.0, 3.0), residual: 0.02, cameras: 3 },
        Marker::missing(),
      ],
      analog: [[1.0, 2.0]],
    },
    {
      number: 2,
      points: [Marker::new(4.0, 5.0, 6.0), Marker::new(7.0, 8.0, 9.0)],
      analog: [[3.0, 4.0]],
    },
    {
      number: 3,
      points: [Marker::new(10.0, 11.0, 12.0), Marker::new(13.0, 14.0, 15.0)],
      analog: [[5.0, 6.0]],
    },
  ]
  Document::new(
    ["L", "R"],
    [channel],
    frames,
    scale=if float_storage { -0.01 } else { 0.01 },
    analog_subsamples=2,
  )
}

///|
test "complete C3D files support sequential random and batched reads" {
  let original = sample_document()
  let data = write(original)
  let reader = Reader::new(data)
  assert_eq(reader.remaining(), 3)
  assert_eq(reader.frame(1).points[0].x, 4.0)
  assert_eq(reader.read_batch(2).length(), 2)
  assert_eq(reader.position(), 2)
  assert_eq(reader.next().unwrap().number, 3)
  assert_true(reader.next() is None)
  reader.seek(0)
  assert_eq(reader.next().unwrap().analog, [[1.0, 2.0]])
  assert_eq(reader.to_document().layout.point_labels, ["L", "R"])
  expect_error(() => reader.seek(4))
}

///|
test "events and unknown parameters survive full file exchange" {
  let original = sample_document()
  let params = original.parameters.put_text(
    "CUSTOM", "NOTE", "保留原始信息",
  )
  let updated = {
    ..original,
    parameters: params,
    events: [Event::new(0.01, "contact")],
  }
  let decoded = read(write(updated))
  assert_eq(decoded.events[0].label, "contact")
  assert_eq(decoded.parameters.require("CUSTOM", "NOTE").text_values(), [
    "保留原始信息",
  ])
  assert_eq(decoded.frames.length(), 3)
}

///|
test "complete data section is required before decoding" {
  let data = write(sample_document())
  let reader = Reader::new(data)
  let end = reader.layout().data_offset + reader.layout().frame_bytes * 3
  expect_error(() => read(data[0:end - 1].to_owned()))
  expect_error(() => {
    Reader::new(data, limits={ ..Limits::default(), max_frames: 2 })
  })
}
