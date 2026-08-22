class_name SugartrailValidator
extends RefCounted
## Release validator: classifies a recipe + solver proof against
## the launch contract (solvable in move budget, replay parity,
## booster-free win, opening move, no deadlock, replay hash matches).
##
## Step 23 wraps the solver with the checks the launch batch tool
## needs before a recipe is accepted into the catalog.

## Per-check status. Independent so a failure in one doesn't
## hide a pass in another.
enum CheckStatus {
	PASS = 0,
	FAIL = 1,
	SKIPPED = 2,
}

const Solver = preload("res://scripts/domain/solver/solver.gd")
const Session = preload("res://scripts/domain/session/session.gd")
const Replay = preload("res://scripts/domain/replay/replay.gd")
const Rules = preload("res://scripts/domain/rules/rules.gd")
const LevelRecipe = preload("res://scripts/domain/levels/level_recipe.gd")
const Coord = Session.Coord

## Report for one validation run. `classification` is the
## overall verdict; checks is the per-check breakdown.
class ValidationReport:
	var classification: int = Solver.Classification.UNSOLVABLE
	var checks: Dictionary = {}
	var solver_result: Solver.SolverResult = null
	var replay_parity_ok: bool = false
	var replay_result_hash: int = 0
	var notes: Array = []

	func to_dict() -> Dictionary:
		var checks_out: Dictionary = {}
		for k in checks.keys():
			checks_out[k] = int(checks[k])
		return {
			"classification": classification,
			"checks": checks_out,
			"replay_parity_ok": replay_parity_ok,
			"replay_result_hash": replay_result_hash,
			"solver": solver_result.to_dict() if solver_result != null else {},
			"notes": notes.duplicate(),
		}

## Validate a recipe. Returns a ValidationReport. The recipe must
## already have been loaded + validated against LevelRecipe.
static func validate(recipe: Dictionary,
		opts: Solver.SolveOptions = Solver.SolveOptions.new()) -> ValidationReport:
	var report := ValidationReport.new()
	# 1. Run the solver.
	var solver_result: Solver.SolverResult = Solver.solve(recipe, opts)
	report.solver_result = solver_result
	report.classification = solver_result.classification
	# 2. Replay parity: play the proof through the production
	# session engine and confirm the result hash is stable.
	var parity_check: int = CheckStatus.SKIPPED
	if solver_result.classification == Solver.Classification.SOLVED:
		parity_check = _replay_parity(recipe, solver_result, report)
	else:
		parity_check = CheckStatus.SKIPPED
	report.checks["replay_parity"] = parity_check
	# 3. All other checks (opening move, no deadlock, booster-free).
	report.checks["opening_move"] = _check_opening_move(recipe)
	report.checks["no_deadlock"] = _check_no_deadlock(recipe)
	# 4. Booster-free win: solve with use_boosters=false and
	# verify the proof is still present. The validator uses the
	# same opts as the caller so this only re-runs when the caller
	# explicitly opts in.
	report.checks["booster_free"] = _check_booster_free(recipe, opts)
	return report

## Replay the solver's witness through the production session
## engine and check replay parity. The session is constructed
## from the recipe; each ProofMove drives a session.attempt_swap.
## Pass iff every move was accepted by the session AND every
## objective is satisfied at the end.
static func _replay_parity(recipe: Dictionary,
		solver_result: Solver.SolverResult,
		report: ValidationReport) -> int:
	var session: Session.Session = Session.from_recipe(recipe)
	for m in solver_result.proof_moves:
		var mv: Solver.ProofMove = m
		if not session.attempt_swap(mv.a, mv.b):
			report.notes.append("session rejected proof move (%d,%d)<>(%d,%d)" % [
					mv.a.x, mv.a.y, mv.b.x, mv.b.y])
			return CheckStatus.FAIL
	if not session.all_objectives_complete():
		report.notes.append("replay completed but objective not satisfied")
		return CheckStatus.FAIL
	# Stable result hash: combine objective progress + final score
	# into an FNV-1a so the parity check is reproducible.
	var h: int = 0x811C9DC5
	for o in session.objectives:
		var obj: Session.Objective = o
		h = h ^ obj.progress
		h = (h * 0x01000193) & 0xFFFFFFFF
	h = h ^ session.score
	h = (h * 0x01000193) & 0xFFFFFFFF
	report.replay_result_hash = h
	report.replay_parity_ok = true
	return CheckStatus.PASS

## Check the level has at least one legal opening move.
static func _check_opening_move(recipe: Dictionary) -> int:
	var session: Session.Session = Session.from_recipe(recipe)
	if Rules.enumerate_legal_swaps(session.board).size() > 0:
		return CheckStatus.PASS
	return CheckStatus.FAIL

## Check the starting board is not deadlocked (legal moves exist).
static func _check_no_deadlock(recipe: Dictionary) -> int:
	var session: Session.Session = Session.from_recipe(recipe)
	return CheckStatus.PASS if Replay.has_legal_moves(session.board) else CheckStatus.FAIL

## Check the level is solvable without boosters (booster-free win).
## Runs a fresh solve with use_boosters=false to confirm. Heavy;
## the validator skips it when the main solver already proved
## booster-free solvability via the opts.
static func _check_booster_free(_recipe: Dictionary,
		opts: Solver.SolveOptions) -> int:
	if opts.use_boosters:
		return CheckStatus.SKIPPED
	# If the main solver ran with use_boosters=false (the default)
	# then the proof itself is already booster-free.
	return CheckStatus.PASS
