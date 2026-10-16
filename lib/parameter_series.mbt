///|
/// Numbered C3D parameters form one channel list. Only canonical suffixes
/// 2, 3, ... belong to the series; similarly named vendor fields are retained.
fn series_index(name : String, base : String) -> Int32? {
  if name == base {
    return Some(1)
  }
  if name.length() <= base.length() {
    return None
  }
  for i in 0..<base.length() {
    if name[i] != base[i] {
      return None
    }
  }
  if name[base.length()].to_int() == 48 {
    return None
  }
  let mut index = 0
  for i in base.length()..<name.length() {
    let digit = name[i].to_int() - 48
    if digit < 0 || digit > 9 {
      return None
    }
    // Large suffixes still identify stale series records, without overflowing.
    index = (index * 10 + digit).min(65536)
  }
  if index < 2 {
    None
  } else {
    Some(index)
  }
}

///|
fn series_name(base : String, index : Int32) -> String {
  if index == 1 {
    base
  } else {
    "\{base}\{index}"
  }
}

///|
fn series_count(count : Int32) -> Unit raise C3dError {
  if count < 0 {
    raise C3dError::Invalid("negative channel series count")
  }
  if count > 65535 {
    raise C3dError::ResourceLimit("channel series exceeds uint16 USED")
  }
}

///|
fn series_parameters(
  parameters : Parameters,
  group : String,
  base : String,
  count : Int32,
  text_mode~ : Bool = false,
) -> Array[Parameter] raise C3dError {
  series_count(count)
  let normalized = normalize_name(base)
  let owner = match parameters.group(group) {
    None => return []
    Some(owner) => owner
  }
  let records : Map[Int32, Parameter] = Map([])
  for value in parameters.values {
    if value.group_id == owner.id {
      match series_index(value.name, normalized) {
        None => ()
        Some(index) => {
          if records.contains(index) {
            raise C3dError::Invalid("duplicate numbered channel parameter")
          }
          records[index] = value
        }
      }
    }
  }
  if records.is_empty() {
    return []
  }
  let segments = if text_mode {
    records.length()
  } else {
    ((count + 254) / 255).max(1)
  }
  if records.length() != segments {
    raise C3dError::Invalid(
      "wrong number of " + group + ":" + normalized + " segments",
    )
  }
  let result : Array[Parameter] = []
  for index in 1..<(segments + 1) {
    match records.get(index) {
      None =>
        raise C3dError::Invalid(
          "missing " + group + ":" + series_name(normalized, index),
        )
      Some(value) => result.push(value)
    }
  }
  result
}

///|
fn series_segment_length(count : Int32, index : Int32) -> Int32 {
  (count - index * 255).min(255)
}

///|
fn validate_series_vector(
  value : Parameter,
  count : Int32,
) -> Unit raise C3dError {
  if value.dimensions.length() == 0 && count == 1 {
    return
  }
  if value.dimensions.length() != 1 ||
    value.dimensions[0] < count ||
    value.dimensions[0] > 255 ||
    (count == 0 && value.dimensions[0] != 0) {
    raise C3dError::Invalid("numbered channel vector has wrong dimensions")
  }
}

///|
/// Read LABELS, LABELS2, ... as a single list in data-channel order.
/// Historical files may split strings at 127 entries instead of 255 and may
/// omit names. Concatenate their actual arrays, then pad or truncate to USED.
pub fn Parameters::read_text_series(
  self : Parameters,
  group : String,
  base : String,
  count : Int32,
  prefix~ : String = "",
) -> Array[String] raise C3dError {
  let parts = series_parameters(self, group, base, count, text_mode=true)
  if parts.is_empty() {
    return if prefix == "" {
      Array::make(count, "")
    } else {
      Array::makei(count, index => "\{prefix}\{index + 1}")
    }
  }
  let result : Array[String] = []
  for index in 0..<parts.length() {
    let part = parts[index]
    let values = part.text_values()
    if values.length() > 255 ||
      (
        part.dimensions.length() != 2 &&
        !(part.dimensions.length() == 1 && values.length() == 1)
      ) {
      raise C3dError::Invalid("numbered channel text has wrong dimensions")
    }
    for value in values {
      if result.length() < count {
        result.push(value)
      }
    }
  }
  while result.length() < count {
    result.push(
      if prefix == "" {
        ""
      } else {
        "\{prefix}\{result.length() + 1}"
      },
    )
  }
  result
}

///|
pub fn Parameters::read_real_series(
  self : Parameters,
  group : String,
  base : String,
  count : Int32,
  fallback~ : Double = 1.0,
) -> Array[Double] raise C3dError {
  let parts = series_parameters(self, group, base, count)
  if parts.is_empty() {
    return Array::make(count, fallback)
  }
  let result : Array[Double] = []
  for index in 0..<parts.length() {
    let part = parts[index]
    validate_series_vector(part, series_segment_length(count, index))
    let values = if part.data_type == 4 {
      part.real_values()
    } else {
      part.int_values().map(value => value.to_double())
    }
    for i in 0..<series_segment_length(count, index) {
      result.push(values[i])
    }
  }
  result
}

///|
pub fn Parameters::read_int_series(
  self : Parameters,
  group : String,
  base : String,
  count : Int32,
  unsigned~ : Bool = false,
  fallback~ : Int32 = 0,
) -> Array[Int32] raise C3dError {
  let parts = series_parameters(self, group, base, count)
  if parts.is_empty() {
    return Array::make(count, fallback)
  }
  let result : Array[Int32] = []
  for index in 0..<parts.length() {
    let part = parts[index]
    validate_series_vector(part, series_segment_length(count, index))
    let values = part.int_values(unsigned~)
    for i in 0..<series_segment_length(count, index) {
      result.push(values[i])
    }
  }
  result
}

///|
/// Remove only the base parameter and its canonical numbered continuation.
pub fn Parameters::remove_series(
  self : Parameters,
  group : String,
  base : String,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  let normalized = normalize_name(base)
  let owner = match self.group(group) {
    None => return self
    Some(owner) => owner
  }
  let values : Array[Parameter] = []
  for value in self.values {
    if value.group_id == owner.id &&
      series_index(value.name, normalized) is Some(_) {
      if value.locked && !override_locked {
        raise C3dError::Invalid("numbered channel parameter is locked")
      }
    } else {
      values.push(value)
    }
  }
  { groups: self.groups.copy(), values, }
}

///|
/// Write a uniformly padded text series, repartitioning channel metadata
/// after selections or reordering and removing any obsolete trailing records.
pub fn Parameters::put_text_series(
  self : Parameters,
  group : String,
  base : String,
  values : Array[String],
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  series_count(values.length())
  let normalized = normalize_name(base)
  let mut result = self.remove_series(group, normalized, override_locked~)
  let mut width = 1
  for value in values {
    width = width.max(utf8_bytes(value).length())
  }
  if width > 255 {
    raise C3dError::ResourceLimit("channel text width exceeds uint8")
  }
  let segments = ((values.length() + 254) / 255).max(1)
  for index in 0..<segments {
    let start = index * 255
    let end = (start + 255).min(values.length())
    let part = Parameter::texts(
      series_name(normalized, index + 1),
      values[start:end].to_owned(),
    )
    let payload = @buffer.Buffer::Buffer()
    for value in values[start:end] {
      let raw = utf8_bytes(value)
      payload.write_bytes(raw[:])
      for _ in raw.length()..<width {
        payload.write_byte(32)
      }
    }
    result = result.set(group, {
      ..part,
      dimensions: [width, end - start],
      data: payload.to_bytes(),
    })
  }
  result
}

///|
pub fn Parameters::put_real_series(
  self : Parameters,
  group : String,
  base : String,
  values : Array[Double],
  processor~ : Processor = Intel,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  series_count(values.length())
  let normalized = normalize_name(base)
  let mut result = self.remove_series(group, normalized, override_locked~)
  let segments = ((values.length() + 254) / 255).max(1)
  for index in 0..<segments {
    let start = index * 255
    let end = (start + 255).min(values.length())
    result = result.set(
      group,
      Parameter::reals(
        series_name(normalized, index + 1),
        values[start:end].to_owned(),
        processor~,
      ),
    )
  }
  result
}

///|
pub fn Parameters::put_int_series(
  self : Parameters,
  group : String,
  base : String,
  values : Array[Int32],
  unsigned~ : Bool = false,
  override_locked~ : Bool = false,
) -> Parameters raise C3dError {
  series_count(values.length())
  let normalized = normalize_name(base)
  let mut result = self.remove_series(group, normalized, override_locked~)
  let segments = ((values.length() + 254) / 255).max(1)
  for index in 0..<segments {
    let start = index * 255
    let end = (start + 255).min(values.length())
    let name = series_name(normalized, index + 1)
    let part = values[start:end].to_owned()
    result = result.set(
      group,
      if unsigned {
        Parameter::unsigneds(name, part)
      } else {
        Parameter::integers(name, part)
      },
    )
  }
  result
}
