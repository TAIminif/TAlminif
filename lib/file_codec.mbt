///|
pub struct Reader {
  data : Bytes
  header : Header
  parameters : Parameters
  layout : Layout
  events : Array[Event]
  mut position : Int32
}

///|
pub fn Reader::new(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Reader raise C3dError {
  let header = read_header(data, limits~)
  let parameters = read_parameters(data, header.parameter_block, limits~)
  let layout = resolve_layout(header, parameters, limits~)
  let length = checked_mul(
    layout.frame_count,
    layout.frame_bytes,
    "data section length",
  )
  check_range(data, layout.data_offset, length)
  let events = read_events(header, parameters)
  validate_semantic_text(layout, events, limits)
  { data, header, parameters, layout, events, position: 0, }
}

///|
pub fn Reader::header(self : Reader) -> Header {
  self.header
}

///|
pub fn Reader::parameters(self : Reader) -> Parameters {
  self.parameters
}

///|
pub fn Reader::layout(self : Reader) -> Layout {
  self.layout
}

///|
pub fn Reader::events(self : Reader) -> Array[Event] {
  self.events.copy()
}

///|
pub fn Reader::position(self : Reader) -> Int32 {
  self.position
}

///|
pub fn Reader::remaining(self : Reader) -> Int32 {
  self.layout.frame_count - self.position
}

///|
pub fn Reader::frame(self : Reader, index : Int32) -> Frame raise C3dError {
  if index < 0 || index >= self.layout.frame_count {
    raise C3dError::Invalid("frame index outside file")
  }
  let offset = checked_add(
    self.layout.data_offset,
    checked_mul(index, self.layout.frame_bytes, "frame offset"),
    "frame offset",
  )
  decode_frame(self.data, offset, self.layout, index)
}

///|
pub fn Reader::seek(self : Reader, index : Int32) -> Unit raise C3dError {
  if index < 0 || index > self.layout.frame_count {
    raise C3dError::Invalid("seek index outside file")
  }
  self.position = index
}

///|
pub fn Reader::next(self : Reader) -> Frame? raise C3dError {
  if self.position == self.layout.frame_count {
    return None
  }
  let frame = self.frame(self.position)
  self.position = self.position + 1
  Some(frame)
}

///|
pub fn Reader::read_batch(
  self : Reader,
  count : Int32,
) -> Array[Frame] raise C3dError {
  if count < 1 {
    raise C3dError::Invalid("batch size must be positive")
  }
  let frames : Array[Frame] = []
  let end = self.position + count.min(self.remaining())
  while self.position < end {
    frames.push(self.next().unwrap())
  }
  frames
}

///|
pub fn Reader::to_document(self : Reader) -> Document raise C3dError {
  let frames : Array[Frame] = []
  for i in 0..<self.layout.frame_count {
    frames.push(self.frame(i))
  }
  {
    header: self.header,
    parameters: self.parameters,
    layout: self.layout,
    frames,
    events: self.events.copy(),
  }
}

///|
pub fn read(
  data : Bytes,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  Reader::new(data, limits~).to_document()
}

///|
pub fn Document::new(
  point_labels : Array[String],
  analog_channels : Array[Channel],
  frames : Array[Frame],
  point_rate~ : Double = 100.0,
  scale~ : Double = -0.01,
  analog_subsamples~ : Int32 = 0,
  analog_global_scale~ : Double = 1.0,
  analog_unsigned~ : Bool = false,
  point_unit~ : String = "mm",
  processor~ : Processor = Intel,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  validate_limits(limits)
  if point_labels.length() > limits.max_points ||
    analog_channels.length() > limits.max_analog_channels ||
    frames.length() > limits.max_frames {
    raise C3dError::ResourceLimit("document dimensions")
  }
  let header = Header::new(
    point_labels.length(),
    point_rate,
    scale~,
    processor~,
  )
  let header = {
    ..header,
    analog_subsamples,
    analog_values_per_frame: checked_mul(
      analog_subsamples,
      analog_channels.length(),
      "analog frame values",
    ),
    last_frame: frames.length().max(1).min(65535),
  }
  let parameters = core_parameters(
    Parameters::empty(),
    header,
    point_labels,
    Array::make(point_labels.length(), ""),
    point_unit,
    analog_channels,
    analog_global_scale,
    analog_unsigned,
    frames.length(),
    1,
  )
  let layout = resolve_layout(header, parameters, limits~)
  let document = { header, parameters, layout, frames, events: [], }
  validate_document(document, limits~)
  document
}

///|
pub fn validate_document(
  document : Document,
  limits~ : Limits = Limits::default(),
) -> Unit raise C3dError {
  let resolved = resolve_layout(document.header, document.parameters, limits~)
  validate_semantic_text(resolved, document.events, limits)
  if resolved != document.layout {
    raise C3dError::Invalid("document cached layout differs from metadata")
  }
  if document.frames.length() != resolved.frame_count {
    raise C3dError::Invalid("document frame count differs from metadata")
  }
  for i in 0..<document.frames.length() {
    if document.frames[i].number != resolved.first_frame + i {
      raise C3dError::Invalid("frame numbering is not sequential")
    }
    validate_frame(document.frames[i], resolved)
  }
  let _ = write_event_parameters(
    document.parameters,
    document.events,
    processor=document.header.processor,
  )
}

///|
pub fn core_parameters(
  base : Parameters,
  header : Header,
  labels : Array[String],
  descriptions : Array[String],
  unit : String,
  channels : Array[Channel],
  global_scale : Double,
  unsigned : Bool,
  frame_count : Int32,
  first_frame : Int32,
) -> Parameters raise C3dError {
  if labels.length() > 65535 || channels.length() > 65535 {
    raise C3dError::ResourceLimit("C3D USED uint16 count")
  }
  if labels.length() != descriptions.length() {
    raise C3dError::Invalid("point description count")
  }
  if first_frame < 1 || frame_count < 0 {
    raise C3dError::Invalid("invalid trial frame range")
  }
  let mut result = base
  result = result.set(
    "POINT",
    Parameter::unsigned("USED", labels.length()),
    override_locked=true,
  )
  result = result.put_real(
    "POINT",
    "SCALE",
    header.scale,
    override_locked=true,
    processor=header.processor,
  )
  result = result.put_real(
    "POINT",
    "RATE",
    header.point_rate,
    override_locked=true,
    processor=header.processor,
  )
  result = result.set(
    "POINT",
    Parameter::unsigned("DATA_START", header.data_block),
    override_locked=true,
  )
  if frame_count <= 65535 {
    result = result.set(
      "POINT",
      Parameter::unsigned("FRAMES", frame_count),
      override_locked=true,
    )
    result = result.remove("POINT", "LONG_FRAMES", override_locked=true)
  } else {
    result = result.set(
      "POINT",
      Parameter::unsigned("FRAMES", 65535),
      override_locked=true,
    )
    result = result.put_real(
      "POINT",
      "LONG_FRAMES",
      frame_count.to_double(),
      override_locked=true,
    )
  }
  let last = if frame_count == 0 {
    first_frame - 1
  } else {
    checked_add(first_frame, frame_count - 1, "last trial frame")
  }
  result = result.set(
    "TRIAL",
    Parameter::unsigneds("ACTUAL_START_FIELD", [
      first_frame & 65535,
      first_frame >> 16,
    ]),
    override_locked=true,
  )
  if frame_count > 0 {
    result = result.set(
      "TRIAL",
      Parameter::unsigneds("ACTUAL_END_FIELD", [last & 65535, last >> 16]),
      override_locked=true,
    )
  } else {
    result = result.remove("TRIAL", "ACTUAL_START_FIELD", override_locked=true)
    result = result.remove("TRIAL", "ACTUAL_END_FIELD", override_locked=true)
  }
  result = result.put_text_series(
    "POINT",
    "LABELS",
    labels,
    override_locked=true,
  )
  result = result.put_text_series(
    "POINT",
    "DESCRIPTIONS",
    descriptions,
    override_locked=true,
  )
  result = result.put_text("POINT", "UNITS", unit, override_locked=true)
  result = result.set(
    "ANALOG",
    Parameter::unsigned("USED", channels.length()),
    override_locked=true,
  )
  result = result.put_real(
    "ANALOG",
    "RATE",
    header.point_rate * header.analog_subsamples.to_double(),
    override_locked=true,
    processor=header.processor,
  )
  result = result.put_real(
    "ANALOG",
    "GEN_SCALE",
    global_scale,
    override_locked=true,
    processor=header.processor,
  )
  result = result.put_text(
    "ANALOG",
    "FORMAT",
    if unsigned {
      "UNSIGNED"
    } else {
      "SIGNED"
    },
    override_locked=true,
  )
  result = result.put_text_series(
    "ANALOG",
    "LABELS",
    channels.map(c => c.label),
    override_locked=true,
  )
  result = result.put_text_series(
    "ANALOG",
    "DESCRIPTIONS",
    channels.map(c => c.description),
    override_locked=true,
  )
  result = result.put_text_series(
    "ANALOG",
    "UNITS",
    channels.map(c => c.unit),
    override_locked=true,
  )
  result = result.put_real_series(
    "ANALOG",
    "SCALE",
    channels.map(c => c.scale),
    override_locked=true,
    processor=header.processor,
  )
  let offsets = channels.map(c => {
    exact_int(
      c.offset,
      if unsigned {
        0
      } else {
        -32768
      },
      if unsigned {
        65535
      } else {
        32767
      },
      "analog offset",
    )
  })
  let result = result.put_int_series(
    "ANALOG",
    "OFFSET",
    offsets,
    unsigned~,
    override_locked=true,
  )
  retain_parameter_metadata(result, base)
}

///|
// Preserve opaque header bytes while migrating only the defined event fields.
fn header_without_events(header : Header) -> Bytes {
  let reserved = header.reserved.to_array()
  for offset in 274..<278 {
    reserved[offset] = 0
  }
  for offset in 280..<370 {
    reserved[offset] = 0
  }
  for offset in 372..<444 {
    reserved[offset] = 0
  }
  Bytes::from_array(reserved)
}

///|
pub fn write(
  document : Document,
  limits~ : Limits = Limits::default(),
  processor~ : Processor = document.header.processor,
) -> Bytes raise C3dError {
  validate_document(document, limits~)
  let mut parameters = write_event_parameters(
    document.parameters,
    document.events,
    processor=document.header.processor,
  )
  let provisional = write_parameters(parameters, limits~, processor~)
  let data_block = 2 + provisional.length() / 512
  parameters = parameters.set(
    "POINT",
    Parameter::unsigned("DATA_START", data_block),
    override_locked=true,
  )
  parameters = retain_parameter_metadata(parameters, document.parameters)
  let section = write_parameters(parameters, limits~, processor~)
  if section.length() != provisional.length() {
    raise C3dError::Invalid("parameter layout changed after DATA_START update")
  }
  let header = {
    ..document.header,
    processor,
    analog_subsamples: document.layout.analog_subsamples,
    parameter_block: 2,
    data_block,
    reserved: header_without_events(document.header),
  }
  // Frame encoding must use the actual target representation of calibration
  // and scale, including VAX values which round when converted to IEEE.
  let header_bytes = write_header(header, limits~)
  let header = {
    ..header,
    scale: encoded_f32(header_bytes, 12, processor),
    point_rate: encoded_f32(header_bytes, 20, processor),
  }
  let target_parameters = read_parameters(
    Bytes::make(512, 0) + section,
    2,
    limits~,
  )
  let layout = resolve_layout(header, target_parameters, limits~)
  let total = checked_add(
    512 + section.length(),
    checked_mul(layout.frame_bytes, layout.frame_count, "write sample bytes"),
    "write file bytes",
  )
  let padded = checked_add(total, (512 - total % 512) % 512, "write alignment")
  if padded > limits.max_file_bytes {
    raise C3dError::ResourceLimit("encoded file size")
  }
  let output = @buffer.Buffer::Buffer(size_hint=padded)
  output.write_bytes(header_bytes[:])
  output.write_bytes(section[:])
  for frame in document.frames {
    output.write_bytes(encode_frame(frame, layout)[:])
  }
  pad_to(output, 512)
  output.to_bytes()
}
