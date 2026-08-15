class_name SugartrailRewards
extends RefCounted
## Reward ledger + catalog + grant logic.
##
## Step 20 introduces the booster economy. Players earn boosters from
## bounded, deterministic, idempotent rewards: star thresholds, chapter
## completion, and tutorial completion. Daily-challenge rewards are
## deferred to a later phase (see docs/02-game-design.md §6.2).
##
## Semantics:
##
##   - Each reward in the catalog has a stable `key` (string id).
##   - The RewardLedger stores the set of keys already claimed. A
##     reward is granted at most ONCE across the entire lifetime of
##     the save, regardless of how many times the trigger fires.
##   - The grant function is pure given (save_data, trigger_event):
##     the only mutation to SaveData is the ledger + inventory delta.
##   - Inventory caps (per-kind and total) are enforced; if the
##     player's inventory is at the cap, the awarded amount is
##     reduced to fit but the reward is still marked as claimed.
##   - Reopening the result screen cannot reclaim — the ledger is
##     persistent.
##   - Reward labels (`Spec.label`) are localization keys (the
##     pattern `reward.label.<reward_key>`). Step 21 wires the
##     presentation layer to resolve them through
##     `SugartrailLocale.translate`. The default catalog keeps the
##     inline English strings in `default_source()` as a fallback.
##
## Integration contract (Step 20):
##
##   The domain layer stays pure: `Rewards.grant_rewards(save_data,
##   source, chapter_catalog)` is the single entry point. Callers in
##   the application/presentation layer (vertical slice, result
##   screen, world-map popup) invoke it from three event sources:
##
##     1. After every level completion: call
##        `SugartrailProgression.record_completion(save_data, ...)`
##        first, then `Rewards.grant_rewards(save_data, source,
##        chapter_catalog)`. The star-threshold and chapter-complete
##        triggers evaluate from the new save state.
##     2. After a tutorial prompt is shown: call
##        `save_data.tutorial.mark(prompt_id)`, then
##        `Rewards.grant_rewards(save_data, source, null)`. The
##        tutorial-complete trigger evaluates from the new seen flag.
##     3. When the result screen opens: it can safely call
##        `Rewards.grant_rewards` again; the ledger ensures no
##        duplicate grants.
##
##   The default catalog ships with `Rewards.default_source()`. The
##   app layer caches this in a global or injects it; tests pass
##   synthetic sources.

## Trigger kinds. A reward fires when its trigger's condition
## becomes true. `STARS_TOTAL` fires once when the player's total
## star count crosses `threshold`. `CHAPTER_COMPLETE` fires once
## when a chapter's last level is completed. `TUTORIAL_COMPLETE`
## fires once when a tutorial prompt is marked seen.
enum TriggerKind {
	STARS_TOTAL = 0,
	CHAPTER_COMPLETE = 1,
	TUTORIAL_COMPLETE = 2,
}

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")
const Booster = preload("res://scripts/domain/boosters/boosters.gd")

## A single reward rule.
class RewardSpec:
	## Stable claim key. Used as the ledger entry.
	var key: String = ""
	## Trigger kind.
	var trigger: int = TriggerKind.STARS_TOTAL
	## Trigger parameter: stars threshold (STARS_TOTAL), chapter id
	## (CHAPTER_COMPLETE), or tutorial prompt id (TUTORIAL_COMPLETE).
	var target: String = ""
	## Threshold for STARS_TOTAL (number of stars >= target fires).
	var threshold: int = 0
	## Items granted: list of Dictionaries `{kind_id: int, count: int}`.
	var items: Array = []
	## Human-readable label shown in the result toast.
	var label: String = ""

	func _init(p_key: String = "", p_trigger: int = TriggerKind.STARS_TOTAL,
			p_target: String = "", p_threshold: int = 0,
			p_items: Array = [], p_label: String = "") -> void:
		key = p_key
		trigger = p_trigger
		target = p_target
		threshold = p_threshold
		items = []
		for it in p_items:
			if it is Dictionary:
				var d: Dictionary = it
				items.append({
					"kind_id": int(d.get("kind_id", Booster.BoosterKind.SWAP_RETRY)),
					"count": max(0, int(d.get("count", 0))),
				})
		label = p_label

	func to_dict() -> Dictionary:
		var out_items: Array = []
		for it in items:
			out_items.append({"kind_id": int(it.kind_id), "count": int(it.count)})
		return {
			"key": key,
			"trigger": trigger,
			"target": target,
			"threshold": threshold,
			"items": out_items,
			"label": label,
		}

	static func from_dict(d: Dictionary) -> RewardSpec:
		return RewardSpec.new(
			String(d.get("key", "")),
			int(d.get("trigger", TriggerKind.STARS_TOTAL)),
			String(d.get("target", "")),
			int(d.get("threshold", 0)),
			d.get("items", []),
			String(d.get("label", "")))

## A RewardSource is the catalog + a way to evaluate triggers.
## It is a plain holder; the actual grant logic lives on `Rewards`
## (the static class) so callers don't need to instantiate one.
class RewardSource:
	var rewards: Array = []

	func _init(p_rewards: Array = []) -> void:
		rewards = []
		for r in p_rewards:
			if r is RewardSpec:
				rewards.append(r)

	func to_dict() -> Dictionary:
		var out: Array = []
		for r in rewards:
			out.append((r as RewardSpec).to_dict())
		return {"rewards": out}

	static func from_dict(d: Dictionary) -> RewardSource:
		var in_arr: Variant = d.get("rewards", [])
		var list: Array = []
		if in_arr is Array:
			for r in (in_arr as Array):
				if r is Dictionary:
					list.append(RewardSpec.from_dict(r))
		return RewardSource.new(list)

	func has(key: String) -> bool:
		for r in rewards:
			if (r as RewardSpec).key == key:
				return true
		return false

	func get_by_key(key: String) -> RewardSpec:
		for r in rewards:
			if (r as RewardSpec).key == key:
				return r
		return null

## What actually got granted by a single `grant_rewards` call.
## Empty items arrays mean no new rewards were granted (the
## ledger already had every triggered reward).
class RewardResult:
	## Granted rewards, in catalog order. Each entry is the
	## RewardSpec that fired.
	var granted: Array = []
	## For each granted reward, the items that were actually added
	## to inventory (after cap clamping). Parallel to `granted`.
	var granted_items: Array = []
	## True if any inventory item was clamped to a cap.
	var any_clamped: bool = false
	## True if a level chapter was completed by this grant (used by
	## the presentation layer to chain CHAPTER_COMPLETE triggers).
	var chapter_completed: String = ""

	func _init() -> void:
		granted = []
		granted_items = []
		any_clamped = false
		chapter_completed = ""

	func to_dict() -> Dictionary:
		var items_out: Array = []
		for arr in granted_items:
			var sub: Array = []
			for it in arr:
				sub.append({"kind_id": int(it.kind_id), "count": int(it.count)})
			items_out.append(sub)
		var granted_out: Array = []
		for r in granted:
			granted_out.append((r as RewardSpec).key)
		return {
			"granted": granted_out,
			"granted_items": items_out,
			"any_clamped": any_clamped,
			"chapter_completed": chapter_completed,
		}

## The default launch catalog. Star thresholds (5/15/30/60/100)
## grant a Swap Retry each. Each chapter's completion grants 2
## Swap Retries. The first time a player completes a tutorial
## prompt, they get a Swap Retry.
static func default_source() -> RewardSource:
	var out: Array = []
	out.append(RewardSpec.new(
			"stars_total:5", TriggerKind.STARS_TOTAL, "", 5,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 1}],
			"reward.label.stars_total:5"))
	out.append(RewardSpec.new(
			"stars_total:15", TriggerKind.STARS_TOTAL, "", 15,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 2}],
			"reward.label.stars_total:15"))
	out.append(RewardSpec.new(
			"stars_total:30", TriggerKind.STARS_TOTAL, "", 30,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 3}],
			"reward.label.stars_total:30"))
	out.append(RewardSpec.new(
			"stars_total:60", TriggerKind.STARS_TOTAL, "", 60,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 5}],
			"reward.label.stars_total:60"))
	out.append(RewardSpec.new(
			"stars_total:100", TriggerKind.STARS_TOTAL, "", 100,
			[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 8}],
			"reward.label.stars_total:100"))
	# Per-chapter completion. The default catalog covers 3 chapters
	# (ch1-sweet-trail, ch2-cascade-master, ch3-blocked-confection).
	for ch_id in ["ch1-sweet-trail", "ch2-cascade-master", "ch3-blocked-confection"]:
		out.append(RewardSpec.new(
				"chapter_complete:" + ch_id, TriggerKind.CHAPTER_COMPLETE,
				ch_id, 0,
				[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 2}],
				"reward.label.chapter_complete:" + ch_id))
	# Tutorial completion — one Swap Retry per tutorial prompt the
	# player sees. The prompt ids are matched verbatim against the
	# TutorialFlags.seen map.
	for tut_id in [
		"tutorial.prompt.swap",
		"tutorial.prompt.objective",
		"tutorial.prompt.frosting.intro",
		"tutorial.prompt.locked.intro",
	]:
		out.append(RewardSpec.new(
				"tutorial_completed:" + tut_id, TriggerKind.TUTORIAL_COMPLETE,
				tut_id, 0,
				[{"kind_id": Booster.BoosterKind.SWAP_RETRY, "count": 1}],
				"reward.label.tutorial_completed:" + tut_id))
	return RewardSource.new(out)

## Resolve a RewardSpec's label through a locale catalog. Returns
## the catalog translation when available; falls back to the spec's
## inline `label` (which is itself a localization key in the
## default catalog) and finally to the spec key. The presentation
## layer calls this once per granted reward to render the result
## toast.
static func localize_label(spec: RewardSpec, catalog) -> String:
	if catalog != null:
		var translated: String = catalog.translate(spec.label)
		if translated != "":
			return translated
	return spec.label

## Count a chapter's total earned stars from SaveData levels.
static func _chapter_stars(save_data, chapter_level_ids: Array) -> int:
	var s: int = 0
	for lid in chapter_level_ids:
		var rec_v: Variant = save_data.levels.get(String(lid), null)
		if rec_v != null:
			var rec = rec_v
			s += int(rec.stars)
	return s

## Count the total earned stars across all levels.
static func total_stars(save_data) -> int:
	var s: int = 0
	for k in save_data.levels:
		var rec_v: Variant = save_data.levels[k]
		if rec_v != null:
			s += int((rec_v as SaveData.LevelRecord).stars)
	return s

## Whether a chapter's last level is now completed (so the chapter
## is freshly completed by this trigger event).
static func _is_chapter_just_completed(save_data, chapter_level_ids: Array) -> bool:
	if chapter_level_ids.size() == 0:
		return false
	var last_id: String = String(chapter_level_ids[chapter_level_ids.size() - 1])
	var rec_v: Variant = save_data.levels.get(last_id, null)
	if rec_v == null:
		return false
	return bool((rec_v as SaveData.LevelRecord).completed_once)

## Apply one reward spec. Mutates `inventory`. Returns a tiny
## Dictionary `{items: Array, clamped: bool}`. `clamped` is true if
## any item was reduced by a cap; `items` is what actually got
## added.
static func _apply_reward(spec: RewardSpec,
		inventory: SaveData.InventoryRecord) -> Dictionary:
	var granted: Array = []
	var clamped: bool = false
	for it in spec.items:
		var kind_id: int = int(it.kind_id)
		var count: int = int(it.count)
		# Per-kind cap.
		var have: int = inventory.boosters.get(kind_id, 0)
		var room_kind: int = max(0, inventory.cap_per_kind - have)
		# Total cap.
		var total_have: int = 0
		for k in inventory.boosters:
			total_have += int(inventory.boosters[k])
		var room_total: int = max(0, inventory.cap_total - total_have)
		var can: int = min(count, room_kind)
		can = min(can, room_total)
		if can < count:
			clamped = true
		if can > 0:
			inventory.boosters[kind_id] = have + can
			granted.append({"kind_id": kind_id, "count": can})
	return {"items": granted, "clamped": clamped}

## Grant any rewards whose triggers are now satisfied. Mutates
## `save_data` in place: marks each newly-claimed key in the
## ledger, increments inventory (clamped to caps), and records the
## granted amounts in the returned RewardResult.
##
## `chapter_catalog` is an optional `SugartrailProgression.ChapterCatalog`
## — when provided, the function evaluates CHAPTER_COMPLETE triggers
## against it. When null, those triggers are simply skipped.
static func grant_rewards(save_data, source: RewardSource,
		chapter_catalog = null) -> RewardResult:
	var result := RewardResult.new()
	if save_data == null or source == null:
		return result
	if save_data.claimed_rewards == null:
		save_data.claimed_rewards = SaveData.ClaimedRewards.new()
	for spec in source.rewards:
		var s: RewardSpec = spec
		# Already claimed? Skip.
		if save_data.claimed_rewards.has(s.key):
			continue
		var should_fire: bool = false
		match s.trigger:
			TriggerKind.STARS_TOTAL:
				var stars: int = total_stars(save_data)
				should_fire = stars >= s.threshold and s.threshold > 0
			TriggerKind.CHAPTER_COMPLETE:
				if chapter_catalog != null:
					var ch_v: Variant = chapter_catalog.by_id(s.target)
					if ch_v != null:
						var ch = ch_v
						if _is_chapter_just_completed(save_data, ch.level_ids):
							should_fire = true
							result.chapter_completed = s.target
			TriggerKind.TUTORIAL_COMPLETE:
				if save_data.tutorial != null:
					should_fire = save_data.tutorial.has_seen(s.target)
		if not should_fire:
			continue
		var applied: Dictionary = _apply_reward(s, save_data.inventory)
		if bool(applied.get("clamped", false)):
			result.any_clamped = true
		save_data.claimed_rewards.mark(s.key)
		result.granted.append(s)
		result.granted_items.append(applied.get("items", []))
	return result

## Count how many total Swap Retries a player would have after
## completing all star milestones. Used by the simulation harness
## to assert balanced economy.
static func expected_rewards_for_stars(star_milestones: Array) -> int:
	# Helper: returns the count for a single STARS_TOTAL threshold.
	# Pure function for the simulation to assert against.
	var total: int = 0
	# The default catalog's per-milestone counts are: 5->1, 15->2,
	# 30->3, 60->5, 100->8. Encoded here for the simulator.
	var per_milestone: Dictionary = {
		5: 1, 15: 2, 30: 3, 60: 5, 100: 8,
	}
	for m in star_milestones:
		var k: int = int(m)
		if per_milestone.has(k):
			total += int(per_milestone[k])
	return total