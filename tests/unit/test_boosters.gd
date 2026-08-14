extends GutTest
## Step 17: booster catalog + atomic use/cancel tests.

const Booster = preload("res://scripts/domain/boosters/boosters.gd")

func _make_pack(inventory: int = 0) -> Booster.BoosterPack:
	var b := Booster.Booster.new(Booster.BoosterKind.SWAP_RETRY, inventory)
	var dict: Dictionary = {Booster.BoosterKind.SWAP_RETRY: b}
	return Booster.BoosterPack.new(dict)

# A. Catalog has the swap-retry booster.

func test_catalog_contains_swap_retry() -> void:
	var known: Array = Booster.known_kinds()
	assert_true(known.has(Booster.BoosterKind.SWAP_RETRY))

# B. New pack starts with zero inventory.

func test_new_pack_has_zero_inventory() -> void:
	var pack := _make_pack(0)
	assert_eq(pack.count(Booster.BoosterKind.SWAP_RETRY), 0)
	assert_eq(pack.total(), 0)

# C. Cannot use with zero inventory.

func test_zero_inventory_cannot_use() -> void:
	var pack := _make_pack(0)
	assert_false(pack.request_use(Booster.BoosterKind.SWAP_RETRY))

# D. Inventory decrements on confirmed use.

func test_confirmed_use_decrements_inventory() -> void:
	var pack := _make_pack(2)
	assert_true(pack.request_use(Booster.BoosterKind.SWAP_RETRY))
	assert_true(pack.confirm(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(pack.count(Booster.BoosterKind.SWAP_RETRY), 1)

# E. Cancel does NOT consume inventory.

func test_cancel_does_not_consume() -> void:
	var pack := _make_pack(2)
	pack.request_use(Booster.BoosterKind.SWAP_RETRY)
	assert_true(pack.cancel(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(pack.count(Booster.BoosterKind.SWAP_RETRY), 2)

# F. Cannot confirm without pending.

func test_confirm_without_pending_fails() -> void:
	var pack := _make_pack(2)
	assert_false(pack.confirm(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(pack.count(Booster.BoosterKind.SWAP_RETRY), 2)

# G. Cannot double-request.

func test_cannot_double_request() -> void:
	var pack := _make_pack(2)
	assert_true(pack.request_use(Booster.BoosterKind.SWAP_RETRY))
	assert_false(pack.request_use(Booster.BoosterKind.SWAP_RETRY))

# H. Atomic consume: confirm runs once.

func test_confirm_runs_once_per_request() -> void:
	var pack := _make_pack(2)
	pack.request_use(Booster.BoosterKind.SWAP_RETRY)
	assert_true(pack.confirm(Booster.BoosterKind.SWAP_RETRY))
	# Subsequent confirm without a pending request does nothing.
	assert_false(pack.confirm(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(pack.count(Booster.BoosterKind.SWAP_RETRY), 1)

# I. Roundtrip via to_dict / from_dict.

func test_booster_pack_roundtrip() -> void:
	var pack := _make_pack(3)
	pack.request_use(Booster.BoosterKind.SWAP_RETRY)
	var d: Dictionary = pack.to_dict()
	var rest: Booster.BoosterPack = Booster.BoosterPack.from_dict(d)
	assert_eq(rest.count(Booster.BoosterKind.SWAP_RETRY), 3)
	var b: Booster.Booster = rest.boosters[Booster.BoosterKind.SWAP_RETRY]
	assert_true(b.pending)

# J. Label + description for known kinds.

func test_label_and_description_for_swap_retry() -> void:
	assert_eq(Booster.label_for(Booster.BoosterKind.SWAP_RETRY), "Swap Retry")
	assert_ne(Booster.description_for(Booster.BoosterKind.SWAP_RETRY), "")

# K. Unknown kind returns safe defaults.

func test_unknown_kind_safe_labels() -> void:
	assert_ne(Booster.label_for(999), "")
	assert_eq(Booster.description_for(999), "")