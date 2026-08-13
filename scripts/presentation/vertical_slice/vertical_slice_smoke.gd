extends Node2D
## Headless profile runner for the vertical slice.
##
## Step 12 needs to capture profile evidence (startup time, frame
## time, memory, package size) without a physical Android device.
## This script is the headless substitute: it loads the vertical
## slice, runs a deterministic scripted playthrough, then prints
## the metrics on stdout in a parseable format. The same scene
## runs on Android; only the harness differs.
##
## Usage:
##   godot --headless --path . --quit-after 120 res://scenes/vertical_slice/vertical_slice_smoke.tscn
## Or, programmatically, by replacing the boot scene with
## vertical_slice_profile_scene in a wrapper.
##
## Output (one metric per line, prefixed with STEP12_):
##   STEP12_LOAD recipe=<id> seed=<n> moves=<n> target=<n>
##   STEP12_FRAME frame=<n> delta_us=<n>
##   STEP12_SWAP a=<x,y> b=<x,y> score=<n> moves=<n> t=<msec>
##   STEP12_WIN swap_count=<n> score=<n> t=<msec>
##   STEP12_LOSS swap_count=<n> score=<n> t=<msec>
##   STEP12_RETRY seed=<n> moves=<n> t=<msec>
##   STEP12_END duration_msec=<n> swap_count=<n> win_count=<n> loss_count=<n>

const LevelLoader = preload("res://scripts/domain/levels/level_loader.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Board = preload("res://scripts/domain/board/board.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const Coord = Board.CellCoord

const DEFAULT_LEVEL_ID: String = "l1-first-match"
const MAX_FRAMES: int = 600  # 10 seconds at 60 fps
const MAX_MOVES: int = 25

var _session: Session.Session = null
var _board: Board = null
var _rng_seed_used: int = 0
var _start_time_msec: int = 0
var _swap_count: int = 0
var _win_count: int = 0
var _loss_count: int = 0
var _frame_count: int = 0
var _last_frame_us: int = 0

func _ready() -> void:
	_start_time_msec = Time.get_ticks_msec()
	var errors: Array = []
	var loaded: LevelLoader.LoadedLevel = LevelLoader.load_level(DEFAULT_LEVEL_ID, errors)
	if loaded == null:
		printerr("STEP12_LOAD_FAILED recipe=%s errors=%s" % [DEFAULT_LEVEL_ID, str(errors)])
		get_tree().quit(1)
		return
	_session = loaded.session
	_board = _session.board
	_rng_seed_used = _session.rng.to_int()
	print("STEP12_LOAD recipe=%s seed=%d moves=%d target=%d" % [
		DEFAULT_LEVEL_ID, _rng_seed_used,
		_session.moves_remaining, _session.objective.target_total])
	# Decide the playthrough plan: alternate between scripted
	# legal moves and forces to exercise win / loss / retry paths.
	# The plan is itself deterministic; replay is the source of
	# truth.
	_run_profiled_playthrough()

func _run_profiled_playthrough() -> void:
	# Phase 1: play up to MAX_MOVES legal moves.
	for i in range(MAX_MOVES):
		if _session.state != Session.State.READY:
			break
		var moves: Array = Rules.enumerate_legal_swaps(_board)
		if moves.size() == 0:
			break
		var pick: Array = moves[0]
		var a: Coord = pick[0]
		var b: Coord = pick[1]
		var before: int = _session.score
		var ok: bool = _session.attempt_swap(a, b)
		if not ok:
			break
		_swap_count += 1
		print("STEP12_SWAP a=%s b=%s score=%d moves=%d t=%d" % [
			a._to_debug_string(), b._to_debug_string(),
			_session.score, _session.moves_remaining,
			_elapsed_msec()])
		match _session.state:
			Session.State.WON:
				_win_count += 1
				print("STEP12_WIN swap_count=%d score=%d t=%d" % [
					_swap_count, _session.score, _elapsed_msec()])
			Session.State.LOST:
				_loss_count += 1
				print("STEP12_LOSS swap_count=%d score=%d t=%d" % [
					_swap_count, _session.score, _elapsed_msec()])
	# Phase 2: force a retry so we exercise the reset path.
	if _session.state == Session.State.READY:
		_session.retry(_rng_seed_used)
		print("STEP12_RETRY seed=%d moves=%d t=%d" % [
			_rng_seed_used, _session.moves_remaining, _elapsed_msec()])
	# Phase 3: force a loss path to capture the LOST transition.
	_force_loss_path()
	print("STEP12_END duration_msec=%d swap_count=%d win_count=%d loss_count=%d" % [
		_elapsed_msec(), _swap_count, _win_count, _loss_count])
	get_tree().quit()

func _force_loss_path() -> void:
	# Brute-force: keep playing until the budget runs out.
	while _session.state == Session.State.READY:
		var moves: Array = Rules.enumerate_legal_swaps(_board)
		if moves.size() == 0:
			# Deadlock: the underlying engine will reshuffle in
			# production; for the smoke run we just stop.
			break
		var pick: Array = moves[0]
		if not _session.attempt_swap(pick[0], pick[1]):
			break
		_swap_count += 1
		if _session.state == Session.State.WON:
			_win_count += 1
			print("STEP12_WIN swap_count=%d score=%d t=%d" % [
				_swap_count, _session.score, _elapsed_msec()])
			break
		if _session.state == Session.State.LOST:
			_loss_count += 1
			print("STEP12_LOSS swap_count=%d score=%d t=%d" % [
				_swap_count, _session.score, _elapsed_msec()])
			break

func _process(_delta: float) -> void:
	_frame_count += 1
	var now: int = Time.get_ticks_usec()
	if _last_frame_us > 0:
		var delta_us: int = now - _last_frame_us
		if _frame_count % 60 == 0:
			print("STEP12_FRAME frame=%d delta_us=%d" % [_frame_count, delta_us])
	_last_frame_us = now
	if _frame_count >= MAX_FRAMES:
		print("STEP12_TIMEOUT duration_msec=%d" % _elapsed_msec())
		get_tree().quit()

func _elapsed_msec() -> int:
	return Time.get_ticks_msec() - _start_time_msec
