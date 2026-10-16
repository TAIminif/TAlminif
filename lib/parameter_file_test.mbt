///|
fn parameter_file_fixture() -> @lib.Parameters raise @lib.C3dError {
  let parameters = @lib.Parameters::empty()
    .add_group(
      "CUSTOM",
      description="parameter-only configuration",
      locked=true,
    )
    .set("CUSTOM", @lib.Parameter::integers("SIGNED", [-32768, -1, 32767]))
    .set("CUSTOM", @lib.Parameter::unsigneds("UNSIGNED", [0, 32768, 65535]))
    .set("CUSTOM", @lib.Parameter::reals("FLOAT", [-0.25, 0.0, 1.5]))
    .set("CUSTOM", @lib.Parameter::texts("LABELS", ["配置", "R"]))
  let byte_parameter = {
    ..@lib.Parameter::integer("BYTE", 0),
    data_type: 1,
    dimensions: [3],
    data: b"\x00\x80\xff",
    description: b"raw byte values",
    locked: true,
  }
  parameters.set("CUSTOM", byte_parameter)
}

///|
test "standalone parameter files preserve all data types locks and descriptions in three encodings" {
  let original = parameter_file_fixture()
  for
    processor in [
      @lib.Processor::Intel,
      @lib.Processor::Dec,
      @lib.Processor::Mips,
    ] {
    let data = @lib.write_parameter_file(original, processor~)
    assert_eq(data.length() % 512, 0)
    assert_eq(@lib.u8(data, 0), 1)
    assert_eq(@lib.u8(data, 1), 80)
    assert_eq(@lib.u8(data, 3), processor.processor_id())
    let decoded = @lib.read_parameter_file(data)
    assert_eq(decoded.groups, original.groups)
    assert_eq(decoded.require("CUSTOM", "SIGNED").int_values(), [
      -32768, -1, 32767,
    ])
    assert_eq(decoded.require("CUSTOM", "UNSIGNED").int_values(unsigned=true), [
      0, 32768, 65535,
    ])
    assert_eq(decoded.require("CUSTOM", "FLOAT").real_values(), [
      -0.25, 0.0, 1.5,
    ])
    assert_eq(decoded.require("CUSTOM", "LABELS").text_values(), ["配置", "R"])
    let byte_parameter = decoded.require("CUSTOM", "BYTE")
    assert_eq(byte_parameter.data, b"\x00\x80\xff")
    assert_eq(byte_parameter.description, b"raw byte values")
    assert_true(byte_parameter.locked)
    for value in decoded.values {
      assert_eq(value.processor, processor)
    }
    let canonical = @lib.read_parameter_file(@lib.write_parameter_file(decoded))
    assert_eq(canonical, original)
    // Trial readers keep a distinct contract: metadata alone is not a trial.
    expect_error(() => @lib.Reader::new(data))
  }
}

///|
test "parameter files follow an arbitrary first parameter block and ignore its reserved first word" {
  let original = parameter_file_fixture()
  let section = @lib.write_parameters(original, processor=@lib.Processor::Mips)
  let data = b"\x03\x50" +
    Bytes::make(1022, 0) +
    b"\xaa\xbb" +
    section[2:].to_owned()
  let decoded = @lib.read_parameter_file(data)
  assert_eq(decoded.require("CUSTOM", "SIGNED").int_values(), [
    -32768, -1, 32767,
  ])
  assert_eq(decoded.require("CUSTOM", "FLOAT").real_values(), [-0.25, 0.0, 1.5])
  assert_eq(decoded.groups, original.groups)
}

///|
test "parameter file validation rejects invalid pointers signatures truncation and processor codes" {
  let data = @lib.write_parameter_file(parameter_file_fixture())
  expect_error(() => @lib.read_parameter_file(b""))
  expect_error(() => @lib.read_parameter_file(b"\x01"))
  expect_error(() => @lib.read_parameter_file(b"\x00" + data[1:].to_owned()))
  expect_error(() => @lib.read_parameter_file(b"\x01\x00" + data[2:].to_owned()))
  expect_error(() => @lib.read_parameter_file(data[0:511].to_owned()))
  expect_error(() => @lib.read_parameter_file(b"\x03" + data[1:].to_owned()))
  expect_error(() => {
    @lib.read_parameter_file(
      data[0:3].to_owned() + b"\x57" + data[4:].to_owned(),
    )
  })
  expect_error(() => {
    @lib.read_parameter_file(
      data[0:2].to_owned() + b"\x00" + data[3:].to_owned(),
    )
  })
  let large = parameter_file_fixture().set(
    "CUSTOM",
    @lib.Parameter::texts("LARGE", Array::make(255, "0123456789")),
  )
  let large_data = @lib.write_parameter_file(large)
  expect_error(() => {
    @lib.read_parameter_file(large_data, limits={
      ..@lib.Limits::default(),
      max_file_bytes: 512,
    })
  })
  expect_error(() => {
    @lib.write_parameter_file(large, limits={
      ..@lib.Limits::default(),
      max_file_bytes: 512,
    })
  })
}
