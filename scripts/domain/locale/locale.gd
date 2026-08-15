class_name SugartrailLocale
extends RefCounted
## Locale catalog + key-based translator.
##
## Step 21 introduces the localisation foundation. Every player-facing
## string flows through a stable key; the catalog maps keys to per-
## language text with an explicit fallback chain. The default
## language is `en` (English); a launch-set second language (Spanish)
## demonstrates the multi-locale path. Adding more languages is a
## data-only change: drop a JSON file into `data/locale/` and list
## its code in the catalog.
##
## Design choices:
##
##   - Pure data + a tiny lookup helper. No scene nodes, no audio,
##     no input, no FS dependency for the in-memory catalog (only the
##     loaders touch the disk).
##   - The catalog is a static in-memory dictionary keyed by locale
##     code. Tests pass synthetic catalogs; the application loads
##     `data/locale/*.json` once at boot.
##   - Every lookup is O(1) per locale step; the fallback chain is
##     bounded (default cap = 5) so a misconfigured catalog cannot
##     trigger an unbounded walk.
##   - Unknown keys return an empty string and never crash. The
##     presentation layer is expected to log + show a placeholder.
##     Tests assert this contract.
##   - The `language` field on SaveData.SettingsRecord is the source
##     of truth for the active locale. When the language is empty or
##     unknown, the catalog falls back to its default (`en`).
##
## Format:
##
##   data/locale/en.json
##     { "version": 1, "code": "en", "name": "English",
##       "fallback": "en",
##       "strings": { "tutorial.prompt.swap": "Swipe, or tap...",
##                    ... } }
##
##   data/locale/es.json
##     { "version": 1, "code": "es", "name": "Español",
##       "fallback": "en",
##       "strings": { "tutorial.prompt.swap": "Desliza o toca...",
##                    ... } }

## A single locale: code + human-readable name + fallback chain
## entry + the key->text map. Loaded from a JSON file or built
## programmatically in tests.
class Locale:
	var code: String = ""
	var name: String = ""
	## Locale code to fall back to when a key is missing. Empty
	## string = "no fallback, terminate the chain".
	var fallback: String = ""
	var strings: Dictionary = {}

	func _init(p_code: String = "", p_name: String = "",
			p_fallback: String = "", p_strings: Dictionary = {}) -> void:
		code = p_code
		name = p_name
		fallback = p_fallback
		strings = {}
		for k in p_strings:
			strings[String(k)] = String(p_strings[k])

	func has_key(key: String) -> bool:
		return strings.has(key)

	## Lookup a translation for the given key. Returns the empty
	## string when the key is missing in this locale (callers
	## chain to the locale's `fallback`).
	func lookup(key: String) -> String:
		return String(strings.get(key, ""))

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in strings:
			out[String(k)] = String(strings[k])
		return {
			"code": code,
			"name": name,
			"fallback": fallback,
			"strings": out,
		}

	static func from_dict(d: Dictionary) -> Locale:
		var s_in: Variant = d.get("strings", {})
		var s: Dictionary = {}
		if s_in is Dictionary:
			for k in (s_in as Dictionary):
				s[String(k)] = String((s_in as Dictionary)[k])
		return Locale.new(
				String(d.get("code", "")),
				String(d.get("name", "")),
				String(d.get("fallback", "")),
				s)

## The catalog: every locale known to the build, plus the active
## code. The catalog is the runtime source of truth; the JSON
## loaders feed it.
class LocaleCatalog:
	## Default locale code used when the player's `language`
	## setting is empty or unknown.
	const DEFAULT_CODE: String = "en"
	## Hard cap on the fallback chain walk. A misconfigured
	## `fallback` cycle (a -> b -> a -> ...) would otherwise loop
	## forever; this cap guarantees O(1) work per translate call.
	const MAX_FALLBACK_HOPS: int = 5

	var locales: Dictionary = {}     # code (String) -> Locale
	var active_code: String = DEFAULT_CODE

	func _init(p_locales: Dictionary = {},
			p_active_code: String = DEFAULT_CODE) -> void:
		locales = {}
		for k in p_locales:
			var v: Variant = p_locales[k]
			if v is Locale:
				locales[String(k)] = v
		if locales.has(DEFAULT_CODE) and not locales.has(p_active_code):
			active_code = DEFAULT_CODE
		else:
			active_code = p_active_code

	func has(code: String) -> bool:
		return locales.has(code)

	func get_locale(code: String) -> Locale:
		var v: Variant = locales.get(code, null)
		if v is Locale:
			return v
		return null

	func codes() -> Array:
		var out: Array = []
		for k in locales:
			out.append(String(k))
		return out

	## Set the active locale. When the requested code is unknown,
	## the active code stays where it was (no silent fallback —
	## callers can inspect `active_code` to detect a misconfig).
	func set_active(code: String) -> bool:
		if not locales.has(code):
			return false
		active_code = code
		return true

	## Translate a key using the active locale's fallback chain.
	## Returns an empty string when the key is unknown in every
	## locale on the chain (callers log + show placeholder).
	func translate(key: String) -> String:
		var seen: Dictionary = {}
		var current: String = active_code
		var hops: int = 0
		while current != "" and hops < MAX_FALLBACK_HOPS:
			if seen.has(current):
				# Cycle detected — bail.
				return ""
			seen[current] = true
			var loc_v: Variant = locales.get(current, null)
			if loc_v == null:
				return ""
			var loc: Locale = loc_v
			if loc.has_key(key):
				return loc.lookup(key)
			current = loc.fallback
			hops += 1
		return ""

	## Translate using an explicit code (not the active one). Same
	## fallback rules apply. Useful for the settings preview UI
	## where the player picks a language before confirming.
	func translate_for(code: String, key: String) -> String:
		var saved: String = active_code
		if not set_active(code):
			return ""
		var out: String = translate(key)
		active_code = saved
		return out

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in locales:
			out[String(k)] = (locales[k] as Locale).to_dict()
		return {
			"default_code": DEFAULT_CODE,
			"active_code": active_code,
			"locales": out,
		}

	static func from_dict(d: Dictionary) -> LocaleCatalog:
		var ls_in: Variant = d.get("locales", {})
		var ls: Dictionary = {}
		if ls_in is Dictionary:
			for k in (ls_in as Dictionary):
				var v: Variant = (ls_in as Dictionary)[k]
				if v is Dictionary:
					ls[String(k)] = Locale.from_dict(v)
		return LocaleCatalog.new(
				ls,
				String(d.get("active_code", DEFAULT_CODE)))

## Build the launch-set catalog from inline data. Used by tests
## and by the application's boot loader when no JSON files are
## shipped (smallest possible build). The application's boot path
## overrides this with the on-disk catalog; tests use the synthetic
## one.
static func default_catalog() -> LocaleCatalog:
	var en_strings: Dictionary = {
		"tutorial.intro.first_level":
				"Welcome to Sugartrail. Swap pieces to clear the board.",
		"tutorial.prompt.select":
				"Tap a piece to select it.",
		"tutorial.prompt.swap":
				"Swipe, or tap a neighbour, to swap.",
		"tutorial.prompt.match":
				"Three of a kind clears them.",
		"tutorial.prompt.cascade":
				"Falling pieces can chain into more matches.",
		"tutorial.prompt.objective":
				"Collect the highlighted colour.",
		"tutorial.prompt.move_limit":
				"You have a limited number of moves.",
		"tutorial.prompt.retry":
				"Lost? Retry any time — every level is unlimited.",
		"tutorial.prompt.pause":
				"Tap the pause button to take a break.",
		"tutorial.prompt.deadlock":
				"If the board deadlocks, a reshuffle keeps you playing.",
		"tutorial.frosting.intro":
				"Frosted cells take an extra clear to break.",
		"tutorial.prompt.frosting.intro":
				"Icy cells cover pieces — match through them to damage the frosting.",
		"tutorial.prompt.frosting.match":
				"Each match on a frosted cell cracks one layer.",
		"tutorial.locked.intro":
				"Some pieces are locked in cages.",
		"tutorial.prompt.locked.intro":
				"Locked pieces won't budge from a regular match.",
		"tutorial.prompt.locked.release":
				"Specials and combos break the lock.",
		"tutorial.layers.intro":
				"Some levels need layers of frosting cleared.",
		"tutorial.prompt.layers.intro":
				"Each frosting match chips a layer — clear them all to win.",
		"tutorial.prompt.layers.break":
				"Every cleared layer counts toward your goal.",
		"tutorial.tokens.intro":
				"Trapped tokens wait for the right piece.",
		"tutorial.prompt.tokens.intro":
				"Match the colour underneath the token to release it.",
		"tutorial.prompt.tokens.release":
				"Released tokens count toward your goal, scoring bonus points.",
		"tutorial.prompt.score.target":
				"Some levels need a score, not a set of pieces.",
		"reward.label.stars_total:5":
				"First 5 stars",
		"reward.label.stars_total:15":
				"15-star milestone",
		"reward.label.stars_total:30":
				"30-star milestone",
		"reward.label.stars_total:60":
				"60-star milestone",
		"reward.label.stars_total:100":
				"100-star milestone",
		"reward.label.chapter_complete:ch1-sweet-trail":
				"Completed ch1-sweet-trail",
		"reward.label.chapter_complete:ch2-cascade-master":
				"Completed ch2-cascade-master",
		"reward.label.chapter_complete:ch3-blocked-confection":
				"Completed ch3-blocked-confection",
		"reward.label.tutorial_completed:tutorial.prompt.swap":
				"Tutorial: tutorial.prompt.swap",
		"reward.label.tutorial_completed:tutorial.prompt.objective":
				"Tutorial: tutorial.prompt.objective",
		"reward.label.tutorial_completed:tutorial.prompt.frosting.intro":
				"Tutorial: tutorial.prompt.frosting.intro",
		"reward.label.tutorial_completed:tutorial.prompt.locked.intro":
				"Tutorial: tutorial.prompt.locked.intro",
		"settings.title": "Settings",
		"settings.music": "Music",
		"settings.effects": "Effects",
		"settings.haptics": "Haptics",
		"settings.language": "Language",
	}
	var es_strings: Dictionary = {
		"tutorial.prompt.swap":
				"Desliza, o toca un vecino, para intercambiar.",
		"tutorial.prompt.match":
				"Tres iguales se eliminan.",
		"tutorial.prompt.objective":
				"Recoge el color destacado.",
		"tutorial.prompt.move_limit":
				"Tienes un número limitado de movimientos.",
		"tutorial.prompt.frosting.intro":
				"Las células heladas cubren piezas — combínalas para dañar el glaseado.",
		"tutorial.prompt.score.target":
				"Algunos niveles necesitan una puntuación, no un conjunto de piezas.",
		"reward.label.stars_total:5":
				"Primeras 5 estrellas",
		"reward.label.stars_total:15":
				"Hito de 15 estrellas",
		"settings.title": "Ajustes",
		"settings.music": "Música",
		"settings.effects": "Efectos",
		"settings.haptics": "Vibración",
		"settings.language": "Idioma",
	}
	var en_loc := Locale.new("en", "English", "", en_strings)
	var es_loc := Locale.new("es", "Español", "en", es_strings)
	var cat := LocaleCatalog.new(
			{"en": en_loc, "es": es_loc},
			LocaleCatalog.DEFAULT_CODE)
	return cat

## Path to a JSON locale file under res://. Returns null when the
## file is absent or unparseable. Used by the boot loader.
static func load_locale_from_path(path: String) -> Locale:
	if not ResourceLoader.exists(path):
		return null
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	var text: String = f.get_as_text()
	f.close()
	var parsed: Variant = JSON.parse_string(text)
	if not (parsed is Dictionary):
		return null
	return Locale.from_dict(parsed)

## Build a catalog by loading every locale file in a directory. The
## directory is enumerated non-recursively; files matching the
## pattern `<code>.json` become one locale each.
static func load_catalog_from_dir(dir_path: String,
		active_code: String = LocaleCatalog.DEFAULT_CODE) -> LocaleCatalog:
	var locales: Dictionary = {}
	var d := DirAccess.open(dir_path)
	if d == null:
		return LocaleCatalog.new({}, active_code)
	d.list_dir_begin()
	var fname: String = d.get_next()
	while fname != "":
		if not d.current_is_dir() and fname.ends_with(".json"):
			var code: String = fname.substr(0, fname.length() - 5)
			var loc := load_locale_from_path(dir_path + "/" + fname)
			if loc != null and loc.code != "":
				# Honour the on-disk code if the filename disagreed.
				var key: String = loc.code if loc.code != "" else code
				locales[key] = loc
		fname = d.get_next()
	d.list_dir_end()
	if not locales.has(LocaleCatalog.DEFAULT_CODE):
		# Without the default locale the catalog is unusable; build
		# an empty one so callers can detect the misconfig.
		return LocaleCatalog.new({}, active_code)
	if not locales.has(active_code):
		active_code = LocaleCatalog.DEFAULT_CODE
	return LocaleCatalog.new(locales, active_code)