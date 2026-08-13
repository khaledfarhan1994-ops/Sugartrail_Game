extends GutTest
## Domain rules — Step 06 fixtures.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Coord = Board.CellCoord

func _assert_coord(actual: Coord, expected_x: int, expected_y: int, msg: String = "") -> void:
	assert_true(actual.is_equal_to(Coord.new(expected_x, expected_y)),
		"%s: expected (%d,%d) got %s" % [msg, expected_x, expected_y, actual.to_string()])

func _board_with_match() -> Board:
	# 6x6 board with one isolated horizontal triple at (1,2)(2,2)(3,2).
	# Everything else uses a kind_id of (x+y)%6 so no spurious runs form.
	var b := Board.new(Board.BoardConfig.new(6, 6, 6, []))
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Board.Piece.new((x + y) % 6))
	b.set_piece(Coord.new(1, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(2, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(3, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(0, 2), Board.Piece.new(0))
	b.set_piece(Coord.new(4, 2), Board.Piece.new(0))
	b.set_piece(Coord.new(5, 2), Board.Piece.new(0))
	return b

func test_adjacency_diagonal_is_rejected() -> void:
	assert_false(Rules.is_orthogonal_neighbor(Coord.new(0, 0), Coord.new(1, 1)))
	assert_false(Rules.is_orthogonal_neighbor(Coord.new(0, 0), Coord.new(2, 0)))

func test_adjacency_orthogonal_is_accepted() -> void:
	assert_true(Rules.is_orthogonal_neighbor(Coord.new(0, 0), Coord.new(1, 0)))
	assert_true(Rules.is_orthogonal_neighbor(Coord.new(0, 0), Coord.new(0, 1)))
	assert_true(Rules.is_orthogonal_neighbor(Coord.new(2, 3), Coord.new(2, 4)))

func test_in_bounds() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 6, []))
	assert_true(Rules.in_bounds(b, Coord.new(0, 0)))
	assert_true(Rules.in_bounds(b, Coord.new(3, 3)))
	assert_false(Rules.in_bounds(b, Coord.new(-1, 0)))
	assert_false(Rules.in_bounds(b, Coord.new(4, 0)))

func test_find_runs_horizontal_three() -> void:
	var b := _board_with_match()
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1, "expected exactly one horizontal run")
	assert_eq(runs[0].size(), 3)
	_assert_coord(runs[0][0], 1, 2, "leftmost run cell")
	_assert_coord(runs[0][2], 3, 2, "rightmost run cell")

func test_find_runs_vertical_four() -> void:
	var b := Board.new(Board.BoardConfig.new(6, 6, 6, []))
	# Single vertical 4-run at col 2.
	for y in range(4):
		b.set_piece(Coord.new(2, y), Board.Piece.new(1))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1, "expected exactly one vertical run, got %d: %s" % [runs.size(), str(runs)])
	assert_eq(runs[0].size(), 4)

func test_find_runs_intersection_no_double_count() -> void:
	# A '+' intersection: a horizontal 3-run at row 2 and a vertical
	# 3-run at col 2, sharing only the centre cell (2,2).
	var b := Board.new(Board.BoardConfig.new(5, 5, 6, []))
	# Background: alternate kind 0/1 in a checkerboard so no incidental
	# runs exist anywhere on the 5x5 board.
	for y in range(5):
		for x in range(5):
			# Skip the cell that will become part of the runs.
			if (x == 1 or x == 2 or x == 3) and y == 2:
				continue
			if x == 2 and (y == 1 or y == 3):
				continue
			var kind: int = (x + y) % 2
			b.set_piece(Coord.new(x, y), Board.Piece.new(kind))
	# The plus itself: all five cells share kind 2 so the horizontal
	# arm (1,2)-(3,2) and the vertical arm (2,1)-(2,3) both qualify
	# and share exactly the centre cell (2,2).
	b.set_piece(Coord.new(1, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(2, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(3, 2), Board.Piece.new(2))
	b.set_piece(Coord.new(2, 1), Board.Piece.new(2))
	b.set_piece(Coord.new(2, 3), Board.Piece.new(2))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 2,
		"expected exactly two runs (H + V), got %d" % runs.size())
	var total_cells := 0
	for run in runs:
		total_cells += run.size()
	# 3 + 3 = 6 (centre counted twice by design — once per run).
	assert_eq(total_cells, 6)

func test_find_runs_blocked_cells_excluded() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 6, [Coord.new(0, 0)]))
	for y in range(4):
		for x in range(4):
			if x == 0 and y == 0:
				continue
			b.set_piece(Coord.new(x, y), Board.Piece.new(1))
	var runs: Array = Rules.find_runs(b)
	var block: Coord = Coord.new(0, 0)
	for run in runs:
		for c in run:
			var cc: Coord = c
			assert_false(cc.is_equal_to(block), "blocked cell appeared in a run")

func test_swap_legal_is_committed() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4, []))
	b.set_piece(Coord.new(1, 1), Board.Piece.new(0))
	b.set_piece(Coord.new(2, 1), Board.Piece.new(0))
	b.set_piece(Coord.new(3, 1), Board.Piece.new(0))
	b.set_piece(Coord.new(0, 1), Board.Piece.new(1))
	b.set_piece(Coord.new(0, 0), Board.Piece.new(1))
	b.set_piece(Coord.new(0, 2), Board.Piece.new(1))
	# Fill the rest so no unintended runs exist.
	for y in range(4):
		for x in range(4):
			if b.cell_at(Coord.new(x, y)).piece != null:
				continue
			b.set_piece(Coord.new(x, y), Board.Piece.new(3))
	# Swapping (0,1) and (1,1) creates a vertical 3-run in col 0
	# (kind 1) plus a horizontal 3-run in row 1 (kind 0). Legal.
	var ok: bool = Rules.try_swap(b, Coord.new(0, 1), Coord.new(1, 1))
	assert_true(ok)
	# The board state is committed.
	assert_eq(b.cell_at(Coord.new(0, 1)).piece.kind_id, 0)
	assert_eq(b.cell_at(Coord.new(1, 1)).piece.kind_id, 1)

func test_swap_illegal_is_reverted() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4, []))
	# Fill so no 3-run can be formed by swapping neighbours.
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b.set_piece(Coord.new(1, 0), Board.Piece.new(1))
	b.set_piece(Coord.new(2, 0), Board.Piece.new(0))
	b.set_piece(Coord.new(3, 0), Board.Piece.new(1))
	for y in range(1, 4):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Board.Piece.new((x * 3 + y) % 4))
	var before_hash: int = b.snapshot_hash()
	var ok: bool = Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok)
	assert_eq(b.snapshot_hash(), before_hash,
		"rejected swap must leave the board unchanged")

func test_swap_out_of_bounds_rejected() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4, []))
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b.set_piece(Coord.new(1, 0), Board.Piece.new(0))
	var ok: bool = Rules.try_swap(b, Coord.new(-1, 0), Coord.new(0, 0))
	assert_false(ok)

func test_swap_diagonal_rejected() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4, []))
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	b.set_piece(Coord.new(1, 1), Board.Piece.new(0))
	var ok: bool = Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 1))
	assert_false(ok)

func test_enumerate_legal_swaps_no_duplicates() -> void:
	var b := _board_with_match()
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1, "expected at least one legal move on a board with a triple")
	var seen := {}
	for m in moves:
		var a: Coord = m[0]
		var n: Coord = m[1]
		assert_true(Rules.is_orthogonal_neighbor(a, n))
		var key: String
		if a.x < n.x or (a.x == n.x and a.y < n.y):
			key = "%d,%d|%d,%d" % [a.x, a.y, n.x, n.y]
		else:
			key = "%d,%d|%d,%d" % [n.x, n.y, a.x, a.y]
		assert_false(seen.has(key), "duplicate swap: %s" % key)
		seen[key] = true

func test_enumerate_legal_swaps_is_canonical() -> void:
	# We do not pin a specific count for arbitrary boards, but every
	# enumerated pair must be (lower-x first, tie on lower-y first).
	var b := _board_with_match()
	var moves: Array = Rules.enumerate_legal_swaps(b)
	for m in moves:
		var a: Coord = m[0]
		var n: Coord = m[1]
		# a must come before n lex.
		var a_first: bool = a.x < n.x or (a.x == n.x and a.y < n.y)
		assert_true(a_first, "swap (%s,%s) not in canonical order" % [a.to_string(), n.to_string()])