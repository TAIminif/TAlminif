///|
test "parameter builders support signed unsigned float and UTF8 arrays" {
  assert_eq(@lib.Parameter::integers("NUM", [-1, 32767]).int_values(), [
    -1, 32767,
  ])
  assert_eq(
    @lib.Parameter::unsigned("COUNT", 65535).number(unsigned=true),
    65535.0,
  )
  assert_eq(@lib.Parameter::reals("RATE", [100.0, 200.0]).real_values(), [
    100.0, 200.0,
  ])
  assert_eq(@lib.Parameter::texts("LABELS", ["左脚", "R"]).text_values(), [
    "左脚", "R",
  ])
  assert_eq(@lib.Parameter::text("UNIT", "mm").text_values(), ["mm"])
  expect_error(() => @lib.Parameter::integer("NUM", 40000))
}

///|
test "immutable parameter editing respects locked fields" {
  let original = @lib.Parameters::empty().put_int("point", "used", 2)
  let changed = original.put_int("POINT", "USED", 3)
  assert_eq(original.require("POINT", "USED").number(), 2.0)
  assert_eq(changed.require("POINT", "USED").number(), 3.0)
  let locked = original.set("POINT", {
    ..original.require("POINT", "USED"),
    locked: true,
  })
  expect_error(() => locked.put_int("POINT", "USED", 4))
  assert_eq(
    locked
    .put_int("POINT", "USED", 4, override_locked=true)
    .require("POINT", "USED")
    .number(),
    4.0,
  )
  expect_error(() => locked.remove("POINT", "USED"))
}

///|
test "Fortran parameter dimension order is explicit" {
  let array = @lib.Parameter::integers("MATRIX", [10, 11, 12, 20, 21, 22], dimensions=[
    3, 2,
  ])
  assert_eq(array.linear_index([2, 1]), 5)
  assert_eq(array.int_values()[array.linear_index([1, 1])], 21)
  expect_error(() => array.linear_index([3, 0]))
  expect_error(() => array.linear_index([0]))
}
