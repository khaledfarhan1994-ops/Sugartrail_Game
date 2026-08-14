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

## Objective kinds supported in Step 10. Blockers (Step 15) and
## other advanced objectives arrive later.
enum ObjectiveKind {
	COLLECT_KIND = 0,
	REACH_SCORE = 1,
}

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece

## A level objective. Exactly one is active per session.
class Objective:
	var kind: int = ObjectiveKind.COLLECT_KIND
	## For COLLECT_KIND: the piece kind_id the player must collect.
	var target_kind: int = 0
	## For COLLECT_KIND or REACH_SCORE: the total required.
	var target_total: int = 0
	## How much progress has been made so far.
	var progress: int = 0

	func _init(p_kind: int = ObjectiveKind.COLLECT_KIND,
			p_target_kind: int = 0, p_target_total: int = 0) -> void:
		kind = p_kind
		target_kind = p_target_kind
		target_total = p_target_total
		progress = 0

	func is_complete() -> bool:
		return progress >= target_total

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"target_kind": target_kind,
			"target_total": target_total,
			"progress": progress,
		}

	static func from_dict(d: Dictionary) -> Objective:
		var o := Objective.new(
			int(d.get("kind", ObjectiveKind.COLLECT_KIND)),
			int(d.get("target_kind", 0)),
			int(d.get("target_total", 0)))
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

## A level session owns the board, the objective, the move counter,
## the score, the action log, and the RNG. It does not own any
## presentation.
class Session:
	var state: int = State.INTRO
	## Recipe metadata: id, version, board config. Kept as a
	## Dictionary so arbitrary recipe fields roundtrip cleanly.
	var recipe: Dictionary = {}
	var board: Board = null
	var objective: Objective = null
	var stars: StarThresholds = null
	## Initial move budget. Each legal swap decrements this by 1.
	var moves_remaining: int = 0
	## Cumulative score across the session.
	var score: int = 0
	## Action log: every legal swap the player has performed.
	var actions: Array = []
	## RNG instance used for refill. Owned by the session.
	var rng: Rng = null

	func _init(p_recipe: Dictionary, p_board: Board, p_objective: Objective,
			p_stars: StarThresholds, p_moves: int, p_rng: Rng) -> void:
		recipe = p_recipe
		board = p_board
		objective = p_objective
		stars = p_stars
		moves_remaining = p_moves
		rng = p_rng

	## Try a swap from the presentation (or from a test). Returns
	## true on success; false if the session cannot accept a swap
	## right now (state != READY, illegal swap, or out of moves).
	## On success the session transitions to RESOLVING, runs the
	## domain resolution, updates the objective and score, and
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
		var removed_in_swap: int = 0
		# First, count pieces removed by the swap itself. try_swap
		# just creates the match; the resolution loop is what
		# actually removes pieces. We award score for every piece
		# the resolution clears.
		var result: Resolution.CascadeResult = Resolution.resolve(board, rng)
		for ev in result.events:
			var e: Resolution.DomainEvent = ev
			if e.kind == Resolution.EventKind.REMOVE:
				removed_in_swap += 1
				# Score: 10 points per piece removed.
				score += 10
				# Cascade bonus: each piece beyond the first in a
				# cycle scores extra so cascades feel rewarding.
				if e.cascade >= 1:
					score += 5 * e.cascade
				# Objective progress: COLLECT_KIND.
				if objective.kind == ObjectiveKind.COLLECT_KIND:
					if e.piece_kind_id == objective.target_kind:
						objective.progress += 1
		# Check win / loss.
		if objective.is_complete():
			state = State.WON
		elif moves_remaining <= 0:
			state = State.LOST
		else:
			state = State.READY
		return true

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
		objective.progress = 0
		actions.clear()
		old_rng = null  # release

	func stars_earned() -> int:
		return stars.stars_for(score)

	## Return a snapshot suitable for JSON serialisation.
	func snapshot_state() -> Dictionary:
		return {
			"state": state,
			"recipe": recipe,
			"moves_remaining": moves_remaining,
			"score": score,
			"objective": objective.to_dict(),
			"stars": stars.to_dict(),
			"rng_state": rng.to_int(),
			"board": board.to_snapshot(),
			"action_count": actions.size(),
		}

## Construct a session from a recipe dictionary. The recipe must
## contain at minimum:
##   recipe_id (string), version (int), moves (int), target_kind (int),
##   target_total (int), palette (int), board_w (int), board_h (int),
##   seed (int).
## Optional: star_one / star_two / star_three overrides, blockers.
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
	var objective := Objective.new(
		ObjectiveKind.COLLECT_KIND,
		int(recipe.get("target_kind", 0)),
		int(recipe.get("target_total", 10)))
	var stars := StarThresholds.new(
		int(recipe.get("star_one", 50)),
		int(recipe.get("star_two", 150)),
		int(recipe.get("star_three", 300)))
	var moves: int = int(recipe.get("moves", 20))
	var session := Session.new(recipe, board, objective, stars, moves, rng)
	session.state = State.READY
	return session
