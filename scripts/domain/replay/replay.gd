class_name SugartrailReplay
extends RefCounted
## Deadlock detection, deterministic reshuffle, and replay engine.
##
## Step 08 builds on the resolution pipeline (Step 07). The three
## pieces are deliberately small so each one is independently testable:
##
##   1. has_legal_moves(board) — fast deadlock check.
##   2. reshuffle(board, rng) — deterministic in-place piece reshuffle
##      that preserves blocked cells, preserves per-kind piece counts,
##      and avoids immediate matches.
##   3. ActionLog + Replay — a serialisable list of player actions plus
##      a deterministic replay engine that re-applies them and produces
##      a stable result hash.

## What kind of player action this log entry represents.
enum ActionKind {
	SWAP = 0,
}

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const CellKind = Board.CellKind
const Piece = Board.Piece

## Maximum number of reshuffle attempts before we give up and raise.
## A real level reshuffles in < 20 attempts on a 6-kind palette. The
## cap exists so the engine fails loudly instead of looping forever on
## pathological configurations (e.g. a 2-wide board with a 6-piece
## palette where 3-runs are unavoidable).
const MAX_RESHUFFLE_ATTEMPTS: int = 1024

## Maximum number of times we will re-attempt reshuffle before giving
## up on an entire board (in case the per-board retry budget runs out).
const MAX_RESHUFFLE_ROUNDS: int = 8

# ----------------------------------------------------------------------------
# Deadlock detection
# ----------------------------------------------------------------------------

## Return true if at least one legal swap exists on the board. A
## legal swap is an orthogonal adjacent pair whose swap would create
## a match. Cheap to call: O(W*H) plus the cost of `enumerate_legal_swaps`,
## which short-circuits on the first match it finds.
static func has_legal_moves(board: Board) -> bool:
	return Rules.enumerate_legal_swaps(board).size() > 0

# ----------------------------------------------------------------------------
# Reshuffle
# ----------------------------------------------------------------------------

## Reshuffle the pieces on the board in place. The blocked-cell layout
## is preserved (a reshuffle must not move or overwrite blocked cells).
## Per-kind piece counts are preserved (the level's objective supply
## must not change). After reshuffle, the board has at least one legal
## move and no immediate matches.
##
## Returns true on success. Returns false (after the safety budget
## has been exhausted) when no legal move can be arranged; callers
## should treat this as a level-design error, not a runtime fault.
static func reshuffle(board: Board, rng: Rng) -> bool:
	# Step 1: collect every piece coord and kind.
	var piece_cells: Array = []
	var kind_counts: Dictionary = {}
	for cell in board._cells:
		if not cell.is_piece():
			continue
		piece_cells.append({"coord": cell.coord, "kind": cell.piece.kind_id})
		var k: int = cell.piece.kind_id
		kind_counts[k] = kind_counts.get(k, 0) + 1
	# Step 2: determine candidate coordinates (non-blocked cells in the
	# stable iteration order). The list must be the same length as
	# `piece_cells` (every piece has exactly one non-blocked cell).
	var candidate_coords: Array = []
	for cell in board._cells:
		if cell.is_blocked():
			continue
		candidate_coords.append(cell.coord)
	if candidate_coords.size() != piece_cells.size():
		push_error("reshuffle: candidate count %d != piece count %d" % [
			candidate_coords.size(), piece_cells.size()
		])
		return false
	# Step 3: shuffle the candidate coordinates deterministically
	# (Fisher-Yates with the seeded RNG). We do NOT change the kinds —
	# only the placement.
	for _round in range(MAX_RESHUFFLE_ROUNDS):
		_attempt_shuffle(board, candidate_coords, rng)
		# Check: does the new layout have at least one legal move AND
		# no immediate matches? If so, we're done.
		if Rules.find_runs(board).size() == 0 and has_legal_moves(board):
			return true
	# Step 4: we failed to find a stable reshuffle. Give up loudly.
	push_error("reshuffle: failed after %d rounds; possible impossible config" % MAX_RESHUFFLE_ROUNDS)
	return false

## Run one Fisher-Yates shuffle of the candidate coords and write the
## pieces onto the board using the original kind multiset.
static func _attempt_shuffle(board: Board, coords: Array, rng: Rng) -> void:
	# Build a shuffled list of coords in place.
	var n: int = coords.size()
	var work: Array = []
	for c in coords:
		work.append(c)
	for i in range(n - 1, 0, -1):
		var j: int = rng.rand_int(i + 1)
		var tmp: Variant = work[i]
		work[i] = work[j]
		work[j] = tmp
	# Collect the kind multiset (preserve count).
	var kinds: Array = []
	for cell in board._cells:
		if cell.is_piece():
			kinds.append(cell.piece.kind_id)
	# The kinds array is in stable iteration order (y outer, x inner).
	# We shuffle that too so the multiset stays intact but the mapping
	# to coords is unpredictable.
	for i in range(kinds.size() - 1, 0, -1):
		var j: int = rng.rand_int(i + 1)
		var tmp: Variant = kinds[i]
		kinds[i] = kinds[j]
		kinds[j] = tmp
	# Clear the board (turn every piece into EMPTY).
	for cell in board._cells:
		if cell.is_piece():
			cell.piece = null
			cell.kind = CellKind.EMPTY
	# Re-place pieces at the shuffled coords with the shuffled kinds.
	for i in range(work.size()):
		var c: Coord = work[i]
		var k: int = kinds[i]
		board.set_piece(c, Piece.new(k))

# ----------------------------------------------------------------------------
# Action log and replay
# ----------------------------------------------------------------------------

## A single player action. Stored in the order it was performed.
class Action:
	var kind: int = 0
	## For SWAP, the two coords being swapped.
	var a: Coord = null
	var b: Coord = null

	func _init(p_kind: int, p_a: Coord, p_b: Coord) -> void:
		kind = p_kind
		a = p_a
		b = p_b

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"a": a.to_dict() if a != null else null,
			"b": b.to_dict() if b != null else null,
		}

	static func from_dict(d: Dictionary) -> Action:
		var a_d: Dictionary = d.get("a", {})
		var b_d: Dictionary = d.get("b", {})
		return Action.new(
			int(d.get("kind", 0)),
			Coord.from_dict(a_d),
			Coord.from_dict(b_d))

## A serialisable record of one play session: the recipe metadata,
## the starting RNG state, the initial board snapshot, every action
## the player took, and the resulting RNG state + event counts.
class ActionLog:
	## Free-form recipe metadata. Conventionally {recipe_id, recipe_version}.
	var recipe: Dictionary = {}
	## Game engine version string used to play the session.
	var engine_version: String = ""
	## The RNG state at the start of the session.
	var initial_rng_state: int = 0
	## The initial board snapshot (SugartrailBoard.to_snapshot()).
	var initial_board: Dictionary = {}
	## Ordered list of Action records.
	var actions: Array = []
	## The RNG state after the last action. Recorded so replays can
	## verify RNG equivalence at the end.
	var final_rng_state: int = 0
	## Total number of domain events produced across all resolutions.
	## Recorded so replays can compare counts (cheaper than comparing
	## full event arrays).
	var total_events: int = 0

	func to_dict() -> Dictionary:
		var actions_out: Array = []
		for act in actions:
			var a: Action = act
			actions_out.append(a.to_dict())
		return {
			"recipe": recipe,
			"engine_version": engine_version,
			"initial_rng_state": initial_rng_state,
			"initial_board": initial_board,
			"actions": actions_out,
			"final_rng_state": final_rng_state,
			"total_events": total_events,
		}

	static func from_dict(d: Dictionary) -> ActionLog:
		var log := ActionLog.new()
		log.recipe = d.get("recipe", {})
		log.engine_version = d.get("engine_version", "")
		log.initial_rng_state = int(d.get("initial_rng_state", 0))
		log.initial_board = d.get("initial_board", {})
		var acts_in: Array = d.get("actions", [])
		for entry in acts_in:
			log.actions.append(Action.from_dict(entry))
		log.final_rng_state = int(d.get("final_rng_state", 0))
		log.total_events = int(d.get("total_events", 0))
		return log

## Result of replaying a log: the final board, the final RNG state,
## and a stable result hash that callers can compare across runs.
class ReplayResult:
	var board: Board = null
	var final_rng_state: int = 0
	var total_events: int = 0
	var result_hash: int = 0
	## If true, every swap in the log was legal at the time it was
	## applied. If false, at least one swap was illegal; the replay
	## stops at the first illegal swap and `last_error_action` holds
	## its index.
	var ok: bool = false
	var last_error_action: int = -1
	var last_error_message: String = ""

## Replay an action log on a fresh RNG and a fresh board restored from
## the log. Returns a ReplayResult describing the final state.
##
## Replay is fully deterministic: same log + same engine version
## always produces the same result hash. Different engine versions
## are explicitly tagged in the log so future replayers can detect
## version drift.
static func replay(log: ActionLog, expected_engine_version: String) -> ReplayResult:
	var result: ReplayResult = ReplayResult.new()
	# Restore the RNG.
	var rng := Rng.from_int(log.initial_rng_state)
	# Restore the board from the snapshot.
	var board: Board = _board_from_snapshot(log.initial_board)
	# Apply each action in order.
	var total_events: int = 0
	var i: int = 0
	for act in log.actions:
		var a: Action = act
		if a.kind == ActionKind.SWAP:
			var ok: bool = Rules.try_swap(board, a.a, a.b)
			if not ok:
				result.ok = false
				result.last_error_action = i
				result.last_error_message = "illegal swap (%s, %s) at action %d" % [
					a.a.to_string(), a.b.to_string(), i]
				return result
			var cascade: Resolution.CascadeResult = Resolution.resolve(board, rng)
			total_events += cascade.events.size()
		i += 1
	# Compare against expected engine version.
	if expected_engine_version != "" and log.engine_version != expected_engine_version:
		result.ok = false
		result.last_error_message = "engine version mismatch: log=%s expected=%s" % [
			log.engine_version, expected_engine_version]
		result.last_error_action = -1
		return result
	# All good — record final state.
	result.board = board
	result.final_rng_state = rng.to_int()
	result.total_events = total_events
	result.result_hash = _compute_result_hash(board, result.final_rng_state, total_events)
	result.ok = true
	return result

## Stable hash of a replay result. Combines the final board's
## snapshot_hash with the RNG state and the total event count so
## equality of the hash implies equality of all three.
static func _compute_result_hash(board: Board, rng_state: int, total_events: int) -> int:
	var h: int = board.snapshot_hash()
	h = (h * 31 + rng_state) & 0xFFFFFFFF
	h = (h * 31 + total_events) & 0xFFFFFFFF
	return h

## Restore a SugartrailBoard from its to_snapshot() representation.
static func _board_from_snapshot(snap: Dictionary) -> Board:
	var w: int = int(snap.get("width", 0))
	var h: int = int(snap.get("height", 0))
	var palette: int = int(snap.get("normal_palette_size", 6))
	var blocked: Array = []
	# The snapshot stores cells, not blocked coords; reconstruct the
	# blocked list from the cells with kind == BLOCKED. We do this in
	# the same stable iteration order so a snapshot roundtrips exactly.
	var cells_in: Array = snap.get("cells", [])
	for entry in cells_in:
		if int(entry.get("kind", -1)) == CellKind.BLOCKED:
			blocked.append(Coord.new(int(entry.get("x", 0)), int(entry.get("y", 0))))
	var board := Board.new(Board.BoardConfig.new(w, h, palette, blocked))
	for entry in cells_in:
		var kind: int = int(entry.get("kind", -1))
		var c := Coord.new(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if kind == CellKind.PIECE:
			var piece_kind: int = int(entry.get("piece_kind_id", 0))
			board.set_piece(c, Piece.new(piece_kind))
		# EMPTY cells stay EMPTY (default), BLOCKED stays BLOCKED.
	return board

## Compare two replay results by result_hash. Returns true if equal.
static func results_equal(a: ReplayResult, b: ReplayResult) -> bool:
	if a.ok != b.ok:
		return false
	if not a.ok:
		# Both failed; compare error index and message.
		return a.last_error_action == b.last_error_action and a.last_error_message == b.last_error_message
	return a.result_hash == b.result_hash and a.total_events == b.total_events
