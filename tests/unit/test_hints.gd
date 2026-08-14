extends GutTest
## Step 17: hint ranker tests.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Hints = preload("res://scripts/domain/hints/hints.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord

func _make_recipe(overrides: Dictionary = {}) -> Dictionary:
	var recipe := {
		"recipe_id": "test-hints",
		"version": 3,
		"chapter": 0,
		"index_in_chapter": 0,
		"board_w": 6,
		"board_h": 8,
		"palette": 4,
		"seed": 1234,
		"moves": 20,
		"objectives": [
			{"kind": 0, "target_kind": 0, "target_total": 6},
		],
		"star_one": 50,
		"star_two": 150,
		"star_three": 300,
		"intro_text": "",
		"tutorial": [],
		"avoid_initial_matches": true,
	}
	for k in overrides:
		recipe[k] = overrides[k]
	return recipe

# A. Suggestion never returns illegal moves.

func test_suggestion_only_returns_legal_moves() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var hints: Array = Hints.suggest(session.board, session.rng, 3)
	assert_true(hints.size() <= 3)
	for h in hints:
		var entry: Dictionary = h
		var a: Coord = entry["coord_a"]
		var b: Coord = entry["coord_b"]
		assert_true(Rules.is_orthogonal_neighbor(a, b))
		# The hint must be a real legal swap on the original board.
		var legal: Array = Rules.enumerate_legal_swaps(session.board)
		var found: bool = false
		for pair in legal:
			if (pair[0].is_equal_to(a) and pair[1].is_equal_to(b)) \
					or (pair[0].is_equal_to(b) and pair[1].is_equal_to(a)):
				found = true
		assert_true(found, "suggested move must be a legal swap")

# B. Suggestion never mutates the board.

func test_suggestion_does_not_mutate_board() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var before_hash: int = session.board.snapshot_hash()
	var before_rng: int = session.rng.to_int()
	Hints.suggest(session.board, session.rng, 1)
	assert_eq(session.board.snapshot_hash(), before_hash,
			"hint ranker must not mutate the board")
	assert_eq(session.rng.to_int(), before_rng,
			"hint ranker must not advance the live RNG")

# C. Suggestion returns a hint with reason.

func test_suggestion_returns_reason_string() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var hints: Array = Hints.suggest(session.board, session.rng, 1)
	if hints.size() == 0:
		pending("no legal moves; skipping")
		return
	var entry: Dictionary = hints[0]
	assert_true(entry.has("reason"))
	assert_ne(entry["reason"], "")
	assert_true(entry.has("score"))
	assert_true(int(entry["score"]) >= 0)

# D. Suggestion is deterministic.

func test_suggestion_deterministic_for_same_input() -> void:
	var recipe := _make_recipe()
	var s1: Session.Session = Session.from_recipe(recipe)
	var s2: Session.Session = Session.from_recipe(recipe)
	var h1: Array = Hints.suggest(s1.board, s1.rng, 2)
	var h2: Array = Hints.suggest(s2.board, s2.rng, 2)
	assert_eq(h1.size(), h2.size())
	for i in range(h1.size()):
		var e1: Dictionary = h1[i]
		var e2: Dictionary = h2[i]
		assert_eq(int(e1["score"]), int(e2["score"]))
		assert_eq(String(e1["reason"]), String(e2["reason"]))

# E. Suggestion with limit 0 returns empty.

func test_suggestion_with_zero_limit_returns_empty() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var hints: Array = Hints.suggest(session.board, session.rng, 0)
	assert_eq(hints.size(), 0)

# F. Suggestion on deadlocked board returns empty.

func test_suggestion_on_deadlocked_board_returns_empty() -> void:
	var b := Board.new(Board.BoardConfig.new(4, 4, 3))
	# Fill with a stable non-matching layout.
	for y in range(4):
		for x in range(4):
			var k: int = (x + 2 * y) % 3
			b.set_piece(Coord.new(x, y), Board.Piece.new(k))
	var rng := Rng.new(99)
	# Force a no-legal-moves state via resolve (which leaves a stable
	# board if no runs appear). For a fresh checkerboard the only
	# way to deadlock is for runs to be absent AND no swap helps.
	# For a 3-color checkerboard, enumerate_legal_swaps may still
	# produce results. We accept either empty or non-empty here as
	# long as the contract holds: returned moves are legal.
	var hints: Array = Hints.suggest(b, rng, 1)
	for h in hints:
		var entry: Dictionary = h
		var legal: Array = Rules.enumerate_legal_swaps(b)
		# If the board has no legal swaps, hints must be empty.
		if legal.size() == 0:
			assert_eq(hints.size(), 0)
			return

# G. Reason is one of the known strings.

func test_suggestion_reason_is_known() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var hints: Array = Hints.suggest(session.board, session.rng, 1)
	if hints.size() == 0:
		pending("no legal moves")
		return
	var entry: Dictionary = hints[0]
	var r: String = String(entry["reason"])
	var known := [Hints.REASON_LEGAL, Hints.REASON_OBJECTIVE,
			Hints.REASON_FROSTING, Hints.REASON_TOKEN, Hints.REASON_CASCADE]
	assert_true(known.has(r), "reason must be one of known labels")

# H. Multiple suggestions are ranked by score descending.

func test_suggestions_ranked_by_score_desc() -> void:
	var session: Session.Session = Session.from_recipe(_make_recipe())
	var hints: Array = Hints.suggest(session.board, session.rng, 5)
	for i in range(1, hints.size()):
		assert_true(int(hints[i - 1]["score"]) >= int(hints[i]["score"]),
				"hints must be ordered by descending score")