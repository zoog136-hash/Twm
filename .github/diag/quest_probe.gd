extends SceneTree
func _initialize() -> void:
	var src = load("res://scripts/quests/source_quest523.gd").new()
	var ok: bool = src.load_pack()
	print("QPROBE ok=%s problem=%s quests=%d" % [ok, src.problem, src.quests.size()])
	quit(0)
