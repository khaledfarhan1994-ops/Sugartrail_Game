class_name SugartrailResolution
extends RefCounted
## Match-3 resolution pipeline: find, remove, gravity, refill, cascade.
##
## Step 07 implements the mutating half of the rules engine. The
## read-mostly half (orthogonal adjacency, bounds, find_runs, legal
## swaps) lives in `rules.gd` and ships with Step 06.
##
## The pipeline is fully deterministic: same board + same RNG seed +
## same starting swap always produces the same final board and the
## same event log. Any error or infinite loop is reported loudly
## rather than silently swallowed.

## Event kinds. New presentation/UI code subscribes to these to
## animate removals, drops, and spawns.
enum EventKind {
	REMOVE = 0,
	MOVE = 1,
	SPAWN = 2,
	CASCADE_START = 3,
	CASCADE_END = 4,
}

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const CellKind = Board.CellKind
const Cell = Board.Cell
const Piece = Board.Piece

## Maximum number of cascade cycles allowed before resolution fails.
## 100 is generous: a real level resolves in < 20 cycles. Anything
## higher than this is a bug we want to know about, not a level we
## want to ship.
const MAX_CASCADE_CYCLES: int = 100

## Maximum number of "remove" events per cycle. A cycle that tries
## to remove more than this many cells is almost certainly a bug.
## Normal match-3 puzzles clear at most a few dozen cells per cycle.
const MAX_REMOVES_PER_CYCLE: int = 4096

# ----------------------------------------------------------------------------
# High-level pipeline
# ----------------------------------------------------------------------------

## Resolve all matches on the board, applying gravity, refill, and
## cascading until the board is stable (no matches). Returns a
## CascadeResult describing every event that occurred.
##
## The RNG is required for refill. Pass the same RNG instance to
## every resolution call to keep gameplay deterministic.
static func resolve(board: Board, rng: Rng) -> CascadeResult:
	var result: CascadeResult = CascadeResult.new()
	var cycle: int = 0
	while true:
		cycle += 1
		if cycle > MAX_CASCADE_CYCLES:
			push_error("resolve: exceeded MAX_CASCADE_CYCLES; possible infinite loop")
			return result
		var runs: Array = Rules.find_runs(board)
		if runs.size() == 0:
			break
		# Record cascade start with the cycle index for this cycle.
		result.events.append(DomainEvent.new(EventKind.CASCADE_START, [], -1, cycle - 1))
		var removed_this_cycle: int = _resolve_cycle(board, runs, result, cycle - 1)
		if removed_this_cycle == 0:
			push_error("resolve: cycle %d found runs but removed 0 pieces" % cycle)
			break
		result.total_removed += removed_this_cycle
		_apply_gravity(board, result, cycle - 1)
		_refill(board, rng, result, cycle - 1)
		result.events.append(DomainEvent.new(EventKind.CASCADE_END, [], -1, cycle - 1))
	result.cycles = cycle - 1
	return result

# ----------------------------------------------------------------------------
# Cycle: remove matched cells
# ----------------------------------------------------------------------------

## Remove all cells in the given runs. Runs is an Array of Arrays of
## CellCoord. Returns the number of pieces removed this cycle.
static func _resolve_cycle(board: Board, runs: Array,
		result: CascadeResult, cascade_index: int) -> int:
	var removed := {}
	var removed_count: int = 0
	for run in runs:
		for c in run:
			var coord: Coord = c
			var key: String = "%d,%d" % [coord.x, coord.y]
			if removed.has(key):
				continue
			removed[key] = true
			var cell: Cell = board.cell_at(coord)
			if cell == null or not cell.is_piece():
				continue
			removed_count += 1
			if removed_count > MAX_REMOVES_PER_CYCLE:
				push_error("resolve: cycle removed too many cells; possible bug")
				return removed_count
			var piece_kind: int = cell.piece.kind_id
			board.set_empty(coord)
			result.events.append(DomainEvent.new(
				EventKind.REMOVE, [coord], piece_kind, cascade_index))
	return removed_count

# ----------------------------------------------------------------------------
# Gravity
# ----------------------------------------------------------------------------

## Apply gravity: each piece falls straight down through any empty
## cells below it, stopping at the bottom row, a blocked cell, or the
## first piece. Blocked cells act as solid floors.
##
## Algorithm: process columns left-to-right, and within each column
## bottom-to-top. Maintain a "land_y" pointer that starts at the
## bottom row and rises as pieces land. Any empty cell above the
## land_y pointer is a slot that the next piece above will fall into.
static func _apply_gravity(board: Board, result: CascadeResult, cascade_index: int) -> void:
	for x in range(board.config.width):
		var land_y: int = board.config.height - 1
		var y: int = board.config.height - 1
		while y >= 0:
			var cell: Cell = board.cell_at(Coord.new(x, y))
			if cell.is_blocked():
				# Blocked cells are floors: anything above falls TOWARD
				# this cell, not onto it. Reset land_y to one above.
				land_y = y - 1
			elif cell.is_piece():
				if y != land_y:
					var from: Coord = Coord.new(x, y)
					var to: Coord = Coord.new(x, land_y)
					var piece: Piece = cell.piece
					board.set_empty(from)
					board.set_piece(to, piece)
					result.events.append(DomainEvent.new(
						EventKind.MOVE, [from, to], piece.kind_id, cascade_index))
				land_y -= 1
			y -= 1

# ----------------------------------------------------------------------------
# Refill
# ----------------------------------------------------------------------------

## Refill every empty cell from the top of the column downward. Each
## cell gets a new random piece with a kind_id in [0, palette_size).
## Spawn order is column-major (y=0..height-1, x=0..width-1) so the
## event log is byte-for-byte reproducible.
static func _refill(board: Board, rng: Rng, result: CascadeResult, cascade_index: int) -> void:
	var palette: int = board.config.normal_palette_size
	for x in range(board.config.width):
		for y in range(board.config.height):
			var c: Coord = Coord.new(x, y)
			var cell: Cell = board.cell_at(c)
			if cell.is_piece() or cell.is_blocked():
				continue
			if not cell.is_empty():
				continue
			var kind: int = rng.rand_int(palette)
			var piece: Piece = Piece.new(kind)
			board.set_piece(c, piece)
			result.events.append(DomainEvent.new(
				EventKind.SPAWN, [c], kind, cascade_index))

# ----------------------------------------------------------------------------
# Pure helpers (also used by tests and the upcoming generator/solver)
# ----------------------------------------------------------------------------

## Fill the entire board with random pieces drawn from the palette.
## Useful for level generation and test fixtures. Any blocked cells
## are left as blocked. If `avoid_initial_matches` is true, the
## routine retries each cell until no horizontal or vertical run of
## 3+ forms at that cell. A safety cap prevents infinite loops; in
## that case the board may still match and the caller is expected to
## reshuffle.
static func fill_random(board: Board, rng: Rng, avoid_initial_matches: bool = false) -> void:
	var palette: int = board.config.normal_palette_size
	var safety: int = board.config.width * board.config.height * 8
	var attempts: int = 0
	for cell in board._cells:
		if cell.is_blocked():
			continue
		var coord: Coord = cell.coord
		var kind: int = -1
		while true:
			attempts += 1
			if attempts > safety:
				kind = rng.rand_int(palette)
				break
			var candidate: int = rng.rand_int(palette)
			if not avoid_initial_matches:
				kind = candidate
				break
			if not _would_form_run(board, coord, candidate):
				kind = candidate
				break
		if kind >= 0:
			board.set_piece(coord, Piece.new(kind))

## Return true if a piece of kind `kind` placed at `coord` would form
## a same-kind run of 3+ horizontally or vertically. Uses the
## current board state (mutating the cell in place is not necessary).
static func _would_form_run(board: Board, coord: Coord, kind: int) -> bool:
	var left_same: int = 0
	var x: int = coord.x - 1
	while x >= 0:
		var lc: Cell = board.cell_at(Coord.new(x, coord.y))
		if lc == null or not lc.is_piece() or lc.piece.kind_id != kind:
			break
		left_same += 1
		x -= 1
	var right_same: int = 0
	x = coord.x + 1
	while x < board.config.width:
		var rc: Cell = board.cell_at(Coord.new(x, coord.y))
		if rc == null or not rc.is_piece() or rc.piece.kind_id != kind:
			break
		right_same += 1
		x += 1
	if left_same + 1 + right_same >= 3:
		return true
	var up_same: int = 0
	var y: int = coord.y - 1
	while y >= 0:
		var uc: Cell = board.cell_at(Coord.new(coord.x, y))
		if uc == null or not uc.is_piece() or uc.piece.kind_id != kind:
			break
		up_same += 1
		y -= 1
	var down_same: int = 0
	y = coord.y + 1
	while y < board.config.height:
		var dc: Cell = board.cell_at(Coord.new(coord.x, y))
		if dc == null or not dc.is_piece() or dc.piece.kind_id != kind:
			break
		down_same += 1
		y += 1
	if up_same + 1 + down_same >= 3:
		return true
	return false

# ----------------------------------------------------------------------------
# Domain event log (data classes)
# ----------------------------------------------------------------------------

## A single domain event. Stored in order in the event log returned
## by `resolve`. Uses plain types so the log can be serialised to
## JSON for replay, telemetry, or animation timelines.
class DomainEvent:
	var kind: int = 0
	## Coordinates relevant to the event. For REMOVE and SPAWN this
	## is [coord]. For MOVE this is [from, to]. For CASCADE_START and
	## CASCADE_END this is [] and the cycle index lives in `cascade`.
	var coords: Array = []
	## Piece kind_id relevant to the event. -1 when not applicable.
	var piece_kind_id: int = -1
	## Cascade cycle index (0-based). -1 if not part of a cascade.
	var cascade: int = -1

	func _init(p_kind: int, p_coords: Array = [],
			p_piece_kind_id: int = -1, p_cascade: int = -1) -> void:
		kind = p_kind
		coords = p_coords
		piece_kind_id = p_piece_kind_id
		cascade = p_cascade

	func to_dict() -> Dictionary:
		var coords_out: Array = []
		for c in coords:
			var cc: Coord = c
			coords_out.append(cc.to_dict())
		return {
			"kind": kind,
			"coords": coords_out,
			"piece_kind_id": piece_kind_id,
			"cascade": cascade,
		}

	func _to_debug_string() -> String:
		var names := ["REMOVE", "MOVE", "SPAWN", "CASCADE_START", "CASCADE_END"]
		var name: String = names[kind] if kind >= 0 and kind < names.size() else "UNKNOWN"
		var coord_strs: Array = []
		for c in coords:
			var cc: Coord = c
			coord_strs.append(cc._to_debug_string())
		return "[%s cascade=%d] kind=%d coords=%s" % [
			name, cascade, piece_kind_id, str(coord_strs)
		]

## Result of one resolution cycle (find + remove + gravity + refill).
class CascadeResult:
	## Number of cascade cycles executed (1 = no cascades, 2 = one cascade, etc.).
	var cycles: int = 0
	## Total number of pieces removed across all cycles.
	var total_removed: int = 0
	## Event log in order.
	var events: Array = []

	func _init() -> void:
		events = []

	func _to_debug_string() -> String:
		return "CascadeResult(cycles=%d, removed=%d, events=%d)" % [cycles, total_removed, events.size()]
