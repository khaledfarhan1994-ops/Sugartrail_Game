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
##   version    : int == 1
##   chapter    : int >= 0
##   index_in_chapter : int >= 0
##   board_w    : int 1..8
##   board_h    : int 1..12
##   palette    : int 1..8
##   seed       : int (any value; seed reproducibility is the
##                contract, not the value)
##   moves      : int 1..200
##   target_kind : int 0..(palette-1)
##   target_total : int 1..(board_w * board_h)
##   star_one   : int >= 0
##   star_two   : int >= star_one
##   star_three : int >= star_two
##   tutorial   : Array of Strings (localization keys), length 0..8
##   intro_text : String (localization key), may be empty
##   avoid_initial_matches : bool, defaults true

## Recipe schema version. Increment when validation rules change
## incompatibly. Old recipes must be migrated before they are loaded.
const SCHEMA_VERSION: int = 1

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

	var ok: bool = errors.size() == 0
	return ValidationResult.new(ok, errors, warnings)

## Load and validate a recipe from a JSON file. Returns null on
## failure (errors already collected into out_errors if non-null).
## Validates before returning; never returns an invalid recipe.
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
	return out