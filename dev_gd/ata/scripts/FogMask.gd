extends Node2D

var fog_polygon  : PackedVector2Array = PackedVector2Array()
var player_pos   : Vector2            = Vector2.ZERO

const PERCEPTION_R := 90.0

func _draw() -> void:
	# Black background covers entire map in world space
	draw_rect(
		Rect2(Vector2.ZERO, Vector2(MapGen.MAP_W * MapGen.TILE, MapGen.MAP_H * MapGen.TILE)),
		Color.BLACK
	)
	# White cone = visible area
	if fog_polygon.size() >= 3:
		draw_colored_polygon(fog_polygon, Color.WHITE)
	# White perception circle = always-visible near zone
	draw_circle(player_pos, PERCEPTION_R, Color.WHITE)
