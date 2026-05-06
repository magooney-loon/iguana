@tool
extends Control
## Decorative separator for the Aero glass UI.
## Draws a thin gently-wavy line with small diamond end caps.

var is_vertical := false
var sep_color   := Color(0.45, 0.55, 0.75, 0.22)
var wave_amp    := 0.6
var cap_size    := 2.0


func _ready() -> void:
	_fit()
	queue_redraw()


func _draw() -> void:
	if size.x < 2.0 or size.y < 2.0:
		return
	if is_vertical:
		_draw_v()
	else:
		_draw_h()


# ── Horizontal ──────────────────────────────────────────────────────────────

func _draw_h() -> void:
	var mid_y  := size.y * 0.5
	var margin := 10.0
	var left   := margin
	var right  := maxf(size.x - margin, left + 6.0)
	var w      := right - left
	var steps  := 28

	# Gentle wavy line
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := left + t * w
		var y := mid_y + sin(t * PI * 3.0) * wave_amp
		pts.append(Vector2(x, y))
	draw_polyline(pts, sep_color, 1.0, true)

	# Diamond end caps
	_draw_diamond(Vector2(left - 1.0, mid_y))
	_draw_diamond(Vector2(right + 1.0, mid_y))


# ── Vertical ────────────────────────────────────────────────────────────────

func _draw_v() -> void:
	var mid_x  := size.x * 0.5
	var margin := 5.0
	var top    := margin
	var bot    := maxf(size.y - margin, top + 6.0)
	var h      := bot - top
	var steps  := 14

	# Gentle wavy line
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var y := top + t * h
		var x := mid_x + sin(t * PI * 3.0) * wave_amp
		pts.append(Vector2(x, y))
	draw_polyline(pts, sep_color, 1.0, true)

	# Diamond end caps
	_draw_diamond(Vector2(mid_x, top - 1.0))
	_draw_diamond(Vector2(mid_x, bot + 1.0))


# ── Helpers ─────────────────────────────────────────────────────────────────

func _draw_diamond(center: Vector2) -> void:
	var r := cap_size
	var pts := PackedVector2Array([
		center + Vector2(0.0, -r),
		center + Vector2(r,  0.0),
		center + Vector2(0.0,  r),
		center + Vector2(-r, 0.0),
	])
	draw_colored_polygon(pts, sep_color)


func _fit() -> void:
	if is_vertical:
		custom_minimum_size = Vector2(10.0, 0.0)
		size_flags_vertical   = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		custom_minimum_size = Vector2(0.0, 8.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
