extends GutTest
## Step 17: booster integration with session / replay / objectives.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Booster = preload("res://scripts/domain/boosters/boosters.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece
const ActionKind = Replay.ActionKind

func _make_recipe(overrides: Dictionary = {}) -> Dictionary:
	var recipe := {
		"recipe_id": "test-boosters",
		"version": 3,
		"board_w": 6,
		"board_h": 8,
		"palette": 6,
		"seed": 7777,
		"moves": 20,
		"objectives": [
			{"kind": 0, "target_kind": 0, "target_total": 10},
		],
		"star_one": 50,
		"star_two": 150,
		"star_three": 300,
		"boosters": [
			{"kind": Booster.BoosterKind.SWAP_RETRY, "count": 2},
		],
	}
	for k in overrides:
		recipe[k] = overrides[k]
	return recipe

# A. Session starts with the recipe's booster inventory.

func test_session_loads_booster_pack_from_recipe() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	assert_not_null(session.booster_pack)
	assert_eq(session.booster_pack.count(Booster.BoosterKind.SWAP_RETRY), 2)

# B. Session with no booster recipe gets an empty pack.

func test_no_boosters_recipe_creates_empty_pack() -> void:
	var recipe := _make_recipe()
	recipe.erase("boosters")
	var session: Session.Session = Session.from_recipe(recipe)
	assert_not_null(session.booster_pack)
	assert_eq(session.booster_pack.total(), 0)

# C. Cannot use a booster outside READY state.

func test_cannot_request_booster_state_not_ready() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	session.state = Session.State.PAUSED
	assert_false(session.request_booster(Booster.BoosterKind.SWAP_RETRY))

# D. Cannot use a booster with zero inventory.

func test_zero_inventory_booster_request_fails() -> void:
	var recipe := _make_recipe()
	recipe["boosters"] = []
	var session: Session.Session = Session.from_recipe(recipe)
	assert_false(session.request_booster(Booster.BoosterKind.SWAP_RETRY))

# E. SWAP_RETRY applies after a swap: previous swap is undone, move refunded.

func test_swap_retry_undoes_previous_swap() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("deadlocked; skipping")
		return
	var pick: Array = moves[0]
	var a: Coord = pick[0]
	var b: Coord = pick[1]
	var moves_before: int = session.moves_remaining
	var ok: bool = session.attempt_swap(a, b)
	assert_true(ok)
	assert_eq(session.moves_remaining, moves_before - 1)
	assert_eq(session.actions.size(), 1)
	# Now use the swap-retry.
	assert_true(session.request_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_true(session.confirm_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(session.moves_remaining, moves_before,
			"swap-retry must refund the move")
	# Action log: the SWAP was removed (retried) and a USE_BOOSTER
	# was appended. Net size = 1 (the booster use replaces the swap).
	assert_eq(session.actions.size(), 1,
			"swap-retry must remove the swap; USE_BOOSTER replaces it")
	assert_eq(session.actions[0].kind, ActionKind.USE_BOOSTER)
	# Inventory must have decremented.
	assert_eq(session.booster_pack.count(Booster.BoosterKind.SWAP_RETRY), 1)

# F. Cancel does not consume inventory.

func test_cancel_booster_does_not_consume() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("deadlocked; skipping")
		return
	var pick: Array = moves[0]
	session.attempt_swap(pick[0], pick[1])
	# Request then cancel.
	assert_true(session.request_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_true(session.cancel_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_eq(session.booster_pack.count(Booster.BoosterKind.SWAP_RETRY), 2)
	# Cancel recorded as an action; the original swap is still in the log.
	assert_eq(session.actions.size(), 2,
			"swap + cancel must both be in the log")

# G. SWAP_RETRY cannot be applied twice to the same swap.

func test_swap_retry_cannot_be_applied_to_same_swap_twice() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Grand a second booster so we have 2 to play with.
	session.booster_pack.boosters[Booster.BoosterKind.SWAP_RETRY] = \
			Booster.Booster.new(Booster.BoosterKind.SWAP_RETRY, 2)
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("deadlocked")
		return
	var pick: Array = moves[0]
	session.attempt_swap(pick[0], pick[1])
	# First retry consumes the swap from the log.
	assert_true(session.request_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_true(session.confirm_booster(Booster.BoosterKind.SWAP_RETRY))
	# The action log no longer has a SWAP to retry; the second retry
	# must fail.
	assert_true(session.request_booster(Booster.BoosterKind.SWAP_RETRY))
	assert_false(session.confirm_booster(Booster.BoosterKind.SWAP_RETRY),
			"swap-retry cannot be applied when no SWAP action exists")

# H. Atomic use: confirm with no pending fails without consuming inventory.

func test_confirm_without_pending_does_not_consume() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# session.confirm_booster requires a request first; without it,
	# confirm fails without consuming. But also: confirm with no
	# request must not crash.
	var ok: bool = session.confirm_booster(Booster.BoosterKind.SWAP_RETRY)
	assert_false(ok)
	assert_eq(session.booster_pack.count(Booster.BoosterKind.SWAP_RETRY), 2,
			"failed confirm must not consume inventory")

# I. Snapshot roundtrips the booster pack.

func test_snapshot_roundtrips_booster_pack() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var snap: Dictionary = session.snapshot_state()
	assert_true(snap.has("booster_pack"))
	# booster_pack is a Dictionary keyed by BoosterKind -> dict.
	var pack: Dictionary = snap["booster_pack"]
	assert_true(pack.has(Booster.BoosterKind.SWAP_RETRY))
	var entry: Dictionary = pack[Booster.BoosterKind.SWAP_RETRY]
	assert_eq(int(entry["inventory"]), 2)

# J. Replay determinism: same SWAP_RETRY log replays to the same hash.

func test_replay_with_use_booster_determinism() -> void:
	var recipe := _make_recipe()
	var s_init: Session.Session = Session.from_recipe(recipe)
	var init_board := s_init.board
	var moves: Array = Rules.enumerate_legal_swaps(init_board)
	if moves.size() == 0:
		pending("deadlocked")
		return
	var pick: Array = moves[0]
	var a: Coord = pick[0]
	var b: Coord = pick[1]
	# Build a log: a SWAP with a recorded pre-swap snapshot, then a
	# SWAP_RETRY that restores from that snapshot. Replay must be
	# deterministic and return ok=true.
	var log := Replay.ActionLog.new()
	log.recipe = recipe
	log.engine_version = "0.6.0-test"
	log.initial_rng_state = s_init.rng.to_int()
	log.initial_board = init_board.to_snapshot()
	# Build a deterministic pre-swap snapshot: the same board.
	var swap_action := Replay.Action.new(ActionKind.SWAP, a, b, -1,
			{"pre_swap_board": init_board.to_snapshot()})
	log.actions.append(swap_action)
	var retry_action := Replay.Action.new(
			ActionKind.USE_BOOSTER, a, b, Booster.BoosterKind.SWAP_RETRY)
	log.actions.append(retry_action)
	var r1: Replay.ReplayResult = Replay.replay(log, "0.6.0-test")
	var r2: Replay.ReplayResult = Replay.replay(log, "0.6.0-test")
	assert_true(r1.ok, "first replay ok: %s" % r1.last_error_message)
	assert_true(r2.ok, "second replay ok: %s" % r2.last_error_message)
	assert_eq(r1.result_hash, r2.result_hash,
			"replay with USE_BOOSTER must be deterministic")
	assert_eq(r1.total_events, r2.total_events)

# K. Combo: SWAP_RETRY followed by a fresh swap is accepted.

func test_combo_retry_then_swap() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	# Play a swap.
	var moves: Array = Rules.enumerate_legal_swaps(session.board)
	if moves.size() == 0:
		pending("deadlocked")
		return
	var pick: Array = moves[0]
	session.attempt_swap(pick[0], pick[1])
	# Undo it.
	session.request_booster(Booster.BoosterKind.SWAP_RETRY)
	session.confirm_booster(Booster.BoosterKind.SWAP_RETRY)
	# Now play another swap.
	var moves2: Array = Rules.enumerate_legal_swaps(session.board)
	if moves2.size() == 0:
		pending("deadlocked after retry")
		return
	var pick2: Array = moves2[0]
	var ok: bool = session.attempt_swap(pick2[0], pick2[1])
	assert_true(ok, "fresh swap after retry must succeed")
	# The action log should be: SWAP_RETRY, SWAP (the retry consumed
	# the previous swap).
	assert_eq(session.actions.size(), 2)
	var last: Replay.Action = session.actions[1]
	assert_eq(last.kind, ActionKind.SWAP)
