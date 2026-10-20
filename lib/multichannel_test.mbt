///|
fn multichannel_document(
  float_storage : Bool,
  unsigned : Bool,
) -> @lib.Document raise @lib.C3dError {
  let labels = Array::makei(511, index => "P\{index + 1}")
  let descriptions = Array::makei(511, index => "point description \{index + 1}")
  let channels : Array[@lib.Channel] = Array::makei(511, index => {
    label: "A\{index + 1}",
    description: "analog description \{index + 1}",
    unit: if index % 2 == 0 {
      "N"
    } else {
      "mV"
    },
    scale: (index % 3 + 1).to_double() * 0.25,
    offset: if unsigned {
      (33000 + index % 11).to_double()
    } else {
      (index % 31 - 15).to_double()
    },
  })
  let frames : Array[@lib.Frame] = Array::makei(4, frame => {
    number: frame + 1,
    points: Array::makei(511, index => {
      if index == 255 && frame == 1 {
        @lib.Marker::missing()
      } else {
        let x = index.to_double() * 0.25 + frame.to_double()
        {
          ..@lib.Marker::new(x, -x, index.to_double() * 0.5),
          residual: 0.5,
          cameras: index % 128,
        }
      }
    }),
    analog: Array::makei(511, index => {
      Array::makei(2, subsample => {
        let channel = channels[index]
        let raw = if unsigned {
          33000 + index % 11 + 30 + frame * 3 + subsample
        } else {
          (index - 255) * 2 + frame * 3 + subsample
        }
        (raw.to_double() - channel.offset) * channel.scale * 0.5
      })
    }),
  })
  let document = @lib.Document::new(
    labels,
    channels,
    frames,
    point_rate=128.0,
    scale=if float_storage { -0.25 } else { 0.25 },
    analog_subsamples=2,
    analog_global_scale=0.5,
    analog_unsigned=unsigned,
  )
  let document = @lib.rebuild(
    document,
    frames,
    labels,
    descriptions,
    channels,
    1,
    [
      @lib.Event::new(0.0, "before"),
      @lib.Event::new(0.0078125, "inside"),
      @lib.Event::new(0.0234375, "end"),
    ],
  )
  {
    ..document,
    parameters: document.parameters
    .put_int_series("ANALOG", "GAIN", Array::makei(511, index => index % 8 + 1))
    .put_real_series(
      "ANALOG",
      "RANGE",
      Array::makei(511, index => (index + 1).to_double() * 0.25),
    )
    .put_text("ANALOG", "RANGE_VENDOR", "retain vendor metadata"),
  }
}

///|
test "511 point and analog channels retain calibrated data across all encodings and storage modes" {
  for unsigned in [false, true] {
    for float_storage in [false, true] {
      let original = multichannel_document(float_storage, unsigned)
      for
        processor in [
          @lib.Processor::Intel,
          @lib.Processor::Dec,
          @lib.Processor::Mips,
        ] {
        let decoded = @lib.read(@lib.write(original, processor~))
        assert_eq(decoded.header.processor, processor)
        assert_eq(decoded.layout.point_labels, original.layout.point_labels)
        assert_eq(
          decoded.layout.point_descriptions,
          original.layout.point_descriptions,
        )
        assert_eq(
          decoded.layout.analog_channels,
          original.layout.analog_channels,
        )
        assert_eq(decoded.layout.analog_subsamples, 2)
        assert_eq(decoded.frames, original.frames)
        assert_eq(
          decoded.parameters.require("POINT", "LABELS3").dimensions[1],
          1,
        )
        assert_eq(decoded.parameters.require("ANALOG", "SCALE3").dimensions, [1])
        assert_eq(
          decoded.parameters.require("ANALOG", "OFFSET3").int_values(unsigned~)[0],
          original.layout.analog_channels[510].offset.to_int(),
        )
        assert_eq(
          decoded.parameters.read_int_series("ANALOG", "GAIN", 511)[510],
          7,
        )
        assert_eq(
          decoded.parameters.read_real_series("ANALOG", "RANGE", 511)[510],
          127.75,
        )

        let selected_indices = [510, 255, 254, 0]
        let selected = decoded
          .select_points(selected_indices)
          .select_analog(selected_indices)
          .crop(1, 3)
        let result = @lib.read(@lib.write(selected))
        assert_eq(result.layout.point_labels, ["P511", "P256", "P255", "P1"])
        assert_eq(
          result.layout.point_descriptions,
          selected_indices.map(index => {
            original.layout.point_descriptions[index]
          }),
        )
        assert_eq(
          result.layout.analog_channels,
          selected_indices.map(index => original.layout.analog_channels[index]),
        )
        assert_eq(result.frames.length(), 2)
        assert_eq(result.frames[0].number, 1)
        assert_eq(
          result.frames[0].points,
          selected_indices.map(index => original.frames[1].points[index]),
        )
        assert_eq(
          result.frames[1].analog,
          selected_indices.map(index => original.frames[2].analog[index]),
        )
        assert_eq(result.events.map(event => event.label), ["inside"])
        assert_eq(result.events[0].time, 0.0)
        assert_eq(result.parameters.read_int_series("ANALOG", "GAIN", 4), [
          7, 8, 7, 1,
        ])
        assert_eq(result.parameters.read_real_series("ANALOG", "RANGE", 4), [
          127.75, 64.0, 63.75, 0.25,
        ])
        assert_eq(
          result.parameters.require("ANALOG", "RANGE_VENDOR").text_values(),
          ["retain vendor metadata"],
        )
        for group in ["POINT", "ANALOG"] {
          for name in ["LABELS2", "LABELS3", "DESCRIPTIONS2", "DESCRIPTIONS3"] {
            assert_true(result.parameters.get(group, name) is None)
          }
        }
        for
          name in [
            "UNITS2", "UNITS3", "SCALE2", "SCALE3", "OFFSET2", "OFFSET3", "GAIN2",
            "GAIN3", "RANGE2", "RANGE3",
          ] {
          assert_true(result.parameters.get("ANALOG", name) is None)
        }
      }
    }
  }
}

///|
test "reordering 256 channels repartitions every auxiliary vector at the boundary" {
  let original = multichannel_document(true, false)
  let input = @lib.read(@lib.write(original, processor=@lib.Processor::Mips))
  let indices = Array::makei(256, index => 510 - index)
  let selected = @lib.read(
    @lib.write(input.select_analog(indices), processor=@lib.Processor::Dec),
  )
  assert_eq(selected.parameters.require("ANALOG", "LABELS").dimensions[1], 255)
  assert_eq(selected.parameters.require("ANALOG", "LABELS2").dimensions[1], 1)
  assert_eq(selected.parameters.require("ANALOG", "GAIN").dimensions, [255])
  assert_eq(selected.parameters.require("ANALOG", "GAIN2").dimensions, [1])
  assert_true(selected.parameters.get("ANALOG", "GAIN3") is None)
  assert_true(selected.parameters.get("ANALOG", "RANGE3") is None)
  assert_eq(
    selected.layout.analog_channels,
    indices.map(index => original.layout.analog_channels[index]),
  )
  assert_eq(
    selected.frames[0].analog,
    indices.map(index => original.frames[0].analog[index]),
  )
  assert_eq(
    selected.parameters.read_int_series("ANALOG", "GAIN", 256),
    indices.map(index => index % 8 + 1),
  )
  assert_eq(
    selected.parameters.read_real_series("ANALOG", "RANGE", 256),
    indices.map(index => (index + 1).to_double() * 0.25),
  )
}

///|
test "analog auxiliary segment annotations survive selection and reordering" {
  let original = multichannel_document(true, false)
  let mut parameters = original.parameters
  for
    (name, description, locked) in [
      ("GAIN", "gain first", false),
      ("GAIN2", "gain second", true),
      ("GAIN3", "gain third", true),
      ("RANGE", "range first", true),
      ("RANGE2", "range second", false),
      ("RANGE3", "range third", false),
    ] {
    parameters = parameters.set("ANALOG", {
      ..parameters.require("ANALOG", name),
      description: @lib.utf8_bytes(description),
      locked,
    })
  }
  let original = { ..original, parameters, }
  for
    indices in [
      Array::makei(511, index => index),
      Array::makei(256, index => 510 - index),
    ] {
    let selected = original.select_analog(indices)
    for processor in [@lib.Intel, @lib.Dec, @lib.Mips] {
      let decoded = @lib.read(@lib.write(selected, processor~))
      for result in [selected, decoded] {
        for name in ["GAIN", "GAIN2", "GAIN3", "RANGE", "RANGE2", "RANGE3"] {
          let expected = original.parameters.require("ANALOG", name)
          match result.parameters.get("ANALOG", name) {
            Some(value) => {
              assert_eq(value.description, expected.description)
              assert_eq(value.locked, expected.locked)
            }
            None => assert_eq(indices.length(), 256)
          }
        }
        assert_eq(
          result.parameters.read_int_series("ANALOG", "GAIN", indices.length()),
          indices.map(index => index % 8 + 1),
        )
        assert_eq(
          result.parameters.read_real_series(
            "ANALOG",
            "RANGE",
            indices.length(),
          ),
          indices.map(index => (index + 1).to_double() * 0.25),
        )
        assert_eq(
          result.frames[0].analog,
          indices.map(index => original.frames[0].analog[index]),
        )
      }
      assert_eq(
        decoded.parameters.require("ANALOG", "RANGE2").processor,
        processor,
      )
    }
  }
}

///|
test "channel times subsamples must remain within the uint16 header field" {
  let original = multichannel_document(true, false)
  expect_error(() => {
    @lib.Document::new(
      [],
      original.layout.analog_channels,
      [],
      analog_subsamples=129,
    )
  })
}

///|
test "VAX low exponent auxiliary values survive channel selection without IEEE narrowing" {
  let precise = @lib.encoded_f32(b"\x80\x00\x01\x00", 0, @lib.Processor::Dec)
  assert_true(precise != Float::from_double(precise).to_double())
  let original = multichannel_document(true, false)
  let original = {
    ..original,
    parameters: original.parameters.put_real_series(
      "ANALOG",
      "RANGE",
      Array::make(511, precise),
      processor=@lib.Processor::Dec,
    ),
  }
  let decoded = @lib.read(@lib.write(original, processor=@lib.Processor::Dec))
  let selected = decoded.select_analog([510, 255, 0])
  assert_eq(
    selected.parameters.require("ANALOG", "RANGE").processor,
    @lib.Processor::Dec,
  )
  assert_eq(selected.parameters.read_real_series("ANALOG", "RANGE", 3), [
    precise, precise, precise,
  ])
  assert_eq(
    @lib.read(@lib.write(selected)).parameters.read_real_series(
      "ANALOG", "RANGE", 3,
    ),
    [precise, precise, precise],
  )
}
