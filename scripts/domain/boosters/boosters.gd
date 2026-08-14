class_name SugartrailBooster
extends RefCounted
## Approved booster catalog + atomic use/cancel semantics.
##
## Step 17 introduces boosters. Boosters are inventory-bounded
## optional assists. They are NEVER required to win a level (the
## validation rule "levels cannot require boosters" is enforced at
## level design time, not here). The launch set is intentionally
## small: just one — a swap-retry that lets the player undo the
## previous swap without burning a move.
##
## Booster semantics:
##
##   - Use is two-phase: confirm or cancel. Cancel does not consume
##     inventory; confirmed use is atomic (the inventory count
##     decrements, the booster effect applies, all in one step).
##   - The presentation layer is responsible for showing the "Are
##     you sure?" dialog. The domain enforces atomicity: `use()`
##     only ever runs once, only if `inventory > 0`, and only if
##     the session state is READY.
##   - Effects are pure functions of the session state at use time;
##     they are recorded in the action log so replays stay
##     deterministic.

## Booster identifiers. The launch set has a single booster.
enum BoosterKind {
	SWAP_RETRY = 0, # Undo the previous swap and refund the move.
}

const Board = preload("res://scripts/domain/board/board.gd")
const Coord = Board.CellCoord

## A booster instance: its kind, its inventory count, and its
## lifecycle state (PENDING / CONFIRMED / CANCELED).
class Booster:
	var kind: int = BoosterKind.SWAP_RETRY
	## How many of this booster the player owns (>= 0).
	var inventory: int = 0
	## A pending-use flag (true once the presentation has called
	## `request_use()` but before the player confirmed).
	var pending: bool = false

	func _init(p_kind: int = BoosterKind.SWAP_RETRY, p_inventory: int = 0) -> void:
		kind = p_kind
		inventory = p_inventory

	func can_use() -> bool:
		return inventory > 0

	func to_dict() -> Dictionary:
		return {
			"kind": kind,
			"inventory": inventory,
			"pending": pending,
		}

	static func from_dict(d: Dictionary) -> Booster:
		var b := Booster.new(
			int(d.get("kind", BoosterKind.SWAP_RETRY)),
			int(d.get("inventory", 0)))
		b.pending = bool(d.get("pending", false))
		return b

## A booster collection. Holds 0+ boosters keyed by BoosterKind.
class BoosterPack:
	var boosters: Dictionary = {}

	func _init(p_boosters: Dictionary = {}) -> void:
		boosters = {}
		for k in p_boosters:
			var kind_v: int = int(k)
			var v: Variant = p_boosters[k]
			if v is Booster:
				boosters[kind_v] = v
			elif typeof(v) == TYPE_INT:
				boosters[kind_v] = Booster.new(kind_v, int(v))
			else:
				boosters[kind_v] = Booster.new(kind_v, 0)

	## Total inventory across all kinds.
	func total() -> int:
		var s: int = 0
		for k in boosters:
			s += int(boosters[k])
		return s

	## Inventory for one kind, 0 if absent.
	func count(kind: int) -> int:
		var v: Variant = boosters.get(kind, 0)
		if v is Booster:
			return (v as Booster).inventory
		return int(v)

	## Mark a kind as pending use. Returns true if the booster
	## kind exists, has inventory > 0, and was not already pending.
	func request_use(kind: int) -> bool:
		var b: Booster = _get_or_create(kind)
		if not b.can_use():
			return false
		if b.pending:
			return false
		b.pending = true
		return true

	## Cancel a pending use. Inventory does NOT decrement. Returns
	## true if a pending use was cleared.
	func cancel(kind: int) -> bool:
		var b: Booster = _get_or_create(kind)
		if not b.pending:
			return false
		b.pending = false
		return true

	## Confirm a pending use: inventory decrements by 1, the
	## pending flag clears. Returns true on success (an inventory
	## unit was consumed).
	func confirm(kind: int) -> bool:
		var b: Booster = _get_or_create(kind)
		if not b.pending:
			return false
		if not b.can_use():
			b.pending = false
			return false
		b.inventory -= 1
		b.pending = false
		return true

	func to_dict() -> Dictionary:
		var out: Dictionary = {}
		for k in boosters:
			var b: Booster = boosters[k]
			out[int(k)] = b.to_dict()
		return out

	static func from_dict(d: Dictionary) -> BoosterPack:
		var pack := BoosterPack.new()
		for k in d:
			var kind_v: int = int(k)
			var entry: Dictionary = d[k]
			pack.boosters[kind_v] = Booster.from_dict(entry)
		return pack

	func _get_or_create(kind: int) -> Booster:
		if not boosters.has(kind):
			boosters[kind] = Booster.new(kind, 0)
		var v: Variant = boosters[kind]
		return v as Booster

## Human-readable label for a booster kind. Used by the presentation
## layer for menu / confirmation dialog text.
static func label_for(kind: int) -> String:
	match kind:
		BoosterKind.SWAP_RETRY: return "Swap Retry"
		_: return "Booster(%d)" % kind

## Short description of the booster's effect.
static func description_for(kind: int) -> String:
	match kind:
		BoosterKind.SWAP_RETRY:
			return "Undo your last swap and refund the move."
		_: return ""

## Catalog of all boosters the engine knows about. The launch set
## is a single entry — anything else must be added explicitly so
## the presentation layer can pin its label/description.
static func known_kinds() -> Array:
	return [BoosterKind.SWAP_RETRY]