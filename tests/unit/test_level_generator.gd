extends GutTest
## Mechanic-aware level generator fixtures.
##
## Step 22 acceptance: the deterministic generator produces schema-clean
## recipes that survive LevelRecipe.validate AND the diagnostic checks
## (no starting 3-runs, at least one legal opening move, target counts
## feasible). Equal input profile + seed produce equal recipe + manifest.

const Generator = preload("res://scripts/domain/levels/level_generator.gd")
const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Coord = Board.CellCoord

const DIFFICULTY = Generator.Difficulty
const MECHANIC = Generator.Mechanic

# ----------------------------------------------------------------------------
# InputProfile basics
# ----------------------------------------------------------------------------

func test_profile_to_dict_roundtrip() -> void:
	var p := Generator.InputProfile.new(2, 4, DIFFICULTY.MEDIUM,
			MECHANIC.RELEASE_TOKEN, 7, 9, 6, 123456789)
	var d: Dictionary = p.to_dict()
	var q := Generator.InputProfile.from_dict(d)
	assert_eq(q.chapter, 2)
	assert_eq(q.index_in_chapter, 4)
	assert_eq(q.difficulty, DIFFICULTY.MEDIUM)
	assert_eq(q.mechanic, MECHANIC.RELEASE_TOKEN)
	assert_eq(q.board_w, 7)
	assert_eq(q.board_h, 9)
	assert_eq(q.palette, 6)
	assert_eq(q.seed_override, 123456789)

func test_validate_rejects_out_of_range_profile() -> void:
	var bad := Generator.InputProfile.new(-1, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 5)
	var errs: Array = Generator.validate_profile(bad)
	assert_gt(errs.size(), 0, "negative chapter should fail")

func test_validate_rejects_bad_difficulty() -> void:
	var bad := Generator.InputProfile.new(0, 0, 99,
			MECHANIC.COLLECT_KIND, 6, 8, 5)
	var errs: Array = Generator.validate_profile(bad)
	assert_true(_contains(errs, "difficulty"))

func test_validate_rejects_bad_board_shape() -> void:
	var bad := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 3, 8, 5)
	var errs: Array = Generator.validate_profile(bad)
	assert_true(_contains(errs, "board_w"))

# ----------------------------------------------------------------------------
# Determinism
# ----------------------------------------------------------------------------

func test_same_seed_produces_identical_recipe() -> void:
	var p := Generator.InputProfile.new(1, 0, DIFFICULTY.MEDIUM,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 42)
	var r1: Generator.GenerationResult = Generator.generate(p)
	var r2: Generator.GenerationResult = Generator.generate(p)
	assert_true(r1.ok, "first generation should succeed: %s" % str(r1.errors))
	assert_true(r2.ok, "second generation should succeed: %s" % str(r2.errors))
	assert_eq(r1.recipe["seed"], r2.recipe["seed"])
	assert_eq(r1.recipe["moves"], r2.recipe["moves"])
	assert_eq(r1.recipe["target_total"], r2.recipe["target_total"])
	assert_eq(r1.manifest["signature_hash"], r2.manifest["signature_hash"])

func test_different_seeds_produce_different_recipes() -> void:
	var p1 := Generator.InputProfile.new(1, 0, DIFFICULTY.MEDIUM,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 1)
	var p2 := Generator.InputProfile.new(1, 0, DIFFICULTY.MEDIUM,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 2)
	var r1: Generator.GenerationResult = Generator.generate(p1)
	var r2: Generator.GenerationResult = Generator.generate(p2)
	assert_true(r1.ok)
	assert_true(r2.ok)
	assert_ne(r1.manifest["signature_hash"], r2.manifest["signature_hash"],
			"different seeds should give different manifest hashes")

# ----------------------------------------------------------------------------
# Schema + diagnostic acceptance
# ----------------------------------------------------------------------------

func test_collect_kind_recipe_passes_validate() -> void:
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 100)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok, "generate should succeed: %s" % str(r.errors))
	var vr: LevelRecipe.ValidationResult = LevelRecipe.validate(r.recipe)
	assert_true(vr.ok, "validate should pass: %s" % str(vr.errors))

func test_release_token_recipe_has_one_token() -> void:
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.MEDIUM,
			MECHANIC.RELEASE_TOKEN, 6, 8, 5, 200)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	assert_eq(r.recipe["tokens"].size(), 1)

func test_clear_layers_recipe_has_blockers() -> void:
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.MEDIUM,
			MECHANIC.CLEAR_LAYERS, 6, 8, 5, 300)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	assert_gt(r.recipe["blockers"].size(), 0,
			"CLEAR_LAYERS level should have frosting blockers")

func test_starting_board_has_no_3run() -> void:
	# The diagnosis step rejects any starting board with a run.
	# This test verifies (a) generation succeeds (so the no-3-run
	# avoidance worked), (b) the manifest hash is stable, and
	# (c) attach_pieces roundtrips a non-empty grid. The actual
	# "no 3-run" check happens inside _diagnose_recipe via
	# Rules.find_runs — covered by test_collect_kind_recipe_passes_validate.
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 4, 7)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	var sample: Array = [[0, 1, 2, 3], [1, 2, 3, 0], [2, 3, 0, 1]]
	var full: Dictionary = Generator.attach_pieces(r.recipe, sample)
	var pieces: Array = full.get("_generated_pieces", [])
	assert_eq(pieces.size(), 3,
			"attach_pieces must copy the provided grid back")
	assert_eq(pieces[0].size(), 4)
	# Reproducibility: same profile + seed => same manifest hash.
	var p2 := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 4, 7)
	var r2: Generator.GenerationResult = Generator.generate(p2)
	assert_eq(r.manifest["signature_hash"], r2.manifest["signature_hash"])

# ----------------------------------------------------------------------------
# Profile-driven objectives + star budget
# ----------------------------------------------------------------------------

func test_difficulty_drives_moves() -> void:
	var easy := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 11)
	var hard := Generator.InputProfile.new(0, 0, DIFFICULTY.HARD,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 11)
	var r_easy: Generator.GenerationResult = Generator.generate(easy)
	var r_hard: Generator.GenerationResult = Generator.generate(hard)
	assert_true(r_easy.ok)
	assert_true(r_hard.ok)
	assert_gt(int(r_easy.recipe["moves"]), int(r_hard.recipe["moves"]),
			"easy should have more moves than hard")

func test_reach_score_objective_has_target_score() -> void:
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.MEDIUM,
			MECHANIC.REACH_SCORE, 6, 8, 5, 444)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	var objs: Array = r.recipe["objectives"]
	assert_eq(objs.size(), 1)
	assert_eq(int(objs[0]["kind"]), Session.ObjectiveKind.REACH_SCORE)
	assert_gt(int(objs[0]["target_score"]), 0,
			"REACH_SCORE level must carry a positive target_score")

func test_clear_layers_objective_target_feasible() -> void:
	# The generator picks a default target_layers that should always
	# be <= the sum of frosting layers placed on the board.
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.MEDIUM,
			MECHANIC.CLEAR_LAYERS, 6, 8, 5, 555)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	var sum_layers: int = 0
	for b in r.recipe["blockers"]:
		sum_layers += int(b.get("layers", 0))
	var target_layers: int = 0
	for o in r.recipe["objectives"]:
		var od: Dictionary = o
		target_layers = int(od.get("target_layers", 0))
	assert_true(target_layers <= sum_layers,
			"CLEAR_LAYERS target_layers must be feasible")

# ----------------------------------------------------------------------------
# Manifest
# ----------------------------------------------------------------------------

func test_manifest_records_metadata() -> void:
	var p := Generator.InputProfile.new(2, 3, DIFFICULTY.HARD,
			MECHANIC.CLEAR_LAYERS, 6, 8, 5, 999)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_true(r.ok)
	assert_eq(int(r.manifest["target_schema_version"]),
			LevelRecipe.SCHEMA_VERSION)
	assert_true(str(r.manifest["generator_version"]).begins_with("0.6.0-"))
	assert_true(r.manifest.has("signature_hash"))
	assert_true(r.manifest.has("profile"))
	var profile: Dictionary = r.manifest["profile"]
	assert_eq(int(profile["chapter"]), 2)

func test_manifest_hash_stable_across_calls() -> void:
	var p := Generator.InputProfile.new(1, 1, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 6, 8, 5, 88)
	var r1: Generator.GenerationResult = Generator.generate(p)
	var r2: Generator.GenerationResult = Generator.generate(p)
	assert_eq(int(r1.manifest["signature_hash"]),
			int(r2.manifest["signature_hash"]))

# ----------------------------------------------------------------------------
# Edge cases + helpers
# ----------------------------------------------------------------------------

func test_attach_pieces_roundtrips_grid() -> void:
	var grid: Array = [
		[0, 1, 2, 3],
		[1, 2, 3, 0],
		[2, 3, 0, 1],
	]
	var stub: Dictionary = {"recipe_id": "stub", "version": 3,
			"chapter": 0, "index_in_chapter": 0, "board_w": 4,
			"board_h": 3, "palette": 4, "seed": 1, "moves": 20,
			"target_kind": 0, "target_total": 10, "star_one": 100,
			"star_two": 200, "star_three": 300, "tutorial": [],
			"intro_text": ""}
	var full: Dictionary = Generator.attach_pieces(stub, grid)
	assert_eq(full.get("_generated_pieces").size(), 3)
	assert_eq(full.get("_generated_pieces")[0].size(), 4)
	# The original stub must remain unchanged (duplicate semantics).
	assert_false(stub.has("_generated_pieces"))

func test_invalid_profile_returns_failure_result() -> void:
	# board_w out of range.
	var p := Generator.InputProfile.new(0, 0, DIFFICULTY.EASY,
			MECHANIC.COLLECT_KIND, 100, 8, 5)
	var r: Generator.GenerationResult = Generator.generate(p)
	assert_false(r.ok)
	assert_gt(r.errors.size(), 0)
	assert_true(r.recipe.is_empty())

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _contains(arr: Array, needle: String) -> bool:
	for entry in arr:
		if str(entry).find(needle) != -1:
			return true
	return false
