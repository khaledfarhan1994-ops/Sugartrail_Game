extends GutTest
## LevelRecipe validation fixtures.
##
## Step 11 first-version of LevelRecipe rejects malformed recipes
## before any session is constructed. Each fixture exercises one
## validation rule.

const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")

func _good_recipe() -> Dictionary:
	return {
		"recipe_id": "test-level",
		"version": 1,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 6,
		"board_h": 8,
		"palette": 6,
		"seed": 12345,
		"moves": 20,
		"target_kind": 0,
		"target_total": 10,
		"star_one": 50,
		"star_two": 100,
		"star_three": 200,
		"intro_text": "",
		"tutorial": ["tutorial.prompt.select"],
		"avoid_initial_matches": true,
	}

func test_validate_accepts_good_recipe() -> void:
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(_good_recipe())
	assert_true(r.ok, "valid recipe should pass: %s" % str(r.errors))
	assert_eq(r.errors.size(), 0)

func test_validate_rejects_missing_field() -> void:
	var bad: Dictionary = _good_recipe()
	bad.erase("recipe_id")
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)
	assert_true(r.errors.size() > 0)
	assert_true(r.errors[0].begins_with("missing required field"))

func test_validate_rejects_wrong_version() -> void:
	var bad: Dictionary = _good_recipe()
	bad["version"] = 99
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)
	for e in r.errors:
		if e.find("version") != -1:
			return
	assert_true(false, "expected an error mentioning version")

func test_validate_rejects_bad_dimensions() -> void:
	var bad: Dictionary = _good_recipe()
	bad["board_w"] = 0
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)
	for e in r.errors:
		if e.find("board_w") != -1:
			return
	assert_true(false, "expected an error mentioning board_w")

func test_validate_rejects_target_kind_out_of_palette() -> void:
	var bad: Dictionary = _good_recipe()
	bad["palette"] = 4
	bad["target_kind"] = 6
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)

func test_validate_rejects_non_decreasing_stars() -> void:
	var bad: Dictionary = _good_recipe()
	bad["star_one"] = 100
	bad["star_two"] = 50
	bad["star_three"] = 200
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)
	for e in r.errors:
		if e.find("star") != -1:
			return
	assert_true(false, "expected an error mentioning star thresholds")

func test_validate_rejects_non_array_tutorial() -> void:
	var bad: Dictionary = _good_recipe()
	bad["tutorial"] = "not an array"
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)
	for e in r.errors:
		if e.find("tutorial") != -1:
			return
	assert_true(false, "expected an error mentioning tutorial")

func test_validate_rejects_empty_recipe_id() -> void:
	var bad: Dictionary = _good_recipe()
	bad["recipe_id"] = "   "
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_false(r.ok)

func test_validate_warns_on_low_moves() -> void:
	var bad: Dictionary = _good_recipe()
	bad["moves"] = 3
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(bad)
	assert_true(r.ok)
	assert_true(r.warnings.size() > 0)

func test_with_defaults_fills_avoid_initial_matches() -> void:
	var raw: Dictionary = _good_recipe()
	raw.erase("avoid_initial_matches")
	var out: Dictionary = LevelRecipe.with_defaults(raw)
	assert_true(out["avoid_initial_matches"])
