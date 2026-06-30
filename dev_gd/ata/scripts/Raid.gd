extends Node2D

const TILE            := MapGen.TILE
const MAP_W           := MapGen.MAP_W
const MAP_H           := MapGen.MAP_H
const PLAYER_R        := 15.0
const PLAYER_SPD      := 120.0
const SPRINT_MULT     := 2.2
const ZOOM            := 1.5
const EXTRACT_REVEAL  := 600.0
const EXTRACT_TIME    := 1.5

# ─── Vision ───────────────────────────────────────────────────────────────────
const CONE_HALF    := 30.0 * PI / 180.0
const PERCEPTION_R  := 90.0
const RAY_STEPS     := 120

# ─── Weapon constants ─────────────────────────────────────────────────────────
const BULLET_SPEED      := 700.0
const BULLET_RANGE      := 950.0
const FIRE_RATE         := 0.22   # seconds between shots
const SPREAD_HALF       := 10.0 * PI / 180.0   # ±10° base spread
const RECOIL_PER_SHOT   := 4.0  * PI / 180.0   # spread added per shot
const RECOIL_MAX        := 30.0 * PI / 180.0   # max spread cap
const RECOIL_RECOVERY   := 25.0 * PI / 180.0   # rad/s recovery when not firing

# ─── Colours ──────────────────────────────────────────────────────────────────
const C_WALL   := Color(0.067, 0.067, 0.067)
const C_FLOOR  := Color(0.500, 0.500, 0.500)
const C_GRID   := Color(0.0,   0.0,   0.0,  0.10)
const C_BULLET := Color(3.0, 2.5, 0.2)   # HDR yellow → bloom
const C_ENEMY_BULLET := Color(3.0, 0.5, 0.3)  # HDR red-orange → bloom

# ─── Enemy constants ──────────────────────────────────────────────────────────
const ENEMY_COUNT_MIN  := 12
const ENEMY_COUNT_MAX  := 18
const ENEMY_R          := 13.0
const ENEMY_SPD        := 65.0
const ENEMY_SPRINT_SPD := 110.0
const ENEMY_SENSE_R    := 200.0   # aggro range
const ENEMY_CHASE_R    := 350.0   # keep chasing up to this distance
const ENEMY_SHOOT_R    := 260.0   # start shooting within this range
const ENEMY_FIRE_RATE  := 0.55
const ENEMY_HP         := 60
const ENEMY_DMG        := 8       # damage per bullet to player

# ─── State ────────────────────────────────────────────────────────────────────
var tiles               : Array              = []
var spawn               : Vector2i           = Vector2i.ZERO
var extraction          : Vector2i           = Vector2i.ZERO
var items               : Array              = []
var inventory           : Inventory          = Inventory.new()
var player_pos          : Vector2            = Vector2.ZERO
var facing              : float              = 0.0
var extraction_revealed : bool               = false
var extraction_in_view  : bool               = false
var extraction_visible  : bool               = false
var extract_progress    : float              = 0.0
var bullets             : Array              = []   # {pos, dir, traveled}
var _fire_cooldown      : float              = 0.0
var _pulse_t            : float              = 0.0
var _fog_polygon        : PackedVector2Array = PackedVector2Array()
var _current_spread     : float              = SPREAD_HALF

# ─── Player stats ─────────────────────────────────────────────────────────────
const MAX_HP     := 100
const MAX_SHIELD := 100
var hp     : int = MAX_HP
var shield : int = MAX_SHIELD

# ─── Enemies ──────────────────────────────────────────────────────────────────
# Each enemy: { pos, hp, state, patrol_target, fire_cd, facing }
# state: 0=PATROL  1=CHASE  2=SHOOT
var enemies        : Array = []
var enemy_bullets  : Array = []   # { pos, dir, traveled }

@onready var _camera      : Camera2D    = $Camera2D
@onready var _hud         : Node2D      = $HUD/HUDDraw
@onready var _touch       : TouchInput  = $HUD/TouchInput
@onready var _fog_vp      : SubViewport = $FogViewport
@onready var _fog_cam     : Camera2D    = $FogViewport/FogCamera
@onready var _fog_mask    : Node2D      = $FogViewport/FogMaskDraw
@onready var _fog_rect    : ColorRect   = $FogLayer/FogRect

# ─── Ready ────────────────────────────────────────────────────────────────────
func _ready() -> void:
	var data         := MapGen.generate()
	tiles            = data["tiles"]
	spawn            = data["spawn"]
	extraction       = data["extraction"]
	items            = data["items"]
	player_pos       = Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
	_camera.zoom     = Vector2(ZOOM, ZOOM)
	_camera.position = player_pos
	_hud.raid        = self
	_spawn_enemies()

	# Size SubViewport to match main viewport
	_resize_fog_viewport()
	get_tree().root.size_changed.connect(_resize_fog_viewport)

	# Wire SubViewport texture → shader uniform on FogRect
	var mat := ShaderMaterial.new()
	mat.shader = preload("res://shaders/fog.gdshader")
	mat.set_shader_parameter("fog_mask", _fog_vp.get_texture())
	_fog_rect.material = mat

func _resize_fog_viewport() -> void:
	_fog_vp.size = Vector2i(get_viewport().get_visible_rect().size)

# ─── Update ───────────────────────────────────────────────────────────────────
func _process(delta: float) -> void:
	var vsize := get_viewport_rect().size
	_touch.set_centers(vsize)
	_update_player(delta)
	_update_facing()
	_update_shoot(delta)
	_update_bullets(delta)
	_update_fog_polygon()
	_update_items()
	_update_extraction(delta)
	_update_enemies(delta)
	_update_enemy_bullets(delta)
	_pulse_t         += delta
	_camera.position  = player_pos
	# Sync fog camera to main camera
	_fog_cam.position = _camera.position
	_fog_cam.zoom     = _camera.zoom
	# Push new polygon to fog mask node
	_fog_mask.fog_polygon = _fog_polygon
	_fog_mask.player_pos  = player_pos
	_fog_mask.queue_redraw()
	queue_redraw()
	_hud.queue_redraw()

func _update_player(delta: float) -> void:
	# WASD / arrow keys
	var dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_UP)    or Input.is_key_pressed(KEY_W): dir.y -= 1.0
	if Input.is_key_pressed(KEY_DOWN)  or Input.is_key_pressed(KEY_S): dir.y += 1.0
	if Input.is_key_pressed(KEY_LEFT)  or Input.is_key_pressed(KEY_A): dir.x -= 1.0
	if Input.is_key_pressed(KEY_RIGHT) or Input.is_key_pressed(KEY_D): dir.x += 1.0
	# Left joystick (additive — both work simultaneously on PC)
	dir += _touch.move_dir
	if dir.length_squared() > 1.0: dir = dir.normalized()
	var spd := PLAYER_SPD * (SPRINT_MULT if (Input.is_key_pressed(KEY_SHIFT) or _touch.is_sprinting) else 1.0)
	player_pos = MapGen.resolve_collision(player_pos + dir * spd * delta, PLAYER_R, tiles)

func _update_facing() -> void:
	if _touch.has_facing:
		facing = _touch.facing
	# Mobile without joystick: keep last facing

func _update_shoot(delta: float) -> void:
	_fire_cooldown = maxf(0.0, _fire_cooldown - delta)

	# Tap shot (outer-start mode, fired on release)
	if _touch.shoot_tap:
		_touch.shoot_tap = false
		if _fire_cooldown <= 0.0:
			var spread := randf_range(-_current_spread, _current_spread)
			var a      := _touch.tap_facing + spread
			var d      := Vector2(cos(a), sin(a))
			bullets.append({ "pos": player_pos, "dir": d, "traveled": 0.0 })
			_current_spread = minf(_current_spread + RECOIL_PER_SHOT, RECOIL_MAX)
			_fire_cooldown  = FIRE_RATE
		return

	# Continuous fire (inner-start mode dragged into outer ring)
	var want_shoot : bool
	if _touch.right_active():
		want_shoot = _touch.is_shooting
	elif not DisplayServer.is_touchscreen_available() \
			and not _touch.left_active() \
			and not _touch.right_active():
		want_shoot = Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)
	else:
		want_shoot = false
	if want_shoot and _fire_cooldown <= 0.0:
		var spread := randf_range(-_current_spread, _current_spread)
		bullets.append({
			"pos":      player_pos,
			"dir":      Vector2(cos(facing + spread), sin(facing + spread)),
			"traveled": 0.0,
		})
		_current_spread = minf(_current_spread + RECOIL_PER_SHOT, RECOIL_MAX)
		_fire_cooldown  = FIRE_RATE

	# Spread recovery when not firing
	if not want_shoot:
		_current_spread = maxf(_current_spread - RECOIL_RECOVERY * delta, SPREAD_HALF)

func _update_bullets(delta: float) -> void:
	var step := BULLET_SPEED * delta
	var alive : Array = []
	for b in bullets:
		b["pos"]      += (b["dir"] as Vector2) * step
		b["traveled"] += step
		if b["traveled"] >= BULLET_RANGE: continue
		var bp : Vector2 = b["pos"]
		var btx := int(bp.x / TILE)
		var bty := int(bp.y / TILE)
		if btx < 0 or btx >= MAP_W or bty < 0 or bty >= MAP_H: continue
		if tiles[bty][btx] == 1: continue
		alive.append(b)
	bullets = alive

func _update_extraction(delta: float) -> void:
	var ex_world := Vector2((extraction.x + 0.5) * TILE, (extraction.y + 0.5) * TILE)
	var dist     := player_pos.distance_to(ex_world)
	if dist < EXTRACT_REVEAL: extraction_revealed = true
	if extraction_revealed:
		var diff : float = fposmod((ex_world - player_pos).angle() - facing + PI, TAU) - PI
		extraction_in_view = dist <= PERCEPTION_R or \
			(dist <= _view_range() and abs(diff) <= CONE_HALF)
	if dist < TILE * 0.75:
		extract_progress += delta
		if extract_progress >= EXTRACT_TIME:
			GameData.result_success   = true
			GameData.result_inventory = inventory
			get_tree().change_scene_to_file("res://scenes/result/Result.tscn")
	else:
		extract_progress = maxf(0.0, extract_progress - delta * 2.0)

func _update_items() -> void:
	for item in items:
		if item["collected"]: continue
		if player_pos.distance_to(item["pos"]) < TILE * 0.75:
			if inventory.try_add(item["type"]):
				item["collected"] = true

# ─── Enemy spawn ──────────────────────────────────────────────────────────────
func _spawn_enemies() -> void:
	var count   := ENEMY_COUNT_MIN + randi() % (ENEMY_COUNT_MAX - ENEMY_COUNT_MIN + 1)
	var spawn_w := Vector2((spawn.x + 0.5) * TILE, (spawn.y + 0.5) * TILE)
	var attempts := 0
	while enemies.size() < count and attempts < 5000:
		attempts += 1
		var tx : int = 2 + randi() % (MAP_W - 4)
		var ty : int = 2 + randi() % (MAP_H - 4)
		if tiles[ty][tx] != 0: continue
		var ep := Vector2((tx + 0.5) * TILE, (ty + 0.5) * TILE)
		if ep.distance_to(spawn_w) < TILE * 8.0: continue
		enemies.append({
			"pos":            ep,
			"hp":             ENEMY_HP,
			"state":          0,          # PATROL
			"patrol_target":  ep,
			"fire_cd":        randf() * ENEMY_FIRE_RATE,
			"facing":         randf() * TAU,
		})

# ─── Enemy AI update ──────────────────────────────────────────────────────────
func _update_enemies(delta: float) -> void:
	var alive : Array = []
	for e in enemies:
		# ── Bullet hit check: player bullets vs this enemy ─────────────────────
		var hit := false
		var surviving_bullets : Array = []
		for b in bullets:
			var bp : Vector2 = b["pos"]
			if bp.distance_to(e["pos"]) < ENEMY_R + 4.0:
				e["hp"] -= 20
				hit = true
			else:
				surviving_bullets.append(b)
		if hit:
			bullets = surviving_bullets
		if e["hp"] <= 0:
			continue   # enemy dead — drop from list

		var ep    : Vector2 = e["pos"]
		var dist  : float   = ep.distance_to(player_pos)

		# ── State transitions ──────────────────────────────────────────────────
		if dist <= ENEMY_SENSE_R:
			e["state"] = 2 if dist <= ENEMY_SHOOT_R else 1
		elif dist > ENEMY_CHASE_R:
			e["state"] = 0

		match int(e["state"]):
			0:   # PATROL
				_enemy_patrol(e, delta)
			1:   # CHASE
				_enemy_move_toward(e, player_pos, ENEMY_SPD, delta)
				e["facing"] = (player_pos - ep).angle()
			2:   # SHOOT
				# Keep a comfortable distance
				if dist < ENEMY_SHOOT_R * 0.5:
					_enemy_move_toward(e, player_pos, -ENEMY_SPD, delta)
				elif dist > ENEMY_SHOOT_R * 0.85:
					_enemy_move_toward(e, player_pos, ENEMY_SPRINT_SPD, delta)
				e["facing"] = (player_pos - ep).angle()
				e["fire_cd"] -= delta
				if e["fire_cd"] <= 0.0:
					e["fire_cd"] = ENEMY_FIRE_RATE
					var spread := randf_range(-0.12, 0.12)
					var a      := float(e["facing"]) + spread
					enemy_bullets.append({
						"pos":      Vector2(e["pos"]),
						"dir":      Vector2(cos(a), sin(a)),
						"traveled": 0.0,
					})

		alive.append(e)
	enemies = alive

func _enemy_patrol(e: Dictionary, delta: float) -> void:
	var ep : Vector2 = e["pos"]
	var pt : Vector2 = e["patrol_target"]
	if ep.distance_to(pt) < 6.0 or _is_wall(pt):
		# Pick a new random patrol point within ~8 tiles
		for _t in range(20):
			var dx := randf_range(-TILE * 6.0, TILE * 6.0)
			var dy := randf_range(-TILE * 6.0, TILE * 6.0)
			var np := ep + Vector2(dx, dy)
			var tx := int(np.x / TILE); var ty := int(np.y / TILE)
			if tx >= 0 and tx < MAP_W and ty >= 0 and ty < MAP_H and tiles[ty][tx] == 0:
				e["patrol_target"] = np
				break
	_enemy_move_toward(e, e["patrol_target"], ENEMY_SPD * 0.6, delta)
	e["facing"] = (Vector2(e["patrol_target"]) - ep).angle()

func _enemy_move_toward(e: Dictionary, target: Vector2, spd: float, delta: float) -> void:
	var ep  : Vector2 = e["pos"]
	var dir := (target - ep)
	if dir.length_squared() < 1.0: return
	dir = dir.normalized()
	if spd < 0.0:
		dir = -dir; spd = -spd
	e["pos"] = MapGen.resolve_collision(ep + dir * spd * delta, ENEMY_R, tiles)

func _is_wall(p: Vector2) -> bool:
	var tx := int(p.x / TILE); var ty := int(p.y / TILE)
	if tx < 0 or tx >= MAP_W or ty < 0 or ty >= MAP_H: return true
	return tiles[ty][tx] == 1

# ─── Enemy bullet update ──────────────────────────────────────────────────────
func _update_enemy_bullets(delta: float) -> void:
	var step := BULLET_SPEED * delta
	var alive : Array = []
	for b in enemy_bullets:
		b["pos"]      += (b["dir"] as Vector2) * step
		b["traveled"] += step
		if b["traveled"] >= BULLET_RANGE * 0.7: continue
		var bp : Vector2 = b["pos"]
		var btx := int(bp.x / TILE); var bty := int(bp.y / TILE)
		if btx < 0 or btx >= MAP_W or bty < 0 or bty >= MAP_H: continue
		if tiles[bty][btx] == 1: continue
		# Hit player
		if bp.distance_to(player_pos) < PLAYER_R + 4.0:
			var dmg := ENEMY_DMG
			if shield > 0:
				var absorbed := mini(shield, dmg)
				shield -= absorbed
				dmg    -= absorbed
			hp = maxi(0, hp - dmg)
			continue
		alive.append(b)
	enemy_bullets = alive

# ─── Fog polygon (DDA ray sweep) ─────────────────────────────────────────────
func _view_range() -> float:
	var vs := get_viewport_rect().size
	return ceil(vs.length() * 0.5 / ZOOM) + TILE * 3.0

func _update_fog_polygon() -> void:
	_fog_polygon.clear()
	_fog_polygon.append(player_pos)
	var vr := _view_range()
	for i in range(RAY_STEPS + 1):
		var angle : float = (facing - CONE_HALF) + float(i) / float(RAY_STEPS) * 2.0 * CONE_HALF
		var dist  : float = _cast_ray_dda(player_pos, angle, vr)
		_fog_polygon.append(player_pos + Vector2(cos(angle), sin(angle)) * dist)

func _cast_ray_dda(origin: Vector2, angle: float, vr: float) -> float:
	var dx    := cos(angle)
	var dy    := sin(angle)
	var tx    := int(origin.x / TILE)
	var ty    := int(origin.y / TILE)
	var t_dx  : float = abs(TILE / dx) if dx != 0.0 else INF
	var t_dy  : float = abs(TILE / dy) if dy != 0.0 else INF
	var step_x : int = 1 if dx > 0.0 else -1
	var step_y : int = 1 if dy > 0.0 else -1
	var tm_x  := ((tx + 1) * TILE - origin.x) / dx if dx > 0.0 else \
				 (tx * TILE - origin.x)         / dx if dx < 0.0 else INF
	var tm_y  := ((ty + 1) * TILE - origin.y) / dy if dy > 0.0 else \
				 (ty * TILE - origin.y)         / dy if dy < 0.0 else INF
	for _i in range(90):
		var t : float
		if tm_x < tm_y:
			t = tm_x; tx += step_x; tm_x += t_dx
		else:
			t = tm_y; ty += step_y; tm_y += t_dy
		if t >= vr: return vr
		if tx < 0 or tx >= MAP_W or ty < 0 or ty >= MAP_H: return vr
		if tiles[ty][tx] == 1: return t
	return vr

# ─── World draw ───────────────────────────────────────────────────────────────
func _draw() -> void:
	_draw_tiles()
	_draw_items()
	_draw_enemies()
	_draw_enemy_bullets()
	_draw_bullets()
	if extraction_revealed: _draw_extraction()
	_draw_player()

func _draw_bullets() -> void:
	const BULLET_W := 3.0
	const BULLET_L := 10.0
	for b in bullets:
		var bp  : Vector2 = b["pos"]
		var bd  : Vector2 = b["dir"]
		var fwd := bd * BULLET_L * 0.5
		var sid := Vector2(-bd.y, bd.x) * BULLET_W * 0.5
		draw_colored_polygon(PackedVector2Array([
			bp - fwd + sid,
			bp + fwd + sid,
			bp + fwd - sid,
			bp - fwd - sid,
		]), C_BULLET)

func _draw_enemy_bullets() -> void:
	const BULLET_W := 3.0
	const BULLET_L := 9.0
	for b in enemy_bullets:
		if not _is_point_visible(b["pos"]): continue
		var bp  : Vector2 = b["pos"]
		var bd  : Vector2 = b["dir"]
		var fwd := bd * BULLET_L * 0.5
		var sid := Vector2(-bd.y, bd.x) * BULLET_W * 0.5
		draw_colored_polygon(PackedVector2Array([
			bp - fwd + sid,
			bp + fwd + sid,
			bp + fwd - sid,
			bp - fwd - sid,
		]), C_ENEMY_BULLET)

func _draw_enemies() -> void:
	for e in enemies:
		var ep : Vector2 = e["pos"]
		if not _is_point_visible(ep): continue
		var state : int = e["state"]
		# Soft glow — brighter when aggressive
		var glow_a := 0.022 if state == 0 else 0.035
		_soft_glow(ep, ENEMY_R, ENEMY_R * 2.2, glow_a, 16, Color(1.0, 0.25, 0.15))
		# Body
		draw_circle(ep, ENEMY_R, Color(0.12, 0.04, 0.04))
		draw_arc(ep, ENEMY_R, 0.0, TAU, 48,
			Color(3.0, 0.5, 0.3) if state > 0 else Color(1.5, 0.4, 0.3), 2.0)
		# Facing dot
		var fd := Vector2(cos(e["facing"]), sin(e["facing"]))
		draw_circle(ep + fd * (ENEMY_R - 4.0), 3.0, Color(4.0, 1.0, 0.5))

func _draw_items() -> void:
	for item in items:
		if item["collected"]: continue
		var p   : Vector2 = item["pos"]
		if not _is_point_visible(p): continue
		var col : Color   = item["type"]["color"]
		draw_circle(p, 6.0, col)
		draw_arc(p, 7.0, 0.0, TAU, 32, col, 1.5)

func _is_point_visible(wp: Vector2) -> bool:
	var d := player_pos.distance_to(wp)
	if d <= PERCEPTION_R: return true
	if d > _view_range():  return false
	var diff : float = fposmod((wp - player_pos).angle() - facing + PI, TAU) - PI
	if abs(diff) > CONE_HALF: return false
	return _point_in_polygon(wp, _fog_polygon)

static func _point_in_polygon(pt: Vector2, poly: PackedVector2Array) -> bool:
	var n := poly.size()
	if n < 3: return false
	var inside := false
	var j := n - 1
	for i in range(n):
		var xi := poly[i].x; var yi := poly[i].y
		var xj := poly[j].x; var yj := poly[j].y
		if ((yi > pt.y) != (yj > pt.y)) and \
		   (pt.x < (xj - xi) * (pt.y - yi) / (yj - yi) + xi):
			inside = not inside
		j = i
	return inside

func _draw_tiles() -> void:
	var half_w := get_viewport_rect().size.x * 0.5 / ZOOM
	var half_h := get_viewport_rect().size.y * 0.5 / ZOOM
	var px := player_pos.x;  var py := player_pos.y
	var min_tx : int = max(0, int((px - half_w) / TILE) - 1)
	var max_tx : int = min(MAP_W - 1, int((px + half_w) / TILE) + 1)
	var min_ty : int = max(0, int((py - half_h) / TILE) - 1)
	var max_ty : int = min(MAP_H - 1, int((py + half_h) / TILE) + 1)
	for ty in range(min_ty, max_ty + 1):
		for tx in range(min_tx, max_tx + 1):
			var rx := float(tx * TILE)
			var ry := float(ty * TILE)
			if tiles[ty][tx] == 1:
				draw_rect(Rect2(rx, ry, TILE, TILE), C_WALL)
			else:
				draw_rect(Rect2(rx, ry, TILE, TILE), C_FLOOR)
				draw_line(Vector2(rx, ry), Vector2(rx + TILE, ry), C_GRID, 1.0)
				draw_line(Vector2(rx, ry), Vector2(rx, ry + TILE), C_GRID, 1.0)

func _draw_extraction() -> void:
	var ex    := float(extraction.x + 0.5) * float(TILE)
	var ey    := float(extraction.y + 0.5) * float(TILE)
	extraction_visible = _is_point_visible(Vector2(ex, ey))
	if not extraction_visible: return
	var pulse := 0.5 + 0.5 * sin(_pulse_t * TAU)
	var r     := TILE * 0.42
	_soft_glow(Vector2(ex, ey), r, r * 1.4, 0.030 * (0.6 + 0.4 * pulse), 20)
	draw_circle(Vector2(ex, ey), r, Color(1.0, 1.0, 1.0, 0.10 + 0.07 * pulse))
	draw_arc(Vector2(ex, ey), r, 0.0, TAU, 64,
		Color(3.0, 3.0, 3.0, 0.50 + 0.40 * pulse), 2.0)       # HDR → bloom
	draw_string(ThemeDB.fallback_font,
		Vector2(ex - 24.0, ey - r - 6.0),
		"EXTRACT", HORIZONTAL_ALIGNMENT_LEFT, -1, 10,
		Color(1.0, 1.0, 1.0, 0.80 + 0.20 * pulse))

func _draw_player() -> void:
	var p := player_pos
	_draw_player_ring(p)
	if shield > 0:
		_soft_glow(p, PLAYER_R, PLAYER_R * 2.8, 0.028 * float(shield) / float(MAX_SHIELD), 20)
	draw_circle(p, PLAYER_R, Color(0.102, 0.102, 0.102))
	draw_arc(p, PLAYER_R, 0.0, TAU, 64, Color(3.0, 3.0, 3.0), 2.0)  # HDR → bloom
	draw_circle(p, 3.5, Color(5.0, 5.0, 5.0))                        # HDR → strong bloom

# Smooth radial glow: `layers` concentric circles from `inner_r` to `inner_r+spread`,
# peak alpha at `inner_r`, fading to 0 at the outer edge.
func _soft_glow(center: Vector2, inner_r: float, spread: float,
		peak_alpha: float, layers: int, col: Color = Color.WHITE) -> void:
	for i in range(layers, 0, -1):
		var t   := float(i) / float(layers)
		var r   := inner_r + t * spread
		var alp := peak_alpha * (1.0 - t)
		draw_circle(center, r, Color(col.r, col.g, col.b, alp))

func _draw_player_ring(p: Vector2) -> void:
	const INNER_R    := PLAYER_R
	const OUTER_R    := PLAYER_R * 2.0
	const RING_COL   := Color(1.0, 1.0, 1.0, 0.22)
	const LINE_COL   := Color(1.0, 1.0, 1.0, 0.35)
	const LINE_W     := 1.2
	const SPREAD_COL := Color(0.90, 0.70, 0.20, 0.18)
	const SPREAD_SEGS := 16

	# ── 偏移扇区填充（以 facing 轴对称，圆心角 = 2×_current_spread）──────────
	var pts := PackedVector2Array()
	for i in range(SPREAD_SEGS + 1):
		var a := (facing - _current_spread) + float(i) / float(SPREAD_SEGS) * _current_spread * 2.0
		pts.append(p + Vector2(cos(a), sin(a)) * OUTER_R)
	for i in range(SPREAD_SEGS, -1, -1):
		var a := (facing - _current_spread) + float(i) / float(SPREAD_SEGS) * _current_spread * 2.0
		pts.append(p + Vector2(cos(a), sin(a)) * INNER_R)
	draw_colored_polygon(pts, SPREAD_COL)

	# ── 内外圆描边 ────────────────────────────────────────────────────────────
	draw_arc(p, INNER_R, 0.0, TAU, 64, RING_COL, 1.5)
	draw_arc(p, OUTER_R, 0.0, TAU, 80, RING_COL, 1.5)

	# ── 视锥边界线 ────────────────────────────────────────────────────────────
	var a0 := facing - CONE_HALF
	var a1 := facing + CONE_HALF
	draw_line(p + Vector2(cos(a0), sin(a0)) * INNER_R,
			  p + Vector2(cos(a0), sin(a0)) * OUTER_R, LINE_COL, LINE_W)
	draw_line(p + Vector2(cos(a1), sin(a1)) * INNER_R,
			  p + Vector2(cos(a1), sin(a1)) * OUTER_R, LINE_COL, LINE_W)

	# ── 朝向中心线（手动虚线，从外圆起始，锚定消除抖动） ──────────────────
	const DASH_LEN  := 5.0
	const GAP_LEN   := 5.0
	const DASH_END  := 80.0
	var fdir := Vector2(cos(facing), sin(facing))
	var t    := OUTER_R + GAP_LEN
	while t + DASH_LEN <= DASH_END:
		draw_line(p + fdir * t, p + fdir * (t + DASH_LEN), LINE_COL, LINE_W)
		t += DASH_LEN + GAP_LEN
