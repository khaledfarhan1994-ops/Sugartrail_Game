extends GutTest
## Step 15: layered frosting and locked cell resolution tests.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord

func _empty_config(w: int = 6, h: int = 8, blockers: Array = []) -> Board.BoardConfig:
	return Board.BoardConfig.new(w, h, 4, [], blockers)

func _put(board: Board, c: Coord, kind: int) -> void:
	board.set_piece(c, Board.Piece.new(kind))

# A. 2-layer frosting: one REMOVE decrements; second REMOVE breaks.

func test_two_layer_frosting_decrements_then_breaks() -> void:
	# Build a 3-row with a 2-layer frosted piece in the middle. All
	# cells filled with kind 0 to ensure the horizontal match.
	var b := Board.new(_empty_config(4, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 2}]))
	# Set FROSTING cell to PIECE (it was empty) by fill_random.
	var rng := Rng.new(11)
	Resolution.fill_random(b, rng, false)
	# Force all cells to kind 0 so cell 1 is in the run.
	_put(b, Coord.new(0, 0), 0)
	b.cell_at(Coord.new(1, 0)).piece = Board.Piece.new(0)
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	# First resolve: clears the horizontal 4-run. Cell 1's frosting
	# decrements from 2 to 1; cell becomes FROSTING with layers=1.
	var r1: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var saw_damage: bool = false
	for ev in r1.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.BLOCKER_DAMAGE \
				and e.coords[0].is_equal_to(Coord.new(1, 0)):
			assert_eq(e.layers_after, 1)
			saw_damage = true
	assert_true(saw_damage, "first clear should emit BLOCKER_DAMAGE with layers_after=1")
	# After resolve, cell 1 is FROSTING with 1 layer.
	var cell_after: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell_after.frosting_layers, 1)

# B. 3-layer frosting: three clears to break.

func test_three_layer_frosting_requires_three_clears() -> void:
	var b := Board.new(_empty_config(4, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 3}]))
	var rng := Rng.new(13)
	Resolution.fill_random(b, rng, false)
	# Force all cells to kind 0 so cell 1 is in the run.
	_put(b, Coord.new(0, 0), 0)
	b.cell_at(Coord.new(1, 0)).piece = Board.Piece.new(0)
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	# First clear: layers 3 -> 2.
	Resolution.resolve(b, rng)
	var cell_after1: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell_after1.frosting_layers, 2)
	# Reset all cells to kind 0 again (cell 1 is FROSTING with layers=2;
	# force a piece back in via direct mutation that preserves layers).
	_put(b, Coord.new(0, 0), 0)
	cell_after1.piece = Board.Piece.new(0)
	cell_after1.kind = Board.CellKind.PIECE
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	Resolution.resolve(b, rng)
	var cell_after2: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_eq(cell_after2.frosting_layers, 1)
	# Third clear: layers 1 -> 0 (BREAK).
	_put(b, Coord.new(0, 0), 0)
	cell_after2.piece = Board.Piece.new(0)
	cell_after2.kind = Board.CellKind.PIECE
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	var r3: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var saw_break: bool = false
	for ev in r3.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.BLOCKER_BREAK \
				and e.coords[0].is_equal_to(Coord.new(1, 0)):
			saw_break = true
	assert_true(saw_break, "third clear should emit BLOCKER_BREAK")
	var cell_final: Board.Cell = b.cell_at(Coord.new(1, 0))
	# After the third clear the frosting breaks (frosting_layers=0).
	# The cell may then be refilled with a new piece by refill.
	assert_eq(cell_final.frosting_layers, 0)

# C. BLOCKER_DAMAGE event payload.

func test_blocker_damage_event_payload() -> void:
	var b := Board.new(_empty_config(4, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 2}]))
	var rng := Rng.new(17)
	Resolution.fill_random(b, rng, false)
	_put(b, Coord.new(0, 0), 0)
	b.cell_at(Coord.new(1, 0)).piece = Board.Piece.new(0)
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	var r: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var damage_ev: Resolution.DomainEvent = null
	for ev in r.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.BLOCKER_DAMAGE \
				and e.coords[0].is_equal_to(Coord.new(1, 0)):
			damage_ev = e
			break
	assert_not_null(damage_ev, "expected BLOCKER_DAMAGE event for cell (1,0)")
	assert_eq(damage_ev.layers_after, 1)
	assert_eq(damage_ev.piece_kind_id, 0)
	assert_eq(damage_ev.coords[0].x, 1)
	assert_eq(damage_ev.coords[0].y, 0)

# D. BLOCKER_BREAK event payload.

func test_blocker_break_event_payload() -> void:
	var b := Board.new(_empty_config(4, 1, [{"x": 1, "y": 0, "type": "FROSTING", "layers": 1}]))
	var rng := Rng.new(19)
	Resolution.fill_random(b, rng, false)
	_put(b, Coord.new(0, 0), 0)
	b.cell_at(Coord.new(1, 0)).piece = Board.Piece.new(0)
	_put(b, Coord.new(2, 0), 0)
	_put(b, Coord.new(3, 0), 0)
	var r: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var break_ev: Resolution.DomainEvent = null
	for ev in r.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.BLOCKER_BREAK \
				and e.coords[0].is_equal_to(Coord.new(1, 0)):
			break_ev = e
			break
	assert_not_null(break_ev, "expected BLOCKER_BREAK event for cell (1,0)")
	assert_eq(break_ev.piece_kind_id, 0)
	assert_eq(break_ev.coords[0].x, 1)

# E. Locked cells stay put through normal cascades.

func test_locked_cell_survives_match() -> void:
	var b := Board.new(_empty_config(4, 1))
	_put(b, Coord.new(0, 0), 0)
	_put(b, Coord.new(1, 0), 0)
	_put(b, Coord.new(2, 0), 0)
	b.cell_at(Coord.new(1, 0)).locked = true
	var rng := Rng.new(23)
	var r: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# Cell 1 (locked) must still hold a piece.
	var cell_after: Board.Cell = b.cell_at(Coord.new(1, 0))
	assert_true(cell_after.is_piece(), "locked cell must keep its piece after match")
	assert_true(cell_after.locked)

# F. Locked cell released by special activation (force-clear).

func test_locked_cell_clears_when_forced() -> void:
	# A horizontal 5-run creates a COLOR_BOMB at the centre cell
	# whose activation clears every piece of its kind_id. Place the
	# locked piece at the centre of a 5-run of kind 0; the color bomb
	# activates and clears every kind-0 piece including the locked
	# cell. Resolution should emit BLOCKER_BREAK for the locked cell.
	var b := Board.new(_empty_config(5, 1))
	_put(b, Coord.new(0, 0), 0)
	_put(b, Coord.new(1, 0), 0)
	# Place a locked piece at the centre of the 5-run.
	b.cell_at(Coord.new(2, 0)).kind = Board.CellKind.PIECE
	b.cell_at(Coord.new(2, 0)).piece = Board.Piece.new(0)
	b.cell_at(Coord.new(2, 0)).locked = true
	_put(b, Coord.new(3, 0), 0)
	_put(b, Coord.new(4, 0), 0)
	var rng := Rng.new(29)
	var r: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# Locked cell at (2,0) should be unlocked. The COLOR_BOMB clears
	# every kind-0 piece including the locked one (the cleared list
	# includes (2,0)). After the clear, refill may spawn a new piece
	# in the slot — the lock is gone either way.
	var cell_after: Board.Cell = b.cell_at(Coord.new(2, 0))
	assert_false(cell_after.locked, "lock released after COLOR_BOMB activation")
	# Look for BLOCKER_BREAK on (2,0).
	var saw_break: bool = false
	for ev in r.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.BLOCKER_BREAK \
				and e.coords[0].is_equal_to(Coord.new(2, 0)):
			saw_break = true
	assert_true(saw_break, "expected BLOCKER_BREAK event for locked (2,0)")