extends GutTest
## Step 18: save data + IO tests.

const SaveData = preload("res://scripts/domain/persistence/save_data.gd")
const SaveIO = preload("res://scripts/domain/persistence/save_io.gd")
const SD = SaveData
const IO = SaveIO

const Save = SD.SaveData
const SaveMetadata = SD.SaveMetadata
const LevelRecord = SD.LevelRecord
const InventoryRecord = SD.InventoryRecord
const SettingsRecord = SD.SettingsRecord
const TutorialFlags = SD.TutorialFlags
const ActiveSession = SD.ActiveSession

func _unique_path(tag: String) -> String:
	# Each test gets its own save location under user:// to avoid
	# cross-test contamination. GUT runs tests serially within a
	# script so this is enough to keep them isolated.
	return "user://test_save_%s_%d.json" % [tag, Time.get_ticks_usec()]

func _make_save() -> Save:
	var data := Save.new()
	data.coins = 100
	data.player_name = "tester"
	data.tutorial.mark("intro")
	var rec := LevelRecord.new("l1-first-match", 250, 3, 1234567, true)
	data.levels[rec.level_id] = rec
	data.inventory.boosters[0] = 2
	return data

# A. Fresh install returns an empty SaveData with safe defaults.

func test_fresh_save_has_safe_defaults() -> void:
	var data := SaveData.fresh_save()
	assert_eq(data.schema_version, SaveData.SAVE_SCHEMA_VERSION)
	assert_eq(data.coins, 0)
	assert_eq(data.player_name, "")
	assert_eq(data.levels.size(), 0)
	assert_not_null(data.inventory)
	assert_not_null(data.settings)
	assert_not_null(data.tutorial)
	assert_not_null(data.active_session)
	assert_true(data.active_session.is_empty())
	assert_true(data.settings.sound_on)
	assert_true(data.settings.music_on)
	assert_eq(data.settings.language, "en")

# B. Validate flags out-of-range stars.

func test_validate_rejects_stars_out_of_range() -> void:
	var data := _make_save()
	var bad := LevelRecord.new("l2", 100, 4, 0, false)  # 4 stars
	data.levels["l2"] = bad
	var errs: Array = SaveData.validate(data)
	assert_true(errs.size() > 0, "must flag out-of-range stars")

# C. Validate flags out-of-range booster inventory.

func test_validate_rejects_inventory_over_cap() -> void:
	var data := _make_save()
	data.inventory.cap_per_kind = 5
	data.inventory.boosters[0] = 99
	var errs: Array = SaveData.validate(data)
	assert_true(errs.size() > 0, "must flag inventory over cap")

# D. Validate flags negative coins.

func test_validate_rejects_negative_coins() -> void:
	var data := _make_save()
	data.coins = -1
	var errs: Array = SaveData.validate(data)
	assert_true(errs.size() > 0, "must flag negative coins")

# E. Roundtrip: to_dict / from_dict preserves all fields.

func test_save_data_roundtrip() -> void:
	var data := _make_save()
	var env: Dictionary = SaveData.to_envelope_dict(data)
	var parsed := SaveData.from_dict(env)
	assert_not_null(parsed)
	assert_eq(parsed.coins, 100)
	assert_eq(parsed.player_name, "tester")
	assert_eq(parsed.levels.size(), 1)
	var rec: LevelRecord = parsed.levels["l1-first-match"]
	assert_eq(rec.stars, 3)
	assert_eq(rec.best_score, 250)
	assert_true(rec.completed_once)
	assert_eq(parsed.inventory.boosters[0], 2)
	assert_true(parsed.tutorial.has_seen("intro"))

# F. Checksum is stable across runs.

func test_checksum_is_stable() -> void:
	var data := _make_save()
	var env: Dictionary = SaveData.to_envelope_dict(data)
	var a: int = SaveData.checksum_of_dict(env)
	var b: int = SaveData.checksum_of_dict(env)
	assert_eq(a, b, "checksum must be deterministic")
	# Different data must produce different checksum.
	var data2 := _make_save()
	data2.coins = 999
	var env2: Dictionary = SaveData.to_envelope_dict(data2)
	var c: int = SaveData.checksum_of_dict(env2)
	assert_ne(a, c, "different data must produce different checksum")

# G. write_atomic + load roundtrips on disk.

func test_write_atomic_then_load_roundtrips() -> void:
	var path := _unique_path("roundtrip")
	var data := _make_save()
	assert_true(SaveIO.write_atomic(data, path, "0.6.0-test", 1000))
	assert_true(FileAccess.file_exists(path))
	var result: SaveIO.IoResult = SaveIO.load(path)
	assert_true(result.ok, "load must succeed: %s" % result.error_message)
	assert_not_null(result.data)
	assert_eq(result.data.coins, 100)
	assert_eq(result.data.player_name, "tester")
	assert_false(result.recovered_from_backup)
	# Cleanup.
	SaveIO.reset(path)

# H. write_atomic rotates the previous primary to backup.

func test_write_atomic_rotates_previous_to_backup() -> void:
	var path := _unique_path("rotate")
	var paths: Dictionary = SaveIO.derive_paths(path)
	# First write.
	var first := _make_save()
	first.coins = 1
	assert_true(SaveIO.write_atomic(first, path, "0.6.0-test", 1))
	# Second write.
	var second := _make_save()
	second.coins = 2
	assert_true(SaveIO.write_atomic(second, path, "0.6.0-test", 2))
	# Backup must exist and reflect the FIRST save.
	assert_true(FileAccess.file_exists(paths["backup"]))
	var backup_result: SaveIO.IoResult = SaveIO.load(paths["backup"])
	assert_true(backup_result.ok)
	assert_eq(backup_result.data.coins, 1, "backup must hold the previous save")
	# Primary must reflect the SECOND save.
	var primary_result: SaveIO.IoResult = SaveIO.load(path)
	assert_true(primary_result.ok)
	assert_eq(primary_result.data.coins, 2)
	SaveIO.reset(path)

# I. Corrupt primary recovers from backup.

func test_corrupt_primary_recovers_from_backup() -> void:
	var path := _unique_path("corrupt")
	var paths: Dictionary = SaveIO.derive_paths(path)
	# Write a good first save.
	var first := _make_save()
	first.coins = 1
	assert_true(SaveIO.write_atomic(first, path, "0.6.0-test", 1))
	# Write a SECOND save so the backup is rotated to the FIRST.
	var second := _make_save()
	second.coins = 2
	assert_true(SaveIO.write_atomic(second, path, "0.6.0-test", 2))
	# Now corrupt the primary by writing garbage.
	var fa := FileAccess.open(path, FileAccess.WRITE)
	assert_not_null(fa)
	fa.store_string("this is not json")
	fa.flush()
	fa.close()
	# Load must succeed and recover from the backup (the first save).
	var result: SaveIO.IoResult = SaveIO.load(path)
	assert_true(result.ok, "load must recover from backup: %s" % result.error_message)
	assert_true(result.recovered_from_backup,
			"load must report backup recovery")
	assert_eq(result.data.coins, 1,
			"recovered save must be the rotated backup (first save)")
	SaveIO.reset(path)

# J. No save on disk returns a failure result.

func test_load_with_no_save_returns_failure() -> void:
	var path := _unique_path("empty")
	SaveIO.reset(path)
	var result: SaveIO.IoResult = SaveIO.load(path)
	assert_false(result.ok)
	assert_null(result.data)

# K. Fresh install: has_save() returns false when nothing exists.

func test_has_save_returns_false_on_fresh_install() -> void:
	var path := _unique_path("fresh")
	SaveIO.reset(path)
	assert_false(SaveIO.has_save(path))
	var data := _make_save()
	SaveIO.write_atomic(data, path, "0.6.0-test", 1)
	assert_true(SaveIO.has_save(path))
	SaveIO.reset(path)

# L. Reset removes both primary and backup.

func test_reset_removes_primary_and_backup() -> void:
	var path := _unique_path("reset")
	var first := _make_save()
	SaveIO.write_atomic(first, path, "0.6.0-test", 1)
	var second := _make_save()
	second.coins = 999
	SaveIO.write_atomic(second, path, "0.6.0-test", 2)
	SaveIO.reset(path)
	assert_false(SaveIO.has_save(path))

# M. Migration: a save with the current version passes through unchanged.

func test_migrate_passes_through_current_version() -> void:
	var data := _make_save()
	var env: Dictionary = SaveData.to_envelope_dict(data)
	var out: Dictionary = SaveData.migrate(env)
	assert_eq(int(out.get("schema_version", 0)), SaveData.SAVE_SCHEMA_VERSION)
	assert_eq(int(out.get("coins", -1)), 100)

# N. Migration: a save from a newer schema is rejected.

func test_migrate_rejects_newer_schema() -> void:
	var data := _make_save()
	var env: Dictionary = SaveData.to_envelope_dict(data)
	env["schema_version"] = SaveData.SAVE_SCHEMA_VERSION + 100
	var errs: Array = []
	var out: Dictionary = SaveData.migrate(env, errs)
	assert_true(errs.size() > 0, "newer schema must be flagged")
	assert_eq(int(out.get("schema_version", 0)), SaveData.SAVE_SCHEMA_VERSION + 100)

# O. write_count increments on every successful write.

func test_write_count_increments() -> void:
	var path := _unique_path("wcount")
	var data := _make_save()
	SaveIO.write_atomic(data, path, "0.6.0-test", 1)
	assert_eq(data.write_count, 1)
	SaveIO.write_atomic(data, path, "0.6.0-test", 2)
	assert_eq(data.write_count, 2)
	SaveIO.write_atomic(data, path, "0.6.0-test", 3)
	assert_eq(data.write_count, 3)
	SaveIO.reset(path)

# P. Load returns the latest write_count.

func test_load_returns_latest_write_count() -> void:
	var path := _unique_path("wcountload")
	var data := _make_save()
	SaveIO.write_atomic(data, path, "0.6.0-test", 1)
	SaveIO.write_atomic(data, path, "0.6.0-test", 2)
	var result: SaveIO.IoResult = SaveIO.load(path)
	assert_true(result.ok)
	assert_eq(result.data.write_count, 2)
	SaveIO.reset(path)

# Q. Save with empty active_session roundtrips.

func test_save_roundtrips_empty_active_session() -> void:
	var data := _make_save()
	var env: Dictionary = SaveData.to_envelope_dict(data)
	var parsed := SaveData.from_dict(env)
	assert_not_null(parsed)
	assert_true(parsed.active_session.is_empty())

# R. Save with active session roundtrips a snapshot.

func test_save_roundtrips_active_session() -> void:
	var data := _make_save()
	data.active_session = ActiveSession.new("l1-first-match",
			{"state": 1, "score": 42}, 9999)
	var env: Dictionary = SaveData.to_envelope_dict(data)
	var parsed := SaveData.from_dict(env)
	assert_not_null(parsed)
	assert_false(parsed.active_session.is_empty())
	assert_eq(parsed.active_session.recipe_id, "l1-first-match")
	assert_eq(parsed.active_session.saved_at, 9999)
	assert_eq(int(parsed.active_session.snapshot["score"]), 42)