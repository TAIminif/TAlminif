///|
// Account without allocating a second UTF-8 copy of attacker-controlled text.
fn add_utf8_text_bytes(
  used : Int32,
  text : String,
  maximum : Int32,
  context : String,
) -> Int32 raise C3dError {
  if text.length() > maximum - used {
    raise C3dError::ResourceLimit(context)
  }
  let mut total = used
  for character in text.iter() {
    let code = character.to_int()
    let size = if code < 128 {
      1
    } else if code < 2048 {
      2
    } else if code < 65536 {
      3
    } else {
      4
    }
    if size > maximum - total {
      raise C3dError::ResourceLimit(context)
    }
    total = total + size
  }
  total
}

///|
fn add_raw_text_bytes(
  used : Int32,
  size : Int32,
  maximum : Int32,
) -> Int32 raise C3dError {
  if size > maximum - used {
    raise C3dError::ResourceLimit("aggregate parameter text")
  }
  used + size
}

///|
/// Bound decoded text separately from its padded parameter representation.
pub fn validate_semantic_text(
  layout : Layout,
  events : Array[Event],
  limits : Limits,
) -> Unit raise C3dError {
  validate_limits(limits)
  let mut bytes = 0
  for text in layout.point_labels {
    bytes = add_utf8_text_bytes(
      bytes,
      text,
      limits.max_text_bytes,
      "semantic text",
    )
  }
  for text in layout.point_descriptions {
    bytes = add_utf8_text_bytes(
      bytes,
      text,
      limits.max_text_bytes,
      "semantic text",
    )
  }
  bytes = add_utf8_text_bytes(
    bytes,
    layout.point_unit,
    limits.max_text_bytes,
    "semantic text",
  )
  for channel in layout.analog_channels {
    for text in [channel.label, channel.description, channel.unit] {
      bytes = add_utf8_text_bytes(
        bytes,
        text,
        limits.max_text_bytes,
        "semantic text",
      )
    }
  }
  for event in events {
    for text in [event.label, event.context, event.description, event.subject] {
      bytes = add_utf8_text_bytes(
        bytes,
        text,
        limits.max_text_bytes,
        "semantic text",
      )
    }
  }
}
