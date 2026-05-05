extends ColorRect

const SHADERS := [
	{ "path": "res://shaders/starfall.gdshader",        "name": "Starfall" },
	{ "path": "res://shaders/afterimage.gdshader",      "name": "Afterimage" },
	{ "path": "res://shaders/phosphorescence.gdshader", "name": "Phosphorescence" },
	{ "path": "res://shaders/submersion.gdshader",      "name": "Submersion" },
	{ "path": "res://shaders/hyperspatial.gdshader",    "name": "Hyperspatial" },
]

var _analyzer: AudioAnalyzer
var _loaded_shaders: Array[Shader] = []
var _shader_index   := 0

# Feedback buffer: self renders into _feedback_vp; shader reads from _backbuffer_vp.
# Two-viewport design avoids the GPU "same texture as framebuffer and uniform" error:
# _backbuffer_vp copies _feedback_vp's output each frame (renders after it in the tree),
# so the shader always reads last frame's completed output, never its own live target.
var _feedback_vp:   SubViewport
var _backbuffer_vp: SubViewport

# Auto-shuffle
var shuffle_interval := 45.0   # var so the settings window can change it
var _shuffle_timer   := 0.0
var _shuffle_on      := false

# Beat-triggered switching cooldown (prevents rapid-fire switches)
const SWITCH_COOLDOWN_MIN := 4.0
var _switch_cooldown := 0.0

# Frame counter for shaders that need per-frame parity or rhythm effects
var _frame_count := 0

# UI overlay (lives on SubViewportContainer, not inside SubViewport)
var _ui: NotificationUI

var _noise_tex: NoiseTexture2D

# Shader transition
var _transition_overlay: TextureRect
var _transitioning := false
var _transition_time := 0.0
const TRANSITION_DURATION := 1.5

# Post-processing display layer — reads raw FeedbackViewport texture,
# applies tonemap/gamma/vignette/grain without feeding back into prev_frame.
var _post_display: ColorRect
var _post_mat:     ShaderMaterial

# Post-process params (exposed so the settings window can modify them)
var pp_exposure       := 1.42
var pp_tonemap_knee   := 0.0
var pp_gamma          := 2.0
var pp_vignette_dark  := 0.30
var pp_grain_strength := 0.01
var pp_loop_reinhard  := 0.0   # per-shader feedback-loop Reinhard compression

# Per-shader post-processing overrides (one dict per shader).
var _shader_pp_configs: Array[Dictionary] = []
const PP_DEFAULTS := {
	"exposure":       1.42,
	"tonemap_knee":   0.0,
	"gamma":          2.0,
	"vignette_dark":  0.30,
	"grain_strength": 0.01,
	"loop_reinhard":  0.0,
}
# Default loop_reinhard per shader (matches each .gdshader default)
const _SHADER_REINHARD_DEFAULTS := [0.9, 1.2, 1.0, 0.69, 0.18]



func _ready() -> void:
	_analyzer = AudioAnalyzer.new()
	_analyzer.setup(
		AudioServer.get_bus_effect_instance(0, 0),
		owner.get_node("Player") as AudioStreamPlayer,
	)

	for def in SHADERS:
		_loaded_shaders.append(load(def.path))

	# Initialize per-shader PP configs with defaults
	for i in _loaded_shaders.size():
		var cfg := PP_DEFAULTS.duplicate()
		cfg["loop_reinhard"] = _SHADER_REINHARD_DEFAULTS[i]
		_shader_pp_configs.append(cfg)

	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = _loaded_shaders[0]

	# _feedback_vp is our direct parent (SubViewport); container is its parent.
	# stretch = true on the container means Godot manages SubViewport size automatically.
	_feedback_vp = get_parent() as SubViewport
	var container := _feedback_vp.get_parent() as SubViewportContainer

	# Build the backbuffer: a separate SubViewport with a TextureRect that copies
	# _feedback_vp's output. It is added as a sibling of VisualizerContainer so
	# Godot renders it AFTER _feedback_vp, guaranteeing it always holds the
	# previous frame by the time the shader runs next frame.
	_backbuffer_vp = SubViewport.new()
	_backbuffer_vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_backbuffer_vp.transparent_bg = false
	_backbuffer_vp.size = Vector2i(1600, 900)

	var bb_rect := TextureRect.new()
	bb_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bb_rect.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	bb_rect.stretch_mode = TextureRect.STRETCH_SCALE
	bb_rect.texture = _feedback_vp.get_texture()
	_backbuffer_vp.add_child(bb_rect)

	# Keep backbuffer resolution in sync with the display area.
	container.resized.connect(func():
		if container.size != Vector2.ZERO:
			_backbuffer_vp.size = Vector2i(container.size)
	)

	# Post-processing display layer: covers the raw SubViewportContainer output with
	# a tone-mapped/gamma-corrected version. It reads _feedback_vp.get_texture() as
	# a plain uniform — it is NEVER the render target, so nothing feeds back through it.
	_post_mat = ShaderMaterial.new()
	_post_mat.shader = load("res://shaders/post_process.gdshader")
	_post_display = ColorRect.new()
	_post_display.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_post_display.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_post_display.material = _post_mat

	# UI lives on the container so it is NOT captured in the feedback texture.
	# If it were inside the SubViewport its labels would trail and spiral forever.
	_ui = NotificationUI.new()
	_ui.setup(_analyzer, SHADERS, self)

	# Defer add_child calls: parent nodes are still setting up at _ready() time.
	# post_display goes in before UI/overlay so UI renders above it.
	container.add_child.call_deferred(_post_display)
	container.add_child.call_deferred(_ui)
	container.get_parent().add_child.call_deferred(_backbuffer_vp)

	# Transition overlay: sits on top of the visualizer, fades out during switch
	_transition_overlay = TextureRect.new()
	_transition_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_transition_overlay.expand_mode  = TextureRect.EXPAND_IGNORE_SIZE
	_transition_overlay.stretch_mode = TextureRect.STRETCH_SCALE
	_transition_overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_transition_overlay.hide()
	container.add_child.call_deferred(_transition_overlay)

	var fnoise := FastNoiseLite.new()
	fnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnoise.frequency = 0.04
	fnoise.fractal_octaves = 4
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.noise = fnoise
	_noise_tex.seamless = true

	# Sync per-shader PP defaults to Config (centralized store)
	Config.shader_pp_configs = _shader_pp_configs
	Config.load_settings()
	# Apply loaded general settings
	shuffle_interval = Config.shuffle_interval
	_shuffle_on = Config.shuffle_on
	_post_display.visible = Config.post_enabled
	# Apply loaded shader index and PP config
	_shader_index = Config.shader_index
	(material as ShaderMaterial).shader = _loaded_shaders[_shader_index]
	_apply_pp_config(_shader_index)


# ── Input and shader switching ─────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	var kc: int = (event as InputEventKey).keycode
	if kc == Keymap.get_key("next_shader"):
		_switch((_shader_index + 1) % _loaded_shaders.size())
	elif kc == Keymap.get_key("prev_shader"):
		_switch((_shader_index - 1 + _loaded_shaders.size()) % _loaded_shaders.size())
	elif kc == Keymap.get_key("toggle_shuffle"):
		_toggle_shuffle()
	elif kc == Keymap.get_key("toggle_postproc"):
		_toggle_post_process()


func _switch(idx: int) -> void:
	# Save current shader's PP config before switching away
	_save_current_pp_config()

	# Capture a STATIC snapshot of the current frame for cross-fade
	var img: Image = _backbuffer_vp.get_texture().get_image()
	_transition_overlay.texture = ImageTexture.create_from_image(img)
	_transition_overlay.modulate.a = 1.0
	_transition_overlay.show()
	_transitioning = true
	_transition_time = 0.0

	_shader_index  = idx
	_shuffle_timer = 0.0
	(material as ShaderMaterial).shader = _loaded_shaders[idx]
	_ui.on_shader_changed(idx)
	_ui.show_label("< %s >" % SHADERS[idx].name)

	# Apply new shader's post-processing config
	_apply_pp_config(idx)


func _toggle_shuffle() -> void:
	_shuffle_on    = !_shuffle_on
	_shuffle_timer = 0.0
	Config.shuffle_on = _shuffle_on
	Config.save()
	_ui.show_label("Shader Shuffle %s" % ("ON" if _shuffle_on else "OFF"))


func _toggle_post_process() -> void:
	_post_display.visible = !_post_display.visible
	Config.post_enabled = _post_display.visible
	Config.save()
	_ui.show_label("Post-process %s" % ("ON" if _post_display.visible else "OFF"))


func _shuffle() -> void:
	var next := _shader_index
	while next == _shader_index:
		next = randi() % _loaded_shaders.size()
	_switch(next)


# ── Frame loop ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_analyzer.process(delta)
	_frame_count += 1

	if _analyzer.is_sounding:
		# Beat-triggered switching: fires on a strong confirmed kick.
		# Only active when shuffle is on; cooldown prevents rapid switches.
		_switch_cooldown = maxf(0.0, _switch_cooldown - delta)
		if _shuffle_on and _switch_cooldown <= 0.0 \
				and _analyzer._beat_confidence > 0.5 \
				and _analyzer._kick_envelope > 0.85:
			_shuffle()
			_switch_cooldown = SWITCH_COOLDOWN_MIN

		# Timer-based fallback (fires when beat confidence is too low to trigger above)
		_shuffle_timer += delta
		if _shuffle_on and _shuffle_timer >= shuffle_interval:
			_shuffle()
			_switch_cooldown = SWITCH_COOLDOWN_MIN

	_ui.process_ui(delta)

	# Fade the transition overlay out
	if _transitioning:
		_transition_time += delta
		var t := clampf(_transition_time / TRANSITION_DURATION, 0.0, 1.0)
		# Smooth ease-out curve
		_transition_overlay.modulate.a = 1.0 - t * t
		if t >= 1.0:
			_transitioning = false
			_transition_overlay.hide()

	_push_uniforms(material as ShaderMaterial)


# ── Shader uniforms ────────────────────────────────────────────────

func _push_uniforms(mat: ShaderMaterial) -> void:
	var a := _analyzer
	mat.set_shader_parameter("rect_size", get_rect().size)

	# Read from the backbuffer (copy of last frame), not from _feedback_vp itself.
	# The GPU forbids using a viewport's own texture as both framebuffer and sampler.
	mat.set_shader_parameter("prev_frame", _backbuffer_vp.get_texture())

	# Frame counter: enables per-frame parity and rhythm effects.
	mat.set_shader_parameter("frame", _frame_count)

	mat.set_shader_parameter("sub_bass",    a._sub_bass)
	mat.set_shader_parameter("bass",        a._bass)
	mat.set_shader_parameter("low_mid",     a._low_mid)
	mat.set_shader_parameter("mid",         a._mid)
	mat.set_shader_parameter("presence",    a._presence)
	mat.set_shader_parameter("treble",      a._treble)
	mat.set_shader_parameter("beat",        a._beat_envelope)
	mat.set_shader_parameter("kick",        a._kick_envelope)
	mat.set_shader_parameter("snare",       a._snare_envelope)
	mat.set_shader_parameter("hihat",       a._hihat_envelope)
	mat.set_shader_parameter("flux_bass",   a._flux_bass)
	mat.set_shader_parameter("flux_mid",    a._flux_mid)
	mat.set_shader_parameter("flux_treble", a._flux_treble)
	mat.set_shader_parameter("energy",      a._energy)
	mat.set_shader_parameter("activity",    a._activity)
	mat.set_shader_parameter("onset",       a._onset)
	mat.set_shader_parameter("loudness",    a._loudness)
	mat.set_shader_parameter("warmth",      a._warmth)
	mat.set_shader_parameter("brightness",  a._brightness)
	mat.set_shader_parameter("density",     a._density)
	mat.set_shader_parameter("beat_phase",  a._beat_phase)
	mat.set_shader_parameter("bpm",         a._bpm)
	mat.set_shader_parameter("beat_confidence", a._beat_confidence)
	mat.set_shader_parameter("beat_threshold",  a._beat_threshold)
	mat.set_shader_parameter("kick_threshold",  a._kick_threshold)
	mat.set_shader_parameter("snare_threshold", a._snare_threshold)
	mat.set_shader_parameter("hihat_threshold", a._hihat_threshold)
	mat.set_shader_parameter("time_val",    a._time)
	mat.set_shader_parameter("noise_tex",   _noise_tex)
	mat.set_shader_parameter("loop_reinhard", pp_loop_reinhard)
	for i in range(a._row_peaks.size()):
		mat.set_shader_parameter("peak_%02d" % i, a._row_peaks[i])

	# Push post-process uniforms to the display layer each frame.
	# screen_tex is set once here because get_texture() returns a stable object,
	# but we re-set it to avoid any edge cases on first frame.
	_post_mat.set_shader_parameter("screen_tex",     _feedback_vp.get_texture())
	_post_mat.set_shader_parameter("noise_tex",      _noise_tex)
	_post_mat.set_shader_parameter("time_val",       a._time)
	_post_mat.set_shader_parameter("exposure",       pp_exposure)
	_post_mat.set_shader_parameter("tonemap_knee",   pp_tonemap_knee)
	_post_mat.set_shader_parameter("gamma",          pp_gamma)
	_post_mat.set_shader_parameter("vignette_dark",  pp_vignette_dark)
	_post_mat.set_shader_parameter("grain_strength", pp_grain_strength)


# ── Per-shader post-processing config ──────────────────────────────

func _apply_pp_config(idx: int) -> void:
	var cfg := _shader_pp_configs[idx]
	pp_exposure       = cfg.get("exposure", PP_DEFAULTS["exposure"])
	pp_tonemap_knee   = cfg.get("tonemap_knee", PP_DEFAULTS["tonemap_knee"])
	pp_gamma          = cfg.get("gamma", PP_DEFAULTS["gamma"])
	pp_vignette_dark  = cfg.get("vignette_dark", PP_DEFAULTS["vignette_dark"])
	pp_grain_strength = cfg.get("grain_strength", PP_DEFAULTS["grain_strength"])
	pp_loop_reinhard  = cfg.get("loop_reinhard", _SHADER_REINHARD_DEFAULTS[idx])


func _save_current_pp_config() -> void:
	_shader_pp_configs[_shader_index] = {
		"exposure":       pp_exposure,
		"tonemap_knee":   pp_tonemap_knee,
		"gamma":          pp_gamma,
		"vignette_dark":  pp_vignette_dark,
		"grain_strength": pp_grain_strength,
		"loop_reinhard":  pp_loop_reinhard,
	}


func update_pp_param(param: String, value: float) -> void:
	match param:
		"exposure":       pp_exposure       = value
		"tonemap_knee":   pp_tonemap_knee   = value
		"gamma":          pp_gamma          = value
		"vignette_dark":  pp_vignette_dark  = value
		"grain_strength": pp_grain_strength = value
		"loop_reinhard":  pp_loop_reinhard  = value
	_shader_pp_configs[_shader_index][param] = value


# ── Settings persistence ────────────────────────────────────────────

func save_settings() -> void:
	_save_current_pp_config()
	# Sync current state into Config
	Config.shader_pp_configs = _shader_pp_configs
	Config.shuffle_on        = _shuffle_on
	Config.shuffle_interval  = shuffle_interval
	Config.post_enabled      = _post_display.visible if is_instance_valid(_post_display) else true
	Config.fullscreen        = (DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_FULLSCREEN)
	Config.shader_index      = _shader_index
	Config.save()
	_ui.show_label("Settings saved")
