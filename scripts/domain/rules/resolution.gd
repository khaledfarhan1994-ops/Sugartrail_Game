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
##
## Step 13 adds SPECIAL_CREATE and SPECIAL_ACTIVATE for line-clear,
## area-clear, and color-bomb specials. Per cycle, SPECIAL_CREATE
## events are emitted first, then SPECIAL_ACTIVATE (carrying the
## cleared-cell list), then REMOVE for the actual cells cleared.
##
## Step 15 adds BLOCKER_DAMAGE (a frosting layer was removed at a
## cell that still has layers remaining) and BLOCKER_BREAK (the
## last frosting layer was removed or a locked cell was released).
enum EventKind {
	REMOVE = 0,
	MOVE = 1,
	SPAWN = 2,
	CASCADE_START = 3,
	CASCADE_END = 4,
	SPECIAL_CREATE = 5,
	SPECIAL_ACTIVATE = 6,
	BLOCKER_DAMAGE = 7,
	BLOCKER_BREAK = 8,
	TOKEN_RELEASE = 9,
}

# ----------------------------------------------------------------------------
# Constants
# ----------------------------------------------------------------------------

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Specials = preload("res://scripts/domain/rules/specials.gd")
const Coord = Board.CellCoord
const CellKind = Board.CellKind
const Cell = Board.Cell
const Piece = Board.Piece
const SpecialPiece = Board.SpecialPiece
const Special = Board.Special
const SpecialKind = Board.SpecialKind

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
## Step 13: each cycle also detects special-piece creations
## (4-line striped, 5-line color bomb, T/L area clearer) and
## activates them. Per cycle the event log emits SPECIAL_CREATE
## events, then SPECIAL_ACTIVATE events, then the normal REMOVE /
## MOVE / SPAWN events.
##
## Step 14: when the player action swaps two cells both holding
## SpecialPieces (a combo), and no 3-run is created by the swap, the
## resolution runs the combo's `activate_combo` and then cascades
## naturally (gravity, refill). The cycle emits CASCADE_START /
## SPECIAL_ACTIVATE / REMOVE / MOVE / SPAWN / CASCADE_END events.
## Combo activations count toward `total_removed`.
##
## `swap_a` and `swap_b` (optional, default null) describe the
## player action that triggered this resolution; they participate in
## special-creation precedence (swap cell wins for 4-runs). Pass
## null for cascade cycles after the initial swap.
##
## The RNG is required for refill. Pass the same RNG instance to
## every resolution call to keep gameplay deterministic.
static func resolve(board: Board, rng: Rng, swap_a: Coord = null, swap_b: Coord = null) -> CascadeResult:
	var result: CascadeResult = CascadeResult.new()
	# Step 14: combo fast-path. When the player swapped two cells both
	# holding SpecialPieces (and the swap did NOT create a match), the
	# only effect of the cycle is the combo activation. We perform it
	# before the standard match-cascade loop.
	var combo_emitted: bool = false
	if swap_a != null and swap_b != null:
		var cell_a: Cell = board.cell_at(swap_a)
		var cell_b: Cell = board.cell_at(swap_b)
		var both_specials: bool = cell_a != null and cell_b != null \
				and cell_a.is_piece() and cell_b.is_piece() \
				and cell_a.piece is SpecialPiece and cell_b.piece is SpecialPiece
		var no_match_after_swap: bool = Rules.find_runs(board).size() == 0
		if both_specials and no_match_after_swap:
			_apply_combo(board, result, swap_a, swap_b)
			combo_emitted = true
			# After a combo, run gravity + refill then check for
			# cascades (the cleared cells may have triggered matches).
			result.events.append(DomainEvent.new(EventKind.CASCADE_START, [], -1, 0))
			_apply_gravity(board, result, 0)
			_refill(board, rng, result, 0)
			result.events.append(DomainEvent.new(EventKind.CASCADE_END, [], -1, 0))
	var cycle: int = 0
	while true:
		cycle += 1
		if cycle > MAX_CASCADE_CYCLES:
			push_error("resolve: exceeded MAX_CASCADE_CYCLES; possible infinite loop")
			return result
		var runs: Array = Rules.find_runs(board)
		if runs.size() == 0:
			break
		result.events.append(DomainEvent.new(EventKind.CASCADE_START, [], -1, cycle - 1))
		var removed_this_cycle: int = _resolve_cycle(board, runs, result, cycle - 1, swap_a, swap_b)
		if removed_this_cycle == 0:
			push_error("resolve: cycle %d found runs but removed 0 pieces" % cycle)
			break
		result.total_removed += removed_this_cycle
		_apply_gravity(board, result, cycle - 1)
		_refill(board, rng, result, cycle - 1)
		# Step 16: check trapped tokens after gravity + refill settle.
		# A token is released when a matching piece now sits under
		# it. Released tokens emit a TOKEN_RELEASE event and are
		# removed from Board.tokens. The loop restarts so the same
		# resolve call still cascades if the released pieces also
		# form a match (rare but supported).
		_check_tokens(board, result, cycle - 1)
		result.events.append(DomainEvent.new(EventKind.CASCADE_END, [], -1, cycle - 1))
		# Cascade cycles after the first have no player-action context.
		swap_a = null
		swap_b = null
	# Step 16: also check tokens at the very end (no cascade left),
	# in case a single release-after-settle matters.
	if board.tokens.size() > 0:
		var final_cycle: int = cycle
		result.events.append(DomainEvent.new(EventKind.CASCADE_START, [], -1, final_cycle))
		_check_tokens(board, result, final_cycle)
		result.events.append(DomainEvent.new(EventKind.CASCADE_END, [], -1, final_cycle))
		cycle += 1
	result.cycles = (1 if combo_emitted else 0) + cycle - 1
	return result

# ----------------------------------------------------------------------------
# Cycle: detect specials, activate specials, remove matched cells
# ----------------------------------------------------------------------------

## Run one resolution cycle. Returns the number of pieces removed
## this cycle. The cycle is:
##
##   1. detect_special_creations (4/5/T/L detection).
##   2. existing-special detection: any cell already holding a
##      SpecialPiece that is part of a match activates here too.
##   3. emit SPECIAL_CREATE events (lex-sorted).
##   4. activate every special in the cycle; emit SPECIAL_ACTIVATE
##      events (lex-sorted).
##   5. remove every cell in the union of match cells + activation
##      cleared cells, deduped, lex-sorted. Emit REMOVE events in
##      that order.
static func _resolve_cycle(board: Board, runs: Array,
		result: CascadeResult, cascade_index: int,
		swap_a: Coord, swap_b: Coord) -> int:
	# Build a coord -> kind map for the run cells (used to populate
	# color bombs with their run's kind).
	var kind_for_coord: Dictionary = {}
	for run in runs:
		for c in run:
			var cc: Coord = c
			var cell: Cell = board.cell_at(cc)
			if cell != null and cell.is_piece():
				kind_for_coord["%d,%d" % [cc.x, cc.y]] = cell.piece.kind_id
	# Detect special creations from the runs.
	var plan: Specials.CreationPlan = Specials.detect_special_creations(runs, swap_a, swap_b)
	# Find any existing SpecialPiece cells that are part of a run
	# (those will activate in the same cycle).
	var existing_special_cells: Array = []
	for run in runs:
		for c in run:
			var cc: Coord = c
			var cell: Cell = board.cell_at(cc)
			if cell != null and cell.is_piece() and cell.piece is SpecialPiece:
				# Avoid double-listing if a creation plan also picked
				# this cell (shouldn't happen — Step 13 specials
				# created from a match detonate now and supersede any
				# "previous" special).
				if not plan.has_creation_at(cc):
					existing_special_cells.append(cc)
	# Apply creations to the board BEFORE activating, so a created
	# special can be activated in the same cycle.
	Specials.apply_creations(board, plan, kind_for_coord)
	# Emit SPECIAL_CREATE events.
	for entry in plan.sorted_entries():
		var cc: Coord = entry["coord"]
		var spec: Special = entry["special"]
		var key: String = "%d,%d" % [cc.x, cc.y]
		var kind_id: int = int(kind_for_coord.get(key, 0))
		result.events.append(DomainEvent.new(
			EventKind.SPECIAL_CREATE, [cc], kind_id, cascade_index, spec.kind, cc, []))
	# Activate every special (created + existing) and gather cleared
	# cells.
	var activation_result: Dictionary = Specials.activate_all(
			board, plan, existing_special_cells, kind_for_coord)
	for act in activation_result["activations"]:
		var origin: Coord = act["origin"]
		var ar: Dictionary = act["result"]
		var origin_kind_id: int = int(kind_for_coord.get(
			"%d,%d" % [origin.x, origin.y], 0))
		result.events.append(DomainEvent.new(
			EventKind.SPECIAL_ACTIVATE, [origin], origin_kind_id, cascade_index,
			int(ar.get("kind", SpecialKind.NONE)), origin, ar.get("cleared", [])))
	# Build the removal set: match cells + activation cleared cells.
	var to_remove: Dictionary = {}
	for run in runs:
		for c in run:
			var cc: Coord = c
			to_remove["%d,%d" % [cc.x, cc.y]] = cc
	for c in activation_result["cleared"]:
		var cc: Coord = c
		to_remove["%d,%d" % [cc.x, cc.y]] = cc
	# Track which cells were specifically targeted by a special
	# activation (vs being in a 3-run). Locked cells are only
	# releasable by special activations, not by matches alone.
	var activated_keys: Dictionary = {}
	for c in activation_result["cleared"]:
		var ac: Coord = c
		activated_keys["%d,%d" % [ac.x, ac.y]] = true
	# Lex-sort removed cells; emit REMOVE events; mutate board.
	var removed_keys: Array = []
	for k in to_remove.keys():
		removed_keys.append(k)
	removed_keys.sort_custom(func(a, b):
			var pa: PackedStringArray = a.split(",")
			var pb: PackedStringArray = b.split(",")
			var ax: int = int(pa[0])
			var ay: int = int(pa[1])
			var bx: int = int(pb[0])
			var by: int = int(pb[1])
			if ay != by:
				return ay < by
			return ax < bx)
	var removed_count: int = 0
	for k in removed_keys:
		var cc: Coord = to_remove[k]
		var cell: Cell = board.cell_at(cc)
		if cell == null or not cell.is_piece():
			continue
		# Step 15: locked cells cannot be removed by matches. The
		# match runs around the locked cell; the locked piece stays.
		# A special activation that targets the locked cell bypasses
		# the lock and releases it via a BLOCKER_BREAK event.
		var was_in_match_only: bool = not activated_keys.has(k)
		if cell.locked and was_in_match_only:
			continue
		removed_count += 1
		if removed_count > MAX_REMOVES_PER_CYCLE:
			push_error("resolve: cycle removed too many cells; possible bug")
			return removed_count
		var piece_kind: int = cell.piece.kind_id
		# Step 15: frosting damage/break. If the cell was PIECE with
		# frosting_layers > 0, decrement the layers; if the result
		# is 0, transition to EMPTY (BLOCKER_BREAK); otherwise stay
		# FROSTING with the new layers (BLOCKER_DAMAGE).
		var had_frosting: bool = cell.frosting_layers > 0
		var layers_after: int = cell.frosting_layers - 1 if had_frosting else 0
		var was_locked: bool = cell.locked
		board.set_empty(cc)
		if had_frosting:
			if layers_after <= 0:
				# Last layer: break the frosting entirely. The cell
				# becomes EMPTY (not FROSTING with layers=0) so the
				# refill can spawn a new piece in the cleared slot.
				cell.kind = CellKind.EMPTY
				cell.frosting_layers = 0
				cell.locked = false
				result.events.append(DomainEvent.new(
					EventKind.BLOCKER_BREAK, [cc], piece_kind, cascade_index,
					-1, null, [], 0))
			else:
				cell.frosting_layers = layers_after
				cell.locked = false
				result.events.append(DomainEvent.new(
					EventKind.BLOCKER_DAMAGE, [cc], piece_kind, cascade_index,
					-1, null, [], layers_after))
		elif was_locked:
			# Locked piece cleared by a special. Emit BLOCKER_BREAK
			# and release the lock by clearing the locked flag.
			cell.locked = false
			result.events.append(DomainEvent.new(
				EventKind.BLOCKER_BREAK, [cc], piece_kind, cascade_index))
		result.events.append(DomainEvent.new(
			EventKind.REMOVE, [cc], piece_kind, cascade_index))
	return removed_count
# ----------------------------------------------------------------------------
# Step 14: combo activation
# ----------------------------------------------------------------------------

## Run a special+special combo activation. Emits a SPECIAL_ACTIVATE
## event and REMOVE events for the cleared cells. The two specials
## are consumed (their cells become empty). Blocked cells in the
## cleared list are silently skipped.
##
## Step 14: when the resolution is called from a swap of two cells
## both holding SpecialPieces, the swap has already been applied to
## the board by `Rules.try_swap`. The post-swap board has each
## cell holding the OTHER side's special, but the swap is a logical
## activation — the effect is symmetric, so we read the kinds from
## the cells (post-swap) and pass the swap_a / swap_b coords as
## the combo epicentres.
static func _apply_combo(board: Board, result: CascadeResult,
		swap_a: Coord, swap_b: Coord) -> void:
	var cell_a: Cell = board.cell_at(swap_a)
	var cell_b: Cell = board.cell_at(swap_b)
	if cell_a == null or cell_b == null:
		return
	if not (cell_a.piece is SpecialPiece) or not (cell_b.piece is SpecialPiece):
		return
	var sp_a: SpecialPiece = cell_a.piece
	var sp_b: SpecialPiece = cell_b.piece
	var dict_a: Dictionary = Specials.activate_combo(board, swap_a, swap_b,
			sp_a.special.kind, sp_b.special.kind, sp_a.kind_id, sp_b.kind_id)
	var cleared: Array = dict_a.get("cleared", [])
	# Emit SPECIAL_ACTIVATE event. The origin is the swap-target
	# (swap_a) and the resulting `cleared` list is the full combo
	# cleared set.
	result.events.append(DomainEvent.new(
		EventKind.SPECIAL_ACTIVATE, [swap_a], sp_a.kind_id, -1,
		int(dict_a.get("kind", SpecialKind.NONE)), swap_a, cleared))
	# Emit REMOVE events for the cleared cells (lex-sorted, deduped).
	# The two swap cells are part of the cleared set (the bomb/area
	# origin cells). We mutate the board from a sorted list so the
	# REMOVE event order is deterministic.
	var removed_keys: Array = []
	var seen: Dictionary = {}
	for c in cleared:
		var cc: Coord = c
		var key: String = "%d,%d" % [cc.x, cc.y]
		if seen.has(key):
			continue
		seen[key] = true
		removed_keys.append(key)
	removed_keys.sort_custom(func(a, b):
		var pa: PackedStringArray = a.split(",")
		var pb: PackedStringArray = b.split(",")
		var ax: int = int(pa[0])
		var ay: int = int(pa[1])
		var bx: int = int(pb[0])
		var by: int = int(pb[1])
		if ay != by:
			return ay < by
		return ax < bx)
	for k in removed_keys:
		var cc: Coord = Coord.new(int(k.split(",")[0]), int(k.split(",")[1]))
		var cell: Cell = board.cell_at(cc)
		if cell == null or not cell.is_piece():
			continue
		var piece_kind: int = cell.piece.kind_id
		board.set_empty(cc)
		result.events.append(DomainEvent.new(
			EventKind.REMOVE, [cc], piece_kind, 0))
		result.total_removed += 1

# ----------------------------------------------------------------------------
# Gravity
# ----------------------------------------------------------------------------

## Apply gravity: each piece falls straight down through any empty
## cells below it, stopping at the bottom row, a blocked cell, or the
## first piece. Blocked cells act as solid floors.
##
## Step 15: FROSTING cells are EMPTY for gravity purposes (the
## frosting is purely visual decoration). Pieces can fall into
## FROSTING cells just like EMPTY cells. BLOCKED cells remain the
## only solid floors. The frosting is preserved across cascades
## and decremented when the cell's piece is cleared.
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
##
## Step 15: FROSTING cells (frosted empty floors) are also refilled.
## The frosting decoration persists across the refill (we set the
## piece but keep frosting_layers), so the cell becomes PIECE with
## frosting_layers > 0 — visually frosted and matchable, and the
## next clear of the piece will damage the frosting again.
static func _refill(board: Board, rng: Rng, result: CascadeResult, cascade_index: int) -> void:
	var palette: int = board.config.normal_palette_size
	for x in range(board.config.width):
		for y in range(board.config.height):
			var c: Coord = Coord.new(x, y)
			var cell: Cell = board.cell_at(c)
			if cell.is_piece() or cell.is_blocked():
				continue
			# FROSTING cells are EMPTY for refill purposes — the
			# frosting decoration is preserved by set_piece on
			# FROSTING (it transitions kind to PIECE but keeps
			# frosting_layers).
			if cell.kind != CellKind.EMPTY and cell.kind != CellKind.FROSTING:
				continue
			var kind: int = rng.rand_int(palette)
			var piece: Piece = Piece.new(kind)
			board.set_piece(c, piece)
			# Preserve frosting_layers if the cell was FROSTING.
			if cell.kind == CellKind.PIECE and cell.frosting_layers > 0:
				# already set by set_piece (preserved through the
				# helper; see set_piece_with_frosting below).
				pass
			result.events.append(DomainEvent.new(
				EventKind.SPAWN, [c], kind, cascade_index))

# ----------------------------------------------------------------------------
# Step 16: trapped-token release check
# ----------------------------------------------------------------------------

## Check every token on the board. A token is released when the
## cell under it holds a piece whose kind_id matches the token's
## `matching_kind` (or `matching_kind == -1` meaning "any piece").
## Released tokens emit a TOKEN_RELEASE event and are removed from
## Board.tokens. The `token_id` is encoded in `special_origin.x` so
## the session can route the progress increment without growing
## DomainEvent's payload (special_origin isn't used by TOKEN_RELEASE
## events for any other purpose).
static func _check_tokens(board: Board, result: CascadeResult,
		cascade_index: int) -> void:
	# Iterate over a copy because we mutate `board.tokens`.
	var to_release: Array = []
	for entry in board.tokens:
		var ed: Dictionary = entry
		var tx: int = int(ed.get("x", -1))
		var ty: int = int(ed.get("y", -1))
		if not board.in_bounds(tx, ty):
			continue
		var cc: Coord = Coord.new(tx, ty)
		var cell: Cell = board.cell_at(cc)
		if cell == null or not cell.is_piece():
			continue
		var matching_kind: int = int(ed.get("matching_kind", -1))
		if matching_kind >= 0 and cell.piece.kind_id != matching_kind:
			continue
		to_release.append({"coord": cc, "id": int(ed.get("id", -1))})
	for rel in to_release:
		var rd: Dictionary = rel
		var cc: Coord = rd["coord"]
		var token_id_v: int = int(rd.get("id", -1))
		board.remove_token_at(cc)
		var id_coord: Coord = Coord.new(token_id_v, 0)
		result.events.append(DomainEvent.new(
				EventKind.TOKEN_RELEASE, [cc], -1, cascade_index,
				-1, id_coord, []))

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
##
## Step 13 adds `special_kind` (SpecialKind enum, -1 for non-special
## events), `special_origin` (Coord of the special for SPECIAL_CREATE /
## SPECIAL_ACTIVATE, null otherwise), and `cleared` (Array of Coords,
## only set on SPECIAL_ACTIVATE).
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
	## SpecialKind (SugartrailBoard.SpecialKind). -1 for non-special
	## events. Set on SPECIAL_CREATE and SPECIAL_ACTIVATE.
	var special_kind: int = -1
	## Coord of the special being created or activated. null when
	## the event is not a special event.
	var special_origin: Coord = null
	## Cells cleared by an activation. Empty for non-activate events.
	var cleared: Array = []
	## Step 15: for BLOCKER_DAMAGE this carries the layers remaining
	## after the damage (0 when the last layer was removed but the
	## event is also a BREAK — we emit a separate BREAK event instead).
	## -1 for non-blocker events.
	var layers_after: int = -1

	func _init(p_kind: int, p_coords: Array = [],
			p_piece_kind_id: int = -1, p_cascade: int = -1,
			p_special_kind: int = -1, p_special_origin: Coord = null,
			p_cleared: Array = [], p_layers_after: int = -1) -> void:
		kind = p_kind
		coords = p_coords
		piece_kind_id = p_piece_kind_id
		cascade = p_cascade
		special_kind = p_special_kind
		special_origin = p_special_origin
		cleared = p_cleared
		layers_after = p_layers_after

	func to_dict() -> Dictionary:
		var coords_out: Array = []
		for c in coords:
			var cc: Coord = c
			coords_out.append(cc.to_dict())
		var cleared_out: Array = []
		for c in cleared:
			var cc: Coord = c
			cleared_out.append(cc.to_dict())
		return {
			"kind": kind,
			"coords": coords_out,
			"piece_kind_id": piece_kind_id,
			"cascade": cascade,
			"special_kind": special_kind,
			"special_origin": null if special_origin == null else special_origin.to_dict(),
			"cleared": cleared_out,
			"layers_after": layers_after,
		}

	func _to_debug_string() -> String:
		var names := ["REMOVE", "MOVE", "SPAWN", "CASCADE_START", "CASCADE_END",
				"SPECIAL_CREATE", "SPECIAL_ACTIVATE"]
		var name: String = names[kind] if kind >= 0 and kind < names.size() else "UNKNOWN"
		var coord_strs: Array = []
		for c in coords:
			var cc: Coord = c
			coord_strs.append(cc._to_debug_string())
		var extra: String = ""
		if special_kind >= 0:
			extra = " special=%d origin=%s cleared=%d" % [
				special_kind,
				"(null)" if special_origin == null else special_origin._to_debug_string(),
				cleared.size()
			]
		return "[%s cascade=%d] kind=%d coords=%s%s" % [
			name, cascade, piece_kind_id, str(coord_strs), extra
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
