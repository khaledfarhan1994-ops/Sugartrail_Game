class_name SugartrailSession
extends RefCounted
## Level session: state machine, objective, score, and stars.
##
## Step 10 turns the deterministic engine (SugartrailBoard +
## SugartrailRules + SugartrailResolution + SugartrailReplay) into a
## complete move-limited level session. The session is itself pure
## data: no rendering, no input, no audio. A presentation layer (or
## a replay test) can drive the session by calling its API and
## reading its state.
##
## The session is fully serialisable: snapshot_state() produces a
## Dictionary that, combined with the action log, reproduces the
## session exactly across runs.

## Session lifecycle states. The state machine transitions are
## described inline in each setter.
enum State {
	INTRO = 0,    # level loaded, animation playing; no input yet
	READY = 1,    # accepting swaps
	RESOLVING = 2,# a swap has been committed; resolution running
	PAUSED = 3,   # explicit pause; no input
	WON = 4,      # objective complete
	LOST = 5,     # out of moves
}

## Objective kinds supported. Step 10 shipped COLLECT_KIND +
## REACH_SCORE (latter as enum only). Step 16 wires REACH_SCORE
## and adds CLEAR_LAYERS + RELEASE_TOKEN.
enum ObjectiveKind {
	COLLECT_KIND = 0,
	REACH_SCORE = 1,
	CLEAR_LAYERS = 2,
	RELEASE_TOKEN = 3,
}

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece

## A level objective. Several may be active per session (Step 16).
## Each objective is independent and carries the fields it needs
## for its kind (other fields are unused).
class Objective:
	var kind: int = ObjectiveKind.COLLECT_KIND
	## For COLLECT_KIND: the piece kind_id the player must collect.
	var target_kind: int = 0
	## For COLLECT_KIND / CLEAR_LAYERS / RELEASE_TOKEN: the total
	## required (pieces collected / frosting layers cleared / tokens
	## released).
	var target_total: int = 0
	## How much progress has been made so far.
	var progress: int = 0
	## For REACH_SCORE: the score the player must reach.
	var target_score: int = 0
	## For CLEAR_LAYERS: the total frosting layers to clear. Defaults
	## to `target_total` so the legacy single `target_total` field
	## still works for CLEAR_LAYERS recipes.
	var target_layers: int = 0
	## For RELEASE_TOKEN: which Board token id this objective is
	## tracking. A negative id means "any token".
	var token_id: int = -1

	func _init(p_kind: int = ObjectiveKind.COLLECT_KIND,
			p_target_kind: int = 0, p_target_total: int = 0,
			p_target_score: int = 0, p_target_layers: int = 0,
			p_token_id: int = -1) -> void:
		kind = p_kind
		target_kind = p_target_kind
		target_total = p_target_total
		progress = 0
		target_score = p_target_score
		target_layers = p_target_layers if p_target_layers > 0 else p_target_total
		token_id = p_token_id

	## True when the objective's completion condition is satisfied.
	func is_complete() -> bool:
		match kind:
			ObjectiveKind.COLLECT_KIND, \
			ObjectiveKind.CLEAR_LAYERS, \
			ObjectiveKind.RELEASE_TOKEN:
				return progress >= target_total
			ObjectiveKind.REACH_SCORE:
				return progress >= target_score
		return false

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"target_kind": target_kind,
			"target_total": target_total,
			"progress": progress,
			"target_score": target_score,
			"target_layers": target_layers,
			"token_id": token_id,
		}

	static func from_dict(d: Dictionary) -> Objective:
		var o := Objective.new(
			int(d.get("kind", ObjectiveKind.COLLECT_KIND)),
			int(d.get("target_kind", 0)),
			int(d.get("target_total", 0)),
			int(d.get("target_score", 0)),
			int(d.get("target_layers", 0)),
			int(d.get("token_id", -1)))
		o.progress = int(d.get("progress", 0))
		return o

## Star thresholds for a session. Defaults are a coarse spread of
## 1, 2, 3 stars at 25%, 60%, and 100% of the score target. The level
## recipe can override these.
class StarThresholds:
	var one_star: int = 0
	var two_star: int = 0
	var three_star: int = 0

	func _init(p_one: int = 0, p_two: int = 0, p_three: int = 0) -> void:
		one_star = p_one
		two_star = p_two
		three_star = p_three

	func stars_for(score: int) -> int:
		if score >= three_star and three_star > 0:
			return 3
		if score >= two_star and two_star > 0:
			return 2
		if score >= one_star and one_star > 0:
			return 1
		return 0

	func to_dict() -> Dictionary:
		return {
			"one_star": one_star,
			"two_star": two_star,
			"three_star": three_star,
		}

	static func from_dict(d: Dictionary) -> StarThresholds:
		return StarThresholds.new(
			int(d.get("one_star", 0)),
			int(d.get("two_star", 0)),
			int(d.get("three_star", 0)))

## A level session owns the board, the objectives, the move counter,
## the score, the action log, and the RNG. It does not own any
## presentation.
##
## Step 16: `objectives` is an Array of Objective. The session is
## won when ALL objectives are complete (AND-joined). The legacy
## `objective` field is preserved as a back-compat shim pointing
## at `objectives[0]` for tests that touch a single objective.
class Session:
	var state: int = State.INTRO
	## Recipe metadata: id, version, board config. Kept as a
	## Dictionary so arbitrary recipe fields roundtrip cleanly.
	var recipe: Dictionary = {}
	var board: Board = null
	## Step 16: list of objectives. The session wins when all are
	## complete. Always at least one entry.
	var objectives: Array = []
	var stars: StarThresholds = null
	## Initial move budget. Each legal swap decrements this by 1.
	var moves_remaining: int = 0
	## Cumulative score across the session.
	var score: int = 0
	## Action log: every legal swap the player has performed.
	var actions: Array = []
	## RNG instance used for refill. Owned by the session.
	var rng: Rng = null

	## Back-compat: legacy callers expect `session.objective` to be
	## a single Objective. We expose objectives[0] for that purpose.
	## Setting it replaces the first entry.
	var objective: Objective:
		get:
			if objectives.size() > 0:
				return objectives[0]
			return null
		set(value):
			if objectives.size() == 0:
				objectives.append(value)
			else:
				objectives[0] = value

	func _init(p_recipe: Dictionary, p_board: Board, p_objectives: Array,
			p_stars: StarThresholds, p_moves: int, p_rng: Rng) -> void:
		recipe = p_recipe
		board = p_board
		objectives = p_objectives
		stars = p_stars
		moves_remaining = p_moves
		rng = p_rng

	## True when every objective is complete.
	func all_objectives_complete() -> bool:
		for o in objectives:
			var obj: Objective = o
			if not obj.is_complete():
				return false
		return true

	## Try a swap from the presentation (or from a test). Returns
	## true on success; false if the session cannot accept a swap
	## right now (state != READY, illegal swap, or out of moves).
	## On success the session transitions to RESOLVING, runs the
	## domain resolution, updates the objectives and score, and
	## transitions back to READY or to WON/LOST as appropriate.
	func attempt_swap(a: Coord, b: Coord) -> bool:
		if state != State.READY:
			return false
		if moves_remaining <= 0:
			return false
		if not Rules.is_orthogonal_neighbor(a, b):
			return false
		if not Rules.try_swap(board, a, b):
			return false
		# Record the action BEFORE resolving, so the log captures
		# exactly what the player did.
		actions.append(Replay.Action.new(Replay.ActionKind.SWAP, a, b))
		moves_remaining -= 1
		state = State.RESOLVING
		# First, count pieces removed by the swap itself. try_swap
		# just creates the match; the resolution loop is what
		# actually removes pieces. We award score for every piece
		# the resolution clears.
		var result: Resolution.CascadeResult = Resolution.resolve(board, rng)
		_update_objectives_from_events(result.events)
		# Check win / loss.
		if all_objectives_complete():
			state = State.WON
		elif moves_remaining <= 0:
			state = State.LOST
		else:
			state = State.READY
		return true

	## Apply the resolution events to each objective. Each event
	## kind contributes to specific objectives (REACH_SCORE watches
	## the score, CLEAR_LAYERS watches BLOCKER_DAMAGE + BLOCKER_BREAK,
	## RELEASE_TOKEN watches TOKEN_RELEASE, COLLECT_KIND watches
	## REMOVE). The score is bumped per the rules in the Step 16
	## design: 10 per piece + 5 per cascade step + 15 per frosting
	## decrement + 50 per token release.
	func _update_objectives_from_events(events: Array) -> void:
		for ev in events:
			var e: Resolution.DomainEvent = ev
			match e.kind:
				Resolution.EventKind.REMOVE:
					score += 10
					if e.cascade >= 1:
						score += 5 * e.cascade
					for o in objectives:
						var obj: Objective = o
						if obj.kind == ObjectiveKind.COLLECT_KIND:
							if e.piece_kind_id == obj.target_kind:
								obj.progress += 1
				Resolution.EventKind.BLOCKER_DAMAGE:
					# Each BLOCKER_DAMAGE decrements a frosting layer
					# by 1; the CLEAR_LAYERS objective counts those.
					score += 15
					for o in objectives:
						var obj: Objective = o
						if obj.kind == ObjectiveKind.CLEAR_LAYERS:
							obj.progress += 1
				Resolution.EventKind.BLOCKER_BREAK:
					# BREAK is the last layer going to zero; count it
					# the same way DAMAGE counts (1 layer cleared).
					score += 15
					for o in objectives:
						var obj: Objective = o
						if obj.kind == ObjectiveKind.CLEAR_LAYERS:
							obj.progress += 1
				Resolution.EventKind.TOKEN_RELEASE:
					# A trapped token reached a matching piece.
					score += 50
					var token_id_v: int = -1
					if e.coords.size() > 0 and e.special_origin != null:
						token_id_v = e.special_origin.x  # encoded in special_origin
					for o in objectives:
						var obj: Objective = o
						if obj.kind == ObjectiveKind.RELEASE_TOKEN:
							if obj.token_id < 0 or obj.token_id == token_id_v:
								obj.progress += 1
		# REACH_SCORE objective tracks `score` directly.
		for o in objectives:
			var obj: Objective = o
			if obj.kind == ObjectiveKind.REACH_SCORE:
				obj.progress = score

	## Pause the session if it is currently accepting input. A
	## session in any state can be paused; only READY can be paused
	## cleanly. PAUSED is reversible via resume().
	func pause() -> void:
		if state == State.READY or state == State.RESOLVING or state == State.INTRO:
			state = State.PAUSED

	func resume() -> void:
		if state == State.PAUSED:
			state = State.READY

	## Retry the session from scratch: reset the board using a
	## fresh RNG draw (same initial seed), clear the action log,
	## and return to INTRO. Deterministic: same initial seed
	## produces the same retry.
	func retry(initial_seed: int) -> void:
		var old_rng: Rng = rng
		rng = Rng.new(initial_seed)
		# Reset the board by rebuilding it. The recipe owns the
		# BoardConfig; we re-create the Board and refill it.
		var cfg: Board.BoardConfig = board.config
		board = Board.new(cfg)
		# Re-fill the board deterministically.
		var avoid: bool = recipe.get("avoid_initial_matches", true)
		Resolution.fill_random(board, rng, avoid)
		# Step 15: re-apply locked cells on the freshly-filled pieces.
		board.apply_locks_to_pieces()
		# Reset the session state.
		state = State.INTRO
		score = 0
		moves_remaining = int(recipe.get("moves", 0))
		for o in objectives:
			var obj: Objective = o
			obj.progress = 0
		actions.clear()
		old_rng = null  # release

	func stars_earned() -> int:
		return stars.stars_for(score)

	## Return a snapshot suitable for JSON serialisation.
	func snapshot_state() -> Dictionary:
		var objs_out: Array = []
		for o in objectives:
			var obj: Objective = o
			objs_out.append(obj.to_dict())
		return {
			"state": state,
			"recipe": recipe,
			"moves_remaining": moves_remaining,
			"score": score,
			"objectives": objs_out,
			"objective_legacy": objective.to_dict() if objective != null else {},
			"stars": stars.to_dict(),
			"rng_state": rng.to_int(),
			"board": board.to_snapshot(),
			"action_count": actions.size(),
		}

## Construct a session from a recipe dictionary. The recipe may use
## the v3 schema with an explicit `objectives` array, or the legacy
## single-objective `target_kind` + `target_total` (auto-migrated
## to a single COLLECT_KIND objective).
##
## Optional v3 fields: tokens (Array of {x,y,id,matching_kind}).
static func from_recipe(recipe: Dictionary) -> Session:
	var w: int = int(recipe.get("board_w", 6))
	var h: int = int(recipe.get("board_h", 8))
	var palette: int = int(recipe.get("palette", 6))
	var blocked: Array = []
	var blockers: Array = recipe.get("blockers", [])
	var cfg := Board.BoardConfig.new(w, h, palette, blocked, blockers)
	var board: Board = Board.new(cfg)
	var seed: int = int(recipe.get("seed", 0))
	var rng := Rng.new(seed)
	var avoid: bool = recipe.get("avoid_initial_matches", true)
	Resolution.fill_random(board, rng, avoid)
	# Step 15: lock the LOCKED cells after refill so the locks ride
	# on the now-occupied pieces.
	board.apply_locks_to_pieces()
	# Step 16: place tokens on the freshly-filled board.
	var tokens_v: Variant = recipe.get("tokens", [])
	if tokens_v is Array:
		for entry in tokens_v:
			var td: Dictionary = entry
			board.add_token(int(td.get("x", 0)), int(td.get("y", 0)),
					int(td.get("id", -1)), int(td.get("matching_kind", -1)))
	var objectives: Array = _objectives_from_recipe(recipe)
	var stars := StarThresholds.new(
		int(recipe.get("star_one", 50)),
		int(recipe.get("star_two", 150)),
		int(recipe.get("star_three", 300)))
	var moves: int = int(recipe.get("moves", 20))
	var session := Session.new(recipe, board, objectives, stars, moves, rng)
	session.state = State.READY
	return session

## Build the objectives list from a recipe. Prefers the explicit
## `objectives` array (v3); falls back to a single COLLECT_KIND
## from the legacy target_kind / target_total pair.
static func _objectives_from_recipe(recipe: Dictionary) -> Array:
	var out: Array = []
	var objs_v: Variant = recipe.get("objectives", [])
	if objs_v is Array and (objs_v as Array).size() > 0:
		for od in objs_v:
			var od_dict: Dictionary = od
			out.append(Objective.from_dict(od_dict))
		return out
	# Back-compat: legacy single-objective recipe.
	var obj := Objective.new(
		ObjectiveKind.COLLECT_KIND,
		int(recipe.get("target_kind", 0)),
		int(recipe.get("target_total", 10)))
	out.append(obj)
	return out
