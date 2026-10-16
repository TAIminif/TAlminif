///|
test "numbered channel arrays cross every 255 entry boundary" {
  for count in [255, 256, 510, 511] {
    let labels = Array::makei(count, index => "P\{index + 1}")
    let scales = Array::makei(count, index => (index + 1).to_double() * 0.25)
    let offsets = Array::makei(count, index => index - 200)
    let parameters = @lib.Parameters::empty()
      .put_text_series("POINT", "LABELS", labels)
      .put_real_series("ANALOG", "SCALE", scales)
      .put_int_series("ANALOG", "OFFSET", offsets)
    assert_eq(parameters.read_text_series("POINT", "LABELS", count), labels)
    assert_eq(parameters.read_real_series("ANALOG", "SCALE", count), scales)
    assert_eq(parameters.read_int_series("ANALOG", "OFFSET", count), offsets)
    assert_eq(parameters.require("POINT", "LABELS").dimensions[1], 255)
    if count > 255 {
      assert_eq(
        parameters.require("POINT", "LABELS2").dimensions[1],
        (count - 255).min(255),
      )
    }
    if count > 510 {
      assert_eq(parameters.require("POINT", "LABELS3").dimensions[1], 1)
    }
  }
}

///|
test "all numbered text segments share a UTF8 byte width" {
  let labels = Array::makei(511, index => {
    if index == 510 {
      "左脚标记"
    } else {
      "P"
    }
  })
  let parameters = @lib.Parameters::empty().put_text_series(
    "POINT", "LABELS", labels,
  )
  assert_eq(parameters.require("POINT", "LABELS").dimensions, [12, 255])
  assert_eq(parameters.require("POINT", "LABELS2").dimensions, [12, 255])
  assert_eq(parameters.require("POINT", "LABELS3").dimensions, [12, 1])
  assert_eq(parameters.read_text_series("POINT", "LABELS", 511), labels)
}

///|
test "series rewriting removes stale tails and retains unrelated vendor metadata" {
  let original = @lib.Parameters::empty()
    .put_text_series("POINT", "LABELS", Array::makei(511, i => "P\{i + 1}"))
    .put_text("POINT", "LABELS_VENDOR", "preserve")
    .put_text("POINT", "LABELS02", "vendor")
    .put_text("OTHER", "LABELS2", "separate group")
  let selected = ["P511", "P256", "P255"]
  let rewritten = original.put_text_series("POINT", "LABELS", selected)
  assert_eq(rewritten.read_text_series("POINT", "LABELS", 3), selected)
  assert_true(rewritten.get("POINT", "LABELS2") is None)
  assert_true(rewritten.get("POINT", "LABELS3") is None)
  assert_eq(rewritten.require("POINT", "LABELS_VENDOR").text_values(), [
    "preserve",
  ])
  assert_eq(rewritten.require("POINT", "LABELS02").text_values(), ["vendor"])
  assert_eq(rewritten.require("OTHER", "LABELS2").text_values(), [
    "separate group",
  ])
  assert_eq(original.read_text_series("POINT", "LABELS", 511).length(), 511)
}

///|
test "numbered arrays reject actual holes while numeric calibration requires complete segments" {
  let full = @lib.Parameters::empty().put_text_series(
    "POINT",
    "LABELS",
    Array::make(511, "P"),
  )
  expect_error(() => {
    full.remove("POINT", "LABELS2").read_text_series("POINT", "LABELS", 511)
  })
  expect_error(() => {
    full.remove("POINT", "LABELS").read_text_series("POINT", "LABELS", 511)
  })
  assert_eq(full.read_text_series("POINT", "LABELS", 510).length(), 510)
  let short = full.put_texts("POINT", "LABELS", Array::make(254, "P"))
  assert_eq(short.read_text_series("POINT", "LABELS", 511)[510], "")
  let mixed_width = full.put_texts("POINT", "LABELS2", Array::make(255, "LONG"))
  assert_eq(mixed_width.read_text_series("POINT", "LABELS", 511)[255], "LONG")
  let numeric = @lib.Parameters::empty().put_real_series(
    "ANALOG",
    "SCALE",
    Array::make(256, 1.0),
  )
  expect_error(() => {
    numeric
    .put_reals("ANALOG", "SCALE", Array::make(254, 1.0))
    .read_real_series("ANALOG", "SCALE", 256)
  })
  expect_error(() => {
    numeric.remove("ANALOG", "SCALE").read_real_series("ANALOG", "SCALE", 256)
  })
}

///|
test "fallback requires the whole series to be absent and supports empty trials" {
  let empty = @lib.Parameters::empty()
  assert_eq(empty.read_text_series("POINT", "LABELS", 3, prefix="P"), [
    "P1", "P2", "P3",
  ])
  assert_eq(empty.read_text_series("POINT", "DESCRIPTIONS", 2), ["", ""])
  assert_eq(empty.read_real_series("ANALOG", "SCALE", 2, fallback=0.5), [
    0.5, 0.5,
  ])
  assert_eq(empty.read_int_series("ANALOG", "OFFSET", 2, fallback=-8), [-8, -8])
  let zero = empty
    .put_text_series("POINT", "LABELS", [])
    .put_real_series("ANALOG", "SCALE", [])
    .put_int_series("ANALOG", "OFFSET", [])
  assert_eq(zero.read_text_series("POINT", "LABELS", 0), [])
  assert_eq(zero.read_real_series("ANALOG", "SCALE", 0), [])
  assert_eq(zero.read_int_series("ANALOG", "OFFSET", 0), [])
  let orphan = empty.put_texts("POINT", "LABELS2", ["P256"])
  expect_error(() => orphan.read_text_series("POINT", "LABELS", 1, prefix="P"))
  expect_error(() => empty.read_text_series("POINT", "LABELS", -1))
  expect_error(() => empty.read_int_series("ANALOG", "OFFSET", 65536))
}

///|
test "unsigned offsets and arbitrary canonical numeric suffixes are handled" {
  let values = Array::makei(256, i => 65000 + i)
  let parameters = @lib.Parameters::empty().put_int_series(
    "ANALOG",
    "OFFSET",
    values,
    unsigned=true,
  )
  assert_eq(
    parameters.read_int_series("ANALOG", "OFFSET", 256, unsigned=true),
    values,
  )
  let stale = parameters
    .put_int("ANALOG", "OFFSET10", 5)
    .put_int("ANALOG", "OFFSET999999999999999999999999999", 6)
  expect_error(() => {
    stale.read_int_series("ANALOG", "OFFSET", 256, unsigned=true)
  })
  let cleared = stale.remove_series("ANALOG", "OFFSET")
  assert_true(cleared.get("ANALOG", "OFFSET10") is None)
  assert_true(
    cleared.get("ANALOG", "OFFSET999999999999999999999999999") is None,
  )
  assert_eq(cleared.read_int_series("ANALOG", "OFFSET", 1), [0])
}

///|
test "series updates respect locked continuations" {
  let original = @lib.Parameters::empty().put_real_series(
    "ANALOG",
    "SCALE",
    Array::make(256, 0.5),
  )
  let locked = original.set("ANALOG", {
    ..original.require("ANALOG", "SCALE2"),
    locked: true,
  })
  expect_error(() => locked.put_real_series("ANALOG", "SCALE", [1.0]))
  expect_error(() => locked.remove_series("ANALOG", "SCALE"))
  let changed = locked.put_real_series(
    "ANALOG",
    "SCALE",
    [1.0],
    override_locked=true,
  )
  assert_eq(changed.read_real_series("ANALOG", "SCALE", 1), [1.0])
  assert_true(changed.get("ANALOG", "SCALE2") is None)
}

///|
test "unused label capacity is tolerated and numeric tails require all actual calibration entries" {
  let parameters = @lib.Parameters::empty()
    .put_text_series("POINT", "LABELS", Array::makei(260, i => "P\{i + 1}"))
    .put_real_series("ANALOG", "SCALE", Array::makei(260, i => i.to_double()))
    .put_int_series("ANALOG", "OFFSET", Array::makei(260, i => i))
  assert_eq(parameters.read_text_series("POINT", "LABELS", 256)[255], "P256")
  assert_eq(parameters.read_real_series("ANALOG", "SCALE", 256).length(), 256)
  assert_eq(parameters.read_int_series("ANALOG", "OFFSET", 256)[255], 255)
  assert_eq(parameters.read_text_series("POINT", "LABELS", 255).length(), 255)
  expect_error(() => parameters.read_int_series("ANALOG", "OFFSET", 261))
  assert_eq(
    parameters
    .put_texts("POINT", "LABELS", Array::make(254, "P"))
    .read_text_series("POINT", "LABELS", 256)[254],
    "P256",
  )
}

///|
test "short last text segments receive defaults without hiding missing numbered segments" {
  let official_style = @lib.Parameters::empty()
    .put_text_series("POINT", "LABELS", Array::makei(48, i => "P\{i + 1}"))
    .put_text_series("POINT", "DESCRIPTIONS", Array::make(20, "known"))
  assert_eq(official_style.read_text_series("POINT", "LABELS", 26).length(), 26)
  let descriptions = official_style.read_text_series(
    "POINT", "DESCRIPTIONS", 26,
  )
  assert_eq(descriptions[19], "known")
  assert_eq(descriptions[20], "")
  assert_eq(descriptions[25], "")
  let partial = @lib.Parameters::empty().put_text_series(
    "POINT",
    "LABELS",
    Array::makei(257, i => "P\{i + 1}"),
  )
  assert_eq(
    partial.read_text_series("POINT", "LABELS", 260, prefix="P")[255:260].to_owned(),
    ["P256", "P257", "P258", "P259", "P260"],
  )
  assert_eq(
    partial
    .remove("POINT", "LABELS2")
    .read_text_series("POINT", "LABELS", 260, prefix="P")[255:260].to_owned(),
    ["P256", "P257", "P258", "P259", "P260"],
  )
}

///|
test "historical 127 plus 73 label splits concatenate actual entries and accept independent widths" {
  let labels = Array::makei(200, i => {
    if i < 127 {
      "P\{i + 1}"
    } else {
      "TRACK\{i + 1}"
    }
  })
  let parameters = @lib.Parameters::empty()
    .put_texts("POINT", "LABELS", labels[0:127].to_owned())
    .put_texts("POINT", "LABELS2", labels[127:200].to_owned())
  assert_eq(parameters.require("POINT", "LABELS").dimensions, [4, 127])
  assert_eq(parameters.require("POINT", "LABELS2").dimensions, [8, 73])
  assert_eq(parameters.read_text_series("POINT", "LABELS", 200), labels)
  let partial = @lib.Parameters::empty().put_texts(
    "POINT",
    "LABELS",
    Array::makei(255, i => "P\{i + 1}"),
  )
  let expanded = partial.read_text_series("POINT", "LABELS", 300, prefix="P")
  assert_eq(expanded[254], "P255")
  assert_eq(expanded[255], "P256")
  assert_eq(expanded[299], "P300")
  let gap = @lib.Parameters::empty()
    .put_texts("POINT", "LABELS", ["P1"])
    .put_texts("POINT", "LABELS3", ["P3"])
  expect_error(() => gap.read_text_series("POINT", "LABELS", 3))
}
