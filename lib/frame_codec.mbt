///|
pub fn decode_frame(
  data : Bytes,
  offset : Int,
  layout : Layout,
  index : Int,
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
      let x = f32(data, cursor)
      let y = f32(data, cursor + 4)
      let z = f32(data, cursor + 8)
      let packed = exact_int(
        f32(data, cursor + 12),
        -32768,
        32767,
        "point residual/mask word",
      )
      cursor = cursor + 16
      (x, y, z, packed)
    } else {
      let x = i16(data, cursor).to_double() * magnitude
      let y = i16(data, cursor + 2).to_double() * magnitude
      let z = i16(data, cursor + 4).to_double() * magnitude
      let packed = i16(data, cursor + 6)
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
        let value = f32(data, cursor)
        cursor = cursor + 4
        value
      } else {
        let value = if layout.analog_unsigned {
          u16(data, cursor)
        } else {
          i16(data, cursor)
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
        put_f32(out, if point.valid { value } else { 0.0 })
      }
      put_f32(out, packed.to_double())
    } else {
      for coordinate in [point.x, point.y, point.z] {
        put_i16(
          out,
          if point.valid {
            round_int(coordinate / magnitude, -32768, 32767, "coordinate")
          } else {
            0
          },
        )
      }
      put_i16(out, packed)
    }
  }
  for sample in 0..<layout.analog_subsamples {
    for channel_index in 0..<layout.analog_channels.length() {
      let channel = layout.analog_channels[channel_index]
      let physical = frame.analog[channel_index][sample]
      let raw = physical / (channel.scale * layout.analog_global_scale) +
        channel.offset
      if layout.float_storage {
        put_f32(out, raw)
      } else if layout.analog_unsigned {
        put_u16(out, round_int(raw, 0, 65535, "unsigned analog sample"))
      } else {
        put_i16(out, round_int(raw, -32768, 32767, "analog sample"))
      }
    }
  }
  if out.length() != layout.frame_bytes {
    raise C3dError::Invalid("encoded frame size differs from layout")
  }
  out.to_bytes()
}

///|
pub fn Layout::time_at(
  self : Layout,
  index : Int,
  subsample? : Int = 0,
) -> Double raise C3dError {
  if index < 0 || index >= self.frame_count {
    raise C3dError::Invalid("frame time index outside range")
  }
  if subsample < 0 ||
    (self.analog_subsamples == 0 && subsample != 0) ||
    (self.analog_subsamples > 0 && subsample >= self.analog_subsamples) {
    raise C3dError::Invalid("subsample time index outside range")
  }
  let start = (self.first_frame - 1 + index).to_double() / self.point_rate
  if subsample == 0 {
    start
  } else {
    start + subsample.to_double() / self.analog_rate
  }
}

///|
pub fn Layout::index_at(self : Layout, time : Double) -> Int raise C3dError {
  if !finite(time) {
    raise C3dError::Invalid("non-finite time")
  }
  let relative = time * self.point_rate - (self.first_frame - 1).to_double()
  let index = relative.floor()
  if index < 0.0 || index >= self.frame_count.to_double() {
    raise C3dError::Invalid("time outside trial")
  }
  index.to_int()
}

///|
pub fn Frame::camera_count(
  self : Frame,
  point_index : Int,
) -> Int raise C3dError {
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
