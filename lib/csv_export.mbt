///|
/// CSV fields follow RFC 4180 quoting; records use CRLF.
pub fn csv_field(text : String) -> String {
  let mut quoted = false
  for character in text.iter() {
    if character == ',' ||
      character == '"' ||
      character == '\r' ||
      character == '\n' {
      quoted = true
    }
  }
  if !quoted {
    return text
  }
  let output = StringBuilder::new()
  output.write_string("\"")
  for character in text.iter() {
    if character == '"' {
      output.write_string("\"\"")
    } else {
      output.write_char(character)
    }
  }
  output.write_string("\"")
  output.to_string()
}

///|
fn csv_row(fields : Array[String]) -> String {
  fields.map(csv_field).join(",") + "\r\n"
}

///|
priv struct CsvOutput {
  builder : StringBuilder
  mut size : Int
}

///|
fn CsvOutput::new() -> CsvOutput {
  { builder: StringBuilder::new(), size: 0 }
}

///|
fn CsvOutput::to_string(self : CsvOutput) -> String {
  self.builder.to_string()
}

///|
fn csv_append(
  output : CsvOutput,
  row : String,
  maximum : Int,
) -> Unit raise C3dError {
  let next = checked_add(
    output.size,
    utf8_bytes(row).length(),
    "CSV output size",
  )
  if next > maximum {
    raise C3dError::ResourceLimit("CSV output size")
  }
  output.builder.write_string(row)
  output.size = next
}

///|
/// Long-form point CSV retains validity, residual and camera mask.
pub fn points_csv(
  reader : Reader,
  maximum_bytes? : Int = 128 * 1024 * 1024,
) -> String raise C3dError {
  if maximum_bytes < 1 {
    raise C3dError::Invalid("CSV size limit")
  }
  let output = CsvOutput::new()
  csv_append(
    output,
    csv_row([
      "frame", "time", "index", "label", "unit", "valid", "x", "y", "z", "residual",
      "cameras",
    ]),
    maximum_bytes,
  )
  let layout = reader.layout()
  for i in 0..<layout.frame_count {
    let frame = reader.frame(i)
    let time = layout.time_at(i)
    for j in 0..<frame.points.length() {
      let point = frame.points[j]
      let fields = [
        frame.number.to_string(),
        time.to_string(),
        j.to_string(),
        layout.point_labels[j],
        layout.point_unit,
        point.valid.to_string(),
      ]
      if point.valid {
        fields.append([
          point.x.to_string(),
          point.y.to_string(),
          point.z.to_string(),
          point.residual.to_string(),
          point.cameras.to_string(),
        ])
      } else {
        fields.append(["", "", "", "", ""])
      }
      csv_append(output, csv_row(fields), maximum_bytes)
    }
  }
  let result = output.to_string()
  if utf8_bytes(result).length() > maximum_bytes {
    raise C3dError::ResourceLimit("CSV UTF-8 output size")
  }
  result
}

///|
/// Analog CSV uses calibrated physical values and the actual analog sample times.
pub fn analog_csv(
  reader : Reader,
  maximum_bytes? : Int = 128 * 1024 * 1024,
) -> String raise C3dError {
  if maximum_bytes < 1 {
    raise C3dError::Invalid("CSV size limit")
  }
  let output = CsvOutput::new()
  csv_append(
    output,
    csv_row(["frame", "subsample", "time", "index", "label", "unit", "value"]),
    maximum_bytes,
  )
  let layout = reader.layout()
  for i in 0..<layout.frame_count {
    let frame = reader.frame(i)
    for subsample in 0..<layout.analog_subsamples {
      let time = layout.time_at(i) + subsample.to_double() / layout.analog_rate
      for j in 0..<layout.analog_channels.length() {
        let channel = layout.analog_channels[j]
        csv_append(
          output,
          csv_row([
            frame.number.to_string(),
            subsample.to_string(),
            time.to_string(),
            j.to_string(),
            channel.label,
            channel.unit,
            frame.analog[j][subsample].to_string(),
          ]),
          maximum_bytes,
        )
      }
    }
  }
  let result = output.to_string()
  if utf8_bytes(result).length() > maximum_bytes {
    raise C3dError::ResourceLimit("CSV UTF-8 output size")
  }
  result
}

///|
pub fn events_csv(
  reader : Reader,
  maximum_bytes? : Int = 128 * 1024 * 1024,
) -> String raise C3dError {
  if maximum_bytes < 1 {
    raise C3dError::Invalid("CSV size limit")
  }
  let output = CsvOutput::new()
  csv_append(
    output,
    csv_row([
      "time", "label", "context", "description", "subject", "icon_id", "generic",
    ]),
    maximum_bytes,
  )
  for event in reader.events() {
    csv_append(
      output,
      csv_row([
        event.time.to_string(),
        event.label,
        event.context,
        event.description,
        event.subject,
        event.icon_id.to_string(),
        event.generic.to_string(),
      ]),
      maximum_bytes,
    )
  }
  let result = output.to_string()
  if utf8_bytes(result).length() > maximum_bytes {
    raise C3dError::ResourceLimit("CSV UTF-8 output size")
  }
  result
}
