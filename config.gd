extends Node

## Centralized config manager for Iguana.
## All persistent settings are saved to / loaded from a single ConfigFile.
## Other nodes call Config.get_* / Config.set_* and Config.save().

const SETTINGS_PATH := "user://iguana_settings.cfg"

# ── Cached values (populated on load, written back on save) ──────────────────

# General
var shuffle_on        := false
var shuffle_interval  := 45.0
var post_enabled      := true
var fullscreen        := false
var shader_index      := 0
var play_mode         := 1  # Playlist.PlayMode.LOOP_ALL
var volume            := 1.0  # 0.0 – 1.0
var crossfade_duration := 2.0  # seconds

# Per-shader post-processing: Array of Dictionary
# Populated externally by visualizer.gd (it owns the shader configs).
var shader_pp_configs: Array[Dictionary] = []

# Default PP values (mirrored from visualizer.gd for standalone access)
const PP_DEFAULTS := {
	"exposure":       1.42,
	"tonemap_knee":   0.0,
	"gamma":          2.0,
	"vignette_dark":  0.30,
	"grain_strength": 0.01,
	"loop_reinhard":  0.0,
}
const SHADER_REINHARD_DEFAULTS := [0.9, 1.2, 1.0, 0.69, 0.18]


# ── Public API ────────────────────────────────────────────────────────────────

func save() -> void:
	var cfg := ConfigFile.new()

	# General
	cfg.set_value("general", "shuffle_on", shuffle_on)
	cfg.set_value("general", "shuffle_interval", shuffle_interval)
	cfg.set_value("general", "post_enabled", post_enabled)
	cfg.set_value("general", "fullscreen", fullscreen)
	cfg.set_value("general", "shader_index", shader_index)
	cfg.set_value("general", "play_mode", play_mode)
	cfg.set_value("general", "volume", volume)
	cfg.set_value("general", "crossfade_duration", crossfade_duration)

	# Per-shader PP configs
	for i in shader_pp_configs.size():
		var section := "shader_%d" % i
		for key in shader_pp_configs[i]:
			cfg.set_value(section, key, shader_pp_configs[i][key])

	var err := cfg.save(SETTINGS_PATH)
	if err != OK:
		push_warning("Config: failed to save settings (%d)" % err)


func load_settings() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(SETTINGS_PATH) != OK:
		# No saved file yet — use defaults, nothing to do
		return

	# General
	if cfg.has_section_key("general", "shuffle_on"):
		shuffle_on = cfg.get_value("general", "shuffle_on")
	if cfg.has_section_key("general", "shuffle_interval"):
		shuffle_interval = cfg.get_value("general", "shuffle_interval")
	if cfg.has_section_key("general", "post_enabled"):
		post_enabled = cfg.get_value("general", "post_enabled")
	if cfg.has_section_key("general", "fullscreen"):
		fullscreen = cfg.get_value("general", "fullscreen")
	if cfg.has_section_key("general", "shader_index"):
		shader_index = cfg.get_value("general", "shader_index")
	if cfg.has_section_key("general", "play_mode"):
		play_mode = cfg.get_value("general", "play_mode")
	if cfg.has_section_key("general", "volume"):
		volume = cfg.get_value("general", "volume")
	if cfg.has_section_key("general", "crossfade_duration"):
		crossfade_duration = cfg.get_value("general", "crossfade_duration")

	# Per-shader PP configs — merge into whatever the visualizer initialized
	for i in shader_pp_configs.size():
		var section := "shader_%d" % i
		if not cfg.has_section(section):
			continue
		for key in PP_DEFAULTS:
			if cfg.has_section_key(section, key):
				shader_pp_configs[i][key] = cfg.get_value(section, key)
