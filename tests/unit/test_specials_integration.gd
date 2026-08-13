extends GutTest
## Special pieces — Step 13 fixtures, part 3 of 3.
##
## Sections:
##   H. Snapshot / replay / engine version
##   I. Integration with the resolution pipeline
##   J. Determinism + refill/spawn safety

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
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

func _count_event(events: Array, kind: int) -> int:
	var n: int = 0
	for e in events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == kind:
			n += 1
	return n

# ----------------------------------------------------------------------------
# H. Snapshot / replay / version
# ----------------------------------------------------------------------------

func test_snapshot_includes_special_metadata() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 1), SpecialPiece.new(3, Special.new(SpecialKind.STRIPED_COL, 1, false)))
	var snap: Dictionary = b.to_snapshot()
	var found: bool = false
	for entry in snap["cells"]:
		if int(entry["x"]) == 1 and int(entry["y"]) == 1:
			found = true
			assert_true(entry.has("special"))
			assert_eq(entry["special"]["kind"], SpecialKind.STRIPED_COL)
			assert_eq(entry["special"]["orientation"], 1)
			break
	assert_true(found)

func test_snapshot_hash_differs_for_special_vs_normal() -> void:
	var b1 := _empty_board()
	_fill_stable(b1)
	var b2 := _empty_board()
	_fill_stable(b2)
	b2.set_piece(Coord.new(1, 1), SpecialPiece.new(3, Special.new(SpecialKind.STRIPED_COL, 1, false)))
	b1.set_piece(Coord.new(1, 1), Piece.new(3))
	assert_ne(b1.snapshot_hash(), b2.snapshot_hash())

func test_snapshot_roundtrips_through_replay() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(2, 2), SpecialPiece.new(4, Special.new(SpecialKind.AREA, 0, false)))
	var snap: Dictionary = b.to_snapshot()
	var restored: Board = Replay._board_from_snapshot(snap)
	var c = restored.cell_at(Coord.new(2, 2))
	assert_true(c.piece is SpecialPiece)
	var sp: SpecialPiece = c.piece
	assert_eq(sp.special.kind, SpecialKind.AREA)
	assert_eq(sp.kind_id, 4)

func test_replay_with_specials_is_deterministic() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var moves: Array = Rules.enumerate_legal_swaps(b)
	if moves.size() == 0:
		b.set_piece(Coord.new(1, 3), Piece.new(5))
		b.set_piece(Coord.new(2, 3), Piece.new(5))
		moves = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1)
	var pick: Array = moves[0]
	var a_coord: Coord = pick[0]
	var b_coord: Coord = pick[1]
	var make_log := func() -> Replay.ActionLog:
		var l := Replay.ActionLog.new()
		l.recipe = {"recipe_id": "step13-striped", "recipe_version": 1}
		l.engine_version = Version.engine_version()
		l.initial_rng_state = 12345
		l.initial_board = b.to_snapshot()
		l.actions.append(Replay.Action.new(Replay.ActionKind.SWAP, a_coord, b_coord))
		return l
	var log1: Replay.ActionLog = make_log.call()
	var log2: Replay.ActionLog = make_log.call()
	var r1: Replay.ReplayResult = Replay.replay(log1, Version.engine_version())
	var r2: Replay.ReplayResult = Replay.replay(log2, Version.engine_version())
	assert_true(r1.ok)
	assert_true(r2.ok)
	assert_eq(r1.result_hash, r2.result_hash)
	assert_eq(r1.total_events, r2.total_events)

func test_engine_version_bumped_for_step_13() -> void:
	assert_eq(Version.ENGINE_MAJOR, 0)
	assert_eq(Version.ENGINE_MINOR, 2)
	assert_eq(Version.ENGINE_PATCH, 0)
	assert_eq(Version.engine_version(), "0.2.0")

func test_engine_version_mismatch_invalidates_old_logs() -> void:
	var log := Replay.ActionLog.new()
	log.engine_version = "0.1.0-old"
	log.initial_rng_state = 0
	var b := _empty_board(4, 4)
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	log.initial_board = b.to_snapshot()
	var result: Replay.ReplayResult = Replay.replay(log, "0.2.0-new")
	assert_false(result.ok)
	assert_true(result.last_error_message.find("engine version") >= 0)

# ----------------------------------------------------------------------------
# I. Integration with the resolution pipeline
# ----------------------------------------------------------------------------

func test_resolution_emits_special_create_event_for_4_run() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var found_create: bool = false
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.SPECIAL_CREATE and ev.special_kind == SpecialKind.STRIPED_ROW:
			found_create = true
			break
	assert_true(found_create)

func test_resolution_emits_special_activate_for_striped() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var activate_count: int = _count_event(result.events, EventKind.SPECIAL_ACTIVATE)
	assert_true(activate_count >= 1)
	var found_with_cleared: bool = false
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.SPECIAL_ACTIVATE and ev.cleared.size() > 0:
			found_with_cleared = true
			break
	assert_true(found_with_cleared)

func test_resolution_event_order_specials_then_remove() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var cycle0: Array = []
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.cascade == 0:
			cycle0.append(ev.kind)
	var first_create: int = -1
	var first_activate: int = -1
	var first_remove: int = -1
	for i in range(cycle0.size()):
		var k: int = cycle0[i]
		if k == EventKind.SPECIAL_CREATE and first_create < 0:
			first_create = i
		if k == EventKind.SPECIAL_ACTIVATE and first_activate < 0:
			first_activate = i
		if k == EventKind.REMOVE and first_remove < 0:
			first_remove = i
	assert_true(first_create >= 0)
	assert_true(first_activate >= 0)
	assert_true(first_remove >= 0)
	assert_true(first_create < first_activate)
	assert_true(first_activate < first_remove)

func test_resolution_5_run_emits_color_bomb_create() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(5))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var found: bool = false
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.SPECIAL_CREATE and ev.special_kind == SpecialKind.COLOR_BOMB:
			found = true
			break
	assert_true(found)

func test_resolution_t_shape_emits_area_create() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 2), Piece.new(1))
	b.set_piece(Coord.new(3, 2), Piece.new(1))
	b.set_piece(Coord.new(2, 3), Piece.new(1))
	b.set_piece(Coord.new(2, 4), Piece.new(1))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 5), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var found: bool = false
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.SPECIAL_CREATE and ev.special_kind == SpecialKind.AREA:
			found = true
			break
	assert_true(found)

func test_resolution_no_special_on_3_run() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	assert_eq(_count_event(result.events, EventKind.SPECIAL_CREATE), 0)

func test_domain_event_to_dict_roundtrips_special_fields() -> void:
	var origin := Coord.new(2, 3)
	var cleared: Array = [Coord.new(0, 1), Coord.new(1, 1)]
	var e := Resolution.DomainEvent.new(
			EventKind.SPECIAL_ACTIVATE, [origin], 5, 0,
			SpecialKind.STRIPED_ROW, origin, cleared)
	var d: Dictionary = e.to_dict()
	assert_eq(d["kind"], EventKind.SPECIAL_ACTIVATE)
	assert_eq(d["special_kind"], SpecialKind.STRIPED_ROW)
	assert_eq(d["special_origin"]["x"], 2)
	assert_eq(d["special_origin"]["y"], 3)
	assert_eq(d["cleared"].size(), 2)
	assert_eq(d["cleared"][0]["x"], 0)
	assert_eq(d["cleared"][0]["y"], 1)

# ----------------------------------------------------------------------------
# J. Determinism + refill/spawn safety
# ----------------------------------------------------------------------------

func test_special_creation_is_deterministic() -> void:
	var make := func() -> Board:
		var b := _empty_board()
		_fill_stable(b)
		b.set_piece(Coord.new(0, 2), Piece.new(5))
		b.set_piece(Coord.new(1, 2), Piece.new(5))
		b.set_piece(Coord.new(2, 2), Piece.new(5))
		b.set_piece(Coord.new(3, 2), Piece.new(5))
		b.set_piece(Coord.new(4, 2), Piece.new(0))
		b.set_piece(Coord.new(5, 2), Piece.new(0))
		return b
	var b1: Board = make.call()
	var b2: Board = make.call()
	var r1: Resolution.CascadeResult = Resolution.resolve(b1, Rng.new(0))
	var r2: Resolution.CascadeResult = Resolution.resolve(b2, Rng.new(0))
	assert_eq(b1.snapshot_hash(), b2.snapshot_hash())
	assert_eq(r1.events.size(), r2.events.size())
	for i in range(r1.events.size()):
		var e1: Resolution.DomainEvent = r1.events[i]
		var e2: Resolution.DomainEvent = r2.events[i]
		assert_eq(e1.kind, e2.kind)
		assert_eq(e1.special_kind, e2.special_kind)
		assert_eq(e1.piece_kind_id, e2.piece_kind_id)

func test_refill_does_not_spawn_specials() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(0, 2), Piece.new(5))
	b.set_piece(Coord.new(1, 2), Piece.new(5))
	b.set_piece(Coord.new(2, 2), Piece.new(5))
	b.set_piece(Coord.new(3, 2), Piece.new(5))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(0)
	Resolution.resolve(b, rng)
	for c in b.all_coords():
		var cell = b.cell_at(c)
		if cell.is_piece():
			assert_false(cell.piece is SpecialPiece,
					"refill must not spawn specials; cell %s" % c._to_debug_string())

func test_reshuffle_refuses_with_specials_on_board() -> void:
	var b := _empty_board()
	_fill_stable(b)
	b.set_piece(Coord.new(1, 1), SpecialPiece.new(2, Special.new(SpecialKind.AREA, 0, false)))
	var rng := Rng.new(0)
	var ok: bool = Replay.reshuffle(b, rng)
	assert_false(ok)