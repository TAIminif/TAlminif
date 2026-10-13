///|
pub fn rebuild(
  document : Document,
  frames : Array[Frame],
  labels : Array[String],
  descriptions : Array[String],
  channels : Array[Channel],
  first_frame : Int,
  events : Array[Event],
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
  let parameters = write_event_parameters(parameters, events)
  let layout = resolve_layout(header, parameters)
  let result = { header, parameters, layout, frames, events }
  validate_document(result)
  result
}

///|
pub fn Document::crop(
  self : Document,
  start : Int,
  end : Int,
  rebase? : Bool = true,
) -> Document raise C3dError {
  validate_document(self)
  if start < 0 || end <= start || end > self.frames.length() {
    raise C3dError::Invalid("crop requires a nonempty half-open frame range")
  }
  let old_start = (self.layout.first_frame - 1 + start).to_double() /
    self.layout.point_rate
  let old_end = (self.layout.first_frame - 1 + end).to_double() /
    self.layout.point_rate
  let first = if rebase { 1 } else { self.layout.first_frame + start }
  let frames : Array[Frame] = []
  for i in start..<end {
    let frame = self.frames[i]
    frames.push({
      number: first + i - start,
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
  )
}

///|
pub fn Document::crop_time(
  self : Document,
  start : Double,
  end : Double,
  rebase? : Bool = true,
) -> Document raise C3dError {
  if !finite(start) || !finite(end) || end <= start {
    raise C3dError::Invalid("invalid crop time range")
  }
  let origin = (self.layout.first_frame - 1).to_double() /
    self.layout.point_rate
  let first = ((start - origin) * self.layout.point_rate).ceil()
  let last = ((end - origin) * self.layout.point_rate).ceil()
  if first < 0.0 || last > self.frames.length().to_double() || first >= last {
    raise C3dError::Invalid(
      "time crop outside trial or contains no frame starts",
    )
  }
  self.crop(first.to_int(), last.to_int(), rebase~)
}

///|
fn validate_selection(indices : Array[Int], count : Int) -> Unit raise C3dError {
  let seen : Map[Int, Bool] = Map([])
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
  indices : Array[Int],
) -> Document raise C3dError {
  validate_document(self)
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
  )
}

///|
pub fn Document::select_analog(
  self : Document,
  indices : Array[Int],
) -> Document raise C3dError {
  validate_document(self)
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
  )
  let parameters = select_analog_auxiliary(
    self.parameters,
    result.parameters,
    indices,
  )
  { ..result, parameters, }
}

///|
fn select_analog_auxiliary(
  source : Parameters,
  target : Parameters,
  indices : Array[Int],
) -> Parameters raise C3dError {
  let mut result = target
  for name in ["GAIN", "RANGE"] {
    match source.get("ANALOG", name) {
      None => ()
      Some(value) => {
        if value.dimensions.length() != 1 {
          raise C3dError::Unsupported("non-vector ANALOG auxiliary metadata")
        }
        let size = element_size(value.data_type)
        let payload = @buffer.Buffer::Buffer()
        for index in indices {
          if index >= value.dimensions[0] {
            raise C3dError::Invalid("ANALOG auxiliary metadata too short")
          }
          payload.write_bytes(value.data[index * size:(index + 1) * size])
        }
        result = result.set(
          "ANALOG",
          { ..value, dimensions: [indices.length()], data: payload.to_bytes() },
          override_locked=true,
        )
      }
    }
  }
  result
}

///|
pub fn Document::rename_point(
  self : Document,
  index : Int,
  label : String,
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
  )
}

///|
pub fn Document::rename_analog(
  self : Document,
  index : Int,
  label : String,
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
  )
}

///|
pub fn Document::with_events(
  self : Document,
  events : Array[Event],
) -> Document raise C3dError {
  rebuild(
    self,
    self.frames.copy(),
    self.layout.point_labels,
    self.layout.point_descriptions,
    self.layout.analog_channels,
    self.layout.first_frame,
    events.copy(),
  )
}

///|
pub fn Document::convert_storage(
  self : Document,
  scale : Double,
  unsigned? : Bool = self.layout.analog_unsigned,
) -> Document raise C3dError {
  if !finite(scale) || scale == 0.0 {
    raise C3dError::Invalid("invalid target point scale")
  }
  let header = { ..self.header, scale: Float::from_double(scale).to_double() }
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
  let layout = resolve_layout(header, params)
  let result = { ..self, header, parameters: params, layout }
  validate_document(result)
  for frame in self.frames {
    let _ = encode_frame(frame, layout)
  }
  result
}

///|
pub fn Document::replace_frame(
  self : Document,
  index : Int,
  frame : Frame,
) -> Document raise C3dError {
  if index < 0 || index >= self.frames.length() {
    raise C3dError::Invalid("replacement frame index")
  }
  let frame = { ..frame, number: self.layout.first_frame + index }
  validate_frame(frame, self.layout)
  let frames = self.frames.copy()
  frames[index] = {
    ..frame,
    points: frame.points.copy(),
    analog: frame.analog.map(a => a.copy()),
  }
  { ..self, frames, }
}

///|
pub fn Document::select_points_by_label(
  self : Document,
  labels : Array[String],
) -> Document raise C3dError {
  let indices : Array[Int] = []
  for label in labels {
    let matches : Array[Int] = []
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
  self.select_points(indices)
}

///|
pub fn Document::select_analog_by_label(
  self : Document,
  labels : Array[String],
) -> Document raise C3dError {
  let indices : Array[Int] = []
  for label in labels {
    let matches : Array[Int] = []
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
  self.select_analog(indices)
}
