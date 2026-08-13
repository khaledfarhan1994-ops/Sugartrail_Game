class_name SugartrailVersion
extends RefCounted
## Sugartrail engine version constants.
##
## This is a tiny domain module exercised by the Step 03 test framework.
## Real domain logic (board, RNG, matches) lives in scripts/domain/ and
## arrives in Step 05+. This file proves the test infrastructure works
## before any real rules are written.

const ENGINE_MAJOR := 0
const ENGINE_MINOR := 2
const ENGINE_PATCH := 0

static func engine_version() -> String:
	return "%d.%d.%d" % [ENGINE_MAJOR, ENGINE_MINOR, ENGINE_PATCH]

static func is_pre_alpha() -> bool:
	return ENGINE_MAJOR == 0