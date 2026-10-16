///|
pub fn decode_frame(
  data : Bytes,
  offset : Int32,
  layout : Layout,
  index : Int32,
) -> Frame raise C3dError {
  if index < 0 || index >= layout.frame_count {
    raise C3dError::Invalid("frame index outside layout")
  }
  check_range(data, offset, layout.frame_bytes)
  let points : Array[Marker] = []
  let mut cursor = offset
  let magnitude = layout.point_scale.abs()
  for _ in 0..<layout.point_count {
    let (x, y, z, packed) = if layout.float_storage {
      let x = encoded_f32(data, cursor, layout.processor)
      let y = encoded_f32(data, cursor + 4, layout.processor)
      let z = encoded_f32(data, cursor + 8, layout.processor)
      let packed = exact_int(
        encoded_f32(data, cursor + 12, layout.processor),
        -32768,
        32767,
        "point residual/mask word",
      )
      cursor = cursor + 16
      (x, y, z, packed)
    } else {
      let x = encoded_i16(data, cursor, layout.processor).to_double() *
        magnitude
      let y = encoded_i16(data, cursor + 2, layout.processor).to_double() *
        magnitude
      let z = encoded_i16(data, cursor + 4, layout.processor).to_double() *
        magnitude
      let packed = encoded_i16(data, cursor + 6, layout.processor)
      cursor = cursor + 8
      (x, y, z, packed)
    }
    let valid = packed >= 0 && finite(x) && finite(y) && finite(z)
    points.push({
      x: if finite(x) {
        x
      } else {
        0.0
      },
      y: if finite(y) {
        y
      } else {
        0.0
      },
      z: if finite(z) {
        z
      } else {
        0.0
      },
      valid,
      residual: if valid {
        (packed & 255).to_double() * magnitude
      } else {
        -1.0
      },
      cameras: if valid {
        (packed >> 8) & 127
      } else {
        0
      },
    })
  }
  let channels = layout.analog_channels.length()
  let analog : Array[Array[Double]] = Array::makei(channels, _ => [])
  for _ in 0..<layout.analog_subsamples {
    for channel_index in 0..<channels {
      let raw = if layout.float_storage {
        let value = encoded_f32(data, cursor, layout.processor)
        cursor = cursor + 4
        value
      } else {
        let value = if layout.analog_unsigned {
          encoded_u16(data, cursor, layout.processor)
        } else {
          encoded_i16(data, cursor, layout.processor)
        }
        cursor = cursor + 2
        value.to_double()
      }
      let channel = layout.analog_channels[channel_index]
      let physical = (raw - channel.offset) *
        channel.scale *
        layout.analog_global_scale
      if !finite(physical) {
        raise C3dError::Invalid("non-finite analog sample")
      }
      analog[channel_index].push(physical)
    }
  }
  if cursor != offset + layout.frame_bytes {
    raise C3dError::Invalid("frame layout consumed unexpected byte count")
  }
  {
    number: checked_add(layout.first_frame, index, "frame number"),
    points,
    analog,
  }
}

///|
pub fn validate_frame(frame : Frame, layout : Layout) -> Unit raise C3dError {
  if frame.points.length() != layout.point_count {
    raise C3dError::Invalid("frame marker count differs from layout")
  }
  if frame.analog.length() != layout.analog_channels.length() {
    raise C3dError::Invalid("frame analog channel count differs from layout")
  }
  for point in frame.points {
    if !finite(point.x) ||
      !finite(point.y) ||
      !finite(point.z) ||
      !finite(point.residual) {
      raise C3dError::Invalid("non-finite marker data")
    }
    if point.cameras < 0 || point.cameras > 127 {
      raise C3dError::Invalid("camera mask outside seven bits")
    }
    if point.valid && point.residual < 0.0 {
      raise C3dError::Invalid("valid point has negative residual")
    }
    if point.valid {
      let _ = round_int(
        point.residual / layout.point_scale.abs(),
        0,
        255,
        "point residual",
      )
      if !layout.float_storage {
        for coordinate in [point.x, point.y, point.z] {
          let _ = round_int(
            coordinate / layout.point_scale.abs(),
            -32768,
            32767,
            "point coordinate",
          )
        }
      }
    }
  }
  for channel in frame.analog {
    if channel.length() != layout.analog_subsamples {
      raise C3dError::Invalid("analog subsample count differs from layout")
    }
    for value in channel {
      if !finite(value) {
        raise C3dError::Invalid("non-finite analog value")
      }
    }
  }
}

///|
pub fn encode_frame(frame : Frame, layout : Layout) -> Bytes raise C3dError {
  validate_frame(frame, layout)
  let out = @buffer.Buffer::Buffer()
  let magnitude = layout.point_scale.abs()
  for point in frame.points {
    let packed = if point.valid {
      round_int(point.residual / magnitude, 0, 255, "residual") |
      (point.cameras << 8)
    } else {
      -1
    }
    if layout.float_storage {
      for value in [point.x, point.y, point.z] {
        put_encoded_f32(
          out,
          if point.valid {
            value
          } else {
            0.0
          },
          layout.processor,
        )
      }
      put_encoded_f32(out, packed.to_double(), layout.processor)
    } else {
      for coordinate in [point.x, point.y, point.z] {
        put_encoded_i16(
          out,
          if point.valid {
            round_int(coordinate / magnitude, -32768, 32767, "coordinate")
          } else {
            0
          },
          layout.processor,
        )
      }
      put_encoded_i16(out, packed, layout.processor)
    }
  }
  for sample in 0..<layout.analog_subsamples {
    for channel_index in 0..<layout.analog_channels.length() {
      let channel = layout.analog_channels[channel_index]
      let physical = frame.analog[channel_index][sample]
      let raw = physical / (channel.scale * layout.analog_global_scale) +
        channel.offset
      if layout.float_storage {
        put_encoded_f32(out, raw, layout.processor)
      } else if layout.analog_unsigned {
        put_encoded_u16(
          out,
          round_int(raw, 0, 65535, "unsigned analog sample"),
          layout.processor,
        )
      } else {
        put_encoded_i16(
          out,
          round_int(raw, -32768, 32767, "analog sample"),
          layout.processor,
        )
      }
    }
  }
  if out.length() != layout.frame_bytes {
    raise C3dError::Invalid("encoded frame size differs from layout")
  }
  out.to_bytes()
}

///|
// Index frame_count is the exclusive trial endpoint, also used by time crops.
// Convert before adding so a valid last frame at Int32::max_value has a valid
// floating-point exclusive endpoint as well.
fn frame_time_boundary(layout : Layout, index : Int32) -> Double raise C3dError {
  if index < 0 || index > layout.frame_count {
    raise C3dError::Invalid("frame time boundary outside range")
  }
  if !finite(layout.point_rate) || layout.point_rate <= 0.0 {
    raise C3dError::Invalid("invalid point rate for frame time")
  }
  (layout.first_frame.to_double() - 1.0 + index.to_double()) / layout.point_rate
}

///|
// Search the same rounded frame timestamps returned by time_at rather than
// inverting their floating-point division with multiplication and ceil/floor.
fn frame_time_lower_bound(
  layout : Layout,
  time : Double,
) -> Int32 raise C3dError {
  let mut low = 0
  let mut high = layout.frame_count
  while low < high {
    let middle = low + (high - low) / 2
    if frame_time_boundary(layout, middle) < time {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
fn frame_time_upper_bound(
  layout : Layout,
  time : Double,
) -> Int32 raise C3dError {
  let mut low = 0
  let mut high = layout.frame_count
  while low < high {
    let middle = low + (high - low) / 2
    if frame_time_boundary(layout, middle) <= time {
      low = middle + 1
    } else {
      high = middle
    }
  }
  low
}

///|
pub fn Layout::time_at(
  self : Layout,
  index : Int32,
  subsample~ : Int32 = 0,
) -> Double raise C3dError {
  if index < 0 || index >= self.frame_count {
    raise C3dError::Invalid("frame time index outside range")
  }
  if subsample < 0 ||
    (self.analog_subsamples == 0 && subsample != 0) ||
    (self.analog_subsamples > 0 && subsample >= self.analog_subsamples) {
    raise C3dError::Invalid("subsample time index outside range")
  }
  let start = frame_time_boundary(self, index)
  if subsample == 0 {
    start
  } else {
    start + subsample.to_double() / self.analog_rate
  }
}

///|
pub fn Layout::index_at(self : Layout, time : Double) -> Int32 raise C3dError {
  if !finite(time) {
    raise C3dError::Invalid("non-finite time")
  }
  if time < frame_time_boundary(self, 0) ||
    time >= frame_time_boundary(self, self.frame_count) {
    raise C3dError::Invalid("time outside trial")
  }
  frame_time_upper_bound(self, time) - 1
}

///|
pub fn Frame::camera_count(
  self : Frame,
  point_index : Int32,
) -> Int32 raise C3dError {
  if point_index < 0 || point_index >= self.points.length() {
    raise C3dError::Invalid("marker index outside frame")
  }
  let mask = self.points[point_index].cameras
  let mut count = 0
  for bit in 0..<7 {
    if (mask & (1 << bit)) != 0 {
      count = count + 1
    }
  }
  count
}
