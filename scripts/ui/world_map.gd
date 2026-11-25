extends CanvasLayer

const WORLD_LEFT := -100.0
const WORLD_RIGHT := 100.0
const WORLD_NORTH := -155.0
const WORLD_SOUTH := 35.0

var _screen: Control
var _map_container: SubViewportContainer
var _map_viewport: SubViewport
var _map_camera: Camera3D
var _marker: Label
var _player: Node3D
var _previous_mouse_mode: Input.MouseMode


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_player = get_parent().get_node("Player") as Node3D
	_build_interface()
	_screen.hide()
	_map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED


func _input(event: InputEvent) -> void:
	if event.is_action_pressed(&"world_map"):
		if not _screen.visible and get_tree().paused:
			return
		_set_open(not _screen.visible)
		get_viewport().set_input_as_handled()
	elif _screen.visible and event.is_action_pressed(&"ui_cancel"):
		_set_open(false)
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if _screen.visible:
		_update_marker()


func _set_open(open: bool) -> void:
	if open:
		_previous_mouse_mode = Input.mouse_mode
		_map_viewport.world_3d = get_viewport().world_3d
	_screen.visible = open
	_map_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS if open else SubViewport.UPDATE_DISABLED
	get_tree().paused = open
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE if open else _previous_mouse_mode
	if open:
		_update_marker()


func _build_interface() -> void:
	_screen = Control.new()
	_screen.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_screen)

	var backdrop := ColorRect.new()
	backdrop.color = Color(0.045, 0.043, 0.033, 0.96)
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_screen.add_child(backdrop)

	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	_screen.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 8)
	margin.add_child(column)

	var header := HBoxContainer.new()
	column.add_child(header)
	var title := Label.new()
	title.text = "МАПА СВІТУ"
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_theme_font_size_override("font_size", 24)
	title.add_theme_color_override("font_color", Color("e8d9ae"))
	header.add_child(title)
	var close_hint := Label.new()
	close_hint.text = "M / ESC  ·  ЗАКРИТИ"
	close_hint.add_theme_font_size_override("font_size", 14)
	close_hint.add_theme_color_override("font_color", Color("c5b994"))
	header.add_child(close_hint)

	var aspect := AspectRatioContainer.new()
	aspect.ratio = 1.0
	aspect.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	aspect.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(aspect)
	var map_area := Control.new()
	aspect.add_child(map_area)

	_map_container = SubViewportContainer.new()
	_map_container.stretch = true
	_map_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_map_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	map_area.add_child(_map_container)
	_map_viewport = SubViewport.new()
	_map_viewport.handle_input_locally = false
	_map_viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	_map_container.add_child(_map_viewport)

	_map_camera = Camera3D.new()
	_map_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_map_camera.size = maxf(WORLD_RIGHT - WORLD_LEFT, WORLD_SOUTH - WORLD_NORTH) + 10.0
	_map_camera.position = Vector3((WORLD_LEFT + WORLD_RIGHT) * 0.5, 250.0, (WORLD_NORTH + WORLD_SOUTH) * 0.5)
	_map_camera.rotation_degrees = Vector3(-90.0, 0.0, 0.0)
	_map_camera.far = 500.0
	var map_environment := Environment.new()
	map_environment.background_mode = Environment.BG_COLOR
	map_environment.background_color = Color("393a29")
	map_environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	map_environment.ambient_light_color = Color("d8d2b3")
	map_environment.ambient_light_energy = 0.8
	_map_camera.environment = map_environment
	_map_viewport.add_child(_map_camera)
	_map_camera.current = true

	_marker = Label.new()
	_marker.text = "◆"
	_marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_marker.add_theme_font_size_override("font_size", 24)
	_marker.add_theme_color_override("font_color", Color("fff1c0"))
	_marker.add_theme_color_override("font_outline_color", Color("3a2115"))
	_marker.add_theme_constant_override("outline_size", 4)
	map_area.add_child(_marker)

	var footer := Label.new()
	footer.text = "◆  ВИ ТУТ                                         ПН ↑"
	footer.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	footer.add_theme_font_size_override("font_size", 14)
	footer.add_theme_color_override("font_color", Color("d7c9a1"))
	column.add_child(footer)


func _update_marker() -> void:
	if _map_viewport.size.x <= 0 or _map_viewport.size.y <= 0:
		return
	var map_position := _map_camera.unproject_position(_player.global_position)
	_marker.position = map_position - _marker.size * 0.5
	_marker.visible = Rect2(Vector2.ZERO, _map_container.size).has_point(map_position)
