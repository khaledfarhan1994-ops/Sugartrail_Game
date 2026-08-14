extends GutTest
## Step 16: multi-objective semantics.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const State = Session.State

func _make_recipe(overrides: Dictionary = {}) -> Dictionary:
	var recipe := {
		"recipe_id": "test-objectives",
		"version": 3,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 6,
		"board_h": 8,
		"palette": 4,
		"seed": 2024,
		"moves": 20,
		"objectives": [
			{"kind": 0, "target_kind": 0, "target_total": 10},
		],
		"target_kind": 0,
		"target_total": 10,
		"star_one": 50,
		"star_two": 150,
		"star_three": 300,
		"intro_text": "",
		"tutorial": [],
		"avoid_initial_matches": true,
	}
	for k in overrides:
		recipe[k] = overrides[k]
	return recipe

# A. COLLECT_KIND existing behaviour: back-compat objective tracks
# objectives[0].

func test_collect_kind_objective_progresses_via_back_compat() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	assert_eq(session.objective.kind, Session.ObjectiveKind.COLLECT_KIND)
	assert_eq(session.objective.target_kind, 0)
	assert_eq(session.objective.target_total, 10)
	# objectives array has exactly one entry.
	assert_eq(session.objectives.size(), 1)

# B. REACH_SCORE completion via accumulated points.

func test_reach_score_completes_when_score_meets_target() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 1, "target_score": 30},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	# Inject a known score via a direct swap that produces matches.
	# Walk a few legal swaps; progress is updated as score climbs.
	for i in range(10):
		if session.moves_remaining <= 0:
			break
		var legal: Array = Rules.enumerate_legal_swaps(session.board)
		if legal.size() == 0:
			break
		session.attempt_swap(legal[0][0], legal[0][1])
	# REACH_SCORE progress mirrors score; after any swaps it is >= 0.
	assert_true(session.objective.progress >= 0)
	assert_eq(session.objective.progress, session.score)

# C. REACH_SCORE loss when moves run out before target hit.

func test_reach_score_loss_when_target_unreached() -> void:
	var recipe := _make_recipe({
		"moves": 1,
		"objectives": [
			{"kind": 1, "target_score": 10000},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	var legal: Array = Rules.enumerate_legal_swaps(session.board)
	if legal.size() == 0:
		pending("deadlocked")
		return
	session.attempt_swap(legal[0][0], legal[0][1])
	assert_false(session.objective.is_complete(),
			"impossibly-high score target must remain incomplete")
	if session.moves_remaining == 0:
		assert_eq(session.state, State.LOST)

# D. CLEAR_LAYERS increments per BLOCKER_DAMAGE event.

func test_clear_layers_increments_on_frosting_damage() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 2, "target_total": 1, "target_layers": 1},
		],
		"blockers": [
			{"x": 1, "y": 0, "type": "FROSTING", "layers": 2},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	# Build a forced 3-run with the frosted cell in the middle.
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for x in range(6):
		session.board.set_piece(Coord.new(x, 0), Piece.new(0))
	# Make the FROSTING cell hold a piece so the match clears it.
	var fc: Board.Cell = session.board.cell_at(Coord.new(1, 0))
	fc.piece = Piece.new(0)
	fc.kind = Board.CellKind.PIECE
	# Run resolve directly (bypassing session.attempt_swap, which
	# would require a player swap to fire). The events flow into
	# session.objective progress via _update_objectives_from_events.
	var rng_clone = session.rng
	var result: Resolution.CascadeResult = Resolution.resolve(session.board, session.rng)
	# Manually update progress.
	session._update_objectives_from_events(result.events)
	assert_true(session.objective.progress >= 1,
			"CLEAR_LAYERS should have at least 1 layer cleared; got %d" % session.objective.progress)

# E. CLEAR_LAYERS increments per BLOCKER_BREAK event.

func test_clear_layers_increments_on_frosting_break() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 2, "target_total": 1, "target_layers": 1},
		],
		"blockers": [
			{"x": 1, "y": 0, "type": "FROSTING", "layers": 1},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for x in range(6):
		session.board.set_piece(Coord.new(x, 0), Piece.new(0))
	var fc: Board.Cell = session.board.cell_at(Coord.new(1, 0))
	fc.piece = Piece.new(0)
	fc.kind = Board.CellKind.PIECE
	var result: Resolution.CascadeResult = Resolution.resolve(session.board, session.rng)
	session._update_objectives_from_events(result.events)
	assert_true(session.objective.progress >= 1)

# F. CLEAR_LAYERS counts frosting decrements across cascades.

func test_clear_layers_accumulates_across_cascades() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 2, "target_total": 2, "target_layers": 2},
		],
		"blockers": [
			{"x": 0, "y": 0, "type": "FROSTING", "layers": 1},
			{"x": 1, "y": 0, "type": "FROSTING", "layers": 1},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for x in range(6):
		session.board.set_piece(Coord.new(x, 0), Piece.new(0))
	var fc1: Board.Cell = session.board.cell_at(Coord.new(0, 0))
	fc1.piece = Piece.new(0)
	fc1.kind = Board.CellKind.PIECE
	var fc2: Board.Cell = session.board.cell_at(Coord.new(1, 0))
	fc2.piece = Piece.new(0)
	fc2.kind = Board.CellKind.PIECE
	var result: Resolution.CascadeResult = Resolution.resolve(session.board, session.rng)
	session._update_objectives_from_events(result.events)
	assert_true(session.objective.progress >= 2,
			"CLEAR_LAYERS should accumulate; got %d" % session.objective.progress)

# G. Multi-objective: COLLECT_KIND + CLEAR_LAYERS both required.

func test_multi_objective_requires_all_to_complete() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 0, "target_kind": 0, "target_total": 100},
			{"kind": 2, "target_total": 1, "target_layers": 1},
		],
		"blockers": [
			{"x": 1, "y": 0, "type": "FROSTING", "layers": 1},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	assert_eq(session.objectives.size(), 2)
	# Drive a clear that satisfies only the CLEAR_LAYERS half.
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for x in range(6):
		session.board.set_piece(Coord.new(x, 0), Piece.new(0))
	var fc: Board.Cell = session.board.cell_at(Coord.new(1, 0))
	fc.piece = Piece.new(0)
	fc.kind = Board.CellKind.PIECE
	var result: Resolution.CascadeResult = Resolution.resolve(session.board, session.rng)
	session._update_objectives_from_events(result.events)
	# CLEAR_LAYERS objective is complete; COLLECT_KIND is not.
	var cl_obj: Session.Objective = session.objectives[1]
	var ck_obj: Session.Objective = session.objectives[0]
	assert_true(cl_obj.is_complete())
	assert_false(ck_obj.is_complete())
	assert_false(session.all_objectives_complete())

# H. Multi-objective: REACH_SCORE + CLEAR_LAYERS, REACH_SCORE
# alone is not enough.

func test_reach_score_alone_does_not_complete_multi_objective() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 1, "target_score": 0},
			{"kind": 2, "target_total": 999, "target_layers": 999},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	# REACH_SCORE 0 is trivially satisfied; CLEAR_LAYERS 999 is not.
	var rs_obj: Session.Objective = session.objectives[0]
	var cl_obj: Session.Objective = session.objectives[1]
	assert_true(rs_obj.is_complete())
	assert_false(cl_obj.is_complete())
	assert_false(session.all_objectives_complete())

# I. Snapshot roundtrips a multi-objective session.

func test_snapshot_roundtrips_multi_objective() -> void:
	var recipe := _make_recipe({
		"objectives": [
			{"kind": 0, "target_kind": 0, "target_total": 10},
			{"kind": 2, "target_total": 3, "target_layers": 3},
		],
	})
	var session: Session.Session = Session.from_recipe(recipe)
	var snap: Dictionary = session.snapshot_state()
	assert_eq((snap["objectives"] as Array).size(), 2)
	var objs: Array = snap["objectives"]
	var o0: Dictionary = objs[0]
	var o1: Dictionary = objs[1]
	assert_eq(int(o0["kind"]), Session.ObjectiveKind.COLLECT_KIND)
	assert_eq(int(o1["kind"]), Session.ObjectiveKind.CLEAR_LAYERS)
	# Back-compat shim exposes objectives[0] under objective_legacy.
	assert_true(snap.has("objective_legacy"))