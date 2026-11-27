extends CanvasLayer
## Combat HUD in Ukrainian: the Cossack's health and stamina, bars over engaged
## enemies, short combat messages (parry, execution) and a controls hint.

const INK := Color("e8d9ae")
const INK_DIM := Color("c5b994")
const PANEL := Color(0.08, 0.06, 0.04, 0.62)
const BLOOD := Color("a3261f")
const GOLD := Color("d6a84a")
const ENEMY_BAR_WIDTH := 110.0

var _player: Node3D
var _combat: PlayerCombat
var _health_bar: ProgressBar
var _stamina_bar: ProgressBar
var _message: Label
var _message_tween: Tween
var _enemy_layer: Control
var _enemy_widgets: Dictionary = {}


func _ready() -> void:
	_build()
	await get_tree().process_frame
	_player = get_tree().get_first_node_in_group(&"player") as Node3D
	if _player == null:
		return
	_combat = _player.get_node_or_null("Combat") as PlayerCombat
	if _combat == null:
		return
	_combat.health.changed.connect(func(c: float, m: float) -> void: _set_bar(_health_bar, c, m))
	_combat.stamina_changed.connect(func(c: float, m: float) -> void: _set_bar(_stamina_bar, c, m))
	_combat.announce.connect(_show_message)
	_set_bar(_health_bar, _combat.health.current, _combat.health.max_health)
	_set_bar(_stamina_bar, _combat.stamina, _combat.max_stamina)


func _process(_delta: float) -> void:
	_update_enemy_bars()


func _build() -> void:
	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(root)

	_enemy_layer = Control.new()
	_enemy_layer.set_anchors_preset(Control.PRESET_FULL_RECT)
	_enemy_layer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(_enemy_layer)

	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", _panel_style())
	panel.anchor_top = 1.0
	panel.anchor_bottom = 1.0
	panel.offset_left = 24.0
	panel.offset_top = -112.0
	panel.offset_right = 344.0
	panel.offset_bottom = -24.0
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(panel)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	panel.add_child(column)
	_health_bar = _labelled_bar(column, "Здоров'я", BLOOD, 14.0)
	_stamina_bar = _labelled_bar(column, "Витривалість", GOLD, 9.0)

	var hint := Label.new()
	hint.text = "ЛКМ — удар (серія до трьох)   ПКМ — захист, вчасно — парирування"
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", INK_DIM)
	hint.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.7))
	hint.add_theme_constant_override("shadow_offset_y", 1)
	hint.anchor_left = 1.0
	hint.anchor_right = 1.0
	hint.anchor_top = 1.0
	hint.anchor_bottom = 1.0
	hint.offset_left = -560.0
	hint.offset_right = -24.0
	hint.offset_top = -48.0
	hint.offset_bottom = -24.0
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	root.add_child(hint)

	_message = Label.new()
	_message.add_theme_font_size_override("font_size", 40)
	_message.add_theme_color_override("font_color", INK)
	_message.add_theme_color_override("font_outline_color", Color(0.1, 0.05, 0.02, 0.9))
	_message.add_theme_constant_override("outline_size", 8)
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.anchor_left = 0.0
	_message.anchor_right = 1.0
	_message.anchor_top = 0.28
	_message.anchor_bottom = 0.28
	_message.offset_top = -30.0
	_message.offset_bottom = 30.0
	_message.modulate.a = 0.0
	root.add_child(_message)


func _labelled_bar(parent: Control, caption: String, color: Color, height: float) -> ProgressBar:
	var label := Label.new()
	label.text = caption
	label.add_theme_font_size_override("font_size", 14)
	label.add_theme_color_override("font_color", INK)
	parent.add_child(label)
	var bar := _bar(color, height)
	parent.add_child(bar)
	return bar


func _bar(color: Color, height: float) -> ProgressBar:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(0.0, height)
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var back := StyleBoxFlat.new()
	back.bg_color = Color(0.0, 0.0, 0.0, 0.55)
	back.border_color = Color(INK, 0.35)
	back.set_border_width_all(1)
	back.set_corner_radius_all(2)
	var fill := StyleBoxFlat.new()
	fill.bg_color = color
	fill.set_corner_radius_all(2)
	bar.add_theme_stylebox_override("background", back)
	bar.add_theme_stylebox_override("fill", fill)
	bar.max_value = 1.0
	bar.value = 1.0
	return bar


func _panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = PANEL
	style.border_color = Color(INK, 0.25)
	style.set_border_width_all(1)
	style.set_corner_radius_all(4)
	style.content_margin_left = 14.0
	style.content_margin_right = 14.0
	style.content_margin_top = 8.0
	style.content_margin_bottom = 10.0
	return style


func _set_bar(bar: ProgressBar, current: float, maximum: float) -> void:
	var target := current / maximum if maximum > 0.0 else 0.0
	var tween := bar.create_tween()
	tween.tween_property(bar, "value", target, 0.15)


func _show_message(text: String) -> void:
	_message.text = text
	if _message_tween != null:
		_message_tween.kill()
	_message.modulate.a = 1.0
	_message.scale = Vector2.ONE
	_message_tween = create_tween()
	_message_tween.tween_interval(0.9)
	_message_tween.tween_property(_message, "modulate:a", 0.0, 0.6)


func _update_enemy_bars() -> void:
	var camera := get_viewport().get_camera_3d()
	var seen: Dictionary = {}
	if camera != null:
		for node in get_tree().get_nodes_in_group(&"enemy"):
			var enemy := node as EnemySabreFighter
			if enemy == null or not enemy.is_alive() or not enemy.is_engaged():
				continue
			var head := enemy.global_position + Vector3.UP * 2.15
			if camera.is_position_behind(head) or camera.global_position.distance_to(head) > 30.0:
				continue
			var widget: Control = _enemy_widgets.get(enemy)
			if widget == null:
				widget = _make_enemy_widget(enemy)
				_enemy_widgets[enemy] = widget
			var screen := camera.unproject_position(head)
			widget.position = screen - Vector2(ENEMY_BAR_WIDTH * 0.5, 26.0)
			var bar := widget.get_node("Bar") as ProgressBar
			bar.value = enemy.health.ratio()
			var staggered := enemy.is_staggered()
			(widget.get_node("Name") as Label).add_theme_color_override(
				"font_color", GOLD if staggered else INK
			)
			widget.show()
			seen[enemy] = true
	for enemy in _enemy_widgets.keys():
		if not seen.has(enemy):
			var widget: Control = _enemy_widgets[enemy]
			if not is_instance_valid(enemy):
				widget.queue_free()
				_enemy_widgets.erase(enemy)
			else:
				widget.hide()


func _make_enemy_widget(enemy: EnemySabreFighter) -> Control:
	var box := Control.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.size = Vector2(ENEMY_BAR_WIDTH, 30.0)
	var name_label := Label.new()
	name_label.name = "Name"
	name_label.text = enemy.display_name
	name_label.add_theme_font_size_override("font_size", 13)
	name_label.add_theme_color_override("font_color", INK)
	name_label.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	name_label.add_theme_constant_override("shadow_offset_y", 1)
	name_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_label.size = Vector2(ENEMY_BAR_WIDTH, 16.0)
	box.add_child(name_label)
	var bar := _bar(BLOOD, 6.0)
	bar.name = "Bar"
	bar.position = Vector2(0.0, 18.0)
	bar.size = Vector2(ENEMY_BAR_WIDTH, 6.0)
	box.add_child(bar)
	_enemy_layer.add_child(box)
	return box
