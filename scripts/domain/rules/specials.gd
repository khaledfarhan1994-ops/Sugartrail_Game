class_name SugartrailSpecials
extends RefCounted
## Special-piece creation and activation for the deterministic domain.
##
## Step 13 introduces four special-piece kinds that arise from match
## shapes (see docs/02-game-design.md §3):
##
##   - 4-in-a-line (H or V)         -> STRIPED_ROW / STRIPED_COL
##   - 5-in-a-line  (H or V)         -> COLOR_BOMB (clears all of one kind)
##   - T or L shape (3+3 sharing 1)  -> AREA clearer (3x3)
##
## A 3-run produces no special. Precedence when shapes overlap is
## strict: 5 > 4 > T/L. The chosen cell for a 4-run is the swap cell
## if it lies inside the run, otherwise the lex-earlier centre cell.
## A 5-run always picks the run's centre cell. T/L always picks the
## shared intersection cell.
##
## All Step-13 specials detonate the cycle they are created
## (`needs_activation = false`). Step 14 adds special+special
## combinations: when the player swaps two cells both holding
## SpecialPieces (without forming a 3-run), the swap is legal and the
## resolution cycle runs `activate_combo` to clear the combined
## effect. The combo cleared list is deduped and lex-sorted. See
## docs/02-game-design.md §3.3 for the full 12-row matrix.
##
## Activation effects (per cycle, deduped, lex-ordered):
##
##   - STRIPED_ROW -> clears every cell in the special's row
##   - STRIPED_COL -> clears every cell in the special's column
##   - COLOR_BOMB  -> clears every piece whose kind_id matches the bomb
##   - AREA        -> clears the 3x3 box centred on the special
##                    (clipped at the board edge; blocked cells excluded)
##
## The cycle's event log emits SPECIAL_CREATE (one per created special)
## then SPECIAL_ACTIVATE (one per activated special, carrying its
## cleared list) then the normal REMOVE / MOVE / SPAWN events.
##
## Determinism: same board + same player-action context (swap_a /
## swap_b passed by resolution) + same RNG produces the same set of
## created specials, the same cleared cells, and the same event log.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Coord = Board.CellCoord
const CellKind = Board.CellKind
const Piece = Board.Piece
const SpecialPiece = Board.SpecialPiece
const Special = Board.Special
const SpecialKind = Board.SpecialKind

## Returned by `detect_special_creations`. Maps CellCoord -> Special
## describing which cells become specials this cycle.
##
## Keys are the cell that should be promoted to a SpecialPiece;
## values are the Special metadata (kind, orientation, needs_activation).
##
## Deterministic: callers iterate over the runs in stable lex order,
## so the returned dictionary has the same insertion order across
## runs that are byte-for-byte equal.
class CreationPlan:
	var swap_a: Coord = null
	var swap_b: Coord = null
	## Map CellCoord -> Special. Iteration order is lex-sorted on the
	## keys for determinism (no Dictionary reliance).
	var entries: Array = []  # Array of {coord: Coord, special: Special}

	func _init(p_swap_a: Coord = null, p_swap_b: Coord = null) -> void:
		swap_a = p_swap_a
		swap_b = p_swap_b
		entries = []

	func has_creation_at(coord: Coord) -> bool:
		for e in entries:
			var ee: Dictionary = e
			var c: Coord = ee["coord"]
			if c.is_equal_to(coord):
				return true
		return false

	func get_special_at(coord: Coord) -> Special:
		for e in entries:
			var ee: Dictionary = e
			var c: Coord = ee["coord"]
			if c.is_equal_to(coord):
				return ee["special"]
		return null

	func add_creation(coord: Coord, special: Special) -> void:
		entries.append({"coord": coord, "special": special})

	func sorted_entries() -> Array:
		var out: Array = []
		for e in entries:
			out.append(e)
		out.sort_custom(func(a, b):
			var ca: Coord = a["coord"]
			var cb: Coord = b["coord"]
			return Coord.compare(ca, cb))
		return out

## Detect which cells of the matched runs should become specials.
## `runs` is the same Array of Arrays of CellCoord returned by
## `Rules.find_runs`. `swap_a` / `swap_b` describe the player action
## that triggered this cycle (both may be null when not applicable,
## e.g. cascade cycles after the first swap).
##
## Algorithm: build a per-cell "what special kind wins here" map with
## strict precedence (5 > 4 > T/L). The 5-run kind always wins for
## any cell it covers; the 4-run kind beats T/L; the T/L kind is
## only assigned when no 4+/5-run covers the cell. The map is then
## converted to a CreationPlan (one entry per cell with a special).
static func detect_special_creations(runs: Array, swap_a: Coord = null, swap_b: Coord = null) -> CreationPlan:
	var plan := CreationPlan.new(swap_a, swap_b)
	# cell_key -> { "kind": int, "orientation": int, "precedence": int }
	# Precedence: 5-run = 3, 4-run = 2, T/L = 1. Higher wins.
	var cell_assignments: Dictionary = {}
	# Pre-compute sorted run indices (lex by first coord of each run)
	# so iteration order is deterministic.
	var indexed_runs: Array = []
	for i in range(runs.size()):
		var run: Array = runs[i]
		indexed_runs.append({"idx": i, "first": _first_coord(run)})
	indexed_runs.sort_custom(func(a, b):
		var ca: Coord = a["first"]
		var cb: Coord = b["first"]
		return Coord.compare(ca, cb))
	# First pass: compute T/L cells (a coord shared by exactly two
	# 3-runs in a + pattern). Also record whether any 5+ run exists
	# (when present, 4-runs and T/L shapes are downgraded).
	var coord_to_run_indices: Dictionary = {}  # key -> Array of run indices
	var has_five_plus: bool = false
	for ri in range(runs.size()):
		var run: Array = runs[ri]
		if run.size() >= 5:
			has_five_plus = true
		if run.size() != 3:
			continue
		for c in run:
			var cc: Coord = c
			var key: String = "%d,%d" % [cc.x, cc.y]
			if not coord_to_run_indices.has(key):
				coord_to_run_indices[key] = []
			(coord_to_run_indices[key] as Array).append(ri)
	# A coord is a T/L cell when it's covered by exactly two distinct
	# 3-runs. (Two 3-runs in a + share one cell.)
	var t_l_cells: Dictionary = {}
	for key in coord_to_run_indices.keys():
		var ri_array: Array = coord_to_run_indices[key]
		if ri_array.size() == 2 and (ri_array[0] as int) != (ri_array[1] as int):
			t_l_cells[key] = true
	# Second pass: for each run in lex order, propose a special at
	# the run's chosen cell(s). Higher precedence wins per cell.
	# When a 5+ run is present, 4-runs and T/L shapes are downgraded
	# to plain clears (the 5-run takes precedence globally).
	for entry in indexed_runs:
		var ri: int = entry["idx"]
		var run: Array = runs[ri]
		var run_size: int = run.size()
		if run_size == 3:
			if has_five_plus:
				continue
			# T/L candidates: the shared cell (only one per pair of
			# 3-runs, by construction).
			for c in run:
				var cc: Coord = c
				var key: String = "%d,%d" % [cc.x, cc.y]
				if not t_l_cells.has(key):
					continue
				_propose_assignment(cell_assignments, key, cc,
						SpecialKind.AREA, 0, 1)
			continue
		if run_size == 4:
			if has_five_plus:
				continue
			var orientation: int = 0 if _is_horizontal_run(run) else 1
			var special_kind: int = SpecialKind.STRIPED_ROW if orientation == 0 else SpecialKind.STRIPED_COL
			var chosen: Coord = _pick_striped_cell(run, swap_a, swap_b)
			var key: String = "%d,%d" % [chosen.x, chosen.y]
			_propose_assignment(cell_assignments, key, chosen,
					special_kind, orientation, 2)
			continue
		if run_size >= 5:
			var centre: Coord = _centre_of(run)
			var key: String = "%d,%d" % [centre.x, centre.y]
			_propose_assignment(cell_assignments, key, centre,
					SpecialKind.COLOR_BOMB, 0, 3)
			continue
	# Convert cell_assignments to a CreationPlan in lex order.
	var keys: Array = []
	for k in cell_assignments.keys():
		keys.append(k)
	keys.sort_custom(func(a, b):
		var pa: PackedStringArray = a.split(",")
		var pb: PackedStringArray = b.split(",")
		var ax: int = int(pa[0])
		var ay: int = int(pa[1])
		var bx: int = int(pb[0])
		var by: int = int(pb[1])
		if ay != by:
			return ay < by
		return ax < bx)
	for key in keys:
		var entry: Dictionary = cell_assignments[key]
		var coord: Coord = entry["coord"]
		var kind: int = entry["kind"]
		var orientation: int = entry["orientation"]
		plan.add_creation(coord, Special.new(kind, orientation, false))
	return plan

## Helper for `detect_special_creations`. Proposes a special at a
## cell; if an existing assignment has higher precedence, the
## proposal is dropped. If equal precedence, the lex-smaller cell
## already won (because runs are iterated in lex order) and the
## later proposal is dropped.
static func _propose_assignment(cell_assignments: Dictionary,
		key: String, coord: Coord, kind: int, orientation: int,
		precedence: int) -> void:
	if cell_assignments.has(key):
		var existing: Dictionary = cell_assignments[key]
		if (existing["precedence"] as int) >= precedence:
			return
	cell_assignments[key] = {
		"coord": coord,
		"kind": kind,
		"orientation": orientation,
		"precedence": precedence,
	}

## Apply the creation plan to the board. Each entry's cell is set
## to a SpecialPiece carrying the run's normal kind (substituted
## by the caller for COLOR_BOMB).
static func apply_creations(board: Board, plan: CreationPlan,
		kind_for_coord: Dictionary) -> void:
	for entry in plan.sorted_entries():
		var cc: Coord = entry["coord"]
		var spec: Special = entry["special"]
		var key: String = "%d,%d" % [cc.x, cc.y]
		var kind_id: int = int(kind_for_coord.get(key, 0))
		var cell = board.cell_at(cc)
		if cell == null:
			continue
		cell.piece = SpecialPiece.new(kind_id, spec)

## Activate a single special at `origin`. Returns a Dictionary
## describing the activation result:
##   {
##     "kind": int (SpecialKind),
##     "center": Coord (the activation epicentre),
##     "color": int (kind_id for COLOR_BOMB; 0 otherwise),
##     "cleared": Array[Coord] (cells the special cleared),
##   }
##
## Blocked cells are excluded from `cleared`.
static func activate(board: Board, origin: Coord,
		_trigger_kind: int = -1, trigger_kind_id: int = -1) -> Dictionary:
	var cell = board.cell_at(origin)
	if cell == null or cell.piece == null or not (cell.piece is SpecialPiece):
		return {"kind": SpecialKind.NONE, "center": origin, "color": 0, "cleared": []}
	var sp: SpecialPiece = cell.piece
	var kind: int = sp.special.kind
	var out: Array = []
	match kind:
		SpecialKind.STRIPED_ROW:
			out = _strip_cells_row(board, origin.y)
		SpecialKind.STRIPED_COL:
			out = _strip_cells_col(board, origin.x)
		SpecialKind.COLOR_BOMB:
			out = _color_clear_cells(board, trigger_kind_id if trigger_kind_id >= 0 else sp.kind_id)
		SpecialKind.AREA:
			out = _area_cells(board, origin)
		_:
			out = []
	# Filter blocked cells.
	var filtered: Array = []
	for c in out:
		var cc: Coord = c
		var bc = board.cell_at(cc)
		if bc != null and not bc.is_blocked():
			filtered.append(cc)
	# Always include the special's own cell (the activation consumes
	# itself) unless blocked.
	var blocked_self: bool = cell.is_blocked()
	if not blocked_self:
		var already: bool = false
		for c in filtered:
			var cc: Coord = c
			if cc.is_equal_to(origin):
				already = true
				break
		if not already:
			filtered.append(origin)
	filtered.sort_custom(func(a, b):
		var ca: Coord = a
		var cb: Coord = b
		return Coord.compare(ca, cb))
	return {
		"kind": kind,
		"center": origin,
		"color": sp.kind_id,
		"cleared": filtered,
	}

## Produce the activation clear list for one or more specials in
## one cycle. Returns:
##   {
##     "activations": Array of (origin: Coord, result: Dictionary from activate),
##     "cleared": Array[Coord] (deduped, lex-sorted across all activations),
##   }
static func activate_all(board: Board, plan: CreationPlan,
		existing_special_cells: Array, kind_for_coord: Dictionary) -> Dictionary:
	var activations: Array = []
	var all_cleared: Dictionary = {}
	# First, specials created this cycle (by creation plan).
	for entry in plan.sorted_entries():
		var cc: Coord = entry["coord"]
		var result: Dictionary = activate(board, cc, -1, int(kind_for_coord.get("%d,%d" % [cc.x, cc.y], 0)))
		activations.append({"origin": cc, "result": result})
		for c in result["cleared"]:
			var cx: Coord = c
			all_cleared["%d,%d" % [cx.x, cx.y]] = cx
	# Then, specials that were already on the board and are now part
	# of a match (their cell is in `existing_special_cells`).
	for spc in existing_special_cells:
		var cell_coord: Coord = spc
		var key: String = "%d,%d" % [cell_coord.x, cell_coord.y]
		if all_cleared.has(key):
			continue  # already activated as part of a creation
		var cell = board.cell_at(cell_coord)
		if cell == null or cell.piece == null or not (cell.piece is SpecialPiece):
			continue
		var sp: SpecialPiece = cell.piece
		if sp.special.needs_activation == false:
			# Same-cycle detonation rule: Step 13 specials detonate
			# now. Activation triggered by the match itself.
			var trigger_kind_id: int = int(kind_for_coord.get(key, sp.kind_id))
			var result: Dictionary = activate(board, cell_coord, -1, trigger_kind_id)
			activations.append({"origin": cell_coord, "result": result})
			for c in result["cleared"]:
				var cx: Coord = c
				all_cleared["%d,%d" % [cx.x, cx.y]] = cx
	# Sort cleared cells lex.
	var cleared_sorted: Array = []
	for k in all_cleared.keys():
		cleared_sorted.append(all_cleared[k])
	cleared_sorted.sort_custom(func(a, b):
		var ca: Coord = a
		var cb: Coord = b
		return Coord.compare(ca, cb))
	return {"activations": activations, "cleared": cleared_sorted}

# ----------------------------------------------------------------------------
# Pure helpers (testable in isolation)
# ----------------------------------------------------------------------------

static func _is_horizontal_run(run: Array) -> bool:
	if run.size() < 2:
		return false
	var first: Coord = run[0]
	for i in range(1, run.size()):
		var ci: Coord = run[i]
		if ci.y != first.y:
			return false
	return true

static func _first_coord(run: Array) -> Coord:
	var out: Coord = run[0]
	for c in run:
		var cc: Coord = c
		if Coord.compare(cc, out):
			out = cc
	return out

static func _centre_of(run: Array) -> Coord:
	# Lex-earliest cell is the smallest by (y, x); pick the median by
	# index. For odd sizes, that's the true centre. For even sizes,
	# the lex-earlier of the two middle cells.
	var sorted: Array = []
	for c in run:
		sorted.append(c)
	sorted.sort_custom(func(a, b):
		var ca: Coord = a
		var cb: Coord = b
		return Coord.compare(ca, cb))
	var n: int = sorted.size()
	if n == 0:
		return Coord.new(0, 0)
	return sorted[(n - 1) / 2]

static func _pick_striped_cell(run: Array, swap_a: Coord, swap_b: Coord) -> Coord:
	# If either swap coord lies inside the run, that coord is the
	# special. Swap order doesn't matter.
	if swap_a != null:
		for c in run:
			var cc: Coord = c
			if cc.is_equal_to(swap_a):
				return swap_a
	if swap_b != null:
		for c in run:
			var cc: Coord = c
			if cc.is_equal_to(swap_b):
				return swap_b
	# Else the centre (lex-earlier of the middle cells).
	return _centre_of(run)

static func _strip_cells_row(board: Board, y: int) -> Array:
	var out: Array = []
	if y < 0 or y >= board.config.height:
		return out
	for x in range(board.config.width):
		out.append(Coord.new(x, y))
	return out

static func _strip_cells_col(board: Board, x: int) -> Array:
	var out: Array = []
	if x < 0 or x >= board.config.width:
		return out
	for y in range(board.config.height):
		out.append(Coord.new(x, y))
	return out

static func _color_clear_cells(board: Board, kind_id: int) -> Array:
	var out: Array = []
	for c in board.all_piece_coords():
		var cell = board.cell_at(c)
		if cell != null and cell.is_piece() and cell.piece.kind_id == kind_id:
			out.append(c)
	return out

static func _area_cells(board: Board, center: Coord) -> Array:
	var out: Array = []
	for dy in range(-1, 2):
		for dx in range(-1, 2):
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x < 0 or x >= board.config.width:
				continue
			if y < 0 or y >= board.config.height:
				continue
			out.append(Coord.new(x, y))
	return out

static func _area_5x5_cells(board: Board, center: Coord) -> Array:
	var out: Array = []
	for dy in range(-2, 3):
		for dx in range(-2, 3):
			var x: int = center.x + dx
			var y: int = center.y + dy
			if x < 0 or x >= board.config.width:
				continue
			if y < 0 or y >= board.config.height:
				continue
			out.append(Coord.new(x, y))
	return out

# ----------------------------------------------------------------------------
# Step 14: special + special combinations
# ----------------------------------------------------------------------------

## Descriptor for one combo. `cleared_fn` is a Callable that takes
## the board and returns a deduped list of cleared cells. The kind
## enum is kept on the descriptor for logging / event payload.
class ComboSpec:
	var a_kind: int = SpecialKind.NONE
	var b_kind: int = SpecialKind.NONE
	var result_kind: int = SpecialKind.NONE
	var cleared_fn: Callable = Callable()

	func _init(p_a: int, p_b: int, p_result: int, p_fn: Callable) -> void:
		a_kind = p_a
		b_kind = p_b
		result_kind = p_result
		cleared_fn = p_fn

## Keying for the combinator table. Order-invariant: `[min, max]`
## yields the same lookup as `[max, min]`.
static func _combo_key(a: int, b: int) -> Array:
	var lo: int = a
	var hi: int = b
	if lo > hi:
		var tmp: int = lo
		lo = hi
		hi = tmp
	return [lo, hi]

## Build the static combinator table. Each entry maps a pair of
## special kinds to the cleared-cell list produced by the swap.
##
## The table is keyed by `(min_kind, max_kind)` so the order of the
## two input coords does not matter. Each entry's `cleared_fn`
## receives the same 4-argument array `(row_origin, col_origin,
## area_origin, bomb_origin)` regardless of swap direction; the
## helper decides which cell is which based on which special kind
## is paired with what.
##
## The closures inspect the passed kinds so they produce the same
## cleared set regardless of which input cell is `a` and which is
## `b`.
static func _build_combo_table(board: Board, a_origin: Coord, b_origin: Coord,
		a_kind: int, b_kind: int, a_kind_id: int, b_kind_id: int) -> Dictionary:
	var table: Dictionary = {}
	# Helper closures ----------------------------------------------------
	# Striped-row at `coord` -> every cell in its row.
	var row_strip := func(coord: Coord) -> Array:
		return _strip_cells_row(board, coord.y)
	# Striped-col at `coord` -> every cell in its column.
	var col_strip := func(coord: Coord) -> Array:
		return _strip_cells_col(board, coord.x)
	# Area at `coord` -> 3x3 around it.
	var area_3 := func(coord: Coord) -> Array:
		return _area_cells(board, coord)
	# Area+area -> 5x5 around each epicentre.
	var area_5 := func(coord: Coord) -> Array:
		return _area_5x5_cells(board, coord)
	# Helpers that union two region lists.
	var union := func(left: Array, right: Array) -> Array:
		var seen: Dictionary = {}
		var out: Array = []
		for c in left:
			var cc: Coord = c
			var key: String = "%d,%d" % [cc.x, cc.y]
			if seen.has(key):
				continue
			seen[key] = true
			out.append(cc)
		for c in right:
			var cc2: Coord = c
			var key2: String = "%d,%d" % [cc2.x, cc2.y]
			if seen.has(key2):
				continue
			seen[key2] = true
			out.append(cc2)
		return out
	# Helper: row of `row_origin` + col of `col_origin`.
	var row_plus_col := func(row_origin: Coord, col_origin: Coord) -> Array:
		return union.call(row_strip.call(row_origin), col_strip.call(col_origin))
	# Helper: row + 3x3 when the row is at `row_origin` and the area
	# is at `area_origin`.
	var row_plus_area := func(row_origin: Coord, area_origin: Coord) -> Array:
		return union.call(row_strip.call(row_origin), area_3.call(area_origin))
	# Helper: col + 3x3.
	var col_plus_area := func(col_origin: Coord, area_origin: Coord) -> Array:
		return union.call(col_strip.call(col_origin), area_3.call(area_origin))
	# Helper: each combo closure receives a stdcall dict with the
	# resolved coords for each role. Closed-over helpers read the
	# roles from this dict.
	var make_dispatch := func(combo_fn: Callable) -> Callable:
		# The combo_fn closure is given a Dictionary with the
		# resolved coords for each special role. The closure then
		# computes the cleared region.
		return func() -> Array:
			var roles: Dictionary = _resolve_roles(board, a_origin, b_origin,
					a_kind, b_kind, a_kind_id, b_kind_id)
			return combo_fn.call(roles)
	# Combinator closures ------------------------------------------------
	# Each combinator closure receives a `roles` dict with keys
	# `row_origin`, `col_origin`, `area_origin`, `bomb_origin`,
	# `bomb_kind_id` (any may be null when the combo doesn't involve
	# that role). The closure returns the cleared list.
	var c_striped_row_col := func(roles: Dictionary) -> Array:
		return row_plus_col.call(roles["row_origin"], roles["col_origin"])
	var c_striped_row_row := func(_roles: Dictionary) -> Array:
		# Two rows. Union of both row strips.
		var c1: Coord = a_origin
		var c2: Coord = b_origin
		return union.call(row_strip.call(c1), row_strip.call(c2))
	var c_striped_col_col := func(_roles: Dictionary) -> Array:
		var c1: Coord = a_origin
		var c2: Coord = b_origin
		return union.call(col_strip.call(c1), col_strip.call(c2))
	var c_striped_row_bomb := func(roles: Dictionary) -> Array:
		# Paint the row of the striped (clear every cell in the row).
		return row_strip.call(roles["row_origin"])
	var c_striped_col_bomb := func(roles: Dictionary) -> Array:
		return col_strip.call(roles["col_origin"])
	var c_striped_row_area := func(roles: Dictionary) -> Array:
		return row_plus_area.call(roles["row_origin"], roles["area_origin"])
	var c_striped_col_area := func(roles: Dictionary) -> Array:
		return col_plus_area.call(roles["col_origin"], roles["area_origin"])
	var c_area_area := func(_roles: Dictionary) -> Array:
		return union.call(area_5.call(a_origin), area_5.call(b_origin))
	var c_bomb_bomb := func(_roles: Dictionary) -> Array:
		return board.all_piece_coords()
	var c_bomb_area := func(roles: Dictionary) -> Array:
		var bomb_kind_id: int = int(roles["bomb_kind_id"])
		return union.call(_color_clear_cells(board, bomb_kind_id),
				area_3.call(roles["area_origin"]))
	# ------------------------------------------------------------------
	table[_combo_key(SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_COL)] = ComboSpec.new(
		SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_COL,
		SpecialKind.STRIPED_ROW, make_dispatch.call(c_striped_row_col))
	table[_combo_key(SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_ROW)] = ComboSpec.new(
		SpecialKind.STRIPED_ROW, SpecialKind.STRIPED_ROW,
		SpecialKind.STRIPED_ROW, make_dispatch.call(c_striped_row_row))
	table[_combo_key(SpecialKind.STRIPED_COL, SpecialKind.STRIPED_COL)] = ComboSpec.new(
		SpecialKind.STRIPED_COL, SpecialKind.STRIPED_COL,
		SpecialKind.STRIPED_COL, make_dispatch.call(c_striped_col_col))
	table[_combo_key(SpecialKind.STRIPED_ROW, SpecialKind.COLOR_BOMB)] = ComboSpec.new(
		SpecialKind.STRIPED_ROW, SpecialKind.COLOR_BOMB,
		SpecialKind.COLOR_BOMB, make_dispatch.call(c_striped_row_bomb))
	table[_combo_key(SpecialKind.STRIPED_COL, SpecialKind.COLOR_BOMB)] = ComboSpec.new(
		SpecialKind.STRIPED_COL, SpecialKind.COLOR_BOMB,
		SpecialKind.COLOR_BOMB, make_dispatch.call(c_striped_col_bomb))
	table[_combo_key(SpecialKind.STRIPED_ROW, SpecialKind.AREA)] = ComboSpec.new(
		SpecialKind.STRIPED_ROW, SpecialKind.AREA,
		SpecialKind.AREA, make_dispatch.call(c_striped_row_area))
	table[_combo_key(SpecialKind.STRIPED_COL, SpecialKind.AREA)] = ComboSpec.new(
		SpecialKind.STRIPED_COL, SpecialKind.AREA,
		SpecialKind.AREA, make_dispatch.call(c_striped_col_area))
	table[_combo_key(SpecialKind.AREA, SpecialKind.AREA)] = ComboSpec.new(
		SpecialKind.AREA, SpecialKind.AREA,
		SpecialKind.AREA, make_dispatch.call(c_area_area))
	table[_combo_key(SpecialKind.COLOR_BOMB, SpecialKind.COLOR_BOMB)] = ComboSpec.new(
		SpecialKind.COLOR_BOMB, SpecialKind.COLOR_BOMB,
		SpecialKind.COLOR_BOMB, make_dispatch.call(c_bomb_bomb))
	table[_combo_key(SpecialKind.COLOR_BOMB, SpecialKind.AREA)] = ComboSpec.new(
		SpecialKind.COLOR_BOMB, SpecialKind.AREA,
		SpecialKind.COLOR_BOMB, make_dispatch.call(c_bomb_area))
	return table

## Resolve the per-role coords for a combo. Returns a Dictionary with
## keys `row_origin`, `col_origin`, `area_origin`, `bomb_origin`,
## `bomb_kind_id`. Any role not present in the combo is null.
static func _resolve_roles(_board: Board, a_origin: Coord, b_origin: Coord,
		a_kind: int, b_kind: int, a_kind_id: int, b_kind_id: int) -> Dictionary:
	var roles: Dictionary = {
		"row_origin": null,
		"col_origin": null,
		"area_origin": null,
		"bomb_origin": null,
		"bomb_kind_id": 0,
	}
	# Pair the kinds with the origins.
	var pairs: Array = [[a_kind, a_origin, a_kind_id], [b_kind, b_origin, b_kind_id]]
	for p in pairs:
		var k: int = p[0]
		var o: Coord = p[1]
		var kid: int = p[2]
		match k:
			SpecialKind.STRIPED_ROW:
				roles["row_origin"] = o
			SpecialKind.STRIPED_COL:
				roles["col_origin"] = o
			SpecialKind.AREA:
				roles["area_origin"] = o
			SpecialKind.COLOR_BOMB:
				roles["bomb_origin"] = o
				roles["bomb_kind_id"] = kid
	return roles

## Look up the combinator spec for an (a, b) pair. Returns null when
## the pair is not a supported combo.
static func lookup_combo(board: Board, a_origin: Coord, b_origin: Coord,
		a_kind: int, b_kind: int, a_kind_id: int, b_kind_id: int) -> ComboSpec:
	var table: Dictionary = _build_combo_table(board, a_origin, b_origin,
			a_kind, b_kind, a_kind_id, b_kind_id)
	return table.get(_combo_key(a_kind, b_kind), null)

## Compute the deduped, lex-sorted cleared list for a combo. Returns
## an empty Array when the pair is unsupported.
static func combo_clear(board: Board, a_origin: Coord, b_origin: Coord,
		a_kind: int, b_kind: int, a_kind_id: int, b_kind_id: int) -> Array:
	var spec: ComboSpec = lookup_combo(board, a_origin, b_origin,
			a_kind, b_kind, a_kind_id, b_kind_id)
	if spec == null:
		return []
	var raw: Array = spec.cleared_fn.call()
	# Dedup by key, then keep lex-sorted order; the helper closures
	# may already union, but a final pass guarantees the contract.
	var seen: Dictionary = {}
	var out: Array = []
	for c in raw:
		var cc: Coord = c
		var key: String = "%d,%d" % [cc.x, cc.y]
		if seen.has(key):
			continue
		seen[key] = true
		out.append(cc)
	# Filter blocked cells (preserves the existing single-special
	# activation contract).
	var filtered: Array = []
	for c in out:
		var cc2: Coord = c
		var bc = board.cell_at(cc2)
		if bc != null and not bc.is_blocked():
			filtered.append(cc2)
	filtered.sort_custom(func(a, b):
		var ca: Coord = a
		var cb: Coord = b
		return Coord.compare(ca, cb))
	return filtered

## Activate a special+special combo. Returns a Dictionary with the
## same shape as `activate`:
##   {
##     "kind": int (SpecialKind combo result kind),
##     "center": Coord (the swap target epicentre; convention: a_origin),
##     "color": int (bomb kind_id for COLOR_BOMB combos; 0 otherwise),
##     "cleared": Array[Coord] (deduped, lex-sorted combo cleared cells),
##     "swap_origin": Coord (the swap target cell set by the player),
##   }
##
## The returned `cleared` list is the union of the combo's region
## (deduped, lex-sorted). Blocked cells are excluded. The cleared
## set is direction-invariant: swapping (a, b) yields the same set
## as (b, a), because the dispatcher resolves each role by kind.
static func activate_combo(board: Board, a_origin: Coord, b_origin: Coord,
		a_kind: int, b_kind: int, a_kind_id: int, b_kind_id: int) -> Dictionary:
	var cleared: Array = combo_clear(board, a_origin, b_origin,
			a_kind, b_kind, a_kind_id, b_kind_id)
	var spec: ComboSpec = lookup_combo(board, a_origin, b_origin,
			a_kind, b_kind, a_kind_id, b_kind_id)
	var result_kind: int = a_kind if spec == null else spec.result_kind
	var color: int = 0
	if result_kind == SpecialKind.COLOR_BOMB:
		# Bomb's kind_id is whichever cell is the bomb.
		var roles: Dictionary = _resolve_roles(board, a_origin, b_origin,
				a_kind, b_kind, a_kind_id, b_kind_id)
		color = int(roles.get("bomb_kind_id", 0))
	return {
		"kind": result_kind,
		"center": a_origin,
		"color": color,
		"cleared": cleared,
		"swap_origin": a_origin,
	}
