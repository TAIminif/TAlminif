///|
/// The Node host only supplies filesystem and process operations.
extern "js" fn arguments() -> FixedArray[String] = "() => globalThis.__moonC3D.args"

///|
extern "js" fn read_bytes(path : String) -> Bytes = "(path) => globalThis.__moonC3D.readBytes(path)"

///|
extern "js" fn read_text(path : String) -> String = "(path) => globalThis.__moonC3D.readText(path)"

///|
extern "js" fn write_bytes(path : String, data : Bytes) -> Unit = "(path, data) => globalThis.__moonC3D.writeBytes(path, data)"

///|
extern "js" fn write_text(path : String, data : String) -> Unit = "(path, data) => globalThis.__moonC3D.writeText(path, data)"

///|
extern "js" fn print_text(text : String) -> Unit = "(text) => globalThis.__moonC3D.stdout(text)"

///|
extern "js" fn fail(text : String, code : Int32) -> Unit = "(text, code) => globalThis.__moonC3D.fail(text, code)"

///|
let help : String =
  #|MoonC3D 0.2.0 — C3D motion-capture tools
  #|Usage: node bin/moonc3d.mjs COMMAND ...
  #|  inspect INPUT                     metadata as JSON
  #|  check INPUT                       validate metadata and every frame
  #|  stats INPUT                       streaming marker/analog statistics
  #|  dump INPUT OUTPUT.json            semantic JSON with raw parameters
  #|  pack INPUT.json OUTPUT.c3d         construct C3D from MoonC3D/1 JSON
  #|  crop INPUT OUTPUT START END       zero-based half-open frame range
  #|  crop-time INPUT OUTPUT START END  absolute seconds, frame-start selection
  #|  select-points INPUT OUTPUT I,...  zero-based ordered point indices
  #|  select-analog INPUT OUTPUT I,...  zero-based ordered analog indices
  #|  convert INPUT OUTPUT SCALE        negative=float32; positive=int16
  #|  convert-encoding INPUT OUTPUT intel|dec|mips
  #|  csv INPUT OUTPUT points|analog|events
  #|  demo OUTPUT.c3d                   create a reproducible example trial
  #|All output paths must be new. Crops rebase frame numbers and event times.

///|
fn arity(args : Array[String], count : Int32) -> Unit raise @c3d.C3dError {
  if args.length() != count {
    raise @c3d.invalid("wrong argument count; use help")
  }
}

///|
fn integer(text : String) -> Int32 raise @c3d.C3dError {
  let result = @string.parse_int(text) catch {
    _ => raise @c3d.invalid("expected integer: " + text)
  }
  if result < 0 {
    raise @c3d.invalid("negative index: " + text)
  }
  result
}

///|
fn number(text : String) -> Double raise @c3d.C3dError {
  let result = @string.parse_double(text) catch {
    _ => raise @c3d.invalid("expected number: " + text)
  }
  if !@c3d.finite(result) {
    raise @c3d.invalid("number must be finite")
  }
  result
}

///|
fn indices(text : String) -> Array[Int32] raise @c3d.C3dError {
  if text == "" {
    return []
  }
  let result : Array[Int32] = []
  for part in text.split(",") {
    result.push(integer(part.to_owned()))
  }
  result
}

///|
fn output_json(value : Json) -> Unit {
  print_text(value.stringify() + "\n")
}

///|
fn saved(path : String, document : @c3d.Document) -> Unit raise @c3d.C3dError {
  let data = @c3d.write(document)
  write_bytes(path, data)
  output_json({
    "output": path,
    "bytes": data.length(),
    "frames": document.layout.frame_count,
  })
}

///|
fn demo() -> @c3d.Document raise @c3d.C3dError {
  let frames : Array[@c3d.Frame] = []
  for i in 0..<20 {
    let t = i.to_double()
    frames.push({
      number: i + 1,
      points: [
        @c3d.Marker::new(t, t * 2.0, 100.0),
        if i >= 5 && i < 8 {
          @c3d.Marker::missing()
        } else {
          @c3d.Marker::new(t + 10.0, t, 90.0)
        },
      ],
      analog: [[t, t + 0.5], [t * 3.0, t * 3.0 + 1.0]],
    })
  }
  let channels : Array[@c3d.Channel] = [
    {
      label: "ForceZ",
      description: "calibrated vertical load",
      unit: "N",
      scale: 0.5,
      offset: 10.0,
    },
    {
      label: "EMG",
      description: "example analog signal",
      unit: "mV",
      scale: 0.25,
      offset: -4.0,
    },
  ]
  let document = @c3d.Document::new(
    ["LeftHeel", "RightHeel"],
    channels,
    frames,
    analog_subsamples=2,
  )
  let document = {
    ..document,
    parameters: document.parameters.put_text(
      "CUSTOM", "NOTE", "MoonC3D reproducible example",
    ),
  }
  document.with_events([
    @c3d.Event::new(0.05, "contact"),
    @c3d.Event::new(0.12, "toe-off"),
  ])
}

///|
fn run(args : Array[String]) -> Unit raise @c3d.C3dError {
  if args.is_empty() || args[0] == "help" || args[0] == "--help" {
    print_text(help + "\n")
    return
  }
  match args[0] {
    "inspect" => {
      arity(args, 2)
      output_json(@c3d.inspect_json(@c3d.Reader::new(read_bytes(args[1]))))
    }
    "check" => {
      arity(args, 2)
      let report = @c3d.check(@c3d.Reader::new(read_bytes(args[1])))
      if report.has_errors() {
        fail(@c3d.report_json(report).stringify(), 1)
      } else {
        output_json(@c3d.report_json(report))
      }
    }
    "stats" => {
      arity(args, 2)
      output_json(
        @c3d.summary_json(@c3d.analyze(@c3d.Reader::new(read_bytes(args[1])))),
      )
    }
    "dump" => {
      arity(args, 3)
      let document = @c3d.read(read_bytes(args[1]))
      write_text(args[2], @c3d.document_json(document).stringify())
      output_json({ "output": args[2], "frames": document.frames.length() })
    }
    "pack" => {
      arity(args, 3)
      saved(args[2], @c3d.import_json(read_text(args[1])))
    }
    "crop" => {
      arity(args, 5)
      let start = integer(args[3])
      let end = integer(args[4])
      saved(args[2], @c3d.read(read_bytes(args[1])).crop(start, end))
    }
    "crop-time" => {
      arity(args, 5)
      let start = number(args[3])
      let end = number(args[4])
      saved(args[2], @c3d.read(read_bytes(args[1])).crop_time(start, end))
    }
    "select-points" => {
      arity(args, 4)
      let selection = indices(args[3])
      saved(args[2], @c3d.read(read_bytes(args[1])).select_points(selection))
    }
    "select-analog" => {
      arity(args, 4)
      let selection = indices(args[3])
      saved(args[2], @c3d.read(read_bytes(args[1])).select_analog(selection))
    }
    "convert-encoding" => {
      arity(args, 4)
      let document = @c3d.read(read_bytes(args[1]))
      let processor = @c3d.processor_from_name(args[3])
      let data = @c3d.write(document, processor~)
      write_bytes(args[2], data)
      output_json({
        "output": args[2],
        "processor": processor.name(),
        "bytes": data.length(),
      })
    }
    "convert" => {
      arity(args, 4)
      let scale = number(args[3])
      saved(args[2], @c3d.read(read_bytes(args[1])).convert_storage(scale))
    }
    "csv" => {
      arity(args, 4)
      if !["points", "analog", "events"].contains(args[3]) {
        raise @c3d.invalid("unknown CSV kind")
      }
      let reader = @c3d.Reader::new(read_bytes(args[1]))
      let csv = match args[3] {
        "points" => @c3d.points_csv(reader)
        "analog" => @c3d.analog_csv(reader)
        _ => @c3d.events_csv(reader)
      }
      write_text(args[2], csv)
      output_json({ "output": args[2], "kind": args[3] })
    }
    "demo" => {
      arity(args, 2)
      saved(args[1], demo())
    }
    _ => raise @c3d.invalid("unknown command; use help")
  }
}

///|
fn main {
  run(arguments().iter().collect()) catch {
    error => {
      let result : Json = {
        "ok": false,
        "error": error.kind(),
        "message": error.message(),
      }
      fail(result.stringify(), 1)
    }
  }
}
