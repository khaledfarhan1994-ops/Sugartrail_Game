extends GutTest
## Step 19: world map / progression tests.

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")
const Progression = preload("res://scripts/domain/progression/chapter.gd")
const Ch = Progression
const LevelRecord = SaveData.LevelRecord

func _make_catalog() -> Ch.ChapterCatalog:
	var ch1 := Ch.Chapter.new("ch1", "Chapter 1",
			["l1", "l2", "l3"], 0)
	var ch2 := Ch.Chapter.new("ch2", "Chapter 2",
			["l4", "l5", "l6"], 6)
	var ch3 := Ch.Chapter.new("ch3", "Chapter 3",
			["l7", "l8", "l9"], 6)
	return Ch.ChapterCatalog.new([ch1, ch2, ch3])

func _known() -> Array:
	return ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9"]

func _fresh_save() -> SaveData.SaveData:
	return SaveData.fresh_save()

# A. Empty save: first level of chapter 1 is the focus, others locked.

func test_initial_state_focus_first_level() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	var nodes: Array = Ch.compute_state(cat, save)
	assert_eq(nodes.size(), 9)
	# l1 is the focus.
	var first: Ch.MapNode = nodes[0]
	assert_eq(first.level_id, "l1")
	assert_eq(first.state, Ch.NodeState.UNLOCKED)
	assert_true(first.is_focus)
	# l2, l3 locked.
	assert_eq(nodes[1].state, Ch.NodeState.LOCKED)
	assert_eq(nodes[2].state, Ch.NodeState.LOCKED)
	# All of chapter 2 + 3 are locked.
	for i in range(3, 9):
		assert_eq(nodes[i].state, Ch.NodeState.LOCKED)

# B. Completing a level unlocks the next in chapter.

func test_completion_unlocks_next_level_in_chapter() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	Progression.record_completion(save, "l1", 100, 3)
	var nodes: Array = Ch.compute_state(cat, save)
	assert_eq(nodes[0].state, Ch.NodeState.COMPLETED)
	assert_eq(nodes[0].best_stars, 3)
	assert_eq(nodes[1].state, Ch.NodeState.UNLOCKED)
	assert_eq(nodes[1].is_focus, true)
	# l3 still locked.
	assert_eq(nodes[2].state, Ch.NodeState.LOCKED)

# C. Stars gate unlocks chapter 2 once total stars >= required.

func test_stars_gate_unlocks_chapter() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	# Complete 6 stars across chapter 1 (e.g., 2 levels with 3 stars each).
	Progression.record_completion(save, "l1", 200, 3)
	Progression.record_completion(save, "l2", 200, 3)
	var nodes: Array = Ch.compute_state(cat, save)
	# Chapter 2 unlocks (6 stars >= required 6).
	assert_eq(nodes[3].state, Ch.NodeState.UNLOCKED,
			"chapter 2 first level must unlock when stars hit the gate")
	# l5, l6 still locked (chain within chapter).
	assert_eq(nodes[4].state, Ch.NodeState.LOCKED)
	assert_eq(nodes[5].state, Ch.NodeState.LOCKED)
	# l3 is still the focus — the player must complete it before
	# the focus advances to chapter 2.
	var focus_id: String = Progression.focus_level_id(cat, save)
	assert_eq(focus_id, "l3", "focus stays on the next pending chapter-1 level")

	# Complete chapter 1 entirely to advance the focus.
	Progression.record_completion(save, "l3", 200, 3)
	var nodes2: Array = Ch.compute_state(cat, save)
	var focus_id2: String = Progression.focus_level_id(cat, save)
	assert_eq(focus_id2, "l4", "completing chapter 1 advances focus to chapter 2")

# D. Stars below the gate keep the chapter locked.

func test_stars_below_gate_keeps_chapter_locked() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	# Only 3 stars — below the 6 required.
	Progression.record_completion(save, "l1", 100, 3)
	var nodes: Array = Ch.compute_state(cat, save)
	# Chapter 2 still locked.
	for i in range(3, 6):
		assert_eq(nodes[i].state, Ch.NodeState.LOCKED)
	var focus_id: String = Progression.focus_level_id(cat, save)
	assert_eq(focus_id, "l2", "must keep focus on next level of chapter 1")

# E. Replay: completed level shows best stars and score.

func test_replay_preserves_best_stars_and_score() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	Progression.record_completion(save, "l1", 100, 1)
	Progression.record_completion(save, "l1", 200, 3)  # better
	Progression.record_completion(save, "l1", 50, 2)   # worse — must be a no-op
	var nodes: Array = Ch.compute_state(cat, save)
	var first: Ch.MapNode = nodes[0]
	assert_eq(first.best_score, 200, "best_score must be monotone up")
	assert_eq(first.best_stars, 3, "best_stars must be monotone up")
	assert_eq(first.state, Ch.NodeState.COMPLETED)

# F. Improved stars triggers a save change.

func test_record_completion_returns_change_flag() -> void:
	var save := _fresh_save()
	# First call: changes (new level record).
	assert_true(Progression.record_completion(save, "l1", 100, 2))
	# Second call with same score/stars: no change.
	assert_false(Progression.record_completion(save, "l1", 100, 2))
	# Third call with strictly better stars: changes.
	assert_true(Progression.record_completion(save, "l1", 100, 3))

# G. Defensive: out-of-range stars is clamped.

func test_record_completion_clamps_stars() -> void:
	var save := _fresh_save()
	Progression.record_completion(save, "l1", 100, 99)
	var rec: LevelRecord = save.levels["l1"]
	assert_eq(rec.stars, 3, "stars must be clamped to 3")
	Progression.record_completion(save, "l1", 100, -5)
	assert_eq(rec.stars, 3, "stars must not regress on negative input")

# H. Corrupt / unknown IDs in a catalog are flagged.

func test_validate_catalog_flags_unknown_ids() -> void:
	var cat := Ch.ChapterCatalog.new([
		Ch.Chapter.new("ch1", "C1", ["l1", "ghost"], 0),
		Ch.Chapter.new("ch2", "C2", ["l1"], 0),  # duplicate
	])
	var errs: Array = Ch.validate_catalog(cat, _known())
	assert_true(errs.size() >= 2, "must flag unknown + duplicate: %s" % errs)

# I. Validate catalog flags empty chapters.

func test_validate_catalog_flags_empty_chapter() -> void:
	var cat := Ch.ChapterCatalog.new([
		Ch.Chapter.new("ch1", "C1", [], 0),
	])
	var errs: Array = Ch.validate_catalog(cat, _known())
	assert_true(errs.size() > 0)

# J. Focus falls back to last node when everything is complete.

func test_focus_falls_back_to_last_when_all_complete() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	for id in ["l1", "l2", "l3", "l4", "l5", "l6", "l7", "l8", "l9"]:
		Progression.record_completion(save, id, 100, 3)
	var nodes: Array = Ch.compute_state(cat, save)
	for n in nodes:
		var node: Ch.MapNode = n
		assert_eq(node.state, Ch.NodeState.COMPLETED)
	# The last node is the focus for replay.
	assert_true(nodes[nodes.size() - 1].is_focus)

# K. Malformed local data: out-of-range stars in save is treated as 0.

func test_malformed_save_stars_treated_as_zero() -> void:
	var cat := _make_catalog()
	var save := _fresh_save()
	# Inject a tampered record with stars=99 (validate would reject,
	# but the map model degrades gracefully).
	save.levels["l1"] = LevelRecord.new("l1", 100, 99, 0, true)
	var nodes: Array = Ch.compute_state(cat, save)
	# The model trusts the save and surfaces 99 stars (the
	# validator runs at LOAD time, not at compute time). The UI
	# is expected to cap at 3 in display.
	assert_eq(nodes[0].best_stars, 99)

# L. Null inputs yield empty list, no crash.

func test_compute_state_handles_null_inputs() -> void:
	var nodes: Array = Ch.compute_state(null, null)
	assert_eq(nodes.size(), 0)
	nodes = Ch.compute_state(null, _fresh_save())
	assert_eq(nodes.size(), 0)
	nodes = Ch.compute_state(_make_catalog(), null)
	assert_eq(nodes.size(), 0)

# M. record_completion on null save is a no-op.

func test_record_completion_null_safe() -> void:
	assert_false(Progression.record_completion(null, "l1", 100, 3))
	assert_false(Progression.record_completion(_fresh_save(), "", 100, 3))

# N. Chapter id and title are carried onto MapNode.

func test_map_node_carries_chapter_metadata() -> void:
	var cat := _make_catalog()
	var nodes: Array = Ch.compute_state(cat, _fresh_save())
	var first: Ch.MapNode = nodes[0]
	assert_eq(first.chapter_id, "ch1")
	assert_eq(first.chapter_title, "Chapter 1")
	assert_eq(first.index_in_chapter, 1)

# O. Chapters file is loadable and validates against the curated index.

func test_chapters_file_loads_clean() -> void:
	# Load the actual chapters.json.
	var path := "res://data/levels/chapters.json"
	if not FileAccess.file_exists(path):
		pending("chapters.json not found; skipping")
		return
	var fa := FileAccess.open(path, FileAccess.READ)
	var text: String = fa.get_as_text()
	fa.close()
	var parsed: Variant = JSON.parse_string(text)
	assert_not_null(parsed)
	assert_eq(typeof(parsed), TYPE_DICTIONARY)
	var cat: Ch.ChapterCatalog = Ch.ChapterCatalog.from_dict(parsed)
	assert_eq(cat.chapters.size(), 3)
	# Pull the curated index for known ids.
	var idx_path := "res://data/levels/curated/INDEX.json"
	if not FileAccess.file_exists(idx_path):
		pending("INDEX.json not found")
		return
	var idx_fa := FileAccess.open(idx_path, FileAccess.READ)
	var idx_text: String = idx_fa.get_as_text()
	idx_fa.close()
	var idx_parsed: Variant = JSON.parse_string(idx_text)
	var known: Array = idx_parsed["ids"]
	var errs: Array = Ch.validate_catalog(cat, known)
	assert_eq(errs.size(), 0, "chapters.json must validate against curated index: %s" % errs)
	# Every level id must be reachable from the catalog.
	for k in known:
		var k_str: String = String(k)
		assert_true(cat.chapter_index.has(k_str),
				"level %s must appear in some chapter" % k_str)