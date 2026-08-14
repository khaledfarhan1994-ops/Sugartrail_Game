class_name SugartrailLevelRecipe
extends RefCounted
## First version of LevelRecipe and strict schema validation.
##
## Step 11 turns the recipe-shaped dictionary that Session.from_recipe
## already accepted into a real, validated class. Every curated level
## in `data/levels/curated/` is loaded through this class; malformed
## recipes raise an error before any session is constructed.
##
## The schema is intentionally narrow for Step 11. Step 22 will
## re-version it once blockers (Step 15) and the remaining objectives
## (Step 16) are in. Today's recipe supports what the first ten
## levels need:
##
##   - 6x8 board (Step 09 default; any 1..8 by 1..12 is accepted)
##   - normal piece palette 1..8
##   - one COLLECT_KIND objective
##   - one move budget
##   - 1/2/3 star thresholds
##   - one or more tutorial prompts keyed by localization id
##
## Schema rules enforced at validate():
##
##   recipe_id  : non-empty String
##   version    : int == 3 (Step 16 bump)
##   chapter    : int >= 0
##   index_in_chapter : int >= 0
##   board_w    : int 1..8
##   board_h    : int 1..12
##   palette    : int 1..8
##   seed       : int (any value; seed reproducibility is the
##                contract, not the value)
##   moves      : int 1..200
##   objectives : Array of objective entries (Step 16, optional).
##                Each entry has the shape
##                  {"kind": int (ObjectiveKind), "target_total": int,
##                   "target_kind": int?, "target_score": int?,
##                   "target_layers": int?, "token_id": int?}
##                At least one objective is required; legacy
##                single-objective recipes (target_kind +
##                target_total) auto-migrate to a single
##                COLLECT_KIND objective.
##   star_one   : int >= 0
##   star_two   : int >= star_one
##   star_three : int >= star_two
##   tutorial   : Array of Strings (localization keys), length 0..8
##   intro_text : String (localization key), may be empty
##   avoid_initial_matches : bool, defaults true
##   blockers   : Array of blocker entries (optional, Step 15). Each
##                entry has the shape
##                  {"x": int, "y": int, "type": "FROSTING"|"LOCKED",
##                   "layers": int >= 1}
##                FROSTING uses layers 1..4; LOCKED uses layers 1
##                (informational). All entries must be in-bounds
##                and not overlap a BLOCKED cell.
##   tokens     : Array of token entries (Step 16, optional). Each
##                entry has the shape
##                  {"x": int, "y": int, "id": int (>= 0),
##                   "matching_kind": int (-1 = any, else 0..palette-1)}
##                Tokens must be in-bounds and not overlap a BLOCKED
##                or FROSTING cell.

## Recipe schema version. Increment when validation rules change
## incompatibly. Old recipes must be migrated before they are loaded.
const SCHEMA_VERSION: int = 3

## Result of validate(). ok == true means the recipe is loadable.
class ValidationResult:
	var ok: bool = false
	var errors: Array = []
	var warnings: Array = []

	func _init(p_ok: bool = false, p_errors: Array = [],
			p_warnings: Array = []) -> void:
		ok = p_ok
		errors = p_errors
		warnings = p_warnings

	func to_dict() -> Dictionary:
		return {
			"ok": ok,
			"errors": errors.duplicate(),
			"warnings": warnings.duplicate(),
		}

## Validate a raw recipe Dictionary. Returns a ValidationResult.
## Never mutates the input. Pushes no error to the engine log —
## callers decide how to surface failures.
static func validate(raw: Dictionary) -> ValidationResult:
	var errors: Array = []
	var warnings: Array = []

	# Required string fields.
	for key in ["recipe_id", "version", "chapter", "index_in_chapter",
			"board_w", "board_h", "palette", "seed", "moves",
			"target_kind", "target_total", "star_one", "star_two",
			"star_three", "tutorial", "intro_text"]:
		if not raw.has(key):
			errors.append("missing required field: %s" % key)

	if errors.size() > 0:
		return ValidationResult.new(false, errors, warnings)

	# recipe_id: non-empty string.
	var recipe_id_v: Variant = raw["recipe_id"]
	if not (recipe_id_v is String) or (recipe_id_v as String).strip_edges() == "":
		errors.append("recipe_id must be a non-empty string")

	# version: int == SCHEMA_VERSION.
	var version_v: int = int(raw["version"])
	if version_v != SCHEMA_VERSION:
		errors.append("version %d does not match SCHEMA_VERSION %d" % [
			version_v, SCHEMA_VERSION])

	# chapter / index_in_chapter: non-negative ints.
	var chapter_v: int = int(raw["chapter"])
	if chapter_v < 0:
		errors.append("chapter must be >= 0 (got %d)" % chapter_v)
	var idx_v: int = int(raw["index_in_chapter"])
	if idx_v < 0:
		errors.append("index_in_chapter must be >= 0 (got %d)" % idx_v)

	# board_w / board_h: 1..8 / 1..12.
	var w: int = int(raw["board_w"])
	if w < 1 or w > 8:
		errors.append("board_w %d out of range 1..8" % w)
	var h: int = int(raw["board_h"])
	if h < 1 or h > 12:
		errors.append("board_h %d out of range 1..12" % h)

	# palette: 1..8.
	var palette: int = int(raw["palette"])
	if palette < 1 or palette > 8:
		errors.append("palette %d out of range 1..8" % palette)

	# moves: 1..200.
	var moves: int = int(raw["moves"])
	if moves < 1 or moves > 200:
		errors.append("moves %d out of range 1..200" % moves)

	# target_kind: 0..(palette-1).
	var target_kind: int = int(raw["target_kind"])
	if target_kind < 0 or target_kind >= palette:
		errors.append("target_kind %d not in palette [0..%d]" % [
			target_kind, palette - 1])

	# target_total: 1..(w*h).
	var target_total: int = int(raw["target_total"])
	if target_total < 1 or target_total > w * h:
		errors.append("target_total %d out of range 1..%d" % [
			target_total, w * h])

	# Stars: non-decreasing, non-negative.
	var s1: int = int(raw["star_one"])
	var s2: int = int(raw["star_two"])
	var s3: int = int(raw["star_three"])
	if s1 < 0 or s2 < s1 or s3 < s2:
		errors.append("star thresholds must be non-decreasing non-negative (got %d, %d, %d)" % [
			s1, s2, s3])

	# Tutorial: array of non-empty strings, length 0..8.
	var tutorial_v: Variant = raw["tutorial"]
	if not (tutorial_v is Array):
		errors.append("tutorial must be an Array of strings")
	else:
		var tutorial: Array = tutorial_v
		if tutorial.size() > 8:
			errors.append("tutorial has %d entries; max 8" % tutorial.size())
		for entry in tutorial:
			if not (entry is String) or (entry as String).strip_edges() == "":
				errors.append("tutorial entries must be non-empty strings")
				break

	# intro_text: string (may be empty).
	var intro_v: Variant = raw["intro_text"]
	if not (intro_v is String):
		errors.append("intro_text must be a string")

	# Optional avoid_initial_matches: bool with sane default.
	var avoid_v: Variant = raw.get("avoid_initial_matches", true)
	if not (avoid_v is bool):
		errors.append("avoid_initial_matches must be a bool")

	# Soft warnings: extreme move budgets / very high targets.
	if moves < 5:
		warnings.append("moves=%d is very low; tutorial clarity may suffer" % moves)
	if target_total > (w * h) / 2:
		warnings.append("target_total=%d is more than half of board (%d cells)" % [
			target_total, w * h])

	# Step 15: optional blockers array. Validate shape, type, layers,
	# bounds, and uniqueness.
	if raw.has("blockers"):
		var blockers_v: Variant = raw["blockers"]
		if not (blockers_v is Array):
			errors.append("blockers must be an Array")
		else:
			var blockers: Array = blockers_v
			var seen_b := {}
			for entry in blockers:
				if not (entry is Dictionary):
					errors.append("blockers entries must be Dictionaries")
					continue
				var d: Dictionary = entry
				if not d.has("x") or not d.has("y") or not d.has("type"):
					errors.append("blockers entry missing required keys (x,y,type)")
					continue
				var bx: int = int(d.get("x", -1))
				var by: int = int(d.get("y", -1))
				var btype: String = str(d.get("type", ""))
				var blayers: int = int(d.get("layers", 0))
				if bx < 0 or bx >= w or by < 0 or by >= h:
					errors.append("blocker at (%d,%d) out of bounds %dx%d" % [bx, by, w, h])
					continue
				if btype != "FROSTING" and btype != "LOCKED":
					errors.append("blocker at (%d,%d) has invalid type '%s'" % [bx, by, btype])
					continue
				if blayers < 1 or blayers > 4:
					errors.append("blocker at (%d,%d) has layers %d (must be 1..4)" % [bx, by, blayers])
					continue
				var bkey: String = "%d,%d" % [bx, by]
				if seen_b.has(bkey):
					errors.append("duplicate blocker at (%d,%d)" % [bx, by])
					continue
				seen_b[bkey] = true

	# Step 16: optional tokens array. Validate shape, id uniqueness,
	# matching_kind range, and bounds. Tokens cannot overlap BLOCKED
	# or FROSTING cells.
	if raw.has("tokens"):
		var tokens_v: Variant = raw["tokens"]
		if not (tokens_v is Array):
			errors.append("tokens must be an Array")
		else:
			var tokens: Array = tokens_v
			var seen_t := {}
			for entry in tokens:
				if not (entry is Dictionary):
					errors.append("tokens entries must be Dictionaries")
					continue
				var td: Dictionary = entry
				var tx: int = int(td.get("x", -1))
				var ty: int = int(td.get("y", -1))
				var t_id: int = int(td.get("id", -1))
				var mk: int = int(td.get("matching_kind", -1))
				if tx < 0 or tx >= w or ty < 0 or ty >= h:
					errors.append("token at (%d,%d) out of bounds %dx%d" % [tx, ty, w, h])
					continue
				if t_id < 0:
					errors.append("token at (%d,%d) has invalid id %d" % [tx, ty, t_id])
					continue
				if mk < -1 or mk >= palette:
					errors.append("token at (%d,%d) has matching_kind %d (must be -1 or 0..%d)" % [
						tx, ty, mk, palette - 1])
					continue
				var tkey: String = "%d,%d" % [tx, ty]
				if seen_t.has(tkey):
					errors.append("duplicate token at (%d,%d)" % [tx, ty])
					continue
				seen_t[tkey] = true

	# Step 16: optional objectives array. Validate shape per kind.
	if raw.has("objectives"):
		var objs_v: Variant = raw["objectives"]
		if not (objs_v is Array):
			errors.append("objectives must be an Array")
		else:
			var objs: Array = objs_v
			if objs.size() == 0:
				errors.append("objectives must be non-empty")
			for oentry in objs:
				if not (oentry is Dictionary):
					errors.append("objectives entries must be Dictionaries")
					continue
				var od: Dictionary = oentry
				var okind: int = int(od.get("kind", -1))
				if okind < 0 or okind > 3:
					errors.append("objective has invalid kind %d (must be 0..3)" % okind)
					continue
				match okind:
					0: # COLLECT_KIND
						var tk: int = int(od.get("target_kind", -1))
						if tk < 0 or tk >= palette:
							errors.append("COLLECT_KIND objective has invalid target_kind %d" % tk)
						var tt: int = int(od.get("target_total", 0))
						if tt < 1 or tt > w * h:
							errors.append("COLLECT_KIND target_total %d out of range 1..%d" % [
								tt, w * h])
					1: # REACH_SCORE
						var ts: int = int(od.get("target_score", 0))
						if ts < 1:
							errors.append("REACH_SCORE target_score %d must be >= 1" % ts)
					2: # CLEAR_LAYERS
						var tl: int = int(od.get("target_layers", 0))
						if tl < 1:
							errors.append("CLEAR_LAYERS target_layers %d must be >= 1" % tl)
					3: # RELEASE_TOKEN
						var tti: int = int(od.get("target_total", 0))
						if tti < 1:
							errors.append("RELEASE_TOKEN target_total %d must be >= 1" % tti)

	var ok: bool = errors.size() == 0
	return ValidationResult.new(ok, errors, warnings)

## Load and validate a recipe from a JSON file. Returns null on
## failure (errors already collected into out_errors if non-null).
## Validates before returning; never returns an invalid recipe.
##
## Step 15: older recipes (version < SCHEMA_VERSION) are auto-
## migrated before validation. Migrations are forward-only: each
## version bump appends a new migration helper that the loader
## chains in order.
static func load_from_file(path: String, out_errors: Array = []) -> Dictionary:
	if out_errors == null:
		out_errors = []
	if not FileAccess.file_exists(path):
		out_errors.append("recipe file not found: %s" % path)
		return {}
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		out_errors.append("recipe file unreadable: %s (error %d)" % [
			path, FileAccess.get_open_error()])
		return {}
	var text: String = fa.get_as_text()
	fa.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		out_errors.append("recipe file is not a JSON object: %s" % path)
		return {}
	var recipe: Dictionary = parsed
	# Auto-migrate older versions to the current schema before
	# validation. The migration chain runs forward-only.
	recipe = migration_v1_to_v2(recipe)
	recipe = migration_v2_to_v3(recipe)
	var result: ValidationResult = validate(recipe)
	if not result.ok:
		for e in result.errors:
			out_errors.append("%s: %s" % [path, e])
		return {}
	return recipe

## Normalise a raw recipe dictionary by filling optional defaults.
## Does NOT validate. Callers should always validate first.
static func with_defaults(raw: Dictionary) -> Dictionary:
	var out: Dictionary = raw.duplicate(true)
	if not out.has("avoid_initial_matches"):
		out["avoid_initial_matches"] = true
	if not out.has("blockers"):
		out["blockers"] = []
	return out

## Step 15: migrate a v1 recipe (Step 11 era) to v2 by adding the
## empty blockers array and bumping version. Returns a new dictionary;
## the input is not mutated. Returns the input unchanged if it is
## already at version >= 2.
static func migration_v1_to_v2(raw: Dictionary) -> Dictionary:
	if raw == null:
		return raw
	var version: int = int(raw.get("version", 1))
	if version >= 2:
		return raw
	var out: Dictionary = raw.duplicate(true)
	out["version"] = SCHEMA_VERSION
	if not out.has("blockers"):
		out["blockers"] = []
	return out

## Step 16: migrate a v2 recipe to v3 by deriving an `objectives`
## array from the legacy single `target_kind` + `target_total`
## pair, and bumping version. Adds the empty `tokens` array. The
## input is not mutated. Returns the input unchanged if already
## at version >= 3.
static func migration_v2_to_v3(raw: Dictionary) -> Dictionary:
	if raw == null:
		return raw
	var version: int = int(raw.get("version", 2))
	if version >= 3:
		return raw
	var out: Dictionary = raw.duplicate(true)
	out["version"] = SCHEMA_VERSION
	if not out.has("objectives"):
		var legacy_obj := {
			"kind": 0,
			"target_kind": int(out.get("target_kind", 0)),
			"target_total": int(out.get("target_total", 10)),
			"progress": 0,
		}
		out["objectives"] = [legacy_obj]
	if not out.has("tokens"):
		out["tokens"] = []
	return out