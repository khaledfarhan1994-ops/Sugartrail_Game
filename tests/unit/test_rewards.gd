extends GutTest
## Step 20: booster economy + reward ledger tests.

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")
const Booster = preload("res://scripts/domain/boosters/boosters.gd")
const Rewards = preload("res://scripts/domain/rewards/rewards.gd")
const Progression = preload("res://scripts/domain/progression/chapter.gd")

const R = Rewards
const Ch = Progression

func _fresh_save() -> SaveData.SaveData:
	return SaveData.fresh_save()

func _default_source() -> R.RewardSource:
	return R.default_source()

func _make_chapters() -> Progression.ChapterCatalog:
	var ch1 = Ch.Chapter.new("ch1-sweet-trail", "C1",
			["l1", "l2"], 0)
	var ch2 = Ch.Chapter.new("ch2-cascade-master", "C2",
			["l3"], 6)
	return Progression.ChapterCatalog.new([ch1, ch2])

# A. RewardSpec roundtrip + keys stable.

func test_reward_spec_roundtrip_preserves_fields() -> void:
	var spec := R.RewardSpec.new("k1", R.TriggerKind.STARS_TOTAL,
			"", 5,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 2}],
			"label")
	var d: Dictionary = spec.to_dict()
	var back: R.RewardSpec = R.RewardSpec.from_dict(d)
	assert_eq(back.key, "k1")
	assert_eq(back.trigger, R.TriggerKind.STARS_TOTAL)
	assert_eq(back.threshold, 5)
	assert_eq(back.items.size(), 1)
	assert_eq(int(back.items[0].kind_id), Booster.BoosterKind.SWAP_RETRY)
	assert_eq(int(back.items[0].count), 2)
	assert_eq(back.label, "label")

# B. Default source contains the documented rewards.

func test_default_source_has_five_star_thresholds_and_chapters() -> void:
	var src: R.RewardSource = _default_source()
	assert_true(src.has("stars_total:5"))
	assert_true(src.has("stars_total:15"))
	assert_true(src.has("stars_total:30"))
	assert_true(src.has("stars_total:60"))
	assert_true(src.has("stars_total:100"))
	assert_true(src.has("chapter_complete:ch1-sweet-trail"))
	assert_true(src.has("chapter_complete:ch2-cascade-master"))
	assert_true(src.has("chapter_complete:ch3-blocked-confection"))
	assert_true(src.has("tutorial_completed:tutorial.prompt.swap"))

# C. STARS_TOTAL trigger fires once when crossing threshold.

func test_stars_threshold_fires_once() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	# Add 4 stars worth of level records — below the first threshold.
	Progression.record_completion(save, "l1", 100, 2)
	Progression.record_completion(save, "l2", 100, 2)
	var r1: R.RewardResult = R.grant_rewards(save, src, null)
	assert_eq(r1.granted.size(), 0)
	# Cross the 5-star threshold.
	Progression.record_completion(save, "l3", 100, 2)
	var r2: R.RewardResult = R.grant_rewards(save, src, null)
	assert_eq(r2.granted.size(), 1)
	assert_eq(r2.granted[0].key, "stars_total:5")
	# Re-call: already claimed, no new grants.
	var r3: R.RewardResult = R.grant_rewards(save, src, null)
	assert_eq(r3.granted.size(), 0)

# D. Inventory delta matches the spec items.

func test_inventory_increments_by_granted_amount() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	var r: R.RewardResult = R.grant_rewards(save, src, null)
	assert_eq(r.granted.size(), 1)
	assert_eq(r.granted_items.size(), 1)
	assert_eq(int(r.granted_items[0][0].count), 1)
	assert_eq(int(save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY]), 1)

# E. Inventory cap clamps the grant but keeps the ledger.

func test_inventory_cap_clamps_but_claims_ledger() -> void:
	var save := _fresh_save()
	# Pre-fill to the per-kind cap.
	save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY] = 99
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	var r: R.RewardResult = R.grant_rewards(save, src_default_safe(), null)
	# The reward is recorded in the ledger so a re-open cannot reclaim.
	assert_true(save.claimed_rewards.has("stars_total:5"))
	# But the actual inventory did not increase (cap saturated).
	assert_eq(int(save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY]), 99)
	assert_true(r.any_clamped)

func src_default_safe() -> R.RewardSource:
	return R.default_source()

# F. CHAPTER_COMPLETE fires only when the last level is completed.

func test_chapter_complete_fires_when_last_level_completed() -> void:
	var save := _fresh_save()
	var cat := _make_chapters()
	var src: R.RewardSource = _default_source()
	# Complete l1 only (first level of ch1).
	Progression.record_completion(save, "l1", 100, 3)
	var r1: R.RewardResult = R.grant_rewards(save, src, cat)
	assert_false(save.claimed_rewards.has("chapter_complete:ch1-sweet-trail"))
	# Complete l2 (last level of ch1) — chapter fires.
	Progression.record_completion(save, "l2", 100, 3)
	var r2: R.RewardResult = R.grant_rewards(save, src, cat)
	assert_true(save.claimed_rewards.has("chapter_complete:ch1-sweet-trail"))
	assert_eq(r2.chapter_completed, "ch1-sweet-trail")

# G. TUTORIAL_COMPLETE fires when a tutorial prompt is marked seen.

func test_tutorial_complete_fires_once() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	save.tutorial.mark("tutorial.prompt.swap")
	var r1: R.RewardResult = R.grant_rewards(save, src, null)
	assert_true(save.claimed_rewards.has("tutorial_completed:tutorial.prompt.swap"))
	var r2: R.RewardResult = R.grant_rewards(save, src, null)
	# Already claimed: no new grant.
	assert_eq(r2.granted.size(), 0)

# H. total_stars counts only completed records.

func test_total_stars_counts_completed_records() -> void:
	var save := _fresh_save()
	Progression.record_completion(save, "l1", 100, 2)
	Progression.record_completion(save, "l2", 100, 3)
	assert_eq(R.total_stars(save), 5)

# I. Re-opening the result screen cannot reclaim.

func test_reopening_result_screen_does_not_reclaim() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	var r1: R.RewardResult = R.grant_rewards(save, src, null)
	assert_eq(r1.granted.size(), 1)
	# Re-call 100 times — same result every time.
	for i in range(100):
		var rr: R.RewardResult = R.grant_rewards(save, src, null)
		assert_eq(rr.granted.size(), 0)
	# Inventory grew by exactly the spec amount, no more.
	assert_eq(int(save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY]), 1)

# J. RewardResult is serialisable + roundtrips.

func test_reward_result_to_dict_roundtrip() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	var r: R.RewardResult = R.grant_rewards(save, src, null)
	var d: Dictionary = r.to_dict()
	assert_eq(int(d.get("any_clamped", -1)), 0)
	var items: Array = d["granted_items"]
	assert_eq(items.size(), 1)
	assert_eq(int(items[0][0].count), 1)

# K. Null safety: null save / null source return empty result.

func test_null_inputs_return_empty_result() -> void:
	var r1: R.RewardResult = R.grant_rewards(null, _default_source(), null)
	assert_eq(r1.granted.size(), 0)
	var src := R.RewardSource.new([])
	var r2: R.RewardResult = R.grant_rewards(_fresh_save(), src, null)
	assert_eq(r2.granted.size(), 0)

# L. ClaimedRewards roundtrips through the save schema v2 envelope.

func test_claimed_rewards_roundtrip_via_envelope() -> void:
	var save := _fresh_save()
	save.claimed_rewards.mark("stars_total:5")
	save.claimed_rewards.mark("chapter_complete:ch1-sweet-trail")
	var envelope: Dictionary = SaveData.to_envelope_dict(save)
	var checksum: int = SaveData.checksum_of_dict(envelope)
	var parsed: Dictionary = envelope.duplicate(true)
	var back := SaveData.from_dict(parsed)
	assert_not_null(back)
	assert_eq(back.claimed_rewards.size(), 2)
	assert_true(back.claimed_rewards.has("stars_total:5"))
	assert_true(back.claimed_rewards.has("chapter_complete:ch1-sweet-trail"))

# M. v1 -> v2 migration inserts an empty ClaimedRewards.

func test_v1_to_v2_migration_inserts_empty_ledger() -> void:
	var v1: Dictionary = {
		"schema_version": 1,
		"levels": {},
		"inventory": {"boosters": {}, "cap_per_kind": 99, "cap_total": 999},
		"settings": {"music_volume": 1.0, "effects_volume": 1.0,
				"haptics_enabled": true, "language": "en",
				"reduced_motion": false, "high_contrast": false,
				"symbol_forward": false},
		"tutorial": {"seen": {}},
		"active_session": {"recipe_id": "", "snapshot": {}, "saved_at": 0},
		"coins": 0,
		"player_name": "",
		"created_at": 0,
		"updated_at": 0,
		"write_count": 0,
	}
	var migrated: Dictionary = SaveData.migrate(v1)
	assert_eq(int(migrated["schema_version"]), 2)
	assert_true(migrated.has("claimed_rewards"))
	var cr: Dictionary = migrated["claimed_rewards"]
	assert_eq(cr.size(), 1)
	assert_true(cr.has("claimed"))
	var claimed: Dictionary = cr["claimed"]
	assert_eq(claimed.size(), 0)

# N. Higher milestones can fire in the same call.

func test_multiple_thresholds_fire_in_one_call() -> void:
	var save := _fresh_save()
	# Add 17 stars worth of records in one go to fire 5 and 15 in the
	# same grant_rewards call.
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	Progression.record_completion(save, "l3", 100, 3)
	Progression.record_completion(save, "l4", 100, 3)
	Progression.record_completion(save, "l5", 100, 3)
	Progression.record_completion(save, "l6", 100, 2)
	var src: R.RewardSource = _default_source()
	var r: R.RewardResult = R.grant_rewards(save, src, null)
	# Both 5 (1) and 15 (2) fire in this single call.
	var keys: Array = []
	for s in r.granted:
		keys.append((s as R.RewardSpec).key)
	assert_true("stars_total:5" in keys)
	assert_true("stars_total:15" in keys)

# O. RewardSource.to_dict / from_dict roundtrips.

func test_reward_source_roundtrip() -> void:
	var src: R.RewardSource = _default_source()
	var d: Dictionary = src.to_dict()
	var back: R.RewardSource = R.RewardSource.from_dict(d)
	assert_eq(back.rewards.size(), src.rewards.size())
	assert_true(back.has("stars_total:100"))

# P. Integration: progression.record_completion -> grant_rewards wires
#    the level-completion reward path end-to-end.

func test_progression_record_completion_triggers_star_reward() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	# Drive the app-layer integration pattern: a level ends, the
	# presentation layer calls record_completion, then grant_rewards.
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 2)
	var r: R.RewardResult = R.grant_rewards(save, src, null)
	# 5 stars is now in; first star threshold fires.
	assert_true(save.claimed_rewards.has("stars_total:5"))
	assert_eq(int(save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY]), 1)

# Q. Integration: tutorial.mark -> grant_rewards wires the tutorial
#    reward path end-to-end.

func test_tutorial_mark_triggers_tutorial_reward() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	# Presentation flow: tutorial strap shows a prompt, the player
	# taps "next", we mark the prompt seen, then grant rewards.
	save.tutorial.mark("tutorial.prompt.swap")
	var r: R.RewardResult = R.grant_rewards(save, src, null)
	assert_true(save.claimed_rewards.has("tutorial_completed:tutorial.prompt.swap"))
	assert_eq(r.granted.size(), 1)

# R. Integration: chapter catalog + record_completion drives the
#    CHAPTER_COMPLETE reward.

func test_chapter_completion_triggers_chapter_reward_via_progression() -> void:
	var save := _fresh_save()
	var cat := _make_chapters()
	var src: R.RewardSource = _default_source()
	# Both levels in ch1 are completed via record_completion; the
	# second call closes the chapter, then grant_rewards fires the
	# CHAPTER_COMPLETE trigger.
	Progression.record_completion(save, "l1", 100, 3)
	Progression.record_completion(save, "l2", 100, 3)
	var r: R.RewardResult = R.grant_rewards(save, src, cat)
	assert_true(save.claimed_rewards.has("chapter_complete:ch1-sweet-trail"))
	assert_eq(r.chapter_completed, "ch1-sweet-trail")
	# 6 stars is now in too — but chapter 2 needs 6 stars, so the
	# stars_total:5 trigger also fires (but not 15 yet).
	var keys: Array = []
	for s in r.granted:
		keys.append((s as R.RewardSpec).key)
	assert_true("chapter_complete:ch1-sweet-trail" in keys)
	assert_true("stars_total:5" in keys)

# S. Integration: idempotency under repeated grant_rewards calls
#    mimics a result screen that re-opens after every level.

func test_result_screen_reopen_does_not_duplicate() -> void:
	var save := _fresh_save()
	var src: R.RewardSource = _default_source()
	# Simulate 5 levels played in sequence. After each, the result
	# screen opens and grant_rewards is called twice (open + reopen).
	# Only one call in the entire sequence is allowed to fire the
	# 5-star threshold; everything else is a no-op.
	var total_grants: int = 0
	for i in range(5):
		Progression.record_completion(save, "l%d" % i, 100, 2)
		# Result screen opens twice per level.
		var r1: R.RewardResult = R.grant_rewards(save, src, null)
		var r2: R.RewardResult = R.grant_rewards(save, src, null)
		total_grants += int(r1.granted.size()) + int(r2.granted.size())
	# Across the entire playthrough, exactly one grant fires (the
	# one that crossed the 5-star threshold).
	assert_eq(total_grants, 1)
	# Total inventory is exactly 1 Swap Retry (5-star threshold).
	assert_eq(int(save.inventory.boosters[Booster.BoosterKind.SWAP_RETRY]), 1)