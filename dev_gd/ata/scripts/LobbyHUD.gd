extends Node2D

@onready var _touch : TouchInput = get_parent().get_node("TouchInput")

func _process(_delta: float) -> void:
	_touch.set_centers(get_viewport_rect().size)
	queue_redraw()

func _draw() -> void:
	var lc := _touch.left_center
	if _touch.is_sprinting:
		for i in range(20, 0, -1):
			var t := float(i) / 20.0
			draw_arc(lc, TouchInput.LEFT_R + t * 20.0, 0.0, TAU, 64,
				Color(1.0, 1.0, 1.0, 0.06 * (1.0 - t)), 3.0)
	var ring_col := Color(1.0, 1.0, 1.0, 0.80) if _touch.is_sprinting else Color(1, 1, 1, 0.18)
	draw_arc(lc, TouchInput.LEFT_R, 0.0, TAU, 64, ring_col, 2.0)
	var lk := _touch.get_left_knob()
	draw_circle(lk, 22.0, Color(1, 1, 1, 0.22))
	draw_arc(lk, 22.0, 0.0, TAU, 40, Color(1, 1, 1, 0.55), 2.0)
