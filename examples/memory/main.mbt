///|
fn main {
  try {
    let frames : Array[@c3d.Frame] = [
      { number: 1, points: [@c3d.Marker::new(1.0, 2.0, 3.0)], analog: [], },
      { number: 2, points: [@c3d.Marker::new(2.0, 3.0, 4.0)], analog: [], },
    ]
    let original = @c3d.Document::new(["Heel"], [], frames)
    let reader = @c3d.Reader::new(@c3d.write(original))
    println(@c3d.inspect_json(reader).stringify())
    println(@c3d.summary_json(@c3d.analyze(reader)).stringify())
  } catch {
    error => abort(error.message())
  }
}
