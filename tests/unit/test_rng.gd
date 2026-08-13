extends GutTest
## Domain RNG — Step 05 fixtures.

const Rng = preload("res://scripts/domain/rng/rng.gd")

func test_rng_seed_zero_is_deterministic() -> void:
	# splitmix64 special-cases the zero state so a seed of 0 is still
	# safe to pass; verify two RNGs seeded with 0 produce the same stream.
	var a := Rng.new(0)
	var b := Rng.new(0)
	for i in range(100):
		assert_eq(a.rand_int(1000), b.rand_int(1000))

func test_rng_same_seed_same_stream() -> void:
	var a := Rng.new(42)
	var b := Rng.new(42)
	for i in range(50):
		assert_eq(a.rand_int(10000), b.rand_int(10000))

func test_rng_float_strictly_less_than_one() -> void:
	var rng := Rng.new(98765)
	for i in range(500):
		var f: float = rng.rand_float()
		assert_true(f < 1.0, "rand_float produced 1.0 or above: %f" % f)

func test_rng_different_seed_different_stream() -> void:
	var a := Rng.new(1)
	var b := Rng.new(2)
	var differs_once := false
	for i in range(20):
		if a.rand_int(1000) != b.rand_int(1000):
			differs_once = true
			break
	assert_true(differs_once, "different seeds must produce different streams")

func test_rng_state_roundtrips() -> void:
	var a := Rng.new(99)
	# Advance the stream a bit.
	a.rand_int(123456)
	var snap := a.to_snapshot()
	var b := Rng.from_snapshot(snap)
	for i in range(50):
		assert_eq(a.rand_int(1000000), b.rand_int(1000000),
			"replay RNG must produce the same stream as the original after a snapshot roundtrip")

func test_rng_int_roundtrips() -> void:
	var a := Rng.new(7)
	# Advance past initial state.
	var advance := a.rand_int(1000)
	# Sanity-check we got a value; this is just to consume one output.
	assert_true(advance >= 0)
	var v := a.to_int()
	var b := Rng.from_int(v)
	assert_eq(a.seed_value(), b.seed_value())
	for i in range(10):
		assert_eq(a.rand_int(100), b.rand_int(100))

func test_rng_range_within_bounds() -> void:
	var rng := Rng.new(12345)
	for i in range(500):
		var v: int = rng.rand_range(3, 7)
		assert_true(v >= 3 and v < 7, "rand_range out of bounds: %d" % v)

func test_rng_float_in_unit_interval() -> void:
	var rng := Rng.new(98765)
	for i in range(500):
		var f: float = rng.rand_float()
		assert_true(f >= 0.0 and f < 1.0)

func test_rng_pick_returns_element() -> void:
	var rng := Rng.new(11)
	var arr := [10, 20, 30, 40, 50]
	for i in range(50):
		var v: int = rng.pick(arr)
		assert_has(arr, v)