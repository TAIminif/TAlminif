///|
pub fn rebuild(
  document : Document,
  frames : Array[Frame],
  labels : Array[String],
  descriptions : Array[String],
  channels : Array[Channel],
  first_frame : Int32,
  events : Array[Event],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  let analog_values = checked_mul(
    document.layout.analog_subsamples,
    channels.length(),
    "edited analog values",
  )
  let subsamples = if channels.is_empty() {
    0
  } else {
    document.layout.analog_subsamples
  }
  let header = {
    ..document.header,
    point_count: labels.length(),
    analog_values_per_frame: if channels.is_empty() {
      0
    } else {
      analog_values
    },
    analog_subsamples: subsamples,
    first_frame: first_frame.min(65535),
    last_frame: if frames.is_empty() {
      first_frame.min(65535)
    } else {
      checked_add(first_frame, frames.length() - 1, "edited last frame").min(
        65535,
      )
    },
  }
  let parameters = core_parameters(
    document.parameters,
    header,
    labels,
    descriptions,
    document.layout.point_unit,
    channels,
    document.layout.analog_global_scale,
    document.layout.analog_unsigned,
    frames.length(),
    first_frame,
  )
  let parameters = write_event_parameters(
    parameters,
    events,
    processor=header.processor,
  )
  let layout = resolve_layout(header, parameters, limits~)
  let result = { header, parameters, layout, frames, events, }
  validate_document(result, limits~)
  result
}

///|
pub fn Document::crop(
  self : Document,
  start : Int32,
  end : Int32,
  rebase~ : Bool = true,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  validate_document(self, limits~)
  if start < 0 || end <= start || end > self.frames.length() {
    raise C3dError::Invalid("crop requires a nonempty half-open frame range")
  }
  let old_start = frame_time_boundary(self.layout, start)
  let old_end = frame_time_boundary(self.layout, end)
  let first = if rebase { 1 } else { self.layout.first_frame + start }
  let frames : Array[Frame] = []
  for i in start..<end {
    let frame = self.frames[i]
    frames.push({
      number: checked_add(first, i - start, "cropped frame number"),
      points: frame.points.copy(),
      analog: frame.analog.map(channel => channel.copy()),
    })
  }
  let events : Array[Event] = []
  for event in self.events {
    if event.time >= old_start && event.time < old_end {
      events.push({
        ..event,
        time: if rebase {
          event.time - old_start
        } else {
          event.time
        },
      })
    }
  }
  rebuild(
    self,
    frames,
    self.layout.point_labels,
    self.layout.point_descriptions,
    self.layout.analog_channels,
    first,
    events,
    limits~,
  )
}

///|
pub fn Document::crop_time(
  self : Document,
  start : Double,
  end : Double,
  rebase~ : Bool = true,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if !finite(start) || !finite(end) || end <= start {
    raise C3dError::Invalid("invalid crop time range")
  }
  validate_document(self, limits~)
  let origin = frame_time_boundary(self.layout, 0)
  let stop = frame_time_boundary(self.layout, self.layout.frame_count)
  if start < origin || end > stop {
    raise C3dError::Invalid("time crop outside trial")
  }
  let first = frame_time_lower_bound(self.layout, start)
  let last = frame_time_lower_bound(self.layout, end)
  if first >= last {
    raise C3dError::Invalid("time crop contains no frame starts")
  }
  self.crop(first, last, rebase~, limits~)
}

///|
fn validate_selection(
  indices : Array[Int32],
  count : Int32,
) -> Unit raise C3dError {
  let seen : Map[Int32, Bool] = Map([])
  for index in indices {
    if index < 0 || index >= count {
      raise C3dError::Invalid("selected index outside channel range")
    }
    if seen.contains(index) {
      raise C3dError::Invalid("duplicate selected channel index")
    }
    seen[index] = true
  }
}

///|
pub fn Document::select_points(
  self : Document,
  indices : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  validate_document(self, limits~)
  validate_selection(indices, self.layout.point_count)
  let labels = indices.map(index => self.layout.point_labels[index])
  let descriptions = indices.map(index => self.layout.point_descriptions[index])
  let frames = self.frames.map(frame => {
    ..frame,
    points: indices.map(index => frame.points[index]),
    analog: frame.analog.map(channel => channel.copy()),
  })
  rebuild(
    self,
    frames,
    labels,
    descriptions,
    self.layout.analog_channels,
    self.layout.first_frame,
    self.events.copy(),
    limits~,
  )
}

///|
pub fn Document::select_analog(
  self : Document,
  indices : Array[Int32],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  validate_document(self, limits~)
  validate_selection(indices, self.layout.analog_channels.length())
  if optional_number(
      self.parameters,
      "FORCE_PLATFORM",
      "USED",
      0.0,
      unsigned=true,
    ) >
    0.0 {
    raise C3dError::Unsupported(
      "analog selection with force-platform channel references",
    )
  }
  let channels = indices.map(index => self.layout.analog_channels[index])
  let frames = self.frames.map(frame => {
    ..frame,
    points: frame.points.copy(),
    analog: indices.map(index => frame.analog[index].copy()),
  })
  let result = rebuild(
    self,
    frames,
    self.layout.point_labels,
    self.layout.point_descriptions,
    channels,
    self.layout.first_frame,
    self.events.copy(),
    limits~,
  )
  let parameters = select_analog_auxiliary(
    self.parameters,
    result.parameters,
    indices,
  )
  let result = { ..result, parameters, }
  validate_document(result, limits~)
  result
}

///|
fn select_analog_auxiliary(
  source : Parameters,
  target : Parameters,
  indices : Array[Int32],
) -> Parameters raise C3dError {
  let mut result = target
  let source_count = exact_int(
    optional_number(source, "ANALOG", "USED", 0.0, unsigned=true),
    0,
    65535,
    "ANALOG:USED",
  )
  if source_count == 0 {
    return target
  }
  for name in ["GAIN", "RANGE"] {
    let parts = series_parameters(source, "ANALOG", name, source_count)
    if parts.is_empty() {
      continue
    }
    let template = parts[0]
    if template.data_type != 1 &&
      template.data_type != 2 &&
      template.data_type != 4 {
      raise C3dError::Unsupported("non-numeric ANALOG auxiliary metadata")
    }
    let size = element_size(template.data_type)
    let flattened = @buffer.Buffer::Buffer()
    for part_index in 0..<parts.length() {
      let part = parts[part_index]
      let count = series_segment_length(source_count, part_index)
      validate_series_vector(part, count)
      validate_parameter(part)
      if part.data_type != template.data_type {
        raise C3dError::Invalid("ANALOG auxiliary series data types differ")
      }
      let data = transcode_parameter_data(
        part.data_type,
        part.data,
        part.processor,
        template.processor,
      )
      flattened.write_bytes(data[0:count * size])
    }
    let source_data = flattened.to_bytes()
    let selected = @buffer.Buffer::Buffer()
    for index in indices {
      selected.write_bytes(source_data[index * size:(index + 1) * size])
    }
    let selected_data = selected.to_bytes()
    result = result.remove_series("ANALOG", name, override_locked=true)
    let segments = ((indices.length() + 254) / 255).max(1)
    for part_index in 0..<segments {
      let start = part_index * 255
      let end = (start + 255).min(indices.length())
      result = result.set("ANALOG", {
        ..template,
        processor: template.processor,
        name: series_name(name, part_index + 1),
        dimensions: [end - start],
        data: selected_data[start * size:end * size].to_owned(),
      })
    }
  }
  retain_parameter_metadata(result, source)
}

///|
pub fn Document::rename_point(
  self : Document,
  index : Int32,
  label : String,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if index < 0 || index >= self.layout.point_count {
    raise C3dError::Invalid("marker index outside range")
  }
  let labels = self.layout.point_labels.copy()
  labels[index] = label
  rebuild(
    self,
    self.frames.copy(),
    labels,
    self.layout.point_descriptions,
    self.layout.analog_channels,
    self.layout.first_frame,
    self.events.copy(),
    limits~,
  )
}

///|
pub fn Document::rename_analog(
  self : Document,
  index : Int32,
  label : String,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if index < 0 || index >= self.layout.analog_channels.length() {
    raise C3dError::Invalid("analog index outside range")
  }
  let channels = self.layout.analog_channels.copy()
  channels[index] = { ..channels[index], label, }
  rebuild(
    self,
    self.frames.copy(),
    self.layout.point_labels,
    self.layout.point_descriptions,
    channels,
    self.layout.first_frame,
    self.events.copy(),
    limits~,
  )
}

///|
pub fn Document::with_events(
  self : Document,
  events : Array[Event],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  rebuild(
    self,
    self.frames.copy(),
    self.layout.point_labels,
    self.layout.point_descriptions,
    self.layout.analog_channels,
    self.layout.first_frame,
    events.copy(),
    limits~,
  )
}

///|
pub fn Document::convert_storage(
  self : Document,
  scale : Double,
  unsigned~ : Bool = self.layout.analog_unsigned,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if !finite(scale) || scale == 0.0 {
    raise C3dError::Invalid("invalid target point scale")
  }
  let header = {
    ..self.header,
    scale: quantize_f32(scale, self.header.processor),
  }
  let params = core_parameters(
    self.parameters,
    header,
    self.layout.point_labels,
    self.layout.point_descriptions,
    self.layout.point_unit,
    self.layout.analog_channels,
    self.layout.analog_global_scale,
    unsigned,
    self.frames.length(),
    self.layout.first_frame,
  )
  let layout = resolve_layout(header, params, limits~)
  let result = { ..self, header, parameters: params, layout, }
  validate_document(result, limits~)
  for frame in self.frames {
    let _ = encode_frame(frame, layout)
  }
  result
}

///|
pub fn Document::replace_frame(
  self : Document,
  index : Int32,
  frame : Frame,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if index < 0 || index >= self.frames.length() {
    raise C3dError::Invalid("replacement frame index")
  }
  let frame = { ..frame, number: self.layout.first_frame + index, }
  validate_frame(frame, self.layout)
  let frames = self.frames.copy()
  frames[index] = {
    ..frame,
    points: frame.points.copy(),
    analog: frame.analog.map(a => a.copy()),
  }
  let result = { ..self, frames, }
  validate_document(result, limits~)
  result
}

///|
pub fn Document::select_points_by_label(
  self : Document,
  labels : Array[String],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  let indices : Array[Int32] = []
  for label in labels {
    let matches : Array[Int32] = []
    for i in 0..<self.layout.point_labels.length() {
      if self.layout.point_labels[i] == label {
        matches.push(i)
      }
    }
    if matches.length() != 1 {
      raise C3dError::Invalid("point label is missing or ambiguous")
    }
    indices.push(matches[0])
  }
  self.select_points(indices, limits~)
}

///|
pub fn Document::select_analog_by_label(
  self : Document,
  labels : Array[String],
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  let indices : Array[Int32] = []
  for label in labels {
    let matches : Array[Int32] = []
    for i in 0..<self.layout.analog_channels.length() {
      if self.layout.analog_channels[i].label == label {
        matches.push(i)
      }
    }
    if matches.length() != 1 {
      raise C3dError::Invalid("analog label is missing or ambiguous")
    }
    indices.push(matches[0])
  }
  self.select_analog(indices, limits~)
}
