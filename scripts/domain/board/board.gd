class_name SugartrailBoard
extends RefCounted
## Typed coordinates, cells, pieces, and immutable board state.
##
## SugartrailBoard is the authoritative gameplay board. It has zero
## dependencies on Godot scene nodes, rendering, audio, input, or the
## filesystem. Everything that mutates the board goes through this
## module and emits domain events for presentation.
##
## Step 05 adds the data model and validation. Step 06 adds match
## detection and legal-move enumeration. Step 07 adds resolution,
## gravity, refill, and cascades.

# ----------------------------------------------------------------------------
# Typed coordinate
# ----------------------------------------------------------------------------

## Axis-aligned integer coordinate. Origin (0,0) is the top-left cell.
class CellCoord:
	## -1 sentinel used by find empty cells. Never a valid board coord.
	const EMPTY: CellCoord = null

	var x: int = 0
	var y: int = 0

	func _init(px: int = 0, py: int = 0) -> void:
		x = px
		y = py

	func is_equal_to(other: CellCoord) -> bool:
		return other != null and x == other.x and y == other.y

	## Lexicographic ordering: top-to-bottom, then left-to-right.
	## Used everywhere the engine needs a stable iteration order so
	## that snapshots and event streams are byte-for-byte reproducible.
	static func compare(a: CellCoord, b: CellCoord) -> bool:
		if a.y != b.y:
			return a.y < b.y
		return a.x < b.x

	func _to_debug_string() -> String:
		return "(%d,%d)" % [x, y]

	func to_dict() -> Dictionary:
		return {"x": x, "y": y}

	static func from_dict(d: Dictionary) -> CellCoord:
		return CellCoord.new(int(d.get("x", 0)), int(d.get("y", 0)))

# ----------------------------------------------------------------------------
# Cell and piece types
# ----------------------------------------------------------------------------

const MAX_PIECE_TYPES: int = 64

## A single grid cell. Stores either a piece, an empty hole, or a
## blocked cell (ice, locked, etc.). Blocker support lands in Step 15.
enum CellKind {
	PIECE = 0,
	EMPTY = 1,
	BLOCKED = 2,
}

## Piece kind ID. Pieces 0..MAX_PIECE_TYPES-1 are normal pieces.
## Special pieces arrive in Step 13 (id range reserved there).
class Piece:
	var kind_id: int = 0

	func _init(p_kind_id: int = 0) -> void:
		kind_id = p_kind_id

	func is_equal_to(other: Piece) -> bool:
		return other != null and kind_id == other.kind_id

# ----------------------------------------------------------------------------
# Cell
# ----------------------------------------------------------------------------

class Cell:
	var coord: CellCoord
	var kind: int = CellKind.EMPTY
	var piece: Piece = null

	func _init(c: CellCoord = null, p_kind: int = CellKind.EMPTY, p_piece: Piece = null) -> void:
		coord = c if c != null else CellCoord.new(0, 0)
		kind = p_kind
		piece = p_piece

	func is_piece() -> bool:
		return kind == CellKind.PIECE and piece != null

	func is_empty() -> bool:
		return kind == CellKind.EMPTY and piece == null

	func is_blocked() -> bool:
		return kind == CellKind.BLOCKED

	func _to_debug_string() -> String:
		if is_piece():
			return "%s=piece(%d)" % [coord._to_debug_string(), piece.kind_id]
		elif is_blocked():
			return "%s=blocked" % coord._to_debug_string()
		return "%s=empty" % coord._to_debug_string()

# ----------------------------------------------------------------------------
# Board configuration and state
# ----------------------------------------------------------------------------

## Static configuration of a board: dimensions, normal-piece palette
## size, and immutable structural blocks. Stored once at level load.
class BoardConfig:
	var width: int = 0
	var height: int = 0
	var normal_palette_size: int = 6
	var blocked: Array = []  # Array[CellCoord], validated at construction

	func _init(p_width: int = 0, p_height: int = 0, p_palette: int = 6, p_blocked: Array = []) -> void:
		width = p_width
		height = p_height
		normal_palette_size = p_palette
		blocked = p_blocked
		_validate()

	func _validate() -> void:
		if width <= 0 or height <= 0:
			push_error("BoardConfig: width and height must be positive (got %dx%d)" % [width, height])
		if normal_palette_size <= 0 or normal_palette_size > MAX_PIECE_TYPES:
			push_error("BoardConfig: normal_palette_size %d out of range 1..%d" % [normal_palette_size, MAX_PIECE_TYPES])
		var seen := {}
		for c in blocked:
			if not (c is CellCoord):
				push_error("BoardConfig: blocked cell is not a CellCoord: %s" % str(c))
				continue
			if c.x < 0 or c.x >= width or c.y < 0 or c.y >= height:
				push_error("BoardConfig: blocked cell %s out of bounds %dx%d" % [c._to_debug_string(), width, height])
				continue
			var key: String = "%d,%d" % [c.x, c.y]
			if seen.has(key):
				push_error("BoardConfig: duplicate blocked cell %s" % c._to_debug_string())
				continue
			seen[key] = true

# ----------------------------------------------------------------------------
# SugartrailBoard — flat cell array, deterministic indexing
# ----------------------------------------------------------------------------

var config: BoardConfig
var _cells: Array = []  # Array[Cell], indexed by y * width + x in stable order

func _init(p_config: BoardConfig = null) -> void:
	if p_config == null:
		p_config = BoardConfig.new(8, 10, 6, [])
	config = p_config
	_init_cells()

func _init_cells() -> void:
	_cells.clear()
	# Build cells in stable iteration order: y outer, x inner.
	for y in range(config.height):
		for x in range(config.width):
			var coord := CellCoord.new(x, y)
			_cells.append(Cell.new(coord, _classify(coord), null))

func _classify(c: CellCoord) -> int:
	for b in config.blocked:
		if b.is_equal_to(c):
			return CellKind.BLOCKED
	return CellKind.EMPTY

# ----------------------------------------------------------------------------
# Cell accessors (read)
# ----------------------------------------------------------------------------

func _index(x: int, y: int) -> int:
	return y * config.width + x

func in_bounds(x: int, y: int) -> bool:
	return x >= 0 and y >= 0 and x < config.width and y < config.height

func cell_at(c: CellCoord) -> Cell:
	if not in_bounds(c.x, c.y):
		return null
	return _cells[_index(c.x, c.y)]

func set_piece(c: CellCoord, piece: Piece) -> void:
	assert(in_bounds(c.x, c.y), "set_piece out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	assert(cell.kind != CellKind.BLOCKED, "set_piece into a BLOCKED cell: %s" % c._to_debug_string())
	assert(piece != null, "set_piece requires non-null Piece")
	cell.kind = CellKind.PIECE
	cell.piece = piece

func set_empty(c: CellCoord) -> void:
	assert(in_bounds(c.x, c.y), "set_empty out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	assert(cell.kind != CellKind.BLOCKED, "set_empty into a BLOCKED cell: %s" % c._to_debug_string())
	cell.kind = CellKind.EMPTY
	cell.piece = null

# ----------------------------------------------------------------------------
# Iteration helpers (read-only)
# ----------------------------------------------------------------------------

func all_coords() -> Array:
	var out: Array = []
	out.resize(config.width * config.height)
	for i in range(out.size()):
		out[i] = _cells[i].coord
	return out

func all_piece_coords() -> Array:
	var out: Array = []
	for cell in _cells:
		if cell.is_piece():
			out.append(cell.coord)
	return out

func empty_coords() -> Array:
	var out: Array = []
	for cell in _cells:
		if cell.is_empty():
			out.append(cell.coord)
	return out

# ----------------------------------------------------------------------------
# Validation and snapshot
# ----------------------------------------------------------------------------

func validate() -> bool:
	for cell in _cells:
		if cell.is_piece():
			if cell.piece == null:
				push_error("validate: PIECE cell %s has null Piece" % cell.coord._to_debug_string())
				return false
			if cell.piece.kind_id < 0 or cell.piece.kind_id >= config.normal_palette_size:
				push_error("validate: PIECE cell %s has invalid kind_id %d" % [cell.coord._to_debug_string(), cell.piece.kind_id])
				return false
		elif cell.kind == CellKind.EMPTY:
			if cell.piece != null:
				push_error("validate: EMPTY cell %s has non-null Piece" % cell.coord._to_debug_string())
				return false
	return true

## Snapshot is a deep, deterministic Dictionary representation of the
## board. Two boards with the same config and cell contents produce
## identical snapshots (modulo iteration order, which is stable).
func to_snapshot() -> Dictionary:
	var cells_array: Array = []
	for cell in _cells:
		var entry: Dictionary = {"x": cell.coord.x, "y": cell.coord.y, "kind": cell.kind}
		if cell.piece != null:
			entry["piece_kind_id"] = cell.piece.kind_id
		cells_array.append(entry)
	return {
		"width": config.width,
		"height": config.height,
		"normal_palette_size": config.normal_palette_size,
		"cells": cells_array,
	}

## Stable hash of the snapshot. Used by replay comparators.
func snapshot_hash() -> int:
	# Cheap deterministic fold; collisions are acceptable for replay
	# comparisons because the snapshot itself is the truth.
	var h: int = 17
	h = (h * 31 + config.width) & 0xFFFFFFFF
	h = (h * 31 + config.height) & 0xFFFFFFFF
	h = (h * 31 + config.normal_palette_size) & 0xFFFFFFFF
	for cell in _cells:
		h = (h * 31 + cell.kind) & 0xFFFFFFFF
		if cell.piece != null:
			h = (h * 31 + cell.piece.kind_id) & 0xFFFFFFFF
	return h