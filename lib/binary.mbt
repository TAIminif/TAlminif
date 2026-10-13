///|
pub fn check_range(
  data : Bytes,
  offset : Int32,
  size : Int32,
) -> Unit raise C3dError {
  if offset < 0 || size < 0 {
    raise C3dError::Invalid("negative byte range")
  }
  if offset > data.length() || size > data.length() - offset {
    raise C3dError::Truncated("byte range outside input")
  }
}

///|
pub fn checked_add(
  a : Int32,
  b : Int32,
  context : String,
) -> Int32 raise C3dError {
  if a < 0 || b < 0 || b > 2147483647 - a {
    raise C3dError::ResourceLimit(context)
  }
  a + b
}

///|
pub fn checked_mul(
  a : Int32,
  b : Int32,
  context : String,
) -> Int32 raise C3dError {
  if a < 0 || b < 0 {
    raise C3dError::Invalid(context)
  }
  if a != 0 && b > 2147483647 / a {
    raise C3dError::ResourceLimit(context)
  }
  a * b
}

///|
pub fn u8(data : Bytes, offset : Int32) -> Int32 raise C3dError {
  check_range(data, offset, 1)
  data[offset].to_int()
}

///|
pub fn i8(data : Bytes, offset : Int32) -> Int32 raise C3dError {
  let value = u8(data, offset)
  if value >= 128 {
    value - 256
  } else {
    value
  }
}

///|
pub fn u16(data : Bytes, offset : Int32) -> Int32 raise C3dError {
  check_range(data, offset, 2)
  data[offset].to_int() | (data[offset + 1].to_int() << 8)
}

///|
pub fn i16(data : Bytes, offset : Int32) -> Int32 raise C3dError {
  let value = u16(data, offset)
  if value >= 32768 {
    value - 65536
  } else {
    value
  }
}

///|
pub fn u32(data : Bytes, offset : Int32) -> UInt32 raise C3dError {
  check_range(data, offset, 4)
  data[offset].to_uint() |
  (data[offset + 1].to_uint() << 8) |
  (data[offset + 2].to_uint() << 16) |
  (data[offset + 3].to_uint() << 24)
}

///|
pub fn f32(data : Bytes, offset : Int32) -> Double raise C3dError {
  Float::reinterpret_from_uint(u32(data, offset)).to_double()
}

///|
pub fn ascii(data : Bytes) -> String raise C3dError {
  let out = StringBuilder()
  for byte in data {
    let value = byte.to_int()
    if value > 127 || value == 0 {
      raise C3dError::Invalid("invalid ASCII identifier")
    }
    out.write_char(value.unsafe_to_char())
  }
  out.to_string()
}

///|
pub fn ascii_bytes(text : String) -> Bytes raise C3dError {
  let out = @buffer.Buffer::Buffer()
  for char in text.iter() {
    let value = char.to_int()
    if value < 1 || value > 127 {
      raise C3dError::Invalid("identifier must use non-NUL ASCII")
    }
    out.write_byte(value.to_byte())
  }
  out.to_bytes()
}

///|
pub fn utf8_text(data : Bytes) -> String raise C3dError {
  @utf8.decode(data[:]) catch {
    _ => raise C3dError::Invalid("invalid UTF-8 text")
  }
}

///|
pub fn utf8_bytes(text : String) -> Bytes {
  @utf8.encode(text)
}

///|
pub fn round_int(
  value : Double,
  minimum : Int32,
  maximum : Int32,
  context : String,
) -> Int32 raise C3dError {
  if !finite(value) {
    raise C3dError::Invalid(context + ": non-finite number")
  }
  let rounded = value.round()
  if rounded < minimum.to_double() || rounded > maximum.to_double() {
    raise C3dError::Invalid(context + ": number outside range")
  }
  rounded.to_int()
}

///|
pub fn exact_int(
  value : Double,
  minimum : Int32,
  maximum : Int32,
  context : String,
) -> Int32 raise C3dError {
  let result = round_int(value, minimum, maximum, context)
  if result.to_double() != value {
    raise C3dError::Invalid(context + ": integer required")
  }
  result
}

///|
pub fn put_u16(out : @buffer.Buffer, value : Int32) -> Unit raise C3dError {
  if value < 0 || value > 65535 {
    raise C3dError::Invalid("uint16 outside range")
  }
  out.write_uint16_le(value.to_uint16())
}

///|
pub fn put_i16(out : @buffer.Buffer, value : Int32) -> Unit raise C3dError {
  if value < -32768 || value > 32767 {
    raise C3dError::Invalid("int16 outside range")
  }
  out.write_int16_le(Int16::from_int(value))
}

///|
pub fn put_f32(out : @buffer.Buffer, value : Double) -> Unit raise C3dError {
  if !finite(value) || Float::from_double(value).is_inf() {
    raise C3dError::Invalid("non-finite or overflowing float32")
  }
  out.write_float_le(Float::from_double(value))
}

///|
pub fn pad_to(out : @buffer.Buffer, alignment : Int32) -> Unit raise C3dError {
  if alignment < 1 {
    raise C3dError::Invalid("invalid alignment")
  }
  let padding = (alignment - out.length() % alignment) % alignment
  for _ in 0..<padding {
    out.write_byte(0)
  }
}

///|
pub fn hex_bytes(data : Bytes) -> String {
  let digits = "0123456789abcdef"
  let out = StringBuilder()
  for byte in data {
    let value = byte.to_int()
    out.write_char(digits[value >> 4].to_int().unsafe_to_char())
    out.write_char(digits[value & 15].to_int().unsafe_to_char())
  }
  out.to_string()
}

///|
pub fn parse_hex(
  text : String,
  max_bytes~ : Int32 = 1048576,
) -> Bytes raise C3dError {
  if text.length() % 2 != 0 {
    raise C3dError::Invalid("odd hex length")
  }
  if max_bytes < 0 || text.length() / 2 > max_bytes {
    raise C3dError::ResourceLimit("hex input")
  }
  let out = @buffer.Buffer::Buffer()
  for i = 0; i < text.length(); i = i + 2 {
    out.write_byte(
      ((hex_digit(text[i].to_int()) << 4) | hex_digit(text[i + 1].to_int())).to_byte(),
    )
  }
  out.to_bytes()
}

///|
fn hex_digit(value : Int32) -> Int32 raise C3dError {
  if value >= 48 && value <= 57 {
    return value - 48
  }
  if value >= 65 && value <= 70 {
    return value - 55
  }
  if value >= 97 && value <= 102 {
    return value - 87
  }
  raise C3dError::Invalid("invalid hex digit")
}
