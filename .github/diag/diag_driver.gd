extends Node
## Diagnostic driver (Twm diag workflow only; never in the game repo).
## Presses through the title, enters the game, keeps the world running for
## PLAY_SECONDS and prints timestamps so SCRIPT ERROR lines can be placed.
const PLAY_SECONDS: float = 130.0
const QA = preload("res://diag/diag_qa.gd")
var started: int = Time.get_ticks_msec()
var world_at: int = -1
var entered: bool = false
var last_tick: int = 0
var pressed_title: int = 0
var _sweep_started: int = 0
var _swept: bool = false
var _spawned: bool = false
var _last_hop: int = 0
var _spawn_done: bool = false
## Every HUD window once, timed (open call + the next frames until idle).
const WINDOWS: Array = ["inventory", "equipment_collections", "card_collections", "skills", "quests", "status_board", "character", "crafting", "enhance", "shop", "npc_shop", "exchange", "warehouse", "map", "teleport", "titles", "totems", "guardians", "weapon_mastery", "emblems", "expedition", "source_dungeons", "spell_groups", "card_fusion", "combinations", "domination_stone", "half_elixir", "option_awakening", "settings", "log", "auto", "menu", "promo_code", "tj_coupons", "sell"]
var _win_index: int = 0
var _win_last: int = 0
var _win_open_at: int = 0
var _win_name: String = ""
var _win_frames: int = 0
var _win_worst: int = 0
var _win_prev_tick: int = 0

func _notification(what: int) -> void:
	pass

func _window_step(world: Node) -> void:
	var hud: Node = _find_hud(world)
	if hud == null: return
	if not _win_name.is_empty():
		print("DIAG_WIN %s open_ms=%d worst_frame_ms=%d frames=%d nodes=%d" % [_win_name, _win_open_at, _win_worst, _win_frames, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT))])
		hud.call("_close_workspace")
	_win_name = WINDOWS[_win_index]
	_win_index += 1
	var started: int = Time.get_ticks_usec()
	hud.call("_navigate", _win_name)
	_win_open_at = int((Time.get_ticks_usec() - started) / 1000)
	_win_frames = 0
	_win_worst = 0
	_win_prev_tick = Time.get_ticks_msec()
## Menu -> exchange, the way the phone player reached it (2026-11-17 523.607:
## the release APK closed the moment the exchange was entered).
const UI_STEPS: Array = []
var _ui_step: int = 0
var _ui_last: int = 0

func _find_hud(n: Node) -> Node:
	if n.has_method("_navigate") and n.has_method("toggle_menu"): return n
	for c: Node in n.get_children():
		var f: Node = _find_hud(c)
		if f != null: return f
	return null

func _ui(world: Node) -> void:
	var hud: Node = _find_hud(world)
	var step: String = UI_STEPS[_ui_step]
	_ui_step += 1
	printerr("DIAG_UI begin %s hud=%s" % [step, str(hud)])
	match step:
		"menu": hud.call("toggle_menu")
		"exchange": hud.call("_navigate", "exchange")
		"select", "select2":
			var panel: Node = world.find_child("FrozenExchangePanel", true, false)
			var listing: ItemList = panel.find_child("ExchangeListings", true, false) as ItemList if panel != null else null
			printerr("DIAG_UI panel=%s items=%d" % [str(panel), listing.item_count if listing != null else -1])
			if listing != null and listing.item_count > 0:
				var index: int = 0 if step == "select" else mini(5, listing.item_count - 1)
				listing.select(index)
				listing.item_selected.emit(index)
				var review: Button = panel.find_child("ExchangeReview", true, false) as Button
				if review != null and not review.disabled: review.pressed.emit()
		"close": hud.call("_close_workspace")
	printerr("DIAG_UI end %s" % step)
var _spawn_regions: Array = []
var _spawn_index: int = 0
var _spawn_tries: int = 0
var _spawned_ok: int = 0

## Real spawns through the population's own _spawn_slot (Monster.setup, view,
## art), one region after another. The player is placed at the region only
## for the call (sample_source_spawn needs it within 40 cells) and put back.
func _spawn_step(world: Node) -> void:
	var population: Variant = world.get("field_population")
	if population == null: return
	var field: Variant = population.get("field")
	var slots: Variant = population.get("slots")
	if field == null or not slots is Array: return
	if _spawn_regions.is_empty():
		var seen: Dictionary = {}
		for slot: Dictionary in slots:
			var region: Dictionary = slot.get("region", {})
			if not region.get("source_rect") is Rect2i or region.get("monster_types", []).is_empty(): continue
			var key: String = str(region.get("monster_types", [])[0])
			if seen.has(key): continue
			seen[key] = true
			_spawn_regions.append(slot)
		_say("spawn: %d distinct kinds over %d slots" % [_spawn_regions.size(), (slots as Array).size()])
		if _spawn_regions.is_empty():
			_spawn_done = true
			return
	if _spawn_index >= _spawn_regions.size() or Time.get_ticks_msec() - _sweep_started > 1500 * 1000:
		_say("spawn done: %d kinds tried, %d built" % [_spawn_index, _spawned_ok])
		_spawn_done = true
		return
	var slot: Dictionary = _spawn_regions[_spawn_index]
	var existing: Variant = slot.get("monster")
	if is_instance_valid(existing) and not existing.dead:
		_spawned_ok += 1
		printerr("DIAG_SPAWN_OK %d %s" % [_spawn_index, str(slot.region.monster_types[0])])
		_spawn_index += 1
		_spawn_tries = 0
		return
	if _spawn_tries >= 30:
		printerr("DIAG_SPAWN_GIVEUP %d %s hold=%s" % [_spawn_index, str(slot.region.monster_types[0]), str(slot.get("patch523_spawn_hold", ""))])
		_spawn_index += 1
		_spawn_tries = 0
		return
	_spawn_tries += 1
	var player: Node2D = world.get("player")
	var home: Vector2 = player.global_position
	var rect: Rect2i = slot.region.source_rect
	player.global_position = field.coordinates.to_world(Vector2(rect.get_center()))
	printerr("DIAG_SPAWN %d try=%d %s" % [_spawn_index, _spawn_tries, str(slot.region.monster_types[0])])
	slot["remaining"] = 0.0
	population.call("_spawn_slot", slot)
	printerr("DIAG_SPAWN_RET %d" % _spawn_index)
	var built: Variant = slot.get("monster")
	if is_instance_valid(built):
		# Let the built actor process a few frames (its first ticks are where
		# the phone died) near the player, as on the phone.
		player.global_position = built.global_position + Vector2(40, 0)
	else:
		player.global_position = home
var _hop_index: int = 0

## Moves the player into the next populated source region so the field
## population spawns real monsters through Monster.setup (as on the phone).
func _hop(world: Node) -> void:
	var population: Variant = world.get("field_population")
	if population == null:
		_say("hop: no population")
		return
	var field: Variant = population.get("field")
	var slots: Variant = population.get("slots")
	if field == null or not slots is Array or (slots as Array).is_empty():
		_say("hop: no slots (field=%s)" % str(field))
		return
	var regions: Array = []
	var seen: Dictionary = {}
	for slot: Dictionary in slots:
		var region: Dictionary = slot.get("region", {})
		if not region.get("source_rect") is Rect2i or region.get("monster_types", []).is_empty(): continue
		var key: String = str(region.source_rect)
		if seen.has(key): continue
		seen[key] = true
		regions.append(region)
	if regions.is_empty():
		_say("hop: no regions among %d slots" % (slots as Array).size())
		return
	var region: Dictionary = regions[_hop_index % regions.size()]
	_hop_index += 1
	var rect: Rect2i = region.source_rect
	var target: Vector2 = field.coordinates.to_world(Vector2(rect.get_center()))
	var player: Node2D = world.get("player")
	var alive: int = 0
	for slot: Dictionary in slots:
		var m: Variant = slot.get("monster")
		if is_instance_valid(m) and not m.dead: alive += 1
	_say("hop %d/%d -> %s types=%s (slots=%d alive=%d)" % [_hop_index, regions.size(), str(rect), str(region.get("monster_types", []).slice(0, 3)), (slots as Array).size(), alive])
	player.global_position = target
const BASE508 = preload("res://scripts/lineagem_base508.gd")

## Every admitted 523 NPC through the same projection Monster.setup runs on a
## spawn (patch523_npc_catalog.project_actor_record), plus npc_definition().
func _sweep(world: Node) -> void:
	var service: Variant = world.get("patch523_npc_spells")
	var catalog: Variant = service.get("catalog") if service != null else null
	if catalog == null:
		_say("sweep: no catalog")
		return
	var DEFS = load("res://scripts/resources/current523_definition_rows.gd")
	var seen: Dictionary = {}
	var ids: Array = []
	for row: Dictionary in DEFS.rows("NpcSpawnPackNpcClassView"):
		var id: int = int(row.get("NpcClassID", -1))
		if id > 0 and not seen.has(id):
			seen[id] = true
			ids.append(id)
	_say("sweep: %d spawnable npc ids" % ids.size())
	var limit_until: int = Time.get_ticks_msec() + 900 * 1000
	_say("sweep: %d admitted npc ids, source_available=%s mode=%s" % [ids.size(), str(catalog.get("source_available")), str(catalog.get("source_mode"))])
	var done: int = 0
	for key: Variant in ids:
		var npc_id: int = int(str(key))
		printerr("DIAG_SWEEP npc=%d" % npc_id)
		var record: Dictionary = BASE508.npc_record(npc_id, {"source_m_npc_id": npc_id})
		var projected: Variant = catalog.project_actor_record(record)
		if not projected is Dictionary: _say("sweep: npc %d projected %s" % [npc_id, type_string(typeof(projected))])
		var definition: Variant = catalog.npc_definition(npc_id)
		if not definition is Dictionary: _say("sweep: npc %d definition %s" % [npc_id, type_string(typeof(definition))])
		done += 1
		if done % 50 == 0:
			var admitted: Variant = catalog.get("admitted_source_identities")
			_say("sweep progress %d admitted=%d error=%s" % [done, (admitted as Dictionary).size() if admitted is Dictionary else -1, str(catalog.get("error"))])
		if Time.get_ticks_msec() > limit_until:
			_say("sweep time budget reached")
			break
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
	if not _win_name.is_empty():
		_win_frames += 1
		if _win_frames > 1: _win_worst = maxi(_win_worst, now - _win_prev_tick)
		_win_prev_tick = now
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
		if entered and not get_tree().paused and now - _sweep_started > 15000 and _win_index < WINDOWS.size() and now - _win_last > 2500:
			_win_last = now
			_window_step(scene)
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
