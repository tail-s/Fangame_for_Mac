## Registers input actions at runtime (keyboard + gamepad).
## Physical keycodes are used so the layout works regardless of the OS input
## source (e.g. the Korean IME on macOS).

const KEYS := {
	"move_left": [KEY_LEFT, KEY_A],
	"move_right": [KEY_RIGHT, KEY_D],
	"move_up": [KEY_UP, KEY_W],
	"move_down": [KEY_DOWN, KEY_S],
	"jump": [KEY_Z, KEY_SPACE],
	"shoot": [KEY_X, KEY_J],
	"dash": [KEY_C, KEY_K, KEY_SHIFT],
	"special": [KEY_V, KEY_L],
	"restart": [KEY_R],
	"pause": [KEY_ESCAPE, KEY_P],
	"confirm": [KEY_ENTER, KEY_KP_ENTER, KEY_Z, KEY_SPACE],
	"cancel": [KEY_ESCAPE, KEY_BACKSPACE],
	"debug": [KEY_F1],
	"debug_unlock": [KEY_F2],
}

const BUTTONS := {
	"move_left": [JOY_BUTTON_DPAD_LEFT],
	"move_right": [JOY_BUTTON_DPAD_RIGHT],
	"move_up": [JOY_BUTTON_DPAD_UP],
	"move_down": [JOY_BUTTON_DPAD_DOWN],
	"jump": [JOY_BUTTON_A],
	"shoot": [JOY_BUTTON_X],
	"dash": [JOY_BUTTON_B, JOY_BUTTON_RIGHT_SHOULDER],
	"special": [JOY_BUTTON_Y],
	"restart": [JOY_BUTTON_BACK],
	"pause": [JOY_BUTTON_START],
	"confirm": [JOY_BUTTON_A],
	"cancel": [JOY_BUTTON_B],
}

const AXES := {
	"move_left": [JOY_AXIS_LEFT_X, -1.0],
	"move_right": [JOY_AXIS_LEFT_X, 1.0],
	"move_up": [JOY_AXIS_LEFT_Y, -1.0],
	"move_down": [JOY_AXIS_LEFT_Y, 1.0],
}


static func register() -> void:
	for action in KEYS:
		if InputMap.has_action(action):
			continue
		InputMap.add_action(action, 0.4)
		for key in KEYS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = key
			InputMap.action_add_event(action, ev)
		for button in BUTTONS.get(action, []):
			var jb := InputEventJoypadButton.new()
			jb.button_index = button
			InputMap.action_add_event(action, jb)
		if AXES.has(action):
			var jm := InputEventJoypadMotion.new()
			jm.axis = AXES[action][0]
			jm.axis_value = AXES[action][1]
			InputMap.action_add_event(action, jm)
