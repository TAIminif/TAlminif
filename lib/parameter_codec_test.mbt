///|
test "independent parameter record golden bytes" {
  let prefix = @buffer.Buffer::Buffer()
  for _ in 0..<512 {
    prefix.write_byte(0)
  }
  prefix.write_bytes(
    b"\x00\x50\x01\x54\x05\xffPOINT\x03\x00\x00\x04\x01USED\x07\x00\x02\x00\x02\x00\x00\x00\x00"[:],
  )
  @lib.pad_to(prefix, 512)
  let result = @lib.read_parameters(prefix.to_bytes(), 2)
  assert_eq(result.groups[0].name, "POINT")
  assert_eq(result.values[0].name, "USED")
  assert_eq(@lib.i16(result.values[0].data, 0), 2)
}

///|
test "parameters preserve arbitrary payloads and locked state" {
  let parameters : @lib.Parameters = {
    groups: [{ id: 7, name: "CUSTOM", description: b"group", locked: true, }],
    values: [
      {
        processor: @lib.Intel,
        group_id: 7,
        name: "DATA",
        data_type: 1,
        dimensions: [2, 3],
        data: b"\x01\x02\x03\x04\x05\x06",
        description: @lib.utf8_bytes("扩展"),
        locked: true,
      },
    ],
  }
  let section = @lib.write_parameters(parameters)
  let full = Bytes::make(512, 0) + section
  assert_eq(@lib.read_parameters(full, 2), parameters)
  expect_error(() => @lib.read_parameters(full[0:700].to_owned(), 2))
}

///|
test "parameter structural validation rejects dangling duplicate and malformed values" {
  let group : @lib.Group = {
    id: 1,
    name: "POINT",
    description: b"",
    locked: false,
  }
  let value : @lib.Parameter = {
    processor: @lib.Intel,
    group_id: 1,
    name: "USED",
    data_type: 2,
    dimensions: [],
    data: b"\x02\x00",
    description: b"",
    locked: false,
  }
  expect_error(() => @lib.write_parameters({ groups: [], values: [value], }))
  expect_error(() => {
    @lib.write_parameters({ groups: [group], values: [value, value], })
  })
  expect_error(() => @lib.validate_parameter({ ..value, dimensions: [3], }))
  expect_error(() => @lib.element_count([255, 255, 255, 255]))
  expect_error(() => @lib.normalize_name("bad:name"))
}
