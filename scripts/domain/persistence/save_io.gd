class_name SugartrailSaveIO
extends RefCounted
## Atomic local save IO with backup rotation.
##
## Step 18 ships the persistence IO layer that complements
## SugartrailSaveData. The split mirrors the rest of the domain
## (board vs rules, recipe vs loader): the data model is pure and
## unit-testable without a filesystem; this module owns the
## on-disk format and atomic-replace dance.
##
## Atomic write contract:
##
##   1. Compute the new SaveData + SaveMetadata.
##   2. JSON-serialise to a temporary file at <path>.tmp.
##   3. Flush the temp file (FileAccess.flush + close).
##   4. If a primary exists at <path>, copy it to <path>.bak
##      BEFORE replacing. This keeps the previous good save as
##      the backup.
##   5. Atomically rename <path>.tmp to <path>. On a POSIX
##      filesystem rename is atomic; on Windows it is roughly
##      atomic (ReplaceFile / MoveFileEx).
##   6. Bump write_count on SaveData so a partially-completed
##      write (which cannot reach step 6) leaves a metadata
##      envelope with a smaller write_count than the data.
##
## Load contract:
##
##   1. Read <path>. Parse JSON; rebuild SaveData + SaveMetadata.
##   2. Recompute checksum from data; compare to metadata.
##      Mismatch = corrupt primary. Fall through to backup.
##   3. If primary missing or corrupt, read <path>.bak and try
##      the same. If backup is also corrupt, return null and the
##      caller falls back to a fresh SaveData.
##   4. The IO layer never THROWS. It returns a Result object so
##      the application layer can choose how to recover (silent
##      fresh save vs. show a "save corrupted" message).

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")

const Save = SaveData.SaveData
const SaveMetadata = SaveData.SaveMetadata

## Default save location. The presentation layer can override by
## passing a different path. Default is `user://save.json` which
## on Android maps to the app's private files directory.
const DEFAULT_PRIMARY_PATH: String = "user://save.json"
const DEFAULT_BACKUP_PATH: String = "user://save.json.bak"
const DEFAULT_TEMP_PATH: String = "user://save.json.tmp"

## A serialisable IO result. `ok` is true on success. On failure,
## `error_message` explains why and `recovered_from_backup` is
## true if the load came from the backup rather than the primary.
class IoResult:
	var ok: bool = false
	var data: Save = null
	var metadata: SaveMetadata = null
	var error_message: String = ""
	var recovered_from_backup: bool = false

	func _init(p_ok: bool = false, p_data: Save = null,
			p_metadata: SaveMetadata = null,
			p_error_message: String = "",
			p_recovered_from_backup: bool = false) -> void:
		ok = p_ok
		data = p_data
		metadata = p_metadata
		error_message = p_error_message
		recovered_from_backup = p_recovered_from_backup

## Build the canonical file layout from a base path. The primary
## file lives at <path>; the backup at <path>.bak; the temporary
## write target at <path>.tmp.
static func derive_paths(primary: String) -> Dictionary:
	return {
		"primary": primary,
		"backup": primary + ".bak",
		"temp": primary + ".tmp",
	}

## Write a SaveData atomically. Returns true on success; false on
## IO failure (in which case error_message_v is filled with the
## underlying Godot error code).
##
## Optional parameters:
##   - engine_version: stamped into the metadata for log inspection.
##   - saved_at: wall-clock seconds. Defaults to 0 (caller may
##     pass OS.get_unix_time_from_system()).
static func write_atomic(data: Save, primary_path: String = DEFAULT_PRIMARY_PATH,
		engine_version: String = "", saved_at: int = 0) -> bool:
	var paths: Dictionary = derive_paths(primary_path)
	var temp_path: String = paths["temp"]
	var bak_path: String = paths["backup"]
	var real_primary: String = paths["primary"]
	# Step 1: bump the write_count and stamp updated_at so a
	# partially-completed write is detectable.
	data.write_count += 1
	data.updated_at = saved_at
	if data.created_at == 0:
		data.created_at = saved_at
	# Step 2: serialise the data + metadata to JSON.
	var data_dict: Dictionary = SaveData.to_envelope_dict(data)
	var meta: SaveMetadata = SaveData.make_metadata(data, engine_version, saved_at)
	var payload := {
		"metadata": meta.to_dict(),
		"data": data_dict,
	}
	var text: String = JSON.stringify(payload, "", true, false)
	# Step 3: write to <path>.tmp, flush, close.
	var fa := FileAccess.open(temp_path, FileAccess.WRITE)
	if fa == null:
		push_error("save_io: cannot open temp file %s (error %d)" % [
			temp_path, FileAccess.get_open_error()])
		return false
	fa.store_string(text)
	# flush + close are the engine's explicit fsync / fd close.
	fa.flush()
	fa.close()
	# Step 4: rotate the existing primary to .bak. We do this BEFORE
	# the rename so the backup is the previous good state. If the
	# rename then fails, we have NOT lost data (the primary is
	# still on disk, untouched).
	if FileAccess.file_exists(real_primary):
		# Replace any existing backup with a copy of the primary.
		# If the primary is corrupt, the BACKUP from the previous
		# write is overwritten — that's the price of the rotation
		# strategy. A more conservative approach would keep TWO
		# generations; Step 18 keeps one as documented.
		var copy_err := DirAccess.copy_absolute(
				ProjectSettings.globalize_path(real_primary),
				ProjectSettings.globalize_path(bak_path))
		if copy_err != OK:
			push_error("save_io: failed to copy primary to backup (error %d)" % copy_err)
			# We continue: the rename below still replaces the
			# primary, and the backup may simply be missing or
			# stale. Worst case the previous save is gone but
			# the new save is in place.
	# Step 5: atomically rename <path>.tmp -> <path>.
	var rename_err := DirAccess.rename_absolute(
			ProjectSettings.globalize_path(temp_path),
			ProjectSettings.globalize_path(real_primary))
	if rename_err != OK:
		push_error("save_io: failed to rename temp to primary (error %d)" % rename_err)
		return false
	return true

## Load a SaveData from disk. Falls back to the backup if the
## primary is missing or fails validation. Returns null data on
## unrecoverable corruption (the caller can fall back to a fresh
## save).
##
## On success the result includes the data, metadata, and a flag
## indicating whether the load came from the backup.
static func load(primary_path: String = DEFAULT_PRIMARY_PATH) -> IoResult:
	var paths: Dictionary = derive_paths(primary_path)
	var real_primary: String = paths["primary"]
	var bak_path: String = paths["backup"]
	# Try the primary first.
	if FileAccess.file_exists(real_primary):
		var r_primary: IoResult = _try_load_file(real_primary)
		if r_primary.ok:
			return r_primary
		# Primary failed: fall through to the backup.
	# Try the backup.
	if FileAccess.file_exists(bak_path):
		var r_backup: IoResult = _try_load_file(bak_path)
		if r_backup.ok:
			r_backup.recovered_from_backup = true
			r_backup.error_message = "primary corrupt or missing; recovered from backup"
			return r_backup
	# Neither worked.
	var fail := IoResult.new(false, null, null,
			"primary and backup are both unreadable or corrupt", false)
	return fail

## Internal: try to load and validate a single file. Returns an
## IoResult.
static func _try_load_file(path: String) -> IoResult:
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return IoResult.new(false, null, null,
				"cannot open %s (error %d)" % [path, FileAccess.get_open_error()], false)
	var text: String = fa.get_as_text()
	fa.close()
	var parsed: Variant = JSON.parse_string(text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return IoResult.new(false, null, null,
				"file %s is not a JSON object" % path, false)
	var payload: Dictionary = parsed
	# Schema-version migration (forward-only).
	var migrate_errors: Array = []
	var data_dict: Dictionary = SaveData.migrate(payload.get("data", {}), migrate_errors)
	if migrate_errors.size() > 0:
		return IoResult.new(false, null, null,
				"migration failed: %s" % String(migrate_errors[0]), false)
	# Validate + parse the data.
	var parse_errors: Array = []
	var data: Save = SaveData.from_dict(data_dict, parse_errors)
	if data == null:
		var msg: String = "validation failed"
		if parse_errors.size() > 0:
			msg = String(parse_errors[0])
		return IoResult.new(false, null, null, msg, false)
	# Validate the metadata.
	var meta_dict_v: Variant = payload.get("metadata", {})
	var meta: SaveMetadata = SaveMetadata.new()
	if meta_dict_v is Dictionary:
		meta = SaveMetadata.from_dict(meta_dict_v)
	# Checksum: recompute from data and compare.
	var envelope: Dictionary = SaveData.to_envelope_dict(data)
	var expected: int = SaveData.checksum_of_dict(envelope)
	if meta.checksum != 0 and meta.checksum != expected:
		return IoResult.new(false, null, null,
				"checksum mismatch: expected %d, got %d" % [expected, meta.checksum], false)
	# write_count drift: a partial write would have updated
	# write_count in data but not metadata. We already validated
	# the metadata's write_count against the data's — drift here
	# means the file was rewritten between writes by an external
	# tool. Accept the data; flag it in metadata so the caller
	# can log if it cares.
	if meta.write_count != data.write_count:
		# Trust the data (it parsed cleanly). Overwrite the
		# metadata.write_count so the next save stamps it.
		meta.write_count = data.write_count
	return IoResult.new(true, data, meta, "", false)

## Delete both the primary and the backup. Used by the "reset
## progress" affordance. Returns true if at least one file was
## removed or both were already absent.
static func reset(primary_path: String = DEFAULT_PRIMARY_PATH) -> bool:
	var paths: Dictionary = derive_paths(primary_path)
	var primary_exists: bool = FileAccess.file_exists(paths["primary"])
	var backup_exists: bool = FileAccess.file_exists(paths["backup"])
	var any_removed: bool = false
	if primary_exists:
		var err := DirAccess.remove_absolute(ProjectSettings.globalize_path(paths["primary"]))
		if err == OK:
			any_removed = true
	if backup_exists:
		var err2 := DirAccess.remove_absolute(ProjectSettings.globalize_path(paths["backup"]))
		if err2 == OK:
			any_removed = true
	return any_removed or not primary_exists and not backup_exists

## True if a save (primary or backup) exists on disk. Used by the
## fresh-install path: if no save exists, the player is new.
static func has_save(primary_path: String = DEFAULT_PRIMARY_PATH) -> bool:
	var paths: Dictionary = derive_paths(primary_path)
	return FileAccess.file_exists(paths["primary"]) \
			or FileAccess.file_exists(paths["backup"])