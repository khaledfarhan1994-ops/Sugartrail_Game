class_name SugartrailHints
extends RefCounted
## Deterministic hint ranker for legal moves.
##
## Step 17 introduces hints. The contract is:
##
##   - Pure function: never mutates the board or the RNG.
##   - Deterministic: same board + same hint seed -> same ranked list.
##   - Never suggests an illegal move.
##   - Returns at most `limit` suggestions, ordered best-first.
##
## A hint is a Dictionary {coord_a, coord_b, score, reason}. The
## presentation layer reads these and animates the suggestion.
## `reason` is a short localization-friendly string ("cascade",
## "objective", "shield-break", etc.).

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const Cell = Board.Cell

## Reason codes returned with each hint. The presentation layer
## maps these to a one-word label for the player.
const REASON_LEGAL: String = "legal"
const REASON_OBJECTIVE: String = "objective"
const REASON_FROSTING: String = "shield-break"
const REASON_TOKEN: String = "token-release"
const REASON_CASCADE: String = "cascade"

## Return at most `limit` legal-move suggestions, ordered best-first.
## `limit` defaults to 1 (the "give me one good move" use case).
## Suggestions are deterministic for a given board + RNG seed.
##
## The ranker reuses the resolution pipeline on a clone of the
## board so the suggested move doesn't perturb the live state. The
## clone is a throwaway Board; we never mutate it.
static func suggest(board: Board, rng: Rng, limit: int = 1) -> Array:
	if limit <= 0:
		return []
	var moves: Array = Rules.enumerate_legal_swaps(board)
	if moves.size() == 0:
		return []
	# Score each move. Ties are broken by lex order on the pair
	# (so the same board + seed always produces the same order).
	var scored: Array = []
	for pair in moves:
		var a: Coord = pair[0]
		var b: Coord = pair[1]
		var score: int = 0
		var reason: String = REASON_LEGAL
		var sim_b: Board = _clone_board(board)
		var sim_rng: Rng = Rng.new(rng.to_int())
		var result: Resolution.CascadeResult = Resolution.resolve(sim_b, sim_rng, a, b)
		# Score the simulated resolution.
		for ev in result.events:
			var e: Resolution.DomainEvent = ev
			match e.kind:
				Resolution.EventKind.REMOVE:
					score += 10
					if e.cascade >= 1:
						score += 5 * e.cascade
				Resolution.EventKind.BLOCKER_DAMAGE, \
				Resolution.EventKind.BLOCKER_BREAK:
					score += 15
					reason = REASON_FROSTING
				Resolution.EventKind.TOKEN_RELEASE:
					score += 50
					if reason == REASON_LEGAL:
						reason = REASON_TOKEN
				Resolution.EventKind.SPECIAL_ACTIVATE, \
				Resolution.EventKind.SPECIAL_CREATE:
					score += 12
					if reason == REASON_LEGAL:
						reason = REASON_CASCADE
		# Boost moves that touch a frosted cell: they chip layering
		# the player needs to break.
		for ev in result.events:
			if ev.kind == Resolution.EventKind.BLOCKER_DAMAGE \
					or ev.kind == Resolution.EventKind.BLOCKER_BREAK:
				score += 25
		# Boost moves that, after the resolution, advance the
		# primary COLLECT_KIND objective (matched kind == target).
		# We check the board's tokens left: a token released = match.
		if sim_b.tokens.size() < board.tokens.size():
			score += 60
			if reason == REASON_LEGAL:
				reason = REASON_TOKEN
		# Build a stable tiebreaker key.
		var key: String = "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
		scored.append({"pair": [a, b], "score": score,
				"reason": reason, "key": key})
	# Sort by score desc, then by key asc for determinism.
	scored.sort_custom(func(x, y):
		if int(x["score"]) != int(y["score"]):
			return int(x["score"]) > int(y["score"])
		return str(x["key"]) < str(y["key"]))
	# Take the top `limit`.
	var out: Array = []
	for i in range(min(limit, scored.size())):
		var entry: Dictionary = scored[i]
		var pair_v: Array = entry["pair"]
		out.append({
			"coord_a": pair_v[0],
			"coord_b": pair_v[1],
			"score": int(entry["score"]),
			"reason": String(entry["reason"]),
		})
	return out

## Cheaply construct a copy of a board for the resolution simulator.
## The clone uses the same BoardConfig but is filled with the same
## pieces (so resolve() sees the same starting state). Blockers are
## carried across; tokens are not rebroadcast because resolve()
## consumes them via _check_tokens.
static func _clone_board(board: Board) -> Board:
	var cfg: Board.BoardConfig = board.config
	var b := Board.new(cfg)
	for cell in board._cells:
		if cell.is_piece() and cell.piece != null:
			if cell.piece is Board.SpecialPiece:
				var sp: Board.SpecialPiece = cell.piece
				b.set_piece(cell.coord, Board.SpecialPiece.new(
					sp.kind_id, sp.special))
			else:
				b.set_piece(cell.coord, Board.Piece.new(cell.piece.kind_id))
	# Copy tokens (deep enough — entries are flat dicts).
	for entry in board.tokens:
		var ed: Dictionary = entry
		b.add_token(int(ed.get("x", 0)), int(ed.get("y", 0)),
				int(ed.get("id", -1)), int(ed.get("matching_kind", -1)))
	return b
