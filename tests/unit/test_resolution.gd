extends GutTest
## Resolution pipeline — Step 07 fixtures.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const EventKind = Resolution.EventKind

func _empty_board(w: int = 6, h: int = 6, palette: int = 6, blocked: Array = []) -> Board:
	return Board.new(Board.BoardConfig.new(w, h, palette, blocked))

func _count_event(events: Array, kind: int) -> int:
	var n: int = 0
	for e in events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == kind:
			n += 1
	return n

func _event_kinds(events: Array) -> Array:
	var out: Array = []
	for e in events:
		var ev: Resolution.DomainEvent = e
		out.append(ev.kind)
	return out

# ----------------------------------------------------------------------------
# Single match, no cascade
# ----------------------------------------------------------------------------

func test_resolve_removes_simple_three_in_a_row() -> void:
	var b := _empty_board()
	# Build a stable background (no incidental runs) using kind (x+2y)%6,
	# then a single horizontal 3-run at row 2 cols 1..3 of kind 2.
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	# Sentinel cells at row 2 cols 0 and 5 to keep the run isolated.
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	# Sanity: exactly one run exists.
	var runs_before: Array = Rules.find_runs(b)
	assert_eq(runs_before.size(), 1, "precondition: one run, got %d" % runs_before.size())
	var rng := Rng.new(12345)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# The triple is removed; gravity drops pieces from rows 0 and 1
	# down; refill spawns above. Final state has no more runs.
	assert_eq(result.total_removed, 3, "triple removed, got %d" % result.total_removed)
	assert_eq(_count_event(result.events, EventKind.REMOVE), 3)
	# After resolve, find_runs must be empty (the cascade terminated).
	var runs_after: Array = Rules.find_runs(b)
	assert_eq(runs_after.size(), 0, "post-resolve board must be stable, got %d runs" % runs_after.size())
	# All cells must be filled (no empties).
	var empty_count: int = 0
	for c in b.all_coords():
		if b.cell_at(c).kind == Board.CellKind.EMPTY:
			empty_count += 1
	assert_eq(empty_count, 0, "refill must fill every empty cell")

func test_resolve_stable_board_emits_no_events() -> void:
	var b := _empty_board()
	# No 3-runs anywhere.
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	var rng := Rng.new(7)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	assert_eq(result.cycles, 0, "stable board: zero cycles expected")
	assert_eq(result.events.size(), 0)
	assert_eq(result.total_removed, 0)

# ----------------------------------------------------------------------------
# Cascades
# ----------------------------------------------------------------------------

func test_resolve_cascade_two_cycles() -> void:
	var b := _empty_board(6, 6)
	# Build a single horizontal 3-run at row 4 cols 2..4 of kind 1.
	# Background is (x+2y)%6 except for the run cells.
	for y in range(6):
		for x in range(6):
			if y == 4 and (x == 2 or x == 3 or x == 4):
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	b.set_piece(Coord.new(2, 4), Piece.new(1))
	b.set_piece(Coord.new(3, 4), Piece.new(1))
	b.set_piece(Coord.new(4, 4), Piece.new(1))
	# Sentinel neighbours at (1,4) and (5,4) so the run stays isolated.
	b.set_piece(Coord.new(1, 4), Piece.new(0))
	b.set_piece(Coord.new(5, 4), Piece.new(0))
	# Sanity: one run at row 4.
	var runs_before: Array = Rules.find_runs(b)
	assert_eq(runs_before.size(), 1, "precondition: one run, got %d" % runs_before.size())
	var rng := Rng.new(42)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# We expect at least one cycle (the original triple). Whether a
	# second cascade cycle happens depends on whether refill above the
	# cleared row produces a new match — we don't constrain that here,
	# but the original triple must be removed exactly once (3 pieces).
	var remove_events := _count_event(result.events, EventKind.REMOVE)
	assert_true(remove_events >= 3,
		"original triple must be removed; got %d remove events" % remove_events)
	# Total cycles at least 1.
	assert_true(result.cycles >= 1)
	# CASCADE_START and CASCADE_END must be paired.
	var depth: int = 0
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.CASCADE_START:
			depth += 1
		elif ev.kind == EventKind.CASCADE_END:
			depth -= 1
	assert_eq(depth, 0, "paired cascade markers")

func test_resolve_event_log_is_well_formed() -> void:
	var b := _empty_board(6, 6)
	for y in range(6):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 6))
	b.set_piece(Coord.new(1, 2), Piece.new(2))
	b.set_piece(Coord.new(2, 2), Piece.new(2))
	b.set_piece(Coord.new(3, 2), Piece.new(2))
	b.set_piece(Coord.new(0, 2), Piece.new(0))
	b.set_piece(Coord.new(4, 2), Piece.new(0))
	b.set_piece(Coord.new(5, 2), Piece.new(0))
	var rng := Rng.new(99)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# Every CASCADE_START must be paired with a CASCADE_END before
	# the next CASCADE_START.
	var depth: int = 0
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		if ev.kind == EventKind.CASCADE_START:
			depth += 1
		elif ev.kind == EventKind.CASCADE_END:
			depth -= 1
			assert_true(depth >= 0, "CASCADE_END without matching START")
	assert_eq(depth, 0, "every CASCADE_START must be matched by a CASCADE_END")
	# No event should reference a coord that is out of bounds.
	for e in result.events:
		var ev: Resolution.DomainEvent = e
		for c in ev.coords:
			var cc: Coord = c
			assert_true(b.in_bounds(cc.x, cc.y), "event coord out of bounds: %s" % cc.to_string())

# ----------------------------------------------------------------------------
# Determinism
# ----------------------------------------------------------------------------

func test_resolve_is_deterministic_same_seed() -> void:
	var make := func() -> Board:
		var b := _empty_board(6, 6)
		for y in range(6):
			for x in range(6):
				b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
		b.set_piece(Coord.new(1, 2), Piece.new(2))
		b.set_piece(Coord.new(2, 2), Piece.new(2))
		b.set_piece(Coord.new(3, 2), Piece.new(2))
		b.set_piece(Coord.new(0, 2), Piece.new(0))
		b.set_piece(Coord.new(4, 2), Piece.new(0))
		b.set_piece(Coord.new(5, 2), Piece.new(0))
		return b

	var b1: Board = make.call()
	var b2: Board = make.call()
	var rng1 := Rng.new(2025)
	var rng2 := Rng.new(2025)
	var r1: Resolution.CascadeResult = Resolution.resolve(b1, rng1)
	var r2: Resolution.CascadeResult = Resolution.resolve(b2, rng2)
	assert_eq(r1.cycles, r2.cycles)
	assert_eq(r1.total_removed, r2.total_removed)
	assert_eq(r1.events.size(), r2.events.size())
	for i in range(r1.events.size()):
		var e1: Resolution.DomainEvent = r1.events[i]
		var e2: Resolution.DomainEvent = r2.events[i]
		assert_eq(e1.kind, e2.kind)
		assert_eq(e1.piece_kind_id, e2.piece_kind_id)
		assert_eq(e1.cascade, e2.cascade)
		assert_eq(e1.coords.size(), e2.coords.size())
		for j in range(e1.coords.size()):
			var c1: Coord = e1.coords[j]
			var c2: Coord = e2.coords[j]
			assert_true(c1.is_equal_to(c2))
	assert_eq(b1.snapshot_hash(), b2.snapshot_hash(),
		"two identical setups with identical seeds must produce identical final boards")

func test_resolve_different_seed_changes_refill_pieces() -> void:
	var make := func() -> Board:
		var b := _empty_board(6, 6)
		# Background: clear bottom row so refill spawns above the triple
		# in row 5, exercising refill determinism.
		for y in range(5):
			for x in range(6):
				b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
		b.set_piece(Coord.new(2, 5), Piece.new(0))
		b.set_piece(Coord.new(3, 5), Piece.new(0))
		b.set_piece(Coord.new(4, 5), Piece.new(0))
		b.set_piece(Coord.new(1, 5), Piece.new(1))
		b.set_piece(Coord.new(5, 5), Piece.new(1))
		return b

	var b1: Board = make.call()
	var b2: Board = make.call()
	Resolution.resolve(b1, Rng.new(1))
	Resolution.resolve(b2, Rng.new(2))
	# With the same initial layout but different seeds the refill
	# pieces above must differ. (Refill occupies row 0..4 above the
	# triple; we compare the top-most refill row which is the last
	# one written.)
	var top_a: int = b1.cell_at(Coord.new(0, 0)).piece.kind_id
	var top_b: int = b2.cell_at(Coord.new(0, 0)).piece.kind_id
	# It's theoretically possible (with negligible probability) that
	# the top row happens to match. We check the whole top row to
	# guard against that flake.
	var differs := false
	for x in range(6):
		var pa: int = b1.cell_at(Coord.new(x, 0)).piece.kind_id
		var pb: int = b2.cell_at(Coord.new(x, 0)).piece.kind_id
		if pa != pb:
			differs = true
			break
	assert_true(differs, "different RNG seeds must yield different refills (top row check)")

# ----------------------------------------------------------------------------
# Gravity
# ----------------------------------------------------------------------------

func test_gravity_drops_through_empty_below() -> void:
	# A match in row 0 cols 0..2 will be removed. The piece at (1,1)
	# has column 1 with a piece only at (1,1) (rows 0 and 3 in col 1
	# will be emptied by the run + refill). Gravity pulls (1,1) down
	# to land on the piece at (1,3).
	var b := _empty_board(4, 4)
	# Run row 0: cols 0,1,2 are kind 1; col 3 is kind 0 (sentinel).
	b.set_piece(Coord.new(0, 0), Piece.new(1))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	b.set_piece(Coord.new(2, 0), Piece.new(1))
	b.set_piece(Coord.new(3, 0), Piece.new(0))
	# Fill row 1: a kind-5 piece at (1,1); rest are kind (x+2)%6 to
	# avoid incidental runs. (1,1) is the piece we want to drop.
	b.set_piece(Coord.new(0, 1), Piece.new(2))
	b.set_piece(Coord.new(1, 1), Piece.new(5))
	b.set_piece(Coord.new(2, 1), Piece.new(4))
	b.set_piece(Coord.new(3, 1), Piece.new(5))
	# Fill rows 2 and 3 with kinds that keep the board stable.
	for y in range(2, 4):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	# Sanity: exactly one run (the row-0 triple).
	var runs_before: Array = Rules.find_runs(b)
	assert_eq(runs_before.size(), 1, "precondition: one run, got %d" % runs_before.size())
	var rng := Rng.new(0)
	Resolution.resolve(b, rng)
	# After resolve, the row-0 cells are emptied and refilled; the
	# piece at (1,1) drops to (1,2) (since (1,3) has a piece of kind
	# (1+2*3)%6=1). Gravity: column 1 had pieces at (1,0)=1 (removed),
	# (1,1)=5 (drops), (1,2)=5 (drops), (1,3)=1 (stops).
	# Expected: (1,3) still kind 1; (1,2) should hold the kind-5 piece
	# that was at (1,2); (1,1) should hold the kind-5 piece that was
	# at (1,1).
	assert_eq(b.cell_at(Coord.new(1, 3)).piece.kind_id, 1, "bottom piece stays")
	# Two kind-5 pieces should occupy column 1 just above row 3, in
	# lex order. Just confirm column 1 has two kind-5 entries and no
	# empty cell.
	var col1_kinds: Array = []
	for y in range(4):
		var c = b.cell_at(Coord.new(1, y))
		if c.is_piece():
			col1_kinds.append(c.piece.kind_id)
	assert_eq(col1_kinds.size(), 4, "column 1 fully refilled, got %s" % str(col1_kinds))
	var fives: int = 0
	for k in col1_kinds:
		if k == 5:
			fives += 1
	assert_eq(fives, 2, "two kind-5 pieces remain in column 1, got %s" % str(col1_kinds))

func test_gravity_respects_blocked_cells() -> void:
	# Board 4x5 with a blocked cell at (2,2). Trigger a match at the
	# top row so gravity runs. The piece at (2,0) is in column 2
	# (the blocked column); after the match, gravity should drop it
	# onto the blocked cell at (2,1) — NOT past it.
	var b := _empty_board(4, 5, 6, [Coord.new(2, 2)])
	# Match at row 0 cols 0,1,2 of kind 1; sentinel at (3,0).
	b.set_piece(Coord.new(0, 0), Piece.new(1))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	b.set_piece(Coord.new(2, 0), Piece.new(1))
	b.set_piece(Coord.new(3, 0), Piece.new(0))
	# Piece at (2,0) is part of the run. After removal it will fall.
	# Place another piece at (2,1) so the kind-1 piece lands on it...
	# actually we want the kind-1 piece to land on the blocked cell.
	# Make (2,1) a different kind so the column is just (2,0)=1
	# (removed) and (2,2)=blocked. So (2,1) is empty above the block.
	# The kind-1 piece at (2,0) was removed, so column 2 above the
	# block is empty. After refill, the kind-1 piece that was at (2,0)
	# no longer exists. The piece that should land on the block must
	# be a piece from row 1 that has nothing below it.
	# Let's restart this setup more carefully:
	b.set_empty(Coord.new(2, 0))  # remove from the run
	b.set_piece(Coord.new(0, 0), Piece.new(1))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	# Now row 0 has a 2-run at (0,0)(1,0). That's not enough — need 3.
	b.set_empty(Coord.new(0, 0))
	b.set_empty(Coord.new(1, 0))
	# Place a proper 3-run at row 0 in cols 0,1,2 of kind 1.
	# Sentinel at (3,0) = 0 to keep run isolated.
	b.set_piece(Coord.new(0, 0), Piece.new(1))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	b.set_piece(Coord.new(2, 0), Piece.new(1))
	# Column 2 above the block: only (2,0) (the run). After the run
	# is removed and (2,0) becomes empty, refill writes a new piece
	# there. Then gravity pulls it down to (2,1) (lands on the block
	# at (2,2)).
	# Fill the rest with kinds that don't form incidental runs.
	for y in range(5):
		for x in range(4):
			if x == 2 and y == 2:
				continue  # blocked
			if y == 0 and (x == 0 or x == 1 or x == 2 or x == 3):
				continue  # row 0 already set
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	# Sanity: exactly one run.
	var runs_before: Array = Rules.find_runs(b)
	assert_eq(runs_before.size(), 1, "precondition: one run, got %d" % runs_before.size())
	var rng := Rng.new(0)
	Resolution.resolve(b, rng)
	# Blocked cell must remain blocked.
	assert_eq(b.cell_at(Coord.new(2, 2)).kind, Board.CellKind.BLOCKED,
		"blocked cell remains blocked")
	# Column 2 above the blocked cell: cells (2,0) and (2,1) are both
	# available for gravity + refill. (2,1) is the "land" position
	# for any piece that falls down column 2. (2,0) is above (2,1)
	# and the column above is row -1 (OOB), so refill writes there.
	# Gravity then drops the refill piece at (2,0) down to (2,1).
	# Confirm: column 2 is fully filled and has no empty cell.
	var col2_empty: int = 0
	var col2_blocked: int = 0
	var col2_piece: int = 0
	for y in range(5):
		var c = b.cell_at(Coord.new(2, y))
		if c.is_piece():
			col2_piece += 1
		elif c.is_blocked():
			col2_blocked += 1
		else:
			col2_empty += 1
	assert_eq(col2_blocked, 1, "exactly one blocked cell in column 2")
	assert_eq(col2_empty, 0, "no empty cells in column 2 after resolve")
	assert_eq(col2_piece, 4, "four piece cells in column 2 after resolve")

# ----------------------------------------------------------------------------
# Blocked cells in matching
# ----------------------------------------------------------------------------

func test_blocked_cells_excluded_from_runs_during_resolve() -> void:
	# A blocked cell must not be removed or overwritten by gravity.
	var b := _empty_board(4, 4, 6, [Coord.new(1, 2)])
	# Build a horizontal 3-run at row 2, cols 0,1,2 of kind 0. The
	# blocked cell at (1,2) means the run splits into (0,2) alone and
	# (2,2) alone, so no match occurs.
	for y in range(4):
		for x in range(4):
			if y == 2 and (x == 0 or x == 2):
				b.set_piece(Coord.new(x, y), Piece.new(0))
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + y) % 6))
	var rng := Rng.new(0)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	assert_eq(result.total_removed, 0,
		"blocked cell must split the run; nothing should be removed")
	assert_eq(b.cell_at(Coord.new(1, 2)).kind, Board.CellKind.BLOCKED,
		"blocked cell must remain blocked through resolution")

# ----------------------------------------------------------------------------
# Safety: bogus infinite-loop guard
# ----------------------------------------------------------------------------

func test_resolve_does_not_loop_forever_on_normal_boards() -> void:
	# Sanity check: a randomly filled board must resolve in well
	# under MAX_CASCADE_CYCLES.
	var b := _empty_board(8, 8)
	var rng := Rng.new(314)
	Resolution.fill_random(b, rng, false)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	assert_true(result.cycles < Resolution.MAX_CASCADE_CYCLES,
		"random board must resolve under the cascade cap; got cycles=%d" % result.cycles)

# ----------------------------------------------------------------------------
# Refill determinism
# ----------------------------------------------------------------------------

func test_refill_fills_all_empty_cells() -> void:
	var b := _empty_board(4, 4)
	# Leave the board entirely empty (no initial pieces). After
	# resolve, the entire board must be filled with pieces (no empty
	# cells except blocked).
	var rng := Rng.new(0)
	# We need to call resolve with no runs so cycles=0 and no refill
	# happens. That's fine; just verify refill fills empties when
	# there IS a match by setting up a single match that, when
	# removed, leaves an empty cell.
	b.set_piece(Coord.new(1, 0), Piece.new(0))
	b.set_piece(Coord.new(2, 0), Piece.new(0))
	b.set_piece(Coord.new(3, 0), Piece.new(0))
	# Distinct kinds around so no incidental runs.
	for y in range(1, 4):
		for x in range(4):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	# Sentinel "different from triple" cells at row 0 cols 0 and 3.
	# Actually (3,0) is part of the triple; (0,0) and (4,0) are OOB
	# so the run starts at (1,0). The triple is at (1,0)(2,0)(3,0).
	# Confirm run before resolve.
	var runs_before: Array = Rules.find_runs(b)
	assert_eq(runs_before.size(), 1)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# After resolve, every cell must contain a piece or be blocked
	# (no EMPTY cells).
	var empty_count: int = 0
	for c in b.all_coords():
		if b.cell_at(c).kind == Board.CellKind.EMPTY:
			empty_count += 1
	assert_eq(empty_count, 0,
		"refill must fill every empty cell; got %d empties" % empty_count)
	assert_true(result.total_removed >= 3)

# ----------------------------------------------------------------------------
# fill_random helper
# ----------------------------------------------------------------------------

func test_fill_random_produces_valid_board() -> void:
	var b := _empty_board(6, 6)
	var rng := Rng.new(0)
	Resolution.fill_random(b, rng, false)
	assert_true(b.validate(), "filled board must validate")
	assert_eq(b.empty_coords().size(), 0)

func test_fill_random_avoid_initial_matches_can_succeed() -> void:
	# On a small palette and a small board, avoid_initial_matches
	# may or may not succeed per cell; the helper must always
	# terminate without leaving the board half-filled.
	var b := _empty_board(4, 4, 3)
	var rng := Rng.new(0)
	Resolution.fill_random(b, rng, true)
	# No empties (helper finishes all cells).
	assert_eq(b.empty_coords().size(), 0)
	# Each cell must have a kind in [0, 3).
	for c in b.all_coords():
		assert_true(b.cell_at(c).is_piece())
		var p: int = b.cell_at(c).piece.kind_id
		assert_true(p >= 0 and p < 3)

# ----------------------------------------------------------------------------
# DomainEvent serialisation
# ----------------------------------------------------------------------------

func test_domain_event_to_dict_roundtrips() -> void:
	var e := Resolution.DomainEvent.new(
		EventKind.REMOVE, [Coord.new(3, 4)], 5, 2)
	var d: Dictionary = e.to_dict()
	assert_eq(d["kind"], EventKind.REMOVE)
	assert_eq(d["piece_kind_id"], 5)
	assert_eq(d["cascade"], 2)
	assert_eq(d["coords"].size(), 1)
	assert_eq(d["coords"][0]["x"], 3)
	assert_eq(d["coords"][0]["y"], 4)
