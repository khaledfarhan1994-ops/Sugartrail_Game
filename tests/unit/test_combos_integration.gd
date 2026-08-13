extends GutTest
## Special + special combinations — Step 14 fixtures, part 2 of 2.
##
## Sections:
##   E. Area + Area (5x5 at each epicentre)
##   F. Color Bomb + Color Bomb (entire board)
##   G. Color Bomb + Area (full-kind clear + 3x3)
##   J. Resolution emits SPECIAL_ACTIVATE with combo cleared list
##   K. Determinism + replay (two clean replays produce identical hashes)

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
# E. Area + Area
# ----------------------------------------------------------------------------

func test_area_plus_area_clears_5x5_at_each_epicentre() -> void:
	var b := _empty_board(8, 8)
	_fill_stable(b)
	_put_special(b, Coord.new(2, 2), SpecialKind.AREA, 0)
	_put_special(b, Coord.new(5, 5), SpecialKind.AREA, 0)
	var cleared: Array = Specials.combo_clear(b, Coord.new(2, 2),
			Coord.new(5, 5), SpecialKind.AREA, SpecialKind.AREA, 0, 0)
	# 5x5 at (2,2) covers rows 0..4 cols 0..4 (25 cells).
	# 5x5 at (5,5) covers rows 3..7 cols 3..7 (25 cells).
	# Overlap: rows 3..4 cols 3..4 (4 cells).
	# 25 + 25 - 4 = 46 cells.
	assert_eq(cleared.size(), 46, "two 5x5 = 46 cells")

# ----------------------------------------------------------------------------
# F. Color Bomb + Color Bomb
# ----------------------------------------------------------------------------

func test_color_bomb_plus_color_bomb_clears_every_piece() -> void:
	var b := _empty_board(6, 6)
	_fill_stable(b)
	_put_special(b, Coord.new(2, 2), SpecialKind.COLOR_BOMB, 1)
	_put_special(b, Coord.new(4, 4), SpecialKind.COLOR_BOMB, 3)
	var cleared: Array = Specials.combo_clear(b, Coord.new(2, 2),
			Coord.new(4, 4), SpecialKind.COLOR_BOMB, SpecialKind.COLOR_BOMB, 1, 3)
	# 6x6 board with no blocked cells = 36 pieces.
	assert_eq(cleared.size(), 36, "two bombs must clear every piece on the board")

# ----------------------------------------------------------------------------
# G. Color Bomb + Area
# ----------------------------------------------------------------------------

func test_color_bomb_plus_area_clears_kind_plus_3x3() -> void:
	# Bomb kind_id = 1; many kind-1 pieces on the board plus an area
	# special at a known position.
	var b := _empty_board(8, 8, 4)
	_fill_stable(b)
	_put_special(b, Coord.new(2, 2), SpecialKind.COLOR_BOMB, 1)
	_put_special(b, Coord.new(5, 5), SpecialKind.AREA, 0)
	# Count kind-1 normal pieces on the board (these will be cleared
	# by the bomb). Background pieces are (x + 2y) % 4; kind 1 cells.
	# The bomb at (2,2) is also kind_id=1 (SpecialPiece); the area
	# at (5,5) is kind_id=0. So the bomb's color clear includes the
	# bomb itself + all kind-1 normal pieces.
	var kind1_normal_count: int = 0
	for y in range(8):
		for x in range(8):
			var cell = b.cell_at(Coord.new(x, y))
			if cell.is_piece() and not (cell.piece is SpecialPiece) and cell.piece.kind_id == 1:
				kind1_normal_count += 1
	# Bomb's color clear = 1 (bomb) + kind1_normal_count cells.
	# Area's 3x3 around (5,5) = 9 cells.
	# Overlap = kind-1 normal pieces in the 3x3 around (5,5).
	var overlap: int = 0
	for y in range(4, 7):
		for x in range(4, 7):
			if x < 8 and y < 8:
				var cell = b.cell_at(Coord.new(x, y))
				if cell.is_piece() and not (cell.piece is SpecialPiece) and cell.piece.kind_id == 1:
					overlap += 1
	var expected: int = (1 + kind1_normal_count) + 9 - overlap
	var dict: Dictionary = Specials.activate_combo(b, Coord.new(2, 2),
			Coord.new(5, 5), SpecialKind.COLOR_BOMB, SpecialKind.AREA, 1, 0)
	var cleared: Array = dict.cleared
	assert_eq(cleared.size(), expected,
			"color bomb + area cleared count: (bomb + kind1) + 9 - overlap")

# ----------------------------------------------------------------------------
# J. Resolution emits SPECIAL_ACTIVATE with combo cleared list
# ----------------------------------------------------------------------------

func test_resolution_runs_combo_for_special_plus_special() -> void:
	# Build a board with two adjacent specials, no runs. Call
	# Resolution.resolve after a player swaps them. Expect:
	# - one SPECIAL_ACTIVATE event with the combo cleared list
	# - the combo's total_removed matches the cleared list size
	# - refill restores the board to full
	var b := _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	_put_special(b, Coord.new(0, 0), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(1, 0), SpecialKind.STRIPED_COL, 0)
	# Apply the swap.
	var ok: bool = Rules.try_swap(b, Coord.new(0, 0), Coord.new(1, 0))
	assert_true(ok, "swap must succeed")
	# Resolve with the swap context.
	var rng := Rng.new(0)
	var cascade: Resolution.CascadeResult = Resolution.resolve(b, rng,
			Coord.new(0, 0), Coord.new(1, 0))
	# Find the SPECIAL_ACTIVATE event.
	var found_activate: bool = false
	for e in cascade.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.SPECIAL_ACTIVATE:
			found_activate = true
			assert_eq(ev.cleared.size(), 11,
					"row+col combo clears 11 cells (6+6-1 overlap)")
			break
	assert_true(found_activate, "resolution must emit SPECIAL_ACTIVATE for combo")
	# After combo + gravity + refill, the board must be filled with
	# 36 pieces (the originals had 36; the combo removed 11, refill
	# restored 36).
	var piece_count: int = 0
	for cell in b._cells:
		if cell.is_piece():
			piece_count += 1
	assert_eq(piece_count, 36, "after combo + refill, board must have 36 pieces")
	# total_removed must equal 11 (the combo cleared list size).
	assert_eq(cascade.total_removed, 11, "combo removes 11 cells")

func test_resolution_does_not_run_combo_for_normal_swap() -> void:
	# A normal swap that creates a match must NOT take the combo
	# path (it goes through the standard match-resolve cycle).
	var b := _empty_board(6, 6)
	_fill_stable(b)
	# 3-run of kind 2 at row 2 cols 1..3 with sentinels.
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	# Find a legal swap that creates the match (no specials involved).
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1, "precondition: at least one legal swap")
	var pick: Array = moves[0]
	var a: Coord = pick[0]
	var bb: Coord = pick[1]
	var ok: bool = Rules.try_swap(b, a, bb)
	assert_true(ok, "swap must succeed")
	var rng := Rng.new(0)
	var cascade: Resolution.CascadeResult = Resolution.resolve(b, rng, a, bb)
	# No combo: total_removed equals 3 (the original 3-run).
	assert_eq(cascade.total_removed, 3,
			"normal 3-run resolution must remove exactly 3 pieces")

# ----------------------------------------------------------------------------
# K. Determinism + replay
# ----------------------------------------------------------------------------

func test_combo_replay_is_deterministic() -> void:
	# Build a board with two adjacent specials. Build an action log
	# with a combo swap. Replay twice and compare hashes.
	var b := _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	_put_special(b, Coord.new(0, 0), SpecialKind.STRIPED_ROW, 0)
	_put_special(b, Coord.new(1, 0), SpecialKind.STRIPED_COL, 0)
	var log := Replay.ActionLog.new()
	log.recipe = {"recipe_id": "combo-test", "recipe_version": 1}
	log.engine_version = Version.engine_version() + "-test"
	log.initial_rng_state = 999
	log.initial_board = b.to_snapshot()
	log.actions.append(Replay.Action.new(
			Replay.ActionKind.SWAP, Coord.new(0, 0), Coord.new(1, 0)))
	var r1: Replay.ReplayResult = Replay.replay(log, "")
	var r2: Replay.ReplayResult = Replay.replay(log, "")
	assert_true(r1.ok, "first replay ok; error=%s" % r1.last_error_message)
	assert_true(r2.ok, "second replay ok; error=%s" % r2.last_error_message)
	assert_eq(r1.result_hash, r2.result_hash,
			"two clean combo replays must produce identical hashes")
	assert_eq(r1.board.snapshot_hash(), r2.board.snapshot_hash(),
			"final board hashes must match")

func test_combo_log_with_older_engine_version_fails() -> void:
	# A combo log tagged with the previous engine version (0.2.0)
	# must be rejected by the current engine (0.3.0).
	var b := _empty_board(6, 6, 3)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 3))
	var log := Replay.ActionLog.new()
	log.recipe = {"recipe_id": "combo-old"}
	log.engine_version = "0.2.0-pre-combo"
	log.initial_rng_state = 1
	log.initial_board = b.to_snapshot()
	var result: Replay.ReplayResult = Replay.replay(log, Version.engine_version())
	assert_false(result.ok, "old-engine combo log must fail")
	assert_true(result.last_error_message.find("engine version") >= 0,
			"error message must mention engine version")
