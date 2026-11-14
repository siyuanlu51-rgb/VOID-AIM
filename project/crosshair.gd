extends Control

var shape_index := 0
var line_length := 9.0
var line_thickness := 2.0
var crosshair_color := Color.WHITE
var opacity := 1.0
var gap := 4.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	queue_redraw()


func apply_style(shape_: int, length_: float, thickness_: float, color_: Color, opacity_: float, gap_: float) -> void:
	shape_index = shape_
	line_length = length_
	line_thickness = thickness_
	crosshair_color = color_
	opacity = opacity_
	gap = gap_
	queue_redraw()


func _draw() -> void:
	var center := size * 0.5
	var color := crosshair_color
	color.a *= opacity
	if shape_index == 1:
		draw_circle(center, maxf(1.5, line_thickness * 1.15), color)
		return
	if shape_index == 2:
		draw_arc(center, maxf(3.0, line_length * 0.68), 0.0, TAU, 48, color, line_thickness, true)
		return
	draw_line(center + Vector2(-gap - line_length, 0), center + Vector2(-gap, 0), color, line_thickness, true)
	draw_line(center + Vector2(gap, 0), center + Vector2(gap + line_length, 0), color, line_thickness, true)
	draw_line(center + Vector2(0, -gap - line_length), center + Vector2(0, -gap), color, line_thickness, true)
	draw_line(center + Vector2(0, gap), center + Vector2(0, gap + line_length), color, line_thickness, true)
	if shape_index == 3:
		draw_circle(center, maxf(1.2, line_thickness * 0.8), color)
