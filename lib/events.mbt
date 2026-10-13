///|
pub fn read_events(
  header : Header,
  parameters : Parameters,
) -> Array[Event] raise C3dError {
  match parameters.get("EVENT", "USED") {
    None => read_header_events(header)
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
      let icons = event_ints(parameters, "ICON_IDS", count)
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
  count : Int,
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
  count : Int,
) -> Array[Int] raise C3dError {
  match parameters.get("EVENT", name) {
    None => Array::make(count, 0)
    Some(value) => {
      let values = value.int_values(unsigned=true)
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
  let count = u16(header.reserved, 276)
  if count > 18 {
    raise C3dError::Invalid("legacy header contains more than 18 events")
  }
  if count == 0 {
    return []
  }
  if u16(header.reserved, 274) != 12345 {
    raise C3dError::Unsupported("legacy two-character header event labels")
  }
  let events : Array[Event] = []
  for i in 0..<count {
    let time = f32(header.reserved, 280 + i * 4)
    if !finite(time) || time < 0.0 {
      raise C3dError::Invalid("invalid legacy event time")
    }
    let raw = header.reserved[372 + i * 4:376 + i * 4].to_owned()
    let mut length = raw.length()
    while length > 0 && (raw[length - 1] == 32 || raw[length - 1] == 0) {
      length = length - 1
    }
    events.push(Event::new(time, utf8_text(raw[0:length].to_owned())))
  }
  events
}

///|
pub fn write_event_parameters(
  parameters : Parameters,
  events : Array[Event],
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
    return result
  }
  let times : Array[Double] = []
  let icons : Array[Int] = []
  let flags : Array[Int] = []
  for event in events {
    if !finite(event.time) || event.time < 0.0 {
      raise C3dError::Invalid("event time must be finite and nonnegative")
    }
    if event.icon_id < 0 || event.icon_id > 32767 {
      raise C3dError::Invalid("event icon ID outside supported range")
    }
    let minutes = (event.time / 60.0).floor()
    times.push(minutes)
    times.push(event.time - minutes * 60.0)
    icons.push(event.icon_id)
    flags.push(if event.generic { 1 } else { 0 })
  }
  result = result.set(
    "EVENT",
    Parameter::reals("TIMES", times, dimensions=[2, events.length()]),
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
  result.put_ints("EVENT", "GENERIC_FLAGS", flags, override_locked=true)
}
