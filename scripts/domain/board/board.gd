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

## A single grid cell. Stores either a piece, an empty hole, a
## blocked cell (structural, never holds a piece — set at level
## load), or a frosted cell (sticky floor that survives across
## cascades and decrements when its underlying piece is cleared).
##
## Step 15 adds the FROSTING cell kind and the per-cell `locked`
## flag for the launch blockers (one-hit / layered frosting,
## locked cells). Frosting persists across cascades; refill
## skips FROSTING cells; gravity treats FROSTING as a floor.
enum CellKind {
	PIECE = 0,
	EMPTY = 1,
	BLOCKED = 2,
	FROSTING = 3,
}

## Special kinds. NONE is the default for normal pieces; the other
## values describe special-piece behaviour (see docs/02-game-design.md
## §3 and the Step 13 design plan).
##
## Step 13 implements creation + activation. Step 14 adds
## special+special combos.
enum SpecialKind {
	NONE = 0,         # normal piece
	STRIPED_ROW = 1,  # 4-in-a-row horizontal; clears its row when activated
	STRIPED_COL = 2,  # 4-in-a-row vertical; clears its column when activated
	COLOR_BOMB = 3,   # 5-in-a-line; clears all pieces of its kind_id when activated
	AREA = 4,         # T or L shape; clears a 3x3 box (clipped) when activated
}

## Piece kind ID. Pieces 0..MAX_PIECE_TYPES-1 are normal pieces.
## Special pieces arrive in Step 13 (id range reserved there).
class Piece:
	var kind_id: int = 0

	func _init(p_kind_id: int = 0) -> void:
		kind_id = p_kind_id

	func is_equal_to(other: Piece) -> bool:
		return other != null and kind_id == other.kind_id

## Special metadata that rides along with a piece. A normal Piece has
## no Special; a SpecialPiece carries both a normal kind_id and a
## Special payload.
class Special:
	var kind: int = SpecialKind.NONE
	## Axis hint for striped specials. 0 = horizontal (unused for
	## non-striped specials), 1 = vertical (unused for non-striped).
	var orientation: int = 0
	## When false (the Step 13 default for newly created specials),
	## the special detonates the cycle it is created. Reserved for
	## Step 14 where some specials require a separate swap/match to
	## activate.
	var needs_activation: bool = false

	func _init(p_kind: int = SpecialKind.NONE, p_orientation: int = 0, p_needs_activation: bool = false) -> void:
		kind = p_kind
		orientation = p_orientation
		needs_activation = p_needs_activation

	func is_special() -> bool:
		return kind != SpecialKind.NONE

	func is_normal() -> bool:
		return kind == SpecialKind.NONE

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"orientation": orientation,
			"needs_activation": needs_activation,
		}

	static func from_dict(d: Dictionary) -> Special:
		return Special.new(
			int(d.get("kind", SpecialKind.NONE)),
			int(d.get("orientation", 0)),
			bool(d.get("needs_activation", false)))

## A piece that carries special metadata. SpecialPiece is the value
## stored in Cell.piece for cells that became specials via Step 13+
## creation rules. Existing reads of `piece.kind_id` continue to work
## because SpecialPiece exposes `kind_id` (the normal palette kind the
## special represents — same field semantics as Piece).
class SpecialPiece:
	var kind_id: int = 0
	var special: Special = Special.new()

	func _init(p_kind_id: int = 0, p_special: Special = null) -> void:
		kind_id = p_kind_id
		special = p_special if p_special != null else Special.new()

	func is_special() -> bool:
		return special != null and special.is_special()

	func is_normal() -> bool:
		return not is_special()

	func to_dict() -> Dictionary:
		return {
			"kind_id": kind_id,
			"special": special.to_dict(),
		}

	static func from_dict(d: Dictionary) -> SpecialPiece:
		var spec_d: Dictionary = d.get("special", {})
		var spec: Special = Special.from_dict(spec_d)
		return SpecialPiece.new(int(d.get("kind_id", 0)), spec)

# ----------------------------------------------------------------------------
# Cell
# ----------------------------------------------------------------------------

class Cell:
	var coord: CellCoord
	var kind: int = CellKind.EMPTY
	## The cell's piece, if any. Either a normal Piece or a
	## SpecialPiece (Step 13+). The field is intentionally Variant
	## so a single cell can hold either; callers should treat
	## `is_piece()` as the primary predicate and check
	## `piece is SpecialPiece` when special semantics matter.
	var piece = null
	## Step 15: how many frosting layers cover this cell. 0 means
	## no frosting. When the underlying piece is cleared, the
	## frosting decrements; on the last layer the cell breaks.
	## Frosting only applies when the cell is in FROSTING kind
	## (kind transitions to FROSTING the cycle the piece is
	## cleared under frosting_layers > 1).
	var frosting_layers: int = 0
	## Step 15: locked cells hold a piece that cannot be removed
	## by matches (the match runs around the locked cell). The
	## lock is released only by a special activation that clears
	## the piece AND lists the cell in the cleared list.
	var locked: bool = false

	func _init(c: CellCoord = null, p_kind: int = CellKind.EMPTY, p_piece = null) -> void:
		coord = c if c != null else CellCoord.new(0, 0)
		kind = p_kind
		piece = p_piece

	func is_piece() -> bool:
		return kind == CellKind.PIECE and piece != null

	func is_empty() -> bool:
		return kind == CellKind.EMPTY and piece == null

	func is_blocked() -> bool:
		return kind == CellKind.BLOCKED

	func is_frosted() -> bool:
		# Step 15: a cell is frosted when it has frosting_layers > 0,
		# regardless of whether the cell currently holds a piece (a
		# frosted piece is still frosted). A frosted PIECE cell is
		# visually frosted; matching the piece damages the frosting.
		return frosting_layers > 0

	func is_locked() -> bool:
		return kind == CellKind.PIECE and locked

	func frosting_remaining() -> int:
		return frosting_layers if is_frosted() else 0

	func _to_debug_string() -> String:
		if is_piece():
			var tag: String = "piece"
			if piece is SpecialPiece:
				var sp: SpecialPiece = piece
				var spec: Special = sp.special
				var names := ["NORMAL", "STRIPED_ROW", "STRIPED_COL", "COLOR_BOMB", "AREA"]
				var nm: String = names[spec.kind] if spec.kind >= 0 and spec.kind < names.size() else "?"
				tag = "special(%s,k%d)" % [nm, sp.kind_id]
			if locked:
				tag = "locked_" + tag
			return "%s=%s(%d)" % [coord._to_debug_string(), tag, piece.kind_id]
		if is_blocked():
			return "%s=blocked" % coord._to_debug_string()
		if is_frosted():
			return "%s=frosting(L%d)" % [coord._to_debug_string(), frosting_layers]
		return "%s=empty" % coord._to_debug_string()

# ----------------------------------------------------------------------------
# Board configuration and state
# ----------------------------------------------------------------------------

## Static configuration of a board: dimensions, normal-piece palette
## size, immutable structural blocks, and initial blocker spec.
## Stored once at level load.
##
## Step 15: `blockers` is an Array[Dictionary] of initial blocker
## placement. Each entry has the shape:
##   {"x": int, "y": int, "type": "FROSTING" | "LOCKED", "layers": int}
## FROSTING entries carry `layers >= 1` (one-hit uses 1, layered
## uses 2-4). LOCKED entries carry `layers >= 1` (informational
## only; locked cells hold a piece and the lock field is set).
## Validated by BoardConfig._validate_blockers().
class BoardConfig:
	var width: int = 0
	var height: int = 0
	var normal_palette_size: int = 6
	var blocked: Array = []  # Array[CellCoord], validated at construction
	var blockers: Array = []  # Array[Dictionary], validated at construction

	func _init(p_width: int = 0, p_height: int = 0, p_palette: int = 6,
			p_blocked: Array = [], p_blockers: Array = []) -> void:
		width = p_width
		height = p_height
		normal_palette_size = p_palette
		blocked = p_blocked
		blockers = p_blockers
		_validate()
		_validate_blockers()

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

	func _validate_blockers() -> void:
		var seen := {}
		for entry in blockers:
			if not (entry is Dictionary):
				push_error("BoardConfig: blocker entry is not a Dictionary: %s" % str(entry))
				continue
			var d: Dictionary = entry
			var x: int = int(d.get("x", -1))
			var y: int = int(d.get("y", -1))
			var type_v: Variant = d.get("type", "")
			var type_str: String = type_v if type_v is String else ""
			var layers: int = int(d.get("layers", 0))
			if x < 0 or x >= width or y < 0 or y >= height:
				push_error("BoardConfig: blocker at (%d,%d) out of bounds %dx%d" % [x, y, width, height])
				continue
			if type_str != "FROSTING" and type_str != "LOCKED":
				push_error("BoardConfig: blocker at (%d,%d) has invalid type '%s'" % [x, y, type_str])
				continue
			if layers < 1:
				push_error("BoardConfig: blocker at (%d,%d) has layers %d (< 1)" % [x, y, layers])
				continue
			var key: String = "%d,%d" % [x, y]
			if seen.has(key):
				push_error("BoardConfig: duplicate blocker at (%d,%d)" % [x, y])
				continue
			for b in blocked:
				var bc: CellCoord = b
				if bc.x == x and bc.y == y:
					push_error("BoardConfig: blocker at (%d,%d) overlaps a BLOCKED cell" % [x, y])
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
	_apply_frosting()

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
	# Step 15: cells with a FROSTING blocker entry start as FROSTING.
	for entry in config.blockers:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		if d.get("type", "") != "FROSTING":
			continue
		if int(d.get("x", -1)) == c.x and int(d.get("y", -1)) == c.y:
			return CellKind.FROSTING
	return CellKind.EMPTY

## Step 15: set frosting_layers on the cells that started FROSTING.
## Runs once at construction. The cells remain FROSTING with no
## piece until refill fills them via a clear-then-spawn cascade (or
## the player matches a piece on top, which decrements).
func _apply_frosting() -> void:
	for entry in config.blockers:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		if d.get("type", "") != "FROSTING":
			continue
		var x: int = int(d.get("x", -1))
		var y: int = int(d.get("y", -1))
		if not in_bounds(x, y):
			continue
		var cell: Cell = _cells[_index(x, y)]
		if cell.kind != CellKind.FROSTING:
			continue
		cell.frosting_layers = int(d.get("layers", 1))

## Step 15: lock all pieces marked as LOCKED in the blocker spec.
## Called by the level loader AFTER refill. Returns errors.
func apply_locks_to_pieces() -> Array:
	var errors: Array = []
	for entry in config.blockers:
		if not (entry is Dictionary):
			continue
		var d: Dictionary = entry
		if d.get("type", "") != "LOCKED":
			continue
		var x: int = int(d.get("x", -1))
		var y: int = int(d.get("y", -1))
		if not in_bounds(x, y):
			errors.append("apply_locks_to_pieces: cell (%d,%d) out of bounds" % [x, y])
			continue
		var cell: Cell = cell_at(CellCoord.new(x, y))
		if cell == null:
			errors.append("apply_locks_to_pieces: cell (%d,%d) is null" % [x, y])
			continue
		if not cell.is_piece():
			errors.append("apply_locks_to_pieces: LOCKED cell (%d,%d) has no piece to lock" % [x, y])
			continue
		cell.locked = true
	return errors

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

func set_piece(c: CellCoord, piece) -> void:
	# `piece` is intentionally untyped so callers can pass either a
	# normal Piece or a SpecialPiece. Both must expose `kind_id`.
	assert(in_bounds(c.x, c.y), "set_piece out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	assert(cell.kind != CellKind.BLOCKED, "set_piece into a BLOCKED cell: %s" % c._to_debug_string())
	assert(piece != null, "set_piece requires non-null Piece")
	# Step 15: preserve frosting_layers when transitioning a
	# FROSTING cell to PIECE (refill of a frosted empty floor).
	var preserved_frosting: int = cell.frosting_layers if cell.kind == CellKind.FROSTING else 0
	cell.kind = CellKind.PIECE
	cell.piece = piece
	if preserved_frosting > 0:
		cell.frosting_layers = preserved_frosting

func set_empty(c: CellCoord) -> void:
	assert(in_bounds(c.x, c.y), "set_empty out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	assert(cell.kind != CellKind.BLOCKED, "set_empty into a BLOCKED cell: %s" % c._to_debug_string())
	# Step 15: preserve frosting state when emptying a frosted piece.
	# If the cell was PIECE with frosting_layers > 0, transitioning
	# to EMPTY keeps the frosting (cell becomes a frosted empty
	# floor waiting for refill).
	var preserved_frosting: int = cell.frosting_layers
	var preserved_locked: bool = cell.locked
	cell.kind = CellKind.EMPTY
	cell.piece = null
	if preserved_frosting > 0:
		cell.kind = CellKind.FROSTING
		cell.frosting_layers = preserved_frosting
		cell.locked = preserved_locked

## Step 15: transition a PIECE cell to FROSTING after the piece is
## cleared and at least one frosting layer remains. Decrements
## frosting_layers by 1.
func damage_to_frosting(c: CellCoord, layers_after: int) -> void:
	assert(in_bounds(c.x, c.y), "damage_to_frosting out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	cell.piece = null
	cell.locked = false
	cell.kind = CellKind.FROSTING
	cell.frosting_layers = layers_after

## Step 15: clear a FROSTING cell entirely (last layer broken).
func break_frosting(c: CellCoord) -> void:
	assert(in_bounds(c.x, c.y), "break_frosting out of bounds: %s" % c._to_debug_string())
	var cell: Cell = _cells[_index(c.x, c.y)]
	cell.kind = CellKind.EMPTY
	cell.piece = null
	cell.frosting_layers = 0
	cell.locked = false

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
##
## Cells holding a SpecialPiece gain a "special" key (SpecialKind +
## orientation) so a snapshot roundtrips the special metadata.
## Step 15: FROSTING cells roundtrip `frosting_layers`; PIECE cells
## roundtrip `locked` so the lock survives snapshot replay.
func to_snapshot() -> Dictionary:
	var cells_array: Array = []
	for cell in _cells:
		var entry: Dictionary = {"x": cell.coord.x, "y": cell.coord.y, "kind": cell.kind}
		if cell.piece != null:
			entry["piece_kind_id"] = cell.piece.kind_id
			if cell.piece is SpecialPiece:
				var sp: SpecialPiece = cell.piece
				entry["special"] = sp.special.to_dict()
			if cell.locked:
				entry["locked"] = true
		if cell.kind == CellKind.FROSTING and cell.frosting_layers > 0:
			entry["frosting_layers"] = cell.frosting_layers
		cells_array.append(entry)
	return {
		"width": config.width,
		"height": config.height,
		"normal_palette_size": config.normal_palette_size,
		"cells": cells_array,
	}

## Stable hash of the snapshot. Used by replay comparators.
## The hash folds in the special kind + orientation so two boards
## that differ only by which cells hold specials replay distinctly.
## Step 15: also folds in frosting_layers and locked so blockers
## roundtrip deterministically.
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
			if cell.piece is SpecialPiece:
				var sp: SpecialPiece = cell.piece
				h = (h * 31 + sp.special.kind) & 0xFFFFFFFF
				h = (h * 31 + sp.special.orientation) & 0xFFFFFFFF
				if sp.special.needs_activation:
					h = (h * 31 + 1) & 0xFFFFFFFF
			if cell.locked:
				h = (h * 31 + 1) & 0xFFFFFFFF
		if cell.kind == CellKind.FROSTING and cell.frosting_layers > 0:
			h = (h * 31 + cell.frosting_layers) & 0xFFFFFFFF
	return h