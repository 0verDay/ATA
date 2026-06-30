extends Node2D

func _ready() -> void:
	queue_redraw()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed:
		get_tree().change_scene_to_file("res://scenes/lobby/Lobby.tscn")

func _draw() -> void:
	var vsize := get_viewport_rect().size
	var inv   := GameData.result_inventory
	var ok    := GameData.result_success

	# Dark overlay
	draw_rect(Rect2(Vector2.ZERO, vsize), Color(0, 0, 0, 0.92))

	# Title
	var title_col := Color.WHITE if ok else Color(0.27, 0.27, 0.27)
	draw_string(ThemeDB.fallback_font,
		Vector2(vsize.x * 0.5 - 48, vsize.y * 0.5 - 120),
		"撤离成功" if ok else "任务失败",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 36, title_col)

	if inv == null:
		return

	# Item list
	var start_y : float = vsize.y * 0.5 - 60.0
	var line_h  : float = 24.0
	var list_x  : float = vsize.x * 0.5 - 140.0

	if inv.placed.is_empty():
		draw_string(ThemeDB.fallback_font,
			Vector2(vsize.x * 0.5 - 28, start_y + line_h),
			"背包为空", HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.35, 0.35, 0.35))
	else:
		for i in range(inv.placed.size()):
			var e     : Dictionary = inv.placed[i]
			var col   : Color      = e["type"]["color"]
			var y     : float      = start_y + i * line_h
			# Colour swatch
			draw_rect(Rect2(list_x, y - 7, 12, 12), col)
			# Name
			draw_string(ThemeDB.fallback_font,
				Vector2(list_x + 18, y),
				e["type"]["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 14,
				Color(0.8, 0.8, 0.8))
			# Value (right-aligned via offset)
			draw_string(ThemeDB.fallback_font,
				Vector2(vsize.x * 0.5 + 100, y),
				"¥%d" % e["type"]["value"],
				HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.67, 0.67, 0.67))

	# Total
	var items_count : int = inv.placed.size()
	var total_y     : float = start_y + max(items_count, 1) * line_h + 20.0
	var total_col   := Color.WHITE if ok else Color(0.4, 0.4, 0.4)
	draw_string(ThemeDB.fallback_font,
		Vector2(vsize.x * 0.5 - 50, total_y),
		"总价值  ¥%d" % inv.total_value(),
		HORIZONTAL_ALIGNMENT_LEFT, -1, 18, total_col)

	# Prompt
	draw_string(ThemeDB.fallback_font,
		Vector2(vsize.x * 0.5 - 52, total_y + 44),
		"点击任意处返回大厅",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 13, Color(0.27, 0.27, 0.27))
