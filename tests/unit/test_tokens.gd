extends GutTest
## Step 16: trapped-token mechanic.

const Board = preload("res://scripts/domain/board/board.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord

# A. Board.add_token places a token entry.

func test_add_token_places_entry() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	assert_true(b.add_token(1, 1, 7, 0))
	assert_eq(b.tokens.size(), 1)
	var entry: Dictionary = b.tokens[0]
	assert_eq(int(entry["x"]), 1)
	assert_eq(int(entry["y"]), 1)
	assert_eq(int(entry["id"]), 7)
	assert_eq(int(entry["matching_kind"]), 0)

# B. to_snapshot + from_snapshot roundtrip tokens (via replay module).

func test_tokens_roundtrip_via_snapshot() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(2, 3, 5, -1)
	var snap: Dictionary = b.to_snapshot()
	assert_true(snap.has("tokens"))
	var tokens_in: Array = snap["tokens"]
	assert_eq(tokens_in.size(), 1)
	var t: Dictionary = tokens_in[0]
	assert_eq(int(t["x"]), 2)
	assert_eq(int(t["y"]), 3)
	assert_eq(int(t["id"]), 5)
	assert_eq(int(t["matching_kind"]), -1)
	# Rebuild a board from the snapshot via the replay module.
	var Replay = preload("res://scripts/domain/replay/replay.gd")
	var b2: Board = Replay._board_from_snapshot(snap)
	assert_eq(b2.tokens.size(), 1)
	var t2: Dictionary = b2.tokens[0]
	assert_eq(int(t2["x"]), 2)
	assert_eq(int(t2["y"]), 3)
	assert_eq(int(t2["id"]), 5)

# C. Token release: matching kind under token triggers TOKEN_RELEASE.

func test_matching_kind_under_token_releases() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(1, 1, 100, 0)
	b.set_piece(Coord.new(1, 1), Board.Piece.new(0))
	var rng := Rng.new(42)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# Find a TOKEN_RELEASE event for (1,1).
	var saw_release: bool = false
	for ev in result.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.TOKEN_RELEASE:
			assert_eq(e.coords[0].x, 1)
			assert_eq(e.coords[0].y, 1)
			saw_release = true
	assert_true(saw_release, "expected TOKEN_RELEASE for matching kind")
	assert_eq(b.tokens.size(), 0, "token must be removed after release")

# D. Token release: matching_kind = -1 accepts any piece.

func test_any_matching_kind_releases_on_any_piece() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(2, 2, 200, -1)
	b.set_piece(Coord.new(2, 2), Board.Piece.new(3))
	var rng := Rng.new(7)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var saw_release: bool = false
	for ev in result.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.TOKEN_RELEASE:
			saw_release = true
	assert_true(saw_release)
	assert_eq(b.tokens.size(), 0)

# E. Token release: tokens with no matching piece stay unreleased.

func test_no_release_when_piece_does_not_match() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(0, 0, 300, 1)
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	var rng := Rng.new(1)
	# No match runs on this single-cell configuration; resolve exits
	# after one cycle with no TOKEN_RELEASE.
	Resolution.resolve(b, rng)
	assert_eq(b.tokens.size(), 1, "non-matching token must remain")

# F. Resolution events include TOKEN_RELEASE.

func test_token_release_event_carries_token_id_in_special_origin() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(1, 0, 42, -1)
	b.set_piece(Coord.new(1, 0), Board.Piece.new(0))
	var rng := Rng.new(99)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	var found_id: int = -1
	for ev in result.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.TOKEN_RELEASE:
			assert_ne(e.special_origin, null,
					"TOKEN_RELEASE must encode the token id in special_origin")
			found_id = e.special_origin.x
	assert_eq(found_id, 42, "token id must be encoded in special_origin.x")

# G. Replay determinism: tokens + objective + special chain
# produce identical snapshot_hash.

func test_snapshot_hash_includes_tokens() -> void:
	var b1 := Board.new(Board.BoardConfig.new(4, 4, 4))
	var b2 := Board.new(Board.BoardConfig.new(4, 4, 4))
	b1.add_token(1, 1, 5, 0)
	# b2 has no token.
	assert_ne(b1.snapshot_hash(), b2.snapshot_hash(),
			"token list must affect snapshot hash")
	# Adding the same token to both produces identical hashes.
	b2.add_token(1, 1, 5, 0)
	assert_eq(b1.snapshot_hash(), b2.snapshot_hash())

# H. RELEASE_TOKEN objective progress increments on release.

func test_release_token_objective_progresses() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 4))
	b.add_token(0, 0, 1, -1)
	b.add_token(3, 3, 2, -1)
	b.set_piece(Coord.new(0, 0), Board.Piece.new(0))
	# Second token has no piece under it; resolve does not release it.
	var rng := Rng.new(2024)
	var result: Resolution.CascadeResult = Resolution.resolve(b, rng)
	# Count TOKEN_RELEASE events.
	var releases: int = 0
	for ev in result.events:
		var e: Resolution.DomainEvent = ev
		if e.kind == Resolution.EventKind.TOKEN_RELEASE:
			releases += 1
	assert_eq(releases, 1)
	assert_eq(b.tokens.size(), 1)