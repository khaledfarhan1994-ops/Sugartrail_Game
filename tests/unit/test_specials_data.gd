extends GutTest
## Special pieces — Step 13 fixtures, part 1 of 3.
##
## Sections:
##   A. Data model (Special, SpecialPiece, dict roundtrips)
##   E. Precedence (5 > 4 > T/L; no special on 3-run; disjoint runs)

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

# ----------------------------------------------------------------------------
# A. Data model
# ----------------------------------------------------------------------------

func test_special_default_is_normal() -> void:
	var spec := Special.new()
	assert_eq(spec.kind, SpecialKind.NONE)
	assert_false(spec.is_special())
	assert_true(spec.is_normal())

func test_specialpiece_roundtrip_kind_id() -> void:
	var sp := SpecialPiece.new(3)
	assert_eq(sp.kind_id, 3)
	assert_false(sp.is_special())

func test_specialpiece_with_special_is_special() -> void:
	var spec := Special.new(SpecialKind.STRIPED_ROW, 0, false)
	var sp := SpecialPiece.new(2, spec)
	assert_true(sp.is_special())
	assert_false(sp.is_normal())
	assert_eq(sp.special.kind, SpecialKind.STRIPED_ROW)
	assert_eq(sp.kind_id, 2)

func test_special_to_dict_roundtrips() -> void:
	var spec := Special.new(SpecialKind.COLOR_BOMB, 0, true)
	var d: Dictionary = spec.to_dict()
	assert_eq(d["kind"], SpecialKind.COLOR_BOMB)
	assert_true(d["needs_activation"])
	var back: Special = Special.from_dict(d)
	assert_eq(back.kind, SpecialKind.COLOR_BOMB)
	assert_true(back.needs_activation)

func test_specialpiece_to_dict_roundtrips() -> void:
	var sp := SpecialPiece.new(4, Special.new(SpecialKind.AREA, 0, false))
	var d: Dictionary = sp.to_dict()
	assert_eq(d["kind_id"], 4)
	assert_eq(d["special"]["kind"], SpecialKind.AREA)
	var back: SpecialPiece = SpecialPiece.from_dict(d)
	assert_eq(back.kind_id, 4)
	assert_eq(back.special.kind, SpecialKind.AREA)

# ----------------------------------------------------------------------------
# E. Precedence
# ----------------------------------------------------------------------------

func test_5_run_beats_4_run_when_overlapping() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 3), Piece.new(5))
	b.set_piece(Coord.new(2, 4), Piece.new(5))
	b.set_piece(Coord.new(2, 5), Piece.new(5))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 1), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	var sizes: Array = []
	for r in runs:
		sizes.append(r.size())
	assert_true(sizes.has(5))
	assert_true(sizes.has(4))
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 1, "only one special: the color bomb wins")
	var entry: Dictionary = plan.entries[0]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.COLOR_BOMB)

func test_4_run_beats_t_shape_when_overlapping() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 3), Piece.new(5))
	b.set_piece(Coord.new(2, 4), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 5), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 1)
	var entry: Dictionary = plan.entries[0]
	var spec: Special = entry["special"]
	assert_eq(spec.kind, SpecialKind.STRIPED_ROW)

func test_no_special_on_3_run() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 1)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 0)

func test_two_disjoint_4_runs_produce_two_stripes() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 1), Piece.new(0))
	b.set_piece(Coord.new(1, 1), Piece.new(0))
	b.set_piece(Coord.new(2, 1), Piece.new(0))
	b.set_piece(Coord.new(3, 1), Piece.new(0))
	b.set_piece(Coord.new(1, 4), Piece.new(1))
	b.set_piece(Coord.new(2, 4), Piece.new(1))
	b.set_piece(Coord.new(3, 4), Piece.new(1))
	b.set_piece(Coord.new(4, 4), Piece.new(1))
	b.set_piece(Coord.new(4, 1), Piece.new(2))
	b.set_piece(Coord.new(5, 1), Piece.new(2))
	b.set_piece(Coord.new(0, 4), Piece.new(2))
	b.set_piece(Coord.new(5, 4), Piece.new(2))
	var runs: Array = Rules.find_runs(b)
	assert_eq(runs.size(), 2)
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, null, null)
	assert_eq(plan.entries.size(), 2)