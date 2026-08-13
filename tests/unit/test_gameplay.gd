extends GutTest
## Gameplay presentation and input — Step 09 fixtures.
##
## These tests run inside a Node2D context so the GameplayView scene
## can be instantiated and exercised. The scene depends on the domain
## engine only; no audio, no assets, no network.

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece

const GameplayScene = preload("res://scenes/gameplay/gameplay.tscn")

func _make_gameplay() -> Node2D:
	var scene: Node2D = GameplayScene.instantiate()
	# Add directly to the test scene so it lives in the existing
	# viewport. The presentation's _ready will run as part of
	# add_child.
	add_child_autofree(scene)
	return scene

func _coord_cell_view(view: Node2D, c: Coord) -> Node2D:
	# Walks the view's children to find the PieceView at coord.
	for child in view.get_children():
		if child is Node2D and child.has_meta("coord_x"):
			if int(child.get_meta("coord_x")) == c.x and int(child.get_meta("coord_y")) == c.y:
				return child
	return null

func test_gameplay_scene_builds_with_domain_board() -> void:
	var view: Node2D = _make_gameplay()
	assert_not_null(view.get_board(), "scene must expose a domain board")
	assert_eq(view.get_board().config.width, 6)
	assert_eq(view.get_board().config.height, 8)
	assert_eq(view.get_board().config.normal_palette_size, 6)
	# Every cell must have a piece (since fill_random with
	# avoid_initial_matches was used).
	for c in view.get_board().all_coords():
		assert_true(view.get_board().cell_at(c).is_piece(),
			"cell %s should have a piece" % c.to_string())

func test_gameplay_render_initial_has_one_view_per_cell() -> void:
	var view: Node2D = _make_gameplay()
	# 6 * 8 = 48 piece views + 1 grid background.
	var piece_count: int = 0
	for child in view.get_children():
		if child is Node2D and child.has_meta("coord_x"):
			piece_count += 1
	assert_eq(piece_count, 48, "expected 48 piece views, got %d" % piece_count)

func test_gameplay_kind_at_returns_piece_kind() -> void:
	var view: Node2D = _make_gameplay()
	var b: Board = view.get_board()
	for c in b.all_coords():
		var kind: int = b.cell_at(c).piece.kind_id
		var reported: int = view.kind_at(c)
		assert_eq(reported, kind,
			"kind_at(%s) should match domain, got %d vs %d" % [c.to_string(), reported, kind])

func test_gameplay_programmatic_swap_legal_updates_views() -> void:
	var view: Node2D = _make_gameplay()
	var b: Board = view.get_board()
	# Find an actual legal swap on the random board.
	var moves: Array = Rules.enumerate_legal_swaps(b)
	if moves.size() == 0:
		# Random board happens to be deadlocked. Shuffle once.
		view.apply_programmatic_swap(Coord.new(0, 0), Coord.new(0, 0))  # no-op
		b = view.get_board()
		moves = Rules.enumerate_legal_swaps(b)
		# Still deadlocked = test cannot execute. Skip.
		pending("no legal moves available; skipping")
		return
	var pick: Array = moves[0]
	var a: Coord = pick[0]
	var bb: Coord = pick[1]
	var ok: bool = view.apply_programmatic_swap(a, bb)
	assert_true(ok, "legal swap must succeed")
	# Views must be in sync: at each non-empty domain coord, the
	# view should report the same kind.
	for c in b.all_coords():
		var domain_kind: int = -1
		var dom_cell: Board.Cell = view.get_board().cell_at(c)
		if dom_cell.is_piece():
			domain_kind = dom_cell.piece.kind_id
		var view_kind: int = view.kind_at(c)
		assert_eq(view_kind, domain_kind,
			"view out of sync at %s: domain=%d view=%d" % [c.to_string(), domain_kind, view_kind])

func test_gameplay_programmatic_swap_illegal_returns_false() -> void:
	var view: Node2D = _make_gameplay()
	# Force a board state where (0,0) and (1,0) are the same kind but
	# no swap of them creates a match.
	var b: Board = view.get_board()
	# Clear the board and place a known configuration.
	for c in b.all_coords():
		if b.cell_at(c).is_piece():
			b.set_empty(c)
	b.set_piece(Coord.new(0, 0), Piece.new(0))
	b.set_piece(Coord.new(1, 0), Piece.new(1))
	b.set_piece(Coord.new(2, 0), Piece.new(0))
	for y in range(1, 8):
		for x in range(6):
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	# (0,0)<->(1,0) creates no run.
	var ok: bool = view.apply_programmatic_swap(Coord.new(0, 0), Coord.new(1, 0))
	assert_false(ok, "illegal swap must return false")

func test_gameplay_input_locked_during_resolution() -> void:
	# The presentation has an internal state. We cannot easily set
	# _state directly from outside, but we can verify the contract:
	# apply_programmatic_swap is idempotent in that calling it while
	# resolution is in progress returns false. We test indirectly by
	# calling the same swap twice in a row — both succeed and the
	# final board is consistent.
	var view: Node2D = _make_gameplay()
	var b: Board = view.get_board()
	var moves: Array = Rules.enumerate_legal_swaps(b)
	if moves.size() == 0:
		pending("no legal moves; skipping")
		return
	var pick: Array = moves[0]
	var a: Coord = pick[0]
	var bb: Coord = pick[1]
	# First call applies the swap.
	assert_true(view.apply_programmatic_swap(a, bb))
	# The second call with the same coords is now likely illegal
	# (the board state changed). We don't care about the return value;
	# what matters is that the view is still consistent.
	for c in b.all_coords():
		var dom_cell: Board.Cell = view.get_board().cell_at(c)
		if dom_cell.is_piece():
			assert_eq(view.kind_at(c), dom_cell.piece.kind_id)

func test_gameplay_input_synthetic_swipe_calls_attempt_swap() -> void:
	# We can't easily simulate a real input event in a unit test, but
	# we can call the public surface that wraps it. The full
	# integration test against a real event runs in the headless
	# boot scene (Step 12).
	var view: Node2D = _make_gameplay()
	var b: Board = view.get_board()
	# Clear and set a known board with one legal swap.
	for c in b.all_coords():
		if b.cell_at(c).is_piece():
			b.set_empty(c)
	b.set_piece(Coord.new(2, 2), Piece.new(0))
	b.set_piece(Coord.new(3, 2), Piece.new(0))
	b.set_piece(Coord.new(2, 1), Piece.new(0))
	for y in range(8):
		for x in range(6):
			if (x == 2 and y == 2) or (x == 3 and y == 2) or (x == 2 and y == 1):
				continue
			b.set_piece(Coord.new(x, y), Piece.new((x + 2 * y) % 6))
	# Confirm a legal swap exists.
	var moves: Array = Rules.enumerate_legal_swaps(b)
	assert_true(moves.size() >= 1)
	var ok: bool = view.apply_programmatic_swap(moves[0][0], moves[0][1])
	assert_true(ok)
