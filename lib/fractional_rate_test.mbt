///|
fn fractional_rate_document(
  rate : Double,
  subsamples : Int32,
  processor : @lib.Processor,
) -> @lib.Document raise @lib.C3dError {
  let channel : @lib.Channel = {
    label: "A",
    description: "fractional frame-rate analog channel",
    unit: "V",
    scale: 1.0,
    offset: 0.0,
  }
  @lib.Document::new(
    ["P"],
    [channel],
    [
      {
        number: 1,
        points: [@lib.Marker::new(1.0, 2.0, 3.0)],
        analog: [Array::make(subsamples, 2.0)],
      },
    ],
    point_rate=rate,
    scale=-1.0,
    analog_subsamples=subsamples,
    processor~,
  )
}

///|
test "fractional point rates retain header subsamples in every processor" {
  for rate in [59.94, 29.97, 23.976] {
    for subsamples in [3, 10] {
      for processor in [@lib.Processor::Intel, Dec, Mips] {
        let document = fractional_rate_document(rate, subsamples, processor)
        assert_eq(document.layout.analog_subsamples, subsamples)
        for target in [@lib.Processor::Intel, Dec, Mips] {
          let decoded = @lib.read(@lib.write(document, processor=target))
          assert_eq(decoded.layout.analog_subsamples, subsamples)
          assert_eq(decoded.frames[0].analog[0].length(), subsamples)
          assert_eq(decoded.frames[0].analog[0][subsamples - 1], 2.0)
          assert_eq(decoded.header.processor, target)
        }
      }
    }
  }
}

///|
test "independently rounded decimal point and analog rates are compatible" {
  for rate in [59.94, 29.97, 23.976] {
    for subsamples in [3, 10] {
      for processor in [@lib.Processor::Intel, Dec, Mips] {
        let document = fractional_rate_document(rate, subsamples, processor)
        let parameters = document.parameters.put_real(
          "ANALOG",
          "RATE",
          rate * subsamples.to_double(),
          override_locked=true,
          processor~,
        )
        let layout = @lib.resolve_layout(document.header, parameters)
        assert_eq(layout.analog_subsamples, subsamples)
        let document = { ..document, parameters, layout, }
        for target in [@lib.Processor::Intel, Dec, Mips] {
          let decoded = @lib.read(@lib.write(document, processor=target))
          assert_eq(decoded.layout.analog_subsamples, subsamples)
        }
      }
    }
  }
}

///|
test "analog rate discrepancies outside the REAL4 rounding cells fail" {
  for processor in [@lib.Processor::Intel, Dec, Mips] {
    let document = fractional_rate_document(59.94, 3, processor)
    // This is far below a broad 1e-5 relative tolerance, but many REAL*4 ULPs.
    for bad_rate in [179.8201, 179.8199, 119.88] {
      let parameters = document.parameters.put_real(
        "ANALOG",
        "RATE",
        bad_rate,
        override_locked=true,
        processor~,
      )
      expect_error(() => @lib.resolve_layout(document.header, parameters))
    }
    let document = fractional_rate_document(1.0, 2, processor)
    // The cells touch only at a tie which rounds away from the odd analog
    // significand. Treating both endpoints as closed would admit this error.
    let parameters = document.parameters.put_real(
      "ANALOG",
      "RATE",
      2.0000002384185791015625,
      override_locked=true,
      processor~,
    )
    expect_error(() => @lib.resolve_layout(document.header, parameters))
  }
}

///|
test "missing analog rate uses header subsamples without division" {
  let document = fractional_rate_document(59.94, 3, Intel)
  let parameters = document.parameters.remove(
    "ANALOG",
    "RATE",
    override_locked=true,
  )
  let layout = @lib.resolve_layout(document.header, parameters)
  assert_eq(layout.analog_subsamples, 3)
  assert_eq(layout.analog_rate, layout.point_rate * 3.0)
}

///|
test "IEEE subnormal rate cells retain constant spacing at powers of two" {
  let rate = @lib.encoded_f32(b"\x02\x00\x00\x00", 0, Intel)
  let analog_rate = @lib.encoded_f32(b"\x0f\x00\x00\x00", 0, Intel)
  for processor in [@lib.Processor::Intel, Mips] {
    let document = fractional_rate_document(rate, 10, processor)
    let parameters = document.parameters.put_real(
      "ANALOG",
      "RATE",
      analog_rate,
      override_locked=true,
      processor~,
    )
    let layout = @lib.resolve_layout(document.header, parameters)
    let document = { ..document, parameters, layout, }
    let decoded = @lib.read(@lib.write(document))
    assert_eq(decoded.layout.point_rate, rate)
    assert_eq(decoded.layout.analog_rate, analog_rate)
    assert_eq(decoded.layout.analog_subsamples, 10)
  }
}
