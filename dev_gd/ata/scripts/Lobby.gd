extends Node2D

# ─── World constants ──────────────────────────────────────────────────────────
const LOBBY_W   := 1600.0
const LOBBY_H   := 1200.0
const BASE_POS  := Vector2(800.0, 600.0)
const BASE_R    := 220.0
const GRID_STEP := 60.0

# ─── Player ───────────────────────────────────────────────────────────────────
const PLAYER_R     := 18.0
const PLAYER_SPEED := 300.0   # px/s  (JS: 5 px/frame × 60fps)
const SPRINT_MULT  := 2.2

var player_pos := Vector2(800.0, 820.0)   # BASE_Y + BASE_R + 120

# ─── Letter animation ─────────────────────────────────────────────────────────
const A_REST_GAP  := 75.0
const A_MAX_DRIFT := BASE_R - A_REST_GAP - 20.0   # 125
const A_FAR_DIST  := 520.0
const A_NEAR_GAP  := 22.0
const A_LERP      := 0.04

var letter_aL := Vector2(-A_REST_GAP, 0.0)
var letter_aR := Vector2( A_REST_GAP, 0.0)

@onready var _camera    : Camera2D   = $Camera2D
@onready var _entry_btn : Button     = $UI/EntryBtn
@onready var _touch     : TouchInput = $UI/TouchInput

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	_camera.position = player_pos
	_style_button()
	_entry_btn.pressed.connect(_on_entry_pressed)

func _style_button() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color     = Color(1.0, 1.0, 1.0, 0.06)
	normal.border_color = Color(1.0, 1.0, 1.0, 0.55)
	normal.set_border_width_all(1)
	normal.set_corner_radius_all(5)
	var hover := normal.duplicate() as StyleBoxFlat
	hover.bg_color = Color(1.0, 1.0, 1.0, 0.14)
	_entry_btn.add_theme_stylebox_override("normal",  normal)
	_entry_btn.add_theme_stylebox_override("hover",   hover)
	_entry_btn.add_theme_stylebox_override("pressed", hover)
	_entry_btn.add_theme_color_override("font_color", Color.WHITE)

func _on_entry_pressed() -> void:
	get_tree().change_scene_to_file("res://scenes/raid/Raid.tscn")

# ─── Update ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	_update_player(delta)
	_update_letters()
	_camera.position = player_pos
	queue_redraw()

func _update_player(delta: float) -> void:
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1.0
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
	dir += _touch.move_dir
	if dir.length_squared() > 1.0: dir = dir.normalized()
	var spd := PLAYER_SPEED * (SPRINT_MULT if (Input.is_key_pressed(KEY_SHIFT) or _touch.is_sprinting) else 1.0)
	player_pos += dir * spd * delta
	player_pos.x = clampf(player_pos.x, PLAYER_R, LOBBY_W - PLAYER_R)
	player_pos.y = clampf(player_pos.y, PLAYER_R, LOBBY_H - PLAYER_R)

func _update_letters() -> void:
	var d    := player_pos - BASE_POS
	var dist := d.length()
	if dist < 0.001: dist = 0.001
	var n := d / dist

	var ratio     := minf(dist / A_FAR_DIST, 1.0)
	var drift_amt := ratio * A_MAX_DRIFT

	var far_L  := Vector2(-A_REST_GAP + n.x * drift_amt, n.y * drift_amt)
	var far_R  := Vector2( A_REST_GAP + n.x * drift_amt, n.y * drift_amt)
	var near_L := Vector2(d.x - A_NEAR_GAP, d.y)
	var near_R := Vector2(d.x + A_NEAR_GAP, d.y)

	var ib := maxf(0.0, 1.0 - dist / BASE_R)
	var b  := ib * ib

	letter_aL += (far_L.lerp(near_L, b) - letter_aL) * A_LERP
	letter_aR += (far_R.lerp(near_R, b) - letter_aR) * A_LERP

# ─── Draw ─────────────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_grid()
	_draw_base()
	_draw_player()

func _draw_grid() -> void:
	var col := Color(0.067, 0.067, 0.133, 1.0)   # #111122
	var x := 0.0
	while x <= LOBBY_W:
		draw_line(Vector2(x, 0.0), Vector2(x, LOBBY_H), col, 1.0)
		x += GRID_STEP
	var y := 0.0
	while y <= LOBBY_H:
		draw_line(Vector2(0.0, y), Vector2(LOBBY_W, y), col, 1.0)
		y += GRID_STEP

func _draw_base() -> void:
	# Outer soft glow
	for i in range(10, 0, -1):
		var t := float(i) / 10.0
		draw_arc(BASE_POS, BASE_R + 5.0 + t * 25.0, 0.0, TAU, 64,
				Color(1.0, 1.0, 1.0, 0.02 * (1.0 - t * 0.5)), 5.0)
	# Radial gradient: 32 concentric filled circles outer→inner
	# Colors match JS: edge #060d18 → center #0d1b2a
	var c_edge   := Color(0.024, 0.047, 0.094)
	var c_center := Color(0.051, 0.106, 0.165)
	for i in range(32):
		var t   := float(i) / 31.0              # 0 = outer edge, 1 = center
		var r   := BASE_R * (1.0 - t) + 0.5    # radius shrinks each step
		draw_circle(BASE_POS, r, c_edge.lerp(c_center, t * t))
	# Border ring
	draw_arc(BASE_POS, BASE_R, 0.0, TAU, 128, Color(0.667, 0.667, 0.667), 2.5)
	# ATA logo
	_draw_ata(BASE_POS, 100.0)

func _draw_ata(center: Vector2, size: float) -> void:
	var h    := size
	var w    := size * 0.62
	var ac_L := center + letter_aL
	var ac_R := center + letter_aR
	var tc   := Vector2(
		(ac_L.x + ac_R.x) * 0.5,
		(ac_L.y + ac_R.y) * 0.5 - h * 0.35
	)
	_draw_letter_a(ac_L, w, h)
	_draw_letter_t(tc,   w, h)
	_draw_letter_a(ac_R, w, h)

func _layer_seg(from: Vector2, to: Vector2) -> void:
	draw_line(from, to, Color(1.0, 1.0, 1.0, 0.08), 18.0, true)
	draw_line(from, to, Color(1.0, 1.0, 1.0, 0.25), 10.0, true)
	draw_line(from, to, Color(2.5, 2.5, 2.5, 0.85),  4.0, true)  # HDR → bloom
	draw_line(from, to, Color(5.0, 5.0, 5.0, 1.00),  2.0, true)  # HDR → strong bloom

func _draw_letter_a(ac: Vector2, w: float, h: float) -> void:
	var dd   := player_pos - ac
	var dlen := dd.length()
	if dlen < 0.001: dlen = 0.001
	var n   := dd / dlen
	var pup := Vector2(n.x * w * 0.10, n.y * h * 0.14)

	# 横线当前 y 位置
	var bar_y := h * 0.06 + pup.y

	# A 三角形在该 y 处的笔画半宽（线性插值：顶点 y=-h/2 宽=0，底边 y=h/2 宽=w/2）
	var bar_t         := clampf((bar_y - h * 0.5) / (-h), 0.0, 1.0)
	var stroke_half   := w * 0.5 * (1.0 - bar_t)

	# 玩家靠下程度 [0,1]，平方缓入
	var below_factor  := clampf(pup.y / (h * 0.14), 0.0, 1.0)
	var detach        := below_factor * below_factor

	# 相接时端点略伸出笔画（+0.04w）；靠下时缩进笔画（-0.12w）→ 清晰浮离
	var bar_half      := lerpf(stroke_half + w * 0.04, stroke_half - w * 0.12, detach)

	_layer_seg(ac + Vector2(-w * 0.5,  h * 0.5), ac + Vector2(0.0,       -h * 0.5))
	_layer_seg(ac + Vector2( 0.0,     -h * 0.5), ac + Vector2(w * 0.5,    h * 0.5))
	_layer_seg(
		ac + Vector2(-bar_half + pup.x, bar_y),
		ac + Vector2( bar_half + pup.x, bar_y)
	)

func _draw_letter_t(tc: Vector2, w: float, h: float) -> void:
	_layer_seg(tc + Vector2(-w * 0.9, -h * 0.5), tc + Vector2(w * 0.9, -h * 0.5))
	_layer_seg(tc + Vector2(0.0,      -h * 0.5), tc + Vector2(0.0,       h * 1.0))

func _draw_player() -> void:
	var p := player_pos
	var r := PLAYER_R
	# Glow rings
	for i in range(6, 0, -1):
		var t := float(i) / 6.0
		draw_circle(p, r * 2.5 * t, Color(1.0, 1.0, 1.0, 0.05 * (1.0 - t + 0.1)))
	# Body
	draw_circle(p, r, Color(0.102, 0.102, 0.102))
	draw_arc(p, r, 0.0, TAU, 64, Color(3.0, 3.0, 3.0), 2.5)    # HDR → bloom
	# Center dot
	draw_circle(p, 4.0, Color(5.0, 5.0, 5.0))                  # HDR → strong bloom
