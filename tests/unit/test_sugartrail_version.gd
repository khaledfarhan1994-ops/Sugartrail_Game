extends GutTest
## Step 03 fixture — proves the test framework runs and asserts work.

func test_engine_version_is_string() -> void:
	var v: String = SugartrailVersion.engine_version()
	assert_eq(typeof(v), TYPE_STRING, "engine_version() must return a String")
	assert_true(v.length() > 0, "engine version string must be non-empty")

func test_engine_version_format() -> void:
	var v: String = SugartrailVersion.engine_version()
	# Format is "<major>.<minor>.<patch>"
	var parts: PackedStringArray = v.split(".")
	assert_eq(parts.size(), 3, "engine version should have exactly three dot-separated parts")

func test_is_pre_alpha_is_bool() -> void:
	assert_eq(typeof(SugartrailVersion.is_pre_alpha()), TYPE_BOOL)