extends GutTest
## Curated level loader, opening move, replay, and tutorial fixtures.
##
## Step 11 acceptance: every curated level loads from data (no .tscn
## per level), has at least one legal opening move, and the prompts
## use known localization keys.

const LevelLoader = preload("res://scripts/domain/levels/level_loader.gd")
const Tutorial = preload("res://scripts/domain/tutorial/tutorial.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Coord = Board.CellCoord

const CURATED_IDS: Array = [
	"l1-first-match",
	"l2-horizontal-vertical",
	"l3-cascade",
	"l4-move-budget",
	"l5-stars",
	"l6-cascade-pressure",
	"l7-tight-budget",
	"l8-pause-and-restart",
	"l9-long-combo",
	"l10-final",
	"l11-frosting-intro",
	"l12-locked-cells",
]

# ----------------------------------------------------------------------------
# Curated level load
# ----------------------------------------------------------------------------

func test_all_curated_levels_load() -> void:
	var errors: Array = []
	var levels: Array = LevelLoader.load_all_curated(errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	assert_eq(levels.size(), CURATED_IDS.size())
	for i in range(CURATED_IDS.size()):
		var loaded: LevelLoader.LoadedLevel = levels[i]
		var recipe: Dictionary = loaded.recipe
		assert_eq(recipe["recipe_id"], CURATED_IDS[i])
		assert_true(loaded.session != null)
		assert_true(loaded.tutorial != null)

func test_load_level_by_id() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("l1-first-match", errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	assert_true(loaded != null)
	assert_eq(loaded.recipe["recipe_id"], "l1-first-match")
	assert_eq(loaded.session.moves_remaining, 25)
	assert_eq(loaded.session.objective.target_total, 6)

func test_load_missing_level_returns_null() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("does-not-exist", errors)
	assert_true(loaded == null)
	assert_true(errors.size() > 0)

# ----------------------------------------------------------------------------
# Opening move
# ----------------------------------------------------------------------------

func test_every_curated_level_has_opening_move() -> void:
	var errors: Array = []
	var levels: Array = LevelLoader.load_all_curated(errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	for loaded in levels:
		var lvl: LevelLoader.LoadedLevel = loaded
		var ok: bool = LevelLoader.has_opening_move(lvl.session)
		assert_true(ok, "%s should have at least one legal opening move" % lvl.recipe["recipe_id"])

func test_curated_levels_use_distinct_seeds() -> void:
	var errors: Array = []
	var levels: Array = LevelLoader.load_all_curated(errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var seen: Dictionary = {}
	for loaded in levels:
		var lvl: LevelLoader.LoadedLevel = loaded
		var seed_v: int = int(lvl.recipe["seed"])
		assert_false(seen.has(seed_v), "duplicate seed %d in curated levels" % seed_v)
		seen[seed_v] = true

# ----------------------------------------------------------------------------
# Replay evidence
# ----------------------------------------------------------------------------

func test_curated_level_replay_is_deterministic() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("l1-first-match", errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	# Build a synthetic log: play the first legal opening move.
	var log: Replay.ActionLog = Replay.ActionLog.new()
	log.recipe = loaded.recipe
	log.initial_board = loaded.session.board.to_snapshot()
	log.initial_rng_state = loaded.session.rng.to_int()
	var moves: Array = Rules.enumerate_legal_swaps(loaded.session.board)
	if moves.size() == 0:
		pending("no opening move")
		return
	var a: Coord = moves[0][0]
	var b: Coord = moves[0][1]
	log.actions.append(Replay.Action.new(Replay.ActionKind.SWAP, a, b))
	# Apply the same move to the live session so we can capture the
	# final RNG state and total events.
	loaded.session.attempt_swap(a, b)
	log.final_rng_state = loaded.session.rng.to_int()
	log.total_events = 1  # placeholder; replay computes its own count
	# Run replay twice; the result hash must match.
	var r1: Replay.ReplayResult = Replay.replay(log, "")
	var r2: Replay.ReplayResult = Replay.replay(log, "")
	assert_true(r1.ok)
	assert_true(r2.ok)
	assert_eq(r1.result_hash, r2.result_hash)

# ----------------------------------------------------------------------------
# Tutorial
# ----------------------------------------------------------------------------

func test_tutorial_pack_from_recipe() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level("l1-first-match", errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var pack: Tutorial.TutorialPack = loaded.tutorial
	assert_eq(pack.intro_key, "tutorial.intro.first_level")
	assert_eq(pack.prompts.size(), 3)
	assert_eq(pack.prompts[0].key, "tutorial.prompt.select")
	assert_eq(pack.prompts[1].key, "tutorial.prompt.swap")
	assert_eq(pack.prompts[2].key, "tutorial.prompt.match")

func test_tutorial_pack_advance() -> void:
	var pack := Tutorial.TutorialPack.new("", [
		Tutorial.Prompt.new("a", 1.0),
		Tutorial.Prompt.new("b", 1.0),
	])
	assert_false(pack.is_complete())
	assert_eq(pack.peek().key, "a")
	var dismissed: Tutorial.Prompt = pack.advance()
	assert_eq(dismissed.key, "a")
	assert_eq(pack.next_prompt, 1)
	assert_eq(pack.peek().key, "b")
	pack.advance()
	assert_true(pack.is_complete())
	assert_true(pack.peek() == null)

func test_tutorial_pack_remaining_keys() -> void:
	var pack := Tutorial.TutorialPack.new("", [
		Tutorial.Prompt.new("a"),
		Tutorial.Prompt.new("b"),
		Tutorial.Prompt.new("c"),
	])
	pack.advance()
	var remaining: Array = pack.remaining_keys()
	assert_eq(remaining.size(), 2)
	assert_eq(remaining[0], "b")
	assert_eq(remaining[1], "c")

func test_all_tutorial_prompts_resolve_known_keys() -> void:
	var errors: Array = []
	var levels: Array = LevelLoader.load_all_curated(errors)
	if errors.size() > 0:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var known: Dictionary = {}
	for k in Tutorial.Catalog.known_keys():
		known[k] = true
	for loaded in levels:
		var lvl: LevelLoader.LoadedLevel = loaded
		var pack: Tutorial.TutorialPack = lvl.tutorial
		if pack.intro_key != "":
			assert_true(known.has(pack.intro_key),
					"unknown intro key: %s in %s" % [pack.intro_key, lvl.recipe["recipe_id"]])
		for p in pack.prompts:
			var prompt: Tutorial.Prompt = p
			assert_true(known.has(prompt.key),
					"unknown prompt key: %s in %s" % [prompt.key, lvl.recipe["recipe_id"]])

func test_english_translation_covers_all_known_keys() -> void:
	for k in Tutorial.Catalog.known_keys():
		var s: String = Tutorial.english(k)
		assert_ne(s, "", "missing English translation for %s" % k)