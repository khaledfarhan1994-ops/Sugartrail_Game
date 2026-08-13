class_name SugartrailRng
extends RefCounted
## Deterministic seeded random number generator.
##
## Sugartrail has no nondeterministic gameplay randomness. Every
## random choice (match-3 refill, level generator roll, reshuffle)
## flows through this RNG so that:
##   * Two runs with the same seed produce identical outputs.
##   * The RNG state itself is serializable so replays can re-create
##     a session exactly.
##
## Implementation: splitmix64 with sign-bit clamping. GDScript's
## 64-bit integers are signed, so the high (sign) bit is forced to
## zero. The resulting 63-bit stream still passes reasonable
## determinism checks for game-scale consumption and roundtrips
## cleanly through JSON-friendly integers.

const GOLDEN_CONST: int = 2177342782468422677  # splitmix64 golden ratio, sign bit cleared
const MIX1: int = 4564476756301768121        # splitmix64 mix constant 1, sign bit cleared
const MIX2: int = 1499779743744070123        # splitmix64 mix constant 2, sign bit cleared
const SIGN_CLEAR: int = 0x7FFFFFFFFFFFFFFF   # 63-bit safe mask (literal in range)

var _state: int = 0

func _init(seed_value: int = 0) -> void:
	# Avoid the all-zero state, which is a fixed point for some RNGs.
	var s: int = seed_value & SIGN_CLEAR
	if s == 0:
		s = GOLDEN_CONST
	_state = s

func seed_value() -> int:
	return _state

# splitmix64 step, with sign bit cleared at each hop.
func _next_u63() -> int:
	_state = (_state + GOLDEN_CONST) & SIGN_CLEAR
	var z: int = _state
	z = (((z >> 30) ^ z) * MIX1) & SIGN_CLEAR
	z = (((z >> 27) ^ z) * MIX2) & SIGN_CLEAR
	z = ((z >> 31) ^ z) & SIGN_CLEAR
	return z

## Inclusive-exclusive integer in [0, n).
func rand_int(n: int) -> int:
	assert(n > 0, "rand_int requires positive n")
	return _next_u63() % n

## Uniform real in [0, 1).
func rand_float() -> float:
	# Use only 53 bits (mantissa precision) so the result is always
	# strictly less than 1.0.
	var bits: int = _next_u63() >> 10  # top 53 bits
	return float(bits) / float(1 << 53)

## Inclusive-exclusive integer in [lo, hi).
func rand_range(lo: int, hi: int) -> int:
	assert(hi > lo, "rand_range requires hi > lo")
	return lo + rand_int(hi - lo)

## Pick one element from an array deterministically.
func pick(arr: Array) -> Variant:
	assert(arr.size() > 0, "pick requires non-empty array")
	var i: int = rand_int(arr.size())
	return arr[i]

## Serialise the RNG so a replay can restore exact behaviour.
func to_snapshot() -> Dictionary:
	return {"state": _state}

static func from_snapshot(d: Dictionary) -> SugartrailRng:
	return SugartrailRng.new(int(d.get("state", 0)))

## Return the state as a JSON-friendly integer.
func to_int() -> int:
	return _state

static func from_int(v: int) -> SugartrailRng:
	return SugartrailRng.new(v)