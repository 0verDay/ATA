extends Node2D

var raid : Node = null

@onready var _touch : TouchInput = get_parent().get_node("TouchInput")

const INV_COLS := 4
const INV_ROWS := 5
const INV_CELL := 44
const INV_PAD  := 10

# ─── Action bar ───────────────────────────────────────────────────────────────
const AB_W          := 520.0
const AB_H          := 110.0
const AB_BAR_H      := 8.0
const AB_BTN_R      := 36.0   # circle button radius
const AB_BTN_GAP    := 10.0   # circle button distance from panel edge
const AB_SQ         := 40.0   # square button size
const AB_SQ_COUNT   := 6

# ─── Action bar button center helpers ────────────────────────────────────────
func _ab_repair_center(vsize: Vector2) -> Vector2:
	var ox    := vsize.x * 0.5 - AB_W * 0.5
	var oy    := vsize.y - AB_H
	var btn_cy := oy + AB_BAR_H + (AB_H - AB_BAR_H * 2.0) * 0.5
	return Vector2(ox + AB_BTN_GAP + AB_BTN_R, btn_cy)

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

	# ── Repair button (left circle) ───────────────────────────────────────────
	var repair_c := _ab_repair_center(vsize)
	if pos.distance_to(repair_c) <= AB_BTN_R:
		raid.shield = raid.MAX_SHIELD
		get_viewport().set_input_as_handled()
		return

	# ── Inventory drop ────────────────────────────────────────────────────────
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
	_draw_action_bar(vsize)
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

# ─── Action bar (bottom-centre) ──────────────────────────────────────────────
func _draw_action_bar(vsize: Vector2) -> void:
	var ox := vsize.x * 0.5 - AB_W * 0.5
	var oy := vsize.y - AB_H

	# Background
	draw_rect(Rect2(ox, oy, AB_W, AB_H), Color(0.0, 0.0, 0.0, 0.72))
	# Border
	draw_rect(Rect2(ox, oy, AB_W, AB_H), Color(1.0, 1.0, 1.0, 0.18), false, 1.0)

	# ── Top progress bar (shield, white) ─────────────────────────────────────
	var shield_ratio := float(raid.shield) / float(raid.MAX_SHIELD)
	draw_rect(Rect2(ox, oy, AB_W, AB_BAR_H), Color(1.0, 1.0, 1.0, 0.10))
	draw_rect(Rect2(ox, oy, AB_W * shield_ratio, AB_BAR_H), Color(1.0, 1.0, 1.0, 0.70))
	draw_rect(Rect2(ox, oy, AB_W, AB_BAR_H), Color(1.0, 1.0, 1.0, 0.25), false, 1.0)

	# ── Bottom progress bar (hp, red) ─────────────────────────────────────────
	var hp_ratio := float(raid.hp) / float(raid.MAX_HP)
	var bot_bar_y := oy + AB_H - AB_BAR_H
	draw_rect(Rect2(ox, bot_bar_y, AB_W, AB_BAR_H), Color(1.0, 1.0, 1.0, 0.10))
	draw_rect(Rect2(ox, bot_bar_y, AB_W * hp_ratio, AB_BAR_H), Color(0.85, 0.18, 0.18, 0.90))
	draw_rect(Rect2(ox, bot_bar_y, AB_W, AB_BAR_H), Color(1.0, 1.0, 1.0, 0.25), false, 1.0)

	# Vertical centre of button row (between the two bars)
	var btn_cy := oy + AB_BAR_H + (AB_H - AB_BAR_H * 2.0) * 0.5

	# ── Left circle button (repair) ────────────────────────────────────────────
	var lc := Vector2(ox + AB_BTN_GAP + AB_BTN_R, btn_cy)
	draw_circle(lc, AB_BTN_R, Color(1.0, 1.0, 1.0, 0.08))
	draw_arc(lc, AB_BTN_R, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.45), 1.5)
	_draw_icon_wrench(lc, AB_BTN_R * 0.52, Color(1.0, 1.0, 1.0, 0.80))

	# ── Right circle button (backpack) ─────────────────────────────────────────
	var rc := Vector2(ox + AB_W - AB_BTN_GAP - AB_BTN_R, btn_cy)
	draw_circle(rc, AB_BTN_R, Color(1.0, 1.0, 1.0, 0.08))
	draw_arc(rc, AB_BTN_R, 0.0, TAU, 48, Color(1.0, 1.0, 1.0, 0.45), 1.5)
	_draw_icon_backpack(rc, AB_BTN_R * 0.52, Color(1.0, 1.0, 1.0, 0.80))

	# ── 6 square buttons (evenly spaced between circle buttons) ───────────────
	var sq_area_start := lc.x + AB_BTN_R
	var sq_area_end   := rc.x - AB_BTN_R
	var sq_area_w     := sq_area_end - sq_area_start
	var sq_spacing    := sq_area_w / float(AB_SQ_COUNT)
	for i in range(AB_SQ_COUNT):
		var cx := sq_area_start + sq_spacing * (float(i) + 0.5)
		var sx := cx - AB_SQ * 0.5
		var sy := btn_cy - AB_SQ * 0.5
		draw_rect(Rect2(sx, sy, AB_SQ, AB_SQ), Color(1.0, 1.0, 1.0, 0.08))
		draw_rect(Rect2(sx, sy, AB_SQ, AB_SQ), Color(1.0, 1.0, 1.0, 0.35), false, 1.0)

# ─── Minimalist icons ────────────────────────────────────────────────────────
# Backpack: rect body + top strap arc + pocket divider line
func _draw_icon_backpack(c: Vector2, s: float, col: Color) -> void:
	var lw := 1.5
	# Body outline
	draw_rect(Rect2(c.x - s * 0.44, c.y - s * 0.44, s * 0.88, s * 0.90), col, false, lw)
	# Top strap arc (handle bump)
	draw_arc(c + Vector2(0.0, -s * 0.44), s * 0.20, PI, TAU, 14, col, lw)
	# Pocket divider line
	draw_line(
		c + Vector2(-s * 0.44, s * 0.12),
		c + Vector2( s * 0.44, s * 0.12),
		col, lw)

# Wrench: diagonal handle line + open C-head arc at top-right end
func _draw_icon_wrench(c: Vector2, s: float, col: Color) -> void:
	var lw := 2.0
	var angle := -PI * 0.25   # 45° NE direction
	var dir   := Vector2(cos(angle), sin(angle))
	var perp  := Vector2(-dir.y, dir.x)
	# Handle
	var tip  := c + dir * s * 0.55
	var tail := c - dir * s * 0.55
	draw_line(tail, tip - dir * s * 0.22, col, lw)
	# Wrench head: open arc (C-shape) centred at tip
	var head_r := s * 0.30
	# Opening gap aligned along handle direction → arc spans ~270°
	var gap_start := angle - PI * 0.35
	var gap_end   := angle + PI * 0.35
	draw_arc(tip, head_r, gap_end, gap_start + TAU, 24, col, lw)
	# Tiny jaw lines to complete the wrench jaw look
	draw_line(tip + Vector2(cos(gap_start), sin(gap_start)) * head_r,
			  tip + Vector2(cos(gap_start), sin(gap_start)) * (head_r + s * 0.12), col, lw)
	draw_line(tip + Vector2(cos(gap_end),   sin(gap_end))   * head_r,
			  tip + Vector2(cos(gap_end),   sin(gap_end))   * (head_r + s * 0.12), col, lw)

# ─── Joystick visuals ─────────────────────────────────────────────────────────
func _draw_joysticks(vsize: Vector2) -> void:
	if not _touch: return
	_touch.set_centers(vsize)

	# ── Left joystick ──────────────────────────────────────────────────────────
	var lc := _touch.left_center
	# Sprint glow
	if _touch.is_sprinting:
		for i in range(20, 0, -1):
			var t := float(i) / 20.0
			draw_arc(lc, TouchInput.LEFT_R + t * 20.0, 0.0, TAU, 64,
				Color(1.0, 1.0, 1.0, 0.06 * (1.0 - t)), 3.0)
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
