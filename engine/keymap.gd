extends Node

## Read-only keymap — central place for all keyboard shortcuts.
## Other nodes call Keymap.get_key("action_id") to look up bindings.

## All actions:  { id: { "name": display, "key": default_keycode } }
## Order here is the order shown in the Keymap settings tab.
const ACTIONS := {
	"play_pause":      { "name": "Play / Pause",           "key": KEY_SPACE },
	"stop":            { "name": "Stop",                    "key": KEY_ESCAPE },
	"prev_track":      { "name": "Previous Track",          "key": KEY_LEFT },
	"next_track":      { "name": "Next Track",              "key": KEY_RIGHT },
	"prev_shader":     { "name": "Previous Shader",         "key": KEY_Q },
	"next_shader":     { "name": "Next Shader",             "key": KEY_E },
	"toggle_shuffle":  { "name": "Toggle Shader Shuffle",   "key": KEY_S },
	"toggle_postproc": { "name": "Toggle Post-Processing",  "key": KEY_P },
	"fullscreen":      { "name": "Toggle Fullscreen",       "key": KEY_F },
	"toggle_playlist": { "name": "Toggle Playlist",         "key": KEY_L },
	"toggle_settings": { "name": "Toggle Settings",       "key": KEY_COMMA },
	"volume_up":      { "name": "Volume Up",                "key": KEY_UP },
	"volume_down":    { "name": "Volume Down",              "key": KEY_DOWN },
}

## Ordered action ids (for display)
var _order: Array[String] = []


func _ready() -> void:
	for id in ACTIONS:
		_order.append(id)


## Public API ──────────────────────────────────────────────────────────────────

func get_key(action: String) -> int:
	if ACTIONS.has(action):
		return ACTIONS[action]["key"] as int
	return KEY_UNKNOWN


func get_action_name(action: String) -> String:
	if ACTIONS.has(action):
		return ACTIONS[action]["name"]
	return action


func get_all_actions() -> Array[String]:
	return _order


## Convert a keycode to a human-readable label (e.g. KEY_SPACE → "Space")
func key_to_label(keycode: int) -> String:
	match keycode:
		KEY_SPACE:       return "Space"
		KEY_ESCAPE:      return "Esc"
		KEY_ENTER:       return "Enter"
		KEY_TAB:         return "Tab"
		KEY_BACKSPACE:   return "Backspace"
		KEY_DELETE:      return "Delete"
		KEY_INSERT:      return "Insert"
		KEY_HOME:        return "Home"
		KEY_END:         return "End"
		KEY_PAGEUP:      return "PgUp"
		KEY_PAGEDOWN:    return "PgDn"
		KEY_UP:          return "↑"
		KEY_DOWN:        return "↓"
		KEY_LEFT:        return "←"
		KEY_RIGHT:       return "→"
		KEY_F1:          return "F1"
		KEY_F2:          return "F2"
		KEY_F3:          return "F3"
		KEY_F4:          return "F4"
		KEY_F5:          return "F5"
		KEY_F6:          return "F6"
		KEY_F7:          return "F7"
		KEY_F8:          return "F8"
		KEY_F9:          return "F9"
		KEY_F10:         return "F10"
		KEY_F11:         return "F11"
		KEY_F12:         return "F12"
		KEY_SHIFT:       return "Shift"
		KEY_CTRL:        return "Ctrl"
		KEY_ALT:         return "Alt"
		KEY_META:        return "Meta"
		KEY_CAPSLOCK:    return "CapsLk"
		KEY_NUMLOCK:     return "NumLk"
		KEY_SCROLLLOCK:  return "ScrLk"
		KEY_PRINT:       return "PrtSc"
		KEY_PAUSE:       return "Pause"
		KEY_MENU:        return "Menu"
		KEY_UNKNOWN:     return "—"
		KEY_COMMA:       return ","
		KEY_PERIOD:      return "."
		KEY_SLASH:       return "/"
		KEY_BACKSLASH:   return "\\"
		KEY_SEMICOLON:   return ";"
		KEY_APOSTROPHE:  return "'"
		KEY_BRACKETLEFT:  return "["
		KEY_BRACKETRIGHT: return "]"
		KEY_MINUS:       return "-"
		KEY_EQUAL:       return "="
		KEY_QUOTELEFT:   return "`"
	if keycode >= KEY_A and keycode <= KEY_Z:
		return char(keycode).to_upper()
	if keycode >= KEY_0 and keycode <= KEY_9:
		return char(keycode)
	if keycode >= KEY_KP_0 and keycode <= KEY_KP_9:
		return "Num" + char(keycode - KEY_KP_0 + KEY_0)
	if keycode >= KEY_KP_ADD and keycode <= KEY_KP_DIVIDE:
		var kp_names := { KEY_KP_ADD: "Num+", KEY_KP_SUBTRACT: "Num-",
			KEY_KP_MULTIPLY: "Num*", KEY_KP_DIVIDE: "Num/",
			KEY_KP_ENTER: "NumEnter", KEY_KP_PERIOD: "Num." }
		if kp_names.has(keycode):
			return kp_names[keycode]
	return "Key_%d" % keycode
