///|
fn time_test_document() -> @lib.Document raise @lib.C3dError {
  let frames : Array[@lib.Frame] = Array::makei(100, i => {
    number: i + 1,
    points: [@lib.Marker::new(i.to_double(), 0.0, 0.0)],
    analog: [[(i * 2).to_double(), (i * 2 + 1).to_double()]],
  })
  @lib.Document::new(
    ["P"],
    [{ label: "A", description: "", unit: "V", scale: 1.0, offset: 0.0, }],
    frames,
    point_rate=100.0,
    analog_subsamples=2,
  )
}

///|
fn time_selected_indices(document : @lib.Document) -> Array[Int32] {
  document.frames.map(frame => frame.points[0].x.to_int())
}

///|
fn previous_positive_time(value : Double) -> Double {
  (value.reinterpret_as_uint64() - 1UL).reinterpret_as_double()
}

///|
fn next_positive_time(value : Double) -> Double {
  (value.reinterpret_as_uint64() + 1UL).reinterpret_as_double()
}

///|
test "frame timestamps invert exactly across decimal rates and trial origins" {
  let base = frame_test_layout(false)
  for rate in [59.94, 100.0, 120.0, 1000.0] {
    for first in [1, 101, 2147483548] {
      let layout = {
        ..base,
        frame_count: 100,
        first_frame: first,
        point_rate: rate,
      }
      for index in 0..<100 {
        assert_eq(layout.index_at(layout.time_at(index)), index)
      }
    }
  }
}

///|
test "time lookup distinguishes adjacent representable times and rejects trial endpoints" {
  let layout = {
    ..frame_test_layout(false),
    frame_count: 100,
    first_frame: 101,
  }
  let boundary = layout.time_at(29)
  assert_eq(layout.index_at(previous_positive_time(boundary)), 28)
  assert_eq(layout.index_at(boundary), 29)
  assert_eq(layout.index_at(next_positive_time(boundary)), 29)
  let start = layout.time_at(0)
  expect_error(() => layout.index_at(previous_positive_time(start)))
  assert_eq(layout.index_at(start), 0)
  let end = 2.0
  assert_eq(layout.index_at(previous_positive_time(end)), 99)
  expect_error(() => layout.index_at(end))
  expect_error(() => layout.index_at(next_positive_time(end)))
  expect_error(() => {
    layout.index_at(0x7ff0000000000000UL.reinterpret_as_double())
  })
  expect_error(() => {
    layout.index_at(0x7ff8000000000000UL.reinterpret_as_double())
  })
}

///|
test "decimal time crop keeps both expected frame starts and analog subsamples" {
  let original = time_test_document()
  let cropped = original.crop_time(0.07, 0.09)
  assert_eq(time_selected_indices(cropped), [7, 8])
  assert_eq(cropped.frames[0].analog, [[14.0, 15.0]])
  assert_eq(cropped.frames[1].analog, [[16.0, 17.0]])
  assert_eq(cropped.layout.time_at(0, subsample=1), 0.005)
  let absolute = original.crop_time(0.07, 0.09, rebase=false)
  assert_eq(absolute.frames.map(frame => frame.number), [8, 9])
  assert_eq(absolute.layout.time_at(0), 0.07)
  assert_eq(absolute.layout.time_at(0, subsample=1), 0.07500000000000001)
}

///|
test "half-open crop honors adjacent representable endpoints without tolerance" {
  let document = time_test_document()
  let start = document.layout.time_at(7)
  let end = document.layout.time_at(9)
  assert_eq(
    time_selected_indices(
      document.crop_time(previous_positive_time(start), end),
    ),
    [7, 8],
  )
  assert_eq(
    time_selected_indices(document.crop_time(next_positive_time(start), end)),
    [8],
  )
  assert_eq(
    time_selected_indices(
      document.crop_time(start, previous_positive_time(end)),
    ),
    [7, 8],
  )
  assert_eq(
    time_selected_indices(document.crop_time(start, next_positive_time(end))),
    [7, 8, 9],
  )
  assert_eq(time_selected_indices(document.crop_time(0.065, 0.085)), [7, 8])
  expect_error(() => document.crop_time(-0.0000000001, 0.1))
  expect_error(() => document.crop_time(0.9, next_positive_time(1.0)))
  expect_error(() => document.crop_time(0.071, 0.079))
  assert_eq(time_selected_indices(document.crop_time(0.99, 1.0)), [99])
}

///|
test "time crop retains a non-one TRIAL origin and high endpoint without integer overflow" {
  let original = time_test_document()
  let shifted_frames = original.frames.map(frame => {
    ..frame,
    number: frame.number + 2147483547,
  })
  let shifted = @lib.rebuild(
    original,
    shifted_frames,
    original.layout.point_labels,
    original.layout.point_descriptions,
    original.layout.analog_channels,
    2147483548,
    [],
  )
  let start = shifted.layout.time_at(98)
  // The exclusive boundary has frame number Int32::max_value + 1; only its
  // timestamp is needed, so this must not wrap as an Int32 operation.
  let end = 2147483647.0 / shifted.layout.point_rate
  let cropped = shifted.crop_time(start, end, rebase=false)
  assert_eq(time_selected_indices(cropped), [98, 99])
  assert_eq(cropped.frames.map(frame => frame.number), [2147483646, 2147483647])
  expect_error(() => {
    shifted.crop_time(previous_positive_time(shifted.layout.time_at(0)), end)
  })
}
