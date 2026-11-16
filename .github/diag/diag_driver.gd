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
var _sweep_started: int = 0
var _swept: bool = false
var _spawned: bool = false
const BASE508 = preload("res://scripts/lineagem_base508.gd")

## Every admitted 523 NPC through the same projection Monster.setup runs on a
## spawn (patch523_npc_catalog.project_actor_record), plus npc_definition().
func _sweep(world: Node) -> void:
	var service: Variant = world.get("patch523_npc_spells")
	var catalog: Variant = service.get("catalog") if service != null else null
	if catalog == null:
		_say("sweep: no catalog")
		return
	var registry: Variant = catalog.get("admitted_source_identities")
	var ids: Array = (registry as Dictionary).keys() if registry is Dictionary else []
	_say("sweep: %d admitted npc ids, source_available=%s mode=%s" % [ids.size(), str(catalog.get("source_available")), str(catalog.get("source_mode"))])
	var done: int = 0
	for key: Variant in ids:
		var npc_id: int = int(str(key))
		print("DIAG_SWEEP npc=%d" % npc_id)
		var record: Dictionary = BASE508.npc_record(npc_id, {"source_m_npc_id": npc_id})
		var projected: Variant = catalog.project_actor_record(record)
		if not projected is Dictionary: _say("sweep: npc %d projected %s" % [npc_id, type_string(typeof(projected))])
		var definition: Variant = catalog.npc_definition(npc_id)
		if not definition is Dictionary: _say("sweep: npc %d definition %s" % [npc_id, type_string(typeof(definition))])
		done += 1
	_say("sweep done %d" % done)

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
		if scene.has_method("loading_readiness") and now - last_tick >= 1000:
			_say("readiness " + JSON.stringify(scene.call("loading_readiness")) + " aden_play=" + str(scene.get("current523_aden_play_active")) + " problem=" + str(scene.get("current523_aden_play_problem")) + " field_map=" + str(scene.get("field_map")))
		if not entered and not get_tree().paused:
			entered = QA.enter_game(scene)
			if entered:
				_say("entered game, class=" + str(scene.get("job_class")))
				_sweep_started = now
		if now - last_tick >= 1000:
			last_tick = now
			var monsters: int = get_tree().get_nodes_in_group("monsters").size()
			var loading: Node = _find_loading(get_tree().root)
			var stage: String = "" if loading == null else str(loading.get("_status_text") if loading.get("_status_text") != null else "") + " awaiting=" + str(loading.get("_awaiting_title")) + " running=" + str(loading.get("_running"))
			_say("tick paused=%s monsters=%d fps=%d loading=%s" % [get_tree().paused, monsters, Engine.get_frames_per_second(), stage])
		if entered and not _swept and not get_tree().paused and now - _sweep_started > 5000:
			_swept = true
			_sweep(scene)
		if entered and _swept and not _spawned and now - _sweep_started > 15000:
			_spawned = true
			if scene.has_method("_spawn_monsters"):
				_say("spawning 12 monsters via world._spawn_monsters")
				scene.call("_spawn_monsters", 12)
				_say("spawn call returned")
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
