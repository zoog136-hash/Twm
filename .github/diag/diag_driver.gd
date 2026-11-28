extends Node
## Diagnostic driver (Twm diag workflow only; never in the game repo).
## Presses through the title, enters the game, keeps the world running for
## PLAY_SECONDS and prints timestamps so SCRIPT ERROR lines can be placed.
const PLAY_SECONDS: float = 240.0
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
## Bag mode: the bag cold, another menu, the bag again (traced function by function).
const BAG_WINDOWS: Array = ["inventory", "equipment_collections", "card_collections", "monsterbook523", "map", "skills", "status_board", "quests", "crafting", "growth96", "titles", "guardians", "inventory", "equipment_collections", "skills"]
const WINDOWS: Array = ["crafting", "tj_coupons", "domination_stone", "card_collections", "emblems", "shop", "source_dungeons", "auto", "teleport", "npc_shop", "inventory", "skills", "map", "titles", "guardians", "status_board"]
var _win_index: int = 0
var _combat_trace: FileAccess = null
var _combat_started: int = 0
var _combat_done: bool = false

## Spawn real monsters near the player, then auto-hunt with every function
## entry traced to a file (main thread) for COMBAT_TRACE_MS.
const COMBAT_TRACE_MS: int = 40000
var _last_refill: int = 0
## Keep the spawned monster's region full (up to 8 alive) around the player,
## so auto-hunting attacks continuously during the trace.
func _fill_region(world: Node) -> void:
	var population: Variant = world.get("field_population")
	if population == null or _spawn_regions.is_empty(): return
	var region: Dictionary = (_spawn_regions[0] as Dictionary).region
	var alive: int = 0
	for slot: Dictionary in population.get("slots"):
		if not is_same(slot.region, region): continue
		var monster: Variant = slot.get("monster")
		if is_instance_valid(monster) and not monster.dead:
			alive += 1
			continue
		if alive >= 8: break
		slot["remaining"] = 0.0
		population.call("_spawn_slot", slot)
		if is_instance_valid(slot.get("monster")): alive += 1
	var player: Node2D = world.get("player")
	var nearest: float = INF
	for m: Node in get_tree().get_nodes_in_group("monsters"):
		if m is Node2D and not m.get("dead"): nearest = minf(nearest, (m as Node2D).global_position.distance_to(player.global_position))
	_say("combat region alive=%d monsters=%d nearest=%.0f auto=%s hp=%s" % [alive, get_tree().get_nodes_in_group("monsters").size(), nearest, str(player.get("auto_enabled")), str(world.get("hp"))])
func _combat_step(world: Node, now: int) -> void:
	if _combat_done: return
	if _combat_started == 0:
		if _spawned_ok < 1 and not _spawn_done:
			_spawn_step(world)
			return
		var player: Node = world.get("player")
		_fill_region(world)
		# As on the phone video: auto-hunt with the bag open (pickups refresh it).
		var hud: Node = _find_hud(world)
		if hud != null and OS.get_environment("DIAG_BAG") != "0": hud.call("_navigate", "inventory")
		player.call("set_auto_enabled", true)
		_combat_trace = FileAccess.open("/mnt/w/fn_combat.txt", FileAccess.WRITE)
		_combat_trace.store_line("DIAG_TRACE begin combat")
		Engine.set_meta(&"diag_trace", _combat_trace)
		_combat_started = now
		_say("combat trace started (spawned %d)" % _spawned_ok)
		return
	if now - _last_refill > 4000:
		_last_refill = now
		_fill_region(world)
	if now - _combat_started >= COMBAT_TRACE_MS:
		Engine.remove_meta(&"diag_trace")
		_combat_trace.store_line("DIAG_TRACE end combat %d ms" % (now - _combat_started))
		_combat_trace.close()
		_combat_done = true
		_say("combat trace done")
## Skills mode: learn every buff and area skill of the class, then cast them
## one by one (cooldowns, MP and HP refilled) with every function traced.
## Prints each cast's call time and the worst frame in the 1.5 s after it.
var _sk_list: Array = []
var _sk_index: int = 0
var _sk_next: int = 0
var _sk_frame_at: int = 0
var _sk_worst: int = 0
var _sk_current: String = ""
func _skills_step(world: Node, now: int) -> void:
	if _combat_done: return
	var frame_at: int = Time.get_ticks_usec()
	if _sk_frame_at > 0: _sk_worst = maxi(_sk_worst, frame_at - _sk_frame_at)
	_sk_frame_at = frame_at
	var svc: Object = world.get("original_skills")
	if svc == null: return
	var cat: Object = svc.get("catalog")
	if _combat_started == 0:
		if _spawned_ok < 1 and not _spawn_done:
			_spawn_step(world)
			return
		_fill_region(world)
		world.set("level", maxi(int(world.get("level")), 90))
		for r: Variant in cat.get("records"):
			if not r is Dictionary or not bool(cat.call("permitted", r)) or bool(r.get("runtime_blocked", false)) or str(r.get("activation", "")) == "passive": continue
			var mode: String = str(r.get("mode", ""))
			if bool(svc.call("is_area_cast", r)) or mode in ["buff", "counter", "stealth"]:
				_sk_list.append(r)
				(cat.get("learned") as Dictionary)[str(r.get("id", ""))] = 1
		cat.set("revision", int(cat.get("revision")) + 1)
		_say("skills list %d (class %s)" % [_sk_list.size(), str(world.get("job_class"))])
		_combat_trace = FileAccess.open("/mnt/w/fn_skills.txt", FileAccess.WRITE)
		_combat_trace.store_line("DIAG_TRACE begin skills")
		Engine.set_meta(&"diag_trace", _combat_trace)
		_combat_started = now
		_sk_next = now + 1500
		return
	if now - _last_refill > 4000:
		_last_refill = now
		_fill_region(world)
	if now < _sk_next: return
	if not _sk_current.is_empty():
		_say("DIAG_CAST_FRAME %s worst_frame_ms=%d" % [_sk_current, _sk_worst / 1000])
		_sk_current = ""
	if _sk_index >= _sk_list.size() * 2 or now - _combat_started > 240000:
		Engine.remove_meta(&"diag_trace")
		_combat_trace.store_line("DIAG_TRACE end skills %d ms" % (now - _combat_started))
		_combat_trace.close()
		_combat_done = true
		_say("skills trace done")
		return
	if not (world.get("pending_attack") as Dictionary).is_empty():
		_sk_next = now + 200
		return
	var record: Dictionary = _sk_list[_sk_index % _sk_list.size()]
	var pass_name: String = "first" if _sk_index < _sk_list.size() else "again"
	_sk_index += 1
	world.set("skill_global_cooldown", 0.0)
	(world.get("skill_cooldowns") as Dictionary).clear()
	world.set("mp", int(world.call("_effective_max_mp")))
	world.set("hp", int(world.call("_effective_max_hp")))
	var label: String = "%s|%s|%s|%s" % [pass_name, str(record.get("id", "")), str(record.get("name", "")), str(record.get("mode", ""))]
	var reason: String = str(svc.call("cost_reason", record, false))
	# First pass traced function by function; the repeat runs untraced so its
	# call time is not inflated by the tracer.
	var traced: bool = pass_name == "first"
	if traced:
		Engine.set_meta(&"diag_trace", _combat_trace)
		_combat_trace.store_line("DIAG_TRACE mark cast " + label)
	else: Engine.remove_meta(&"diag_trace")
	var t0: int = Time.get_ticks_usec()
	var ok: bool = bool(svc.call("cast", record, true))
	var spent: int = Time.get_ticks_usec() - t0
	if traced: _combat_trace.store_line("DIAG_TRACE mark called")
	_say("DIAG_CAST %s ok=%s call_ms=%.1f reason=%s" % [label, str(ok), spent / 1000.0, reason])
	_sk_current = label
	_sk_worst = 0
	_sk_frame_at = Time.get_ticks_usec()
	_sk_next = now + 1500

## DIAG_BIGBAG=1: before the mode runs, fill the bag with ~300 distinct real
## items (every Nth original ItemClass with a native record) through the same
## receipted supply a box uses, so bag/save costs match a late-game phone bag.
var _bigbag_done: bool = false
func _grant_big_bag(world: Node) -> void:
	_bigbag_done = true
	var rows: Script = load("res://scripts/resources/current523_definition_rows.gd")
	var ids: Variant = rows.call("column", "ItemClass", "ID")
	var supply: Script = load("res://scripts/loot/patch523_item_inventory.gd")
	var picked: Array = []
	var step: int = 7
	var i: int = 0
	var scan_started: int = Time.get_ticks_msec()
	while i < ids.size() and picked.size() < 300 and Time.get_ticks_msec() - scan_started < 30000:
		var id: int = int(ids[i])
		i += step
		if id <= 0: continue
		var record: Dictionary = world.call("source_item_record", id, 1)
		if record.is_empty():
			var definition: Variant = world.call("source_item_definition", id)
			if definition is Dictionary and not (definition as Dictionary).is_empty(): record = world.call("source_item_record", id, 1)
		if record.is_empty(): continue
		picked.append({"item_class_id": id, "amount": 1, "bless_raw": 1, "enchant": 0})
	var ok: int = 0
	var t0: int = Time.get_ticks_msec()
	for start: int in range(0, picked.size(), 25):
		var batch: Array = picked.slice(start, start + 25)
		var staged: Dictionary = supply.call("stage", world, batch, {"kind": "twilight_debug_catalog"})
		if not staged.get("ok", false):
			_say("bigbag stage refused: " + str(staged.get("reason", staged)).left(160))
			continue
		if supply.call("commit", world, batch, {"kind": "twilight_debug_catalog", "initial_level_origin": "twilight_debug_default_zero"}): ok += batch.size()
	_say("bigbag granted %d of %d picked in %d ms, inventory=%d instances=%d" % [ok, picked.size(), Time.get_ticks_msec() - t0, (world.get("inventory") as Dictionary).size(), (world.get("item_instances") as Dictionary).size() if world.get("item_instances") is Dictionary else -1])

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
		print("DIAG_WIN %s open_ms=%d worst_frame_ms=%d frames=%d nodes=%d res=%d" % [_win_name, _win_open_at, _win_worst, _win_frames, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])
		if Engine.has_meta(&"diag_trace"): (Engine.get_meta(&"diag_trace") as FileAccess).store_line("DIAG_TRACE end win%d_%s %d ms" % [_win_index, _win_name, _win_open_at])
		hud.call("_close_workspace")
	var list: Array = BAG_WINDOWS if OS.get_environment("DIAG_MODE") == "bag" else WINDOWS
	if _win_index >= list.size():
		_win_index = WINDOWS.size()
		if Engine.has_meta(&"diag_trace"):
			(Engine.get_meta(&"diag_trace") as FileAccess).close()
			Engine.remove_meta(&"diag_trace")
			_say("bag trace done")
		return
	_win_name = list[_win_index]
	_win_index += 1
	if OS.get_environment("DIAG_MODE") == "bag" and not Engine.has_meta(&"diag_trace"):
		Engine.set_meta(&"diag_trace", FileAccess.open("/mnt/w/fn_bag.txt", FileAccess.WRITE))
	if Engine.has_meta(&"diag_trace"): (Engine.get_meta(&"diag_trace") as FileAccess).store_line("DIAG_TRACE begin win%d_%s" % [_win_index, _win_name])
	if Engine.has_meta(&"diag_trace"): (Engine.get_meta(&"diag_trace") as FileAccess).store_line("FN %d diag:open_%s" % [Time.get_ticks_usec(), _win_name])
	print("DIAG_NODES before %s nodes=%d objs=%d res=%d" % [_win_name, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT)), int(Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))])
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

var _mem_at: int = -100000
func _mem_line(now: int) -> void:
	if now - _mem_at < 2000: return
	_mem_at = now
	var rss: String = ""; var hwm: String = ""
	# /proc files report length 0: read line by line.
	var f := FileAccess.open("/proc/self/status", FileAccess.READ)
	if f != null:
		while not f.eof_reached():
			var line: String = f.get_line()
			if line.begins_with("VmRSS:"): rss = line.substr(6).strip_edges()
			if line.begins_with("VmHWM:"): hwm = line.substr(6).strip_edges()
	print("DIAG_MEM t=%d static=%dMB static_peak=%dMB rss=%s hwm=%s tex=%dMB nodes=%d objs=%d" % [now/1000, OS.get_static_memory_usage()/1048576, OS.get_static_memory_peak_usage()/1048576, rss, hwm, int(Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED))/1048576, int(Performance.get_monitor(Performance.OBJECT_NODE_COUNT)), int(Performance.get_monitor(Performance.OBJECT_COUNT))])

func _process(_delta: float) -> void:
	var now: int = Time.get_ticks_msec()
	_mem_line(now)
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
			entered = QA.enter_game(scene, OS.get_environment("DIAG_CLASS") if not OS.get_environment("DIAG_CLASS").is_empty() else "기사")
			if entered:
				_say("entered game, class=" + str(scene.get("job_class")))
				_sweep_started = now
		if entered and OS.get_environment("DIAG_BIGBAG") == "1" and not _bigbag_done and now - _sweep_started > 6000:
			_grant_big_bag(scene)
		if now - last_tick >= 1000:
			last_tick = now
			var monsters: int = get_tree().get_nodes_in_group("monsters").size()
			var loading: Node = _find_loading(get_tree().root)
			var stage: String = "" if loading == null else str(loading.get("_status_text") if loading.get("_status_text") != null else "") + " awaiting=" + str(loading.get("_awaiting_title")) + " running=" + str(loading.get("_running"))
			_say("tick paused=%s monsters=%d fps=%d loading=%s" % [get_tree().paused, monsters, Engine.get_frames_per_second(), stage])
		if entered and OS.get_environment("DIAG_MODE") == "pixels" and not get_tree().paused and now - _sweep_started > 12000 and not _pixels_started:
			_pixels_started = true
			_pixel_run(scene)
		if entered and OS.get_environment("DIAG_MODE") == "save" and not _save_traced and now - _sweep_started > 15000:
			_save_traced = true
			_save_trace(scene)
		if entered and OS.get_environment("DIAG_MODE") == "combat" and not get_tree().paused and now - _sweep_started > 8000:
			_combat_step(scene, now)
		elif entered and OS.get_environment("DIAG_MODE") == "skills" and not get_tree().paused and now - _sweep_started > 8000:
			_skills_step(scene, now)
		elif entered and OS.get_environment("DIAG_SKIP_WINDOWS") != "1" and not OS.get_environment("DIAG_MODE") in ["combat", "skills"] and not get_tree().paused and now - _sweep_started > 15000 and _win_index < WINDOWS.size() and now - _win_last > 2500:
			_win_last = now
			_window_step(scene)
		if now - world_at >= int(PLAY_SECONDS * 1000.0) and OS.get_environment("DIAG_MODE") != "pixels" and not (OS.get_environment("DIAG_MODE") == "skills" and not _combat_done):
			_say("DIAG_DONE survived %.0fs in world" % PLAY_SECONDS)
			get_tree().quit(0)
	if now - started > int(OS.get_environment("DIAG_TIMEOUT_S") if not OS.get_environment("DIAG_TIMEOUT_S").is_empty() else "2400") * 1000:
		_say("DIAG_TIMEOUT")
		get_tree().quit(3)

func _find_loading(node: Node) -> Node:
	if node != get_tree().root and node.get("_awaiting_title") != null: return node
	for child: Node in node.get_children():
		var found: Node = _find_loading(child)
		if found != null: return found
	return null


## Map ground pixels: the renderer's own tile pass drawn into a private
## viewport (nothing else on it) at fixed offsets from the entry position, so
## two builds compare ground pixels only (no actors, HUD or animation).
var _pixels_started: bool = false
const PIXEL_OFFSETS: Array = [Vector2(0, 0), Vector2(384, 0), Vector2(0, 288), Vector2(-512, -256), Vector2(900, 400), Vector2(-900, 500), Vector2(260, -700), Vector2(0, 0)]
func _find_renderer(n: Node) -> Node:
	if n.has_method("_draw_tiles") and n.has_method("_build_frame"): return n
	for c: Node in n.get_children():
		var f: Node = _find_renderer(c)
		if f != null: return f
	return null

func _pixel_run(world: Node) -> void:
	DirAccess.make_dir_recursive_absolute("/mnt/w/px")
	var renderer: Node = _find_renderer(world)
	if renderer == null:
		_say("PIXELS no renderer"); get_tree().quit(4); return
	var player: Node2D = world.get("player")
	var home: Vector2 = player.global_position
	player.call("set_auto_enabled", false) if player.has_method("set_auto_enabled") else null
	for index: int in PIXEL_OFFSETS.size():
		player.global_position = home + PIXEL_OFFSETS[index]
		if player is CharacterBody2D: (player as CharacterBody2D).velocity = Vector2.ZERO
		var camera: Variant = player.get("camera")
		if camera is Camera2D: (camera as Camera2D).reset_smoothing(); (camera as Camera2D).force_update_scroll()
		for i: int in 5: await get_tree().process_frame
		renderer.call("refresh_visible")
		for i: int in 40: await get_tree().process_frame
		var view: Rect2 = renderer.call("_view_rect")
		var delta: Vector2 = renderer.get("_visual_delta")
		var capture := SubViewport.new()
		capture.size = Vector2i(view.size)
		capture.transparent_bg = false
		capture.disable_3d = true
		capture.canvas_item_default_texture_filter = Viewport.DEFAULT_CANVAS_ITEM_TEXTURE_FILTER_NEAREST
		capture.render_target_update_mode = SubViewport.UPDATE_ONCE
		var canvas := Node2D.new()
		canvas.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		var ground: Variant = renderer.get("_tile_ground")
		if ground is CanvasItem and (ground as CanvasItem).material != null: canvas.material = (ground as CanvasItem).material
		canvas.position = delta - view.position
		canvas.draw.connect(func() -> void: renderer.call("_draw_tiles", canvas))
		capture.add_child(canvas)
		add_child(capture)
		for i: int in 4: await get_tree().process_frame
		var image: Image = capture.get_texture().get_image()
		image.save_png("/mnt/w/px/%02d.png" % index)
		var metrics: Dictionary = renderer.call("frame_metrics")
		print("DIAG_PIXEL %d pos=%s view=%s problem=%s draw_commands=%s blocks=%s" % [index, str(player.global_position), str(view), str(renderer.get("problem")), str(metrics.get("draw_commands")), str(metrics.get("visible_blocks", "-"))])
		capture.queue_free()
	_say("PIXELS done")
	get_tree().quit(0)


## Save cost: five quiet saves traced function by function.
var _save_traced: bool = false
func _save_trace(world: Node) -> void:
	var trace := FileAccess.open("/mnt/w/fn_save.txt", FileAccess.WRITE)
	Engine.set_meta(&"diag_trace", trace)
	for i: int in 5:
		var t0: int = Time.get_ticks_usec()
		var result: Variant = world.call("_save_game", true)
		trace.store_line("FN %d diag:save_done" % Time.get_ticks_usec())
		_say("save %d result=%s ms=%.1f" % [i, str(result), (Time.get_ticks_usec() - t0) / 1000.0])
		for f: int in 5: await get_tree().process_frame
	Engine.remove_meta(&"diag_trace")
	trace.close()
	_say("save trace done")
