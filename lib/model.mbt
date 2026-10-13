///|
pub suberror C3dError {
  Invalid(String)
  Truncated(String)
  Unsupported(String)
  ResourceLimit(String)
} derive(Debug)

///|
pub fn C3dError::message(self : C3dError) -> String {
  match self {
    Invalid(text) | Truncated(text) | Unsupported(text) | ResourceLimit(text) =>
      text
  }
}

///|
/// Construct an invalid-input error for application adapters.
pub fn invalid(message : String) -> C3dError {
  C3dError::Invalid(message)
}

///|
pub fn C3dError::kind(self : C3dError) -> String {
  match self {
    Invalid(_) => "invalid"
    Truncated(_) => "truncated"
    Unsupported(_) => "unsupported"
    ResourceLimit(_) => "resource_limit"
  }
}

///|
pub(all) struct Limits {
  max_file_bytes : Int
  max_parameters : Int
  max_parameter_bytes : Int
  max_frames : Int
  max_points : Int
  max_analog_channels : Int
  max_subsamples : Int
  max_total_values : Int
  max_text_bytes : Int
} derive(Debug, Eq)

///|
pub fn Limits::default() -> Limits {
  {
    max_file_bytes: 128 * 1024 * 1024,
    max_parameters: 4096,
    max_parameter_bytes: 1024 * 1024,
    max_frames: 200_000,
    max_points: 255,
    max_analog_channels: 255,
    max_subsamples: 2048,
    max_total_values: 20_000_000,
    max_text_bytes: 1048576,
  }
}

///|
pub(all) struct Header {
  parameter_block : Int
  point_count : Int
  analog_values_per_frame : Int
  first_frame : Int
  last_frame : Int
  max_gap : Int
  scale : Double
  data_block : Int
  analog_subsamples : Int
  point_rate : Double
  reserved : Bytes
} derive(Debug, Eq)

///|
pub(all) struct Group {
  id : Int
  name : String
  description : Bytes
  locked : Bool
} derive(Debug, Eq)

///|
pub(all) struct Parameter {
  group_id : Int
  name : String
  data_type : Int
  dimensions : Array[Int]
  data : Bytes
  description : Bytes
  locked : Bool
} derive(Debug, Eq)

///|
pub(all) struct Parameters {
  groups : Array[Group]
  values : Array[Parameter]
} derive(Debug, Eq)

///|
pub(all) struct Marker {
  x : Double
  y : Double
  z : Double
  residual : Double
  cameras : Int
  valid : Bool
} derive(Debug, Eq)

///|
pub fn Marker::new(x : Double, y : Double, z : Double) -> Marker {
  { x, y, z, residual: 0.0, cameras: 0, valid: true }
}

///|
pub fn Marker::missing() -> Marker {
  { x: 0.0, y: 0.0, z: 0.0, residual: -1.0, cameras: 0, valid: false }
}

///|
pub(all) struct Frame {
  number : Int
  points : Array[Marker]
  analog : Array[Array[Double]]
} derive(Debug, Eq)

///|
pub(all) struct Event {
  time : Double
  label : String
  context : String
  description : String
  subject : String
  icon_id : Int
  generic : Bool
} derive(Debug, Eq)

///|
pub fn Event::new(time : Double, label : String) -> Event {
  {
    time,
    label,
    context: "",
    description: "",
    subject: "",
    icon_id: 0,
    generic: false,
  }
}

///|
pub(all) struct Channel {
  label : String
  description : String
  unit : String
  scale : Double
  offset : Double
} derive(Debug, Eq)

///|
pub(all) struct Layout {
  frame_count : Int
  first_frame : Int
  point_count : Int
  point_rate : Double
  point_scale : Double
  point_labels : Array[String]
  point_descriptions : Array[String]
  point_unit : String
  analog_channels : Array[Channel]
  analog_subsamples : Int
  analog_rate : Double
  analog_global_scale : Double
  analog_unsigned : Bool
  float_storage : Bool
  frame_bytes : Int
  data_offset : Int
} derive(Debug, Eq)

///|
pub(all) struct Document {
  header : Header
  parameters : Parameters
  layout : Layout
  frames : Array[Frame]
  events : Array[Event]
} derive(Debug, Eq)

///|
pub(all) enum Severity {
  Warning
  Error
} derive(Debug, Eq)

///|
pub(all) struct Diagnostic {
  severity : Severity
  code : String
  location : String
  message : String
} derive(Debug, Eq)

///|
pub(all) struct Report {
  diagnostics : Array[Diagnostic]
} derive(Debug, Eq)

///|
pub fn Report::has_errors(self : Report) -> Bool {
  self.diagnostics.any(d => d.severity == Error)
}

///|
pub fn finite(value : Double) -> Bool {
  !value.is_inf() && !value.is_nan()
}

///|
pub fn validate_limits(limits : Limits) -> Unit raise C3dError {
  if limits.max_file_bytes < 512 ||
    limits.max_parameter_bytes < 512 ||
    limits.max_parameters < 1 ||
    limits.max_frames < 0 ||
    limits.max_points < 0 ||
    limits.max_analog_channels < 0 ||
    limits.max_subsamples < 1 ||
    limits.max_total_values < 0 ||
    limits.max_text_bytes < 0 {
    raise C3dError::Invalid("invalid resource limits")
  }
}
