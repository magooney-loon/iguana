extends Node

## Centralized config manager for Iguana.
## All persistent settings are saved to / loaded from a single ConfigFile.
## Other nodes call Config.get_* / Config.set_* and Config.save().
##
## Per-shader settings use the shader's filename stem (e.g. "solstice")
## as the key, NOT the array index.  This keeps settings stable when
## new shaders are added and the discovery order changes.

const SETTINGS_PATH := "user://iguana_settings.cfg"

# ── Cached values (populated on load, written back on save) ──────────────────

# General
var shuffle_on        := false
var shuffle_interval  := 45.0
var post_enabled      := true
var fullscreen        := false
var shader_index      := 0
var shader_name       := ""        # filename stem of the selected shader
var play_mode         := 1  # Playlist.PlayMode.LOOP_ALL
var volume            := 1.0  # 0.0 – 1.0
var crossfade_duration  := 2.0  # seconds
var auto_hide_player   := false
var vsync_enabled      := true
var max_fps            := 60
var theme_name         := "aero_blue"
var skin_name          := "aero"

# Per-shader post-processing: Dictionary keyed by filename stem
# e.g. { "solstice": { "exposure": 1.4, ... }, "mars": { ... } }
# Populated externally by visualizer.gd (it owns the shader configs).
var shader_pp_configs: Dictionary = {}

# Ordered list of shader keys (filename stems), set by visualizer.gd at startup.
# Needed so we can write configs in order and resolve names to indices.
var shader_keys: Array[String] = []

# Default PP values (mirrored from visualizer.gd for standalone access)
const PP_DEFAULTS := {
	"exposure":       1.42,
	"tonemap_knee":   0.0,
	"gamma":          2.0,
	"vignette_dark":  0.30,
	"grain_strength": 0.01,
	"loop_reinhard":  0.0,
}


# ── Public API ────────────────────────────────────────────────────────────────

func save() -> void:
	var cfg := ConfigFile.new()

	# General
	cfg.set_value("general", "shuffle_on", shuffle_on)
	cfg.set_value("general", "shuffle_interval", shuffle_interval)
	cfg.set_value("general", "post_enabled", post_enabled)
	cfg.set_value("general", "fullscreen", fullscreen)
	cfg.set_value("general", "shader_name", shader_name)
	cfg.set_value("general", "play_mode", play_mode)
	cfg.set_value("general", "volume", volume)
	cfg.set_value("general", "crossfade_duration", crossfade_duration)
	cfg.set_value("general", "auto_hide_player",  auto_hide_player)
	cfg.set_value("general", "vsync_enabled", vsync_enabled)
	cfg.set_value("general", "max_fps", max_fps)
	cfg.set_value("general", "theme_name", theme_name)
	cfg.set_value("general", "skin_name", skin_name)

	# Per-shader PP configs — keyed by filename stem
	for key in shader_pp_configs:
		var section := "shader_%s" % key
		for pp_key in shader_pp_configs[key]:
			cfg.set_value(section, pp_key, shader_pp_configs[key][pp_key])

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
	if cfg.has_section_key("general", "shader_name"):
		shader_name = cfg.get_value("general", "shader_name")
	elif cfg.has_section_key("general", "shader_index"):
		# Migration: old config stored a numeric index.
		# We can't perfectly resolve it (shader order may have changed),
		# but clamp it to a valid range so it doesn't crash.
		var old_index: int = cfg.get_value("general", "shader_index")
		if old_index >= 0 and old_index < shader_keys.size():
			shader_name = shader_keys[old_index]
		elif shader_keys.size() > 0:
			shader_name = shader_keys[0]
	if cfg.has_section_key("general", "play_mode"):
		play_mode = cfg.get_value("general", "play_mode")
	if cfg.has_section_key("general", "volume"):
		volume = cfg.get_value("general", "volume")
	if cfg.has_section_key("general", "crossfade_duration"):
		crossfade_duration = cfg.get_value("general", "crossfade_duration")
	if cfg.has_section_key("general", "auto_hide_player"):
		auto_hide_player = cfg.get_value("general", "auto_hide_player")
	if cfg.has_section_key("general", "vsync_enabled"):
		vsync_enabled = cfg.get_value("general", "vsync_enabled")
	if cfg.has_section_key("general", "max_fps"):
		max_fps = cfg.get_value("general", "max_fps")
	if cfg.has_section_key("general", "theme_name"):
		theme_name = cfg.get_value("general", "theme_name")
	if cfg.has_section_key("general", "skin_name"):
		skin_name = cfg.get_value("general", "skin_name")

	# Resolve shader_name → shader_index
	shader_index = 0  # default
	if shader_name != "" and shader_name in shader_keys:
		shader_index = shader_keys.find(shader_name)

	# Per-shader PP configs — merge saved values into the defaults
	# that visualizer.gd already populated.
	for key in shader_pp_configs:
		var section := "shader_%s" % key
		if not cfg.has_section(section):
			continue
		for pp_key in PP_DEFAULTS:
			if cfg.has_section_key(section, pp_key):
				shader_pp_configs[key][pp_key] = cfg.get_value(section, pp_key)
