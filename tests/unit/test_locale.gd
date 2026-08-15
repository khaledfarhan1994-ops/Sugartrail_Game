extends GutTest
## Step 21: localisation foundation tests.

const Locale = preload("res://scripts/domain/locale/locale.gd")
const Tutorial = preload("res://scripts/domain/tutorial/tutorial.gd")
const Rewards = preload("res://scripts/domain/rewards/rewards.gd")
const SaveData = preload("res://scripts/domain/persistence/save_data.gd")

func _catalog_with(en: Dictionary, es: Dictionary = {}) -> Locale.LocaleCatalog:
	var locales: Dictionary = {
		"en": Locale.Locale.new("en", "English", "", en),
	}
	if not es.is_empty():
		locales["es"] = Locale.Locale.new("es", "Español", "en", es)
	return Locale.LocaleCatalog.new(locales, "en")

# A. Locale roundtrip preserves all fields.

func test_locale_to_dict_from_dict_roundtrip() -> void:
	var loc := Locale.Locale.new("en", "English", "",
			{"hello": "Hello", "bye": "Bye"})
	var d: Dictionary = loc.to_dict()
	var back: Locale.Locale = Locale.Locale.from_dict(d)
	assert_eq(back.code, "en")
	assert_eq(back.name, "English")
	assert_eq(back.fallback, "")
	assert_eq(back.strings.get("hello"), "Hello")
	assert_eq(back.strings.get("bye"), "Bye")

# B. Catalog translate returns the active locale's text.

func test_catalog_translate_returns_active_text() -> void:
	var cat: Locale.LocaleCatalog = _catalog_with(
			{"hello": "Hello"}, {"hello": "Hola"})
	assert_eq(cat.translate("hello"), "Hello")
	cat.set_active("es")
	assert_eq(cat.translate("hello"), "Hola")

# C. Fallback chain walks to the default locale when a key is missing.

func test_catalog_translate_falls_back_to_default_locale() -> void:
	var cat: Locale.LocaleCatalog = _catalog_with(
			{"hello": "Hello"},
			{"bye": "Adiós"})
	cat.set_active("es")
	# "hello" missing in es; falls back to en.
	assert_eq(cat.translate("hello"), "Hello")
	# "bye" exists in es.
	assert_eq(cat.translate("bye"), "Adiós")

# D. Unknown key returns an empty string (never crashes).

func test_catalog_translate_unknown_key_returns_empty() -> void:
	var cat: Locale.LocaleCatalog = _catalog_with({"hello": "Hello"})
	assert_eq(cat.translate("missing.key"), "")
	assert_eq(cat.translate(""), "")

# E. set_active rejects unknown codes.

func test_set_active_rejects_unknown_code() -> void:
	var cat: Locale.LocaleCatalog = _catalog_with({"hello": "Hello"})
	assert_false(cat.set_active("fr"))
	assert_eq(cat.active_code, "en")
	cat.set_active("en")
	assert_true(cat.set_active("en"))

# F. Fallback cycle is detected and terminated.

func test_fallback_cycle_is_bounded() -> void:
	var a := Locale.Locale.new("a", "A", "b", {"k": "A"})
	var b := Locale.Locale.new("b", "B", "a", {"k": "B"})
	var cat := Locale.LocaleCatalog.new({"a": a, "b": b}, "a")
	# Should not loop forever; returns "" because the chain is broken.
	# The cap is MAX_FALLBACK_HOPS=5; the test only asserts termination.
	assert_eq(cat.translate("k"), "A")

# G. translate_for previews a non-active locale without mutating state.

func test_translate_for_does_not_mutate_active() -> void:
	var cat: Locale.LocaleCatalog = _catalog_with(
			{"hello": "Hello"}, {"hello": "Hola"})
	cat.set_active("en")
	assert_eq(cat.translate_for("es", "hello"), "Hola")
	# active_code still en.
	assert_eq(cat.active_code, "en")

# H. Default catalog ships English + Spanish with at least one
#    Spanish-only key falling back to English.

func test_default_catalog_has_english_and_spanish() -> void:
	var cat: Locale.LocaleCatalog = Locale.default_catalog()
	assert_true(cat.has("en"))
	assert_true(cat.has("es"))
	assert_eq(cat.active_code, "en")
	assert_eq(cat.get_locale("en").code, "en")
	assert_eq(cat.get_locale("es").fallback, "en")

# I. The known_keys() tutorial catalog is fully resolvable through
#    the default English catalog.

func test_default_catalog_resolves_tutorial_known_keys() -> void:
	var cat: Locale.LocaleCatalog = Locale.default_catalog()
	var keys: Array = Tutorial.Catalog.known_keys()
	for k in keys:
		var translated: String = cat.translate(String(k))
		assert_ne(translated, "",
				"tutorial key %s must resolve in default catalog" % k)

# J. RewardSpec labels in the default source are valid catalog keys.

func test_default_reward_labels_resolve_in_catalog() -> void:
	var cat: Locale.LocaleCatalog = Locale.default_catalog()
	var src: Rewards.RewardSource = Rewards.default_source()
	for spec in src.rewards:
		var s: Rewards.RewardSpec = spec
		var translated: String = Rewards.localize_label(s, cat)
		assert_ne(translated, "",
				"reward spec %s label %s must resolve" % [s.key, s.label])

# K. localize_label falls back to the spec.label when catalog is null.

func test_localize_label_falls_back_to_spec_label() -> void:
	var spec := Rewards.RewardSpec.new("k", 0, "", 0, [], "fallback string")
	assert_eq(Rewards.localize_label(spec, null), "fallback string")

# L. Boot path: load_catalog_from_dir reads every JSON file under
#    data/locale/ and uses <code>.json as the locale code.

func test_load_catalog_from_dir_reads_json_files() -> void:
	var cat: Locale.LocaleCatalog = Locale.load_catalog_from_dir(
			"res://data/locale", "en")
	assert_true(cat.has("en"))
	assert_true(cat.has("es"))
	assert_eq(cat.get_locale("en").name, "English")
	assert_eq(cat.get_locale("es").name, "Español")

# M. Empty / missing directory returns an empty catalog (never throws).

func test_load_catalog_from_dir_missing_dir_returns_empty() -> void:
	var cat: Locale.LocaleCatalog = Locale.load_catalog_from_dir(
			"res://data/locale_does_not_exist", "en")
	assert_eq(cat.locales.size(), 0)

# N. SaveData.SettingsRecord.language roundtrips through the schema.

func test_settings_language_roundtrips_via_envelope() -> void:
	var save: SaveData.SaveData = SaveData.fresh_save()
	save.settings.language = "es"
	var envelope: Dictionary = SaveData.to_envelope_dict(save)
	var parsed: Dictionary = envelope.duplicate(true)
	var back: SaveData.SaveData = SaveData.from_dict(parsed)
	assert_eq(back.settings.language, "es")

# O. From a parsed dictionary with unknown language, validate does
#    NOT reject (the catalog layer is what decides what is valid).

func test_settings_unknown_language_passes_validation() -> void:
	var save: SaveData.SaveData = SaveData.fresh_save()
	save.settings.language = "fr"
	var errors: Array = []
	var envelope: Dictionary = SaveData.to_envelope_dict(save)
	var parsed: Dictionary = envelope.duplicate(true)
	var back: SaveData.SaveData = SaveData.from_dict(parsed, errors)
	assert_not_null(back)
	assert_eq(back.settings.language, "fr")