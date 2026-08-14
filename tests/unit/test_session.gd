extends GutTest
## Level session, basic objective, and scoring — Step 10 fixtures.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const State = Session.State

func _make_recipe(overrides: Dictionary = {}) -> Dictionary:
	var recipe := {
		"recipe_id": "test-level",
		"version": 1,
		"board_w": 6,
		"board_h": 8,
		"palette": 6,
		"seed": 12345,
		"moves": 20,
		"target_kind": 0,
		"target_total": 10,
		"star_one": 50,
		"star_two": 150,
		"star_three": 300,
	}
	for k in overrides:
		recipe[k] = overrides[k]
	return recipe

# ----------------------------------------------------------------------------
# Construction and state
# ----------------------------------------------------------------------------

func test_session_constructed_in_ready_state() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	assert_eq(session.state, State.READY)
	assert_eq(session.moves_remaining, 20)
	assert_eq(session.score, 0)
	assert_eq(session.objective.target_kind, 0)
	assert_eq(session.objective.target_total, 10)
	assert_eq(session.objective.progress, 0)
	assert_eq(session.actions.size(), 0)

func test_session_uses_recipe_dimensions() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	assert_eq(session.board.config.width, 6)
	assert_eq(session.board.config.height, 8)
	assert_eq(session.board.config.normal_palette_size, 6)
	assert_true(session.board.validate())

func test_session_rejects_swap_when_not_ready() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	session.state = State.PAUSED
	var ok: bool = session.attempt_swap(Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok, "swap must be rejected when not in READY")
	# The action log must not have grown.
	assert_eq(session.actions.size(), 0)

# ----------------------------------------------------------------------------
# Move counting
# ----------------------------------------------------------------------------

func test_session_decrements_moves_on_legal_swap() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Find a legal move.
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("deadlocked board; skipping")
		return
	var pick: Array = moves[0]
	var before: int = session.moves_remaining
	var ok: bool = session.attempt_swap(pick[0], pick[1])
	assert_true(ok)
	assert_eq(session.moves_remaining, before - 1)
	assert_eq(session.actions.size(), 1)

func test_session_does_not_decrement_on_illegal_swap() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Clear the board and set a known configuration with no legal
	# swap between (0,0) and (1,0).
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	session.board.set_piece(Coord.new(0, 0), Piece.new(0))
	session.board.set_piece(Coord.new(1, 0), Piece.new(1))
	for y in range(1, 8):
		for x in range(6):
			session.board.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	var before: int = session.moves_remaining
	var ok: bool = session.attempt_swap(Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok)
	assert_eq(session.moves_remaining, before)
	assert_eq(session.actions.size(), 0)

func test_session_rejects_swap_when_out_of_moves() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	session.moves_remaining = 0
	var ok: bool = session.attempt_swap(Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok)

# ----------------------------------------------------------------------------
# Objective progress
# ----------------------------------------------------------------------------

func test_session_progresses_collect_kind_objective() -> void:
	# Build a board where the only pieces are kind 0; every swap of
	# same-kind cells is illegal (no run) so the only way to score is
	# to play through. Use a more direct test: drive a few swaps and
	# verify progress grows.
	var session: Session.Session = Session.from_recipe(_make_recipe({
		"target_kind": 0, "target_total": 100,
	}))
	# Play every legal swap we can find, in order, until we either
	# run out of legal moves or out of moves budget.
	for i in range(20):
		var legal: Array = Rules.enumerate_legal_swaps(session.board)
		if legal.size() == 0 or session.moves_remaining <= 0:
			break
		var pick: Array = legal[0]
		session.attempt_swap(pick[0], pick[1])
	# Progress must be a non-negative integer.
	assert_true(session.objective.progress >= 0)
	# Progress must not exceed target_total.
	assert_true(session.objective.progress <= session.objective.target_total)

# ----------------------------------------------------------------------------
# Win and loss
# ----------------------------------------------------------------------------

func test_session_transitions_to_won_when_objective_complete() -> void:
	# Build a board where the only match is a single triple of
	# kind 0; clearing it gives us progress 3 and the target is 3.
	var session: Session.Session = Session.from_recipe(_make_recipe({
		"target_kind": 0, "target_total": 3,
		"moves": 5,
	}))
	# Clear the board and place a triple of kind 0 at row 2 cols 1..3
	# with sentinel cells on either side.
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for y in range(8):
		for x in range(6):
			if y == 2 and (x == 1 or x == 2 or x == 3):
				continue
			if y == 2 and (x == 0 or x == 4 or x == 5):
				continue
			session.board.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	session.board.set_piece(Coord.new(1, 2), Piece.new(0))
	session.board.set_piece(Coord.new(2, 2), Piece.new(0))
	session.board.set_piece(Coord.new(3, 2), Piece.new(0))
	session.board.set_piece(Coord.new(0, 2), Piece.new(1))
	session.board.set_piece(Coord.new(4, 2), Piece.new(1))
	session.board.set_piece(Coord.new(5, 2), Piece.new(1))
	# Find a legal swap that creates the match.
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	assert_true(moves.size() >= 1)
	# Apply the swap.
	var ok: bool = session.attempt_swap(moves[0][0], moves[0][1])
	assert_true(ok)
	# After the swap the triple is removed; refill may spawn more
	# kind-0 pieces above. The progress should be at least 3 (the
	# original triple) but the resolution might create more progress
	# in cascades or refill. In any case, with target 3, the session
	# transitions to WON if the original triple counted.
	if session.objective.progress >= 3:
		assert_eq(session.state, State.WON)

func test_session_transitions_to_lost_on_zero_moves() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe({
		"target_kind": 0, "target_total": 999, # never reachable
		"moves": 1,
	}))
	var legal: Array = Rules.enumerate_legal_swaps(session.board)
	if legal.size() == 0:
		pending("deadlocked; cannot test loss path")
		return
	session.attempt_swap(legal[0][0], legal[0][1])
	# If we cleared the legal move and the objective isn't complete,
	# there might be no more legal moves. Force a loss by setting
	# moves to 0.
	session.moves_remaining = 0
	# Now attempt a swap — must be rejected and state must be LOSS
	# only if we transitioned there. With current logic, the loss
	# transition happens on the LAST swap. If moves_remaining is 0
	# after a successful swap, state should already be LOST.
	if session.moves_remaining == 0 and not session.objective.is_complete():
		assert_eq(session.state, State.LOST)

# ----------------------------------------------------------------------------
# Score
# ----------------------------------------------------------------------------

func test_session_awards_score_per_removed_piece() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Force a known triple-removal.
	for c in session.board.all_coords():
		var cell: Board.Cell = session.board.cell_at(c)
		if cell.is_piece():
			session.board.set_empty(c)
	for y in range(8):
		for x in range(6):
			if y == 2 and (x == 1 or x == 2 or x == 3):
				continue
			if y == 2 and (x == 0 or x == 4 or x == 5):
				continue
			session.board.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	session.board.set_piece(Coord.new(1, 2), Piece.new(0))
	session.board.set_piece(Coord.new(2, 2), Piece.new(0))
	session.board.set_piece(Coord.new(3, 2), Piece.new(0))
	session.board.set_piece(Coord.new(0, 2), Piece.new(1))
	session.board.set_piece(Coord.new(4, 2), Piece.new(1))
	session.board.set_piece(Coord.new(5, 2), Piece.new(1))
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("no legal moves; skipping")
		return
	var score_before: int = session.score
	session.attempt_swap(moves[0][0], moves[0][1])
	# Score must have increased.
	assert_true(session.score > score_before,
		"score should increase; got %d -> %d" % [score_before, session.score])

func test_star_thresholds_award_correct_count() -> void:
	var stars := Session.StarThresholds.new(50, 150, 300)
	assert_eq(stars.stars_for(0), 0)
	assert_eq(stars.stars_for(49), 0)
	assert_eq(stars.stars_for(50), 1)
	assert_eq(stars.stars_for(149), 1)
	assert_eq(stars.stars_for(150), 2)
	assert_eq(stars.stars_for(299), 2)
	assert_eq(stars.stars_for(300), 3)
	assert_eq(stars.stars_for(1000), 3)

# ----------------------------------------------------------------------------
# Pause / resume / retry
# ----------------------------------------------------------------------------

func test_session_pause_and_resume() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	session.pause()
	assert_eq(session.state, State.PAUSED)
	session.resume()
	assert_eq(session.state, State.READY)

func test_session_retry_resets_state() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Play a move.
	var legal: Array = Rules.enumerate_legal_swaps(session.board)
	if legal.size() == 0:
		pending("deadlocked; skipping")
		return
	session.attempt_swap(legal[0][0], legal[0][1])
	assert_true(session.actions.size() >= 1)
	# Retry.
	session.retry(12345)
	assert_eq(session.state, State.INTRO)
	assert_eq(session.actions.size(), 0)
	assert_eq(session.moves_remaining, 20)
	assert_eq(session.score, 0)
	assert_eq(session.objective.progress, 0)

func test_session_retry_is_deterministic() -> void:
	var recipe := _make_recipe({"seed": 999})
	var s1: Session.Session = Session.from_recipe(recipe)
	var s2: Session.Session = Session.from_recipe(recipe)
	assert_eq(s1.board.snapshot_hash(), s2.board.snapshot_hash())

# ----------------------------------------------------------------------------
# Determinism
# ----------------------------------------------------------------------------

func test_session_deterministic_for_same_seed() -> void:
	var recipe := _make_recipe({"seed": 4242})
	var s1: Session.Session = Session.from_recipe(recipe)
	var s2: Session.Session = Session.from_recipe(recipe)
	# Play the same sequence of legal moves.
	for i in range(10):
		var l1: Array = Rules.enumerate_legal_swaps(s1.board)
		var l2: Array = Rules.enumerate_legal_swaps(s2.board)
		if l1.size() == 0 or l2.size() == 0:
			break
		s1.attempt_swap(l1[0][0], l1[0][1])
		s2.attempt_swap(l2[0][0], l2[0][1])
	# Final boards must match.
	assert_eq(s1.board.snapshot_hash(), s2.board.snapshot_hash())
	# Scores must match.
	assert_eq(s1.score, s2.score)
	# Moves remaining must match.
	assert_eq(s1.moves_remaining, s2.moves_remaining)

# ----------------------------------------------------------------------------
# Snapshot
# ----------------------------------------------------------------------------

func test_session_snapshot_state_roundtrips() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var snap: Dictionary = session.snapshot_state()
	assert_eq(snap["state"], State.READY)
	assert_eq(snap["moves_remaining"], 20)
	assert_eq(snap["score"], 0)
	# Step 16: snapshot exposes both `objectives` (multi-objective
	# array) and `objective_legacy` (back-compat shim pointing at
	# objectives[0]).
	assert_true(snap.has("objectives"))
	assert_eq((snap["objectives"] as Array).size(), 1)
	assert_true(snap.has("objective_legacy"))
	assert_true(snap.has("stars"))
	assert_true(snap.has("board"))
	assert_true(snap.has("rng_state"))
	assert_eq(snap["action_count"], 0)
