extends Node
## Diagnostic driver (Twm diag workflow only; never in the game repo).
## Presses through the title, enters the game, keeps the world running for
## PLAY_SECONDS and prints timestamps so SCRIPT ERROR lines can be placed.
const PLAY_SECONDS: float = 150.0
const QA = preload("res://tests/qa_class_selection.gd")
var started: int = Time.get_ticks_msec()
var world_at: int = -1
var entered: bool = false
var last_tick: int = 0
var pressed_title: int = 0

func _init() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func _say(text: String) -> void:
	print("DIAG t=%.1fs %s" % [(Time.get_ticks_msec() - started) / 1000.0, text])

func _find_title(node: Node) -> Node:
	if node.get("_awaiting_title") == true: return node
	for child: Node in node.get_children():
		var found: Node = _find_title(child)
		if found != null: return found
	return null

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	var title: Node = _find_title(get_tree().root)
	if title != null and now - pressed_title > 2000:
		pressed_title = now
		_say("title: pressing start")
		var key := InputEventKey.new(); key.keycode = KEY_SPACE; key.pressed = true
		Input.parse_input_event(key)
		var up := InputEventKey.new(); up.keycode = KEY_SPACE; up.pressed = false
		Input.parse_input_event(up)
	var scene: Node = get_tree().current_scene
	if scene != null and scene.get_node_or_null("HUD") != null and scene.has_method("resolve_patch523_npc_hit"):
		if world_at < 0:
			world_at = now
			_say("world scene ready: " + str(scene.scene_file_path))
		if not entered and not get_tree().paused:
			entered = QA.enter_game(scene)
			if entered: _say("entered game, class=" + str(scene.get("job_class")))
		if now - last_tick >= 1000:
			last_tick = now
			var monsters: int = get_tree().get_nodes_in_group("monsters").size()
			var loading: Node = _find_loading(get_tree().root)
			var stage: String = "" if loading == null else str(loading.get("_status_text") if loading.get("_status_text") != null else "") + " awaiting=" + str(loading.get("_awaiting_title")) + " running=" + str(loading.get("_running"))
			_say("tick paused=%s monsters=%d fps=%d loading=%s" % [get_tree().paused, monsters, Engine.get_frames_per_second(), stage])
		if now - world_at >= int(PLAY_SECONDS * 1000.0):
			_say("DIAG_DONE survived %.0fs in world" % PLAY_SECONDS)
			get_tree().quit(0)
	if now - started > 2400 * 1000:
		_say("DIAG_TIMEOUT")
		get_tree().quit(3)

func _find_loading(node: Node) -> Node:
	if node != get_tree().root and node.get("_awaiting_title") != null: return node
	for child: Node in node.get_children():
		var found: Node = _find_loading(child)
		if found != null: return found
	return null
