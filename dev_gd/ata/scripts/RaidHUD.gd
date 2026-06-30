extends Node2D

var raid : Node = null

@onready var _touch : TouchInput = get_parent().get_node("TouchInput")

const INV_COLS := 4
const INV_ROWS := 5
const INV_CELL := 44
const INV_PAD  := 10

# ─── Inventory origin: top-right ─────────────────────────────────────────────
func _inv_origin(vsize: Vector2) -> Vector2:
	return Vector2(
		vsize.x - INV_COLS * INV_CELL - INV_PAD,
		INV_PAD + 20.0
	)

# ─── Input: inventory drop ────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not raid: return
	var pressed : bool
	var pos     : Vector2
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		pressed = e.pressed; pos = e.position
	elif event is InputEventMouseButton and not DisplayServer.is_touchscreen_available():
		var e := event as InputEventMouseButton
		if e.button_index != MOUSE_BUTTON_LEFT: return
		pressed = e.pressed; pos = e.position
	else:
		return
	if not pressed: return

	var vsize  := get_viewport_rect().size
	var origin := _inv_origin(vsize)
	if pos.x < origin.x or pos.x > origin.x + INV_COLS * INV_CELL: return
	if pos.y < origin.y or pos.y > origin.y + INV_ROWS * INV_CELL: return
	var col : int = int((pos.x - origin.x) / INV_CELL)
	var row : int = int((pos.y - origin.y) / INV_CELL)
	raid.inventory.drop_at(row, col)
	get_viewport().set_input_as_handled()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not raid: return
	var vsize := get_viewport_rect().size
	_draw_arrow(vsize)
	_draw_extract_bar(vsize)
	_draw_inventory(vsize)
	_draw_joysticks(vsize)

# ─── Direction arrow ─────────────────────────────────────────────────────────
func _draw_arrow(vsize: Vector2) -> void:
	if raid.extraction_visible: return
	var ex_world := Vector2(
		(raid.extraction.x + 0.5) * float(MapGen.TILE),
		(raid.extraction.y + 0.5) * float(MapGen.TILE)
	)
	var angle  : float = (ex_world - (raid.player_pos as Vector2)).angle()
	var center := vsize * 0.5
	var tip    := Vector2(center.x + cos(angle) * 60.0, center.y + sin(angle) * 60.0)
	var pts := PackedVector2Array([
		tip + Vector2( 12.0,  0.0).rotated(angle),
		tip + Vector2( -8.0, -7.0).rotated(angle),
		tip + Vector2( -8.0,  7.0).rotated(angle),
	])
	draw_colored_polygon(pts, Color(1.0, 1.0, 1.0, 0.55))
	draw_string(ThemeDB.fallback_font,
		Vector2(center.x - 84.0, vsize.y - 16.0),
		"探索地图以找到撤离点",
		HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color(1, 1, 1, 0.30))

# ─── Extraction progress bar ─────────────────────────────────────────────────
func _draw_extract_bar(vsize: Vector2) -> void:
	if raid.extract_progress <= 0.0: return
	var prog : float = raid.extract_progress / raid.EXTRACT_TIME
	var bw := 200.0; var bh := 10.0
	var bx := vsize.x * 0.5 - bw * 0.5
	var by := vsize.y - 58.0
	draw_rect(Rect2(bx - 2.0, by - 2.0, bw + 4.0, bh + 4.0), Color(0, 0, 0, 0.55))
	draw_rect(Rect2(bx, by, bw * prog, bh), Color.WHITE)
	draw_rect(Rect2(bx, by, bw, bh), Color(1, 1, 1, 0.40), false)
	draw_string(ThemeDB.fallback_font,
		Vector2(vsize.x * 0.5 - 22.0, by - 6.0),
		"撤离中…", HORIZONTAL_ALIGNMENT_LEFT, -1, 12, Color.WHITE)

# ─── Inventory (top-right) ────────────────────────────────────────────────────
func _draw_inventory(vsize: Vector2) -> void:
	var inv    := raid.inventory as Inventory
	var origin := _inv_origin(vsize)
	var ox     := origin.x
	var oy     := origin.y
	draw_rect(Rect2(ox - 4, oy - 20, INV_COLS * INV_CELL + 8, INV_ROWS * INV_CELL + 24),
		Color(0, 0, 0, 0.72))
	draw_string(ThemeDB.fallback_font, Vector2(ox, oy - 16),
		"背包  (点击丢弃)", HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.53, 0.53, 0.53))
	for r in range(INV_ROWS):
		for c in range(INV_COLS):
			draw_rect(
				Rect2(ox + c * INV_CELL, oy + r * INV_CELL, INV_CELL, INV_CELL),
				Color(1, 1, 1, 0.12), false)
	var drawn := {}
	for r in range(INV_ROWS):
		for c in range(INV_COLS):
			var entry = inv.grid[r][c]
			if entry == null: continue
			var eid : int = entry["_id"]
			if drawn.has(eid): continue
			drawn[eid] = true
			var itype : Dictionary = entry["type"]
			var ir : int = entry["row"]
			var ic : int = entry["col"]
			var ix := ox + ic * INV_CELL + 2
			var iy := oy + ir * INV_CELL + 2
			var iw : float = int(itype["w"]) * INV_CELL - 4
			var ih : float = int(itype["h"]) * INV_CELL - 4
			draw_rect(Rect2(ix, iy, iw, ih), itype["color"])
			draw_string(ThemeDB.fallback_font,
				Vector2(ix + iw * 0.5 - 12, iy + ih * 0.5 - 6),
				itype["name"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0, 0, 0, 0.85))
			draw_string(ThemeDB.fallback_font,
				Vector2(ix + iw * 0.5 - 14, iy + ih * 0.5 + 3),
				"¥%d" % itype["value"], HORIZONTAL_ALIGNMENT_LEFT, -1, 9,
				Color(0, 0, 0, 0.85))

# ─── Joystick visuals ─────────────────────────────────────────────────────────
func _draw_joysticks(vsize: Vector2) -> void:
	if not _touch: return
	_touch.set_centers(vsize)

	# ── Left joystick ──────────────────────────────────────────────────────────
	var lc := _touch.left_center
	# Sprint glow
	if _touch.is_sprinting:
		for i in range(6, 0, -1):
			var t := float(i) / 6.0
			draw_arc(lc, TouchInput.LEFT_R + t * 14.0, 0.0, TAU, 64,
				Color(1.0, 1.0, 1.0, 0.12 * (1.0 - t + 0.1)), 3.0 + t * 2.0)
	# Outer boundary ring
	var ring_col := Color(1.0, 1.0, 1.0, 0.80) if _touch.is_sprinting else Color(1, 1, 1, 0.18)
	draw_arc(lc, TouchInput.LEFT_R, 0.0, TAU, 64, ring_col, 2.0)
	# Knob
	var lk := _touch.get_left_knob()
	draw_circle(lk, 22.0, Color(1, 1, 1, 0.22))
	draw_arc(lk, 22.0, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 2.0)

	# ── Right joystick ─────────────────────────────────────────────────────────
	var rc := _touch.right_center
	# Outer ring (shoot zone) — slightly red tint
	draw_arc(rc, TouchInput.RIGHT_OUTER_R, 0.0, TAU, 80, Color(1.0, 0.5, 0.4, 0.25), 2.5)
	draw_arc(rc, TouchInput.RIGHT_OUTER_R, 0.0, TAU, 80, Color(1.0, 0.5, 0.4, 0.30), 1.0)
	# Inner circle (aim zone) — white
	draw_arc(rc, TouchInput.RIGHT_INNER_R, 0.0, TAU, 48, Color(1, 1, 1, 0.45), 2.0)
	draw_circle(rc, TouchInput.RIGHT_INNER_R, Color(1, 1, 1, 0.06))
	# Knob — red when shooting, orange-ish when tap-pending, white when aim-only
	var rk    := _touch.get_right_knob()
	var active_shoot := _touch.is_shooting or (_touch._right_in_outer and _touch._right_started_outer)
	var r_col := Color(1.0, 0.4, 0.3, 0.85) if active_shoot else Color(1, 1, 1, 0.55)
	draw_circle(rk, 18.0, r_col * Color(1, 1, 1, 0.3))
	draw_arc(rk, 18.0, 0.0, TAU, 40, r_col, 2.0)
	# Facing line when right stick active
	if _touch.right_active():
		var dir := Vector2(cos(_touch.facing), sin(_touch.facing))
		draw_line(rc, rc + dir * TouchInput.RIGHT_OUTER_R, Color(1, 1, 1, 0.20), 1.5)
