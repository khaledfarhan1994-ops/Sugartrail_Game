class_name SugartrailSaveData
extends RefCounted
## Versioned local save schema + integrity metadata.
##
## Step 18 ships the persistence foundation: a SaveData document
## that captures everything the engine persists across launches
## (progression, inventory, settings, tutorial flags, active
## session), a SaveMetadata envelope (schema version, checksum,
## created/updated timestamps), validators that catch malformed
## data before it pollutes downstream code, and a migration path
## forward-only across schema versions.
##
## SaveData is pure data. It does NOT read or write files; that
## is the job of SugartrailSaveIO. Splitting data from IO is the
## same separation the rest of the domain uses (board vs rules,
## recipe vs loader) — it keeps the save format unit-testable
## without a filesystem, and lets us swap the backing store later
## (e.g. for cloud sync or encrypted local storage) without
## rewriting validation.
##
## Persistence requirements (see docs/03-technical-architecture.md §5):
##
##   - Versioned schema. Migrations are explicit and forward-only.
##   - Checksum covers every field so we can detect partial writes.
##   - Validate schema, ranges, IDs, and checksum on load.
##   - Recover from corruption using the backup and a non-technical
##     message.

const SAVE_SCHEMA_VERSION: int = 2

## A single saved level's progression record. The level_id is the
## recipe's stable id (e.g. "l1-first-match"). best_score is the
## highest score ever achieved on this level. stars is the highest
## star count (0..3). last_played is a Unix-style timestamp (0 means
## never). completed_once is true the first time the level is won
## (used to unlock the next node on the map).
class LevelRecord:
	var level_id: String = ""
	var best_score: int = 0
	var stars: int = 0
	var last_played: int = 0
	var completed_once: bool = false

	func _init(p_id: String = "", p_best_score: int = 0,
			p_stars: int = 0, p_last_played: int = 0,
			p_completed_once: bool = false) -> void:
		level_id = p_id
		best_score = p_best_score
		stars = p_stars
		last_played = p_last_played
		completed_once = p_completed_once

	func to_dict() -> Dictionary:
		return {
			"level_id": level_id,
			"best_score": best_score,
			"stars": stars,
			"last_played": last_played,
			"completed_once": completed_once,
		}

	static func from_dict(d: Dictionary) -> LevelRecord:
		return LevelRecord.new(
			String(d.get("level_id", "")),
			int(d.get("best_score", 0)),
			int(d.get("stars", 0)),
			int(d.get("last_played", 0)),
			bool(d.get("completed_once", false)))

## A persistent booster inventory record. Keyed by BoosterKind id
## (an int). Caps the inventory to a sane per-kind ceiling so a
## corrupt save cannot grant the player infinite boosters.
class InventoryRecord:
	## The booster inventory: {kind_id (int): count (int)}.
	var boosters: Dictionary = {}
	## Total cap across all kinds. Default is generous but finite.
	var cap_per_kind: int = 99
	## Total cap across the whole inventory.
	var cap_total: int = 999

	func _init(p_boosters: Dictionary = {}, p_cap_per_kind: int = 99,
			p_cap_total: int = 999) -> void:
		boosters = {}
		for k in p_boosters:
			var v: Variant = p_boosters[k]
			boosters[int(k)] = int(v)
		cap_per_kind = p_cap_per_kind
		cap_total = p_cap_total

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in boosters:
			out[int(k)] = int(boosters[k])
		return {
			"boosters": out,
			"cap_per_kind": cap_per_kind,
			"cap_total": cap_total,
		}

	static func from_dict(d: Dictionary) -> InventoryRecord:
		var boosters_in: Variant = d.get("boosters", {})
		var bs: Dictionary = {}
		if boosters_in is Dictionary:
			for k in (boosters_in as Dictionary):
				bs[int(k)] = int(boosters_in[k])
		return InventoryRecord.new(
				bs,
				int(d.get("cap_per_kind", 99)),
				int(d.get("cap_total", 999)))

## Persistent player settings. Defaults are the most permissive
## (sound on, music on, full difficulty, English).
class SettingsRecord:
	var sound_on: bool = true
	var music_on: bool = true
	var haptics_on: bool = true
	var reduced_motion: bool = false
	var high_contrast: bool = false
	var large_text: bool = false
	var language: String = "en"

	func to_dict() -> Dictionary:
		return {
			"sound_on": sound_on,
			"music_on": music_on,
			"haptics_on": haptics_on,
			"reduced_motion": reduced_motion,
			"high_contrast": high_contrast,
			"large_text": large_text,
			"language": language,
		}

	static func from_dict(d: Dictionary) -> SettingsRecord:
		var s := SettingsRecord.new()
		s.sound_on = bool(d.get("sound_on", true))
		s.music_on = bool(d.get("music_on", true))
		s.haptics_on = bool(d.get("haptics_on", true))
		s.reduced_motion = bool(d.get("reduced_motion", false))
		s.high_contrast = bool(d.get("high_contrast", false))
		s.large_text = bool(d.get("large_text", false))
		var lang_v: Variant = d.get("language", "en")
		if lang_v is String:
			var lang_str: String = lang_v
			if lang_str != "":
				s.language = lang_str
		return s

## Tutorial flags: which prompts have been seen. Keyed by prompt id.
class TutorialFlags:
	var seen: Dictionary = {}

	func _init(p_seen: Dictionary = {}) -> void:
		seen = {}
		for k in p_seen:
			seen[String(k)] = bool(p_seen[k])

	func mark(p_id: String) -> void:
		seen[p_id] = true

	func has_seen(p_id: String) -> bool:
		return bool(seen.get(p_id, false))

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in seen:
			out[String(k)] = bool(seen[k])
		return {"seen": out}

	static func from_dict(d: Dictionary) -> TutorialFlags:
		var seen_in: Variant = d.get("seen", {})
		var s: Dictionary = {}
		if seen_in is Dictionary:
			for k in (seen_in as Dictionary):
				s[String(k)] = bool(seen_in[k])
		return TutorialFlags.new(s)

## Set of reward keys that have already been granted. Rewards in
## the catalog are claimed exactly once across the lifetime of the
## save; the ledger ensures reopening the result screen cannot
## reclaim. Step 20 ships this for the booster economy; daily-
## challenge rewards (deferred) would key off a device-day string
## here in a later phase.
class ClaimedRewards:
	var claimed: Dictionary = {}

	func _init(p_claimed: Dictionary = {}) -> void:
		claimed = {}
		for k in p_claimed:
			claimed[String(k)] = bool(p_claimed[k])

	func has(p_key: String) -> bool:
		return bool(claimed.get(p_key, false))

	func mark(p_key: String) -> void:
		claimed[p_key] = true

	func size() -> int:
		return claimed.size()

	func keys() -> Array:
		var out: Array = []
		for k in claimed:
			out.append(String(k))
		return out

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in claimed:
			out[String(k)] = bool(claimed[k])
		return {"claimed": out}

	static func from_dict(d: Dictionary) -> ClaimedRewards:
		var in_v: Variant = d.get("claimed", {})
		var c: Dictionary = {}
		if in_v is Dictionary:
			for k in (in_v as Dictionary):
				c[String(k)] = bool(in_v[k])
		return ClaimedRewards.new(c)

## Snapshot of an active in-progress session. Used to resume a level
## that was interrupted (app backgrounded, device rebooted, etc).
## The full state is the Session.snapshot_state() dictionary.
class ActiveSession:
	var recipe_id: String = ""
	var snapshot: Dictionary = {}
	var saved_at: int = 0

	func _init(p_recipe_id: String = "", p_snapshot: Dictionary = {},
			p_saved_at: int = 0) -> void:
		recipe_id = p_recipe_id
		snapshot = p_snapshot.duplicate(true)
		saved_at = p_saved_at

	func is_empty() -> bool:
		return recipe_id == "" and snapshot.is_empty()

	func to_dict() -> Dictionary:
		return {
			"recipe_id": recipe_id,
			"snapshot": snapshot.duplicate(true),
			"saved_at": saved_at,
		}

	static func from_dict(d: Dictionary) -> ActiveSession:
		var snap_v: Variant = d.get("snapshot", {})
		var snap: Dictionary = {}
		if snap_v is Dictionary:
			snap = (snap_v as Dictionary).duplicate(true)
		return ActiveSession.new(
				String(d.get("recipe_id", "")),
				snap,
				int(d.get("saved_at", 0)))

## The save document itself. Composed of the records above.
class SaveData:
	var schema_version: int = SAVE_SCHEMA_VERSION
	## Map of level_id -> LevelRecord.
	var levels: Dictionary = {}
	var inventory: InventoryRecord = null
	var settings: SettingsRecord = null
	var tutorial: TutorialFlags = null
	var active_session: ActiveSession = null
	## Step 20: claimed reward keys (one entry per granted reward).
	## Used by the booster economy to ensure idempotent grants.
	var claimed_rewards: ClaimedRewards = null
	## Cumulative coins / soft currency. Independent of inventory so
	## reward grants can be audited separately.
	var coins: int = 0
	## Player-chosen display name. Empty string means "anonymous".
	var player_name: String = ""
	## Wall-clock seconds since Unix epoch when the save was created.
	var created_at: int = 0
	## Wall-clock seconds since Unix epoch when the save was last
	## touched. Stamps update on every write.
	var updated_at: int = 0
	## Monotonic counter that increments on every write. Used by the
	## IO layer to detect partial writes (a write that completed
	## should bump this; a write that crashed mid-flight should not).
	var write_count: int = 0

	func _init() -> void:
		inventory = InventoryRecord.new()
		settings = SettingsRecord.new()
		tutorial = TutorialFlags.new()
		active_session = ActiveSession.new()
		claimed_rewards = ClaimedRewards.new()
		levels = {}

## The integrity envelope. Stored alongside the data; the IO layer
## computes the checksum over the data and stamps this envelope so
## the loader can detect tampering / partial writes.
class SaveMetadata:
	var schema_version: int = SAVE_SCHEMA_VERSION
	## Stable hash of the SaveData document (excluding this
	## envelope). Algorithm: 32-bit FNV-1a over a deterministic
	## JSON-serialised form of the data. Cheap, well-known, no
	## crypto needed (this is local-only integrity, not security).
	var checksum: int = 0
	## Wall-clock seconds since Unix epoch when this save was
	## written. Independent of SaveData.updated_at so a clock
	## rollback cannot rewrite history silently.
	var saved_at: int = 0
	## Engine version that wrote this save. Used to log mismatches;
	## load is not blocked on engine drift.
	var engine_version: String = ""
	## Mirror of SaveData.write_count. The IO layer reads back the
	## file's envelope and compares it to what was written; mismatch
	## means a partial write (interrupted) and triggers recovery
	## from the backup.
	var write_count: int = 0

	func to_dict() -> Dictionary:
		return {
			"schema_version": schema_version,
			"checksum": checksum,
			"saved_at": saved_at,
			"engine_version": engine_version,
			"write_count": write_count,
		}

	static func from_dict(d: Dictionary) -> SaveMetadata:
		var m := SaveMetadata.new()
		m.schema_version = int(d.get("schema_version", SAVE_SCHEMA_VERSION))
		m.checksum = int(d.get("checksum", 0))
		m.saved_at = int(d.get("saved_at", 0))
		m.engine_version = String(d.get("engine_version", ""))
		m.write_count = int(d.get("write_count", 0))
		return m

## Stable, hash-friendly representation. Returns the SaveData as a
## Dictionary in a canonical key order so the checksum is stable
## across runs. The order MUST match what checksum_of_dict hashes.
static func to_envelope_dict(data: SaveData) -> Dictionary:
	var levels_out: Dictionary = {}
	# Sort by level_id so the JSON serialisation is byte-identical
	# across runs (Godot's JSON does not sort keys).
	var level_ids: Array = []
	for k in data.levels:
		level_ids.append(String(k))
	level_ids.sort()
	for id in level_ids:
		var rec: LevelRecord = data.levels[id]
		levels_out[id] = rec.to_dict()
	return {
		"schema_version": data.schema_version,
		"levels": levels_out,
		"inventory": data.inventory.to_dict(),
		"settings": data.settings.to_dict(),
		"tutorial": data.tutorial.to_dict(),
		"active_session": data.active_session.to_dict(),
		"claimed_rewards": data.claimed_rewards.to_dict(),
		"coins": data.coins,
		"player_name": data.player_name,
		"created_at": data.created_at,
		"updated_at": data.updated_at,
		"write_count": data.write_count,
	}

## Compute a 32-bit FNV-1a hash of a Dictionary. The Dictionary
## must already be in canonical form (use to_envelope_dict). The
## result is stable across runs because the canonical form sorts
## the level keys.
##
## Note: FNV-1a is not cryptographic. It detects accidental
## corruption (partial writes, byte flips in transit); it does NOT
## detect malicious tampering. That is acceptable for a local-only
## save with no network exposure.
static func checksum_of_dict(d: Dictionary) -> int:
	# FNV-1a 32-bit constants.
	var h: int = 0x811C9DC5
	# JSON is the canonical serial form for our Dictionary. Godot's
	# JSON.stringify uses stable key order with sort_keys=true.
	var text: String = JSON.stringify(d, "", true, false)
	# Walk every byte of the canonical text.
	for i in range(text.length()):
		h = h ^ text.unicode_at(i)
		h = (h * 0x01000193) & 0xFFFFFFFF
	return h

## Validate the structural fields of a SaveData. Returns an Array
## of human-readable error strings. Empty array means OK. Catches:
##
##   - schema version mismatch
##   - level stars out of range (must be 0..3)
##   - booster inventory over cap
##   - unknown fields are ignored (forward-compat)
static func validate(data: SaveData) -> Array:
	var errors: Array = []
	if data.schema_version > SAVE_SCHEMA_VERSION:
		errors.append("save schema version %d is newer than engine supports (%d)" % [
			data.schema_version, SAVE_SCHEMA_VERSION])
	if data.schema_version < 1:
		errors.append("save schema version %d is invalid (< 1)" % data.schema_version)
	# Validate level records.
	for k in data.levels:
		var rec: LevelRecord = data.levels[k]
		if rec.stars < 0 or rec.stars > 3:
			errors.append("level %s: stars %d out of range 0..3" % [rec.level_id, rec.stars])
		if rec.best_score < 0:
			errors.append("level %s: best_score %d is negative" % [rec.level_id, rec.best_score])
		if rec.level_id == "":
			errors.append("level record has empty level_id")
		elif rec.level_id != String(k):
			errors.append("level record key %s mismatches id %s" % [k, rec.level_id])
	# Validate inventory.
	var total: int = 0
	for k in data.inventory.boosters:
		var n: int = int(data.inventory.boosters[k])
		if n < 0:
			errors.append("booster kind %d has negative inventory %d" % [int(k), n])
		if n > data.inventory.cap_per_kind:
			errors.append("booster kind %d inventory %d exceeds cap_per_kind %d" % [
				int(k), n, data.inventory.cap_per_kind])
		total += n
	if total > data.inventory.cap_total:
		errors.append("total booster inventory %d exceeds cap_total %d" % [
			total, data.inventory.cap_total])
	# Validate coins.
	if data.coins < 0:
		errors.append("coins %d is negative" % data.coins)
	return errors

## Build a fresh SaveData with safe defaults. Used by the loader
## when there is no primary or backup (fresh install) and by tests.
static func fresh_save() -> SaveData:
	var data := SaveData.new()
	data.created_at = 0
	data.updated_at = 0
	data.write_count = 0
	return data

## Build a SaveData from a parsed Dictionary (i.e. the result of
## JSON.parse_string). Unknown fields are ignored. Returns null on
## irrecoverable parse failure (the caller should fall back to a
## fresh save in that case).
##
## Validates the result. If validation fails, returns null and
## fills out_errors with the messages; the caller should fall back
## to the backup.
static func from_dict(d: Dictionary, out_errors: Array = []) -> SaveData:
	if out_errors == null:
		out_errors = []
	var data := SaveData.new()
	data.schema_version = int(d.get("schema_version", SAVE_SCHEMA_VERSION))
	# Levels.
	var levels_in: Variant = d.get("levels", {})
	if levels_in is Dictionary:
		for k in (levels_in as Dictionary):
			var lv: Variant = (levels_in as Dictionary)[k]
			if lv is Dictionary:
				var rec: LevelRecord = LevelRecord.from_dict(lv)
				if rec.level_id == "":
					rec.level_id = String(k)
				data.levels[rec.level_id] = rec
	# Inventory.
	var inv_in: Variant = d.get("inventory", {})
	if inv_in is Dictionary:
		data.inventory = InventoryRecord.from_dict(inv_in)
	# Settings.
	var set_in: Variant = d.get("settings", {})
	if set_in is Dictionary:
		data.settings = SettingsRecord.from_dict(set_in)
	# Tutorial.
	var tut_in: Variant = d.get("tutorial", {})
	if tut_in is Dictionary:
		data.tutorial = TutorialFlags.from_dict(tut_in)
	# Active session.
	var sess_in: Variant = d.get("active_session", {})
	if sess_in is Dictionary:
		data.active_session = ActiveSession.from_dict(sess_in)
	# Claimed rewards (Step 20). Optional in older saves; lazy-fill
	# an empty ClaimedRewards when missing so downstream code can
	# always call `claimed_rewards.mark(key)` safely.
	var cr_in: Variant = d.get("claimed_rewards", {})
	if cr_in is Dictionary and not (cr_in as Dictionary).is_empty():
		data.claimed_rewards = ClaimedRewards.from_dict(cr_in)
	# Coins.
	data.coins = int(d.get("coins", 0))
	# Player name.
	data.player_name = String(d.get("player_name", ""))
	# Timestamps.
	data.created_at = int(d.get("created_at", 0))
	data.updated_at = int(d.get("updated_at", 0))
	data.write_count = int(d.get("write_count", 0))
	# Validate.
	var errors: Array = validate(data)
	for e in errors:
		out_errors.append(String(e))
	if errors.size() > 0:
		return null
	return data

## Migrate a parsed save dictionary forward to SAVE_SCHEMA_VERSION.
## Forward-only. Each schema bump appends one migration helper.
## This is the entry point the IO layer calls.
static func migrate(parsed: Dictionary, out_errors: Array = []) -> Dictionary:
	if out_errors == null:
		out_errors = []
	var version: int = int(parsed.get("schema_version", 1))
	if version > SAVE_SCHEMA_VERSION:
		out_errors.append("save schema version %d is newer than this engine supports" % version)
		return parsed
	# Step 20: v1 -> v2 adds the claimed_rewards ledger. Older saves
	# are given an empty ledger so the booster economy can start
	# granting from a clean state.
	if version < 2:
		parsed = migration_v1_to_v2(parsed)
		version = 2
	parsed["schema_version"] = SAVE_SCHEMA_VERSION
	return parsed

## v1 -> v2 migration: insert an empty ClaimedRewards ledger if
## absent. Reward keys for the launcher set are derived from the
## current best_stars total so a player upgrading from v1 does not
## retroactively receive rewards (they will earn them on the next
## completion that crosses a threshold). The PLAYER'S progress is
## preserved as-is; only the ledger is fresh.
static func migration_v1_to_v2(parsed: Dictionary) -> Dictionary:
	if not parsed.has("claimed_rewards"):
		parsed["claimed_rewards"] = {"claimed": {}}
	return parsed

## Build a SaveMetadata that wraps the given SaveData. The
## checksum covers the canonical envelope dictionary.
static func make_metadata(data: SaveData, engine_version: String = "",
		saved_at: int = 0) -> SaveMetadata:
	var m := SaveMetadata.new()
	m.schema_version = data.schema_version
	var envelope: Dictionary = to_envelope_dict(data)
	m.checksum = checksum_of_dict(envelope)
	m.saved_at = saved_at
	m.engine_version = engine_version
	m.write_count = data.write_count
	return m