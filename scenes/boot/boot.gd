extends Node
## Boot scene controller for Sugartrail.
##
## The boot scene is the single entry point referenced by project.godot
## (run/main_scene). Its only job during Step 01 is to confirm the engine
## can construct the scene tree, then quit cleanly so a headless launch
## can be verified.
##
## No gameplay, presentation, or persistence wiring belongs in this file.
## Real navigation, loading, and start-up flow arrive in later steps.

func _ready() -> void:
	print("[Sugartrail.boot] Scene tree ready at ", Time.get_datetime_string_from_system())
	# Quit after one frame so headless verification can confirm a clean
	# open -> render -> exit cycle. Real start-up flow replaces this in
	# the application layer (planned for Phase C).
	get_tree().create_timer(0.1).timeout.connect(_on_boot_complete)

func _on_boot_complete() -> void:
	print("[Sugartrail.boot] Boot complete; exiting for headless verification.")
	get_tree().quit()