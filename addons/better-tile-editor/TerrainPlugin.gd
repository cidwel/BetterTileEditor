@tool
extends EditorPlugin

const AUTOLOAD_NAME = "BetterTerrain"
const AUTOLOAD_SCRIPT = "res://addons/better-tile-editor/BetterTerrain.gd"

const AUTO_OPEN_SETTING := "editors/better_terrain/open_panel_on_select"
var _support_editor: Node
var dock : Control
var button : Button
var floating_window : Window
var dock_in_floating := false
var was_visible := false
var _picker_cursor_on := false

var _integration: RefCounted
var _integration_attempted := false
const TileMapIntegration := preload("res://addons/better-tile-editor/editor/TileMapIntegration.gd")

func _enter_tree() -> void:
	# Wait for autoloads to register
	await get_tree().process_frame

	if !_autoload_is_loaded():
		# Autoload wasn't present on plugin init, which means plugin won't have loaded correctly
		add_autoload_singleton(AUTOLOAD_NAME, "res://addons/better-tile-editor/BetterTerrain.gd")
		ProjectSettings.save()

		var confirm = ConfirmationDialog.new()
		confirm.dialog_text = "The editor needs to be restarted for BetterTileEditor to load correctly. Restart now? Note: Unsaved changes will be lost."
		confirm.confirmed.connect(func():
			OS.set_restart_on_exit(true, ["-e"])
			get_tree().quit()
		)
		get_editor_interface().popup_dialog_centered(confirm)

	_support_editor = preload("res://addons/better-tile-editor/editor/SupportLayerEditor.gd").new()
	add_child(_support_editor)
	scene_changed.connect(_support_editor.prepare_scene)
	_support_editor.prepare_scene(EditorInterface.get_edited_scene_root())
	dock = load("res://addons/better-tile-editor/editor/Dock.tscn").instantiate()
	dock.update_overlay.connect(self.update_overlays)
	get_editor_interface().get_editor_main_screen().mouse_exited.connect(dock.canvas_mouse_exit)
	dock.undo_manager = get_undo_redo()
	dock.force_show_terrains.connect(_show_terrain_panel)
	dock.make_floating_toggled.connect(_on_make_floating_toggled)
	dock.options_changed.connect(_apply_options)
	dock.tileset_created.connect(_on_tileset_created)
	_try_integrate()
	if button != null:
		button.hide()
	_resume_selection.call_deferred()


# After a reload, _edit may come before the dock exists or not at all
func _resume_selection() -> void:
	var edited := EditorInterface.get_inspector().get_edited_object()
	if edited == null or not _handles(edited):
		return
	_edit(edited)
	_make_visible(true)


func _try_integrate() -> void:
	if dock == null or _integration_attempted or dock_in_floating:
		return
	_integration_attempted = true
	for connection in dock.force_show_terrains.get_connections():
		if connection.callable != _show_terrain_panel:
			dock.force_show_terrains.disconnect(connection.callable)
	if not dock.force_show_terrains.is_connected(_show_terrain_panel):
		dock.force_show_terrains.connect(_show_terrain_panel)
	if button != null:
		remove_control_from_bottom_panel(dock)
		button = null
	var integration := TileMapIntegration.new()
	if integration.install(EditorInterface.get_base_control(), dock):
		_integration = integration
		_integration.active_changed.connect(update_overlays)
		_apply_options()
	else:
		_add_bottom_panel()


# Godot 4.7 editor autoloads may be unnamed; match the script as a fallback.
func _autoload_is_loaded() -> bool:
	if get_tree().root.get_node_or_null(NodePath(AUTOLOAD_NAME)):
		return true

	for child in get_tree().root.get_children():
		var script := child.get_script()
		if script and script.resource_path == AUTOLOAD_SCRIPT:
			return true

	return false


func _exit_tree() -> void:
	_set_picker_cursor(false)
	_support_editor.queue_free()
	dock.tilemap = null
	dock._watch_layer_order()
	if button != null:
		remove_control_from_bottom_panel(dock)
	if _integration != null:
		_integration.uninstall()
	if is_instance_valid(floating_window):
		floating_window.remove_child(dock)
		floating_window.queue_free()
	dock.queue_free()


func _handles(object) -> bool:
	# TileMap is only handled to say it isn't supported.
	return object is TileMapLayer or object is TileSet or object is TileMap


func _make_visible(visible) -> void:
	was_visible = visible
	if dock == null or dock_in_floating:
		return
	if button != null:
		button.visible = visible
	if visible and dock.tilemap and _auto_open_enabled():
		_show_terrain_panel.call_deferred()


func _add_bottom_panel() -> void:
	button = add_control_to_bottom_panel(dock, "BetterTileEditor")
	button.toggled.connect(dock.about_to_be_visible)
	_apply_options()


func _apply_options() -> void:
	var settings := EditorInterface.get_editor_settings()
	_support_editor.hide_layers = settings.has_setting(dock.HIDE_SUPPORT_SETTING) and bool(settings.get_setting(dock.HIDE_SUPPORT_SETTING))
	_support_editor.refresh()
	var hide_native := settings.has_setting(dock.HIDE_NATIVE_TERRAINS_SETTING) and bool(settings.get_setting(dock.HIDE_NATIVE_TERRAINS_SETTING))
	var hide_tiles := settings.has_setting(dock.HIDE_NATIVE_TILES_SETTING) and bool(settings.get_setting(dock.HIDE_NATIVE_TILES_SETTING))
	var hide_patterns := settings.has_setting(dock.HIDE_NATIVE_PATTERNS_SETTING) and bool(settings.get_setting(dock.HIDE_NATIVE_PATTERNS_SETTING))
	var rename_tab := settings.has_setting(dock.RENAME_TAB_SETTING) and bool(settings.get_setting(dock.RENAME_TAB_SETTING))
	if _integration != null:
		_integration.apply_options([hide_tiles, hide_patterns, hide_native], rename_tab)
	if button != null:
		button.text = "Tiles" if rename_tab else "BetterTileEditor"


func _mount_panel() -> void:
	if _integration == null or dock_in_floating:
		return
	if dock.tilemap != null:
		if button != null:
			remove_control_from_bottom_panel(dock)
			button = null
		_integration.attach_panel()
	elif button == null:
		dock.get_parent().remove_child(dock)
		_add_bottom_panel()
		_integration.refresh()


func _show_terrain_panel() -> void:
	if dock_in_floating:
		floating_window.grab_focus()
	elif _integration != null and dock.tilemap != null:
		_integration.select_terrain()
	else:
		make_bottom_panel_item_visible(dock)


func _canvas_active() -> bool:
	if _integration != null and dock.tilemap != null:
		return _integration.is_active() and (dock_in_floating or dock.is_visible_in_tree())
	return dock_in_floating or dock.is_visible_in_tree()


func _auto_open_enabled() -> bool:
	var settings := EditorInterface.get_editor_settings()
	if !settings.has_setting(AUTO_OPEN_SETTING):
		settings.set_setting(AUTO_OPEN_SETTING, true)
		settings.set_initial_value(AUTO_OPEN_SETTING, true, false)
	return bool(settings.get_setting(AUTO_OPEN_SETTING))


func _edit(object) -> void:
	if dock == null:
		return
	_try_integrate()
	var new_tileset : TileSet = null

	dock.show_unsupported(object as TileMap)
	dock.show_missing_tileset(object as TileMapLayer)
	if object is TileMap:
		_warn_tilemap_node()
		object = null
	if object is TileMapLayer:
		dock.tilemap = object
		new_tileset = object.tile_set
	if object is TileSet:
		dock.tilemap = null
		new_tileset = object
	dock._watch_layer_order()

	if dock.tileset != new_tileset:
		dock.tiles_about_to_change()
		dock.tileset = new_tileset
		dock.tiles_changed()
	_mount_panel()


# A new TileSet needs an atlas first, and that is added in Godot's own TileSet tab
func _on_tileset_created(layer: TileMapLayer) -> void:
	EditorInterface.edit_node(layer)
	_edit(layer)
	await get_tree().process_frame
	for editor in EditorInterface.get_base_control().find_children("*", "TileSetEditor", true, false):
		var panel := editor.get_parent()
		if panel is TabContainer:
			panel.current_tab = editor.get_index()
		else:
			make_bottom_panel_item_visible(editor)
		break


const TILEMAP_NOT_SUPPORTED := "BetterTileEditor does not support TileMap nodes, only TileMapLayer nodes."


func _warn_tilemap_node() -> void:
	EditorInterface.get_editor_toaster().push_toast(TILEMAP_NOT_SUPPORTED,
		EditorToaster.SEVERITY_WARNING, dock.TILEMAP_CONVERT_HINT)


func _forward_canvas_draw_over_viewport(overlay: Control) -> void:
	if _canvas_active():
		dock.canvas_draw(overlay)


func _process(_delta: float) -> void:
	if dock == null:
		return
	var editing: bool = was_visible and dock.tilemap != null and _canvas_active()
	dock.set_picker_lit(editing and dock.picker_modifier_down())
	var want: bool = editing and _mouse_over_canvas() and dock.picker_armed()
	if want != _picker_cursor_on:
		_set_picker_cursor(want)


func _mouse_over_canvas() -> bool:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return false
	var container := viewport.get_parent() as Control
	return container != null and container.is_visible_in_tree() \
		and container.get_global_rect().has_point(container.get_global_mouse_position())


func _set_picker_cursor(on: bool) -> void:
	if on == _picker_cursor_on:
		return
	_picker_cursor_on = on
	# Input.set_custom_mouse_cursor does nothing in the editor, so go through DisplayServer.
	# A cached image also switch the current shape, so restore it after.
	var shape_now := DisplayServer.cursor_get_shape()
	# The 2D editor picks the shape by tool, so override all of them.
	for shape in DisplayServer.CURSOR_MAX:
		if on:
			DisplayServer.cursor_set_custom_image(dock.picker_cursor(), shape, dock.picker_cursor_hotspot())
		else:
			DisplayServer.cursor_set_custom_image(null, shape)
	DisplayServer.cursor_set_shape(shape_now)


func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if not _canvas_active():
		return false

	return dock.canvas_input(event)


func _input(event: InputEvent) -> void:
	if dock == null:
		return
	if event is InputEventMouseButton and event.pressed:
		dock.note_click(event.global_position)
		return
	if not event is InputEventKey or not event.pressed:
		return
	if event.keycode == KEY_DELETE and not event.echo and not _typing():
		# Delete goes to the terrain or favorite last clicked, not to the scene tree
		var target: String = dock.delete_target()
		if not target.is_empty():
			get_viewport().set_input_as_handled()
			dock.delete_selected(target)
			return
	if not _canvas_active() or dock.tilemap == null or not dock.fill_button.shortcut.matches_event(event):
		return
	var focus := get_viewport().gui_get_focus_owner()
	var in_context := false
	while focus != null:
		if focus is LineEdit or focus is TextEdit:
			return
		if focus == dock or focus.is_class("CanvasItemEditor"):
			in_context = true
		focus = focus.get_parent_control()
	if not in_context:
		return
	# Consume B before the native Scene Paint shortcut receives it.
	get_viewport().set_input_as_handled()
	if not event.echo:
		_leave_scene_paint_mode()
		dock.cancel_paint()
		dock.fill_button.button_pressed = true


func _typing() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return focus is LineEdit or focus is TextEdit


func _leave_scene_paint_mode() -> void:
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_shortcut("canvas_item_editor/scene_paint_mode"):
		return
	var paint_shortcut := settings.get_shortcut("canvas_item_editor/scene_paint_mode")
	var select_shortcut := settings.get_shortcut("canvas_item_editor/select_mode")
	var paint_button: Button
	var select_button: Button
	for control in EditorInterface.get_editor_main_screen().find_children("*", "Button", true, false):
		if control.shortcut == paint_shortcut:
			paint_button = control
		elif control.shortcut == select_shortcut:
			select_button = control
	if paint_button != null and paint_button.button_pressed and select_button != null:
		select_button.pressed.emit()


func _on_make_floating_toggled(pressed: bool) -> void:
	if pressed:
		_dock_to_floating_window()
	else:
		_dock_back_to_bottom_panel(true)


func _dock_to_floating_window() -> void:
	if dock_in_floating:
		return
	dock_in_floating = true

	if button != null:
		remove_control_from_bottom_panel(dock)
		button = null
	elif dock.get_parent() != null:
		dock.get_parent().remove_child(dock)

	floating_window = Window.new()
	floating_window.title = "BetterTileEditor"
	floating_window.size = Vector2i(1100, 700)
	floating_window.min_size = Vector2i(600, 400)
	floating_window.wrap_controls = true
	floating_window.close_requested.connect(_on_floating_window_close_requested)

	floating_window.add_child(dock)
	dock.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	get_editor_interface().get_base_control().add_child(floating_window)
	floating_window.popup_centered()
	dock.show()
	dock.about_to_be_visible(true)
	if _integration != null:
		_integration.refresh()


func _dock_back_to_bottom_panel(restore_pressed: bool) -> void:
	if not dock_in_floating:
		return
	dock_in_floating = false

	if is_instance_valid(floating_window):
		if dock.get_parent() == floating_window:
			floating_window.remove_child(dock)
		floating_window.queue_free()
		floating_window = null

	if _integration != null and dock.tilemap != null:
		_integration.attach_panel()
		_integration.select_terrain()
	else:
		_add_bottom_panel()
		button.visible = was_visible

	if restore_pressed:
		dock.set_make_floating_pressed(false)


func _on_floating_window_close_requested() -> void:
	_dock_back_to_bottom_panel(true)
