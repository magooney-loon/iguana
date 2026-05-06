@tool
extends Control
## Decorative separator for the Aero glass UI.
## Draws a wavy line with diamond end caps that react to audio —
## waves surge on beat, caps pulse and glow.

var is_vertical := false

# ── Audio input (set per frame by StylesUI.update_audio) ────────────────
var beat   := 0.0
var energy := 0.0
var bass   := 0.0

# ── Smoothing ───────────────────────────────────────────────────────────
var _s_beat   := 0.0
var _s_energy := 0.0

# ── Base values ─────────────────────────────────────────────────────────
var _base_color := Color(0.45, 0.55, 0.75, 0.22)
var _base_wave  := 0.5
var _base_cap   := 1.8
var _seed       := 0.0


func _ready() -> void:
	_fit()
	_seed = randf() * 100.0


func _process(_delta: float) -> void:
	_s_beat   = lerpf(_s_beat,   beat,   0.18)
	_s_energy = lerpf(_s_energy, energy, 0.12)
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

	var live_wave := _base_wave + _s_beat * 2.5 + _s_energy * 0.6
	var live_color := _base_color
	live_color.a = _base_color.a + _s_energy * 0.15
	var line_w := 1.0 + _s_beat * 0.8

	# Per-instance wave shape — frequency, phase, secondary wave all unique
	var freq := 2.5 + sin(_seed) * 1.5
	var phase := _seed * 3.7
	var freq2 := 1.8 + cos(_seed * 0.7) * 0.8

	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var x := left + t * w
		var y := mid_y + sin(t * PI * freq + phase) * live_wave
		y += sin(t * PI * freq2 + _seed * 2.1) * live_wave * 0.3
		pts.append(Vector2(x, y))
	draw_polyline(pts, live_color, line_w, true)

	# Diamond end caps — pulse and glow on beat
	_draw_cap(Vector2(left - 1.0, mid_y))
	_draw_cap(Vector2(right + 1.0, mid_y))


# ── Vertical ────────────────────────────────────────────────────────────────

func _draw_v() -> void:
	var mid_x  := size.x * 0.5
	var margin := 5.0
	var top    := margin
	var bot    := maxf(size.y - margin, top + 6.0)
	var h      := bot - top
	var steps  := 14

	var live_wave := _base_wave + _s_beat * 2.0 + _s_energy * 0.4
	var live_color := _base_color
	live_color.a = _base_color.a + _s_energy * 0.15
	var line_w := 1.0 + _s_beat * 0.6

	# Per-instance wave shape
	var freq := 2.5 + sin(_seed * 1.3) * 1.5
	var phase := _seed * 2.9
	var freq2 := 1.5 + cos(_seed * 0.5) * 0.7

	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var y := top + t * h
		var x := mid_x + sin(t * PI * freq + phase) * live_wave
		x += sin(t * PI * freq2 + _seed * 1.7) * live_wave * 0.3
		pts.append(Vector2(x, y))
	draw_polyline(pts, live_color, line_w, true)

	# Diamond end caps — pulse and glow on beat
	_draw_cap(Vector2(mid_x, top - 1.0))
	_draw_cap(Vector2(mid_x, bot + 1.0))


# ── Helpers ─────────────────────────────────────────────────────────────────

func _draw_cap(center: Vector2) -> void:
	var r := _base_cap + _s_beat * 1.8

	# Glow halo on beat — soft circle
	if _s_beat > 0.05:
		var glow_r := r * 2.2
		var glow_col := Color(_base_color.r, _base_color.g, _base_color.b,
			_s_beat * 0.35)
		draw_circle(center, glow_r, glow_col)

	# Solid circle cap
	var cap_col := Color(_base_color.r, _base_color.g, _base_color.b,
		_base_color.a + _s_beat * 0.4)
	draw_circle(center, r, cap_col)


func _fit() -> void:
	if is_vertical:
		custom_minimum_size = Vector2(10.0, 0.0)
		size_flags_vertical   = Control.SIZE_EXPAND_FILL
		size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	else:
		custom_minimum_size = Vector2(0.0, 8.0)
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
