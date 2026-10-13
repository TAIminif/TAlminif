///|
pub(all) struct Distribution {
  count : Int32
  minimum : Double
  maximum : Double
  mean : Double
  variance : Double
  rms : Double
} derive(Debug, Eq)

///|
pub struct Moments {
  mut count : Int32
  mut minimum : Double
  mut maximum : Double
  mut mean : Double
  mut m2 : Double
  mut sum_squares : Double
}

///|
pub fn Moments::new() -> Moments {
  {
    count: 0,
    minimum: 0.0,
    maximum: 0.0,
    mean: 0.0,
    m2: 0.0,
    sum_squares: 0.0,
  }
}

///|
pub fn Moments::add(self : Moments, value : Double) -> Unit raise C3dError {
  if !finite(value) {
    raise C3dError::Invalid("statistics require finite samples")
  }
  if self.count == 2147483647 {
    raise C3dError::ResourceLimit("statistics sample count")
  }
  let next_count = self.count + 1
  let delta = value - self.mean
  let next_mean = self.mean + delta / next_count.to_double()
  let next_m2 = self.m2 + delta * (value - next_mean)
  let squares = self.sum_squares + value * value
  if !finite(next_mean) || !finite(next_m2) || !finite(squares) {
    raise C3dError::ResourceLimit("statistics numerical overflow")
  }
  if self.count == 0 {
    self.minimum = value
    self.maximum = value
  } else {
    self.minimum = self.minimum.min(value)
    self.maximum = self.maximum.max(value)
  }
  self.count = next_count
  self.mean = next_mean
  self.m2 = next_m2
  self.sum_squares = squares
}

///|
pub fn Moments::finish(self : Moments) -> Distribution {
  {
    count: self.count,
    minimum: self.minimum,
    maximum: self.maximum,
    mean: self.mean,
    variance: if self.count < 2 {
      0.0
    } else {
      (self.m2 / (self.count - 1).to_double()).max(0.0)
    },
    rms: if self.count == 0 {
      0.0
    } else {
      (self.sum_squares / self.count.to_double()).sqrt()
    },
  }
}

///|
pub(all) struct MarkerSummary {
  label : String
  valid_samples : Int32
  missing_samples : Int32
  longest_missing_run : Int32
  x : Distribution
  y : Distribution
  z : Distribution
  residual : Distribution
} derive(Debug, Eq)

///|
pub(all) struct AnalogSummary {
  label : String
  unit : String
  samples : Distribution
} derive(Debug, Eq)

///|
pub(all) struct TrialSummary {
  frames : Int32
  point_rate : Double
  analog_rate : Double
  first_frame : Int32
  duration : Double
  markers : Array[MarkerSummary]
  analog : Array[AnalogSummary]
} derive(Debug, Eq)

///|
struct MarkerMoments {
  x : Moments
  y : Moments
  z : Moments
  residual : Moments
  mut missing : Int32
  mut current_gap : Int32
  mut longest_gap : Int32
}

///|
pub struct Analyzer {
  layout : Layout
  markers : Array[MarkerMoments]
  analog : Array[Moments]
  mut frames : Int32
}

///|
pub fn Analyzer::new(layout : Layout) -> Analyzer {
  {
    layout,
    frames: 0,
    markers: Array::makei(layout.point_count, _ => {
      x: Moments::new(),
      y: Moments::new(),
      z: Moments::new(),
      residual: Moments::new(),
      missing: 0,
      current_gap: 0,
      longest_gap: 0,
    }),
    analog: Array::makei(layout.analog_channels.length(), _ => Moments::new()),
  }
}

///|
pub fn Analyzer::add(self : Analyzer, frame : Frame) -> Unit raise C3dError {
  validate_frame(frame, self.layout)
  if self.frames >= self.layout.frame_count ||
    frame.number != self.layout.first_frame + self.frames {
    raise C3dError::Invalid(
      "analysis requires sequential frames from the trial start",
    )
  }
  for i in 0..<self.markers.length() {
    let source = frame.points[i]
    let target = self.markers[i]
    if source.valid {
      target.x.add(source.x)
      target.y.add(source.y)
      target.z.add(source.z)
      target.residual.add(source.residual)
      target.current_gap = 0
    } else {
      target.missing = target.missing + 1
      target.current_gap = target.current_gap + 1
      target.longest_gap = target.longest_gap.max(target.current_gap)
    }
  }
  for channel in 0..<self.analog.length() {
    for sample in frame.analog[channel] {
      self.analog[channel].add(sample)
    }
  }
  self.frames = self.frames + 1
}

///|
pub fn Analyzer::finish(self : Analyzer) -> TrialSummary {
  let markers : Array[MarkerSummary] = []
  for i in 0..<self.markers.length() {
    let source = self.markers[i]
    markers.push({
      label: self.layout.point_labels[i],
      valid_samples: source.x.count,
      missing_samples: source.missing,
      longest_missing_run: source.longest_gap,
      x: source.x.finish(),
      y: source.y.finish(),
      z: source.z.finish(),
      residual: source.residual.finish(),
    })
  }
  let analog : Array[AnalogSummary] = []
  for i in 0..<self.analog.length() {
    analog.push({
      label: self.layout.analog_channels[i].label,
      unit: self.layout.analog_channels[i].unit,
      samples: self.analog[i].finish(),
    })
  }
  {
    frames: self.frames,
    point_rate: self.layout.point_rate,
    analog_rate: self.layout.analog_rate,
    first_frame: self.layout.first_frame,
    duration: self.frames.to_double() / self.layout.point_rate,
    markers,
    analog,
  }
}

///|
pub fn analyze(reader : Reader) -> TrialSummary raise C3dError {
  let analyzer = Analyzer::new(reader.layout())
  for i in 0..<reader.layout().frame_count {
    analyzer.add(reader.frame(i))
  }
  analyzer.finish()
}

///|
pub fn distribution_json(value : Distribution) -> Json {
  if value.count == 0 {
    return {
      "count": 0,
      "minimum": null,
      "maximum": null,
      "mean": null,
      "variance": null,
      "rms": null,
    }
  }
  {
    "count": value.count,
    "minimum": value.minimum,
    "maximum": value.maximum,
    "mean": value.mean,
    "variance": value.variance,
    "rms": value.rms,
  }
}

///|
pub fn summary_json(summary : TrialSummary) -> Json {
  {
    "frames": summary.frames,
    "point_rate": summary.point_rate,
    "analog_rate": summary.analog_rate,
    "first_frame": summary.first_frame,
    "duration": summary.duration,
    "markers": Json(
      summary.markers.map(marker => {
        (
          {
            "label": marker.label,
            "valid_samples": marker.valid_samples,
            "missing_samples": marker.missing_samples,
            "longest_missing_run": marker.longest_missing_run,
            "x": distribution_json(marker.x),
            "y": distribution_json(marker.y),
            "z": distribution_json(marker.z),
            "residual": distribution_json(marker.residual),
          } : Json)
      }),
    ),
    "analog": Json(
      summary.analog.map(channel => {
        (
          {
            "label": channel.label,
            "unit": channel.unit,
            "samples": distribution_json(channel.samples),
          } : Json)
      }),
    ),
  }
}

///|
pub fn inspect_json(reader : Reader) -> Json {
  let layout = reader.layout()
  {
    "format": "C3D",
    "processor": "Intel IEEE little-endian",
    "storage": if layout.float_storage {
      "float32"
    } else {
      "int16"
    },
    "frames": layout.frame_count,
    "first_frame": layout.first_frame,
    "point_count": layout.point_count,
    "point_rate": layout.point_rate,
    "point_scale": layout.point_scale,
    "point_labels": Json(layout.point_labels),
    "point_unit": layout.point_unit,
    "analog_subsamples": layout.analog_subsamples,
    "analog_rate": layout.analog_rate,
    "analog_channels": Json(layout.analog_channels.map(channel_json)),
    "parameter_groups": reader.parameters().groups.length(),
    "parameters": reader.parameters().values.length(),
    "events": Json(reader.events().map(event_json)),
    "data_offset": layout.data_offset,
    "frame_bytes": layout.frame_bytes,
  }
}

///|
fn check_labels(
  labels : Array[String],
  kind : String,
  diagnostics : Array[Diagnostic],
) -> Unit {
  let seen : Map[String, Bool] = Map([])
  for i in 0..<labels.length() {
    if labels[i] == "" {
      diagnostics.push({
        severity: Warning,
        code: "EMPTY_LABEL",
        location: "\{kind}[\{i}]",
        message: "channel label is empty",
      })
    } else if seen.contains(labels[i]) {
      diagnostics.push({
        severity: Warning,
        code: "DUPLICATE_LABEL",
        location: "\{kind}[\{i}]",
        message: "label-based selection would be ambiguous",
      })
    }
    seen[labels[i]] = true
  }
}

///|
pub fn check(
  reader : Reader,
  scan_frames~ : Bool = true,
) -> Report raise C3dError {
  let diagnostics : Array[Diagnostic] = []
  let layout = reader.layout()
  check_labels(layout.point_labels, "points", diagnostics)
  check_labels(layout.analog_channels.map(c => c.label), "analog", diagnostics)
  for
    name in ["USED", "SCALE", "RATE", "FRAMES", "DATA_START", "LABELS", "UNITS"] {
    if reader.parameters().get("POINT", name) is None {
      diagnostics.push({
        severity: Warning,
        code: "MISSING_POINT_PARAMETER",
        location: "POINT:" + name,
        message: "legacy fallback was used for a standard parameter",
      })
    }
  }
  let start = (layout.first_frame - 1).to_double() / layout.point_rate
  let end = start + layout.frame_count.to_double() / layout.point_rate
  for i in 0..<reader.events().length() {
    let event = reader.events()[i]
    if event.time < start || event.time >= end {
      diagnostics.push({
        severity: Warning,
        code: "EVENT_OUTSIDE_TRIAL",
        location: "events[\{i}]",
        message: "event time is outside the half-open trial interval",
      })
    }
  }
  if scan_frames {
    for i in 0..<layout.frame_count {
      try reader.frame(i) catch {
        error =>
          diagnostics.push({
            severity: Error,
            code: "INVALID_FRAME",
            location: "frames[\{i}]",
            message: error.message(),
          })
      } noraise {
        _ => ()
      }
      if diagnostics.length() >= 1000 {
        raise C3dError::ResourceLimit("diagnostic count")
      }
    }
  }
  Report::{ diagnostics, }
}

///|
pub fn report_json(report : Report) -> Json {
  {
    "ok": !report.has_errors(),
    "diagnostics": Json(
      report.diagnostics.map(item => {
        (
          {
            "severity": if item.severity == Error {
              "error"
            } else {
              "warning"
            },
            "code": item.code,
            "location": item.location,
            "message": item.message,
          } : Json)
      }),
    ),
  }
}
