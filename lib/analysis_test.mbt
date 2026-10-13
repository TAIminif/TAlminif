///|
test "online calibrated statistics use all subsamples and omit missing points" {
  let summary = analyze(Reader::new(write(sample_document())))
  assert_eq(summary.frames, 3)
  assert_eq(summary.markers[1].valid_samples, 2)
  assert_eq(summary.markers[1].missing_samples, 1)
  assert_eq(summary.markers[1].longest_missing_run, 1)
  assert_eq(summary.markers[1].x.mean, 10.0)
  assert_eq(summary.analog[0].samples.count, 6)
  assert_eq(summary.analog[0].samples.mean, 3.5)
  assert_eq(summary.analog[0].samples.variance, 3.5)
}

///|
test "streaming moments are stable and empty distributions explicit" {
  let moments = Moments::new()
  for value in [1000000001.0, 1000000002.0, 1000000003.0] {
    moments.add(value)
  }
  assert_eq(moments.finish().variance, 1.0)
  assert_eq(distribution_json(Moments::new().finish()), {
    "count": 0,
    "minimum": null,
    "maximum": null,
    "mean": null,
    "variance": null,
    "rms": null,
  })
}

///|
test "quality diagnostics identify duplicate labels and event times" {
  let document = sample_document()
    .rename_point(1, "L")
    .with_events([Event::new(1.0, "outside")])
  let report = check(Reader::new(write(document)))
  assert_false(report.has_errors())
  assert_true(report.diagnostics.any(d => d.code == "DUPLICATE_LABEL"))
  assert_true(report.diagnostics.any(d => d.code == "EVENT_OUTSIDE_TRIAL"))
}
