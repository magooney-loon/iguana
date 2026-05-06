class_name StylesUI

# ── Active theme / skin ───────────────────────────────────────────────────────
static var active_theme: UITheme
static var active_skin: UISkin

# ── Shared noise shader ───────────────────────────────────────────────────────
static var _noise_shader: Shader
static var _aero_panels: Array[WeakRef] = []
static var _aero_seps: Array[WeakRef] = []
static var _aero_sep_script: GDScript


static func theme() -> UITheme:
	if active_theme == null:
		active_theme = UITheme.new()
	return active_theme


static func skin() -> UISkin:
	if active_skin == null:
		active_skin = UISkin.new()
	return active_skin


## Load a named theme from ui/themes/<name>.tres.
## Falls back to UITheme defaults if the file is missing or invalid.
static func load_theme(name: String) -> void:
	var path := "res://ui/themes/%s.tres" % name
	if ResourceLoader.exists(path):
		var t := ResourceLoader.load(path) as UITheme
		if t != null:
			active_theme = t
			return
	active_theme = UITheme.new()


## Load a named skin from ui/skins/<name>.tres.
## Falls back to UISkin defaults if the file is missing or invalid.
## Invalidates the cached noise shader so the new shader_path is picked up.
static func load_skin(name: String) -> void:
	var path := "res://ui/skins/%s.tres" % name
	if ResourceLoader.exists(path):
		var s := ResourceLoader.load(path) as UISkin
		if s != null:
			active_skin = s
			_noise_shader = null
			return
	active_skin = UISkin.new()
	_noise_shader = null


static func _get_noise_shader() -> Shader:
	if _noise_shader == null:
		var shader_path := skin().shader_path
		_noise_shader = load(shader_path) as Shader
		if _noise_shader == null:
			push_warning("StylesUI: failed to load shader: %s" % shader_path)
	return _noise_shader


## Apply a grain + vignette material directly to a panel Control.
static func apply_noise(panel: Control, subtle := true) -> void:
	var shader := _get_noise_shader()
	if shader == null:
		return
	var s := skin()
	var mat := ShaderMaterial.new()
	mat.shader = shader
	if subtle:
		mat.set_shader_parameter("grain_strength",      s.subtle_grain_strength)
		mat.set_shader_parameter("grain_speed",         s.subtle_grain_speed)
		mat.set_shader_parameter("vignette_strength",   s.subtle_vignette_strength)
		mat.set_shader_parameter("vignette_pulse",      s.subtle_vignette_pulse)
		mat.set_shader_parameter("vignette_pulse_spd",  s.subtle_vignette_pulse_spd)
	else:
		mat.set_shader_parameter("grain_strength",      s.normal_grain_strength)
		mat.set_shader_parameter("grain_speed",         s.normal_grain_speed)
		mat.set_shader_parameter("vignette_strength",   s.normal_vignette_strength)
		mat.set_shader_parameter("vignette_pulse",      s.normal_vignette_pulse)
		mat.set_shader_parameter("vignette_pulse_spd",  s.normal_vignette_pulse_spd)
	panel.material = mat


## Apply Frutiger Aero gloss + bevel on top of the noise.
static func apply_aero(panel: Control, subtle := true) -> void:
	apply_noise(panel, subtle)
	var mat := panel.material as ShaderMaterial
	if mat == null:
		return
	var s := skin()
	if subtle:
		mat.set_shader_parameter("specular_strength",   s.subtle_specular_strength)
		mat.set_shader_parameter("specular_y_pos",      s.subtle_specular_y_pos)
		mat.set_shader_parameter("specular_height",     s.subtle_specular_height)
		mat.set_shader_parameter("corner_radius",       s.subtle_corner_radius)
		mat.set_shader_parameter("wave_seed",           randf() * 100.0)
		mat.set_shader_parameter("gradient_strength",   s.subtle_gradient_strength)
		mat.set_shader_parameter("fresnel_strength",    s.subtle_fresnel_strength)
		mat.set_shader_parameter("fresnel_width",       s.subtle_fresnel_width)
		mat.set_shader_parameter("bevel_strength",      s.subtle_bevel_strength)
		mat.set_shader_parameter("bevel_width",         s.subtle_bevel_width)
		mat.set_shader_parameter("gloss_texture_str",   s.subtle_gloss_texture_str)
		mat.set_shader_parameter("caustic_scale",       s.subtle_caustic_scale)
		mat.set_shader_parameter("iridescence",         s.subtle_iridescence)
	else:
		mat.set_shader_parameter("specular_strength",   s.normal_specular_strength)
		mat.set_shader_parameter("specular_y_pos",      s.normal_specular_y_pos)
		mat.set_shader_parameter("specular_height",     s.normal_specular_height)
		mat.set_shader_parameter("corner_radius",       s.normal_corner_radius)
		mat.set_shader_parameter("wave_seed",           randf() * 100.0)
		mat.set_shader_parameter("gradient_strength",   s.normal_gradient_strength)
		mat.set_shader_parameter("fresnel_strength",    s.normal_fresnel_strength)
		mat.set_shader_parameter("fresnel_width",       s.normal_fresnel_width)
		mat.set_shader_parameter("bevel_strength",      s.normal_bevel_strength)
		mat.set_shader_parameter("bevel_width",         s.normal_bevel_width)
		mat.set_shader_parameter("gloss_texture_str",   s.normal_gloss_texture_str)
		mat.set_shader_parameter("caustic_scale",       s.normal_caustic_scale)
		mat.set_shader_parameter("iridescence",         s.normal_iridescence)
	_aero_panels.append(WeakRef.new())
	_aero_panels[-1] = weakref(panel)


## Push audio data to all active aero panels and separators every frame.
static func update_audio(beat_val: float, energy_val: float, bass_val: float) -> void:
	var alive: Array[WeakRef] = []
	for ref in _aero_panels:
		var panel := ref.get_ref() as Control
		if panel == null:
			continue
		var mat := panel.material as ShaderMaterial
		if mat == null:
			continue
		mat.set_shader_parameter("beat",   beat_val)
		mat.set_shader_parameter("energy", energy_val)
		mat.set_shader_parameter("bass",   bass_val)
		alive.append(ref)
	_aero_panels = alive

	var live: Array[WeakRef] = []
	for ref in _aero_seps:
		var sep := ref.get_ref() as Control
		if sep == null:
			continue
		sep.set("beat",   beat_val)
		sep.set("energy", energy_val)
		sep.set("bass",   bass_val)
		live.append(ref)
	_aero_seps = live


static func glass_box(bg: Color, radius: float = 10.0, highlight: bool = true) -> StyleBoxFlat:
	var t := theme()
	var s := StyleBoxFlat.new()
	s.bg_color           = bg
	s.border_color       = t.c_hilite if highlight else t.c_border
	s.set_border_width_all(1)
	s.corner_radius_top_left     = int(radius)
	s.corner_radius_top_right    = int(radius)
	s.corner_radius_bottom_right = int(radius)
	s.corner_radius_bottom_left  = int(radius)
	s.shadow_color       = t.c_shadow
	s.shadow_size        = maxi(int(radius * 0.9), 4)
	s.shadow_offset      = Vector2(0, maxf(radius * 0.3, 1.5))
	s.anti_aliasing_size = 2.0
	return s


static func apply_glass_btn(btn: Button) -> void:
	var t  := theme()
	var sk := skin()
	var r  := sk.btn_radius
	var n := glass_box(t.c_btn, r, true)
	n.content_margin_left   = 10.0
	n.content_margin_right  = 10.0
	n.content_margin_top    = 4.0
	n.content_margin_bottom = 4.0
	var h := glass_box(t.c_btn_h, r, true)
	h.content_margin_left   = 10.0
	h.content_margin_right  = 10.0
	h.content_margin_top    = 4.0
	h.content_margin_bottom = 4.0
	h.shadow_size = 14
	var p := glass_box(t.c_btn_p, r, true)
	p.content_margin_left   = 10.0
	p.content_margin_right  = 10.0
	p.content_margin_top    = 5.0
	p.content_margin_bottom = 3.0
	p.shadow_size   = 4
	p.shadow_offset = Vector2(0, 1)
	btn.add_theme_stylebox_override("normal",  n)
	btn.add_theme_stylebox_override("hover",   h)
	btn.add_theme_stylebox_override("pressed", p)


static func apply_glass_slider(slider: HSlider, compact := false) -> void:
	var t  := theme()
	var sk := skin()
	var track_h  := sk.slider_track_compact if compact else sk.slider_track_normal
	var grab_size := sk.slider_grab_compact  if compact else sk.slider_grab_normal
	var radius   := 4.0 if compact else 5.0

	var bg := StyleBoxFlat.new()
	bg.bg_color     = t.c_slider_bg
	bg.border_color = Color(t.c_border.r, t.c_border.g, t.c_border.b, 0.12)
	bg.set_border_width_all(1)
	bg.corner_radius_top_left     = int(radius)
	bg.corner_radius_top_right    = int(radius)
	bg.corner_radius_bottom_right = int(radius)
	bg.corner_radius_bottom_left  = int(radius)
	bg.content_margin_top    = track_h
	bg.content_margin_bottom = track_h
	slider.add_theme_stylebox_override("slider", bg)

	var fill := StyleBoxFlat.new()
	fill.bg_color     = t.c_slider_fill
	fill.border_color = Color(t.c_border.r, t.c_border.g, t.c_border.b, 0.20)
	fill.set_border_width_all(1)
	fill.corner_radius_top_left     = int(radius)
	fill.corner_radius_top_right    = int(radius)
	fill.corner_radius_bottom_right = int(radius)
	fill.corner_radius_bottom_left  = int(radius)
	fill.content_margin_top    = track_h
	fill.content_margin_bottom = track_h
	slider.add_theme_stylebox_override("fill", fill)

	var grab := StyleBoxFlat.new()
	grab.bg_color     = t.c_grabber
	grab.border_color = t.c_hilite
	grab.set_border_width_all(1)
	grab.corner_radius_top_left     = int(grab_size / 2.0)
	grab.corner_radius_top_right    = int(grab_size / 2.0)
	grab.corner_radius_bottom_right = int(grab_size / 2.0)
	grab.corner_radius_bottom_left  = int(grab_size / 2.0)
	grab.shadow_color  = t.c_shadow
	grab.shadow_size   = 4
	grab.shadow_offset = Vector2(0, 2)
	grab.anti_aliasing_size   = 2.0
	grab.content_margin_left  = grab_size
	grab.content_margin_right = grab_size
	grab.content_margin_top   = grab_size
	grab.content_margin_bottom = grab_size
	slider.add_theme_stylebox_override("grabber_area", grab)

	var grab_h := StyleBoxFlat.new()
	grab_h.bg_color     = t.c_grabber_h
	grab_h.border_color = Color(t.c_grabber_h.r + 0.15, t.c_grabber_h.g + 0.07, t.c_grabber_h.b, 0.4)
	grab_h.set_border_width_all(1)
	grab_h.corner_radius_top_left     = int(grab_size / 2.0)
	grab_h.corner_radius_top_right    = int(grab_size / 2.0)
	grab_h.corner_radius_bottom_right = int(grab_size / 2.0)
	grab_h.corner_radius_bottom_left  = int(grab_size / 2.0)
	grab_h.shadow_color  = t.c_shadow
	grab_h.shadow_size   = 6
	grab_h.shadow_offset = Vector2(0, 3)
	grab_h.anti_aliasing_size    = 2.0
	grab_h.content_margin_left   = grab_size + 1.0
	grab_h.content_margin_right  = grab_size + 1.0
	grab_h.content_margin_top    = grab_size + 1.0
	grab_h.content_margin_bottom = grab_size + 1.0
	slider.add_theme_stylebox_override("grabber_area_highlight", grab_h)


static func apply_bar_style(panel: PanelContainer) -> void:
	var t  := theme()
	var sk := skin()
	var style := glass_box(t.c_glass_dark, sk.bar_radius, true)
	style.corner_radius_bottom_left  = 0
	style.corner_radius_bottom_right = 0
	style.content_margin_left   = sk.bar_padding_h
	style.content_margin_right  = sk.bar_padding_h
	style.content_margin_top    = sk.bar_padding_v
	style.content_margin_bottom = sk.bar_padding_v
	style.shadow_size = sk.bar_shadow_size
	panel.add_theme_stylebox_override("panel", style)


static func make_vsep() -> Control:
	if _aero_sep_script == null:
		_aero_sep_script = load("res://ui/aero_sep.gd")
	var sep := Control.new()
	sep.set_script(_aero_sep_script)
	sep.set("is_vertical",  true)
	sep.set("_base_color",  theme().c_sep_draw)
	sep.set("_base_wave",   skin().sep_base_wave)
	sep.set("_base_cap",    skin().sep_base_cap)
	_aero_seps.append(weakref(sep))
	return sep


static func load_icon(name: String) -> Texture2D:
	var path := "res://ui/icons/%s.svg" % name
	var tex := load(path) as Texture2D
	if tex == null:
		push_warning("StylesUI: icon not found: %s" % path)
	return tex


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


static func set_icon(btn: Button, icon_name: String) -> void:
	var tex := load_icon(icon_name)
	if tex:
		btn.icon = tex
	btn.text = ""


static func make_link_label(text: String, url: String, font_size: int = 12) -> Label:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.modulate = theme().c_link
	lbl.mouse_filter = Control.MOUSE_FILTER_STOP
	lbl.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	lbl.set_meta("link_url", url)
	lbl.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			OS.shell_open(url)
	)
	lbl.mouse_entered.connect(func() -> void:
		lbl.modulate = theme().c_link_h
		lbl.add_theme_color_override("font_color", theme().c_link_h)
	)
	lbl.mouse_exited.connect(func() -> void:
		lbl.modulate = theme().c_link
		lbl.add_theme_color_override("font_color", theme().c_link)
	)
	return lbl


static func win_section(parent: Control, title: String) -> void:
	var lbl := Label.new()
	lbl.text = title
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.modulate = theme().c_section
	parent.add_child(lbl)


static func win_sep(parent: Control) -> void:
	if _aero_sep_script == null:
		_aero_sep_script = load("res://ui/aero_sep.gd")
	var sep := Control.new()
	sep.set_script(_aero_sep_script)
	sep.set("is_vertical", false)
	sep.set("_base_color",  theme().c_sep_draw)
	sep.set("_base_wave",   skin().sep_base_wave)
	sep.set("_base_cap",    skin().sep_base_cap)
	_aero_seps.append(weakref(sep))
	parent.add_child(sep)
