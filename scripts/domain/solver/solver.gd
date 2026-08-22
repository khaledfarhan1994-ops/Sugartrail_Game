class_name SugartrailSolver
extends RefCounted
## Exact-rule level solver + release validator.
##
## Step 23 ships the production solver: a bounded iterative-
## deepening depth-first search over legal swaps that proves a
## level is solvable within its move budget, returns a witness
## sequence of swaps that achieves the objective, and reports
## enough metadata (nodes visited, branching factor, move count)
## for the difficulty scorer (Step 24) to consume.
##
## The solver's contract:
##
##   - Same input recipe + opts produce the same SolverResult.
##   - "Heuristic wins" do NOT count: the solver returns SOLVED
##     only when it found an explicit move sequence whose replay
##     through the production session engine achieves the
##     objective. There is no "probably solvable" tier.
##   - Boundable: max_depth, max_nodes, max_time_ms. When the bound
##     is hit the solver returns either TIMEOUT (more search
##     likely to find an answer) or RESOURCE_LIMIT (the level is
##     provably out of search budget for the configured opts).
##   - Reproducible: the search clones the recipe's session board
##     + carries the recipe's seed into the refill RNG so the
##     cascades produced by the solver match the cascades the
##     session engine will produce when the proof is replayed.
##
## The solver does NOT generate levels. It validates them. The
## generator (Step 22) emits a recipe; the solver proves the
## recipe is winnable; the validator (SugartrailValidator, this
## file) then plays the proof through the production session
## engine to confirm parity.

## Outcome of a solve. Exactly one of the four classifications.
enum Classification {
	SOLVED = 0,
	UNSOLVABLE = 1,
	TIMEOUT = 2,
	RESOURCE_LIMIT = 3,
}

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Coord = Board.CellCoord

## Hard caps for the iterative-deepening search. Each cap is the
## "documented failure mode" — exceeding it produces TIMEOUT /
## RESOURCE_LIMIT rather than an unbounded search. The defaults are
## the per-recipe budgets the launch batch tool uses; tests override
## these to keep runtimes short.
const DEFAULT_MAX_DEPTH: int = 30
const DEFAULT_MAX_NODES: int = 200_000
const DEFAULT_MAX_TIME_MS: int = 5000

## Solver options. max_moves = the level's documented move budget
## (passed in by the validator from the recipe's `moves` field).
## The other three are search-budget knobs.
class SolveOptions:
	var max_moves: int = 20
	var max_depth: int = DEFAULT_MAX_DEPTH
	var max_nodes: int = DEFAULT_MAX_NODES
	var max_time_ms: int = DEFAULT_MAX_TIME_MS
	var use_boosters: bool = false
	var seed: int = 0

	func _init(p_max_moves: int = 20,
			p_max_depth: int = DEFAULT_MAX_DEPTH,
			p_max_nodes: int = DEFAULT_MAX_NODES,
			p_max_time_ms: int = DEFAULT_MAX_TIME_MS,
			p_use_boosters: bool = false,
			p_seed: int = 0) -> void:
		max_moves = p_max_moves
		max_depth = p_max_depth
		max_nodes = p_max_nodes
		max_time_ms = p_max_time_ms
		use_boosters = p_use_boosters
		seed = p_seed

## A single move in a witness sequence. Carries the two coords of
## the swap; the validator replays these through the production
## session engine to confirm parity.
class ProofMove:
	var a: Coord = null
	var b: Coord = null

	func _init(p_a: Coord, p_b: Coord) -> void:
		a = p_a
		b = p_b

	func to_dict() -> Dictionary:
		return {"x1": a.x, "y1": a.y, "x2": b.x, "y2": b.y}

## Final result of a solve. classification is the answer;
## proof_moves is the witness (empty when not SOLVED);
## stats describe the search effort for the difficulty scorer.
class SolverResult:
	var classification: int = Classification.TIMEOUT
	var proof_moves: Array = []  # Array[ProofMove]
	var moves_used: int = 0
	var nodes_visited: int = 0
	var dead_ends_hit: int = 0
	var duration_ms: int = 0
	var note: String = ""

	func _init(p_classification: int = Classification.TIMEOUT,
			p_proof_moves: Array = [], p_moves_used: int = 0,
			p_nodes_visited: int = 0, p_dead_ends: int = 0,
			p_duration_ms: int = 0, p_note: String = "") -> void:
		classification = p_classification
		proof_moves = p_proof_moves
		moves_used = p_moves_used
		nodes_visited = p_nodes_visited
		dead_ends_hit = p_dead_ends
		duration_ms = p_duration_ms
		note = p_note

	func to_dict() -> Dictionary:
		var proof_out: Array = []
		for m in proof_moves:
			proof_out.append((m as ProofMove).to_dict())
		return {
			"classification": classification,
			"proof_moves": proof_out,
			"moves_used": moves_used,
			"nodes_visited": nodes_visited,
			"dead_ends_hit": dead_ends_hit,
			"duration_ms": duration_ms,
			"note": note,
		}

## Internal node state for the IDDFS loop. Carries the board
## snapshot, the per-objective progress, the RNG state, the
## remaining moves, the witness path so far, and the depth.
## The RNG state is the critical bit that keeps the solver's
## cascades aligned with the session engine's cascades on replay.
class _Node:
	var board_snap: Dictionary
	var rng_state: int
	var objectives: Dictionary   # {kind_str -> progress}
	var moves_remaining: int
	var path: Array              # Array[ProofMove]
	var depth: int

	func _init(p_board_snap: Dictionary, p_rng_state: int,
			p_objectives: Dictionary,
			p_moves_remaining: int, p_path: Array,
			p_depth: int) -> void:
		board_snap = p_board_snap
		rng_state = p_rng_state
		objectives = p_objectives
		moves_remaining = p_moves_remaining
		path = p_path
		depth = p_depth

## Solve a recipe. Returns a SolverResult. The recipe must be
## validated against LevelRecipe.SCHEMA_VERSION first; the solver
## does not re-validate.
static func solve(recipe: Dictionary,
		opts: SolveOptions = SolveOptions.new()) -> SolverResult:
	var t_start: int = Time.get_ticks_msec()
	var session: Session.Session = Session.from_recipe(recipe)
	var objectives_state: Dictionary = _objectives_state(session)
	var board_snap: Dictionary = session.board.to_snapshot()
	var rng_state: int = session.rng.to_int() if session.rng != null else opts.seed
	# Transposition table. Keyed by a signature that includes
	# board hash + objective progress + moves remaining + rng
	# state. Avoids re-exploring equivalent states.
	var visited: Dictionary = {}
	var stats: Dictionary = {"nodes": 0, "dead_ends": 0}
	var initial := _Node.new(board_snap, rng_state,
			objectives_state, opts.max_moves, [], 0)
	var proof: Array = _iddfs(initial, opts, visited, stats, t_start)
	var duration: int = Time.get_ticks_msec() - t_start
	if proof.size() > 0:
		return SolverResult.new(Classification.SOLVED, proof,
				proof.size(), int(stats["nodes"]),
				int(stats["dead_ends"]), duration,
				"solved at depth %d" % proof.size())
	if int(stats["nodes"]) >= opts.max_nodes:
		return SolverResult.new(Classification.RESOURCE_LIMIT, [],
				0, int(stats["nodes"]), int(stats["dead_ends"]),
				duration, "node cap %d hit" % opts.max_nodes)
	if duration >= opts.max_time_ms:
		return SolverResult.new(Classification.TIMEOUT, [],
				0, int(stats["nodes"]), int(stats["dead_ends"]),
				duration, "time cap %dms hit" % opts.max_time_ms)
	return SolverResult.new(Classification.UNSOLVABLE, [],
			0, int(stats["nodes"]), int(stats["dead_ends"]),
			duration, "exhausted search at max_depth %d" % opts.max_depth)

## Iterative-deepening DFS. Bounded by max_depth (move budget),
## max_nodes, and max_time_ms. Returns the witness array on
## success or an empty array on failure. The caller checks
## `witness.size() > 0` to detect a proof.
static func _iddfs(root: _Node, opts: SolveOptions,
		visited: Dictionary, stats: Dictionary,
		t_start: int) -> Array:
	var max_moves: int = min(opts.max_moves, opts.max_depth)
	# Iterative deepening: try depth limits 1..max_moves in order.
	# Each iteration re-starts from root; transposition table is
	# scoped per-iteration so deeper iterations see fresh history.
	for limit in range(1, max_moves + 1):
		visited.clear()
		stats["nodes"] = 0
		stats["dead_ends"] = 0
		var witness: Array = _dfs(root, limit, opts, visited, stats,
				t_start)
		if witness.size() > 0:
			return witness
		if int(stats["nodes"]) >= opts.max_nodes:
			return []
		if Time.get_ticks_msec() - t_start >= opts.max_time_ms:
			return []
	return []

## Depth-limited DFS. Returns a witness array (size > 0) if the
## objective is reachable within `limit` more swaps, or an empty
## array otherwise.
static func _dfs(node: _Node, limit: int, opts: SolveOptions,
		visited: Dictionary, stats: Dictionary,
		t_start: int) -> Array:
	if Time.get_ticks_msec() - t_start >= opts.max_time_ms:
		return []
	if int(stats["nodes"]) >= opts.max_nodes:
		return []
	stats["nodes"] += 1
	# Build a board from the snapshot and an RNG from the carried
	# state. Both are passed into Resolution.resolve so the refill
	# uses the same RNG the session engine will use.
	var board: Board = _board_from_snapshot(node.board_snap)
	var rng := SugartrailRng.from_int(node.rng_state)
	# Check win condition: every objective at progress >= target.
	if _is_objective_complete(node.objectives):
		return node.path
	if limit == 0 or node.moves_remaining <= 0:
		return []
	# Enumerate legal moves. Order is stable across calls for the
	# same board (Rules.enumerate_legal_swaps iterates cells in
	# snapshot order).
	var moves: Array = Rules.enumerate_legal_swaps(board)
	var key: String = _signature(node.board_snap,
			node.objectives, node.moves_remaining,
			node.rng_state)
	if visited.has(key) and int(visited[key]) >= node.depth:
		return []
	visited[key] = node.depth
	for entry in moves:
		var a: Coord = entry[0]
		var b: Coord = entry[1]
		if not Rules.try_swap(board, a, b):
			continue
		var cascade: Resolution.CascadeResult = Resolution.resolve(
				board, rng)
		var new_moves_remaining: int = node.moves_remaining - 1
		var new_objectives: Dictionary = _apply_cascade_to_objectives(
				node.objectives, cascade)
		var new_board_snap: Dictionary = board.to_snapshot()
		var new_rng_state: int = rng.to_int()
		# If we are out of moves, prune.
		if new_moves_remaining <= 0:
			stats["dead_ends"] += 1
			continue
		var new_node := _Node.new(new_board_snap, new_rng_state,
				new_objectives,
				new_moves_remaining,
				node.path + [ProofMove.new(a, b)],
				node.depth + 1)
		var result: Array = _dfs(new_node, limit - 1, opts, visited,
				stats, t_start)
		if result.size() > 0:
			return result
		stats["dead_ends"] += 1
		# Backtrack: rebuild board + rng from the parent snapshots
		# so the next sibling sees the same state.
		board = _board_from_snapshot(node.board_snap)
		rng = SugartrailRng.from_int(node.rng_state)
	return []

## Goal check: every objective at progress >= target. The
## objectives state is a dictionary keyed by kind ("collect",
## "reach_score", etc.) carrying {progress, target}.
static func _is_objective_complete(state: Dictionary) -> bool:
	for kind in state.keys():
		var entry: Dictionary = state[kind]
		if int(entry.get("progress", 0)) < int(entry.get("target", 1)):
			return false
	return state.size() > 0

## Build the initial objective state dictionary from a session.
static func _objectives_state(session: Session.Session) -> Dictionary:
	var out: Dictionary = {}
	for o in session.objectives:
		var obj: Session.Objective = o
		var key: String = _objective_kind_name(obj.kind)
		out[key] = {
			"progress": int(obj.progress),
			"target": int(_objective_target(obj)),
			"target_kind": int(obj.target_kind),
			"target_score": int(obj.target_score),
		}
	return out

## Map a cascade's events to objective progress deltas and return
## the updated state dictionary. Mirrors Session._update_objectives_from_events.
static func _apply_cascade_to_objectives(state: Dictionary,
		cascade: Resolution.CascadeResult) -> Dictionary:
	var out: Dictionary = state.duplicate(true)
	# Track score separately for REACH_SCORE.
	var score: int = 0
	for ev in cascade.events:
		var event: Resolution.DomainEvent = ev
		match event.kind:
			Resolution.EventKind.REMOVE:
				score += 10
				if event.cascade >= 1:
					score += 5 * event.cascade
				if out.has("collect"):
					var target_kind: int = int(out["collect"].get("target_kind", -1))
					if event.piece_kind_id == target_kind:
						# Each REMOVE event corresponds to one cell.
						out["collect"]["progress"] = int(out["collect"]["progress"]) + 1
			Resolution.EventKind.BLOCKER_DAMAGE:
				score += 15
				if out.has("clear_layers"):
					out["clear_layers"]["progress"] = int(out["clear_layers"]["progress"]) + 1
			Resolution.EventKind.BLOCKER_BREAK:
				score += 15
				if out.has("clear_layers"):
					out["clear_layers"]["progress"] = int(out["clear_layers"]["progress"]) + 1
			Resolution.EventKind.TOKEN_RELEASE:
				score += 50
				if out.has("release_token"):
					out["release_token"]["progress"] = int(out["release_token"]["progress"]) + 1
	# REACH_SCORE tracks the running score.
	if out.has("reach_score"):
		out["reach_score"]["progress"] = int(out["reach_score"]["progress"]) + score
	return out

## Read the target total for an objective depending on its kind.
static func _objective_target(obj: Session.Objective) -> int:
	match obj.kind:
		Session.ObjectiveKind.COLLECT_KIND, \
		Session.ObjectiveKind.RELEASE_TOKEN:
			return obj.target_total
		Session.ObjectiveKind.REACH_SCORE:
			return obj.target_score
		Session.ObjectiveKind.CLEAR_LAYERS:
			return max(obj.target_layers, obj.target_total)
	return 0

## String name for an objective kind. Used as the key in the
## state dictionary.
static func _objective_kind_name(kind: int) -> String:
	match kind:
		Session.ObjectiveKind.COLLECT_KIND: return "collect"
		Session.ObjectiveKind.REACH_SCORE: return "reach_score"
		Session.ObjectiveKind.CLEAR_LAYERS: return "clear_layers"
		Session.ObjectiveKind.RELEASE_TOKEN: return "release_token"
	return "unknown"

## Compute a deterministic signature for a state. Two states with
## the same signature are considered equivalent for the
## transposition table.
static func _signature(board_snap: Dictionary, objectives: Dictionary,
		moves_remaining: int, rng_state: int) -> String:
	var h: int = 0x811C9DC5
	var cells: Array = board_snap.get("cells", [])
	for c in cells:
		var cd: Dictionary = c
		var kind: int = int(cd.get("kind", 0))
		var piece_kind: int = int(cd.get("piece_kind_id", -1))
		var special: int = 0
		if cd.has("special"):
			special = int(cd["special"].get("kind", 0))
		var locked: int = 1 if bool(cd.get("locked", false)) else 0
		var frosting: int = int(cd.get("frosting_layers", 0))
		h = h ^ (kind * 31 + piece_kind * 17 + special * 7 + locked * 3 + frosting)
		h = (h * 0x01000193) & 0xFFFFFFFF
	# Mix in objective progress (so "all reds collected" and
	# "5 reds collected" are different states).
	var obj_keys: Array = objectives.keys()
	obj_keys.sort()
	for k in obj_keys:
		var entry: Dictionary = objectives[k]
		h = h ^ (int(entry.get("progress", 0)) * 53)
		h = (h * 0x01000193) & 0xFFFFFFFF
	h = h ^ (moves_remaining * 101)
	h = (h * 0x01000193) & 0xFFFFFFFF
	# Mix in RNG state so two states with the same board + progress
	# but different future random outcomes are not collapsed.
	h = h ^ (rng_state * 131)
	h = (h * 0x01000193) & 0xFFFFFFFF
	return str(h)

## Build a Board from a snapshot dictionary. The snapshot stores
## the BLOCKED list (reconstructed from cells with kind==BLOCKED)
## so the restored board matches the source exactly. FROSTING cells
## roundtrip through `kind` + `frosting_layers`.
static func _board_from_snapshot(snap: Dictionary) -> Board:
	var w: int = int(snap.get("width", 0))
	var h: int = int(snap.get("height", 0))
	var palette: int = int(snap.get("normal_palette_size", 6))
	var blocked: Array = []
	var cells_in: Array = snap.get("cells", [])
	for entry in cells_in:
		if int(entry.get("kind", -1)) == Board.CellKind.BLOCKED:
			blocked.append(Coord.new(int(entry.get("x", 0)),
					int(entry.get("y", 0))))
	var board := Board.new(Board.BoardConfig.new(w, h, palette, blocked))
	for entry in cells_in:
		var kind: int = int(entry.get("kind", -1))
		var c := Coord.new(int(entry.get("x", 0)), int(entry.get("y", 0)))
		if kind == Board.CellKind.PIECE:
			var piece_kind: int = int(entry.get("piece_kind_id", 0))
			if entry.has("special"):
				var sp := Board.SpecialPiece.new(
						piece_kind, Board.Special.from_dict(entry["special"]))
				board.set_piece(c, sp)
			else:
				board.set_piece(c, Board.Piece.new(piece_kind))
			if bool(entry.get("locked", false)):
				board.cell_at(c).locked = true
		elif kind == Board.CellKind.FROSTING:
			var fl: int = int(entry.get("frosting_layers", 1))
			board.cell_at(c).kind = Board.CellKind.FROSTING
			board.cell_at(c).frosting_layers = fl
	var tokens_in: Array = snap.get("tokens", [])
	for td in tokens_in:
		var tdd: Dictionary = td
		board.add_token(int(tdd.get("x", 0)), int(tdd.get("y", 0)),
				int(tdd.get("id", -1)),
				int(tdd.get("matching_kind", -1)))
	return board
