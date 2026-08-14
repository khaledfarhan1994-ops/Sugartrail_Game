extends GutTest
## Replay and deadlock — Step 08 fixtures.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const ActionKind = Replay.ActionKind

func _empty_board(w: int = 6, h: int = 6, palette: int = 6, blocked: Array = []) -> Board:
	return Board.new(Board.BoardConfig.new(w, h, palette, blocked))

# ----------------------------------------------------------------------------
# Deadlock detection
# ----------------------------------------------------------------------------

func test_has_legal_moves_true_on_board_with_match() -> void:
	var b := _empty_board()
	# Build the same fixture used in test_rules.gd: a horizontal
	# 3-run at row 2 cols 1..3 of kind 2, with (x+y)%6 background
	# and sentinel pieces at cols 0,4,5 in row 2.
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 6))
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	assert_true(Replay.has_legal_moves(b),
		"a board with a match must have a legal move (the move that created the match)")

func test_has_legal_moves_false_on_deadlocked_board() -> void:
	# Construct a 4x3 board with 3 palette colours arranged so no
	# orthogonal swap produces a 3-run. A 4-wide board with the
	# pattern below avoids 3-runs in both axes:
	#   A B C A
	#   B C A B
	#   C A B C
	# Every swap changes two cells; let's enumerate to confirm.
	var b := _empty_board(4, 3, 3)
	for y in range(3):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	# Verify it has no legal moves.
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_eq(moves.size(), 0,
		"precondition: deadlocked 4x3 board, got moves=%d" % moves.size())
	assert_false(Replay.has_legal_moves(b))

func test_has_legal_moves_true_after_one_swap_creates_a_match() -> void:
	# Same 4x3 deadlocked board but flip one cell to break the lock.
	var b := _empty_board(4, 3, 3)
	for y in range(3):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	b.set_piece(Coord.new(0, 1), Piece.new(0))  # was 1, now 0
	# Now there should be a legal move (the swap that creates the
	# first run).
	assert_true(Replay.has_legal_moves(b))

# ----------------------------------------------------------------------------
# Reshuffle
# ----------------------------------------------------------------------------

func test_reshuffle_preserves_blocked_cells() -> void:
	var b := _empty_board(6, 6, 4, [Coord.new(2, 2), Coord.new(4, 4)])
	for y in range(6):
		for x in range(6):
			if (x == 2 and y == 2) or (x == 4 and y == 4):
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 4))
	var rng := Rng.new(2025)
	var ok: bool = Replay.reshuffle(b, rng)
	assert_true(ok, "reshuffle should succeed on a normal 6x6 board")
	# Blocked cells must remain blocked.
	assert_eq(b.cell_at(Coord.new(2, 2)).kind, Board.CellKind.BLOCKED)
	assert_eq(b.cell_at(Coord.new(4, 4)).kind, Board.CellKind.BLOCKED)

func test_reshuffle_preserves_piece_counts_per_kind() -> void:
	var b := _empty_board(6, 6, 4)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 4))
	var counts_before: Dictionary = {}
	for cell in b._cells:
		if cell.is_piece():
			var k: int = cell.piece.kind_id
			counts_before[k] = counts_before.get(k, 0) + 1
	var rng := Rng.new(7)
	Replay.reshuffle(b, rng)
	var counts_after: Dictionary = {}
	for cell in b._cells:
		if cell.is_piece():
			var k2: int = cell.piece.kind_id
			counts_after[k2] = counts_after.get(k2, 0) + 1
	for k in counts_before:
		assert_eq(counts_after.get(k, 0), counts_before[k],
			"kind %d count must be preserved (%d -> %d)" % [k, counts_before[k], counts_after.get(k, 0)])

func test_reshuffle_breaks_deadlock() -> void:
	# Use the 4x3 deadlocked board from the previous test.
	var b := _empty_board(4, 3, 3)
	for y in range(3):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	# Sanity: deadlocked.
	assert_false(Replay.has_legal_moves(b), "precondition: deadlocked")
	var rng := Rng.new(123)
	var ok: bool = Replay.reshuffle(b, rng)
	assert_true(ok, "reshuffle must succeed")
	assert_true(Replay.has_legal_moves(b), "post-reshuffle board must have a legal move")
	# No immediate matches.
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 0, "post-reshuffle board must have no immediate matches")

func test_reshuffle_is_deterministic_same_seed() -> void:
	var make := func() -> Board:
		var bb := _empty_board(6, 6, 4)
		for y in range(6):
			for x in range(6):
				bb.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 4))
		return bb

	var b1: Board = make.call()
	var b2: Board = make.call()
	Replay.reshuffle(b1, Rng.new(99))
	Replay.reshuffle(b2, Rng.new(99))
	assert_eq(b1.snapshot_hash(), b2.snapshot_hash(),
		"same seed must produce identical post-reshuffle boards")

# ----------------------------------------------------------------------------
# Action log and replay
# ----------------------------------------------------------------------------

func test_action_log_roundtrips_through_dict() -> void:
	var log := Replay.ActionLog.new()
	log.recipe = {"recipe_id": "level-1-1", "recipe_version": 1}
	log.engine_version = "0.4.0-test"
	log.initial_rng_state = 12345
	var b := _empty_board(4, 4)
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	log.initial_board = b.to_snapshot()
	log.actions.append(Replay.Action.new(ActionKind.SWAP, Coord.new(0, 0), Coord.new(1, 0)))
	log.final_rng_state = 99999
	log.total_events = 7
	var d: Dictionary = log.to_dict()
	var restored: Replay.ActionLog = Replay.ActionLog.from_dict(d)
	assert_eq(restored.recipe["recipe_id"], "level-1-1")
	assert_eq(restored.engine_version, "0.4.0-test")
	assert_eq(restored.initial_rng_state, 12345)
	assert_eq(restored.final_rng_state, 99999)
	assert_eq(restored.total_events, 7)
	assert_eq(restored.actions.size(), 1)
	var act: Replay.Action = restored.actions[0]
	assert_eq(act.kind, ActionKind.SWAP)
	assert_true(act.a.is_equal_to(Coord.new(0, 0)))
	assert_true(act.b.is_equal_to(Coord.new(1, 0)))

func test_replay_reproduces_final_state() -> void:
	# Build a small action log by hand: a single legal swap that
	# clears the 3-run we set up.
	var b := _empty_board(6, 6)
	for y in range(1, 6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	b.set_piece(Coord.new(1, 0), Piece.new(2))
	b.set_piece(Coord.new(2, 0), Piece.new(2))
	b.set_piece(Coord.new(3, 0), Piece.new(2))
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	b.set_piece(Coord.new(4, 0), Piece.new(0))
	b.set_piece(Coord.new(5, 0), Piece.new(0))
	# Confirm one run exists.
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1, "precondition: one run")
	# Pick a swap that creates the run: swap (0,0)<->(1,0) brings a
	# kind-0 piece next to two kind-2 pieces; the resulting row is
	# 0,2,2,2,0,0 — no run, actually. The run already exists, so a
	# NO-OP swap wouldn't be legal. The move that created the run
	# is hypothetical; we just want a swap that IS legal.
	# Use Rules.enumerate_legal_swaps to find one.
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1, "precondition: at least one legal swap")
	var pick: Array = moves[0]
	var a_coord: Coord = pick[0]
	var b_coord: Coord = pick[1]
	# Compose the log.
	var log := Replay.ActionLog.new()
	log.recipe = {"recipe_id": "test", "recipe_version": 1}
	log.engine_version = "0.4.0-test"
	log.initial_rng_state = 42
	log.initial_board = b.to_snapshot()
	log.actions.append(Replay.Action.new(ActionKind.SWAP, a_coord, b_coord))
	# Replay twice from clean state and compare hashes.
	var r1: Replay.ReplayResult = Replay.replay(log, "0.4.0-test")
	var r2: Replay.ReplayResult = Replay.replay(log, "0.4.0-test")
	assert_true(r1.ok, "first replay ok")
	assert_true(r2.ok, "second replay ok")
	assert_eq(r1.result_hash, r2.result_hash, "result hashes must match")
	assert_eq(r1.total_events, r2.total_events, "event counts must match")
	assert_eq(r1.board.snapshot_hash(), r2.board.snapshot_hash(),
		"final board hashes must match")
	assert_eq(r1.final_rng_state, r2.final_rng_state,
		"final RNG states must match")

func test_replay_detects_engine_version_mismatch() -> void:
	var log := Replay.ActionLog.new()
	log.recipe = {"recipe_id": "test"}
	log.engine_version = "0.2.0-old"
	log.initial_rng_state = 0
	var b := _empty_board(4, 4)
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	log.initial_board = b.to_snapshot()
	var result: Replay.ReplayResult = Replay.replay(log, "0.4.0-new")
	assert_false(result.ok, "version mismatch should fail")
	assert_true(result.last_error_message.find("engine version") >= 0,
		"error message must mention engine version: %s" % result.last_error_message)

func test_replay_detects_illegal_swap() -> void:
	var log := Replay.ActionLog.new()
	log.engine_version = "0.4.0-test"
	log.initial_rng_state = 0
	var b := _empty_board(4, 4)
	# No pieces; nothing to swap. Put a couple of pieces so try_swap
	# can be called.
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	log.initial_board = b.to_snapshot()
	# This swap does NOT create a match — it must be flagged illegal.
	log.actions.append(Replay.Action.new(ActionKind.SWAP, Coord.new(0, 0), Coord.new(1, 0)))
	var result: Replay.ReplayResult = Replay.replay(log, "")
	assert_false(result.ok, "illegal swap must cause replay to fail")
	assert_eq(result.last_error_action, 0)

func test_replay_hash_includes_board_and_rng() -> void:
	# Two different RNG seeds at the start of replay produce different
	# result hashes because refill uses the RNG. We trigger a
	# resolution by setting up a board with a 3-run at the top of a
	# column that, when cleared, triggers gravity + refill above.
	var b := _empty_board(4, 6)
	# Vertical 3-run at col 0 rows 0..2 of kind 0; sentinel cells in
	# col 0 rows 3..5 of kind 1.
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	b.set_piece(Coord.new(0, 1), Piece.new(0))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(0, 3), Piece.new(1))
	b.set_piece(Coord.new(0, 4), Piece.new(2))
	b.set_piece(Coord.new(0, 5), Piece.new(3))
	# Fill the rest with kinds that keep the board stable.
	for y in range(6):
		for x in range(1, 4):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 4))
	# Confirm one run exists.
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1, "precondition: one run, got %d" % runs.size())
	# Find a legal move that, when applied, removes the run. The
	# canonical "swap to make the match" example: swap (0,2) with
	# (1,2) where (1,2) is currently not kind 0 — that creates a
	# 3-run in row 2 cols 0..2 (kind 0). The match in row 2 also
	# includes (0,2) which is part of the original vertical run, so
	# the resolution will clear (0,0)(0,1)(0,2) and (0,2)(1,2)(2,2),
	# requiring refill above row 2.
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1, "precondition: at least one legal swap")
	var pick: Array = moves[0]
	var a_coord: Coord = pick[0]
	var b_coord: Coord = pick[1]
	var make_log := func(rng_state: int) -> Replay.ActionLog:
		var l := Replay.ActionLog.new()
		l.engine_version = "0.4.0-test"
		l.initial_rng_state = rng_state
		l.initial_board = b.to_snapshot()
		l.actions.append(Replay.Action.new(ActionKind.SWAP, a_coord, b_coord))
		return l

	var l1: Replay.ActionLog = make_log.call(1)
	var l2: Replay.ActionLog = make_log.call(2)
	var r1: Replay.ReplayResult = Replay.replay(l1, "")
	var r2: Replay.ReplayResult = Replay.replay(l2, "")
	assert_true(r1.ok, "replay 1 must succeed; last_error=%s" % r1.last_error_message)
	assert_true(r2.ok, "replay 2 must succeed; last_error=%s" % r2.last_error_message)
	assert_true(r1.total_events > 0, "replay must produce events; got %d" % r1.total_events)
	assert_ne(r1.result_hash, r2.result_hash,
		"different initial RNG seeds must yield different result hashes")
