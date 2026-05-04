extends ColorRect

const SHADERS := [
	{ "path": "res://shaders/cosmic_abyss.gdshader", "name": "Cosmic Abyss" },
	{ "path": "res://shaders/starfall.gdshader", "name": "Starfall" },
	{ "path": "res://shaders/afterimage.gdshader", "name": "Afterimage" },
	{ "path": "res://shaders/glitch_garden.gdshader", "name": "Glitch Garden" },
	{ "path": "res://shaders/signal_scope.gdshader", "name": "Signal Scope" },
]

var _analyzer: AudioAnalyzer
var _loaded_shaders: Array[Shader] = []
var _shader_index   := 0

# Auto-shuffle
const SHUFFLE_INTERVAL := 45.0
var _shuffle_timer := 0.0
var _shuffle_on    := false

# UI overlay (context menu, debug HUD, label)
var _ui: VisualizerUI

# Build a NoiseTexture2D for shaders that sample a noise channel
var _noise_tex: NoiseTexture2D


func _ready() -> void:
	_analyzer = AudioAnalyzer.new()
	_analyzer.setup(
		AudioServer.get_bus_effect_instance(0, 0),
		owner.get_node("Player") as AudioStreamPlayer,
	)

	for def in SHADERS:
		_loaded_shaders.append(load(def.path))

	# Start with the first shader
	material = ShaderMaterial.new()
	(material as ShaderMaterial).shader = _loaded_shaders[0]

	# Build UI overlay (label, context menu, debug HUD)
	_ui = VisualizerUI.new()
	_ui.setup(_analyzer, SHADERS)
	add_child(_ui)

	# Build a NoiseTexture2D for shaders that sample a noise channel
	var fnoise := FastNoiseLite.new()
	fnoise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	fnoise.frequency = 0.04
	fnoise.fractal_octaves = 4
	_noise_tex = NoiseTexture2D.new()
	_noise_tex.width = 512
	_noise_tex.height = 512
	_noise_tex.noise = fnoise
	_noise_tex.seamless = true


# ── Input and shader switching ─────────────────────────────────────

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey and event.pressed):
		return
	match (event as InputEventKey).keycode:
		KEY_E: _switch((_shader_index + 1) % _loaded_shaders.size())
		KEY_Q: _switch((_shader_index - 1 + _loaded_shaders.size()) % _loaded_shaders.size())
		KEY_S: _toggle_shuffle()


func _switch(idx: int) -> void:
	_shader_index  = idx
	_shuffle_timer = 0.0
	(material as ShaderMaterial).shader = _loaded_shaders[idx]
	_ui.on_shader_changed(idx)
	_ui.show_label("< %s >" % SHADERS[idx].name)


func _toggle_shuffle() -> void:
	_shuffle_on    = !_shuffle_on
	_shuffle_timer = 0.0
	_ui.show_label("Shuffle %s" % ("ON" if _shuffle_on else "OFF"))


func _shuffle() -> void:
	var next := _shader_index
	while next == _shader_index:
		next = randi() % _loaded_shaders.size()
	_switch(next)


# ── Frame loop ─────────────────────────────────────────────────────

func _process(delta: float) -> void:
	_analyzer.process(delta)

	# Shuffle timer (only when audio is active)
	if _analyzer.is_sounding:
		_shuffle_timer += delta
		if _shuffle_on and _shuffle_timer >= SHUFFLE_INTERVAL:
			_shuffle()

	_ui.process_ui(delta)
	_push_uniforms(material as ShaderMaterial)


# ── Shader uniforms ────────────────────────────────────────────────

func _push_uniforms(mat: ShaderMaterial) -> void:
	var a := _analyzer
	mat.set_shader_parameter("rect_size", get_rect().size)
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
	for i in range(a._row_peaks.size()):
		mat.set_shader_parameter("peak_%02d" % i, a._row_peaks[i])
