extends GutTest
## Domain board data model — Step 05 fixtures.

const Board = preload("res://scripts/domain/board/board.gd")
const Coord = preload("res://scripts/domain/board/board.gd").CellCoord

func _make_empty_config(w: int = 6, h: int = 8, palette: int = 6, blocked: Array = []) -> Board.BoardConfig:
	return Board.BoardConfig.new(w, h, palette, blocked)

func test_board_default_construction() -> void:
	var cfg := _make_empty_config(6, 8, 6, [])
	var board := Board.new(cfg)
	assert_eq(board.config.width, 6)
	assert_eq(board.config.height, 8)
	assert_eq(board.config.normal_palette_size, 6)
	assert_eq(board.validate(), true)
	assert_eq(board._cells.size(), 48)

func test_board_cells_initially_empty() -> void:
	var board := Board.new(_make_empty_config(4, 4))
	for c in board.all_coords():
		assert_eq(board.cell_at(c).kind, Board.CellKind.EMPTY)

func test_board_piece_set_and_query() -> void:
	var board := Board.new(_make_empty_config(4, 4))
	var coord := Coord.new(1, 2)
	board.set_piece(coord, Board.Piece.new(3))
	var cell: Board.Cell = board.cell_at(coord)
	assert_eq(cell.kind, Board.CellKind.PIECE)
	assert_eq(cell.piece.kind_id, 3)

func test_board_out_of_bounds_returns_null() -> void:
	var board := Board.new(_make_empty_config(4, 4))
	assert_eq(board.cell_at(Coord.new(-1, 0)), null)
	assert_eq(board.cell_at(Coord.new(4, 0)), null)
	assert_eq(board.cell_at(Coord.new(0, 4)), null)

func test_board_empty_coords_are_listed() -> void:
	var board := Board.new(_make_empty_config(3, 3))
	assert_eq(board.empty_coords().size(), 9)
	board.set_piece(Coord.new(1, 1), Board.Piece.new(0))
	assert_eq(board.empty_coords().size(), 8)

func test_board_blocked_cells_start_blocked() -> void:
	var blocked: Array = [Coord.new(0, 0), Coord.new(2, 2)]
	var board := Board.new(_make_empty_config(4, 4, 6, blocked))
	assert_eq(board.cell_at(Coord.new(0, 0)).kind, Board.CellKind.BLOCKED)
	assert_eq(board.cell_at(Coord.new(2, 2)).kind, Board.CellKind.BLOCKED)
	assert_eq(board.cell_at(Coord.new(1, 1)).kind, Board.CellKind.EMPTY)

func test_board_piece_must_be_in_palette() -> void:
	var board := Board.new(_make_empty_config(4, 4, 4))
	board.set_piece(Coord.new(1, 1), Board.Piece.new(5))
	assert_eq(board.validate(), false)

func test_board_snapshot_is_deterministic() -> void:
	var b1 := Board.new(_make_empty_config(4, 4))
	var b2 := Board.new(_make_empty_config(4, 4))
	b1.set_piece(Coord.new(0, 0), Board.Piece.new(2))
	b1.set_piece(Coord.new(3, 3), Board.Piece.new(5))
	b2.set_piece(Coord.new(3, 3), Board.Piece.new(5))
	b2.set_piece(Coord.new(0, 0), Board.Piece.new(2))
	assert_eq(b1.snapshot_hash(), b2.snapshot_hash(),
		"snapshot hash must be order-independent of insertion order")

func test_board_snapshot_order_matters() -> void:
	var b1 := Board.new(_make_empty_config(4, 4))
	var b2 := Board.new(_make_empty_config(4, 4))
	b1.set_piece(Coord.new(0, 0), Board.Piece.new(2))
	b2.set_piece(Coord.new(0, 0), Board.Piece.new(3))
	assert_ne(b1.snapshot_hash(), b2.snapshot_hash())

func test_cellcoord_lex_order() -> void:
	var a := Coord.new(1, 2)
	var b := Coord.new(3, 1)
	# compare returns true if a < b. y first: 2 > 1 so a > b.
	assert_false(Coord.compare(a, b))
	assert_true(Coord.compare(b, a))
	var c := Coord.new(1, 3)
	assert_true(Coord.compare(a, c))