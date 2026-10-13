///|
test "independent parameter record golden bytes" {
  let prefix = @buffer.Buffer::Buffer()
  for _ in 0..<512 {
    prefix.write_byte(0)
  }
  prefix.write_bytes(
    b"\x00\x50\x01\x54\x05\xffPOINT\x03\x00\x00\x04\x01USED\x07\x00\x02\x00\x02\x00\x00\x00\x00"[:],
  )
  pad_to(prefix, 512)
  let result = read_parameters(prefix.to_bytes(), 2)
  assert_eq(result.groups[0].name, "POINT")
  assert_eq(result.values[0].name, "USED")
  assert_eq(i16(result.values[0].data, 0), 2)
}

///|
test "parameters preserve arbitrary payloads and locked state" {
  let parameters : Parameters = {
    groups: [{ id: 7, name: "CUSTOM", description: b"group", locked: true }],
    values: [
      {
        group_id: 7,
        name: "DATA",
        data_type: 1,
        dimensions: [2, 3],
        data: b"\x01\x02\x03\x04\x05\x06",
        description: utf8_bytes("扩展"),
        locked: true,
      },
    ],
  }
  let section = write_parameters(parameters)
  let full = Bytes::make(512, 0) + section
  assert_eq(read_parameters(full, 2), parameters)
  expect_error(() => read_parameters(full[0:700].to_owned(), 2))
}

///|
test "parameter structural validation rejects dangling duplicate and malformed values" {
  let group : Group = { id: 1, name: "POINT", description: b"", locked: false }
  let value : Parameter = {
    group_id: 1,
    name: "USED",
    data_type: 2,
    dimensions: [],
    data: b"\x02\x00",
    description: b"",
    locked: false,
  }
  expect_error(() => write_parameters({ groups: [], values: [value] }))
  expect_error(() => {
    write_parameters({ groups: [group], values: [value, value] })
  })
  expect_error(() => validate_parameter({ ..value, dimensions: [3] }))
  expect_error(() => element_count([255, 255, 255, 255]))
  expect_error(() => normalize_name("bad:name"))
}
