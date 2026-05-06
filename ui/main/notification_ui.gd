class_name NotificationUI
extends Control

## Minimal overlay: just the shader-name label that fades out after switching.
## All shader selection and debug display live in the settings window (player_ui.gd).

var _label: Label
var _label_timer := 0.0


func setup(_analyzer: AudioAnalyzer, _shaders: Array, _visualizer: ColorRect) -> void:
	pass


func _ready() -> void:
	set_anchors_preset(PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_label = Label.new()
	_label.add_theme_font_size_override("font_size", StylesUI.theme().font_notification)
	_label.position = StylesUI.theme().notify_offset
	_label.add_theme_color_override("font_shadow_color", StylesUI.theme().c_notify_shadow)
	_label.add_theme_constant_override("shadow_offset_x", 1)
	_label.add_theme_constant_override("shadow_offset_y", 1)
	_label.hide()
	add_child(_label)


func show_label(text: String) -> void:
	_label.text = text
	_label.modulate.a = 1.0
	_label.show()
	_label_timer = 2.0


func on_shader_changed(_index: int) -> void:
	pass


func process_ui(delta: float) -> void:
	if _label_timer > 0.0:
		_label_timer -= delta
		_label.modulate.a = clampf(_label_timer, 0.0, 1.0)
		if _label_timer <= 0.0:
			_label.hide()
