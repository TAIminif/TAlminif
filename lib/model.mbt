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
  max_file_bytes : Int32
  max_parameters : Int32
  max_parameter_bytes : Int32
  max_frames : Int32
  max_points : Int32
  max_analog_channels : Int32
  max_subsamples : Int32
  max_total_values : Int32
  max_text_bytes : Int32
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
  parameter_block : Int32
  point_count : Int32
  analog_values_per_frame : Int32
  first_frame : Int32
  last_frame : Int32
  max_gap : Int32
  scale : Double
  data_block : Int32
  analog_subsamples : Int32
  point_rate : Double
  reserved : Bytes
} derive(Debug, Eq)

///|
pub(all) struct Group {
  id : Int32
  name : String
  description : Bytes
  locked : Bool
} derive(Debug, Eq)

///|
pub(all) struct Parameter {
  group_id : Int32
  name : String
  data_type : Int32
  dimensions : Array[Int32]
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
  cameras : Int32
  valid : Bool
} derive(Debug, Eq)

///|
pub fn Marker::new(x : Double, y : Double, z : Double) -> Marker {
  { x, y, z, residual: 0.0, cameras: 0, valid: true, }
}

///|
pub fn Marker::missing() -> Marker {
  { x: 0.0, y: 0.0, z: 0.0, residual: -1.0, cameras: 0, valid: false, }
}

///|
pub(all) struct Frame {
  number : Int32
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
  icon_id : Int32
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
  frame_count : Int32
  first_frame : Int32
  point_count : Int32
  point_rate : Double
  point_scale : Double
  point_labels : Array[String]
  point_descriptions : Array[String]
  point_unit : String
  analog_channels : Array[Channel]
  analog_subsamples : Int32
  analog_rate : Double
  analog_global_scale : Double
  analog_unsigned : Bool
  float_storage : Bool
  frame_bytes : Int32
  data_offset : Int32
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
