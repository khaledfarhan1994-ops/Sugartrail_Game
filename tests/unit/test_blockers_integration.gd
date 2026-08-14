extends GutTest
## Step 15: blocker integration tests covering replay, version bump,
## schema migration, and recipe loading.

const Board = preload("res://scripts/domain/board/board.gd")
const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const LevelLoader = preload("res://scripts/domain/levels/level_loader.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Version = preload("res://scripts/domain/sugartrail_version.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord

# A. Replay determinism: two replays of a frosting log produce
# identical snapshot_hash.

func test_replay_determinism_with_frosting() -> void:
	var b1 := Board.new(Board.BoardConfig.new(4, 4, 4, [],
			[{"x": 1, "y": 0, "type": "FROSTING", "layers": 2}]))
	b1.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b1.set_piece(Coord.new(2, 0), Board.Piece.new(0))
	b1.set_piece(Coord.new(3, 0), Board.Piece.new(0))
	var rng1 := Rng.new(31)
	Resolution.fill_random(b1, rng1, false)
	var r1: Resolution.CascadeResult = Resolution.resolve(b1, rng1)
	var h1: int = b1.snapshot_hash()

	var b2 := Board.new(Board.BoardConfig.new(4, 4, 4, [],
			[{"x": 1, "y": 0, "type": "FROSTING", "layers": 2}]))
	b2.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b2.set_piece(Coord.new(2, 0), Board.Piece.new(0))
	b2.set_piece(Coord.new(3, 0), Board.Piece.new(0))
	var rng2 := Rng.new(31)
	Resolution.fill_random(b2, rng2, false)
	var r2: Resolution.CascadeResult = Resolution.resolve(b2, rng2)
	var h2: int = b2.snapshot_hash()
	assert_eq(h1, h2, "snapshot hash must be deterministic across replays")
	assert_eq(r1.total_removed, r2.total_removed)

# B. Engine version bump: 0.4.0.

func test_engine_version_is_0_4_0() -> void:
	assert_eq(Version.engine_version(), "0.4.0")

# C. Schema v2 migration: v1 recipe without blockers loads with empty blockers.

func test_schema_v1_to_v2_migration_adds_empty_blockers() -> void:
	var raw: Dictionary = {
		"recipe_id": "l1-first-match",
		"version": 1,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 6,
		"board_h": 8,
		"palette": 6,
		"seed": 101,
		"moves": 25,
		"target_kind": 0,
		"target_total": 6,
		"star_one": 30,
		"star_two": 80,
		"star_three": 150,
		"intro_text": "",
		"tutorial": [],
		"avoid_initial_matches": true,
	}
	var migrated: Dictionary = LevelRecipe.migration_v1_to_v2(raw)
	assert_eq(migrated["version"], LevelRecipe.SCHEMA_VERSION)
	assert_eq(migrated["blockers"], [])
	# Re-validate the migrated recipe.
	var revalidation: LevelRecipe.ValidationResult = LevelRecipe.validate(migrated)
	assert_true(revalidation.ok, "migrated v2 must validate: %s" % str(revalidation.errors))

# D. Schema v2 rejection: invalid type rejected.

func test_schema_v2_rejects_bad_blocker_type() -> void:
	var raw: Dictionary = {
		"recipe_id": "bad",
		"version": 2,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 4,
		"board_h": 4,
		"palette": 4,
		"seed": 0,
		"moves": 10,
		"target_kind": 0,
		"target_total": 1,
		"star_one": 10,
		"star_two": 20,
		"star_three": 30,
		"intro_text": "",
		"tutorial": [],
		"avoid_initial_matches": true,
		"blockers": [{"x": 0, "y": 0, "type": "INVALID", "layers": 1}],
	}
	var r: LevelRecipe.ValidationResult = LevelRecipe.validate(raw)
	assert_false(r.ok)
	assert_true(r.errors.size() > 0)

# E. Recipe load: l11-frosting-intro loads and has a session.

func test_load_frosting_intro_recipe() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("l11-frosting-intro", errors)
	assert_not_null(loaded, "l11 must load: %s" % str(errors))
	assert_not_null(loaded.session)
	# Verify frosting cells are present on the initial board.
	var frosted_count: int = 0
	for cell in loaded.session.board._cells:
		if cell.is_frosted():
			frosted_count += 1
	assert_gt(frosted_count, 0, "l11 must start with at least one frosted cell")

# F. Recipe load: l12-locked-cells loads and has locked pieces.

func test_load_locked_cells_recipe() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("l12-locked-cells", errors)
	assert_not_null(loaded, "l12 must load: %s" % str(errors))
	var locked_count: int = 0
	for cell in loaded.session.board._cells:
		if cell.is_locked():
			locked_count += 1
	assert_gt(locked_count, 0, "l12 must start with at least one locked piece")