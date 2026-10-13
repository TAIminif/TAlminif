///|
pub fn Parameters::empty() -> Parameters {
  { groups: [], values: [], }
}

///|
pub fn Parameters::group(
  self : Parameters,
  name : String,
) -> Group? raise C3dError {
  let normalized = normalize_name(name)
  for group in self.groups {
    if group.name == normalized {
      return Some(group)
    }
  }
  None
}

///|
pub fn Parameters::get(
  self : Parameters,
  group : String,
  name : String,
) -> Parameter? raise C3dError {
  let normalized = normalize_name(name)
  match self.group(group) {
    None => None
    Some(found) => {
      for value in self.values {
        if value.group_id == found.id && value.name == normalized {
          return Some(value)
        }
      }
      None
    }
  }
}

///|
pub fn Parameters::require(
  self : Parameters,
  group : String,
  name : String,
) -> Parameter raise C3dError {
  match self.get(group, name) {
    Some(value) => value
    None => raise C3dError::Invalid("missing parameter " + group + ":" + name)
  }
}

///|
pub fn Parameters::add_group(
  self : Parameters,
  name : String,
  description~ : String = "",
  locked~ : Bool = false,
) -> Parameters raise C3dError {
  let normalized = normalize_name(name)
  if self.group(normalized) is Some(_) {
    raise C3dError::Invalid("group already exists")
  }
  let mut id = 1
  while self.groups.any(group => group.id == id) {
    id = id + 1
  }
  if id > 127 {
    raise C3dError::ResourceLimit("group identifiers exhausted")
  }
  let group = {
    id,
    name: normalized,
    description: utf8_bytes(description),
    locked,
  }
  if group.description.length() > 255 {
    raise C3dError::Invalid("group description too long")
  }
  { groups: self.groups + [group], values: self.values.copy(), }
}

///|
pub fn Parameters::set(
  self : Parameters,
  group : String,
  value : Parameter,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  let base = if self.group(group) is None {
    self.add_group(group)
  } else {
    self
  }
  let id = base.group(group).unwrap().id
  let normalized = { ..value, name: normalize_name(value.name), group_id: id, }
  validate_parameter(normalized)
  let values : Array[Parameter] = []
  let mut replaced = false
  for existing in base.values {
    if existing.group_id == id && existing.name == normalized.name {
      if existing.locked && !override_locked {
        raise C3dError::Invalid("parameter is locked")
      }
      values.push(normalized)
      replaced = true
    } else {
      values.push(existing)
    }
  }
  if !replaced {
    values.push(normalized)
  }
  { groups: base.groups.copy(), values, }
}

///|
pub fn Parameters::remove(
  self : Parameters,
  group : String,
  name : String,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  let existing = self.get(group, name)
  match existing {
    None => self
    Some(value) => {
      if value.locked && !override_locked {
        raise C3dError::Invalid("parameter is locked")
      }
      {
        groups: self.groups.copy(),
        values: self.values.filter(item => {
          !(item.group_id == value.group_id && item.name == value.name)
        }),
      }
    }
  }
}

///|
pub fn Parameter::integer(
  name : String,
  value : Int32,
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  put_i16(out, value)
  {
    group_id: 1,
    name: normalize_name(name),
    data_type: 2,
    dimensions: [],
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
}

///|
pub fn Parameter::unsigned(
  name : String,
  value : Int32,
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  put_u16(out, value)
  {
    group_id: 1,
    name: normalize_name(name),
    data_type: 2,
    dimensions: [],
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
}

///|
pub fn Parameter::real(
  name : String,
  value : Double,
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  put_f32(out, value)
  {
    group_id: 1,
    name: normalize_name(name),
    data_type: 4,
    dimensions: [],
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
}

///|
pub fn Parameter::integers(
  name : String,
  values : Array[Int32],
  dimensions~ : Array[Int32] = [values.length()],
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  for value in values {
    put_i16(out, value)
  }
  let result = {
    group_id: 1,
    name: normalize_name(name),
    data_type: 2,
    dimensions,
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
  validate_parameter(result)
  result
}

///|
pub fn Parameter::unsigneds(
  name : String,
  values : Array[Int32],
  dimensions~ : Array[Int32] = [values.length()],
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  for value in values {
    put_u16(out, value)
  }
  let result = {
    group_id: 1,
    name: normalize_name(name),
    data_type: 2,
    dimensions,
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
  validate_parameter(result)
  result
}

///|
pub fn Parameter::reals(
  name : String,
  values : Array[Double],
  dimensions~ : Array[Int32] = [values.length()],
) -> Parameter raise C3dError {
  let out = @buffer.Buffer::Buffer()
  for value in values {
    put_f32(out, value)
  }
  let result = {
    group_id: 1,
    name: normalize_name(name),
    data_type: 4,
    dimensions,
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
  validate_parameter(result)
  result
}

///|
pub fn Parameter::text(
  name : String,
  value : String,
) -> Parameter raise C3dError {
  let raw = utf8_bytes(value)
  if raw.length() > 255 {
    raise C3dError::ResourceLimit("text parameter width exceeds uint8")
  }
  {
    group_id: 1,
    name: normalize_name(name),
    data_type: -1,
    dimensions: [raw.length()],
    data: raw,
    description: b"",
    locked: false,
  }
}

///|
pub fn Parameter::texts(
  name : String,
  values : Array[String],
) -> Parameter raise C3dError {
  if values.length() > 255 {
    raise C3dError::ResourceLimit("string array exceeds 255 entries")
  }
  let mut width = 1
  for value in values {
    width = width.max(utf8_bytes(value).length())
  }
  if width > 255 {
    raise C3dError::ResourceLimit("string width exceeds 255 bytes")
  }
  let out = @buffer.Buffer::Buffer()
  for value in values {
    let raw = utf8_bytes(value)
    out.write_bytes(raw[:])
    for _ in raw.length()..<width {
      out.write_byte(32)
    }
  }
  {
    group_id: 1,
    name: normalize_name(name),
    data_type: -1,
    dimensions: [width, values.length()],
    data: out.to_bytes(),
    description: b"",
    locked: false,
  }
}

///|
pub fn Parameter::int_values(
  self : Parameter,
  unsigned~ : Bool = false,
) -> Array[Int32] raise C3dError {
  validate_parameter(self)
  let count = element_count(self.dimensions)
  let values : Array[Int32] = []
  match self.data_type {
    1 =>
      for i in 0..<count {
        values.push(if unsigned { u8(self.data, i) } else { i8(self.data, i) })
      }
    2 =>
      for i in 0..<count {
        values.push(
          if unsigned {
            u16(self.data, i * 2)
          } else {
            i16(self.data, i * 2)
          },
        )
      }
    _ => raise C3dError::Invalid("integer parameter required")
  }
  values
}

///|
pub fn Parameter::real_values(self : Parameter) -> Array[Double] raise C3dError {
  validate_parameter(self)
  if self.data_type != 4 {
    raise C3dError::Invalid("float32 parameter required")
  }
  let values : Array[Double] = []
  for i in 0..<element_count(self.dimensions) {
    let value = f32(self.data, i * 4)
    if !finite(value) {
      raise C3dError::Invalid("non-finite numeric parameter")
    }
    values.push(value)
  }
  values
}

///|
pub fn Parameter::number(
  self : Parameter,
  unsigned~ : Bool = false,
) -> Double raise C3dError {
  if element_count(self.dimensions) != 1 {
    raise C3dError::Invalid("scalar numeric parameter required")
  }
  if self.data_type == 4 {
    self.real_values()[0]
  } else {
    self.int_values(unsigned~)[0].to_double()
  }
}

///|
pub fn Parameter::text_values(self : Parameter) -> Array[String] raise C3dError {
  validate_parameter(self)
  if self.data_type != -1 || self.dimensions.length() < 1 {
    raise C3dError::Invalid("character array required")
  }
  let width = self.dimensions[0]
  let count = if self.dimensions.length() == 1 {
    1
  } else {
    element_count(self.dimensions[1:].to_owned())
  }
  let result : Array[String] = []
  for i in 0..<count {
    let start = i * width
    let mut end = start + width
    while end > start && (self.data[end - 1] == 32 || self.data[end - 1] == 0) {
      end = end - 1
    }
    result.push(utf8_text(self.data[start:end].to_owned()))
  }
  result
}

///|
pub fn Parameter::linear_index(
  self : Parameter,
  indices : Array[Int32],
) -> Int32 raise C3dError {
  validate_parameter(self)
  if indices.length() != self.dimensions.length() {
    raise C3dError::Invalid("array index rank mismatch")
  }
  let mut result = 0
  let mut stride = 1
  for i in 0..<indices.length() {
    let index = indices[i]
    if index < 0 || index >= self.dimensions[i] {
      raise C3dError::Invalid("array index outside dimension")
    }
    result = checked_add(
      result,
      checked_mul(index, stride, "array index"),
      "array index",
    )
    stride = checked_mul(stride, self.dimensions[i], "array stride")
  }
  result
}

///|
pub fn Parameter::description_text(self : Parameter) -> String raise C3dError {
  utf8_text(self.description)
}

///|
pub fn Parameters::put_int(
  self : Parameters,
  group : String,
  name : String,
  value : Int32,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::integer(name, value), override_locked~)
}

///|
pub fn Parameters::put_real(
  self : Parameters,
  group : String,
  name : String,
  value : Double,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::real(name, value), override_locked~)
}

///|
pub fn Parameters::put_text(
  self : Parameters,
  group : String,
  name : String,
  value : String,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::text(name, value), override_locked~)
}

///|
pub fn Parameters::put_texts(
  self : Parameters,
  group : String,
  name : String,
  values : Array[String],
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::texts(name, values), override_locked~)
}

///|
pub fn Parameters::put_reals(
  self : Parameters,
  group : String,
  name : String,
  values : Array[Double],
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::reals(name, values), override_locked~)
}

///|
pub fn Parameters::put_ints(
  self : Parameters,
  group : String,
  name : String,
  values : Array[Int32],
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  self.set(group, Parameter::integers(name, values), override_locked~)
}

///|
pub fn optional_number(
  parameters : Parameters,
  group : String,
  name : String,
  fallback : Double,
  unsigned~ : Bool = false,
) -> Double raise C3dError {
  match parameters.get(group, name) {
    None => fallback
    Some(value) => value.number(unsigned~)
  }
}

///|
pub fn optional_text(
  parameters : Parameters,
  group : String,
  name : String,
  fallback : String,
) -> String raise C3dError {
  match parameters.get(group, name) {
    None => fallback
    Some(value) => {
      let texts = value.text_values()
      if texts.length() != 1 {
        raise C3dError::Invalid(
          "scalar text required for " + group + ":" + name,
        )
      }
      texts[0]
    }
  }
}
