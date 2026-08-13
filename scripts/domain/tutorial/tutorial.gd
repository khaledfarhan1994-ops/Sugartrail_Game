class_name SugartrailTutorial
extends RefCounted
## Concise, skippable tutorial prompts and level intro information.
##
## Step 11 introduces the tutorial prompts that ride alongside the
## first ten curated levels. The tutorial is deliberately small:
## every prompt is a localization key, the player can skip it, and
## it never obscures the required controls (the prompt lives in a
## strap below the board, never overlapping it).
##
## The tutorial itself is pure data. The presentation layer (a
## future Scene) reads `TutorialPack.from_recipe()` and animates
## the prompts. This module just gives the domain a stable
## representation that tests can pin and the loader can
## deserialise.

## A single prompt. Always one localization key plus a display
## duration. Duration is in seconds of unobstructed reading time;
## the presentation may pause the timer when the player is mid-swap.
class Prompt:
	var key: String = ""
	var duration: float = 0.0

	func _init(p_key: String = "", p_duration: float = 4.0) -> void:
		key = p_key
		duration = p_duration

	func to_dict() -> Dictionary:
		return {"key": key, "duration": duration}

	static func from_dict(d: Dictionary) -> Prompt:
		return Prompt.new(
			String(d.get("key", "")),
			float(d.get("duration", 4.0)))

## A bundle of prompts and a level intro for one level. Built from
## a validated recipe dictionary.
class TutorialPack:
	## Localization key for the level intro strap. May be empty.
	var intro_key: String = ""
	## Ordered list of prompts to show during play.
	var prompts: Array = []
	## Index of the next prompt to show. The presentation typically
	## advances this when the matching in-game action occurs.
	var next_prompt: int = 0

	func _init(p_intro_key: String = "", p_prompts: Array = []) -> void:
		intro_key = p_intro_key
		prompts = p_prompts
		next_prompt = 0

	## Return the next prompt to show, or null if all prompts have
	## been shown. Does not advance the pointer; the presentation
	## decides when to call advance().
	func peek() -> Prompt:
		if next_prompt >= prompts.size():
			return null
		return prompts[next_prompt]

	## Advance past the current prompt. Returns the prompt that was
	## just dismissed, or null if there was nothing to dismiss.
	func advance() -> Prompt:
		if next_prompt >= prompts.size():
			return null
		var p: Prompt = prompts[next_prompt]
		next_prompt += 1
		return p

	## True if every prompt has been shown.
	func is_complete() -> bool:
		return next_prompt >= prompts.size()

	## Backwards-compat helper. Returns the list of remaining
	## prompt keys (the presentation layer renders these as a
	## single combined string when the player asks to "see all").
	func remaining_keys() -> Array:
		var out: Array = []
		for i in range(next_prompt, prompts.size()):
			out.append(prompts[i].key)
		return out

	func to_dict() -> Dictionary:
		var prompt_dicts: Array = []
		for p in prompts:
			prompt_dicts.append((p as Prompt).to_dict())
		return {
			"intro_key": intro_key,
			"prompts": prompt_dicts,
			"next_prompt": next_prompt,
		}

## Build a TutorialPack from a validated recipe dictionary. The
## recipe must already have `intro_text` (string) and `tutorial`
## (Array of strings). Returns a TutorialPack with default
## durations. Unknown keys fall through with a 0-second default,
## which the presentation should treat as "show immediately".
static func from_recipe(recipe: Dictionary) -> TutorialPack:
	var intro: String = String(recipe.get("intro_text", ""))
	var raw_prompts: Array = recipe.get("tutorial", [])
	var prompts: Array = []
	for entry in raw_prompts:
		var p := Prompt.new(entry, 4.0)
		prompts.append(p)
	return TutorialPack.new(intro, prompts)

## Catalog of localization keys known to the English (en) resources.
## The presentation builds a runtime dictionary by indexing this
## table. Step 21 (localization) replaces this with a real .po/.csv
## file; for now the keys live in-domain so tests can detect missing
## translations.
class Catalog:
	## Strip -level intro.
	const STRAP_INTRO: String = "tutorial.intro.first_level"
	## Tap a piece to select it.
	const PROMPT_SELECT: String = "tutorial.prompt.select"
	## Swipe or tap-target to swap.
	const PROMPT_SWAP: String = "tutorial.prompt.swap"
	## Three of a kind in a row or column clears them.
	const PROMPT_MATCH: String = "tutorial.prompt.match"
	## Cascades happen when falling pieces form new matches.
	const PROMPT_CASCADE: String = "tutorial.prompt.cascade"
	## The objective ring: collect the highlighted colour.
	const PROMPT_OBJECTIVE: String = "tutorial.prompt.objective"
	## Move budget — make every swap count.
	const PROMPT_MOVE_LIMIT: String = "tutorial.prompt.move_limit"
	## You can always retry.
	const PROMPT_RETRY: String = "tutorial.prompt.retry"
	## Pause is always available.
	const PROMPT_PAUSE: String = "tutorial.prompt.pause"
	## A level can be reshuffled if the board deadlocks. Tutorial-level
	## boards never deadlock, but introducing the player to the
	## concept here sets them up for later levels.
	const PROMPT_DEADLOCK: String = "tutorial.prompt.deadlock"

	## Known keys for the first ten levels. The tests use this set
	## to verify that every prompt key resolves to a known English
	## string.
	static func known_keys() -> Array:
		return [
			STRAP_INTRO,
			PROMPT_SELECT,
			PROMPT_SWAP,
			PROMPT_MATCH,
			PROMPT_CASCADE,
			PROMPT_OBJECTIVE,
			PROMPT_MOVE_LIMIT,
			PROMPT_RETRY,
			PROMPT_PAUSE,
			PROMPT_DEADLOCK,
		]

## English translation strings. Step 21 replaces this with a real
## .po file. The keys must match Catalog.known_keys(). Tests pin
## these strings so that any rewording is an explicit, recorded
## decision.
static func english(key: String) -> String:
	match key:
		Catalog.STRAP_INTRO: return "Welcome to Sugartrail. Swap pieces to clear the board."
		Catalog.PROMPT_SELECT: return "Tap a piece to select it."
		Catalog.PROMPT_SWAP: return "Swipe, or tap a neighbour, to swap."
		Catalog.PROMPT_MATCH: return "Three of a kind clears them."
		Catalog.PROMPT_CASCADE: return "Falling pieces can chain into more matches."
		Catalog.PROMPT_OBJECTIVE: return "Collect the highlighted colour."
		Catalog.PROMPT_MOVE_LIMIT: return "You have a limited number of moves."
		Catalog.PROMPT_RETRY: return "Lost? Retry any time — every level is unlimited."
		Catalog.PROMPT_PAUSE: return "Tap the pause button to take a break."
		Catalog.PROMPT_DEADLOCK: return "If the board deadlocks, a reshuffle keeps you playing."
		_: return ""