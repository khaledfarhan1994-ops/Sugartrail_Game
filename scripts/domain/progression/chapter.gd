class_name SugartrailProgression
extends RefCounted
## Chapter-based progression: world-map data + lock-state computation.
##
## Step 19 ships the *application* and *domain* side of the world
## map: a ChapterCatalog that knows about chapters and their
## levels, a MapModel that joins that with the player's SaveData
## to compute the current node states (locked / unlocked /
## completed, best stars, best score), and a ProgressionRule set
## that decides which node becomes the "current focus" when the
## app boots or the player finishes a level.
##
## The scene / UI work that paints the map on screen belongs to
## Step 19's presentation layer. That code reads MapModel.state()
## and rebuilds the visible node list when the model emits a
## "changed" signal (rebuilt on save, on level completion, on
## reset).
##
## Important design choices:
##
##   - The chapter catalog is data-only (a JSON file referenced
##     by chapter_catalog_path). The domain code never hardcodes
##     a level list; the loader feeds it. Tests pass a synthetic
##     in-memory catalog.
##
##   - Lock state is derived from the SaveData. It is NOT
##     persisted separately — if the save is corrupt and resets,
##     the map rediscovers its true state from best_stars +
##     completed_once. This means "skip ahead" cheats can never
##     persist past a save reset.
##
##   - The "current focus" is the first UNLOCKED, not-yet-COMPLETED
##     level in the catalog order. If every level is completed,
##     the focus falls back to the LAST level (so replay is
##     available without further input).
##
##   - Chapter gates: a chapter is unlocked when the player has
##     at least `stars_required` total stars from levels in the
##     previous chapter (or always-unlocked for chapter 1).
##     Optional — chapters can also be ordered such that
##     completing the last level of chapter N implicitly unlocks
##     chapter N+1 regardless of stars.

## A single chapter in the world-map catalog.
class Chapter:
	## Stable id (e.g., "ch1-sweet-trail").
	var id: String = ""
	## Human-readable title. Localisation happens in the
	## presentation layer.
	var title: String = ""
	## Ordered list of level recipe ids in this chapter. The order
	## defines the unlock chain within the chapter.
	var level_ids: Array = []
	## Stars required from the PREVIOUS chapter to unlock this one.
	## 0 or negative means "previous chapter's last-level-completion
	## is sufficient". For chapter 1, this is ignored (always open).
	var stars_required: int = 0

	func _init(p_id: String = "", p_title: String = "",
			p_level_ids: Array = [], p_stars_required: int = 0) -> void:
		id = p_id
		title = p_title
		level_ids = []
		for lid in p_level_ids:
			level_ids.append(String(lid))
		stars_required = p_stars_required

	func to_dict() -> Dictionary:
		return {
			"id": id,
			"title": title,
			"level_ids": level_ids.duplicate(),
			"stars_required": stars_required,
		}

	static func from_dict(d: Dictionary) -> Chapter:
		var lv_in: Variant = d.get("level_ids", [])
		var lv: Array = []
		if lv_in is Array:
			for item in (lv_in as Array):
				lv.append(String(item))
		return Chapter.new(
			String(d.get("id", "")),
			String(d.get("title", "")),
			lv,
			int(d.get("stars_required", 0)))

## The catalog of every chapter + the flat list of every level id
## in catalog order. Loaded from chapters.json.
class ChapterCatalog:
	var chapters: Array = []     # Array[Chapter]
	## Convenience: all level ids in catalog order.
	var flat_level_ids: Array = []
	## Convenience: chapter index per level id (1-based).
	var chapter_index: Dictionary = {}

	func _init(p_chapters: Array = []) -> void:
		chapters = []
		for c in p_chapters:
			if c is Chapter:
				chapters.append(c)
		_rebuild_indexes()

	func _rebuild_indexes() -> void:
		flat_level_ids = []
		chapter_index = {}
		var ci: int = 1
		for ch_obj in chapters:
			var ch: Chapter = ch_obj
			for lid in ch.level_ids:
				flat_level_ids.append(String(lid))
				chapter_index[String(lid)] = ci
			ci += 1

	static func from_dict(d: Dictionary) -> ChapterCatalog:
		var ch_in: Variant = d.get("chapters", [])
		var chs: Array = []
		if ch_in is Array:
			for item in (ch_in as Array):
				if item is Dictionary:
					chs.append(Chapter.from_dict(item))
		var cat := ChapterCatalog.new(chs)
		cat._rebuild_indexes()
		return cat

## The lock state of one map node. UI maps these to visuals
## (LOCKED = grey + lock icon, UNLOCKED = bright dot, COMPLETED
## = star count overlay).
enum NodeState {
	## The level cannot be played yet (chapter not unlocked OR
	## earlier-in-chapter level not completed).
	LOCKED = 0,
	## The level can be played but has never been completed.
	UNLOCKED = 1,
	## The level has been completed at least once.
	COMPLETED = 2,
}

## A single level's position on the map. Derived from the catalog
## + SaveData; never persisted on its own.
class MapNode:
	var level_id: String = ""
	var chapter_id: String = ""
	var chapter_title: String = ""
	## 1-based position within the chapter (1 = first level).
	var index_in_chapter: int = 0
	## Computed lock state.
	var state: int = NodeState.LOCKED
	## Highest stars achieved (0..3). 0 for never-completed levels.
	var best_stars: int = 0
	## Highest score achieved. 0 for never-completed levels.
	var best_score: int = 0
	## Whether this is the "current focus" node (the one the
	## app suggests when the player opens the map).
	var is_focus: bool = false

## Compute the map state from a catalog + a save document.
## Returns an Array of MapNode in catalog order. The list is empty
## if either input is null/empty. Never throws.
static func compute_state(catalog: ChapterCatalog, save_data) -> Array:
	if catalog == null or save_data == null:
		return []
	var nodes: Array = []
	# First pass: compute per-level data without lock state.
	var level_data: Array = []
	for ch_idx in range(catalog.chapters.size()):
		var ch: Chapter = catalog.chapters[ch_idx]
		var level_index: int = 1
		for lid in ch.level_ids:
			var id_str: String = String(lid)
			var rec_v: Variant = save_data.levels.get(id_str, null)
			var best_stars: int = 0
			var best_score: int = 0
			var completed: bool = false
			if rec_v != null:
				var rec = rec_v
				best_stars = int(rec.stars)
				best_score = int(rec.best_score)
				completed = bool(rec.completed_once)
			level_data.append({
				"chapter_idx": ch_idx,
				"chapter_id": ch.id,
				"chapter_title": ch.title,
				"level_id": id_str,
				"index_in_chapter": level_index,
				"best_stars": best_stars,
				"best_score": best_score,
				"completed": completed,
			})
			level_index += 1
	# Compute stars per chapter.
	var stars_per_chapter: Dictionary = {}
	for ch_idx in range(catalog.chapters.size()):
		var ch: Chapter = catalog.chapters[ch_idx]
		stars_per_chapter[ch.id] = 0
	for ld in level_data:
		stars_per_chapter[ld["chapter_id"]] = int(
			stars_per_chapter.get(ld["chapter_id"], 0)) + int(ld["best_stars"])
	# Compute chapter-unlocked predicates.
	var chapter_unlocked: Dictionary = {}
	for ch_idx in range(catalog.chapters.size()):
		var ch: Chapter = catalog.chapters[ch_idx]
		chapter_unlocked[ch.id] = _is_chapter_unlocked(
			catalog, ch_idx, stars_per_chapter, level_data)
	# Second pass: compute per-level lock state.
	# A level unlocks when its chapter is unlocked AND either it is
	# the first level in that chapter OR the IMMEDIATELY PRECEDING
	# level (in catalog order) is completed. Tracking "the previous
	# level completed" as a per-chapter boolean is wrong: any
	# completed level in the chapter would falsely unlock every
	# later sibling. Instead we walk level_data in order and let
	# `prev_in_catalog_done` be the completion flag of the previous
	# element of level_data.
	var prev_in_catalog_done: bool = false
	for ld in level_data:
		var node := MapNode.new()
		node.level_id = ld["level_id"]
		node.chapter_id = ld["chapter_id"]
		node.chapter_title = ld["chapter_title"]
		node.index_in_chapter = ld["index_in_chapter"]
		node.best_stars = ld["best_stars"]
		node.best_score = ld["best_score"]
		var unwrapped: bool = bool(chapter_unlocked.get(ld["chapter_id"], false))
		var is_first: bool = (int(ld["index_in_chapter"]) == 1)
		if not unwrapped:
			node.state = NodeState.LOCKED
		elif bool(ld["completed"]):
			node.state = NodeState.COMPLETED
		elif is_first or prev_in_catalog_done:
			node.state = NodeState.UNLOCKED
		else:
			node.state = NodeState.LOCKED
		if bool(ld["completed"]):
			prev_in_catalog_done = true
		else:
			prev_in_catalog_done = false
		nodes.append(node)
	# Focus = first UNLOCKED, not-yet-COMPLETED. If none, last node.
	var focus_index: int = -1
	for i in range(nodes.size()):
		var n: MapNode = nodes[i]
		if n.state == NodeState.UNLOCKED:
			focus_index = i
			break
	if focus_index < 0 and nodes.size() > 0:
		focus_index = nodes.size() - 1
		var last: MapNode = nodes[focus_index]
		if last.state == NodeState.LOCKED:
			var first: MapNode = nodes[0]
			if first.state == NodeState.UNLOCKED:
				focus_index = 0
	if focus_index >= 0:
		var focus: MapNode = nodes[focus_index]
		focus.is_focus = true
	return nodes

## Predicate: is this chapter unlocked, given the running tally
## of stars earned per chapter so far and the per-level completion
## data?
##
## Rules (in order):
##   1. Chapter 1 is always unlocked.
##   2. If stars_required > 0, the previous chapter must yield at
##      least that many stars.
##   3. If stars_required <= 0, the previous chapter's last level
##      must be completed (the per-level chain handles the unlock
##      of the first level; we still return true here so the
##      per-level chain can do its work).
static func _is_chapter_unlocked(catalog: ChapterCatalog, ch_idx: int,
		stars_per_chapter: Dictionary, level_data: Array) -> bool:
	if ch_idx <= 0:
		return true
	var prev: Chapter = catalog.chapters[ch_idx - 1]
	var required: int = catalog.chapters[ch_idx].stars_required
	if required > 0:
		return int(stars_per_chapter.get(prev.id, 0)) >= required
	# No stars gate: chapter is "structurally unlocked" when the
	# previous chapter's last level is completed (computed below).
	# We return true unconditionally; the per-level chain will
	# lock the first level of this chapter until the prev chapter
	# is finished.
	# Walk level_data to find the last level of prev chapter.
	var prev_last_level_id: String = ""
	for ld in level_data:
		if ld["chapter_id"] == prev.id:
			prev_last_level_id = String(ld["level_id"])
	if prev_last_level_id == "":
		return false
	# Check if that level is completed.
	for ld in level_data:
		if String(ld["level_id"]) == prev_last_level_id \
				and bool(ld["completed"]):
			return true
	return false

## Award a level completion. Mutates the SaveData in place. The
## decision to mark completed_once=true is made here so any
## presentation path that wants to record a win uses the same
## logic; in particular, replayability: completed_once stays
## true once set. best_stars / best_score are monotone up.
## Returns true if the SaveData actually changed.
static func record_completion(save_data, level_id: String,
		score: int, stars: int) -> bool:
	if save_data == null or level_id == "":
		return false
	# Clamp stars to 0..3 defensively.
	var safe_stars: int = max(0, min(3, int(stars)))
	var safe_score: int = max(0, int(score))
	var rec_v: Variant = save_data.levels.get(level_id, null)
	if rec_v == null:
		# Build a default LevelRecord so record_completion is the
		# canonical entry point for tracking progression.
		var SaveData = load("res://scripts/domain/persistence/save_data.gd")
		var rec = SaveData.LevelRecord.new(level_id, safe_score,
				safe_stars, 0, true)
		rec.last_played = int(Time.get_unix_time_from_system())
		save_data.levels[level_id] = rec
		return true
	var rec = rec_v
	var changed: bool = false
	if safe_score > int(rec.best_score):
		rec.best_score = safe_score
		changed = true
	if safe_stars > int(rec.stars):
		rec.stars = safe_stars
		changed = true
	if not bool(rec.completed_once):
		rec.completed_once = true
		changed = true
	rec.last_played = int(Time.get_unix_time_from_system())
	return changed

## Validate a catalog. Unknown / duplicated level ids are flagged
## so an unknown / corrupt chapter file does not silently bypass
## progression. Returns Array of error strings; empty = OK.
static func validate_catalog(catalog: ChapterCatalog,
		known_level_ids: Array) -> Array:
	var errs: Array = []
	if catalog == null:
		errs.append("catalog is null")
		return errs
	if catalog.chapters.size() == 0:
		errs.append("catalog has zero chapters")
	var seen_ids: Dictionary = {}
	for ch_idx in range(catalog.chapters.size()):
		var ch: Chapter = catalog.chapters[ch_idx]
		if ch.id == "":
			errs.append("chapter %d has empty id" % ch_idx)
		if ch.level_ids.size() == 0:
			errs.append("chapter %s has zero levels" % ch.id)
		for lid in ch.level_ids:
			var id_str: String = String(lid)
			if id_str == "":
				errs.append("chapter %s has empty level_id" % ch.id)
			if seen_ids.has(id_str):
				errs.append("level %s appears in multiple chapters" % id_str)
			seen_ids[id_str] = true
			var found: bool = false
			for k in known_level_ids:
				if String(k) == id_str:
					found = true
					break
			if not found:
				errs.append("chapter %s level %s not in known levels" % [ch.id, id_str])
	return errs

## Given a save data, find the focus node id. Convenience for the
## presentation layer that just wants the "what should I show
## first" answer.
static func focus_level_id(catalog: ChapterCatalog, save_data) -> String:
	var nodes: Array = compute_state(catalog, save_data)
	for n in nodes:
		var node: MapNode = n
		if node.is_focus:
			return node.level_id
	return ""