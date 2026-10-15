extends Control
## Small screen-space location cue, shown only when geometry obscures the bird.
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	hide()

func _draw() -> void:
	var points := PackedVector2Array([Vector2(0, -8), Vector2(7, 0), Vector2(0, 8), Vector2(-7, 0)])
	draw_colored_polygon(points, Color("f3d491"))
	points.append(points[0])
	draw_polyline(points, Color("29413b"), 2.0, true)
	draw_circle(Vector2.ZERO, 2, Color("29413b"))
