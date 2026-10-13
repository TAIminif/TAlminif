///|
pub fn normalize_name(name : String) -> String raise C3dError {
  if name.length() < 1 || name.length() > 127 {
    raise C3dError::Invalid("parameter name length must be 1..127")
  }
  let result = StringBuilder()
  for char in name.iter() {
    let code = char.to_int()
    let upper = if code >= 97 && code <= 122 { code - 32 } else { code }
    if !((upper >= 65 && upper <= 90) ||
      (upper >= 48 && upper <= 57) ||
      upper == 95) {
      raise C3dError::Invalid(
        "parameter identifiers require ASCII letters, digits or underscore",
      )
    }
    result.write_char(upper.unsafe_to_char())
  }
  result.to_string()
}

///|
pub fn element_size(data_type : Int32) -> Int32 raise C3dError {
  match data_type {
    -1 | 1 => 1
    2 => 2
    4 => 4
    _ => raise C3dError::Unsupported("unsupported parameter element type")
  }
}

///|
pub fn element_count(dimensions : Array[Int32]) -> Int32 raise C3dError {
  if dimensions.length() > 7 {
    raise C3dError::Invalid("parameter has more than seven dimensions")
  }
  let mut count = 1
  for dimension in dimensions {
    if dimension < 0 || dimension > 255 {
      raise C3dError::Invalid("parameter dimension outside uint8 range")
    }
    count = checked_mul(count, dimension, "parameter dimension product")
  }
  count
}

///|
pub fn validate_parameter(
  value : Parameter,
  limits~ : Limits = Limits::default(),
) -> Unit raise C3dError {
  let _ = normalize_name(value.name)
  if value.group_id < 1 || value.group_id > 127 {
    raise C3dError::Invalid("parameter group ID outside range")
  }
  if value.description.length() > 255 {
    raise C3dError::Invalid("parameter description exceeds 255 bytes")
  }
  let expected = checked_mul(
    element_count(value.dimensions),
    element_size(value.data_type),
    "parameter size",
  )
  if expected > limits.max_parameter_bytes {
    raise C3dError::ResourceLimit("parameter data size")
  }
  if value.data.length() != expected {
    raise C3dError::Invalid("parameter data size differs from dimensions")
  }
}

///|
pub fn validate_parameters(
  parameters : Parameters,
  limits~ : Limits = Limits::default(),
) -> Unit raise C3dError {
  validate_limits(limits)
  if parameters.groups.length() > 127 ||
    parameters.values.length() > limits.max_parameters {
    raise C3dError::ResourceLimit("too many groups or parameters")
  }
  let ids : Map[Int32, Bool] = Map([])
  let names : Map[String, Bool] = Map([])
  let keys : Map[String, Bool] = Map([])
  let mut bytes = 0
  for group in parameters.groups {
    if group.id < 1 || group.id > 127 {
      raise C3dError::Invalid("group ID outside range")
    }
    let name = normalize_name(group.name)
    if ids.contains(group.id) || names.contains(name) {
      raise C3dError::Invalid("duplicate group ID or name")
    }
    if group.description.length() > 255 {
      raise C3dError::Invalid("group description exceeds 255 bytes")
    }
    ids[group.id] = true
    names[name] = true
    bytes = checked_add(bytes, group.description.length(), "parameter metadata")
  }
  for value in parameters.values {
    validate_parameter(value, limits~)
    if !ids.contains(value.group_id) {
      raise C3dError::Invalid("parameter refers to undefined group")
    }
    let key = "\{value.group_id}:" + normalize_name(value.name)
    if keys.contains(key) {
      raise C3dError::Invalid("duplicate parameter in group")
    }
    keys[key] = true
    bytes = checked_add(
      bytes,
      value.data.length() + value.description.length(),
      "parameter metadata",
    )
    if bytes > limits.max_parameter_bytes {
      raise C3dError::ResourceLimit("aggregate parameter data")
    }
  }
}

///|
pub fn read_parameters(
  data : Bytes,
  parameter_block : Int32,
  limits~ : Limits = Limits::default(),
) -> Parameters raise C3dError {
  validate_limits(limits)
  if parameter_block < 2 || parameter_block > 255 {
    raise C3dError::Unsupported("parameter-only or invalid block layout")
  }
  let start = checked_mul(parameter_block - 1, 512, "parameter offset")
  check_range(data, start, 4)
  let blocks = u8(data, start + 2)
  if blocks < 1 {
    raise C3dError::Invalid("empty parameter section")
  }
  if u8(data, start + 3) != 84 {
    raise C3dError::Unsupported("only Intel IEEE processor format is supported")
  }
  let size = checked_mul(blocks, 512, "parameter section size")
  if size > limits.max_parameter_bytes {
    raise C3dError::ResourceLimit("parameter section")
  }
  check_range(data, start, size)
  let end = start + size
  let groups : Array[Group] = []
  let values : Array[Parameter] = []
  let mut cursor = start + 4
  let mut records = 0
  while cursor < end {
    if cursor + 2 > end {
      raise C3dError::Truncated("parameter record prefix")
    }
    let signed_length = i8(data, cursor)
    if signed_length == 0 {
      break
    }
    if signed_length == -128 {
      raise C3dError::Invalid("invalid parameter name length")
    }
    let length = signed_length.abs()
    let group_id = i8(data, cursor + 1)
    if group_id == 0 || group_id == -128 {
      raise C3dError::Invalid("invalid group ID")
    }
    let pointer = checked_add(cursor, 2 + length, "record pointer")
    if pointer + 2 > end {
      raise C3dError::Truncated("parameter record name")
    }
    let name = normalize_name(ascii(data[cursor + 2:pointer].to_owned()))
    let jump = u16(data, pointer)
    let record_end = if jump == 0 {
      end
    } else {
      checked_add(pointer, jump, "record jump")
    }
    if record_end > end || record_end < pointer + 3 {
      raise C3dError::Invalid("invalid next-record offset")
    }
    let mut payload = pointer + 2
    if group_id < 0 {
      let description_length = u8(data, payload)
      payload = payload + 1
      if description_length > record_end - payload {
        raise C3dError::Truncated("group description")
      }
      groups.push({
        id: -group_id,
        name,
        locked: signed_length < 0,
        description: data[payload:payload + description_length].to_owned(),
      })
    } else {
      if payload + 2 > record_end {
        raise C3dError::Truncated("parameter type and rank")
      }
      let data_type = i8(data, payload)
      let rank = u8(data, payload + 1)
      if rank > 7 || rank > record_end - payload - 2 {
        raise C3dError::Invalid("invalid parameter rank")
      }
      payload = payload + 2
      let dimensions : Array[Int32] = []
      for _ in 0..<rank {
        dimensions.push(u8(data, payload))
        payload = payload + 1
      }
      let bytes = checked_mul(
        element_count(dimensions),
        element_size(data_type),
        "parameter payload size",
      )
      if bytes > record_end - payload - 1 {
        raise C3dError::Truncated("parameter payload")
      }
      let raw = data[payload:payload + bytes].to_owned()
      payload = payload + bytes
      let description_length = u8(data, payload)
      payload = payload + 1
      if description_length > record_end - payload {
        raise C3dError::Truncated("parameter description")
      }
      values.push({
        group_id,
        name,
        data_type,
        dimensions,
        data: raw,
        description: data[payload:payload + description_length].to_owned(),
        locked: signed_length < 0,
      })
    }
    records = records + 1
    if records > limits.max_parameters + 127 {
      raise C3dError::ResourceLimit("parameter record count")
    }
    if jump == 0 {
      break
    }
    cursor = record_end
  }
  let result = { groups, values, }
  validate_parameters(result, limits~)
  result
}

///|
fn encode_record(
  name : String,
  group_id : Int32,
  locked : Bool,
  payload : Bytes,
) -> Bytes raise C3dError {
  let name_bytes = ascii_bytes(normalize_name(name))
  let out = @buffer.Buffer::Buffer()
  let length = name_bytes.length()
  out.write_byte((if locked { 256 - length } else { length }).to_byte())
  out.write_byte(
    (if group_id < 0 { 256 + group_id } else { group_id }).to_byte(),
  )
  out.write_bytes(name_bytes[:])
  put_u16(out, payload.length() + 2)
  out.write_bytes(payload[:])
  out.to_bytes()
}

///|
pub fn write_parameters(
  parameters : Parameters,
  limits~ : Limits = Limits::default(),
) -> Bytes raise C3dError {
  validate_parameters(parameters, limits~)
  let records = @buffer.Buffer::Buffer()
  for group in parameters.groups {
    let payload = @buffer.Buffer::Buffer()
    payload.write_byte(group.description.length().to_byte())
    payload.write_bytes(group.description[:])
    records.write_bytes(
      encode_record(group.name, -group.id, group.locked, payload.to_bytes())[:],
    )
  }
  for value in parameters.values {
    let payload = @buffer.Buffer::Buffer()
    payload.write_byte(
      (if value.data_type == -1 { 255 } else { value.data_type }).to_byte(),
    )
    payload.write_byte(value.dimensions.length().to_byte())
    for dimension in value.dimensions {
      payload.write_byte(dimension.to_byte())
    }
    payload.write_bytes(value.data[:])
    payload.write_byte(value.description.length().to_byte())
    payload.write_bytes(value.description[:])
    records.write_bytes(
      encode_record(
        value.name,
        value.group_id,
        value.locked,
        payload.to_bytes(),
      )[:],
    )
  }
  let size = checked_add(records.length(), 6, "parameter section")
  let blocks = checked_add(size, 511, "parameter alignment") / 512
  if blocks > 255 || blocks * 512 > limits.max_parameter_bytes {
    raise C3dError::ResourceLimit("parameter block count")
  }
  let out = @buffer.Buffer::Buffer()
  out.write_byte(0)
  out.write_byte(80)
  out.write_byte(blocks.to_byte())
  out.write_byte(84)
  out.write_bytes(records.to_bytes()[:])
  out.write_byte(0)
  out.write_byte(0)
  pad_to(out, 512)
  out.to_bytes()
}
