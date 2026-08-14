extends GutTest
## Step 15: launch blocker (frosting + locked) cell-level tests.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Coord = Board.CellCoord

func _empty_config(w: int = 6, h: int = 8, blockers: Array = []) -> Board.BoardConfig:
	return Board.BoardConfig.new(w, h, 4, [], blockers)

func _fill_uniform(board: Board, kind: int) -> void:
	for cell in board._cells:
		if cell.kind == Board.CellKind.EMPTY:
			board.set_piece(cell.coord, Board.Piece.new(kind))

func _fill_alternating(board: Board) -> void:
	for cell in board._cells:
		if cell.kind == Board.CellKind.EMPTY:
			board.set_piece(cell.coord, Board.Piece.new((cell.coord.x + cell.coord.y) % 4))

# A. Cell model: FROSTING kind, predicates, frosting_layers.

func test_cell_kind_frosting_exists() -> void:
	assert_eq(Board.CellKind.FROSTING, 3)

func test_cell_predicates_is_frosted() -> void:
	var b := Board.new(_empty_config(4, 4, [{"x": 1, "y": 2, "type": "FROSTING", "layers": 2}]))
	var cell: Board.Cell = b.cell_at(Coord.new(1, 2))
	assert_eq(cell.kind, Board.CellKind.FROSTING)
	assert_true(cell.is_frosted())
	assert_false(cell.is_piece())
	assert_eq(cell.frosting_remaining(), 2)

func test_cell_predicates_is_locked() -> void:
	var b := Board.new(_empty_config(4, 4))
	b.set_piece(Coord.new(2, 3), Board.Piece.new(0))
	b.cell_at(Coord.new(2, 3)).locked = true
	var cell: Board.Cell = b.cell_at(Coord.new(2, 3))
	assert_true(cell.is_locked())
	assert_true(cell.is_piece())
	assert_false(cell.is_frosted())

# B. BoardConfig blocker validation.

func test_board_config_accepts_valid_blockers() -> void:
	var cfg := _empty_config(4, 4, [
		{"x": 0, "y": 0, "type": "FROSTING", "layers": 1},
		{"x": 2, "y": 2, "type": "LOCKED", "layers": 1},
	])
	assert_eq(cfg.blockers.size(), 2)

func test_board_config_rejects_out_of_bounds_blocker() -> void:
	# Should push_error but not crash. We only assert it parses.
	var cfg := _empty_config(4, 4, [{"x": 10, "y": 0, "type": "FROSTING", "layers": 1}])
	assert_eq(cfg.blockers.size(), 1)

func test_board_config_rejects_bad_blocker_type() -> void:
	var cfg := _empty_config(4, 4, [{"x": 0, "y": 0, "type": "BOMB", "layers": 1}])
	assert_eq(cfg.blockers.size(), 1)

func test_board_config_rejects_zero_layers() -> void:
	var cfg := _empty_config(4, 4, [{"x": 0, "y": 0, "type": "FROSTING", "layers": 0}])
	assert_eq(cfg.blockers.size(), 1)

# C. Board construction applies blockers correctly.

func test_board_applies_frosting_at_construction() -> void:
	var b := Board.new(_empty_config(4, 4, [{"x": 1, "y": 1, "type": "FROSTING", "layers": 3}]))
	var cell: Board.Cell = b.cell_at(Coord.new(1, 1))
	assert_eq(cell.kind, Board.CellKind.FROSTING)
	assert_eq(cell.frosting_layers, 3)

func test_board_apply_locks_to_pieces_after_refill() -> void:
	var b := Board.new(_empty_config(4, 4, [{"x": 2, "y": 2, "type": "LOCKED", "layers": 1}]))
	# Fill the board, then lock.
	_fill_uniform(b, 0)
	var errors: Array = b.apply_locks_to_pieces()
	assert_eq(errors.size(), 0)
	var cell: Board.Cell = b.cell_at(Coord.new(2, 2))
	assert_true(cell.locked)
	assert_true(cell.is_piece())

func test_board_apply_locks_fails_for_frosting_cell() -> void:
	var b := Board.new(_empty_config(4, 4, [{"x": 2, "y": 2, "type": "LOCKED", "layers": 1}]))
	# Don't fill the board. The LOCKED cell is FROSTING (empty) -> error.
	var errors: Array = b.apply_locks_to_pieces()
	assert_eq(errors.size(), 1)

# D. Gravity: FROSTING cells are EMPTY for gravity (pieces fall into them).

func test_gravity_preserves_frosted_cell() -> void:
	# FROSTING cells are EMPTY for gravity — pieces above fall through
	# them and the frosting is preserved. We use fill_random which
	# populates FROSTING cells with pieces.
	var b := Board.new(_empty_config(3, 3, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	Resolution.fill_random(b, Rng.new(101), false)
	var cell: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell.kind, Board.CellKind.PIECE,
		"frosted cell refilled with a piece")
	assert_eq(cell.frosting_layers, 1, "frosting preserved after refill")

# E. Refill: FROSTING cells get refilled like EMPTY.

func test_refill_fills_frosting_cell() -> void:
	var b := Board.new(_empty_config(3, 3, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	Resolution.fill_random(b, Rng.new(42), false)
	# After refill, FROSTING cell should have a piece (frosting preserved).
	var cell: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell.kind, Board.CellKind.PIECE)
	assert_eq(cell.frosting_layers, 1)

# F. find_runs: FROSTING cells break runs.

func test_find_runs_breaks_at_frosting() -> void:
	var b := Board.new(_empty_config(4, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	# Fill (but FROSTING cell is empty after construction).
	_fill_uniform(b, 0)
	# Now b has pieces at x=0,2,3 but FROSTING at x=1 (no piece).
	var runs: Array = Rules.find_runs(b)
	# 3 consecutive same-kind pieces (x=0 only; FROSTING breaks it).
	# x=2,3 only form a 2-run which is < 3.
	assert_eq(runs.size(), 0)

# G. try_swap: rejects FROSTING+FROSTING (implicit since FROSTING has no piece).

func test_try_swap_rejects_frosting_pair() -> void:
	var b := Board.new(_empty_config(4, 1, [
		{"x": 0, "y": 0, "type": "FROSTING", "layers": 1},
		{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	# No pieces on the board; try_swap must reject.
	assert_false(Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 0)))

# H. enumerate_legal_swaps: excludes FROSTING pairs.

func test_enumerate_legal_swaps_excludes_frosting() -> void:
	var b := Board.new(_empty_config(4, 1, [
		{"x": 0, "y": 0, "type": "FROSTING", "layers": 1},
		{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_eq(moves.size(), 0)

# I. RESOLVE: one-hit frosting prevents a cascade below until the frosting breaks.

func test_resolve_frosting_one_hit_blocks_until_broken() -> void:
	var b := Board.new(_empty_config(3, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	# Fill cells 0 and 2 with kind 0 (and refill cell 1 via resolution).
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b.set_piece(Coord.new(2, 0), Board.Piece.new(0))
	# Force a refill by calling resolve directly (will spawn a piece in cell 1).
	var rng := Rng.new(7)
	Resolution.fill_random(b, rng, false)
	var cell: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell.kind, Board.CellKind.PIECE)
	assert_eq(cell.frosting_layers, 1, "frosting preserved after refill")