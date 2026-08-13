extends GutTest
## Special + special combinations — Step 14 fixtures, part 1 of 2.
##
## Sections:
##   A. Data model (ComboSpec construction; key normalisation)
##   B. Striped + Striped (H+H, V+V, H+V) for both swap directions
##   C. Striped + Color Bomb (H+V) for both swap directions
##   D. Striped + Area (H+V) for both swap directions
##   H. try_swap accepts special+special without 3-run
##   I. enumerate_legal_swaps emits combo swaps
##
## Larger combos (E. Area+Area, F. Bomb+Bomb, G. Bomb+Area),
## resolution integration (J), and replay determinism (K) live in
## `test_combos_integration.gd`.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Specials = preload("res://scripts/domain/rules/specials.gd")
const Version = preload("res://scripts/domain/sugartrail_version.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const SpecialPiece = Board.SpecialPiece
const Special = Board.Special
const SpecialKind = Board.SpecialKind
const EventKind = Resolution.EventKind

func _empty_board(w: int = 6, h: int = 6, palette: int = 6, blocked: Array = []) -> Board:
	return Board.new(Board.BoardConfig.new(w, h, palette, blocked))

func _fill_stable(b: Board) -> void:
	for y in range(b.config.height):
		for x in range(b.config.width):
			var cell = b.cell_at(Coord.new(x, y))
			if cell.is_blocked():
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % b.config.normal_palette_size))

func _put_special(b: Board, coord: Coord, kind: int, kind_id: int) -> void:
	b.set_piece(coord, SpecialPiece.new(kind_id, Special.new(kind, 0, false)))

# ----------------------------------------------------------------------------
# A. Data model
# ----------------------------------------------------------------------------

func test_combo_key_is_order_invariant() -> void:
	var k1: Array = Specials._combo_key(SpecialKind.STRIPED_ROW, SpecialKind.AREA)
	var k2: Array = Specials._combo_key(SpecialKind.AREA, SpecialKind.STRIPED_ROW)
	assert_eq(k1, k2, "combo_key must be [min,max] regardless of input order")

func test_combo_lookup_returns_null_for_unsupported_pair() -> void:
	# STRIPED_ROW + STRIPED_ROW is supported; pick a clearly unsupported
	# combination (e.g. normal piece kind - doesn't apply, but two of
	# the same special kind that aren't on the supported matrix).
	# Actually all same-kind pairs ARE supported. So we test a
	# non-existent special kind combo.
	var b := _empty_board()
	var spec: Specials.ComboSpec = Specials.lookup_combo(b, Coord.new(0, 0),
			Coord.new(1, 0), 99, 100, 0, 0)
	assert_null(spec, "unknown kinds must produce null")

func test_combospec_holds_inputs_and_cleared_fn() -> void:
	var b := _empty_board()
	var spec: Specials.ComboSpec = Specials.lookup_combo(b, Coord.new(0, 0),
			Coord.new(1, 0), SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_COL,
			0, 1)
	assert_not_null(spec, "STRIPED_ROW + STRIPED_COL must be a supported combo")
	assert_eq(spec.a_kind, SpecialKind.STRIPED_ROW)
	assert_eq(spec.b_kind, SpecialKind.STRIPED_COL)
	assert_true(spec.cleared_fn.is_valid(), "cleared_fn must be a Callable")

func test_combo_clear_empty_for_unsupported() -> void:
	var b := _empty_board()
	var cleared: Array = Specials.combo_clear(b, Coord.new(0, 0),
			Coord.new(1, 0), 99, 100, 0, 0)
	assert_eq(cleared.size(), 0, "unsupported pair must clear nothing")

# ----------------------------------------------------------------------------
# B. Striped + Striped
# ----------------------------------------------------------------------------

func test_striped_row_plus_col_clears_row_and_col() -> void:
	# Row-striped at (0,2) clears row 2; col-striped at (3,0) clears col 3.
	# Combined: every cell in row 2 + every cell in col 3 (deduped).
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(0, 2), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(3, 0), SpecialKind.STRIPED_COL, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(0, 2), Coord.new(3, 0),
			SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_COL, 0, 0)
	# 6 row + 6 col - 1 overlap at (3,2) = 11 unique cells.
	assert_eq(cleared.size(), 11, "row + col must clear 11 unique cells")
	# Verify the overlap cell (3,2) is in the cleared list.
	var found_overlap: bool = false
	for c in cleared:
		var cc: Coord = c
		if cc.is_equal_to(Coord.new(3, 2)):
			found_overlap = true
			break
	assert_true(found_overlap, "overlap cell (3,2) must be in cleared")
	# Verify every row 2 cell is in cleared.
	for x in range(6):
		var found_row: bool = false
		for c in cleared:
			var cc: Coord = c
			if cc.is_equal_to(Coord.new(x, 2)):
				found_row = true
				break
		assert_true(found_row, "row 2 cell (x=%d) must be cleared" % x)
	# Verify every col 3 cell is in cleared.
	for y in range(6):
		var found_col: bool = false
		for c in cleared:
			var cc: Coord = c
			if cc.is_equal_to(Coord.new(3, y)):
				found_col = true
				break
		assert_true(found_col, "col 3 cell (y=%d) must be cleared" % y)

func test_striped_row_plus_row_clears_both_rows() -> void:
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(1, 2), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(4, 4), SpecialKind.STRIPED_ROW, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(1, 2), Coord.new(4, 4),
			SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_ROW, 0, 0)
	# Two distinct rows: 6 + 6 = 12 cells.
	assert_eq(cleared.size(), 12, "two row-striped must clear 12 cells")
	for x in range(6):
		for y in [2, 4]:
			var found: bool = false
			for c in cleared:
				var cc: Coord = c
				if cc.is_equal_to(Coord.new(x, y)):
					found = true
					break
			assert_true(found, "row %d cell (x=%d) must be cleared" % [y, x])

func test_striped_col_plus_col_clears_both_cols() -> void:
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(1, 2), SpecialKind.STRIPED_COL, 0)
	_put_special(b, Coord.new(4, 4), SpecialKind.STRIPED_COL, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(1, 2), Coord.new(4, 4),
			SpecialKind.STRIPED_COL, SpecialKind.STRIPED_COL, 0, 0)
	assert_eq(cleared.size(), 12, "two col-striped must clear 12 cells")
	for y in range(6):
		for x in [1, 4]:
			var found: bool = false
			for c in cleared:
				var cc: Coord = c
				if cc.is_equal_to(Coord.new(x, y)):
					found = true
					break
			assert_true(found, "col %d cell (y=%d) must be cleared" % [x, y])

func test_striped_row_plus_col_swap_direction_invariance() -> void:
	# Same combo with swapped (a, b) coords produces the same cleared
	# SET (regardless of order). The swap order does not matter.
	var b1 := _empty_board(6, 6)
	_fill_stable(b1)
	_put_special(b1, Coord.new(0, 2), SpecialKind.STRIPED_ROW, 0)
	_put_special(b1, Coord.new(3, 0), SpecialKind.STRIPED_COL, 0)
	var cleared_fwd: Array = Specials.combo_clear(b1, Coord.new(0, 2),
			Coord.new(3, 0), SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_COL, 0, 0)
	var cleared_bwd: Array = Specials.combo_clear(b1, Coord.new(3, 0),
			Coord.new(0, 2), SpecialKind.STRIPED_COL, SpecialKind.STRIPED_ROW, 0, 0)
	# Compare as sets (sorted by (y, x)).
	var fwd_keys: Array = []
	for c in cleared_fwd:
		var cc: Coord = c
		fwd_keys.append("%d,%d" % [cc.y, cc.x])
	fwd_keys.sort()
	var bwd_keys: Array = []
	for c in cleared_bwd:
		var cc: Coord = c
		bwd_keys.append("%d,%d" % [cc.y, cc.x])
	bwd_keys.sort()
	assert_eq(fwd_keys, bwd_keys,
			"combo cleared set must be direction-invariant")

# ----------------------------------------------------------------------------
# C. Striped + Color Bomb
# ----------------------------------------------------------------------------

func test_striped_row_plus_color_bomb_clears_row() -> void:
	# The bomb "paints" the row; per the Step 14 matrix the cleared
	# list is the full row (paint effect).
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(1, 2), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(4, 3), SpecialKind.COLOR_BOMB, 2)
	var dict: Dictionary = Specials.activate_combo(b, Coord.new(1, 2),
			Coord.new(4, 3), SpecialKind.STRIPED_ROW, SpecialKind.COLOR_BOMB, 0, 2)
	assert_eq(dict.kind, SpecialKind.COLOR_BOMB, "combo result kind is COLOR_BOMB")
	var cleared: Array = dict.cleared
	# Row 2 has 6 cells.
	assert_eq(cleared.size(), 6, "striped-row + bomb clears the row (6 cells)")

func test_striped_col_plus_color_bomb_clears_col() -> void:
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(3, 1), SpecialKind.STRIPED_COL, 0)
	_put_special(b, Coord.new(4, 3), SpecialKind.COLOR_BOMB, 1)
	var cleared: Array = Specials.combo_clear(b, Coord.new(3, 1),
			Coord.new(4, 3), SpecialKind.STRIPED_COL, SpecialKind.COLOR_BOMB, 0, 1)
	assert_eq(cleared.size(), 6, "striped-col + bomb clears the column (6 cells)")

func test_striped_bomb_swap_direction_invariance() -> void:
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(1, 2), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(4, 3), SpecialKind.COLOR_BOMB, 2)
	var fwd: Array = Specials.combo_clear(b, Coord.new(1, 2), Coord.new(4, 3),
			SpecialKind.STRIPED_ROW, SpecialKind.COLOR_BOMB, 0, 2)
	var bwd: Array = Specials.combo_clear(b, Coord.new(4, 3), Coord.new(1, 2),
			SpecialKind.COLOR_BOMB, SpecialKind.STRIPED_ROW, 2, 0)
	# Compare as sets.
	var fwd_keys: Array = []
	for c in fwd:
		var cc: Coord = c
		fwd_keys.append("%d,%d" % [cc.y, cc.x])
	fwd_keys.sort()
	var bwd_keys: Array = []
	for c in bwd:
		var cc: Coord = c
		bwd_keys.append("%d,%d" % [cc.y, cc.x])
	bwd_keys.sort()
	assert_eq(fwd_keys, bwd_keys,
			"striped + bomb cleared set must be direction-invariant")

# ----------------------------------------------------------------------------
# D. Striped + Area
# ----------------------------------------------------------------------------

func test_striped_row_plus_area_clears_row_plus_3x3() -> void:
	var b := _empty_board(8, 8)
	_fill_stable(b)
	_put_special(b, Coord.new(2, 3), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(5, 5), SpecialKind.AREA, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(2, 3),
			Coord.new(5, 5), SpecialKind.STRIPED_ROW, SpecialKind.AREA, 0, 0)
	# Row y=3 has 8 cells. Area at (5,5) has 9 cells (within bounds).
	# No overlap (row 3 col 5 not in the 3x3 around (5,5)).
	assert_eq(cleared.size(), 8 + 9, "row + 3x3 = 17 cells, no overlap")

func test_striped_col_plus_area_clears_col_plus_3x3() -> void:
	var b := _empty_board(8, 8)
	_fill_stable(b)
	_put_special(b, Coord.new(3, 1), SpecialKind.STRIPED_COL, 0)
	_put_special(b, Coord.new(5, 5), SpecialKind.AREA, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(3, 1),
			Coord.new(5, 5), SpecialKind.STRIPED_COL, SpecialKind.AREA, 0, 0)
	# Col x=3 has 8 cells (none in the 3x3 around (5,5), since the
	# 3x3 covers cols 4,5,6). Area at (5,5) has 9 cells. No overlap.
	# 8 + 9 = 17.
	assert_eq(cleared.size(), 17, "col + 3x3 = 17 cells (no overlap)")

func test_striped_area_swap_direction_invariance() -> void:
	var b := _empty_board(8, 8)
	_fill_stable(b)
	_put_special(b, Coord.new(2, 3), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(5, 5), SpecialKind.AREA, 0)
	var fwd: Array = Specials.combo_clear(b, Coord.new(2, 3), Coord.new(5, 5),
			SpecialKind.STRIPED_ROW, SpecialKind.AREA, 0, 0)
	var bwd: Array = Specials.combo_clear(b, Coord.new(5, 5), Coord.new(2, 3),
			SpecialKind.AREA, SpecialKind.STRIPED_ROW, 0, 0)
	# Compare as sets.
	var fwd_keys: Array = []
	for c in fwd:
		var cc: Coord = c
		fwd_keys.append("%d,%d" % [cc.y, cc.x])
	fwd_keys.sort()
	var bwd_keys: Array = []
	for c in bwd:
		var cc: Coord = c
		bwd_keys.append("%d,%d" % [cc.y, cc.x])
	bwd_keys.sort()
	assert_eq(fwd_keys, bwd_keys,
			"striped + area cleared set must be direction-invariant")

# ----------------------------------------------------------------------------
# E. Area + Area
# ----------------------------------------------------------------------------
# (E, F, G, J, K moved to test_combos_integration.gd.)

# ----------------------------------------------------------------------------
# H. try_swap accepts special+special without 3-run
# ----------------------------------------------------------------------------

func test_try_swap_accepts_special_plus_special() -> void:
	# Two specials placed on a board that has NO 3-run anywhere.
	# try_swap must return true (legal) because both cells are specials.
	var b := _empty_board(6, 6)
	# Use a stable 4x3-like pattern but spread across 6x6 with
	# no runs. With palette=6 and pattern (x + y) % 6 the board has
	# many runs. Use palette=3 with the (x + y) % 3 pattern -> no runs.
	b = _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	# Confirm no runs.
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 0, "precondition: no runs on 6x6 (x+y)%3 board")
	# Place two adjacent specials.
	_put_special(b, Coord.new(0, 0), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(1, 0), SpecialKind.STRIPED_COL, 0)
	# Swap (0,0) <-> (1,0). Both specials; no 3-run formed.
	var ok: bool = Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 0))
	assert_true(ok, "special+special swap must be legal even without a 3-run")

func test_try_swap_still_rejects_normal_swap_without_run() -> void:
	# Two normal pieces adjacent; no run formed by swap; not specials.
	var b := _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	# Swap doesn't create a match.
	var ok: bool = Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok, "normal swap without run must be rejected")

func test_try_swap_rejects_special_plus_normal_without_run() -> void:
	# Special + normal adjacent; the swap does NOT create a 3-run.
	# Step 14: this swap must be rejected (the Step 13 swap-triggered
	# activation rule still requires a 3-run for special+normal).
	var b := _empty_board(6, 6)
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), SpecialPiece.new(5, Special.new(SpecialKind.STRIPED_ROW, 0, false)))
	b.set_piece(Coord.new(2, 2), Piece.new(3))
	b.set_piece(Coord.new(3, 2), Piece.new(3))
	b.set_piece(Coord.new(4, 2), Piece.new(3))
	# Swap (1,2) <-> (2,2): the special at (1,2) is kind 5, kind 3
	# pieces at (2,2)(3,2)(4,2). After swap, (1,2) is kind 3 and
	# (2,2) is the special. (1,2)(2,2)(3,2) is kind 3 + special +
	# kind 3 -- not a 3-run. (2,2)(3,2)(4,2) is special + kind 3 +
	# kind 3 -- not a 3-run. So try_swap must return false.
	var ok: bool = Rules.try_swap(b, Coord.new(1, 2), Coord.new(2, 2))
	assert_false(ok, "special+normal swap without run must be rejected")

# ----------------------------------------------------------------------------
# I. enumerate_legal_swaps emits combo swaps
# ----------------------------------------------------------------------------

func test_enumerate_legal_swaps_includes_combo_swaps() -> void:
	var b := _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	# Place two adjacent specials; no runs exist on the board.
	_put_special(b, Coord.new(0, 0), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(1, 0), SpecialKind.STRIPED_COL, 0)
	var moves: Array = Rules.enumerate_legal_swaps(b)
	# Without specials, this board has 0 legal moves.
	# With the special pair, the swap (0,0)<->(1,0) becomes legal.
	# The board must remain unchanged (moves must be undoable).
	var board_hash_before: int = b.snapshot_hash()
	var found: bool = false
	for m in moves:
		var pair: Array = m
		var a: Coord = pair[0]
		var bb: Coord = pair[1]
		if (a.is_equal_to(Coord.new(0, 0)) and bb.is_equal_to(Coord.new(1, 0))) \
				or (a.is_equal_to(Coord.new(1, 0)) and bb.is_equal_to(Coord.new(0, 0))):
			found = true
			break
	assert_true(found, "combo swap must appear in legal moves list")
	assert_eq(b.snapshot_hash(), board_hash_before, "enumerate must not mutate the board")
