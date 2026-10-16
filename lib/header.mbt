///|
pub fn read_header(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Header raise C3dError {
  validate_limits(limits)
  if data.length() > limits.max_file_bytes {
    raise C3dError::ResourceLimit("file size")
  }
  check_range(data, 0, 512)
  if u8(data, 1) != 80 {
    raise C3dError::Unsupported("only C3D point data format is supported")
  }
  let parameter_block = u8(data, 0)
  if parameter_block < 2 {
    raise C3dError::Unsupported("parameter-only C3D files are unsupported")
  }
  let parameter_offset = checked_mul(
    parameter_block - 1,
    512,
    "parameter offset",
  )
  check_range(data, parameter_offset, 4)
  let processor = read_processor(data, parameter_block)
  let header : Header = {
    processor,
    parameter_block,
    point_count: encoded_u16(data, 2, processor),
    analog_values_per_frame: encoded_u16(data, 4, processor),
    first_frame: encoded_u16(data, 6, processor),
    last_frame: encoded_u16(data, 8, processor),
    max_gap: encoded_u16(data, 10, processor),
    scale: encoded_f32(data, 12, processor),
    data_block: encoded_u16(data, 16, processor),
    analog_subsamples: encoded_u16(data, 18, processor),
    point_rate: encoded_f32(data, 20, processor),
    reserved: data[24:512].to_owned(),
  }
  validate_header(header, limits~)
  let parameter_blocks = u8(data, parameter_offset + 2)
  if parameter_blocks < 1 ||
    header.data_block < parameter_block + parameter_blocks {
    raise C3dError::Invalid("data overlaps parameter section")
  }
  header
}

///|
pub fn validate_header(
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Unit raise C3dError {
  validate_limits(limits)
  for
    field in [
      header.point_count,
      header.analog_values_per_frame,
      header.first_frame,
      header.last_frame,
      header.max_gap,
      header.data_block,
      header.analog_subsamples,
    ] {
    if field < 0 || field > 65535 {
      raise C3dError::Invalid("header integer outside uint16")
    }
  }
  if header.parameter_block < 2 ||
    header.parameter_block > 255 ||
    header.data_block <= header.parameter_block {
    raise C3dError::Invalid("invalid block positions")
  }
  if header.point_count > limits.max_points {
    raise C3dError::ResourceLimit("point count")
  }
  if header.analog_subsamples > limits.max_subsamples {
    raise C3dError::ResourceLimit("analog subsamples")
  }
  if !finite(header.scale) || header.scale == 0.0 {
    raise C3dError::Invalid("invalid point scale")
  }
  if !finite(header.point_rate) || header.point_rate <= 0.0 {
    raise C3dError::Invalid("invalid point rate")
  }
  if header.reserved.length() != 488 {
    raise C3dError::Invalid("header reserved bytes must have length 488")
  }
  if header.analog_values_per_frame > 0 && header.analog_subsamples < 1 {
    raise C3dError::Invalid("analog samples have no subframe count")
  }
  if header.analog_subsamples > 0 &&
    header.analog_values_per_frame % header.analog_subsamples != 0 {
    raise C3dError::Invalid(
      "analog sample count is not divisible by subsamples",
    )
  }
}

///|
pub fn write_header(
  header : Header,
  limits~ : Limits = Limits::default(),
) -> Bytes raise C3dError {
  validate_header(header, limits~)
  let out = @buffer.Buffer::Buffer()
  out.write_byte(header.parameter_block.to_byte())
  out.write_byte(80)
  for
    value in [
      header.point_count,
      header.analog_values_per_frame,
      header.first_frame,
      header.last_frame,
      header.max_gap,
    ] {
    put_encoded_u16(out, value, header.processor)
  }
  put_encoded_f32(out, header.scale, header.processor)
  put_encoded_u16(out, header.data_block, header.processor)
  put_encoded_u16(out, header.analog_subsamples, header.processor)
  put_encoded_f32(out, header.point_rate, header.processor)
  out.write_bytes(header.reserved[:])
  out.to_bytes()
}

///|
pub fn Header::new(
  point_count : Int32,
  point_rate : Double,
  scale~ : Double = -0.01,
  processor~ : Processor = Intel,
) -> Header raise C3dError {
  {
    processor,
    parameter_block: 2,
    point_count,
    analog_values_per_frame: 0,
    first_frame: 1,
    last_frame: 1,
    max_gap: 0,
    scale: quantize_f32(scale, processor),
    data_block: 3,
    analog_subsamples: 0,
    point_rate: quantize_f32(point_rate, processor),
    reserved: Bytes::make(488, 0),
  }
}

///|
pub fn trial_frame(
  parameters : Parameters,
  name : String,
) -> Int32? raise C3dError {
  match parameters.get("TRIAL", name) {
    None => None
    Some(value) => {
      if value.data_type != 2 || value.data.length() != 4 {
        raise C3dError::Invalid("TRIAL frame field must contain two words")
      }
      let combined = encoded_u16(value.data, 0, value.processor).reinterpret_as_uint() |
        (
          encoded_u16(value.data, 2, value.processor).reinterpret_as_uint() <<
          16
        )
      if combined > 2147483647U {
        raise C3dError::ResourceLimit("TRIAL frame number")
      }
      Some(combined.reinterpret_as_int())
    }
  }
}

///|
pub fn resolve_frame_range(
  header : Header,
  parameters : Parameters,
  limits : Limits,
) -> (Int32, Int32) raise C3dError {
  let trial_start = trial_frame(parameters, "ACTUAL_START_FIELD")
  let trial_end = trial_frame(parameters, "ACTUAL_END_FIELD")
  if (trial_start is Some(_)) != (trial_end is Some(_)) {
    raise C3dError::Invalid("TRIAL frame pair incomplete")
  }
  let first = trial_start.unwrap_or(1)
  if first < 1 {
    raise C3dError::Invalid("first frame must be positive")
  }
  let trial_count = match trial_end {
    None => None
    Some(last) => {
      if last < first {
        raise C3dError::Invalid("inverted TRIAL range")
      }
      Some(checked_add(last - first, 1, "TRIAL frame count"))
    }
  }
  let base = match parameters.get("POINT", "FRAMES") {
    None => None
    Some(value) =>
      Some(
        exact_int(
          value.number(unsigned=true),
          0,
          limits.max_frames,
          "POINT:FRAMES",
        ),
      )
  }
  let extended = match parameters.get("POINT", "LONG_FRAMES") {
    None => None
    Some(value) =>
      Some(
        exact_int(
          value.number(unsigned=true),
          0,
          limits.max_frames,
          "POINT:LONG_FRAMES",
        ),
      )
  }
  let count = match extended {
    Some(value) => {
      if base is Some(base_count) && base_count != 65535 && base_count != value {
        raise C3dError::Invalid("conflicting POINT frame counts")
      }
      value
    }
    None =>
      match base {
        Some(value) =>
          if value == 65535 {
            trial_count.unwrap_or(value)
          } else {
            value
          }
        None =>
          match trial_count {
            Some(value) => value
            None => {
              if header.last_frame < header.first_frame {
                raise C3dError::Invalid(
                  "missing frame count and inverted header range",
                )
              }
              header.last_frame - header.first_frame + 1
            }
          }
      }
  }
  if count > limits.max_frames {
    raise C3dError::ResourceLimit("frame count")
  }
  if trial_count is Some(value) && value != count {
    raise C3dError::Invalid("TRIAL range disagrees with frame count")
  }
  let _ = checked_add(first, count, "frame range")
  (first, count)
}

///|
fn labels_or_default(
  parameters : Parameters,
  group : String,
  name : String,
  count : Int32,
  prefix : String,
) -> Array[String] raise C3dError {
  parameters.read_text_series(group, name, count, prefix~)
}

///|
fn numeric_vector(
  parameters : Parameters,
  group : String,
  name : String,
  count : Int32,
  fallback : Double,
  unsigned~ : Bool = false,
) -> Array[Double] raise C3dError {
  if unsigned {
    parameters
    .read_int_series(group, name, count, unsigned~, fallback=0)
    .map(x => x.to_double())
  } else {
    parameters.read_real_series(group, name, count, fallback~)
  }
}

///|
pub fn resolve_layout(
  header : Header,
  parameters : Parameters,
  limits~ : Limits = Limits::default(),
) -> Layout raise C3dError {
  validate_header(header, limits~)
  validate_parameters(parameters, limits~)
  let point_count = exact_int(
    optional_number(
      parameters,
      "POINT",
      "USED",
      header.point_count.to_double(),
      unsigned=true,
    ),
    0,
    limits.max_points,
    "POINT:USED",
  )
  if point_count != header.point_count {
    raise C3dError::Invalid("POINT:USED differs from header")
  }
  let point_scale = optional_number(parameters, "POINT", "SCALE", header.scale)
  let point_rate = optional_number(
    parameters,
    "POINT",
    "RATE",
    header.point_rate,
  )
  if !finite(point_scale) ||
    point_scale == 0.0 ||
    !finite(point_rate) ||
    point_rate <= 0.0 {
    raise C3dError::Invalid("invalid POINT scale or rate")
  }
  if point_scale != header.scale || point_rate != header.point_rate {
    raise C3dError::Invalid("POINT scale/rate differs from header")
  }
  let (first_frame, frame_count) = resolve_frame_range(
    header, parameters, limits,
  )
  let data_block = exact_int(
    optional_number(
      parameters,
      "POINT",
      "DATA_START",
      header.data_block.to_double(),
      unsigned=true,
    ),
    1,
    65535,
    "POINT:DATA_START",
  )
  if data_block != header.data_block {
    raise C3dError::Invalid("POINT:DATA_START differs from header")
  }
  let point_labels = if point_count == 0 {
    []
  } else {
    labels_or_default(parameters, "POINT", "LABELS", point_count, "P")
  }
  let point_descriptions = if point_count == 0 {
    []
  } else {
    labels_or_default(parameters, "POINT", "DESCRIPTIONS", point_count, "")
  }
  let point_unit = optional_text(parameters, "POINT", "UNITS", "mm")
  let header_channels = if header.analog_subsamples == 0 {
    0
  } else {
    header.analog_values_per_frame / header.analog_subsamples
  }
  let analog_count = exact_int(
    optional_number(
      parameters,
      "ANALOG",
      "USED",
      header_channels.to_double(),
      unsigned=true,
    ),
    0,
    limits.max_analog_channels,
    "ANALOG:USED",
  )
  if analog_count != header_channels {
    raise C3dError::Invalid("ANALOG:USED differs from header sample layout")
  }
  let (subsamples, analog_rate, analog_unsigned, global_scale, analog_channels) = if analog_count ==
    0 {
    // The standard makes all remaining ANALOG parameters inactive at USED=0.
    (0, 0.0, false, 1.0, [])
  } else {
    let analog_rate = optional_number(
      parameters,
      "ANALOG",
      "RATE",
      point_rate * header.analog_subsamples.to_double(),
    )
    let subsamples = exact_int(
      analog_rate / point_rate,
      1,
      limits.max_subsamples,
      "analog/point rate ratio",
    )
    if !finite(analog_rate) ||
      analog_rate < 0.0 ||
      subsamples != header.analog_subsamples {
      raise C3dError::Invalid("analog rate and header subsamples disagree")
    }
    let analog_format = optional_text(parameters, "ANALOG", "FORMAT", "SIGNED")
    if analog_format != "SIGNED" && analog_format != "UNSIGNED" {
      raise C3dError::Unsupported("unsupported analog format")
    }
    let analog_unsigned = analog_format == "UNSIGNED"
    let global_scale = optional_number(parameters, "ANALOG", "GEN_SCALE", 1.0)
    if !finite(global_scale) || global_scale == 0.0 {
      raise C3dError::Invalid("invalid analog global scale")
    }
    let labels = labels_or_default(
      parameters, "ANALOG", "LABELS", analog_count, "A",
    )
    let descriptions = labels_or_default(
      parameters, "ANALOG", "DESCRIPTIONS", analog_count, "",
    )
    let units = labels_or_default(
      parameters, "ANALOG", "UNITS", analog_count, "",
    )
    let scales = numeric_vector(
      parameters, "ANALOG", "SCALE", analog_count, 1.0,
    )
    let offsets = numeric_vector(
      parameters,
      "ANALOG",
      "OFFSET",
      analog_count,
      0.0,
      unsigned=analog_unsigned,
    )
    let analog_channels : Array[Channel] = []
    for i in 0..<analog_count {
      if !finite(scales[i]) ||
        scales[i] == 0.0 ||
        !finite(scales[i] * global_scale) ||
        scales[i] * global_scale == 0.0 {
        raise C3dError::Invalid("invalid analog channel scale")
      }
      analog_channels.push({
        label: labels[i],
        description: descriptions[i],
        unit: units[i],
        scale: scales[i],
        offset: offsets[i],
      })
    }
    (subsamples, analog_rate, analog_unsigned, global_scale, analog_channels)
  }
  let sample_values = checked_add(
    checked_mul(point_count, 4, "point values"),
    header.analog_values_per_frame,
    "frame values",
  )
  let total_values = checked_mul(
    sample_values, frame_count, "total sample values",
  )
  if total_values > limits.max_total_values {
    raise C3dError::ResourceLimit("total sample values")
  }
  let float_storage = point_scale < 0.0
  let frame_bytes = checked_mul(
    sample_values,
    if float_storage {
      4
    } else {
      2
    },
    "frame byte size",
  )
  {
    processor: header.processor,
    frame_count,
    first_frame,
    point_count,
    point_rate,
    point_scale,
    point_labels,
    point_descriptions,
    point_unit,
    analog_channels,
    analog_subsamples: subsamples,
    analog_rate,
    analog_global_scale: global_scale,
    analog_unsigned,
    float_storage,
    frame_bytes,
    data_offset: checked_mul(data_block - 1, 512, "data offset"),
  }
}
