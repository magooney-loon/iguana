class_name StylesUI

## ── Shared noise shader ──────────────────────────────────────────────────────
## Loaded once and reused for every panel that requests an industrial overlay.
static var _noise_shader: Shader


static func _get_noise_shader() -> Shader:
	if _noise_shader == null:
		_noise_shader = load("res://shaders/ui_noise.gdshader") as Shader
		if _noise_shader == null:
			push_warning("StylesUI: failed to load ui_noise.gdshader")
	return _noise_shader


## Apply an industrial noise material directly to a panel Control.
## The canvas_item shader modifies the panel's rendered StyleBox output
## in-place — no extra children needed.
static func apply_noise(panel: Control, subtle := true) -> void:
	var shader := _get_noise_shader()
	if shader == null:
		return

	var mat := ShaderMaterial.new()
	mat.shader = shader
	if subtle:
		# Grain
		mat.set_shader_parameter("grain_strength", 0.03)
		mat.set_shader_parameter("grain_speed", 1.0)
		# Scanlines
		mat.set_shader_parameter("scanline_strength", 0.025)
		mat.set_shader_parameter("scanline_scroll_spd", 0.2)
		# Scratches
		mat.set_shader_parameter("scratch_strength", 0.015)
		mat.set_shader_parameter("scratch_drift", 0.1)
		# CRT effects
		mat.set_shader_parameter("flicker_strength", 0.01)
		mat.set_shader_parameter("roll_speed", 0.035)
		mat.set_shader_parameter("roll_strength", 0.02)
		mat.set_shader_parameter("interference_str", 0.01)
		# Vignette
		mat.set_shader_parameter("vignette_strength", 0.06)
		mat.set_shader_parameter("vignette_pulse", 0.015)
		mat.set_shader_parameter("vignette_pulse_spd", 0.4)
		# Chromatic aberration
		mat.set_shader_parameter("chromatic_str", 0.0006)
		mat.set_shader_parameter("chromatic_flicker", 0.3)
	else:
		# Grain
		mat.set_shader_parameter("grain_strength", 0.05)
		mat.set_shader_parameter("grain_speed", 1.5)
		# Scanlines
		mat.set_shader_parameter("scanline_strength", 0.05)
		mat.set_shader_parameter("scanline_scroll_spd", 0.4)
		# Scratches
		mat.set_shader_parameter("scratch_strength", 0.03)
		mat.set_shader_parameter("scratch_drift", 0.25)
		# CRT effects
		mat.set_shader_parameter("flicker_strength", 0.025)
		mat.set_shader_parameter("roll_speed", 0.06)
		mat.set_shader_parameter("roll_strength", 0.04)
		mat.set_shader_parameter("interference_str", 0.025)
		# Vignette
		mat.set_shader_parameter("vignette_strength", 0.12)
		mat.set_shader_parameter("vignette_pulse", 0.03)
		mat.set_shader_parameter("vignette_pulse_spd", 0.7)
		# Chromatic aberration
		mat.set_shader_parameter("chromatic_str", 0.0012)
		mat.set_shader_parameter("chromatic_flicker", 0.5)
	panel.material = mat


## ── Aero Glass Theme ──────────────────────────────────────────────────────────
## Colour palette
const C_GLASS     := Color(0.08, 0.09, 0.16, 0.68)
const C_GLASS_LT := Color(0.14, 0.16, 0.26, 0.55)
const C_BORDER   := Color(0.55, 0.65, 0.85, 0.18)
const C_HILITE   := Color(0.70, 0.80, 1.00, 0.22)
const C_SHADOW   := Color(0.0, 0.0, 0.02, 0.45)
const C_BTN      := Color(0.16, 0.18, 0.28, 0.35)
const C_BTN_H    := Color(0.30, 0.38, 0.55, 0.45)
const C_BTN_P    := Color(0.08, 0.09, 0.14, 0.50)
const C_ACCENT   := Color(0.40, 0.58, 0.92, 0.35)


static func glass_box(bg: Color, radius: float = 10.0, highlight: bool = true) -> StyleBoxFlat:
	var s := StyleBoxFlat.new()
	s.bg_color           = bg
	s.border_color       = C_BORDER
	s.set_border_width_all(1)
	s.corner_radius_top_left     = int(radius)
	s.corner_radius_top_right    = int(radius)
	s.corner_radius_bottom_right = int(radius)
	s.corner_radius_bottom_left  = int(radius)
	s.shadow_color       = C_SHADOW
	s.shadow_size        = 8
	s.shadow_offset      = Vector2(0, 3)
	if highlight:
		s.border_color = C_HILITE
	return s


static func apply_glass_btn(btn: Button) -> void:
	var n := glass_box(C_BTN, 7.0, true)
	n.content_margin_left   = 10.0
	n.content_margin_right  = 10.0
	n.content_margin_top    = 4.0
	n.content_margin_bottom = 4.0
	var h := glass_box(C_BTN_H, 7.0, true)
	h.content_margin_left   = 10.0
	h.content_margin_right  = 10.0
	h.content_margin_top    = 4.0
	h.content_margin_bottom = 4.0
	var p := glass_box(C_BTN_P, 7.0, true)
	p.content_margin_left   = 10.0
	p.content_margin_right  = 10.0
	p.content_margin_top    = 4.0
	p.content_margin_bottom = 4.0
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)


static func apply_bar_style(panel: PanelContainer) -> void:
	var style := glass_box(Color(0.06, 0.07, 0.12, 0.72), 12.0, true)
	style.content_margin_left   = 14.0
	style.content_margin_right  = 14.0
	style.content_margin_top    = 8.0
	style.content_margin_bottom = 8.0
	style.shadow_size = 14
	panel.add_theme_stylebox_override("panel", style)


static func make_vsep() -> VSeparator:
	return VSeparator.new()


## Load an SVG icon from ui/icons/<name>.svg and return a Texture2D.
static func load_icon(name: String) -> Texture2D:
	var path := "res://ui/icons/%s.svg" % name
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("StylesUI: icon not found: %s" % path)
	return tex


## Create a Button with only an icon (no text) and a tooltip.
## Connects `callback` to `pressed` if it's valid.
static func icon_btn(icon_name: String, tooltip: String = "",
		min_size := Vector2(32, 28), callback: Callable = Callable()) -> Button:
	var btn := Button.new()
	var tex := load_icon(icon_name)
	if tex:
		btn.icon = tex
		btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		btn.expand_icon = true
	btn.tooltip_text = tooltip
	btn.custom_minimum_size = min_size
	btn.focus_mode = Control.FOCUS_NONE
	if callback.is_valid():
		btn.pressed.connect(callback)
	apply_glass_btn(btn)
	return btn


## Update the icon on an existing button (for play/pause, loop modes, etc.).
static func set_icon(btn: Button, icon_name: String) -> void:
	var tex := load_icon(icon_name)
	if tex:
		btn.icon = tex
	btn.text = ""


## Create a Label that acts as a clickable link.
## Stores `url` in metadata and opens it in the system browser on click.
static func make_link_label(text: String, url: String, font_size: int = 12) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = Color(0.55, 0.75, 1.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lbl.set_meta("link_url", url)
	lbl.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url)
	)
	lbl.mouse_entered.connect(func() -> void:
		lbl.modulate = Color(0.70, 0.88, 1.0)
		lbl.add_theme_color_override("font_color", Color(0.70, 0.88, 1.0))
	)
	lbl.mouse_exited.connect(func() -> void:
		lbl.modulate = Color(0.55, 0.75, 1.0)
		lbl.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
	)
	return lbl


static func win_section(parent: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = Color(0.55, 0.8, 1.0, 0.75)
	parent.add_child(lbl)


static func win_sep(parent: Control) -> void:
	parent.add_child(HSeparator.new())
