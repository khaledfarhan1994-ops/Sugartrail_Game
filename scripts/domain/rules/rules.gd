class_name SugartrailRules
extends RefCounted
## Match-3 rules: orthogonal adjacency, bounds, run detection,
## legal-move enumeration, swap application, and rejected-swap restore.
##
## Step 06 implements the read-mostly half of the rules engine. The
## mutating half (resolution, gravity, refill, cascades) lives in
## `resolution.gd` and ships with Step 07.

const Board = preload("res://scripts/domain/board/board.gd")
const Coord = Board.CellCoord
const CellKind = Board.CellKind
const Cell = Board.Cell
const Piece = Board.Piece

# ----------------------------------------------------------------------------
# Adjacency and bounds
# ----------------------------------------------------------------------------

static var ORTHOGONAL_DIRS: Array = [
	Coord.new( 0, -1),  # up
	Coord.new( 1,  0),  # right
	Coord.new( 0,  1),  # down
	Coord.new(-1,  0),  # left
]

static func in_bounds(board: Board, c: Coord) -> bool:
	return board.in_bounds(c.x, c.y)

static func is_orthogonal_neighbor(a: Coord, b: Coord) -> bool:
	var dx: int = abs(a.x - b.x)
	var dy: int = abs(a.y - b.y)
	return (dx == 1 and dy == 0) or (dx == 0 and dy == 1)

static func orthogonal_neighbor_coords(board: Board, c: Coord) -> Array:
	var out: Array = []
	for d in ORTHOGONAL_DIRS:
		var n: Coord = Coord.new(c.x + d.x, c.y + d.y)
		if in_bounds(board, n):
			out.append(n)
	return out

# ----------------------------------------------------------------------------
# Match detection
# ----------------------------------------------------------------------------

## Detect every horizontal and vertical run of >= 3 pieces on the
## board. Returns an Array of Arrays of CellCoord (the cells in each
## run). A cell may appear in both a horizontal and a vertical run
## when runs intersect (the '+' case).
static func find_runs(board: Board) -> Array:
	var runs: Array = []
	for cell in board._cells:
		var c: Coord = cell.coord
		if not cell.is_piece():
			continue
		# Horizontal run starting at this cell only if the cell to
		# the LEFT is not the same kind (so we don't double-count).
		var left_cell: Cell = board.cell_at(Coord.new(c.x - 1, c.y))
		var start_of_h: bool = left_cell == null or not left_cell.is_piece() or left_cell.piece.kind_id != cell.piece.kind_id
		if start_of_h:
			var h_run: Array = _extend_h_run(board, c)
			if h_run.size() >= 3:
				runs.append(h_run)
		# Vertical run starting at this cell only if the cell ABOVE
		# is not the same kind.
		var up_cell: Cell = board.cell_at(Coord.new(c.x, c.y - 1))
		var start_of_v: bool = up_cell == null or not up_cell.is_piece() or up_cell.piece.kind_id != cell.piece.kind_id
		if start_of_v:
			var v_run: Array = _extend_v_run(board, c)
			if v_run.size() >= 3:
				runs.append(v_run)
	return runs

static func _extend_h_run(board: Board, c: Coord) -> Array:
	var run: Array = []
	var kind: int = board.cell_at(c).piece.kind_id
	var x: int = c.x
	while x < board.config.width:
		var cur: Cell = board.cell_at(Coord.new(x, c.y))
		if cur == null or not cur.is_piece() or cur.piece.kind_id != kind:
			break
		run.append(Coord.new(x, c.y))
		x += 1
	return run

static func _extend_v_run(board: Board, c: Coord) -> Array:
	var run: Array = []
	var kind: int = board.cell_at(c).piece.kind_id
	var y: int = c.y
	while y < board.config.height:
		var cur: Cell = board.cell_at(Coord.new(c.x, y))
		if cur == null or not cur.is_piece() or cur.piece.kind_id != kind:
			break
		run.append(Coord.new(c.x, y))
		y += 1
	return run

# ----------------------------------------------------------------------------
# Legal swap
# ----------------------------------------------------------------------------

## Try to swap two adjacent piece cells. If the swap creates a run,
## commit it; otherwise restore the originals and return false.
## The board is mutated in-place only on success.
static func try_swap(board: Board, a: Coord, b: Coord) -> bool:
	if not in_bounds(board, a) or not in_bounds(board, b):
		return false
	if not is_orthogonal_neighbor(a, b):
		return false
	var cell_a: Cell = board.cell_at(a)
	var cell_b: Cell = board.cell_at(b)
	if cell_a == null or cell_b == null:
		return false
	if not cell_a.is_piece() or not cell_b.is_piece():
		return false
	# Snapshot originals (small; two Piece values).
	var piece_a: Piece = cell_a.piece
	var piece_b: Piece = cell_b.piece
	# Tentatively swap.
	cell_a.piece = piece_b
	cell_b.piece = piece_a
	# Check both cells for runs (a match could include other cells too,
	# but a 3-cell swap match only needs to exist at a or b; the global
	# find_runs call would catch additional matches which is fine for
	# the deterministic swap check — we still accept the swap).
	if find_runs(board).size() > 0:
		return true
	# Restore.
	cell_a.piece = piece_a
	cell_b.piece = piece_b
	return false

# ----------------------------------------------------------------------------
# Legal-move enumeration
# ----------------------------------------------------------------------------

## Enumerate every legal swap (a, b) in stable order. A legal swap
## is an orthogonal adjacent pair of piece cells whose swap creates
## at least one match.
static func enumerate_legal_swaps(board: Board) -> Array:
	var moves: Array = []
	var seen := {}
	for cell in board._cells:
		if not cell.is_piece():
			continue
		var a: Coord = cell.coord
		for n in orthogonal_neighbor_coords(board, a):
			var cell_n: Cell = board.cell_at(n)
			if cell_n == null or not cell_n.is_piece():
				continue
			# Canonicalize to (low-x, low-y) first so we don't emit
			# both (a, b) and (b, a).
			var key: String
			if a.x < n.x or (a.x == n.x and a.y < n.y):
				key = "%d,%d|%d,%d" % [a.x, a.y, n.x, n.y]
			else:
				key = "%d,%d|%d,%d" % [n.x, n.y, a.x, a.y]
			if seen.has(key):
				continue
			seen[key] = true
			if try_swap(board, a, n):
				moves.append([a, n])
				# Undo: try_swap only commits when there is a run,
				# so the swap is currently committed. Restore.
				var cell_a_now: Cell = board.cell_at(a)
				var cell_n_now: Cell = board.cell_at(n)
				var pa: Piece = cell_a_now.piece
				var pn: Piece = cell_n_now.piece
				cell_a_now.piece = pn
				cell_n_now.piece = pa
	return moves