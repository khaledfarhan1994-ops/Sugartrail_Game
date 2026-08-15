extends SceneTree
## Sugartrail economy simulator.
##
## Step 20 introduces a booster economy. This tool simulates a player
## playing through every curated level (in chapter order) at every
## possible star count, then walks through the tutorial prompts to
## verify the reward ledger produces a balanced booster income.
##
## The simulator is a pure-GDScript command-line tool; it does not
## need a running Godot server or a window. Run it with:
##
##   godot --headless --script tools/sim_economy.gd
##
## It prints a balance report to stdout:
##
##   STEP20_ECONOMY total_swap_retries=<n>
##   STEP20_ECONOMY tutorial_swap_retries=<n>
##   STEP20_ECONOMY star_swap_retries=<n>
##   STEP20_ECONOMY chapter_swap_retries=<n>
##   STEP20_ECONOMY cap_clamped=<bool>
##
## Exit code is 0 if the report matches the documented balance
## targets (see `EXPECTED_*` constants below); non-zero otherwise.

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")
const Rewards = preload("res://scripts/domain/rewards/rewards.gd")
const Progression = preload("res://scripts/domain/progression/chapter.gd")

## Path to the chapter catalog JSON. Loaded once at simulator start
## so CHAPTER_COMPLETE triggers can be evaluated.
const CHAPTER_CATALOG_PATH: String = "res://data/levels/chapters.json"

## Curator: every level id in launch order. Mirrors the
## data/levels/curated/INDEX.json set so the simulator exercises
## every real level without depending on filesystem ordering.
const LAUNCH_LEVEL_IDS: Array = [
	"l1-first-match",
	"l2-horizontal-vertical",
	"l3-cascade",
	"l4-move-budget",
	"l5-stars",
	"l6-cascade-pressure",
	"l7-tight-budget",
	"l8-pause-and-restart",
	"l9-long-combo",
	"l10-final",
	"l11-frosting-intro",
	"l12-locked-cells",
	"l13-clear-layers",
	"l14-release-token",
	"l15-mixed-objectives",
]

## Curator: every tutorial prompt id the player will see in a
## fresh-launch flow.
const LAUNCH_TUTORIAL_IDS: Array = [
	"tutorial.prompt.swap",
	"tutorial.prompt.objective",
	"tutorial.prompt.frosting.intro",
	"tutorial.prompt.locked.intro",
]

## Curator: star counts a fresh player might realistically earn on
## each level. The simulator walks each level at 1 star, 2 stars,
## and 3 stars to bracket worst / mid / best income.
const STAR_OUTCOMES: Array = [1, 2, 3]

## Documented balance targets. These are the public numbers that
## `docs/02-game-design.md §6` (booster economy) promises:
##
##   - 5 / 15 / 30 / 60 / 100 star thresholds grant 1 / 2 / 3 / 5 / 8
##     Swap Retries, summed across the entire playthrough.
##   - Each of the 3 chapters grants 2 Swap Retries on completion.
##   - Each of the 4 tutorial prompts grants 1 Swap Retry.
##
## So a perfect-run player (15 levels × 3 stars = 45 stars) hits the
## 30-star threshold but not the 60-star. Income from level play:
##   star: 1 + 2 + 3 = 6 Swap Retries (thresholds 5/15/30).
##   chapter: 3 × 2 = 6 Swap Retries.
##   Total from level play = 12 Swap Retries.
## Income from the tutorial flow (independent of level play):
##   tutorial: 4 × 1 = 4 Swap Retries.
const EXPECTED_PERFECT_STAR_REWARDS: int = 1 + 2 + 3
const EXPECTED_CHAPTER_REWARDS: int = 6
const EXPECTED_PERFECT_LEVEL_TOTAL: int = (
	EXPECTED_PERFECT_STAR_REWARDS
	+ EXPECTED_CHAPTER_REWARDS)
const EXPECTED_TUTORIAL_REWARDS: int = 4

func _init() -> void:
	var ok: bool = _run_simulation()
	if ok:
		print("STEP20_ECONOMY_OK")
		quit(0)
	else:
		print("STEP20_ECONOMY_FAIL")
		quit(1)

## Drive a fresh-player simulation. Returns true if the balance
## matches the documented targets, false otherwise.
func _run_simulation() -> bool:
	var catalog := _load_chapter_catalog()
	if catalog == null:
		print("STEP20_ECONOMY_LOAD_FAIL")
		return false
	var src: Rewards.RewardSource = Rewards.default_source()
	# Drive the level-completion path.
	var save := SaveData.fresh_save()
	for level_id in LAUNCH_LEVEL_IDS:
		# Worst case: 1 star.
		Progression.record_completion(save, String(level_id), 100, 1)
	# Capture the worst-case balance.
	var worst_result: Rewards.RewardResult = Rewards.grant_rewards(save, src, catalog)
	var worst_swap_retries: int = _swap_retries(worst_result)
	# Mid case: re-load save, walk every level at 2 stars.
	var mid_save := SaveData.fresh_save()
	for level_id in LAUNCH_LEVEL_IDS:
		Progression.record_completion(mid_save, String(level_id), 100, 2)
	var mid_result: Rewards.RewardResult = Rewards.grant_rewards(mid_save, src, catalog)
	var mid_swap_retries: int = _swap_retries(mid_result)
	# Best case: walk every level at 3 stars.
	var best_save := SaveData.fresh_save()
	for level_id in LAUNCH_LEVEL_IDS:
		Progression.record_completion(best_save, String(level_id), 100, 3)
	var best_result: Rewards.RewardResult = Rewards.grant_rewards(best_save, src, catalog)
	var best_swap_retries: int = _swap_retries(best_result)
	# Tutorial path: a fresh save, mark every prompt, grant rewards.
	var tut_save := SaveData.fresh_save()
	for tut_id in LAUNCH_TUTORIAL_IDS:
		tut_save.tutorial.mark(String(tut_id))
	var tut_result: Rewards.RewardResult = Rewards.grant_rewards(tut_save, src, null)
	var tut_swap_retries: int = _swap_retries(tut_result)
	# Print the report.
	print("STEP20_ECONOMY total_swap_retries_perfect=%d" % best_swap_retries)
	print("STEP20_ECONOMY total_swap_retries_mid=%d" % mid_swap_retries)
	print("STEP20_ECONOMY total_swap_retries_worst=%d" % worst_swap_retries)
	print("STEP20_ECONOMY tutorial_swap_retries=%d" % tut_swap_retries)
	# Assert: best case hits the documented total.
	if best_swap_retries != EXPECTED_PERFECT_LEVEL_TOTAL:
		print("STEP20_ECONOMY_MISMATCH expected_perfect=%d got=%d" % [
			EXPECTED_PERFECT_LEVEL_TOTAL, best_swap_retries])
		return false
	# Assert: tutorial path grants exactly EXPECTED_TUTORIAL_REWARDS.
	if tut_swap_retries != EXPECTED_TUTORIAL_REWARDS:
		print("STEP20_ECONOMY_MISMATCH expected_tutorial=%d got=%d" % [
			EXPECTED_TUTORIAL_REWARDS, tut_swap_retries])
		return false
	# Assert: best >= worst and best >= mid (monotone in stars).
	if best_swap_retries < mid_swap_retries:
		print("STEP20_ECONOMY_MISMATCH monotone best<mid")
		return false
	if best_swap_retries < worst_swap_retries:
		print("STEP20_ECONOMY_MISMATCH monotone best<worst")
		return false
	return true

## Load the chapter catalog from disk so CHAPTER_COMPLETE triggers
## evaluate. Returns null on parse failure.
func _load_chapter_catalog() -> Progression.ChapterCatalog:
	if not ResourceLoader.exists(CHAPTER_CATALOG_PATH):
		print("STEP20_ECONOMY chapter catalog missing at %s" % CHAPTER_CATALOG_PATH)
		return null
	var f := FileAccess.open(CHAPTER_CATALOG_PATH, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return Progression.ChapterCatalog.from_dict(parsed)

## Sum the Swap Retry count across a RewardResult.
func _swap_retries(r: Rewards.RewardResult) -> int:
	var total: int = 0
	for arr in r.granted_items:
		for it in arr:
			total += int(it.count)
	return total