extends Node2D
## Vertical slice scene: loads a curated level and renders the gameplay
## scene with HUD, objective, moves, and tutorial prompts.
##
## Step 12 wires the deterministic domain (SugartrailBoard +
## SugartrailRules + SugartrailResolution + SugartrailReplay +
## SugartrailSession + SugartrailLevelLoader + SugartrailTutorial)
## into a single portrait scene that can be exercised on Android or
## in headless CI. The presentation is original-safe placeholder
## visuals that match Step 09; art polish happens in Step 27.
##
## The scene is the canonical entry point for the Step 12 vertical
## slice acceptance run. It loads level 1 by default and prints
## well-known phase markers so screenshots and profile traces can
## correlate frames with game state.

const LevelLoader = preload("res://scripts/domain/levels/level_loader.gd")
const Tutorial = preload("res://scripts/domain/tutorial/tutorial.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Rng = preload("res://scripts/domain/rng/rng.gd")
const Resolution = preload("res://scripts/domain/rules/resolution.gd")
const Coord = Board.CellCoord
const Piece = Board.Piece

## Default recipe ID for the first level. The codeless flow simply
## loads this; in the final game the level ID comes from the world
## map (Step 19).
const DEFAULT_LEVEL_ID: String = "l1-first-match"

## Pixels per cell. Matches Step 09 presentation.
const CELL_SIZE: int = 96

## HUD layout. The HUD is a pair of left-aligned labels under the
## board and the tutorial strap below the HUD.
const HUD_OFFSET_Y: int = 16
const STRAP_OFFSET_Y: int = 64

## Tunable target-fps for the slice. The actual measurement is
## recorded in the headless profile run.
const TARGET_FPS: int = 60

var _session: Session.Session = null
var _tutorial: Tutorial.TutorialPack = null
var _recipe_id: String = DEFAULT_LEVEL_ID
var _board: Board = null
var _rng: Rng = null
var _state: int = 0  # mirrors gameplay.gd: IDLE=0, RESOLVING=1, SWIPING=2
var _selected: Coord = null
var _drag_origin_px: Vector2 = Vector2.ZERO
var _piece_views: Array = []
var _hud_moves: Label = null
var _hud_score: Label = null
var _hud_objective: Label = null
var _strap: Label = null
var _tutorial_index: int = 0
var _start_time_msec: int = 0
var _swap_count: int = 0
var _death_count: int = 0
var _win_count: int = 0
var _rng_seed_used: int = 0

func _ready() -> void:
	Engine.max_fps = TARGET_FPS
	_start_time_msec = Time.get_ticks_msec()
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(_recipe_id, errors)
	if loaded == null:
		push_error("[VerticalSlice] failed to load %s: %s" % [
			_recipe_id, str(errors)])
		print("[VerticalSlice] LOAD_FAILED recipe=", _recipe_id,
				" errors=", errors)
		get_tree().quit(1)
		return
	_session = loaded.session
	_tutorial = loaded.tutorial
	_board = _session.board
	_rng = _session.rng
	_rng_seed_used = _rng.to_int()
	# Position the board centred horizontally, just below the top safe area.
	var board_pixel_w: int = _board.config.width * CELL_SIZE
	var viewport_w: int = get_viewport_rect().size.x
	var x_off: int = int((viewport_w - board_pixel_w) / 2)
	var y_off: int = 128
	position = Vector2(x_off, y_off)
	_render_initial()
	_build_hud()
	_show_tutorial_prompt()
	print("[VerticalSlice] LOADED recipe=", _recipe_id,
			" seed=", _rng_seed_used,
			" moves=", _session.moves_remaining,
			" target_total=", _session.objective.target_total)
	print("[VerticalSlice] READY_FRAMES_TIME_MSEC=", _elapsed_msec())

# ----------------------------------------------------------------------------
# Initial render
# ----------------------------------------------------------------------------

func _render_initial() -> void:
	for child in get_children():
		child.queue_free()
	_piece_views.clear()
	# Background grid.
	var grid := ColorRect.new()
	grid.color = Color(0.10, 0.10, 0.13)
	grid.size = Vector2(_board.config.width * CELL_SIZE,
			_board.config.height * CELL_SIZE)
	grid.position = Vector2.ZERO
	add_child(grid)
	# One PieceView per piece.
	for cell in _board._cells:
		if not cell.is_piece():
			continue
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
	var palette: Array = [
		Color(1.00, 0.55, 0.55),
		Color(0.55, 1.00, 0.55),
		Color(0.55, 0.65, 1.00),
		Color(1.00, 0.95, 0.55),
		Color(1.00, 0.70, 0.95),
		Color(0.70, 1.00, 0.95),
	]
	return palette[kind % palette.size()]

func _cell_to_local(c: Coord) -> Vector2:
	return Vector2(c.x * CELL_SIZE, c.y * CELL_SIZE)

func _local_to_cell(local_pos: Vector2) -> Coord:
	var x: int = int(local_pos.x) / CELL_SIZE
	var y: int = int(local_pos.y) / CELL_SIZE
	return Coord.new(x, y)

# ----------------------------------------------------------------------------
# HUD
# ----------------------------------------------------------------------------

func _build_hud() -> void:
	# HUD lives in the parent viewport, not in this Node's local
	# coordinate system, so we anchor it absolutely.
	var hud := Node2D.new()
	hud.position = Vector2(16, _board.config.height * CELL_SIZE + HUD_OFFSET_Y)
	hud.name = "HUD"
	get_tree().root.add_child.call_deferred(hud)
	_hud_moves = Label.new()
	_hud_moves.position = Vector2(0, 0)
	_hud_moves.add_theme_font_size_override("font_size", 28)
	_hud_moves.add_theme_color_override("font_color", Color.WHITE)
	hud.add_child(_hud_moves)
	_hud_score = Label.new()
	_hud_score.position = Vector2(0, 36)
	_hud_score.add_theme_font_size_override("font_size", 28)
	_hud_score.add_theme_color_override("font_color", Color.WHITE)
	hud.add_child(_hud_score)
	_hud_objective = Label.new()
	_hud_objective.position = Vector2(0, 72)
	_hud_objective.add_theme_font_size_override("font_size", 28)
	_hud_objective.add_theme_color_override("font_color", Color.WHITE)
	hud.add_child(_hud_objective)
	_strap = Label.new()
	_strap.position = Vector2(16, _board.config.height * CELL_SIZE + STRAP_OFFSET_Y)
	_strap.add_theme_font_size_override("font_size", 22)
	_strap.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85))
	_strap.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_strap.custom_minimum_size = Vector2(get_viewport_rect().size.x - 32, 0)
	get_tree().root.add_child.call_deferred(_strap)
	_refresh_hud()

func _refresh_hud() -> void:
	if _hud_moves != null:
		_hud_moves.text = "Moves: %d" % _session.moves_remaining
	if _hud_score != null:
		_hud_score.text = "Score: %d" % _session.score
	if _hud_objective != null:
		_hud_objective.text = "Collect %d of colour %d  (%d / %d)" % [
			_session.objective.target_total,
			_session.objective.target_kind,
			_session.objective.progress,
			_session.objective.target_total]

func _show_tutorial_prompt() -> void:
	if _strap == null:
		return
	if _tutorial_index == 0 and _tutorial.intro_key != "":
		_strap.text = Tutorial.english(_tutorial.intro_key)
		return
	var prompts: Array = _tutorial.prompts
	if _tutorial_index - 1 < 0 or _tutorial_index - 1 >= prompts.size():
		_strap.text = ""
		return
	var prompt: Tutorial.Prompt = prompts[_tutorial_index - 1]
	_strap.text = Tutorial.english(prompt.key)

func _advance_tutorial() -> void:
	_tutorial_index += 1
	_show_tutorial_prompt()

# ----------------------------------------------------------------------------
# Input
# ----------------------------------------------------------------------------

func _input(event: InputEvent) -> void:
	if _state == 1:  # RESOLVING
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
	return viewport_pos - position

func _on_press(local_pos: Vector2) -> void:
	if _state != 0:
		return
	if not _in_board(local_pos):
		return
	_drag_origin_px = local_pos
	_selected = _local_to_cell(local_pos)
	_state = 2  # SWIPING

func _on_release(local_pos: Vector2) -> void:
	if _state != 2:
		return
	var drag: Vector2 = local_pos - _drag_origin_px
	_state = 0
	var consumed: bool = false
	if drag.length() >= CELL_SIZE * 0.4:
		var dir: Vector2 = drag.normalized()
		var target: Coord = _swipe_target(_selected, dir)
		if target != null:
			_attempt_swap(_selected, target)
			consumed = true
	_selected = null
	if not consumed:
		# Tap with no swipe: treat as 'next hint' on the tutorial.
		_advance_tutorial()

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

func _in_board(local_pos: Vector2) -> bool:
	if local_pos.x < 0 or local_pos.y < 0:
		return false
	if local_pos.x >= _board.config.width * CELL_SIZE:
		return false
	if local_pos.y >= _board.config.height * CELL_SIZE:
		return false
	return true

func _attempt_swap(a: Coord, b: Coord) -> void:
	if not Rules.is_orthogonal_neighbor(a, b):
		return
	if not Rules.try_swap(_board, a, b):
		print("[VerticalSlice] ILLEGAL_SWAP ", a._to_debug_string(), " <-> ", b._to_debug_string(),
				" t=", _elapsed_msec())
		return
	var pa: int = _board.cell_at(a).piece.kind_id
	var pb: int = _board.cell_at(b).piece.kind_id
	_remove_view(a)
	_remove_view(b)
	_add_view(a, pa)
	_add_view(b, pb)
	_state = 1  # RESOLVING
	var pre_state: int = _session.state
	var events: Array = _run_session_swap(a, b)
	_apply_events(events)
	_state = 0
	_swap_count += 1
	if _session.state == Session.State.WON and pre_state != Session.State.WON:
		_win_count += 1
		print("[VerticalSlice] WIN swap_count=", _swap_count,
				" score=", _session.score, " t=", _elapsed_msec())
	elif _session.state == Session.State.LOST and pre_state != Session.State.LOST:
		_death_count += 1
		print("[VerticalSlice] LOSS swap_count=", _swap_count,
				" score=", _session.score, " t=", _elapsed_msec())
	_refresh_hud()

func _run_session_swap(a: Coord, b: Coord) -> Array:
	# Drive the session.attempt_swap but capture the resolution events.
	# The simplest way: drive session.attempt_swap and listen to its
	# side effects on the board, then run a fresh resolve to capture
	# the events for view updates. We accept one duplicate resolve
	# (session already resolved) for the screenshot/profile run.
	if _session.attempt_swap(a, b):
		# The session already resolved once. For visual fidelity we
		# re-resolve on the (now emptied/refilled) board to capture
		# events for any cascaded state. Resolving on a stable board
		# is a no-op so this is cheap.
		var result: Resolution.CascadeResult = Resolution.resolve(_board, _rng)
		return result.events
	return []

# ----------------------------------------------------------------------------
# View updates
# ----------------------------------------------------------------------------

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
# Utilities
# ----------------------------------------------------------------------------

func _elapsed_msec() -> int:
	return Time.get_ticks_msec() - _start_time_msec

## Programmatic win-and-restart path used by the headless profile
## run. Sets moves_remaining to 0 then retries to capture baseline
## timings. Not bound to input.
func _headless_force_loss_and_retry() -> void:
	_session.moves_remaining = 0
	_session.retry(_rng_seed_used)
	_render_initial()
	_refresh_hud()
	print("[VerticalSlice] RETRY seed=", _rng_seed_used,
			" moves=", _session.moves_remaining, " t=", _elapsed_msec())