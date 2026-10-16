///|
fn frame_test_layout(float_storage : Bool) -> @lib.Layout {
  {
    processor: @lib.Intel,
    frame_count: 2,
    first_frame: 1,
    point_count: 1,
    point_rate: 100.0,
    point_scale: if float_storage {
      -0.5
    } else {
      0.5
    },
    point_labels: ["P1"],
    point_descriptions: [""],
    point_unit: "mm",
    analog_channels: [
      { label: "A1", description: "", unit: "V", scale: 0.25, offset: 10.0, },
    ],
    analog_subsamples: 2,
    analog_rate: 200.0,
    analog_global_scale: 2.0,
    analog_unsigned: false,
    float_storage,
    frame_bytes: if float_storage {
      24
    } else {
      12
    },
    data_offset: 1024,
  }
}

///|
test "integer point and analog bytes match independent golden layout" {
  let layout = frame_test_layout(false)
  let raw = b"\x04\x00\xfc\xff\x06\x00\x03\x05\x0c\x00\x0e\x00"
  let frame = @lib.decode_frame(raw, 0, layout, 0)
  assert_eq(frame.points[0], {
    x: 2.0,
    y: -2.0,
    z: 3.0,
    residual: 1.5,
    cameras: 5,
    valid: true,
  })
  assert_eq(frame.analog, [[1.0, 2.0]])
  assert_eq(frame.camera_count(0), 2)
  assert_eq(@lib.encode_frame(frame, layout), raw)
}

///|
test "float marker residual word is numeric not bit reinterpretation" {
  let layout = frame_test_layout(true)
  let out = @buffer.Buffer::Buffer()
  for value in [1.25, 2.5, 3.75, 1283.0, 12.0, 14.0] {
    @lib.put_f32(out, value)
  }
  let frame = @lib.decode_frame(out.to_bytes(), 0, layout, 0)
  assert_eq(frame.points[0].x, 1.25)
  assert_eq(frame.points[0].residual, 1.5)
  assert_eq(frame.points[0].cameras, 5)
  assert_eq(frame.analog, [[1.0, 2.0]])
  assert_eq(@lib.encode_frame(frame, layout), out.to_bytes())
}

///|
test "missing markers and narrowing errors" {
  let layout = frame_test_layout(false)
  let frame : @lib.Frame = {
    number: 1,
    points: [@lib.Marker::missing()],
    analog: [[0.0, 0.0]],
  }
  assert_false(
    @lib.decode_frame(@lib.encode_frame(frame, layout), 0, layout, 0).points[0].valid,
  )
  expect_error(() => {
    @lib.encode_frame(
      { ..frame, points: [@lib.Marker::new(1.0e10, 0.0, 0.0)], },
      layout,
    )
  })
  expect_error(() => @lib.encode_frame({ ..frame, analog: [[]], }, layout))
  expect_error(() => @lib.decode_frame(b"short", 0, layout, 0))
}

///|
test "time conversion includes analog subframe rate" {
  let layout = frame_test_layout(false)
  assert_eq(layout.time_at(1), 0.01)
  assert_eq(layout.time_at(1, subsample=1), 0.015)
  assert_eq(layout.index_at(0.015), 1)
  expect_error(() => layout.time_at(1, subsample=2))
}
