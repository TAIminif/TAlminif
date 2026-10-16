///|
pub fn read_events(
  header : Header,
  parameters : Parameters,
) -> Array[Event] raise C3dError {
  let events = read_parameter_events(parameters)
  let first = trial_frame(parameters, "ACTUAL_START_FIELD").unwrap_or(1)
  if first < 1 || !finite(header.point_rate) || header.point_rate <= 0.0 {
    raise C3dError::Invalid("invalid trial origin for header events")
  }
  let origin = (first - 1).to_double() / header.point_rate
  // The two stores are independent. Modern entries retain their context and
  // other metadata; identical header time/label copies add no new semantics.
  // Header seconds are relative to this file's first sample, whereas the
  // library's logical event axis follows original trial frame one.
  for raw in read_header_events(header) {
    let time = origin + raw.time
    if !finite(time) {
      raise C3dError::Invalid("header event trial time overflows")
    }
    let legacy = { ..raw, time, }
    let mut duplicate = false
    for event in events {
      if event.time == legacy.time && event.label == legacy.label {
        duplicate = true
        break
      }
    }
    if !duplicate {
      events.push(legacy)
    }
  }
  events
}

///|
fn read_parameter_events(
  parameters : Parameters,
) -> Array[Event] raise C3dError {
  match parameters.get("EVENT", "USED") {
    None => []
    Some(used) => {
      let count = exact_int(used.number(unsigned=true), 0, 255, "EVENT:USED")
      if count == 0 {
        return []
      }
      let times = parameters.require("EVENT", "TIMES")
      if times.data_type != 4 || times.dimensions != [2, count] {
        raise C3dError::Invalid("EVENT:TIMES must have shape [2,events]")
      }
      let values = times.real_values()
      let labels = event_texts(parameters, "LABELS", count)
      let contexts = event_texts(parameters, "CONTEXTS", count)
      let descriptions = event_texts(parameters, "DESCRIPTIONS", count)
      let subjects = event_texts(parameters, "SUBJECTS", count)
      let icons = event_ints(parameters, "ICON_IDS", count, unsigned=false)
      let flags = event_ints(parameters, "GENERIC_FLAGS", count)
      let events : Array[Event] = []
      for i in 0..<count {
        let minutes = values[2 * i]
        let seconds = values[2 * i + 1]
        if minutes < 0.0 ||
          seconds < 0.0 ||
          seconds >= 60.0 ||
          minutes.floor() != minutes {
          raise C3dError::Invalid("invalid EVENT minutes/seconds pair")
        }
        let time = minutes * 60.0 + seconds
        if !finite(time) {
          raise C3dError::Invalid("non-finite event time")
        }
        events.push({
          time,
          label: labels[i],
          context: contexts[i],
          description: descriptions[i],
          subject: subjects[i],
          icon_id: icons[i],
          generic: flags[i] != 0,
        })
      }
      events
    }
  }
}

///|
fn event_texts(
  parameters : Parameters,
  name : String,
  count : Int32,
) -> Array[String] raise C3dError {
  match parameters.get("EVENT", name) {
    None => Array::make(count, "")
    Some(value) => {
      let texts = value.text_values()
      if texts.length() != count {
        raise C3dError::Invalid("EVENT text array length mismatch")
      }
      texts
    }
  }
}

///|
fn event_ints(
  parameters : Parameters,
  name : String,
  count : Int32,
  unsigned~ : Bool = true,
) -> Array[Int32] raise C3dError {
  match parameters.get("EVENT", name) {
    None => Array::make(count, 0)
    Some(value) => {
      let values = value.int_values(unsigned~)
      if values.length() != count {
        raise C3dError::Invalid("EVENT integer array length mismatch")
      }
      values
    }
  }
}

///|
pub fn read_header_events(header : Header) -> Array[Event] raise C3dError {
  if header.reserved.length() != 488 {
    raise C3dError::Invalid("invalid header event area")
  }
  let count = encoded_u16(header.reserved, 276, header.processor)
  if count > 18 {
    raise C3dError::Invalid("legacy header contains more than 18 events")
  }
  if count == 0 {
    return []
  }
  let label_width = if encoded_u16(header.reserved, 274, header.processor) ==
    12345 {
    4
  } else {
    2
  }
  let events : Array[Event] = []
  for i in 0..<count {
    let time = encoded_f32(header.reserved, 280 + i * 4, header.processor)
    if !finite(time) || time < 0.0 {
      raise C3dError::Invalid("invalid legacy event time")
    }
    let label_start = 372 + i * label_width
    let raw = header.reserved[label_start:label_start + label_width].to_owned()
    let mut length = raw.length()
    while length > 0 && (raw[length - 1] == 32 || raw[length - 1] == 0) {
      length = length - 1
    }
    // Display flags are application hints; OFF does not invalidate an event.
    events.push(Event::new(time, ascii(raw[0:length].to_owned())))
  }
  events
}

///|
pub fn write_event_parameters(
  parameters : Parameters,
  events : Array[Event],
  processor~ : Processor = Intel,
) -> Parameters raise C3dError {
  if events.length() > 255 {
    raise C3dError::ResourceLimit("EVENT arrays support at most 255 events")
  }
  let mut result = parameters
  let names = [
    "USED", "TIMES", "LABELS", "CONTEXTS", "DESCRIPTIONS", "SUBJECTS", "ICON_IDS",
    "GENERIC_FLAGS",
  ]
  for name in names {
    result = result.remove("EVENT", name, override_locked=true)
  }
  result = result.put_int(
    "EVENT",
    "USED",
    events.length(),
    override_locked=true,
  )
  if events.is_empty() {
    return retain_parameter_metadata(result, parameters)
  }
  let times : Array[Double] = []
  let icons : Array[Int32] = []
  let flags : Array[Int32] = []
  for event in events {
    if !finite(event.time) || event.time < 0.0 {
      raise C3dError::Invalid("event time must be finite and nonnegative")
    }
    if event.icon_id < -32768 || event.icon_id > 32767 {
      raise C3dError::Invalid("event icon ID outside supported range")
    }
    let mut minutes = (event.time / 60.0).floor()
    let mut seconds = quantize_f32(event.time - minutes * 60.0, processor)
    // Rounding 59.999999... to REAL*4 can otherwise create an invalid pair.
    if seconds >= 60.0 {
      minutes = minutes + 1.0
      seconds = 0.0
    }
    times.push(minutes)
    times.push(seconds)
    icons.push(event.icon_id)
    flags.push(if event.generic { 1 } else { 0 })
  }
  result = result.set(
    "EVENT",
    Parameter::reals(
      "TIMES",
      times,
      dimensions=[2, events.length()],
      processor~,
    ),
    override_locked=true,
  )
  result = result.put_texts(
    "EVENT",
    "LABELS",
    events.map(e => e.label),
    override_locked=true,
  )
  result = result.put_texts(
    "EVENT",
    "CONTEXTS",
    events.map(e => e.context),
    override_locked=true,
  )
  result = result.put_texts(
    "EVENT",
    "DESCRIPTIONS",
    events.map(e => e.description),
    override_locked=true,
  )
  result = result.put_texts(
    "EVENT",
    "SUBJECTS",
    events.map(e => e.subject),
    override_locked=true,
  )
  result = result.put_ints("EVENT", "ICON_IDS", icons, override_locked=true)
  let result = result.put_ints(
    "EVENT",
    "GENERIC_FLAGS",
    flags,
    override_locked=true,
  )
  retain_parameter_metadata(result, parameters)
}
