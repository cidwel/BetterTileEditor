@tool
extends RefCounted

signal active_changed

var editor: Control
var native_content: Control
var native_tabs: TabBar
var tabs: TabBar
var container: VBoxContainer
var panel: Control
var _native_tabs_panel: Control
var _tabs_were_visible := true
var _content_index := 0
var _floating_notice: Label
var _tabs_frame: PanelContainer
var _bar_was_visible := true
var _native_vertical_flags: int

func install(base: Control, terrain_panel: Control) -> bool:
	# Match native TileMap tabs by signal owner; translated labels and node paths are unstable.
	for candidate in base.find_children("*", "TileMapLayerEditor", true, false):
		for bar in candidate.find_children("*", "TabBar", true, false):
			for connection in bar.get_signal_connection_list("tab_changed"):
				var callback: Callable = connection.callable
				if callback.get_object() == candidate and String(callback.get_method()).ends_with("_tab_changed"):
					editor = candidate
					native_tabs = bar
	if editor == null or native_tabs == null or not editor.has_method("make_visible"):
		return false
	native_content = native_tabs
	while native_content.get_parent() != editor:
		native_content = native_content.get_parent()
	_content_index = native_content.get_index()
	_native_tabs_panel = native_tabs.get_parent()
	_tabs_were_visible = _native_tabs_panel.visible
	_bar_was_visible = native_tabs.visible
	_native_vertical_flags = native_content.size_flags_vertical
	container = VBoxContainer.new()
	container.name = "BetterTileEditorTileMap"
	container.theme = EditorInterface.get_editor_theme()
	container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	editor.add_child(container)
	tabs = TabBar.new()
	tabs.name = "TileMapModes"
	tabs.theme = EditorInterface.get_editor_theme()
	tabs.theme_type_variation = native_tabs.theme_type_variation
	tabs.clip_tabs = native_tabs.clip_tabs
	for i in native_tabs.tab_count:
		tabs.add_tab(native_tabs.get_tab_title(i), native_tabs.get_tab_icon(i))
	tabs.add_tab("Better Tile Editor")
	tabs.current_tab = native_tabs.current_tab
	_tabs_frame = PanelContainer.new()
	_tabs_frame.theme_type_variation = _native_tabs_panel.theme_type_variation
	_tabs_frame.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	container.add_child(_tabs_frame)
	_tabs_frame.add_child(tabs)
	native_content.reparent(container)
	native_content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	native_tabs.hide()
	_floating_notice = Label.new()
	_floating_notice.text = "Better Tile Editor is open in a separate window."
	container.add_child(_floating_notice)
	panel = terrain_panel
	attach_panel()
	tabs.tab_changed.connect(_select_tab)
	native_tabs.tab_changed.connect(_native_tab_changed)
	container.visibility_changed.connect(_visibility_changed)
	_select_tab(tabs.current_tab)
	return true

func is_active() -> bool:
	return tabs != null and tabs.current_tab == native_tabs.tab_count

func attach_panel() -> void:
	if panel.get_parent() == null:
		container.add_child(panel)
	else:
		panel.reparent(container)
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_select_tab(tabs.current_tab)

func select_terrain() -> void:
	tabs.current_tab = native_tabs.tab_count
	_select_tab(tabs.current_tab)
	editor.call("make_visible")

func refresh() -> void:
	_select_tab(tabs.current_tab)

func apply_options(hidden_tabs: Array, rename_tab: bool) -> void:
	for index in hidden_tabs.size():
		if hidden_tabs[index] and tabs.current_tab == index:
			select_terrain()
		tabs.set_tab_hidden(index, hidden_tabs[index])
	tabs.set_tab_title(native_tabs.tab_count, "Tiles" if rename_tab else "Better Tile Editor")
	# The bottom panel's "TileMap" tab too; its editor is an EditorDock from Godot 4.7, whose
	# title names the tab, and an empty one gives the default back.
	if "title" in editor:
		editor.set("title", "Tiles" if rename_tab else "")

func _select_tab(index: int) -> void:
	var own := index == native_tabs.tab_count
	var frame_parent: Control = panel.get_node("VBox/Toolbar") if own and panel.get_parent() == container else container
	if _tabs_frame.get_parent() != frame_parent:
		_tabs_frame.reparent(frame_parent)
		frame_parent.move_child(_tabs_frame, 0)
	# Hiding this ancestor also disables native TileMap painting and brush prefiews.
	var tab_parent: Control = _tabs_frame if own else _native_tabs_panel
	if tabs.get_parent() != tab_parent:
		tabs.reparent(tab_parent)
	_tabs_frame.visible = own
	_native_tabs_panel.show()
	native_content.visible = not own
	if not own:
		panel.terrain_undo.finish_action()
		panel.paint_mode = panel.PaintMode.NO_PAINT
		native_tabs.current_tab = index
	if panel.get_parent() == container:
		panel.visible = own
	_floating_notice.visible = own and panel.get_parent() != container
	if own:
		panel.about_to_be_visible(true)
	active_changed.emit()

func _native_tab_changed(index: int) -> void:
	if not is_active():
		if tabs.is_tab_hidden(index):
			select_terrain()
			return
		tabs.set_block_signals(true)
		tabs.current_tab = index
		tabs.set_block_signals(false)

func _visibility_changed() -> void:
	if panel.get_parent() == container and panel.is_visible_in_tree():
		panel.about_to_be_visible(true)
	active_changed.emit()

func uninstall() -> void:
	if editor != null and "title" in editor:
		editor.set("title", "")
	container.visibility_changed.disconnect(_visibility_changed)
	native_tabs.tab_changed.disconnect(_native_tab_changed)
	if _tabs_frame.get_parent() != container:
		_tabs_frame.reparent(container)
	if panel.get_parent() == container:
		container.remove_child(panel)
	tabs.get_parent().remove_child(tabs)
	tabs.queue_free()
	native_tabs.visible = _bar_was_visible
	native_content.size_flags_vertical = _native_vertical_flags
	native_content.reparent(editor)
	editor.move_child(native_content, _content_index)
	native_content.show()
	_native_tabs_panel.visible = _tabs_were_visible
	container.queue_free()
