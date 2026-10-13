///|
pub fn json_field(value : Json, key : String) -> Json raise C3dError {
  match value {
    Object(fields) =>
      match fields.get(key) {
        Some(field) => field
        None => raise C3dError::Invalid("missing JSON field: " + key)
      }
    _ => raise C3dError::Invalid("JSON object required")
  }
}

///|
pub fn json_optional(value : Json, key : String) -> Json? raise C3dError {
  match value {
    Object(fields) => fields.get(key)
    _ => raise C3dError::Invalid("JSON object required")
  }
}

///|
pub fn json_number(value : Json) -> Double raise C3dError {
  match value {
    Number(number, ..) =>
      if finite(number) {
        number
      } else {
        raise C3dError::Invalid("JSON number must be finite")
      }
    _ => raise C3dError::Invalid("JSON number required")
  }
}

///|
pub fn json_string(value : Json) -> String raise C3dError {
  match value {
    String(text) => text
    _ => raise C3dError::Invalid("JSON string required")
  }
}

///|
pub fn json_bool(value : Json) -> Bool raise C3dError {
  match value {
    True => true
    False => false
    _ => raise C3dError::Invalid("JSON boolean required")
  }
}

///|
pub fn json_array(value : Json) -> Array[Json] raise C3dError {
  match value {
    Array(items) => items
    _ => raise C3dError::Invalid("JSON array required")
  }
}

///|
fn number_or(
  value : Json,
  key : String,
  fallback : Double,
) -> Double raise C3dError {
  match json_optional(value, key) {
    None => fallback
    Some(item) => json_number(item)
  }
}

///|
fn string_or(
  value : Json,
  key : String,
  fallback : String,
) -> String raise C3dError {
  match json_optional(value, key) {
    None => fallback
    Some(item) => json_string(item)
  }
}

///|
fn bool_or(value : Json, key : String, fallback : Bool) -> Bool raise C3dError {
  match json_optional(value, key) {
    None => fallback
    Some(item) => json_bool(item)
  }
}

///|
fn ensure_keys(value : Json, allowed : Array[String]) -> Unit raise C3dError {
  match value {
    Object(fields) =>
      for key, _ in fields {
        if !allowed.contains(key) {
          raise C3dError::Invalid("unknown JSON field: " + key)
        }
      }
    _ => raise C3dError::Invalid("JSON object required")
  }
}

///|
pub fn marker_json(point : Marker) -> Json {
  {
    "x": point.x,
    "y": point.y,
    "z": point.z,
    "residual": point.residual,
    "cameras": point.cameras,
    "valid": point.valid,
  }
}

///|
pub fn event_json(event : Event) -> Json {
  {
    "time": event.time,
    "label": event.label,
    "context": event.context,
    "description": event.description,
    "subject": event.subject,
    "icon_id": event.icon_id,
    "generic": event.generic,
  }
}

///|
pub fn channel_json(channel : Channel) -> Json {
  {
    "label": channel.label,
    "description": channel.description,
    "unit": channel.unit,
    "scale": channel.scale,
    "offset": channel.offset,
  }
}

///|
pub fn parameters_json(parameters : Parameters) -> Json {
  {
    "groups": Json(
      parameters.groups.map(group => {
        (
          {
            "id": group.id,
            "name": group.name,
            "description_hex": hex_bytes(group.description),
            "locked": group.locked,
          } : Json)
      }),
    ),
    "values": Json(
      parameters.values.map(value => {
        (
          {
            "group_id": value.group_id,
            "name": value.name,
            "data_type": value.data_type,
            "dimensions": Json(value.dimensions),
            "data_hex": hex_bytes(value.data),
            "description_hex": hex_bytes(value.description),
            "locked": value.locked,
          } : Json)
      }),
    ),
  }
}

///|
pub fn frame_json(frame : Frame) -> Json {
  {
    "number": frame.number,
    "points": Json(frame.points.map(marker_json)),
    "analog": Json(frame.analog),
  }
}

///|
pub fn document_json(document : Document) -> Json {
  {
    "format": "MoonC3D/1",
    "point_labels": Json(document.layout.point_labels),
    "point_descriptions": Json(document.layout.point_descriptions),
    "point_unit": document.layout.point_unit,
    "point_rate": document.layout.point_rate,
    "scale": document.layout.point_scale,
    "first_frame": document.layout.first_frame,
    "analog_subsamples": document.layout.analog_subsamples,
    "analog_global_scale": document.layout.analog_global_scale,
    "analog_unsigned": document.layout.analog_unsigned,
    "analog_channels": Json(document.layout.analog_channels.map(channel_json)),
    "frames": Json(document.frames.map(frame_json)),
    "events": Json(document.events.map(event_json)),
    "parameters": parameters_json(document.parameters),
  }
}

///|
pub fn parse_parameters_json(
  value : Json,
  limits~ : Limits = Limits::default(),
) -> Parameters raise C3dError {
  ensure_keys(value, ["groups", "values"])
  let group_values = json_array(json_field(value, "groups"))
  let parameter_values = json_array(json_field(value, "values"))
  if group_values.length() > 127 ||
    parameter_values.length() > limits.max_parameters {
    raise C3dError::ResourceLimit("JSON metadata record count")
  }
  let groups : Array[Group] = []
  for group in group_values {
    ensure_keys(group, ["id", "name", "description_hex", "locked"])
    groups.push({
      id: exact_int(json_number(json_field(group, "id")), 1, 127, "group ID"),
      name: normalize_name(json_string(json_field(group, "name"))),
      description: parse_hex(
        string_or(group, "description_hex", ""),
        max_bytes=255,
      ),
      locked: bool_or(group, "locked", false),
    })
  }
  let values : Array[Parameter] = []
  for parameter in parameter_values {
    ensure_keys(parameter, [
      "group_id", "name", "data_type", "dimensions", "data_hex", "description_hex",
      "locked",
    ])
    let dimensions_json = json_array(json_field(parameter, "dimensions"))
    if dimensions_json.length() > 7 {
      raise C3dError::Invalid("JSON parameter rank")
    }
    let dimensions = dimensions_json.map(item => {
      exact_int(json_number(item), 0, 255, "parameter dimension")
    })
    values.push({
      group_id: exact_int(
        json_number(json_field(parameter, "group_id")),
        1,
        127,
        "group ID",
      ),
      name: normalize_name(json_string(json_field(parameter, "name"))),
      data_type: exact_int(
        json_number(json_field(parameter, "data_type")),
        -1,
        4,
        "parameter type",
      ),
      dimensions,
      data: parse_hex(
        json_string(json_field(parameter, "data_hex")),
        max_bytes=limits.max_parameter_bytes,
      ),
      description: parse_hex(
        string_or(parameter, "description_hex", ""),
        max_bytes=255,
      ),
      locked: bool_or(parameter, "locked", false),
    })
  }
  let result = { groups, values, }
  validate_parameters(result, limits~)
  result
}

///|
pub fn parse_marker_json(value : Json) -> Marker raise C3dError {
  ensure_keys(value, ["x", "y", "z", "residual", "cameras", "valid"])
  let valid = bool_or(value, "valid", true)
  {
    x: json_number(json_field(value, "x")),
    y: json_number(json_field(value, "y")),
    z: json_number(json_field(value, "z")),
    residual: number_or(value, "residual", if valid { 0.0 } else { -1.0 }),
    cameras: exact_int(number_or(value, "cameras", 0.0), 0, 127, "camera mask"),
    valid,
  }
}

///|
pub fn parse_event_json(value : Json) -> Event raise C3dError {
  ensure_keys(value, [
    "time", "label", "context", "description", "subject", "icon_id", "generic",
  ])
  {
    time: json_number(json_field(value, "time")),
    label: json_string(json_field(value, "label")),
    context: string_or(value, "context", ""),
    description: string_or(value, "description", ""),
    subject: string_or(value, "subject", ""),
    icon_id: exact_int(
      number_or(value, "icon_id", 0.0),
      0,
      32767,
      "event icon ID",
    ),
    generic: bool_or(value, "generic", false),
  }
}

///|
pub fn parse_channel_json(value : Json) -> Channel raise C3dError {
  ensure_keys(value, ["label", "description", "unit", "scale", "offset"])
  {
    label: json_string(json_field(value, "label")),
    description: string_or(value, "description", ""),
    unit: string_or(value, "unit", ""),
    scale: number_or(value, "scale", 1.0),
    offset: number_or(value, "offset", 0.0),
  }
}

///|
pub fn parse_document_json(
  value : Json,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  validate_limits(limits)
  ensure_keys(value, [
    "format", "point_labels", "point_descriptions", "point_unit", "point_rate", "scale",
    "first_frame", "analog_subsamples", "analog_global_scale", "analog_unsigned",
    "analog_channels", "frames", "events", "parameters",
  ])
  if string_or(value, "format", "MoonC3D/1") != "MoonC3D/1" {
    raise C3dError::Unsupported("unknown interchange format")
  }
  let label_values = json_array(json_field(value, "point_labels"))
  if label_values.length() > limits.max_points {
    raise C3dError::ResourceLimit("JSON point count")
  }
  let labels = label_values.map(json_string)
  let channel_values = json_array(json_field(value, "analog_channels"))
  if channel_values.length() > limits.max_analog_channels {
    raise C3dError::ResourceLimit("JSON analog count")
  }
  let channels = channel_values.map(parse_channel_json)
  let frame_values = json_array(json_field(value, "frames"))
  if frame_values.length() > limits.max_frames {
    raise C3dError::ResourceLimit("JSON frame count")
  }
  let subsamples = exact_int(
    number_or(value, "analog_subsamples", 0.0),
    0,
    limits.max_subsamples,
    "analog subsamples",
  )
  let per_frame = checked_add(
    checked_mul(labels.length(), 4, "JSON points"),
    checked_mul(channels.length(), subsamples, "JSON analog values"),
    "JSON frame size",
  )
  if checked_mul(per_frame, frame_values.length(), "JSON samples") >
    limits.max_total_values {
    raise C3dError::ResourceLimit("JSON sample count")
  }
  let first = exact_int(
    number_or(value, "first_frame", 1.0),
    1,
    2147483647,
    "first frame",
  )
  let frames : Array[Frame] = []
  for i in 0..<frame_values.length() {
    let frame = frame_values[i]
    ensure_keys(frame, ["number", "points", "analog"])
    let expected_number = checked_add(first, i, "JSON frame number")
    match json_optional(frame, "number") {
      None => ()
      Some(raw) => {
        let supplied = exact_int(
          json_number(raw),
          1,
          2147483647,
          "JSON frame number",
        )
        if supplied != expected_number {
          raise C3dError::Invalid(
            "JSON frame numbers must follow first_frame consecutively",
          )
        }
      }
    }
    let point_values = json_array(json_field(frame, "points"))
    let analog_values = json_array(json_field(frame, "analog"))
    if point_values.length() != labels.length() ||
      analog_values.length() != channels.length() {
      raise C3dError::Invalid("JSON frame channel count mismatch")
    }
    let analog : Array[Array[Double]] = []
    for channel in analog_values {
      let samples = json_array(channel)
      if samples.length() != subsamples {
        raise C3dError::Invalid("JSON analog subsample count mismatch")
      }
      analog.push(samples.map(json_number))
    }
    frames.push({
      number: i + 1,
      points: point_values.map(parse_marker_json),
      analog,
    })
  }
  let base = Document::new(
    labels,
    channels,
    frames,
    point_rate=number_or(value, "point_rate", 100.0),
    scale=number_or(value, "scale", -0.01),
    analog_subsamples=subsamples,
    analog_global_scale=number_or(value, "analog_global_scale", 1.0),
    analog_unsigned=bool_or(value, "analog_unsigned", false),
    point_unit=string_or(value, "point_unit", "mm"),
  )
  let parameters = match json_optional(value, "parameters") {
    None => base.parameters
    Some(raw) => parse_parameters_json(raw, limits~)
  }
  let events = match json_optional(value, "events") {
    None => []
    Some(raw) => {
      let values = json_array(raw)
      if values.length() > 255 {
        raise C3dError::ResourceLimit("JSON events")
      }
      values.map(parse_event_json)
    }
  }
  let descriptions = match json_optional(value, "point_descriptions") {
    None => base.layout.point_descriptions
    Some(raw) => {
      let values = json_array(raw)
      if values.length() != labels.length() {
        raise C3dError::Invalid("point description count")
      }
      values.map(json_string)
    }
  }
  let numbered = frames.map(frame => {
    ..frame,
    number: checked_add(first, frame.number - 1, "frame number"),
  })
  rebuild(
    { ..base, parameters, },
    numbered,
    labels,
    descriptions,
    channels,
    first,
    events,
  )
}

///|
pub fn import_json(
  text : String,
  limits~ : Limits = Limits::default(),
) -> Document raise C3dError {
  if text.length() > limits.max_file_bytes {
    raise C3dError::ResourceLimit("JSON input size")
  }
  check_json_nesting(text, 64)
  let parsed = @json.parse(text[:]) catch {
    _ => raise C3dError::Invalid("invalid JSON syntax or nesting")
  }
  parse_document_json(parsed, limits~)
}

///|
pub fn check_json_nesting(
  text : String,
  maximum : Int32,
) -> Unit raise C3dError {
  if maximum < 1 {
    raise C3dError::Invalid("invalid JSON depth limit")
  }
  let mut depth = 0
  let mut quoted = false
  let mut escaped = false
  for character in text.iter() {
    let code = character.to_int()
    if quoted {
      if escaped {
        escaped = false
      } else if code == 92 {
        escaped = true
      } else if code == 34 {
        quoted = false
      }
    } else if code == 34 {
      quoted = true
    } else if code == 123 || code == 91 {
      depth = depth + 1
      if depth > maximum {
        raise C3dError::ResourceLimit("JSON nesting depth")
      }
    } else if code == 125 || code == 93 {
      depth = depth - 1
      if depth < 0 {
        raise C3dError::Invalid("unbalanced JSON brackets")
      }
    }
  }
  if quoted || depth != 0 {
    raise C3dError::Invalid("unterminated JSON text")
  }
}
