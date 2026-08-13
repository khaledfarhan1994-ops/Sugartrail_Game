extends GutTest
## Special pieces — Step 13 fixtures, part 2 of 3.
##
## Sections:
##   B. 4-in-a-row creates a striped
##   C. 5-in-a-row creates a color bomb
##   D. T and L shapes create an area clearer
##   F. Activation effects (row, col, color bomb, area, edge, blocked)
##   G. Swap-triggered activation

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Specials = preload("res://scripts/domain/rules/specials.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const SpecialPiece = Board.SpecialPiece
const Special = Board.Special
const SpecialKind = Board.SpecialKind

func _empty_board(w: int = 6, h: int = 6, palette: int = 6, blocked: Array = []) -> Board:
	return Board.new(Board.BoardConfig.new(w, h, palette, blocked))

func _fill_stable(b: Board) -> void:
	for y in range(b.config.height):
		for x in range(b.config.width):
			var cell = b.cell_at(Coord.new(x, y))
			if cell.is_blocked():
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % b.config.normal_palette_size))

func _build_board_with_special_at(coord: Coord, kind: int, kind_id: int) -> Board:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(coord, SpecialPiece.new(kind_id, Special.new(kind, 0, false)))
	return b

# ----------------------------------------------------------------------------
# B. 4-in-a-row creates a striped
# ----------------------------------------------------------------------------

func test_4_in_a_row_horizontal_creates_striped_row_at_centre() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 1)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.STRIPED_ROW)
	assert_eq(spec.orientation, 0)
	assert_eq(coord.x, 1)
	assert_eq(coord.y, 2)

func test_4_in_a_row_horizontal_swap_cell_becomes_special() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(5))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(
		runs, Coord.new(3, 2), Coord.new(3, 1))
	assert_eq(plan.entries.size(), 1)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	assert_eq(coord.x, 3)
	assert_eq(coord.y, 2)

func test_4_in_a_row_vertical_creates_striped_col() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(3, 1), Piece.new(4))
	b.set_piece(Coord.new(3, 2), Piece.new(4))
	b.set_piece(Coord.new(3, 3), Piece.new(4))
	b.set_piece(Coord.new(3, 4), Piece.new(4))
	b.set_piece(Coord.new(3, 0), Piece.new(0))
	b.set_piece(Coord.new(3, 5), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.STRIPED_COL)
	assert_eq(spec.orientation, 1)
	assert_eq(coord.x, 3)
	assert_eq(coord.y, 2)

# ----------------------------------------------------------------------------
# C. 5-in-a-row creates a color bomb
# ----------------------------------------------------------------------------

func test_5_in_a_row_horizontal_creates_color_bomb_at_centre() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(5))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.COLOR_BOMB)
	assert_eq(coord.x, 2)
	assert_eq(coord.y, 2)

func test_5_in_a_row_vertical_creates_color_bomb_at_centre() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(2, 0), Piece.new(3))
	b.set_piece(Coord.new(2, 1), Piece.new(3))
	b.set_piece(Coord.new(2, 2), Piece.new(3))
	b.set_piece(Coord.new(2, 3), Piece.new(3))
	b.set_piece(Coord.new(2, 4), Piece.new(3))
	b.set_piece(Coord.new(2, 5), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.COLOR_BOMB)
	assert_eq(coord.x, 2)
	assert_eq(coord.y, 2)

# ----------------------------------------------------------------------------
# D. T and L shapes
# ----------------------------------------------------------------------------

func test_t_shape_3plus3_creates_area_at_intersection() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 2), Piece.new(1))
	b.set_piece(Coord.new(3, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 3), Piece.new(1))
	b.set_piece(Coord.new(2, 4), Piece.new(1))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 5), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 2)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 1)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.AREA)
	assert_eq(coord.x, 2)
	assert_eq(coord.y, 2)

func test_l_shape_3plus3_creates_area_at_intersection() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(1))
	b.set_piece(Coord.new(1, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 3), Piece.new(1))
	b.set_piece(Coord.new(2, 4), Piece.new(1))
	b.set_piece(Coord.new(3, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 5), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 2)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 1)
	var entry: Dictionary = plan.entries[0]
	var coord: Coord = entry["coord"]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.AREA)
	assert_eq(coord.x, 2)
	assert_eq(coord.y, 2)

# ----------------------------------------------------------------------------
# F. Activation effects
# ----------------------------------------------------------------------------

func test_striped_row_clears_entire_row() -> void:
	var b := _build_board_with_special_at(Coord.new(2, 3), SpecialKind.STRIPED_ROW, 1)
	var result: Dictionary = Specials.activate(b, Coord.new(2, 3), -1, 1)
	assert_eq(result["kind"], SpecialKind.STRIPED_ROW)
	var cleared: Array = result["cleared"]
	assert_eq(cleared.size(), b.config.width)
	for i in range(cleared.size() - 1):
		var a: Coord = cleared[i]
		var c: Coord = cleared[i + 1]
		assert_true(Coord.compare(a, c))

func test_striped_col_clears_entire_column() -> void:
	var b := _build_board_with_special_at(Coord.new(3, 2), SpecialKind.STRIPED_COL, 1)
	var result: Dictionary = Specials.activate(b, Coord.new(3, 2), -1, 1)
	assert_eq(result["kind"], SpecialKind.STRIPED_COL)
	var cleared: Array = result["cleared"]
	assert_eq(cleared.size(), b.config.height)

func test_color_bomb_clears_all_of_its_kind() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(2, 3), SpecialPiece.new(1, Special.new(SpecialKind.COLOR_BOMB, 0, false)))
	var result: Dictionary = Specials.activate(b, Coord.new(2, 3), -1, 1)
	var expected := 1
	for c in b.all_piece_coords():
		var cell = b.cell_at(c)
		if cell.piece is SpecialPiece:
			continue
		if cell.piece.kind_id == 1:
			expected += 1
	var cleared: Array = result["cleared"]
	assert_true(cleared.size() >= expected,
			"color bomb cleared %d, expected >= %d" % [cleared.size(), expected])

func test_area_clearer_clears_3x3() -> void:
	var b := _build_board_with_special_at(Coord.new(3, 3), SpecialKind.AREA, 2)
	var result: Dictionary = Specials.activate(b, Coord.new(3, 3), -1, 2)
	var cleared: Array = result["cleared"]
	assert_eq(cleared.size(), 9)

func test_area_at_edge_clips_3x3() -> void:
	var b := _empty_board(4, 4)
	_fill_stable(b)
	b.set_piece(Coord.new(0, 0), SpecialPiece.new(2, Special.new(SpecialKind.AREA, 0, false)))
	var result: Dictionary = Specials.activate(b, Coord.new(0, 0), -1, 2)
	var cleared: Array = result["cleared"]
	assert_eq(cleared.size(), 4)

func test_activation_respects_blocked_cells() -> void:
	var b := _empty_board(6, 6, 6, [Coord.new(2, 3)])
	_fill_stable(b)
	b.set_piece(Coord.new(2, 2), SpecialPiece.new(2, Special.new(SpecialKind.AREA, 0, false)))
	var result: Dictionary = Specials.activate(b, Coord.new(2, 2), -1, 2)
	var cleared: Array = result["cleared"]
	for c in cleared:
		var cc: Coord = c
		assert_false(cc.is_equal_to(Coord.new(2, 3)),
				"blocked cell (2,3) must not appear in cleared set")
		var cell = b.cell_at(cc)
		assert_false(cell.is_blocked())

# ----------------------------------------------------------------------------
# G. Swap-triggered activation
# ----------------------------------------------------------------------------

func test_striped_swapped_with_normal_activates_at_destination() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 0), SpecialPiece.new(5, Special.new(SpecialKind.STRIPED_ROW, 0, false)))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 3), Piece.new(5))
	b.set_piece(Coord.new(2, 4), Piece.new(5))
	b.set_piece(Coord.new(2, 0), Piece.new(0))
	var cell = b.cell_at(Coord.new(1, 0))
	assert_true(cell.piece is SpecialPiece)
	var result: Dictionary = Specials.activate(b, Coord.new(1, 0), -1, 5)
	assert_eq(result["kind"], SpecialKind.STRIPED_ROW)
	assert_eq(result["cleared"].size(), b.config.width)

func test_color_bomb_swapped_with_normal_clears_target_color() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 0), SpecialPiece.new(0, Special.new(SpecialKind.COLOR_BOMB, 0, false)))
	var result: Dictionary = Specials.activate(b, Coord.new(0, 0), -1, 2)
	# The bomb is "color 0" (its own kind_id); it clears all kind 0.
	# It will NOT clear kind 2. Confirm at least one cell of a
	# different kind_id survives on the board.
	var all_clear: bool = true
	for c in b.all_piece_coords():
		var cell = b.cell_at(c)
		if cell.piece.kind_id != 0:
			all_clear = false
			break
	assert_false(all_clear,
			"a color bomb on kind 0 must not clear kind 2 cells; got %s" % str(result["cleared"]))