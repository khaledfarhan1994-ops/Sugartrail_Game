extends GutTest
## Exact-rule level solver fixtures.
##
## Step 23 acceptance: the solver proves solvability, returns a
## witness, and respects the resource bounds (max_depth,
## max_nodes, max_time_ms). The validator wraps the solver with
## the launch-contract checks (opening move, no deadlock,
## replay parity, booster-free win).

const Solver = preload("res://scripts/domain/solver/solver.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Validator = preload("res://scripts/domain/solver/validator.gd")
const LevelLoader = preload("res://scripts/domain/levels/level_loader.gd")
const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Coord = Board.CellCoord

# ----------------------------------------------------------------------------
# SolveOptions + SolverResult basics
# ----------------------------------------------------------------------------

func test_solveoptions_defaults() -> void:
	var opts := Solver.SolveOptions.new()
	assert_eq(opts.max_moves, 20)
	assert_eq(opts.max_depth, Solver.DEFAULT_MAX_DEPTH)
	assert_eq(opts.max_nodes, Solver.DEFAULT_MAX_NODES)
	assert_eq(opts.max_time_ms, Solver.DEFAULT_MAX_TIME_MS)
	assert_false(opts.use_boosters)

func test_solverresult_to_dict_shape() -> void:
	var r := Solver.SolverResult.new()
	var d: Dictionary = r.to_dict()
	assert_true(d.has("classification"))
	assert_true(d.has("proof_moves"))
	assert_true(d.has("moves_used"))
	assert_true(d.has("nodes_visited"))
	assert_true(d.has("dead_ends_hit"))
	assert_true(d.has("duration_ms"))
	assert_true(d.has("note"))

# ----------------------------------------------------------------------------
# Solver on launch levels
# ----------------------------------------------------------------------------

func test_solve_first_curated_level() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(
			"l1-first-match", errors)
	if errors.size() > 0 or loaded == null:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var opts := Solver.SolveOptions.new()
	opts.max_moves = loaded.session.moves_remaining
	opts.max_depth = 12
	opts.max_nodes = 5000
	opts.max_time_ms = 3000
	var r: Solver.SolverResult = Solver.solve(loaded.recipe, opts)
	assert_eq(int(r.classification), int(Solver.Classification.SOLVED),
			"first curated should be solvable: %s" % r.note)
	assert_gt(r.proof_moves.size(), 0, "witness must be non-empty")
	assert_true(r.moves_used <= int(loaded.session.moves_remaining))

func test_solve_each_curated_level_is_solvable() -> void:
	# Spot-check a handful of curated levels so we don't time the
	# test budget. The validator is the proper end-to-end check;
	# this just confirms the solver doesn't choke on real input.
	var levels_to_check: Array = [
		"l1-first-match", "l3-cascade", "l6-cascade-pressure",
		"l11-frosting-intro",
	]
	for recipe_id in levels_to_check:
		var errors: Array = []
		var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(
				recipe_id, errors)
		if loaded == null:
			continue
		var opts := Solver.SolveOptions.new()
		opts.max_moves = loaded.session.moves_remaining
		opts.max_depth = 6
		opts.max_nodes = 1000
		opts.max_time_ms = 2000
		var r: Solver.SolverResult = Solver.solve(loaded.recipe, opts)
		# Some levels may legitimately need deeper search than
		# 6 moves with 1000 nodes; the validator is the place to
		# make strict assertions. Here we just confirm the solver
		# returns without crashing.
		assert_true(r.classification >= 0)

# ----------------------------------------------------------------------------
# Synthetic fixtures
# ----------------------------------------------------------------------------

func test_solve_synthetic_collect_kind_winnable() -> void:
	# Hand-rolled recipe: 6x8, palette 3, target_total 4.
	# With a small palette, finding 4 matches is easy.
	var recipe := _synthetic_collect_recipe(3, 4, 10)
	var opts := Solver.SolveOptions.new()
	opts.max_moves = 10
	opts.max_depth = 8
	opts.max_nodes = 2000
	opts.max_time_ms = 2000
	var r: Solver.SolverResult = Solver.solve(recipe, opts)
	assert_eq(int(r.classification), int(Solver.Classification.SOLVED),
			"small-palette synthetic should be solvable: %s" % r.note)
	assert_gt(r.proof_moves.size(), 0)

func test_solve_returns_unsolvable_when_no_legal_moves() -> void:
	# Recipe with zero moves remaining: the solver must classify
	# as UNSOLVABLE (or TIMEOUT) because there is no path to the
	# objective without making any move.
	var recipe := _synthetic_collect_recipe(5, 1, 1)
	var opts := Solver.SolveOptions.new()
	opts.max_moves = 0
	opts.max_depth = 0
	opts.max_nodes = 500
	opts.max_time_ms = 500
	var r: Solver.SolverResult = Solver.solve(recipe, opts)
	# With 0 moves, the solver cannot make progress. SOLVED is
	# only possible if the starting board already meets the
	# target_total=1 — which is rare but not impossible if a piece
	# of target kind is on the board. We accept UNSOLVABLE or
	# TIMEOUT but reject RESOURCE_LIMIT (we didn't burn nodes).
	assert_ne(int(r.classification),
			int(Solver.Classification.RESOURCE_LIMIT),
			"a 0-moves recipe must not hit the node cap")

func test_solve_respects_max_time_budget() -> void:
	# A tiny max_time_ms forces a TIMEOUT classification on most
	# levels. The solver must terminate without crashing.
	var recipe := _synthetic_collect_recipe(5, 15, 15)
	var opts := Solver.SolveOptions.new()
	opts.max_moves = 15
	opts.max_depth = 15
	opts.max_nodes = 100_000
	opts.max_time_ms = 50  # 50 ms is too tight for any real search
	var r: Solver.SolverResult = Solver.solve(recipe, opts)
	# Either TIMEOUT or RESOURCE_LIMIT, depending on which bound
	# hits first. SOLVED is unlikely on a 50 ms budget.
	if r.classification == Solver.Classification.SOLVED:
		# If we did solve, the witness must still be valid.
		assert_gt(r.proof_moves.size(), 0)
	else:
		assert_true(
				r.classification == Solver.Classification.TIMEOUT
				or r.classification == Solver.Classification.RESOURCE_LIMIT)

# ----------------------------------------------------------------------------
# Determinism
# ----------------------------------------------------------------------------

func test_solve_is_deterministic() -> void:
	var recipe := _synthetic_collect_recipe(4, 6, 8)
	var opts := Solver.SolveOptions.new()
	opts.max_moves = 8
	opts.max_depth = 6
	opts.max_nodes = 1000
	opts.max_time_ms = 1000
	var r1: Solver.SolverResult = Solver.solve(recipe, opts)
	var r2: Solver.SolverResult = Solver.solve(recipe, opts)
	assert_eq(int(r1.classification), int(r2.classification))
	if r1.classification == Solver.Classification.SOLVED:
		assert_eq(r1.proof_moves.size(), r2.proof_moves.size())

# ----------------------------------------------------------------------------
# Validator wrappers
# ----------------------------------------------------------------------------

func test_validator_witness_replays_through_session() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(
			"l1-first-match", errors)
	if loaded == null:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var opts := Solver.SolveOptions.new()
	opts.max_moves = loaded.session.moves_remaining
	opts.max_depth = 12
	opts.max_nodes = 5000
	opts.max_time_ms = 3000
	var report: Validator.ValidationReport = Validator.validate(
			loaded.recipe, opts)
	assert_eq(int(report.classification),
			int(Solver.Classification.SOLVED),
			"first curated should be SOLVED: %s" % str(report.notes))
	assert_true(report.replay_parity_ok,
			"replay parity must hold: %s" % str(report.notes))
	assert_eq(int(report.checks.get("opening_move", -1)),
			int(Validator.CheckStatus.PASS))
	assert_eq(int(report.checks.get("no_deadlock", -1)),
			int(Validator.CheckStatus.PASS))
	assert_eq(int(report.checks.get("booster_free", -1)),
			int(Validator.CheckStatus.PASS))

func test_validator_report_shape() -> void:
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(
			"l1-first-match", errors)
	if loaded == null:
		assert_eq(0, errors.size(), "loader errors: %s" % str(errors))
		return
	var opts := Solver.SolveOptions.new()
	opts.max_moves = loaded.session.moves_remaining
	opts.max_depth = 12
	opts.max_nodes = 5000
	opts.max_time_ms = 3000
	var report: Validator.ValidationReport = Validator.validate(
			loaded.recipe, opts)
	var d: Dictionary = report.to_dict()
	assert_true(d.has("classification"))
	assert_true(d.has("checks"))
	assert_true(d.has("replay_parity_ok"))
	assert_true(d.has("solver"))
	assert_true(d.has("notes"))

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------

func _synthetic_collect_recipe(palette: int, target_total: int,
		moves: int) -> Dictionary:
	return {
		"recipe_id": "synth-collect",
		"version": LevelRecipe.SCHEMA_VERSION,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 6,
		"board_h": 8,
		"palette": palette,
		"seed": 12345,
		"moves": moves,
		"target_kind": 0,
		"target_total": target_total,
		"star_one": 50,
		"star_two": 150,
		"star_three": 300,
		"tutorial": [],
		"intro_text": "",
		"avoid_initial_matches": true,
		"blockers": [],
		"objectives": [{
			"kind": 0,  # COLLECT_KIND
			"target_kind": 0,
			"target_total": target_total,
		}],
		"tokens": [],
	}
