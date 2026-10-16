///|
/// C3D's processor byte controls integers and REAL*4 values throughout a file.
pub(all) enum Processor {
  Intel
  Dec
  Mips
} derive(Debug, Eq)

///|
pub extend Processor with @debug.Debug::{to_repr}

///|
pub extend Processor with Eq::{equal, not_equal}

///|
pub fn Processor::processor_id(self : Processor) -> Int32 {
  match self {
    Intel => 84
    Dec => 85
    Mips => 86
  }
}

///|
pub fn Processor::name(self : Processor) -> String {
  match self {
    Intel => "intel"
    Dec => "dec"
    Mips => "mips"
  }
}

///|
pub fn Processor::description(self : Processor) -> String {
  match self {
    Intel => "Intel IEEE little-endian"
    Dec => "DEC/VAX F_floating little-endian"
    Mips => "SGI/MIPS IEEE big-endian"
  }
}

///|
pub fn processor_from_id(id : Int32) -> Processor raise C3dError {
  match id {
    84 => Intel
    85 => Dec
    86 => Mips
    _ => raise C3dError::Unsupported("unknown C3D processor identifier")
  }
}

///|
pub fn processor_from_name(name : String) -> Processor raise C3dError {
  match name.to_lower() {
    "intel" | "ieee" | "84" => Intel
    "dec" | "vax" | "dec/vax" | "85" => Dec
    "mips" | "sgi" | "sgi/mips" | "86" => Mips
    _ => raise C3dError::Invalid("processor must be intel, dec or mips")
  }
}

///|
/// Read this byte before interpreting any multibyte values in the header.
pub fn read_processor(
  data : Bytes,
  parameter_block : Int32,
) -> Processor raise C3dError {
  if parameter_block < 1 || parameter_block > 255 {
    raise C3dError::Invalid("parameter block outside uint8 range")
  }
  let start = checked_mul(parameter_block - 1, 512, "parameter offset")
  check_range(data, start, 4)
  processor_from_id(u8(data, start + 3))
}

///|
pub fn encoded_u16(
  data : Bytes,
  offset : Int32,
  processor : Processor,
) -> Int32 raise C3dError {
  check_range(data, offset, 2)
  if processor == Mips {
    (data[offset].to_int() << 8) | data[offset + 1].to_int()
  } else {
    u16(data, offset)
  }
}

///|
pub fn encoded_i16(
  data : Bytes,
  offset : Int32,
  processor : Processor,
) -> Int32 raise C3dError {
  let value = encoded_u16(data, offset, processor)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
pub fn encoded_u32(
  data : Bytes,
  offset : Int32,
  processor : Processor,
) -> UInt32 raise C3dError {
  check_range(data, offset, 4)
  if processor == Mips {
    (data[offset].to_uint() << 24) |
    (data[offset + 1].to_uint() << 16) |
    (data[offset + 2].to_uint() << 8) |
    data[offset + 3].to_uint()
  } else {
    u32(data, offset)
  }
}

///|
/// Exact powers of two used here are safely within the binary64 normal range.
fn processor_power_of_two(exponent : Int32) -> Double {
  ((exponent + 1023).to_uint64() << 52).reinterpret_as_double()
}

///|
/// Decode VAX mathematically into binary64, preserving its low-exponent bits.
pub fn encoded_f32(
  data : Bytes,
  offset : Int32,
  processor : Processor,
) -> Double raise C3dError {
  check_range(data, offset, 4)
  if processor != Dec {
    return Float::reinterpret_from_uint(encoded_u32(data, offset, processor)).to_double()
  }
  let first = u16(data, offset)
  let exponent = (first >> 7) & 255
  let negative = (first & 32768) != 0
  if exponent == 0 {
    if negative {
      raise C3dError::Invalid("DEC/VAX reserved floating operand")
    }
    // VAX treats a positive zero exponent as zero even with a dirty fraction.
    return 0.0
  }
  let fraction = ((first & 127) << 16) | u16(data, offset + 2)
  let magnitude = (8388608 + fraction).to_double() *
    processor_power_of_two(exponent - 152)
  if negative {
    -magnitude
  } else {
    magnitude
  }
}

///|
pub fn put_encoded_u16(
  out : @buffer.Buffer,
  value : Int32,
  processor : Processor,
) -> Unit raise C3dError {
  if value < 0 || value > 65535 {
    raise C3dError::Invalid("uint16 outside range")
  }
  if processor == Mips {
    out.write_uint16_be(value.to_uint16())
  } else {
    put_u16(out, value)
  }
}

///|
pub fn put_encoded_i16(
  out : @buffer.Buffer,
  value : Int32,
  processor : Processor,
) -> Unit raise C3dError {
  if value < -32768 || value > 32767 {
    raise C3dError::Invalid("int16 outside range")
  }
  put_encoded_u16(out, if value < 0 { value + 65536 } else { value }, processor)
}

///|
/// Encode with round-to-nearest, ties-to-even. VAX has no infinities or NaNs.
pub fn put_encoded_f32(
  out : @buffer.Buffer,
  value : Double,
  processor : Processor,
) -> Unit raise C3dError {
  if processor != Dec {
    if !finite(value) || Float::from_double(value).is_inf() {
      raise C3dError::Invalid("non-finite or overflowing float32")
    }
    if processor == Mips {
      out.write_float_be(Float::from_double(value))
    } else {
      put_f32(out, value)
    }
    return
  }
  if !finite(value) {
    raise C3dError::Invalid("DEC/VAX cannot encode non-finite values")
  }
  if value == 0.0 {
    out.write_uint_le(0U)
    return
  }
  let magnitude = value.abs()
  if magnitude < processor_power_of_two(-128) {
    raise C3dError::Invalid("DEC/VAX floating underflow")
  }
  let mut normalized = magnitude
  let mut exponent = 129
  while normalized >= 2.0 {
    normalized = normalized * 0.5
    exponent = exponent + 1
  }
  while normalized < 1.0 {
    normalized = normalized * 2.0
    exponent = exponent - 1
  }
  if exponent > 255 {
    raise C3dError::Invalid("DEC/VAX floating overflow")
  }
  let scaled = (normalized - 1.0) * 8388608.0
  let mut fraction = scaled.floor().to_int()
  let remainder = scaled - fraction.to_double()
  if remainder > 0.5 || (remainder == 0.5 && (fraction & 1) != 0) {
    fraction = fraction + 1
  }
  if fraction == 8388608 {
    fraction = 0
    exponent = exponent + 1
  }
  if exponent > 255 {
    raise C3dError::Invalid("DEC/VAX floating overflow after rounding")
  }
  let sign = if value < 0.0 { 32768 } else { 0 }
  put_u16(out, sign | (exponent << 7) | (fraction >> 16))
  put_u16(out, fraction & 65535)
}

///|
/// Quantize to the actual destination format, keeping VAX low-exponent bits.
pub fn quantize_f32(
  value : Double,
  processor : Processor,
) -> Double raise C3dError {
  let out = @buffer.Buffer::Buffer()
  put_encoded_f32(out, value, processor)
  encoded_f32(out.to_bytes(), 0, processor)
}

///| Transcode numeric payloads; textual and byte payloads are left untouched.

///|
/// IEEE-to-IEEE conversion preserves all original bits, including NaN payloads.
pub fn transcode_parameter_data(
  data_type : Int32,
  raw : Bytes,
  source : Processor,
  target : Processor,
) -> Bytes raise C3dError {
  let size = element_size(data_type)
  if raw.length() % size != 0 {
    raise C3dError::Invalid("parameter payload is not an element multiple")
  }
  if size == 1 || source == target {
    return raw
  }
  let out = @buffer.Buffer::Buffer()
  if data_type == 2 {
    for offset = 0; offset < raw.length(); offset = offset + 2 {
      put_encoded_u16(out, encoded_u16(raw, offset, source), target)
    }
  } else if source != Dec && target != Dec {
    for offset = 0; offset < raw.length(); offset = offset + 4 {
      out.write_byte(raw[offset + 3])
      out.write_byte(raw[offset + 2])
      out.write_byte(raw[offset + 1])
      out.write_byte(raw[offset])
    }
  } else {
    for offset = 0; offset < raw.length(); offset = offset + 4 {
      put_encoded_f32(out, encoded_f32(raw, offset, source), target)
    }
  }
  out.to_bytes()
}
