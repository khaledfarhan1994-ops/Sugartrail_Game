class_name SugartrailLevelGenerator
extends RefCounted
## Mechanic-aware level recipe generator.
##
## Step 22 ships the production-side of the level pipeline: a
## deterministic generator that turns an InputProfile (chapter,
## mechanic, board shape, palette, difficulty, seed) into a fully
## validated recipe dictionary. The generator is the source of all
## 10,000+ generated levels; curated levels are hand-written recipes
## checked into the same schema.
##
## The generator's contract:
##
##   - Deterministic: equal input profile + seed produce equal recipe
##     and equal manifest hash.
##   - Self-rejecting: accidental starting matches, missing legal
##     moves, and obvious impossible configurations are caught
##     inside the generator, not by an external validator. A
##     generator call that returns null has already diagnosed why.
##   - Schema-aware: the produced recipe matches
##     `SugartrailLevelRecipe.SCHEMA_VERSION` (currently v3, the
##     same as curated) so the LevelLoader accepts it without any
##     extra migration.
##   - Mechanic-aware: the chosen mechanic (objective kind, blocker
##     layout, token layout) feeds back into generation so the
##     generated recipe is meaningful for its purpose (a
##     CLEAR_LAYERS level actually has frosting to clear; a
##     RELEASE_TOKEN level actually has a token to release).
##
## The generator does NOT solve the level (Step 23 owns the solver).
## It only produces a recipe that is structurally valid; the solver
## then proves (or rejects) it is solvable within the move budget.

## Difficulty bands. The band drives the move budget, target count,
## and blocker density; the generator does not have its own opinion
## about what counts as "easy" or "hard", it just maps the band to
## documented ranges.
enum Difficulty {
	EASY = 0,
	MEDIUM = 1,
	HARD = 2,
}

## Mechanic kinds. The generator picks an objective kind + matching
## board features based on this.
enum Mechanic {
	COLLECT_KIND = 0,
	REACH_SCORE = 1,
	CLEAR_LAYERS = 2,
	RELEASE_TOKEN = 3,
}

const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Coord = Board.CellCoord

## Generator version. Bump when the algorithm changes in a way that
## could produce a different recipe for the same input profile +
## seed (the manifest records this so a regenerate can detect drift).
const GENERATOR_VERSION: String = "0.6.0-step22"

## Recipe schema version this generator targets. Kept equal to
## `LevelRecipe.SCHEMA_VERSION` so the LevelLoader accepts the
## output without an extra migration step.
const TARGET_SCHEMA_VERSION: int = LevelRecipe.SCHEMA_VERSION

## Hard cap on retry attempts to escape accidental matches /
## deadlock configurations during generation. Each attempt rolls a
## new board from the same seed family; once the cap is hit the
## generator gives up and returns null with an error.
const MAX_GENERATION_ATTEMPTS: int = 32

## An input profile describes everything the generator needs. Every
## field has a documented range; out-of-range values are caught at
## validate() time so a misconfigured batch fails fast.
class InputProfile:
	var chapter: int = 0
	## Zero-based position within the chapter (informational; not
	## consumed by the generator).
	var index_in_chapter: int = 0
	## Difficulty band (0..2).
	var difficulty: int = Difficulty.EASY
	## Objective mechanic. Drives the recipe's objective kind and
	## any blockers / tokens the generator adds.
	var mechanic: int = Mechanic.COLLECT_KIND
	## Board width 4..8.
	var board_w: int = 6
	## Board height 6..10.
	var board_h: int = 8
	## Number of piece kinds in the palette 4..8.
	var palette: int = 5
	## Optional override seed. 0 = "derive seed from the inputs".
	## Non-zero seeds give the deterministic reproducibility tests
	## a fixed handle.
	var seed_override: int = 0

	func _init(p_chapter: int = 0, p_index: int = 0,
			p_difficulty: int = Difficulty.EASY,
			p_mechanic: int = Mechanic.COLLECT_KIND,
			p_board_w: int = 6, p_board_h: int = 8,
			p_palette: int = 5, p_seed_override: int = 0) -> void:
		chapter = p_chapter
		index_in_chapter = p_index
		difficulty = p_difficulty
		mechanic = p_mechanic
		board_w = p_board_w
		board_h = p_board_h
		palette = p_palette
		seed_override = p_seed_override

	func to_dict() -> Dictionary:
		return {
			"chapter": chapter,
			"index_in_chapter": index_in_chapter,
			"difficulty": difficulty,
			"mechanic": mechanic,
			"board_w": board_w,
			"board_h": board_h,
			"palette": palette,
			"seed_override": seed_override,
		}

	static func from_dict(d: Dictionary) -> InputProfile:
		return InputProfile.new(
				int(d.get("chapter", 0)),
				int(d.get("index_in_chapter", 0)),
				int(d.get("difficulty", Difficulty.EASY)),
				int(d.get("mechanic", Mechanic.COLLECT_KIND)),
				int(d.get("board_w", 6)),
				int(d.get("board_h", 8)),
				int(d.get("palette", 5)),
				int(d.get("seed_override", 0)))

## Result of `generate()`. Either `ok == true` and `recipe` is a
## full recipe dictionary, or `ok == false` and `errors` explains
## why. The caller (a batch tool) decides what to do with failures.
class GenerationResult:
	var ok: bool = false
	var recipe: Dictionary = {}
	var manifest: Dictionary = {}
	var errors: Array = []

	func _init(p_ok: bool = false, p_recipe: Dictionary = {},
			p_manifest: Dictionary = {}, p_errors: Array = []) -> void:
		ok = p_ok
		recipe = p_recipe
		manifest = p_manifest
		errors = p_errors

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"errors": errors.duplicate(),
		}

## Validate an InputProfile. Returns an empty errors array on
## success; an array of error strings otherwise. Out-of-range values
## are caught here so the generator body can assume its inputs.
static func validate_profile(p: InputProfile) -> Array:
	var errors: Array = []
	if p.chapter < 0:
		errors.append("chapter %d < 0" % p.chapter)
	if p.index_in_chapter < 0:
		errors.append("index_in_chapter %d < 0" % p.index_in_chapter)
	if p.difficulty < 0 or p.difficulty > 2:
		errors.append("difficulty %d not in 0..2" % p.difficulty)
	if p.mechanic < 0 or p.mechanic > 3:
		errors.append("mechanic %d not in 0..3" % p.mechanic)
	if p.board_w < 4 or p.board_w > 8:
		errors.append("board_w %d out of range 4..8" % p.board_w)
	if p.board_h < 6 or p.board_h > 10:
		errors.append("board_h %d out of range 6..10" % p.board_h)
	if p.palette < 4 or p.palette > 8:
		errors.append("palette %d out of range 4..8" % p.palette)
	return errors

## Generate a recipe from an InputProfile. Returns a
## GenerationResult. On success `recipe` passes
## `LevelRecipe.validate`; on failure `errors` lists the reasons.
##
## The same input profile + seed produces the same recipe every
## time (tested in test_level_generator.gd).
static func generate(p: InputProfile) -> GenerationResult:
	var prof_errors: Array = validate_profile(p)
	if prof_errors.size() > 0:
		return GenerationResult.new(false, {}, {}, prof_errors)
	var seed: int = _derive_seed(p)
	# Generate the board state. Retry up to MAX_GENERATION_ATTEMPTS
	# times so accidental matches + deadlocks don't leak through.
	var attempts: int = 0
	var last_errors: Array = []
	var recipe: Dictionary = {}
	var pieces: Array = []
	while attempts < MAX_GENERATION_ATTEMPTS:
		var attempt_seed: int = _attempt_seed(seed, attempts)
		var attempt_pieces: Array = _generate_pieces(p,
				SugartrailRng.new(attempt_seed))
		# Check for the -1 generator-retry signal before we build
		# the rest of the recipe (it means the no-3-run pick failed).
		if _has_retry_signal(attempt_pieces):
			last_errors = ["piece grid hit generator-retry signal"]
			attempts += 1
			continue
		recipe = _attempt_recipe(p, attempt_seed)
		# Attach the pieces so the validator can build the board.
		recipe["_generated_pieces"] = attempt_pieces
		var errs: Array = _diagnose_recipe(p, recipe)
		if errs.size() == 0:
			pieces = attempt_pieces
			last_errors = []
			break
		last_errors = errs
		attempts += 1
	if last_errors.size() > 0:
		return GenerationResult.new(false, {}, {},
				["generator gave up after %d attempts; last errors: %s" % [
					MAX_GENERATION_ATTEMPTS, str(last_errors)]])
	var manifest: Dictionary = _build_manifest(p, seed, recipe)
	# Drop the diagnostic-only pieces from the recipe before
	# returning; the batch tool re-attaches via attach_pieces()
	# if it wants to persist them.
	var out_recipe: Dictionary = recipe.duplicate(true)
	out_recipe.erase("_generated_pieces")
	return GenerationResult.new(true, out_recipe, manifest, [])

## Derive the seed from the inputs. When `seed_override` is non-zero
## the caller is pinning reproducibility; otherwise the seed is a
## stable hash of the profile so two distinct profiles with the same
## override still get distinct seeds.
static func _derive_seed(p: InputProfile) -> int:
	if p.seed_override != 0:
		return p.seed_override
	# Stable, hash-like combination. NOT cryptographic; the goal is
	# that distinct inputs produce distinct seeds.
	var h: int = 0x811C9DC5
	var fields: Array = [p.chapter, p.index_in_chapter, p.difficulty,
			p.mechanic, p.board_w, p.board_h, p.palette]
	for f in fields:
		h = h ^ int(f)
		h = (h * 0x01000193) & 0xFFFFFFFF
	# Avoid returning 0 (treated as "uninitialised" by the RNG).
	if h == 0:
		h = 1
	return h

## Derive the per-attempt seed. Each attempt rolls a different board
## from the same seed family so we can escape bad starts without
## losing reproducibility.
static func _attempt_seed(seed: int, attempt: int) -> int:
	var v: int = seed ^ (attempt * 0x9E3779B1)
	v = v & 0x7FFFFFFFFFFFFFFF
	if v == 0:
		v = 1
	return v

## Build one candidate recipe from the profile + attempt seed.
## The caller (generate()) separately attaches the generated piece
## grid into the recipe dict via `_generated_pieces` so the diagnosis
## step can build the board. This function only assembles the rest
## of the recipe (blockers, tokens, objectives, star thresholds).
static func _attempt_recipe(p: InputProfile,
		attempt_seed: int) -> Dictionary:
	var rng := SugartrailRng.new(attempt_seed)
	var blockers: Array = _generate_blockers(p, rng)
	var tokens: Array = _generate_tokens(p, rng)
	var moves: int = _moves_for(p, rng)
	var stars: Array = _star_thresholds_for(p, moves)
	# COLLECT_KIND: pick the kind, then derive a target_total that
	# fits the kind's expected share of cells. The exact kind count
	# is only known after the piece grid is generated; the diagnosis
	# step will retry if the kind happens to be under-represented.
	var target_kind: int = 0
	var target_total: int = _target_total_for(p, rng)
	if p.mechanic == Mechanic.COLLECT_KIND:
		target_kind = int(rng.rand_int(p.palette))
		target_total = _clamp_target_to_kind_share(p, target_kind)
	# CLEAR_LAYERS: derive the target from the actual blockers sum
	# so the objective is always achievable.
	var layers_target: int = 0
	if p.mechanic == Mechanic.CLEAR_LAYERS:
		layers_target = _sum_frosting_layers(blockers)
	var objectives: Array = _generate_objectives(p, rng, target_total,
			layers_target, target_kind)
	var seed_value: int = attempt_seed
	# Stable recipe id derived from inputs. The batch tool may
	# rewrite ids to avoid collisions; the generator's id is just a
	# default.
	var recipe_id: String = "gen-ch%d-l%d-%s" % [
			p.chapter, p.index_in_chapter, _hex(seed_value)]
	return {
		"recipe_id": recipe_id,
		"version": TARGET_SCHEMA_VERSION,
		"chapter": p.chapter,
		"index_in_chapter": p.index_in_chapter,
		"board_w": p.board_w,
		"board_h": p.board_h,
		"palette": p.palette,
		"seed": seed_value,
		"moves": moves,
		"target_kind": target_kind,
		"target_total": target_total,
		"star_one": stars[0],
		"star_two": stars[1],
		"star_three": stars[2],
		"tutorial": [],
		"intro_text": "",
		"avoid_initial_matches": true,
		"blockers": blockers,
		"tokens": tokens,
		"objectives": objectives,
		"curated": false,
		"generator_version": GENERATOR_VERSION,
	}

## Generate the piece grid as a 2-D array (row-major). Uses the
## standard "no-initial-match" technique: for each cell, try a kind
## that does not form a 3-run with its left and up neighbours. If
## no such kind exists, fall back to a random one (the generator
## will retry the whole board).
static func _generate_pieces(p: InputProfile, rng) -> Array:
	var grid: Array = []
	var w: int = p.board_w
	var h: int = p.board_h
	for y in range(h):
		var row: Array = []
		for x in range(w):
			var pick: int = _pick_kind(p, rng, row, x, y, grid)
			row.append(pick)
		grid.append(row)
	return grid

## Pick a kind for cell (x, y). Avoids 3-runs with the previous 2
## same-kind cells to the left (x-1, x-2) and the previous 2 above
## (y-1, y-2). If a conflict-free pick exists, returns one chosen
## uniformly; otherwise returns the first kind (the caller retries).
static func _pick_kind(p: InputProfile, rng, row: Array, x: int,
		y: int, grid: Array) -> int:
	var forbidden: Dictionary = {}
	if x >= 2 and row[x - 1] == row[x - 2]:
		forbidden[row[x - 1]] = true
	if y >= 2 and grid[y - 1][x] == grid[y - 2][x]:
		forbidden[grid[y - 1][x]] = true
	var pool: Array = []
	for k in range(p.palette):
		if not forbidden.has(k):
			pool.append(k)
	if pool.size() == 0:
		# Generator-retry signal: return -1 so _generate_pieces
		# surfaces an obvious mark, and the diagnosis step rejects.
		return -1
	var pick: int = int(pool[int(rng.rand_int(pool.size()))])
	return pick

## Generate the blockers list. CLEAR_LAYERS levels get frosting
## cells; other mechanics get a few decorative frosting cells (0..1)
## so the board is not always empty. No blockers for COLLECT_KIND
## unless the difficulty is HARD.
static func _generate_blockers(p: InputProfile, rng) -> Array:
	var blockers: Array = []
	var frosting_count: int = 0
	match p.mechanic:
		Mechanic.CLEAR_LAYERS:
			# 4..8 frosting cells, 1..2 layers each.
			frosting_count = 4 + int(rng.rand_int(5))
		Mechanic.RELEASE_TOKEN:
			# A couple of decorative frosting cells so the board
			# does not look bare.
			frosting_count = int(rng.rand_int(3))
		_:
			# COLLECT_KIND / REACH_SCORE: zero or a couple depending
			# on difficulty.
			if p.difficulty == Difficulty.HARD:
				frosting_count = int(rng.rand_int(3))
	if frosting_count == 0:
		return blockers
	var used: Dictionary = {}
	for i in range(frosting_count):
		var x: int = int(rng.rand_int(p.board_w))
		var y: int = int(rng.rand_int(p.board_h))
		var key: String = "%d,%d" % [x, y]
		if used.has(key):
			continue
		used[key] = true
		blockers.append({
			"x": x,
			"y": y,
			"type": "FROSTING",
			"layers": 1 + int(rng.rand_int(2)),
		})
	return blockers

## Generate the tokens list. RELEASE_TOKEN levels get exactly one
## token; other mechanics get zero.
static func _generate_tokens(p: InputProfile, rng) -> Array:
	if p.mechanic != Mechanic.RELEASE_TOKEN:
		return []
	var x: int = int(rng.rand_int(p.board_w))
	var y: int = int(rng.rand_int(p.board_h))
	# -1 = "any kind" so the player can use any colour to release.
	return [{
		"x": x,
		"y": y,
		"id": 0,
		"matching_kind": -1,
	}]

## Generate the objectives list. Always returns exactly one entry;
## the schema requires at least one. COLLECT_KIND needs a real
## `target_total` (computed by the caller via _target_total_for)
## because the schema validator rejects 0. CLEAR_LAYERS receives
## its `target_layers` from the caller (the sum of frosting layers
## placed on the board) so the objective is always achievable.
static func _generate_objectives(p: InputProfile, _rng,
		collect_kind_total: int = 1,
		clear_layers_total: int = 0,
		collect_target_kind: int = 0) -> Array:
	var target_kind: int = collect_target_kind
	var target_score: int = 0
	match p.mechanic:
		Mechanic.COLLECT_KIND:
			pass  # target_kind already set from caller.
		Mechanic.REACH_SCORE:
			# Reach score ~ 60% of a full-board clear at 10 pts /
			# piece. Round to the nearest 50.
			target_score = _round50(_score_target_for(p))
	if p.mechanic == Mechanic.COLLECT_KIND:
		return [{
			"kind": Session.ObjectiveKind.COLLECT_KIND,
			"target_kind": target_kind,
			"target_total": collect_kind_total,
		}]
	if p.mechanic == Mechanic.REACH_SCORE:
		return [{
			"kind": Session.ObjectiveKind.REACH_SCORE,
			"target_score": target_score,
		}]
	if p.mechanic == Mechanic.CLEAR_LAYERS:
		return [{
			"kind": Session.ObjectiveKind.CLEAR_LAYERS,
			"target_layers": max(1, clear_layers_total),
		}]
	return [{
		"kind": Session.ObjectiveKind.RELEASE_TOKEN,
		"target_total": 1,
	}]

## COLLECT_KIND target_total. Roughly 30% / 50% / 70% of board
## cells for EASY / MEDIUM / HARD.
static func _target_total_for(p: InputProfile, _rng) -> int:
	var frac: float = 0.30
	match p.difficulty:
		Difficulty.EASY: frac = 0.30
		Difficulty.MEDIUM: frac = 0.50
		Difficulty.HARD: frac = 0.70
	var cells: int = p.board_w * p.board_h
	var t: int = int(round(float(cells) * frac))
	return max(1, min(t, cells))

## Clamp a COLLECT_KIND target_total to the expected share of cells
## a single kind gets on the board. With palette=K, each kind
## averages cells/K; on a small palette the variance is small so
## this is safe. The diagnosis step still verifies the chosen kind
## actually has at least that many cells on the generated grid.
static func _clamp_target_to_kind_share(p: InputProfile,
		_kind: int) -> int:
	var cells: int = p.board_w * p.board_h
	var avg_share: int = int(round(float(cells) / float(p.palette)))
	var target: int = _target_total_for(p, null)
	return max(1, min(target, avg_share))

## Move budget per difficulty. EASY: 25, MEDIUM: 20, HARD: 18.
static func _moves_for(p: InputProfile, _rng) -> int:
	match p.difficulty:
		Difficulty.EASY: return 25
		Difficulty.MEDIUM: return 20
		Difficulty.HARD: return 18
	return 25

## Star thresholds: 1-star = 30% of moves, 2-star = 60%, 3-star =
## 100%. Documented so the manifest records the contract.
static func _star_thresholds_for(_p: InputProfile, moves: int) -> Array:
	var s1: int = int(round(float(moves) * 0.30))
	var s2: int = int(round(float(moves) * 0.60))
	var s3: int = moves
	return [s1, s2, s3]

## REACH_SCORE target (raw, before rounding). 60% of full-clear
## points at 10 points/piece removal.
static func _score_target_for(p: InputProfile) -> int:
	var cells: int = p.board_w * p.board_h
	return int(round(float(cells) * 10 * 0.60))

## Sum the `layers` field across a blockers list. Used so the
## CLEAR_LAYERS objective's target equals the frosting the
## generator actually placed.
static func _sum_frosting_layers(blockers: Array) -> int:
	var s: int = 0
	for b in blockers:
		s += int(b.get("layers", 0))
	return s

## Round a number to the nearest multiple of 50.
static func _round50(v: int) -> int:
	return int(round(float(v) / 50.0)) * 50

## Hex encode (8 chars, lowercase). Used for stable recipe ids.
static func _hex(v: int) -> String:
	var s: String = ""
	var mask: int = 0xFFFFFFFF
	var n: int = v & mask
	for i in range(8):
		var d: int = n & 0xF
		var ch: String
		if d < 10:
			ch = str(d)
		else:
			ch = String.chr(97 + d - 10)
		s = ch + s
		n = n >> 4
	return s

## Diagnose a candidate recipe. Returns an empty errors array on
## success; the list of reasons the generator should retry
## otherwise. The checks mirror the LevelRecipe.validate rules so
## the generator's output is always schema-clean.
static func _diagnose_recipe(p: InputProfile, recipe: Dictionary) -> Array:
	var errors: Array = []
	# Schema-level: defer to LevelRecipe.validate.
	var vr: LevelRecipe.ValidationResult = LevelRecipe.validate(recipe)
	if not vr.ok:
		errors.append_array(vr.errors)
		return errors
	# Piece grid sanity: every cell has a valid kind.
	for row in recipe.get("_generated_pieces", []):
		for k in row:
			if k < 0:
				errors.append("piece grid has -1 (generator-retry signal)")
				return errors
	# Build the board and check "no accidental matches" + "at
	# least one legal opening move" against the rules engine.
	var board: Board = _build_board(p, recipe)
	var runs: Array = Rules.find_runs(board)
	if runs.size() > 0:
		errors.append("starting board has %d accidental runs" % runs.size())
		return errors
	var legal: Array = Rules.enumerate_legal_swaps(board)
	if legal.size() == 0:
		errors.append("starting board has no legal opening moves")
		return errors
	# Objective feasibility: COLLECT_KIND target_total must be
	# achievable (no more than the cells of that kind on the
	# board). The level starts full; the player can match the
	# whole board in cascades so the target is achievable if it is
	# <= the count of that kind.
	if p.mechanic == Mechanic.COLLECT_KIND:
		var t_kind: int = int(recipe.get("target_kind", 0))
		var t_total: int = int(recipe.get("target_total", 0))
		var count: int = _count_kind_in_grid(p, recipe, t_kind)
		if t_total > count:
			errors.append("target_total %d exceeds kind %d count %d" % [
					t_total, t_kind, count])
	# CLEAR_LAYERS target must be <= sum of frosting layers.
	if p.mechanic == Mechanic.CLEAR_LAYERS:
		var t_layers: int = 0
		for o in recipe.get("objectives", []):
			var od: Dictionary = o
			t_layers = int(od.get("target_layers", 0))
		var sum_layers: int = 0
		for b in recipe.get("blockers", []):
			var bd: Dictionary = b
			sum_layers += int(bd.get("layers", 0))
		if t_layers > sum_layers:
			errors.append("target_layers %d exceeds frosting sum %d" % [
					t_layers, sum_layers])
	# RELEASE_TOKEN target must be 1 and exactly one token.
	if p.mechanic == Mechanic.RELEASE_TOKEN:
		if int(recipe.get("tokens", []).size()) != 1:
			errors.append("RELEASE_TOKEN requires exactly 1 token")
	return errors

## Build a Board from the recipe's pieces + blockers. The recipe
## stores pieces in `_generated_pieces` (added by the generator);
## blockers are passed through BoardConfig so they land in the
## FROSTING cells with their layers. Curated recipes do not carry
## `_generated_pieces` and are out of scope for this diagnosis.
static func _build_board(p: InputProfile, recipe: Dictionary) -> Board:
	var blocked: Array = []
	var blockers: Array = recipe.get("blockers", [])
	var cfg := Board.BoardConfig.new(p.board_w, p.board_h, p.palette,
			blocked, blockers)
	var board: Board = Board.new(cfg)
	var pieces: Array = recipe.get("_generated_pieces", [])
	for y in range(p.board_h):
		for x in range(p.board_w):
			var k: int = int(pieces[y][x])
			board.set_piece(Coord.new(x, y), Board.Piece.new(k))
	return board

## Count how many cells of `kind` are in the generated piece grid.
static func _count_kind_in_grid(_p: InputProfile, recipe: Dictionary,
		kind: int) -> int:
	var pieces: Array = recipe.get("_generated_pieces", [])
	var c: int = 0
	for row in pieces:
		for k in row:
			if int(k) == kind:
				c += 1
	return c

## Build the manifest for a successful generation. The manifest is
## the audit trail: input parameters, generator version, schema
## version, seed, and a normalised signature hash so a batch tool
## can deduplicate.
static func _build_manifest(p: InputProfile, seed: int,
		recipe: Dictionary) -> Dictionary:
	var sig_input: Dictionary = recipe.duplicate(true)
	# Strip volatile fields so the signature is stable across
	# regenerations of identical inputs.
	sig_input.erase("recipe_id")
	sig_input.erase("generator_version")
	sig_input.erase("curated")
	sig_input.erase("_generated_pieces")
	var sig_text: String = JSON.stringify(sig_input, "", true, false)
	var sig_hash: int = _fnv1a(sig_text)
	return {
		"generator_version": GENERATOR_VERSION,
		"target_schema_version": TARGET_SCHEMA_VERSION,
		"seed": seed,
		"profile": p.to_dict(),
		"recipe_id": recipe.get("recipe_id", ""),
		"signature_hash": sig_hash,
	}

## 32-bit FNV-1a over a string.
static func _fnv1a(text: String) -> int:
	var h: int = 0x811C9DC5
	for i in range(text.length()):
		h = h ^ text.unicode_at(i)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h

## Build the recipe with the piece grid attached. Public so the
## batch tool can write the generated pieces into the recipe
## dictionary before persisting.
static func attach_pieces(recipe: Dictionary, pieces: Array) -> Dictionary:
	var out: Dictionary = recipe.duplicate(true)
	out["_generated_pieces"] = pieces
	return out

## Detect the -1 generator-retry signal in a generated piece grid.
static func _has_retry_signal(pieces: Array) -> bool:
	for row in pieces:
		for k in row:
			if int(k) < 0:
				return true
	return false