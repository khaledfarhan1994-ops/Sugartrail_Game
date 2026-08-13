extends Node2D
## Gameplay presentation and input controller.
##
## Step 09 wires the deterministic domain (SugartrailBoard +
## SugartrailRules + SugartrailResolution + SugartrailReplay) into a
## playable portrait scene. The domain remains authoritative: input
## is only accepted when the presentation is in the IDLE state, and
## every visual change is driven by replaying the domain events the
## resolution pipeline emits.
##
## Visual placement is original-safe placeholder: solid coloured
## squares with a kind-index label. Step 27 replaces this with real
## art; the controller never assumes a particular visual style.

## State machine for input locking during resolution. The domain
## engine drives every transition.
enum State {
	## Player can select a piece and choose a swap.
	IDLE = 0,
	## A legal swap was committed; resolution (remove + gravity +
	## refill + cascade) is running visually.
	RESOLVING = 1,
	## A swipe gesture is in progress (one finger down, not yet up).
	SWIPING = 2,
}

const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece

## Default dimensions and palette for a fresh play session. The
## presentation is deliberately small so the same scene fits the
## 720x1280 portrait viewport on the lowest target Android.
const DEFAULT_BOARD_W: int = 6
const DEFAULT_BOARD_H: int = 8
const DEFAULT_PALETTE: int = 6

## Pixels per cell. Sized so a 6-wide board fits comfortably in the
## 720-pixel-wide portrait viewport (6 * 96 = 576 px, leaving safe-area
## margins on either side).
const CELL_SIZE: int = 96

var _board: Board = null
var _rng: Rng = null
var _state: int = State.IDLE
## Position of the first selected cell while waiting for the swap
## target. null when nothing is selected.
var _selected: Coord = null
## Drag origin in viewport pixels, captured on touch/mouse down.
var _drag_origin_px: Vector2 = Vector2.ZERO
## Cells are rendered as a flat 2D array of Node2D sprites. Indexed
## by `y * width + x` for stable order. We avoid ColorRect because
## we want each piece to be its own Node2D so per-cell tweens are
## independent.
var _piece_views: Array = []

func _ready() -> void:
	_rng = Rng.new(2025)
	_start_new_board()
	# Center the board horizontally; place it just below the top safe area.
	var board_pixel_w: int = _board.config.width * CELL_SIZE
	var viewport_w: int = get_viewport_rect().size.x
	var x_off: int = int((viewport_w - board_pixel_w) / 2)
	var y_off: int = 96
	position = Vector2(x_off, y_off)
	_render_initial()

func _start_new_board() -> void:
	var blocked: Array = []
	_board = Board.new(Board.BoardConfig.new(DEFAULT_BOARD_W, DEFAULT_BOARD_H,
			DEFAULT_PALETTE, blocked))
	Resolution.fill_random(_board, _rng, true)

func _render_initial() -> void:
	# Clear any old views (in case of restart).
	for child in get_children():
		child.queue_free()
	_piece_views.clear()
	# Background grid: a single ColorRect behind the cells.
	var grid := ColorRect.new()
	grid.color = Color(0.10, 0.10, 0.13)
	grid.size = Vector2(_board.config.width * CELL_SIZE,
			_board.config.height * CELL_SIZE)
	grid.position = Vector2.ZERO
	add_child(grid)
	# Background of blocked cells (none in the default config).
	# Then one PieceView per piece.
	for cell in _board._cells:
		var view: Node2D = _make_piece_view(cell.coord, cell.piece)
		_piece_views.append(view)
		add_child(view)

func _make_piece_view(c: Coord, p: Piece) -> Node2D:
	var n := Node2D.new()
	n.position = _cell_to_local(c)
	var rect := ColorRect.new()
	rect.color = _kind_color(p.kind_id)
	rect.size = Vector2(CELL_SIZE - 6, CELL_SIZE - 6)
	rect.position = Vector2(3, 3)
	n.add_child(rect)
	var label := Label.new()
	label.text = str(p.kind_id)
	label.position = Vector2(20, 18)
	label.add_theme_font_size_override("font_size", 36)
	label.add_theme_color_override("font_color", Color.BLACK)
	n.add_child(label)
	n.set_meta("coord_x", c.x)
	n.set_meta("coord_y", c.y)
	return n

func _kind_color(kind: int) -> Color:
	# Original-safe palette: distinct hues with reasonable contrast.
	var palette: Array = [
		Color(1.00, 0.55, 0.55),  # kind 0: warm pink
		Color(0.55, 1.00, 0.55),  # kind 1: fresh green
		Color(0.55, 0.65, 1.00),  # kind 2: soft blue
		Color(1.00, 0.95, 0.55),  # kind 3: warm yellow
		Color(1.00, 0.70, 0.95),  # kind 4: rose
		Color(0.70, 1.00, 0.95),  # kind 5: mint
	]
	return palette[kind % palette.size()]

func _cell_to_local(c: Coord) -> Vector2:
	return Vector2(c.x * CELL_SIZE, c.y * CELL_SIZE)

func _local_to_cell(local_pos: Vector2) -> Coord:
	var x: int = int(local_pos.x) / CELL_SIZE
	var y: int = int(local_pos.y) / CELL_SIZE
	return Coord.new(x, y)

# ----------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _state == State.RESOLVING:
		return
	if event is InputEventMouseButton:
		_handle_mouse(event)
	elif event is InputEventScreenTouch:
		_handle_touch(event)

func _handle_mouse(event: InputEventMouseButton) -> void:
	if event.button_index != MOUSE_BUTTON_LEFT:
		return
	if event.pressed:
		_on_press(_viewport_to_local(event.position))
	else:
		_on_release(_viewport_to_local(event.position))

func _handle_touch(event: InputEventScreenTouch) -> void:
	if event.pressed:
		_on_press(_viewport_to_local(event.position))
	else:
		_on_release(_viewport_to_local(event.position))

func _viewport_to_local(viewport_pos: Vector2) -> Vector2:
	# Account for the board's offset on screen.
	return viewport_pos - position

func _on_press(local_pos: Vector2) -> void:
	if _state != State.IDLE:
		return
	if not _in_board(local_pos):
		return
	_drag_origin_px = local_pos
	_selected = _local_to_cell(local_pos)
	_state = State.SWIPING

func _on_release(local_pos: Vector2) -> void:
	if _state != State.SWIPING:
		return
	var drag: Vector2 = local_pos - _drag_origin_px
	_state = State.IDLE
	if drag.length() >= CELL_SIZE * 0.4:
		# Treat as a swipe: pick a target by the dominant direction.
		var dir: Vector2 = drag.normalized()
		var target: Coord = _swipe_target(_selected, dir)
		if target != null:
			_attempt_swap(_selected, target)
			_selected = null
			return
	# Otherwise treat as a tap. The release coord may match the press
	# (no movement) — nothing to do.
	_selected = null

func _swipe_target(start: Coord, dir: Vector2) -> Coord:
	if abs(dir.x) > abs(dir.y):
		var nx: int = start.x + (1 if dir.x > 0 else -1)
		if nx >= 0 and nx < _board.config.width:
			return Coord.new(nx, start.y)
	else:
		var ny: int = start.y + (1 if dir.y > 0 else -1)
		if ny >= 0 and ny < _board.config.height:
			return Coord.new(start.x, ny)
	return null

func _attempt_swap(a: Coord, b: Coord) -> void:
	if not Rules.is_orthogonal_neighbor(a, b):
		return
	if not Rules.try_swap(_board, a, b):
		# Illegal swap: shake feedback (just print for now, real haptics
		# land with the audio system in a later step).
		print("[GameplayView] illegal swap: ", a.to_string(), " <-> ", b.to_string())
		return
	# Reflect the swap visually: the pieces at a and b have exchanged.
	# Try_swap has already mutated the domain board, but the views
	# were not updated. Build two synthetic MOVE events to sync the
	# view, then run resolution.
	var pre_swap_events: Array = []
	var pa: int = _board.cell_at(a).piece.kind_id
	var pb: int = _board.cell_at(b).piece.kind_id
	# The simplest correct approach: just rebuild the views for a
	# and b by removing the old ones and spawning new ones. Future
	# steps replace this with a tweened animation.
	_remove_view(a)
	_remove_view(b)
	_add_view(a, pa)
	_add_view(b, pb)
	_state = State.RESOLVING
	var result: Resolution.CascadeResult = Resolution.resolve(_board, _rng)
	_apply_events(result.events)
	_state = State.IDLE

func _in_board(local_pos: Vector2) -> bool:
	if local_pos.x < 0 or local_pos.y < 0:
		return false
	if local_pos.x >= _board.config.width * CELL_SIZE:
		return false
	if local_pos.y >= _board.config.height * CELL_SIZE:
		return false
	return true

# ----------------------------------------------------------------------------
# Event-driven view updates
# ----------------------------------------------------------------------------

## Replay every domain event in order. For Step 09 this is a
## synchronous rebuild of the piece views (remove / spawn immediately;
## move is a position update). A future step adds tweened animation.
func _apply_events(events: Array) -> void:
	for ev in events:
		var e: Resolution.DomainEvent = ev
		match e.kind:
			Resolution.EventKind.MOVE:
				var from: Coord = e.coords[0]
				var to: Coord = e.coords[1]
				_move_view(from, to)
			Resolution.EventKind.REMOVE:
				var c: Coord = e.coords[0]
				_remove_view(c)
			Resolution.EventKind.SPAWN:
				var c2: Coord = e.coords[0]
				_add_view(c2, e.piece_kind_id)
			Resolution.EventKind.CASCADE_START, Resolution.EventKind.CASCADE_END:
				pass

func _move_view(from: Coord, to: Coord) -> void:
	var v: Node2D = _view_at(from)
	if v == null:
		return
	# Move the view node and update its meta so subsequent lookups
	# find it at the new position.
	v.position = _cell_to_local(to)
	v.set_meta("coord_x", to.x)
	v.set_meta("coord_y", to.y)

func _remove_view(c: Coord) -> void:
	var v: Node2D = _view_at(c)
	if v == null:
		return
	_piece_views.erase(v)
	v.queue_free()

func _add_view(c: Coord, kind: int) -> void:
	var v: Node2D = _make_piece_view(c, Piece.new(kind))
	_piece_views.append(v)
	add_child(v)

func _view_at(c: Coord) -> Node2D:
	for v in _piece_views:
		if int(v.get_meta("coord_x", -1)) == c.x and int(v.get_meta("coord_y", -1)) == c.y:
			return v
	return null

# ----------------------------------------------------------------------------
# Public API used by higher-level sessions and tests
# ----------------------------------------------------------------------------

## Apply a deterministic legal swap driven by code (not by input).
## Used by the session layer (Step 10) and by replay tests.
func apply_programmatic_swap(a: Coord, b: Coord) -> bool:
	if _state != State.IDLE:
		return false
	if not Rules.is_orthogonal_neighbor(a, b):
		return false
	if not Rules.try_swap(_board, a, b):
		return false
	# Reflect the swap visually (see _attempt_swap for rationale).
	var pa: int = _board.cell_at(a).piece.kind_id
	var pb: int = _board.cell_at(b).piece.kind_id
	_remove_view(a)
	_remove_view(b)
	_add_view(a, pa)
	_add_view(b, pb)
	_state = State.RESOLVING
	var result: Resolution.CascadeResult = Resolution.resolve(_board, _rng)
	_apply_events(result.events)
	_state = State.IDLE
	return true

## Return the underlying domain board. The presentation must never
## leak its internal Sprite2D into domain decisions — callers use this
## to read state, not to mutate.
func get_board() -> Board:
	return _board

## Return the piece kind rendered at the given cell, or -1 if no piece.
func kind_at(c: Coord) -> int:
	var v: Node2D = _view_at(c)
	if v == null:
		return -1
	for child in v.get_children():
		if child is Label:
			return int(child.text)
	return -1
