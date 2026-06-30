class_name TouchInput
extends Node

# ─── Joystick geometry ────────────────────────────────────────────────────────
const LEFT_R        := 90.0
const RIGHT_INNER_R := 65.0
const RIGHT_OUTER_R := 150.0

# ─── Public state ─────────────────────────────────────────────────────────────
var move_dir    : Vector2 = Vector2.ZERO
var is_sprinting: bool    = false
var has_facing  : bool    = false
var facing      : float   = 0.0
var is_shooting : bool    = false   # continuous fire (inner-start mode in outer ring)
var shoot_tap   : bool    = false   # consumed by Raid: fire one bullet
var tap_facing  : float   = 0.0

# ─── Centers ──────────────────────────────────────────────────────────────────
var left_center  : Vector2 = Vector2.ZERO
var right_center : Vector2 = Vector2.ZERO
var _vsize       : Vector2 = Vector2.ZERO

func set_centers(vsize: Vector2) -> void:
	_vsize       = vsize
	left_center  = Vector2(160.0, vsize.y - 160.0)
	right_center = Vector2(vsize.x - 160.0, vsize.y - 160.0)

# ─── Touch tracking ───────────────────────────────────────────────────────────
var _left_id    : int  = -1
var _left_pos   : Vector2 = Vector2.ZERO

var _right_id           : int     = -1
var _right_pos          : Vector2 = Vector2.ZERO
var _right_in_outer     : bool    = false  # finger currently in outer ring
var _right_started_outer: bool    = false  # touch started in outer ring (tap mode)

# ─── Input ────────────────────────────────────────────────────────────────────
func _input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var e := event as InputEventScreenTouch
		_touch_raw(e.index, e.position, e.pressed)
	elif event is InputEventScreenDrag:
		var e := event as InputEventScreenDrag
		_drag_raw(e.index, e.position)
	elif not DisplayServer.is_touchscreen_available():
		if event is InputEventMouseButton:
			var e := event as InputEventMouseButton
			if e.button_index == MOUSE_BUTTON_LEFT:
				_touch_raw(0, e.position, e.pressed)
		elif event is InputEventMouseMotion:
			if Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
				_drag_raw(0, (event as InputEventMouseMotion).position)

func _touch_raw(id: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var in_left  := pos.distance_to(left_center)  <= LEFT_R
		var in_right := pos.distance_to(right_center) <= RIGHT_OUTER_R
		if in_left and _left_id == -1:
			_left_id  = id
			_left_pos = pos
			_update_move()
		elif in_right and _right_id == -1:
			_right_id    = id
			_right_pos   = pos
			var dist     := pos.distance_to(right_center)
			_right_in_outer      = dist >= RIGHT_INNER_R
			_right_started_outer = _right_in_outer
			is_shooting          = false
			_update_right()
		# Touches outside both joystick zones: ignored
	else:
		if id == _left_id:
			_left_id     = -1
			move_dir     = Vector2.ZERO
			is_sprinting = false
		elif id == _right_id:
			if _right_started_outer:
				# Tap mode: fire if still in outer ring, cancel if in inner
				if _right_in_outer:
					shoot_tap  = true
					tap_facing = facing
			# Continuous mode ends automatically (is_shooting = false below)
			_right_id            = -1
			_right_in_outer      = false
			_right_started_outer = false
			has_facing           = false
			is_shooting          = false

func _drag_raw(id: int, pos: Vector2) -> void:
	if id == _left_id:
		_left_pos = pos
		_update_move()
	elif id == _right_id:
		_right_pos = pos
		_update_right()

func _update_move() -> void:
	var d := _left_pos - left_center
	is_sprinting = d.length() > LEFT_R
	if d.length() > LEFT_R: d = d.normalized() * LEFT_R
	move_dir = d / LEFT_R

func _update_right() -> void:
	var d    := _right_pos - right_center
	var dist := d.length()
	if dist > 0.1:
		facing     = d.angle()
		has_facing = true
	_right_in_outer = dist >= RIGHT_INNER_R

	if not _right_started_outer:
		# Continuous mode: shoot whenever in outer ring
		is_shooting = _right_in_outer

# ─── Queries ──────────────────────────────────────────────────────────────────
func left_active()  -> bool: return _left_id  != -1
func right_active() -> bool: return _right_id != -1

func get_left_knob() -> Vector2:
	if _left_id == -1: return left_center
	var d := _left_pos - left_center
	if d.length() > LEFT_R: d = d.normalized() * LEFT_R
	return left_center + d

func get_right_knob() -> Vector2:
	if _right_id == -1: return right_center
	var d := _right_pos - right_center
	if d.length() > RIGHT_OUTER_R: d = d.normalized() * RIGHT_OUTER_R
	return right_center + d
