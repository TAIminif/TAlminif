///|
/// Read a C3D parameter file without inventing a point-data header or trial.
/// The first word identifies the format and locates the parameter section;
/// when that section starts later, its own first word is reserved and ignored.
pub fn read_parameter_file(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Parameters raise C3dError {
  validate_limits(limits)
  if data.length() > limits.max_file_bytes {
    raise C3dError::ResourceLimit("parameter file size")
  }
  check_range(data, 0, 2)
  if u8(data, 1) != 80 {
    raise C3dError::Invalid("invalid C3D parameter-file signature")
  }
  let parameter_block = u8(data, 0)
  if parameter_block < 1 {
    raise C3dError::Invalid("parameter file has no parameter-block pointer")
  }
  read_parameters(data, parameter_block, limits~)
}

///|
/// Write a standalone, 512-byte-aligned parameter file in the selected
/// processor encoding. The parameter section starts at file block one.
pub fn write_parameter_file(
  parameters : Parameters,
  processor~ : Processor = Intel,
  limits~ : Limits = Limits::default(),
) -> Bytes raise C3dError {
  validate_limits(limits)
  let section = write_parameters(parameters, processor~, limits~)
  if section.length() > limits.max_file_bytes {
    raise C3dError::ResourceLimit("encoded parameter file size")
  }
  b"\x01" + section[1:].to_owned()
}
