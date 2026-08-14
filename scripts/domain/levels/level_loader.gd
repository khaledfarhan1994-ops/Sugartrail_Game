class_name SugartrailLevelLoader
extends RefCounted
## Loads curated level recipes and constructs a session + tutorial pack.
##
## Step 11 ships ten curated levels under `data/levels/curated/`.
## This module is the boundary between the on-disk JSON and the
## in-memory domain objects: it loads, validates, and constructs
## a SugartrailSession + SugartrailTutorial.TutorialPack pair.
##
## The loader is a thin glue layer. It does not know how to play
## the level — that is the session's job.

const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const Tutorial = preload("res://scripts/domain/tutorial/tutorial.gd")
const Session = preload("res://scripts/domain/session/session.gd")

## Result of loading one level: the validated recipe, the session
## built from it, and the tutorial pack derived from its prompts.
class LoadedLevel:
	var recipe: Dictionary = {}
	var recipe_path: String = ""
	var session: Session.Session = null
	var tutorial: Tutorial.TutorialPack = null

	func _init(p_recipe: Dictionary, p_path: String,
			p_session: Session.Session,
			p_tutorial: Tutorial.TutorialPack) -> void:
		recipe = p_recipe
		recipe_path = p_path
		session = p_session
		tutorial = p_tutorial

## Build a session from a recipe dictionary. The recipe must
## already have been validated.
static func build_session_from_recipe(recipe: Dictionary) -> Session.Session:
	var normalised: Dictionary = LevelRecipe.with_defaults(recipe)
	return Session.from_recipe(normalised)

## Build a tutorial pack from a validated recipe.
static func build_tutorial_from_recipe(recipe: Dictionary) -> Tutorial.TutorialPack:
	return Tutorial.from_recipe(recipe)

## Load one level by recipe ID. Search order:
##   res://data/levels/curated/{recipe_id}.json
## Returns null if the file does not load or does not validate.
## out_errors is populated with any validation messages.
##
## Step 15: v1 recipes (Step 11 era) are auto-migrated to v2 by
## adding the empty `blockers` array and bumping the version. v2
## recipes load directly.
static func load_level(recipe_id: String,
		out_errors: Array = []) -> LoadedLevel:
	if out_errors == null:
		out_errors = []
	var path: String = "res://data/levels/curated/%s.json" % recipe_id
	var recipe: Dictionary = LevelRecipe.load_from_file(path, out_errors)
	if recipe.is_empty():
		return null
	# Migrate older recipes to current schema before validation. The
	# load_from_file already validated against SCHEMA_VERSION, so a
	# v1 file will fail validation — re-validate after migration.
	recipe = LevelRecipe.migration_v1_to_v2(recipe)
	var revalidation: LevelRecipe.ValidationResult = LevelRecipe.validate(recipe)
	if not revalidation.ok:
		for e in revalidation.errors:
			out_errors.append("%s: %s" % [path, e])
		return null
	var session: Session.Session = build_session_from_recipe(recipe)
	var tutorial: Tutorial.TutorialPack = build_tutorial_from_recipe(recipe)
	return LoadedLevel.new(recipe, path, session, tutorial)

## Load every curated level in the directory, in order. Returns an
## Array of LoadedLevel. Recipes that fail validation are skipped
## and logged into out_errors.
static func load_all_curated(out_errors: Array = []) -> Array:
	if out_errors == null:
		out_errors = []
	var out: Array = []
	# We don't have an FS list API in pure domain code, so we read
	# from a manifest file (`res://data/levels/curated/INDEX.json`)
	# listing the curated IDs in their canonical order. The index
	# itself is checked in.
	var index_path: String = "res://data/levels/curated/INDEX.json"
	if not FileAccess.file_exists(index_path):
		out_errors.append("curated manifest not found: %s" % index_path)
		return out
	var fa := FileAccess.open(index_path, FileAccess.READ)
	if fa == null:
		out_errors.append("curated manifest unreadable: %s" % index_path)
		return out
	var text: String = fa.get_as_text()
	fa.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		out_errors.append("curated manifest is not a JSON object: %s" % index_path)
		return out
	var manifest: Dictionary = parsed
	var ids: Array = manifest.get("ids", [])
	if not (ids is Array) or ids.size() == 0:
		out_errors.append("curated manifest has no ids array: %s" % index_path)
		return out
	for entry in ids:
		if not (entry is String):
			out_errors.append("curated manifest entry is not a string: %s" % str(entry))
			continue
		var loaded: LoadedLevel = load_level(entry, out_errors)
		if loaded != null:
			out.append(loaded)
	return out

## Verify a level has at least one legal opening move. Used by
## the curated-level tests to confirm every recipe is immediately
## playable.
static func has_opening_move(session: Session.Session) -> bool:
	if session == null or session.board == null:
		return false
	# Reuse the replay module's deadlock check; importing the rules
	# directly is not necessary.
	var Replay = preload("res://scripts/domain/replay/replay.gd")
	return Replay.has_legal_moves(session.board)