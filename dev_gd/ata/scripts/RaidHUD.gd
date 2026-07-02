extends Node2D

var raid : Node = null

@onready var _touch : TouchInput = get_parent().get_node("TouchInput")

const INV_COLS := 5
const INV_ROWS := 5
const INV_CELL := 64
const INV_PAD  := 30

const INV_SMALL_COLS := 4
const INV_SMALL_ROWS := 1

# ─── Inventory overlay toggle ─────────────────────────────────────────────────
var _inv_open  : bool      = false
var _blur_rect : ColorRect = null

# ─── Drag state ───────────────────────────────────────────────────────────────
var _drag_active : bool       = false
var _drag_entry  : Dictionary = {}
var _drag_source : String     = ""   # "inv" | "safe"
var _drag_pos    : Vector2    = Vector2.ZERO
var _drag_cell_w : float      = 60.0
var _drag_cell_h : float      = 60.0

func _ready() -> void:
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/screen_blur.gdshader")
	_blur_rect = ColorRect.new()
	_blur_rect.set_anchors_preset(Control.PRESET_FULL_RECT)
	_blur_rect.material = mat
	_blur_rect.visible  = false
	get_parent().add_child.call_deferred(_blur_rect)
	_reorder_blur.call_deferred()

func _reorder_blur() -> void:
	get_parent().move_child(_blur_rect, get_index())

func _set_inv_open(value: bool) -> void:
	_inv_open = value
	if _blur_rect:
		_blur_rect.visible = value
	queue_redraw()

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

func _ab_backpack_center(vsize: Vector2) -> Vector2:
	var ox    := vsize.x * 0.5 - AB_W * 0.5
	var oy    := vsize.y - AB_H
	var btn_cy := oy + AB_BAR_H + (AB_H - AB_BAR_H * 2.0) * 0.5
	return Vector2(ox + AB_W - AB_BTN_GAP - AB_BTN_R, btn_cy)

# ─── Layout helpers ───────────────────────────────────────────────────────────
const PAD := INV_PAD   # unified gap = 30

# Vertical available zone: [PAD, vsize.y - AB_H - PAD]
func _avail_top(vsize: Vector2) -> float:
	return PAD

func _avail_bottom(vsize: Vector2) -> float:
	return vsize.y - AB_H - PAD

func _avail_h(vsize: Vector2) -> float:
	return _avail_bottom(vsize) - _avail_top(vsize)

# Horizontal thirds
func _col_x(vsize: Vector2, col: int) -> float:   # left edge of column 0/1/2
	return vsize.x * float(col) / 3.0

# ─── Panel rect helpers ────────────────────────────────────────────────────────
# Left-side small panel (bottom-left corner beside action bar)
func _rect_left_small(vsize: Vector2) -> Rect2:
	var x0 := PAD
	var x1 := (vsize.x - AB_W) * 0.5 - PAD
	var y0 := vsize.y - AB_H
	var y1 := vsize.y - PAD
	return Rect2(x0, y0, x1 - x0, y1 - y0)

# Right-side small panel (bottom-right corner beside action bar)
func _rect_right_small(vsize: Vector2) -> Rect2:
	var x0 := (vsize.x + AB_W) * 0.5 + PAD
	var x1 := vsize.x - PAD
	var y0 := vsize.y - AB_H
	var y1 := vsize.y - PAD
	return Rect2(x0, y0, x1 - x0, y1 - y0)

# Left column upper panel
func _rect_left_top(vsize: Vector2) -> Rect2:
	const INV_H := INV_ROWS * INV_CELL
	var x0 := PAD
	var x1 := _col_x(vsize, 1) - PAD
	var y0 := _avail_top(vsize)
	var y1 := _avail_bottom(vsize) - INV_H - PAD
	return Rect2(x0, y0, x1 - x0, y1 - y0)

# Left column lower panel (inventory grid container)
func _rect_left_bottom(vsize: Vector2) -> Rect2:
	const INV_H := INV_ROWS * INV_CELL
	var x0 := PAD
	var x1 := _col_x(vsize, 1) - PAD
	var y1 := _avail_bottom(vsize)
	var y0 := y1 - INV_H
	return Rect2(x0, y0, x1 - x0, INV_H)

# Middle column panel
func _rect_middle(vsize: Vector2) -> Rect2:
	var x0 := _col_x(vsize, 1) + PAD
	var x1 := _col_x(vsize, 2) - PAD
	var y0 := _avail_top(vsize)
	var y1 := _avail_bottom(vsize)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

# Right column panel
func _rect_right(vsize: Vector2) -> Rect2:
	var x0 := _col_x(vsize, 2) + PAD
	var x1 := vsize.x - PAD
	var y0 := _avail_top(vsize)
	var y1 := _avail_bottom(vsize)
	return Rect2(x0, y0, x1 - x0, y1 - y0)

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if not raid: return
	var vsize    := get_viewport_rect().size
	var pos      := Vector2.ZERO
	var pressed  := false
	var released := false
	var moved    := false

	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		pos = e.position; pressed = e.pressed; released = not e.pressed
	elif event is InputEventScreenDrag:
		pos = (event as InputEventScreenDrag).position; moved = true
	elif not DisplayServer.is_touchscreen_available():
		if event is InputEventMouseButton:
			var e := event as InputEventMouseButton
			if e.button_index != MOUSE_BUTTON_LEFT: return
			pos = e.position; pressed = e.pressed; released = not e.pressed
		elif event is InputEventMouseMotion:
			pos = (event as InputEventMouseMotion).position; moved = true
		else:
			return
	else:
		return

	# ── Drag move ─────────────────────────────────────────────────────────────
	if moved:
		if _drag_active:
			_drag_pos = pos
			queue_redraw()
			get_viewport().set_input_as_handled()
		return

	# ── Drag release ──────────────────────────────────────────────────────────
	if released and _drag_active:
		_handle_drag_drop(pos, vsize)
		get_viewport().set_input_as_handled()
		return

	if not pressed: return

	# ── Repair button ─────────────────────────────────────────────────────────
	var repair_c := _ab_repair_center(vsize)
	if pos.distance_to(repair_c) <= AB_BTN_R:
		raid.shield = raid.MAX_SHIELD
		get_viewport().set_input_as_handled()
		return

	# ── Backpack button ───────────────────────────────────────────────────────
	var bp_c := _ab_backpack_center(vsize)
	if pos.distance_to(bp_c) <= AB_BTN_R:
		_set_inv_open(not _inv_open)
		get_viewport().set_input_as_handled()
		return

	# ── Inventory interactions ────────────────────────────────────────────────
	if not _inv_open: return

	# Drag start from main inventory
	var inv_panel := _rect_left_bottom(vsize)
	if inv_panel.has_point(pos):
		var cw := inv_panel.size.x / INV_COLS
		var ch := inv_panel.size.y / INV_ROWS
		var col := clampi(int((pos.x - inv_panel.position.x) / cw), 0, INV_COLS - 1)
		var row := clampi(int((pos.y - inv_panel.position.y) / ch), 0, INV_ROWS - 1)
		if raid.inventory.grid[row][col] != null:
			_drag_entry  = raid.inventory.drop_at(row, col)
			_drag_source = "inv"
			_drag_active = true
			_drag_pos    = pos
			_drag_cell_w = cw
			_drag_cell_h = ch
			queue_redraw()
		get_viewport().set_input_as_handled()
		return

	# Drag start from safe inventory
	var safe_panel := _rect_left_small(vsize)
	if safe_panel.has_point(pos):
		var cw := safe_panel.size.x / INV_SMALL_COLS
		var ch := safe_panel.size.y / INV_SMALL_ROWS
		var col := clampi(int((pos.x - safe_panel.position.x) / cw), 0, INV_SMALL_COLS - 1)
		var row := clampi(int((pos.y - safe_panel.position.y) / ch), 0, INV_SMALL_ROWS - 1)
		if raid.safe_inventory.grid[row][col] != null:
			_drag_entry  = raid.safe_inventory.drop_at(row, col)
			_drag_source = "safe"
			_drag_active = true
			_drag_pos    = pos
			_drag_cell_w = cw
			_drag_cell_h = ch
			queue_redraw()
		get_viewport().set_input_as_handled()
		return

	# Tap elsewhere → close
	if pos.y < vsize.y - AB_H:
		_set_inv_open(false)
		get_viewport().set_input_as_handled()

# ─── Drag drop handler ────────────────────────────────────────────────────────
func _handle_drag_drop(pos: Vector2, vsize: Vector2) -> void:
	var itype  : Dictionary = _drag_entry["type"]
	var iw : int = int(itype["w"])
	var ih : int = int(itype["h"])
	var placed := false

	# Helper: compute base top-left cell from pointer + cell metrics
	# base = round(pointer_offset / cell_size - item_cells / 2)
	var inv_panel := _rect_left_bottom(vsize)
	if inv_panel.has_point(pos):
		var cw  := inv_panel.size.x / INV_COLS
		var ch  := inv_panel.size.y / INV_ROWS
		var base_c := roundi((pos.x - inv_panel.position.x) / cw - iw * 0.5)
		var base_r := roundi((pos.y - inv_panel.position.y) / ch - ih * 0.5)
		placed = raid.inventory.try_place_at(itype, base_r, base_c)

	if not placed:
		var safe_panel := _rect_left_small(vsize)
		if safe_panel.has_point(pos):
			var cw  := safe_panel.size.x / INV_SMALL_COLS
			var ch  := safe_panel.size.y / INV_SMALL_ROWS
			var base_c := roundi((pos.x - safe_panel.position.x) / cw - iw * 0.5)
			var base_r := roundi((pos.y - safe_panel.position.y) / ch - ih * 0.5)
			placed = raid.safe_inventory.try_place_at(itype, base_r, base_c)

	if not placed:
		if _drag_source == "inv":
			raid.inventory.try_add(itype)
		else:
			raid.safe_inventory.try_add(itype)

	_drag_active = false
	_drag_entry  = {}
	_drag_source = ""
	queue_redraw()

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _draw() -> void:
	if not raid: return
	var vsize := get_viewport_rect().size
	if _inv_open:
		_draw_overlay(vsize)
	else:
		_draw_arrow(vsize)
		_draw_extract_bar(vsize)
		_draw_joysticks(vsize)
	# Action bar always on top
	_draw_action_bar(vsize)

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
	draw_colored_polygon(pts, UITheme.C_TEXT * Color(1,1,1,0.55))

# ─── Extraction progress bar ─────────────────────────────────────────────────
func _draw_extract_bar(vsize: Vector2) -> void:
	if raid.extract_progress <= 0.0: return
	var prog : float = raid.extract_progress / raid.EXTRACT_TIME
	var bw := 200.0; var bh := 10.0
	var bx := vsize.x * 0.5 - bw * 0.5
	var by := vsize.y - 58.0
	UITheme.draw_bar(self, Rect2(bx, by, bw, bh), prog, UITheme.C_BAR_FILL)
	UITheme.draw_label(self, Vector2(vsize.x * 0.5 - 22.0, by - 6.0),
		"撤离中…", UITheme.FONT_SIZE_S, UITheme.C_TEXT)

# ─── Shared panel draw helper ─────────────────────────────────────────────────
func _draw_panel(r: Rect2) -> void:
	UITheme.draw_panel(self, r)

# ─── Draw inventory grid + items inside a panel ───────────────────────────────
func _draw_inv_grid(panel: Rect2, inv: Inventory, cols: int, rows: int) -> void:
	_draw_panel(panel)
	var cw := panel.size.x / cols
	var ch := panel.size.y / rows
	var ox := panel.position.x
	var oy := panel.position.y
	for r in range(rows):
		for c in range(cols):
			UITheme.draw_cell(self, Rect2(ox + c * cw, oy + r * ch, cw, ch))
	var drawn := {}
	for r in range(rows):
		for c in range(cols):
			var entry = inv.grid[r][c]
			if entry == null: continue
			var eid : int = entry["_id"]
			if drawn.has(eid): continue
			drawn[eid] = true
			_draw_item_block(entry, ox, oy, cw, ch)

func _draw_item_block(entry: Dictionary, ox: float, oy: float,
		cw: float, ch: float, alpha: float = 1.0) -> void:
	var itype : Dictionary = entry["type"]
	var ix := ox + int(entry["col"]) * cw + 3
	var iy := oy + int(entry["row"]) * ch + 3
	var iw : float = int(itype["w"]) * cw - 6
	var ih : float = int(itype["h"]) * ch - 6
	var col : Color = itype["color"]
	col.a *= alpha
	draw_rect(Rect2(ix, iy, iw, ih), col)
	UITheme.draw_label(self,
		Vector2(ix + iw * 0.5 - 16, iy + ih * 0.5 - 8),
		itype["name"], UITheme.FONT_SIZE_M, Color(0, 0, 0, 0.90 * alpha))
	UITheme.draw_label(self,
		Vector2(ix + iw * 0.5 - 18, iy + ih * 0.5 + 6),
		"¥%d" % itype["value"], UITheme.FONT_SIZE_S, Color(0, 0, 0, 0.85 * alpha))

# ─── Inventory overlay (dim + all UI panels + inventory grid) ─────────────────
func _draw_overlay(vsize: Vector2) -> void:
	draw_rect(Rect2(0.0, 0.0, vsize.x, vsize.y), UITheme.C_OVERLAY)

	# ── Left small panel (safe inventory) ─────────────────────────────────────
	_draw_inv_grid(_rect_left_small(vsize), raid.safe_inventory,
		INV_SMALL_COLS, INV_SMALL_ROWS)

	# ── Right small panel ─────────────────────────────────────────────────────
	_draw_panel(_rect_right_small(vsize))

	# ── Left column upper panel ────────────────────────────────────────────────
	_draw_left_top_panel(vsize)

	# ── Middle and right column panels ────────────────────────────────────────
	_draw_panel(_rect_middle(vsize))
	_draw_panel(_rect_right(vsize))

	# ── Main inventory (left column lower panel) ───────────────────────────────
	UITheme.draw_label(self,
		Vector2(_rect_left_bottom(vsize).position.x, _rect_left_bottom(vsize).position.y - 14),
		"背包  (拖拽移动)", UITheme.FONT_SIZE_M, UITheme.C_TEXT_DIM)
	_draw_inv_grid(_rect_left_bottom(vsize), raid.inventory, INV_COLS, INV_ROWS)

	# ── Drag ghost ────────────────────────────────────────────────────────────
	if _drag_active and not _drag_entry.is_empty():
		const GHOST_SCALE := 0.70
		var itype  : Dictionary = _drag_entry["type"]
		var gcw    := _drag_cell_w * GHOST_SCALE
		var gch    := _drag_cell_h * GHOST_SCALE
		var ghost_w := float(int(itype["w"])) * gcw
		var ghost_h := float(int(itype["h"])) * gch
		var ghost_entry := { "type": itype, "row": 0, "col": 0 }
		_draw_item_block(ghost_entry,
			_drag_pos.x - ghost_w * 0.5, _drag_pos.y - ghost_h * 0.5,
			gcw, gch, 0.65)

# ─── Action bar (bottom-centre) ──────────────────────────────────────────────
func _draw_action_bar(vsize: Vector2) -> void:
	var ox := vsize.x * 0.5 - AB_W * 0.5
	var oy := vsize.y - AB_H

	UITheme.draw_panel(self, Rect2(ox, oy, AB_W, AB_H))

	# ── Top progress bar (shield) ─────────────────────────────────────────────
	var shield_ratio := float(raid.shield) / float(raid.MAX_SHIELD)
	UITheme.draw_bar(self, Rect2(ox, oy, AB_W, AB_BAR_H),
		shield_ratio, UITheme.C_BAR_FILL)

	# ── Bottom progress bar (hp) ──────────────────────────────────────────────
	var hp_ratio := float(raid.hp) / float(raid.MAX_HP)
	UITheme.draw_bar(self, Rect2(ox, oy + AB_H - AB_BAR_H, AB_W, AB_BAR_H),
		hp_ratio, UITheme.C_BAR_HP)

	# Vertical centre of button row
	var btn_cy := oy + AB_BAR_H + (AB_H - AB_BAR_H * 2.0) * 0.5

	# ── Left circle button (repair) ────────────────────────────────────────────
	var lc := Vector2(ox + AB_BTN_GAP + AB_BTN_R, btn_cy)
	UITheme.draw_circle_btn(self, lc, AB_BTN_R, false)
	_draw_icon_wrench(lc, AB_BTN_R * 0.52, UITheme.C_TEXT)

	# ── Right circle button (backpack) ────────────────────────────────────────
	var rc := Vector2(ox + AB_W - AB_BTN_GAP - AB_BTN_R, btn_cy)
	UITheme.draw_circle_btn(self, rc, AB_BTN_R, _inv_open)
	_draw_icon_backpack(rc, AB_BTN_R * 0.52, UITheme.C_TEXT)

	# ── 6 square buttons ──────────────────────────────────────────────────────
	var sq_area_start := lc.x + AB_BTN_R
	var sq_area_end   := rc.x - AB_BTN_R
	var sq_spacing    := (sq_area_end - sq_area_start) / float(AB_SQ_COUNT)
	for i in range(AB_SQ_COUNT):
		var cx := sq_area_start + sq_spacing * (float(i) + 0.5)
		UITheme.draw_square_btn(self,
			Rect2(cx - AB_SQ * 0.5, btn_cy - AB_SQ * 0.5, AB_SQ, AB_SQ))

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
	var ring_col := UITheme.C_BORDER if _touch.is_sprinting else UITheme.C_BORDER_DIM
	draw_arc(lc, TouchInput.LEFT_R, 0.0, TAU, 64, ring_col, 2.0)
	var lk := _touch.get_left_knob()
	draw_circle(lk, 22.0, UITheme.C_FILL_HI)
	draw_arc(lk, 22.0, 0.0, TAU, 40, UITheme.C_BORDER, 2.0)

	# ── Right joystick ─────────────────────────────────────────────────────────
	var rc := _touch.right_center
	draw_arc(rc, TouchInput.RIGHT_OUTER_R, 0.0, TAU, 80, UITheme.C_BORDER_DIM, 1.5)
	draw_arc(rc, TouchInput.RIGHT_INNER_R, 0.0, TAU, 48, UITheme.C_BORDER_DIM, 1.5)
	draw_circle(rc, TouchInput.RIGHT_INNER_R, UITheme.C_FILL_LO)
	var rk    := _touch.get_right_knob()
	var active_shoot := _touch.is_shooting or (_touch._right_in_outer and _touch._right_started_outer)
	var r_col := UITheme.C_BAR_HP if active_shoot else UITheme.C_BORDER
	draw_circle(rk, 18.0, r_col * Color(1, 1, 1, 0.3))
	draw_arc(rk, 18.0, 0.0, TAU, 40, r_col, 2.0)
	if _touch.right_active():
		var dir := Vector2(cos(_touch.facing), sin(_touch.facing))
		draw_line(rc, rc + dir * TouchInput.RIGHT_OUTER_R, UITheme.C_BORDER_DIM, 1.5)

# ─── Left-top panel: equipment slots + stick figure ──────────────────────────
const EQ_COLS    := 2   # slots per column (left / right)
const EQ_PADDING := 8.0 # inner padding inside panel

func _draw_left_top_panel(vsize: Vector2) -> void:
	var p    := _rect_left_top(vsize)
	_draw_panel(p)

	# Slot cell: square, height = (panel.h - 2*pad) / EQ_COLS
	var inner_h   := p.size.y - EQ_PADDING * 2.0
	var cell_size := inner_h / float(EQ_COLS)
	var col_w     := cell_size   # columns are square cells wide

	# Left column origin (inside panel, padded)
	var lx := p.position.x + EQ_PADDING
	var ly := p.position.y + EQ_PADDING

	# Right column origin
	var rx := p.position.x + p.size.x - EQ_PADDING - col_w
	var ry := ly

	# Draw left and right equipment slot columns
	for i in range(EQ_COLS):
		var cy := ly + i * cell_size
		UITheme.draw_cell(self, Rect2(lx, cy, cell_size, cell_size))
		UITheme.draw_cell(self, Rect2(rx, cy, cell_size, cell_size))

	# Center area for stick figure
	var cx := (lx + col_w + rx) * 0.5
	var cy_mid := p.position.y + p.size.y * 0.5
	var fig_h  := inner_h * 0.72
	_draw_stick_figure(Vector2(cx, cy_mid), fig_h, UITheme.C_TEXT)

func _draw_stick_figure(center: Vector2, height: float, col: Color) -> void:
	var lw       := UITheme.BORDER_W + 0.5
	var head_r   := height * 0.12
	var body_len := height * 0.32
	var arm_w    := height * 0.22
	var leg_len  := height * 0.28
	var leg_spr  := height * 0.14

	# Layout reference points
	var head_c  := center + Vector2(0.0, -height * 0.5 + head_r)
	var neck    := head_c + Vector2(0.0,  head_r)
	var hip     := neck   + Vector2(0.0,  body_len)
	var arm_mid := neck   + Vector2(0.0,  body_len * 0.35)

	# Head
	draw_arc(head_c, head_r, 0.0, TAU, 32, col, lw)
	# Body
	draw_line(neck, hip, col, lw)
	# Arms
	draw_line(arm_mid + Vector2(-arm_w, 0.0), arm_mid + Vector2(arm_w, 0.0), col, lw)
	# Legs
	draw_line(hip, hip + Vector2(-leg_spr,  leg_len), col, lw)
	draw_line(hip, hip + Vector2( leg_spr,  leg_len), col, lw)
