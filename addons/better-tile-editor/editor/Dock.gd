@tool
extends Control

signal update_overlay
signal tileset_created(layer: TileMapLayer)
signal force_show_terrains
signal make_floating_toggled(pressed: bool)
signal options_changed

# The maximum individual tiles the overlay will draw before shortcutting the display
# To prevent editor lag when drawing large rectangles or filling large areas
const MAX_CANVAS_RENDER_TILES = 1500
const TERRAIN_PROPERTIES_SCENE := preload("res://addons/better-tile-editor/editor/TerrainProperties.tscn")
const TERRAIN_ENTRY_SCENE := preload("res://addons/better-tile-editor/editor/TerrainEntry.tscn")
const TERRAIN_ENTRY_SCRIPT := preload("res://addons/better-tile-editor/editor/TerrainEntry.gd")
const CLIFF_EDITOR_SCRIPT := preload("res://addons/better-tile-editor/editor/CliffEditor.gd")
const CLIFF_TERRAIN := preload("res://addons/better-tile-editor/CliffTerrain.gd")
const SUPPORT_LAYERS := preload("res://addons/better-tile-editor/SupportLayers.gd")
const SCATTER_TERRAIN := preload("res://addons/better-tile-editor/ScatterTerrain.gd")
const EXEMPLAR_DATA := preload("res://addons/better-tile-editor/ExemplarData.gd")
const OBJECT_BAKE := preload("res://addons/better-tile-editor/ObjectBake.gd")
const OBJECT_OVEN_SCRIPT := preload("res://addons/better-tile-editor/editor/ObjectOven.gd")
const SCATTER_BAG_SCRIPT := preload("res://addons/better-tile-editor/editor/ScatterBag.gd")

var _scatter_bag: PanelContainer = null
const EXEMPLAR_TERRAIN := preload("res://addons/better-tile-editor/ExemplarTerrain.gd")
const EXEMPLAR_EDITOR_SCRIPT := preload("res://addons/better-tile-editor/editor/ExemplarEditor.gd")
const CLIFF_DATA := preload("res://addons/better-tile-editor/CliffData.gd")
const SLOPE_TERRAIN := preload("res://addons/better-tile-editor/SlopeTerrain.gd")
const SLOPE_EDITOR_SCRIPT := preload("res://addons/better-tile-editor/editor/SlopeEditor.gd")
const ICON_DIR := "res://addons/better-tile-editor/icons/"

## Preload the script for constants; the autolofd node cannot supply compile-time values.
const BT_SCRIPT := preload("res://addons/better-tile-editor/BetterTerrain.gd")

const TOOL_MODES := {
	# Selecting copies, pastes and clears peering bits: only terrains with bits use it.
	"select_tiles": [
		BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.CATEGORY,
	],
	"live_test": [
		BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.CATEGORY, BT_SCRIPT.TerrainType.DECORATION,
	],
	"paint_type": [
		BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.CATEGORY, BT_SCRIPT.TerrainType.DECORATION,
		BT_SCRIPT.TerrainType.EXEMPLAR,
	],
	"paint_terrain": [
		BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.CATEGORY, BT_SCRIPT.TerrainType.DECORATION,
	],
	"paint_symmetry": [
		BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.CATEGORY, BT_SCRIPT.TerrainType.DECORATION,
	],
	"object_lone": [BT_SCRIPT.TerrainType.OBJECT],
	"object_joined": [BT_SCRIPT.TerrainType.OBJECT],
	"object_bake": [BT_SCRIPT.TerrainType.OBJECT],
	"exemplar": [BT_SCRIPT.TerrainType.EXEMPLAR],
	"cliff": [BT_SCRIPT.TerrainType.MATCH_TILES, BT_SCRIPT.TerrainType.MATCH_VERTICES,
		BT_SCRIPT.TerrainType.EXEMPLAR],
}
const MIN_ZOOM_SETTING := "editor/better_terrain/min_zoom_amount"
const MAX_ZOOM_SETTING := "editor/better_terrain/max_zoom_amount"

const GRID_MODE_SETTING := "editors/better_terrain/grid_view"
const COLLAPSED_SETTING := "editors/better_terrain/collapsed_groups"
const QUICK_MODE_SETTING := "editors/better_terrain/quick_mode"
const HIDE_SUPPORT_SETTING := "editors/better_terrain/hide_support_layers"
const SHOW_ZOOM_SETTING := "editors/better_terrain/show_zoom_control"
const SHOW_TOOL_NAMES_SETTING := "editors/better_terrain/show_tool_names"
const SHOW_TILE_GRID_SETTING := "editors/better_terrain/show_tile_grid"
const SHOW_EMPTY_ATLAS_SETTING := "editors/better_terrain/show_empty_atlas_space"
const SHOW_REFRESH_SETTING := "editors/better_terrain/show_refresh_button"
const HIDE_NATIVE_TERRAINS_SETTING := "editors/better_terrain/hide_native_terrains"
const HIDE_NATIVE_TILES_SETTING := "editors/better_terrain/hide_native_tiles"
const HIDE_NATIVE_PATTERNS_SETTING := "editors/better_terrain/hide_native_patterns"
const RENAME_TAB_SETTING := "editors/better_terrain/rename_tab_to_terrains"
const FILL_SCOPE_SETTING := "editors/better_terrain/fill_scope"
const HIDE_TYPE_ICONS_SETTING := "editors/better_terrain/hide_type_icons"
const SHOW_HIDDEN_SETTING := "editors/better_terrain/show_hidden_terrains"
const HIDE_SCENES_SETTING := "editors/better_terrain/hide_scene_tiles"
const PICKER_MODIFIER_SETTING := "editors/better_terrain/picker_modifier"
const PICKER_SELECT_LAYER_SETTING := "editors/better_terrain/picker_select_layer"

enum PickerModifier { ALT, SHIFT }
const PICKER_MODIFIER_NAMES := ["Alt", "Shift"]

const GROUP_META := &"better_terrain_group"
const GROUP_HEADER_SCRIPT := preload("res://addons/better-tile-editor/editor/GroupHeader.gd")
const TERRAIN_LIST_SCRIPT := preload("res://addons/better-tile-editor/editor/TerrainList.gd")
const SCENES_GROUP := TERRAIN_LIST_SCRIPT.SCENES_GROUP
const SCENE_META := &"better_terrain_scene"
## Survives a reload of the plugin, which frees the dock: [tile set instance id, entry].
const LAST_ENTRY_META := &"_better_tile_editor_last_entry"


# Buttons
@onready var draw_button: Button = $VBox/Toolbar/Draw
@onready var line_button: Button = $VBox/Toolbar/Line
@onready var rectangle_button: Button = $VBox/Toolbar/Rectangle
@onready var fill_button: Button = $VBox/Toolbar/Fill
@onready var replace_button: Button = $VBox/Toolbar/Replace

@onready var paint_type: Button = $VBox/Toolbar/PaintType
@onready var paint_terrain: Button = $VBox/Toolbar/PaintTerrain
@onready var select_tiles: Button = $VBox/Toolbar/SelectTiles

@onready var paint_symmetry: Button = $VBox/Toolbar/PaintSymmetry
@onready var object_lone: Button = $VBox/Toolbar/ObjectLone
@onready var object_joined: Button = $VBox/Toolbar/ObjectJoined
@onready var symmetry_options: OptionButton = $VBox/Toolbar/SymmetryOptions

@onready var shuffle_random: Button = $VBox/Toolbar/ShuffleRandom
@onready var zoom_slider_container: VBoxContainer = $VBox/Toolbar/ZoomContainer

@onready var source_selector: MenuBar = $VBox/Toolbar/Sources
@onready var source_selector_popup: PopupMenu = $VBox/Toolbar/Sources/Sources

@onready var clean_button: Button = $VBox/Toolbar/Clean
@onready var live_test_button: Button = $VBox/Toolbar/LiveTest
@onready var layer_up: Button = $VBox/Toolbar/LayerUp
@onready var layer_down: Button = $VBox/Toolbar/LayerDown
@onready var layer_highlight: Button = $VBox/Toolbar/LayerHighlight
@onready var layer_grid: Button = $VBox/Toolbar/LayerGrid
@onready var make_floating: Button = $VBox/Toolbar/MakeFloating

@onready var grid_mode_button: Button = $VBox/HSplit/Terrains/LowerToolbar/GridMode
@onready var quick_mode_button: Button = $VBox/HSplit/Terrains/LowerToolbar/QuickMode

@onready var edit_tool_buttons: HBoxContainer = $VBox/HSplit/Terrains/LowerToolbar/EditTools
@onready var add_terrain_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/AddTerrain
@onready var edit_terrain_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/EditTerrain
@onready var pick_icon_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/PickIcon
@onready var move_up_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/MoveUp
@onready var move_down_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/MoveDown
@onready var remove_terrain_button: Button = $VBox/HSplit/Terrains/LowerToolbar/EditTools/RemoveTerrain

@onready var scroll_container: ScrollContainer = $VBox/HSplit/Terrains/Panel/ScrollContainer
@onready var terrain_list: HFlowContainer = $VBox/HSplit/Terrains/Panel/ScrollContainer/TerrainList
@onready var tile_view: Control = $VBox/HSplit/Editors/Panel/ScrollArea/TileView


var selected_entry := -2

var tilemap : TileMapLayer:
	set(value):
		var changed_layer := tilemap != value
		tilemap = value
		# Selection changes must not modify the scene tree.
		if changed_layer:
			_clear_map_selection()
			_all_selection.clipboard.clear()
		_sync_cliff_rows()
var tileset : TileSet

var undo_manager : EditorUndoRedoManager
var terrain_undo

const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")

var draw_overlay := false
var initial_click : Vector2i
var prev_position : Vector2i
var current_position : Vector2i
var tileset_dirty := false
var zoom_slider : HSlider

enum PaintMode {
	NO_PAINT,
	PAINT,
	ERASE
}

enum PaintAction {
	NO_ACTION,
	LINE,
	RECT,
	SLOPE
}

enum SourceSelectors {
	ALL = 1000000,
	NONE = 1000001,
}

var paint_mode := PaintMode.NO_PAINT

var paint_action := PaintAction.NO_ACTION

var layer_stale := false

var _atlas_refresh_timer: Timer
var auto_resolve_timer : Timer

var group_bar : ScrollContainer
var group_bar_items : HBoxContainer

var group_filter := ""

var _search_box: LineEdit
var _search_text := ""
var _group_filter_before_search := ""

var _known_groups := {}
var _collapsed := {}
var _scene_thumbnails := {}
## Thumbnails taken from the scene's own sprite, drawn at real size on the map.
var _scene_sprite_keys := {}
var _scenes_by_group := {}


# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	_load_collapsed()
	terrain_list.set_script(TERRAIN_LIST_SCRIPT)
	terrain_list.terrain_dropped.connect(_drop_terrain_into_group)
	terrain_list.group_dropped.connect(_drop_terrain_group)
	terrain_list.context_requested.connect(_open_terrain_context)
	terrain_list.scene_dropped.connect(_drop_scene_into_group)
	var manage_groups := Button.new()
	manage_groups.name = "TerrainGroups"
	manage_groups.icon = get_theme_icon("Groups", "EditorIcons")
	manage_groups.flat = true
	manage_groups.focus_mode = Control.FOCUS_NONE
	manage_groups.tooltip_text = "Terrain groups: create, rename and delete groups"
	manage_groups.pressed.connect(_open_terrain_groups)
	$VBox/HSplit/Terrains/LowerToolbar.add_child(manage_groups)
	draw_button.icon = get_theme_icon("Edit", "EditorIcons")
	line_button.icon = get_theme_icon("Line", "EditorIcons")
	rectangle_button.icon = get_theme_icon("Rectangle", "EditorIcons")
	fill_button.icon = get_theme_icon("Bucket", "EditorIcons")
	select_tiles.icon = get_theme_icon("ToolSelect", "EditorIcons")
	select_tiles.tooltip_text = "Select tiles in the atlas, then:\nCtrl+C / Ctrl+V to copy and paste their peering bits\nDelete to clear their bits\nEnter to add them to, or take them out of, this terrain"
	add_terrain_button.icon = get_theme_icon("Add", "EditorIcons")
	edit_terrain_button.icon = get_theme_icon("Tools", "EditorIcons")
	pick_icon_button.icon = get_theme_icon("ColorPick", "EditorIcons")
	move_up_button.icon = get_theme_icon("ArrowUp", "EditorIcons")
	move_down_button.icon = get_theme_icon("ArrowDown", "EditorIcons")
	remove_terrain_button.icon = get_theme_icon("Remove", "EditorIcons")
	grid_mode_button.icon = get_theme_icon("FileThumbnail", "EditorIcons")
	_add_cliff_button()
	_add_map_select_button()
	_add_slope_button()
	_add_picker_button()
	_hook_brush_menu()
	_add_options_button()
	_hook_cliff_level_watch()
	_build_order_watch_timer()
	quick_mode_button.icon = get_theme_icon("GuiVisibilityVisible", "EditorIcons")
	layer_up.icon = get_theme_icon("MoveUp", "EditorIcons")
	layer_down.icon = get_theme_icon("MoveDown", "EditorIcons")
	layer_highlight.icon = get_theme_icon("TileMapHighlightSelected", "EditorIcons")
	layer_grid.icon = get_theme_icon("Grid", "EditorIcons")
	make_floating.icon = get_theme_icon("MakeFloating", "EditorIcons")
	live_test_button.icon = get_theme_icon("Reload", "EditorIcons")

	clip_contents = true

	select_tiles.button_group.pressed.connect(_on_bit_button_pressed)

	_atlas_refresh_timer = Timer.new()
	_atlas_refresh_timer.one_shot = true
	_atlas_refresh_timer.wait_time = 0.1
	_atlas_refresh_timer.timeout.connect(func():
		if tile_view.editing_rules():
			_atlas_refresh_timer.start()
		elif tileset_dirty:
			tiles_changed())
	add_child(_atlas_refresh_timer)
	auto_resolve_timer = Timer.new()
	auto_resolve_timer.one_shot = true
	auto_resolve_timer.wait_time = 0.25
	auto_resolve_timer.timeout.connect(_auto_resolve_layer)
	add_child(auto_resolve_timer)

	terrain_undo = load("res://addons/better-tile-editor/editor/TerrainUndo.gd").new()
	add_child(terrain_undo)

	_build_search_box()


	tile_view.undo_manager = undo_manager
	tile_view.terrain_undo = terrain_undo
	
	tile_view.paste_occurred.connect(_on_paste_occurred)
	tile_view.change_zoom_level.connect(_on_change_zoom_level)
	tile_view.terrain_updated.connect(_on_terrain_updated)

	_build_scatter_bag()
	_build_collision_panel()
	_build_fill_scope()
	
	# Zoom slider is manipulated by settings, make it at runtime
	zoom_slider = HSlider.new()
	zoom_slider.custom_minimum_size = Vector2(100, 0)
	zoom_slider.value_changed.connect(tile_view._on_zoom_value_changed)
	zoom_slider_container.add_child(zoom_slider)
	
	# Init settings if needed
	if !ProjectSettings.has_setting(MIN_ZOOM_SETTING):
		ProjectSettings.set(MIN_ZOOM_SETTING, 1.0)
	ProjectSettings.add_property_info({
		"name": MIN_ZOOM_SETTING,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "0.1,1.0,0.1"
	})
	ProjectSettings.set_initial_value(MIN_ZOOM_SETTING, 1.0)
	ProjectSettings.set_as_basic(MIN_ZOOM_SETTING, true)
	
	if !ProjectSettings.has_setting(MAX_ZOOM_SETTING):
		ProjectSettings.set(MAX_ZOOM_SETTING, 8.0)
	ProjectSettings.add_property_info({
		"name": MAX_ZOOM_SETTING,
		"type": TYPE_FLOAT,
		"hint": PROPERTY_HINT_RANGE,
		"hint_string": "2.0,32.0,1.0"
	})
	ProjectSettings.set_initial_value(MAX_ZOOM_SETTING, 8.0)
	ProjectSettings.set_as_basic(MAX_ZOOM_SETTING, true)
	ProjectSettings.set_order(MAX_ZOOM_SETTING, ProjectSettings.get_order(MIN_ZOOM_SETTING) + 1)
	
	ProjectSettings.settings_changed.connect(_on_adjust_settings)
	_on_adjust_settings()
	zoom_slider.value = 1.0

	_build_group_bar()
	scroll_container.resized.connect(_update_group_header_widths)
	_restore_view_modes()
	_arrange_toolbar()
	_apply_tool_names()


#region Display groups

func _build_group_bar() -> void:
	var terrains_column := terrain_list.get_parent().get_parent().get_parent()

	group_bar = ScrollContainer.new()
	group_bar.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	group_bar.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	group_bar.custom_minimum_size = Vector2(0, 40)
	group_bar.visible = false

	group_bar_items = HBoxContainer.new()
	group_bar_items.add_theme_constant_override("separation", 4)
	group_bar.add_child(group_bar_items)

	terrains_column.add_child(group_bar)
	terrains_column.move_child(group_bar, 0)


func _group_abbreviation(group_name: String) -> String:
	var words := group_name.split(" ", false)
	if words.size() >= 2:
		return (words[0].substr(0, 1) + words[1].substr(0, 1)).to_upper()
	return group_name.substr(0, 2).to_upper()


func _rebuild_group_bar() -> void:
	for c in group_bar_items.get_children():
		group_bar_items.remove_child(c)
		c.queue_free()

	var groups := _groups_with_terrains()
	group_bar.visible = !groups.is_empty()

	if groups.is_empty():
		group_filter = ""
		return

	if !group_filter.is_empty() and !groups.any(func(g): return g.name == group_filter):
		group_filter = ""

	group_bar_items.add_child(_make_all_chip())
	var sep := VSeparator.new()
	sep.add_theme_constant_override("separation", 8)
	group_bar_items.add_child(sep)

	for g in groups:
		group_bar_items.add_child(_make_group_chip(g))


func _groups_with_terrains() -> Array:
	if !tileset:
		return []
	return BetterTerrain.get_terrain_groups(tileset).filter(
		func(g): return (!BetterTerrain.get_terrains_in_group(tileset, g.name).is_empty() or _scenes_by_group.has(g.name)) and _group_shown(g.name)
	)


func _group_shown(group: String) -> bool:
	if group != SLOPE_TERRAIN.HIDDEN_GROUP:
		return true
	var settings := EditorInterface.get_editor_settings()
	return settings.has_setting(SHOW_HIDDEN_SETTING) and bool(settings.get_setting(SHOW_HIDDEN_SETTING))


func _group_thumbnail(g: Dictionary, side: int) -> Control:
	var texture := BetterTerrain.get_terrain_icon_texture(tileset, g.icon_terrain)

	if texture:
		var rect := TextureRect.new()
		rect.texture = texture
		rect.custom_minimum_size = Vector2(side, side)
		rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
		return rect

	var swatch := ColorRect.new()
	swatch.color = g.color
	swatch.custom_minimum_size = Vector2(side, side)
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return swatch


func _make_all_chip() -> Button:
	var chip := Button.new()
	chip.toggle_mode = true
	chip.button_pressed = group_filter.is_empty()
	chip.tooltip_text = "Show terrains from every group"
	chip.custom_minimum_size = Vector2(34, 34)
	chip.set_meta(GROUP_META, "")
	chip.toggled.connect(func(pressed):
		if !pressed:
			chip.set_pressed_no_signal(true)
			return
		_on_group_chip_toggled(false, ""))
	_style_chip(chip)

	var icon_rect := TextureRect.new()
	icon_rect.texture = load("res://addons/better-tile-editor/icons/GroupAll.svg")
	icon_rect.custom_minimum_size = Vector2(16, 16)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_fill_chip(chip, "ALL", icon_rect)
	return chip


func _fill_chip(chip: Button, text: String, thumbnail: Control) -> void:
	var box := VBoxContainer.new()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.alignment = BoxContainer.ALIGNMENT_CENTER
	box.add_theme_constant_override("separation", 1)

	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	label.add_theme_font_size_override("font_size", 8)
	label.add_theme_color_override("font_color", Color.WHITE)
	box.add_child(label)

	thumbnail.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	box.add_child(thumbnail)

	chip.add_child(box)
	box.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)


func _style_chip(chip: Button) -> void:
	var accent := get_theme_color("accent_color", "Editor")

	var pressed_style := StyleBoxFlat.new()
	pressed_style.bg_color = accent
	pressed_style.set_corner_radius_all(3)
	pressed_style.set_content_margin_all(2)
	chip.add_theme_stylebox_override("pressed", pressed_style)

	var hover_pressed_style := pressed_style.duplicate()
	hover_pressed_style.bg_color = accent.lightened(0.15)
	chip.add_theme_stylebox_override("hover_pressed", hover_pressed_style)


func _make_group_chip(g: Dictionary) -> Button:
	var chip := Button.new()
	chip.toggle_mode = true
	chip.button_pressed = group_filter == g.name
	chip.tooltip_text = g.name
	chip.custom_minimum_size = Vector2(34, 34)
	chip.set_meta(GROUP_META, g.name)
	chip.toggled.connect(_on_group_chip_toggled.bind(g.name))

	_style_chip(chip)
	_fill_chip(chip, _group_abbreviation(g.name), _group_thumbnail(g, 16))
	return chip


func _on_group_chip_toggled(pressed: bool, group_name: String) -> void:
	if _search_box and _search_box.visible:
		_search_box.visible = false
		_search_box.text = ""
		_search_text = ""

	group_filter = group_name if pressed else ""
	_group_filter_before_search = group_filter
	if pressed and _collapsed.has(group_name):
		_expand_group(group_name)

	for c in group_bar_items.get_children():
		if c.has_method("set_pressed_no_signal"):
			c.set_pressed_no_signal(c.get_meta(GROUP_META, "") == group_filter)

	_apply_entry_filters()


func _display_group_of(terrain: Dictionary) -> String:
	var group : String = terrain.get("group", "")
	return group if _known_groups.has(group) else ""


func _make_group_header(g: Dictionary) -> Control:
	var header := HBoxContainer.new()
	header.set_script(GROUP_HEADER_SCRIPT)
	header.set_meta(GROUP_META, g.name)
	header.setup(g.name, _collapsed.has(g.name), _group_thumbnail(g, 14),
		get_theme_color("font_disabled_color", "Editor"))
	header.set_row_width(_available_list_width(), _list_row_width())
	header.collapse_toggled.connect(_on_group_collapse_toggled)
	header.terrain_dropped.connect(_drop_terrain_into_group)
	header.setup_reordering(tileset.get_instance_id())
	header.manage_requested.connect(_open_terrain_groups)
	return header


func _open_terrain_groups(group: String = "") -> void:
	if tileset == null:
		return
	var manager = load("res://addons/better-tile-editor/editor/TerrainGroups.gd").new()
	manager.tileset = tileset
	add_child(manager)
	manager.refresh()
	var groups := BetterTerrain.get_terrain_groups(tileset)
	var index := groups.find_custom(func(g): return g.name == group)
	if index >= 0:
		manager._list.select(index)
		manager._sync_buttons()
	manager.groups_changed.connect(func():
		group_filter = ""
		rebuild_terrain_list())
	manager.visibility_changed.connect(func():
		if not manager.visible:
			manager.queue_free())
	manager.popup_centered()


func _drop_terrain_group(source: String, target: String, after: bool) -> void:
	var groups := BetterTerrain.get_terrain_groups(tileset)
	var from_index := groups.find_custom(func(g): return g.name == source)
	var to_index := groups.find_custom(func(g): return g.name == target)
	if from_index < 0 or to_index < 0 or from_index == to_index:
		return
	if after:
		to_index += 1
	if from_index < to_index:
		to_index -= 1
	if from_index == to_index:
		return
	undo_manager.create_action("Reorder terrain groups", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"_perform_move_terrain_group", tileset, from_index, to_index)
	undo_manager.add_undo_method(self, &"_perform_move_terrain_group", tileset, to_index, from_index)
	undo_manager.commit_action()


func _perform_move_terrain_group(target: TileSet, from_index: int, to_index: int) -> void:
	BetterTerrain.move_terrain_group(target, from_index, to_index)
	if tileset == target:
		rebuild_terrain_list()


func _on_group_collapse_toggled(group: String, collapsed: bool) -> void:
	if collapsed:
		_collapsed[group] = true
	else:
		_collapsed.erase(group)
	_store_collapsed()
	_apply_entry_filters()


func _expand_group(group: String) -> void:
	_collapsed.erase(group)
	_store_collapsed()
	for c in terrain_list.get_children():
		if c.has_method("set_collapsed") and c.group_name == group:
			c.set_collapsed(false)


func _store_collapsed() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings != null:
		settings.set_setting(COLLAPSED_SETTING, PackedStringArray(_collapsed.keys()))


func _load_collapsed() -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(COLLAPSED_SETTING):
		return
	_collapsed.clear()
	for n in settings.get_setting(COLLAPSED_SETTING):
		_collapsed[String(n)] = true


func _drop_terrain_into_group(id: int, group: String) -> void:
	if tileset == null or group == SCENES_GROUP:
		return
	var t := BetterTerrain.get_terrain(tileset, id)
	if not t.valid:
		return
	var target := group
	if String(t.group) == target:
		return
	undo_manager.create_action("Move terrain to group", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_edit_terrain", id, t.name, t.color, t.type, t.categories, t.icon, target, t.get("object", {}))
	undo_manager.add_undo_method(self, &"perform_edit_terrain", id, t.name, t.color, t.type, t.categories, t.icon, t.group, t.get("object", {}))
	undo_manager.commit_action()


func _available_list_width() -> float:
	if !is_instance_valid(scroll_container):
		return 0.0

	var width := scroll_container.size.x
	var vscroll := scroll_container.get_v_scroll_bar()
	if vscroll and (vscroll.visible or scroll_container.vertical_scroll_mode == ScrollContainer.SCROLL_MODE_RESERVE):
		width -= vscroll.size.x

	return maxf(width, 0.0)


## List entries are wider than the view, so view-wide headers would share a line when a group collapses.
func _list_row_width() -> float:
	var width := _available_list_width()
	if !grid_mode_button.button_pressed:
		width = maxf(width, TERRAIN_ENTRY_SCRIPT.LIST_ROW_WIDTH)
	return width


func _update_group_header_widths() -> void:
	var width := _available_list_width()
	if width <= 0.0:
		return

	var row := _list_row_width()
	for c in terrain_list.get_children():
		if c.has_method("set_row_width"):
			c.set_row_width(width, row)
		elif !c.has_method("terrain_id"):
			c.custom_minimum_size.x = row

#endregion


func _restore_view_modes() -> void:
	var settings := EditorInterface.get_editor_settings()

	grid_mode_button.set_pressed_no_signal(settings.get_setting(GRID_MODE_SETTING) if settings.has_setting(GRID_MODE_SETTING) else true)
	if settings.has_setting(QUICK_MODE_SETTING):
		quick_mode_button.set_pressed_no_signal(settings.get_setting(QUICK_MODE_SETTING))

	_on_grid_mode_pressed()
	_on_quick_mode_pressed()


func _store_view_mode(setting: String, value: bool) -> void:
	var settings := EditorInterface.get_editor_settings()
	if settings.has_setting(setting) and bool(settings.get_setting(setting)) == value:
		return

	settings.set_setting(setting, value)


func _process(_delta):
	scroll_container.scroll_horizontal = 0


func _on_adjust_settings():
	zoom_slider.min_value = ProjectSettings.get_setting(MIN_ZOOM_SETTING, 1.0)
	zoom_slider.max_value = ProjectSettings.get_setting(MAX_ZOOM_SETTING, 8.0)
	zoom_slider.step = (zoom_slider.max_value - zoom_slider.min_value) / 100.0


const MAX_FILL_CELLS := 20000

var _view_cells := Rect2i()


func _get_fill_cells(target: Vector2i) -> Array:
	var pick := BetterTerrain.get_cell(tilemap, target)

	var by_sight := _fill_by_sight()
	var shape_of := tilemap
	if by_sight:
		var top := BetterTerrain.top_layer_at(tilemap, target)
		if top != null:
			shape_of = top
			pick = BetterTerrain.get_cell(top, target)
	elif pick == BetterTerrain.TileCategory.EMPTY:
		var below := BetterTerrain.layer_below(tilemap, target)
		if below != null:
			shape_of = below
			pick = BetterTerrain.get_cell(below, target)

	var bounds := shape_of.get_used_rect()
	if pick == BetterTerrain.TileCategory.EMPTY and _view_cells.size != Vector2i.ZERO:
		bounds = bounds.merge(_view_cells) if bounds.size != Vector2i.ZERO else _view_cells
	var neighbors = BetterTerrain.data.cells_adjacent_for_fill(tileset)
	
	# No sets yet, so use a dictionary
	var checked := {}
	var pending := [target]
	var goal := []
	
	while !pending.is_empty():
		var p = pending.pop_front()
		if checked.has(p):
			continue
		checked[p] = true
		var alike: bool = BetterTerrain.same_visible_region(tilemap, target, p) if by_sight \
			else BetterTerrain.same_fill_region(shape_of, target, p)
		if !bounds.has_point(p) or not alike:
			continue
		
		goal.append(p)
		if goal.size() >= MAX_FILL_CELLS:
			break
		pending.append_array(BetterTerrain.data.neighboring_coords(tilemap, p, neighbors))
	
	return goal


func tiles_about_to_change() -> void:
	if tileset and tileset.changed.is_connected(queue_tiles_changed):
		tileset.changed.disconnect(queue_tiles_changed)
	if _slope_editor != null and _slope_editor.visible:
		_slope_editor.close()


func tiles_changed() -> void:
	_atlas_refresh_timer.stop()
	# Direct calls load a fresh layer; tileset.changed marks it dbrty before deferring.
	if !tileset_dirty:
		layer_stale = false

	# ensure up to date
	BetterTerrain._update_terrain_data(tileset)
	
	rebuild_terrain_list()

	source_selector_popup.clear()
	source_selector_popup.add_item("All", SourceSelectors.ALL)
	source_selector_popup.add_item("None", SourceSelectors.NONE)
	var source_count = tileset.get_source_count() if tileset else 0
	for s in source_count:
		var source_id = tileset.get_source_id(s)
		var source := tileset.get_source(source_id)
		if !(source is TileSetAtlasSource):
			continue
		
		var source_name := source.resource_name
		if source_name.is_empty():
			var texture := (source as TileSetAtlasSource).texture
			var texture_name := texture.resource_name if texture else ""
			if !texture_name.is_empty():
				source_name = texture_name
			else:
				var texture_path := texture.resource_path if texture else ""
				if !texture_path.is_empty():
					source_name = texture_path.get_file()
		
		if !source_name.is_empty():
			source_name += " "
		source_name += " (ID: %d)" % source_id
		
		source_selector_popup.add_check_item(source_name, source_id)
		
		source_selector_popup.set_item_checked(
			source_selector_popup.get_item_index(source_id),
			not tile_view.disabled_sources.has(source_id)
		)
	source_selector.visible = source_selector_popup.item_count > 3 # All, None and more than one source
	
	update_tile_view_paint()
	tile_view.refresh_tileset(tileset)
	
	if tileset and !tileset.changed.is_connected(queue_tiles_changed):
		tileset.changed.connect(queue_tiles_changed)
	
	clean_button.visible = BetterTerrain._has_invalid_peering_types(tileset)
	
	tileset_dirty = false
	_on_grid_mode_pressed()
	_on_quick_mode_pressed()

	live_test_button.modulate = Color(1.0, 0.7, 0.3) if layer_stale else Color.WHITE
	_restore_last_entry()
	update_overlay.emit()


## A reload of the plugin makes a new dock with nothing selected; pick what was.
func _restore_last_entry() -> void:
	if tileset == null or selected_entry != -2 or not Engine.has_meta(LAST_ENTRY_META):
		return
	var last: Array = Engine.get_meta(LAST_ENTRY_META)
	if last[0] != tileset.get_instance_id():
		return
	var id: int = last[1]
	var entry = _entry_for_id(id)
	if entry == null:
		return
	_on_entry_select(id)
	entry.selected = true
	entry.queue_redraw()
	_sync_scene_selection()


func about_to_be_visible(becoming_visible: bool) -> void:
	if !becoming_visible:
		return
	
	if tilemap and tileset != tilemap.tile_set:
		tiles_about_to_change()
		tileset = tilemap.tile_set
		tiles_changed()
	
	var settings := EditorInterface.get_editor_settings()
	layer_highlight.set_pressed_no_signal(settings.get_setting("editors/tiles_editor/highlight_selected_layer"))
	layer_grid.set_pressed_no_signal(settings.get_setting("editors/tiles_editor/display_grid"))


func queue_tiles_changed() -> void:
	# Bring terrain data up to date with complex tileset changes
	if !tileset:
		return

	if tilemap and live_test_button.button_pressed:
		layer_stale = true
		auto_resolve_timer.start()

	if tile_view.editing_rules():
		tileset_dirty = true
		_atlas_refresh_timer.start()
		tile_view.queue_redraw()
		return

	if tileset_dirty:
		return

	tileset_dirty = true
	tiles_changed.call_deferred()


func _auto_resolve_layer() -> void:
	if tile_view.editing_rules():
		auto_resolve_timer.start()
		return
	if !tilemap or !tileset or !live_test_button.button_pressed:
		return

	var area := tilemap.get_used_rect()
	if area.size.x <= 0 or area.size.y <= 0:
		return

	BetterTerrain.update_terrain_area(tilemap, area)
	layer_stale = false
	live_test_button.modulate = Color.WHITE
	update_overlay.emit()


func _on_entry_edit_requested(id: int) -> void:
	_on_entry_select(id)
	_on_edit_terrain_pressed()


func _on_entry_select(id:int):
	selected_entry = id
	if tileset != null:
		Engine.set_meta(LAST_ENTRY_META, [tileset.get_instance_id(), id])
	if selected_entry >= BetterTerrain.terrain_count(tileset):
		selected_entry = BetterTerrain.TileCategory.EMPTY
	for c in terrain_list.get_children():
		if c.has_method("terrain_id") and (c.terrain_id() != id or c.has_meta(SCENE_META)):
			c.set_selected(false)
	update_tile_view_paint()


func _on_clean_pressed() -> void:
	var confirmed := [false]
	var popup := ConfirmationDialog.new()
	popup.dialog_text = tr("Tile set changes have caused terrain to become invalid. Remove invalid terrain data?")
	popup.dialog_hide_on_ok = false
	popup.confirmed.connect(func():
		confirmed[0] = true
		popup.hide()
	)
	EditorInterface.popup_dialog_centered(popup)
	await popup.visibility_changed
	popup.queue_free()
	
	if confirmed[0]:
		undo_manager.create_action("Clean invalid terrain peering data", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(BetterTerrain, &"_clear_invalid_peering_types", tileset)
		undo_manager.add_do_method(self, &"tiles_changed")
		terrain_undo.create_peering_restore_point(undo_manager, tileset)
		undo_manager.add_undo_method(self, &"tiles_changed")
		undo_manager.commit_action()


func _on_live_test_toggled(pressed: bool) -> void:
	if !pressed:
		auto_resolve_timer.stop()
		layer_stale = false
		live_test_button.modulate = Color.WHITE
		update_overlay.emit()
		return

	if !tilemap or !tileset:
		push_warning("[Live test] No TileMapLayer is selected. Select the layer NODE in the scene tree; opening the TileSet is not enough.")
		return

	var area := tilemap.get_used_rect()
	if area.size.x <= 0 or area.size.y <= 0:
		push_warning("[Live test] Layer '%s' is empty: no tiles painted on it." % tilemap.name)
		return

	var used_cells := tilemap.get_used_cells()
	if not used_cells.any(func(c): return BetterTerrain.get_cell(tilemap, c) >= 0):
		push_warning("[Live test] None of this layer's tiles has a terrain type assigned in the TileSet, so there is nothing to reconnect. Assign terrains to those tiles in the BetterTerrain editor.")

	undo_manager.create_action(tr("Re-solve terrain layer"), UndoRedo.MERGE_DISABLE, tilemap)
	undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, area)
	terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, area)
	undo_manager.commit_action()

	layer_stale = false
	live_test_button.modulate = Color.WHITE
	update_overlay.emit()


func _on_grid_mode_pressed() -> void:
	_store_view_mode(GRID_MODE_SETTING, grid_mode_button.button_pressed)
	for c in terrain_list.get_children():
		if c.has_method("terrain_id"):
			c.grid_mode = grid_mode_button.button_pressed
			c.update_style()
	_update_group_header_widths()


func _on_quick_mode_pressed() -> void:
	_store_view_mode(QUICK_MODE_SETTING, quick_mode_button.button_pressed)
	_apply_entry_filters()


func _build_search_box() -> void:
	var panel := terrain_list.get_parent().get_parent() as Control
	if panel == null:
		return

	var overlay := Control.new()
	overlay.name = "SearchOverlay"
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(overlay)

	_search_box = LineEdit.new()
	_search_box.placeholder_text = "Filter terrains (all groups)"
	_search_box.clear_button_enabled = true
	_search_box.visible = false
	_search_box.anchor_top = 1.0
	_search_box.anchor_bottom = 1.0
	_search_box.offset_left = 6
	_search_box.offset_right = 226
	_search_box.offset_top = -34
	_search_box.offset_bottom = -6
	_search_box.text_changed.connect(_on_search_changed)
	overlay.add_child(_search_box)


func _unhandled_key_input(event: InputEvent) -> void:
	if !(event is InputEventKey) or !event.pressed or _search_box == null:
		return

	var focused := get_viewport().gui_get_focus_owner()
	var in_list : bool = focused != null and (focused == terrain_list or terrain_list.is_ancestor_of(focused))

	if event.keycode == KEY_ESCAPE and _search_box.visible:
		_close_search()
		accept_event()
		return

	if !in_list or _search_box.visible:
		return
	if event.is_command_or_control_pressed() or event.alt_pressed:
		return

	var ch := char(event.unicode)
	if event.unicode < 32 or ch.strip_edges().is_empty():
		return

	_group_filter_before_search = group_filter
	group_filter = ""
	_sync_group_chips()

	_search_box.visible = true
	_search_box.text = ch
	_search_box.grab_focus()
	_search_box.caret_column = _search_box.text.length()
	_on_search_changed(_search_box.text)
	accept_event()


func _on_search_changed(text: String) -> void:
	_search_text = text.strip_edges()
	if _search_text.is_empty() and !_search_box.has_focus():
		_close_search()
		return
	_apply_entry_filters()


func _close_search() -> void:
	if _search_box == null or !_search_box.visible:
		return
	_search_box.visible = false
	_search_box.text = ""
	_search_text = ""
	group_filter = _group_filter_before_search
	_sync_group_chips()
	_apply_entry_filters()
	terrain_list.grab_focus()


func _sync_group_chips() -> void:
	if group_bar_items == null:
		return
	for c in group_bar_items.get_children():
		if c.has_method("set_pressed_no_signal"):
			c.set_pressed_no_signal(c.get_meta(GROUP_META, "") == group_filter)


func _apply_entry_filters() -> void:
	var quick := quick_mode_button.button_pressed
	edit_tool_buttons.visible = !quick

	var searching := !_search_text.is_empty()
	for c in terrain_list.get_children():
		var of_group: String = c.get_meta(GROUP_META, "")
		var in_filter : bool = group_filter.is_empty() or of_group == group_filter
		if in_filter and not searching and (c.has_method("terrain_id") or c.has_meta(&"empty_terrain_group")) and _collapsed.has(of_group):
			in_filter = false
		if searching:
			in_filter = c.has_method("terrain_id") \
				and c.terrain.name.to_lower().contains(_search_text.to_lower())

		if c.has_method("terrain_id"):
			var paintable : bool = c.terrain.type in [BetterTerrain.TerrainType.MATCH_TILES,
				BetterTerrain.TerrainType.MATCH_VERTICES, BetterTerrain.TerrainType.OBJECT,
				BetterTerrain.TerrainType.EXEMPLAR, BetterTerrain.TerrainType.SCATTER,
				BetterTerrain.TerrainType.SINGLE] or c.terrain.has("tool_icon")
			c.visible = in_filter and (!quick or paintable)
		else:
			c.visible = in_filter


func update_tile_view_paint() -> void:
	tile_view.paint = selected_entry
	_update_picker_tooltip()
	tile_view.dim_unassigned_tiles = not _is_single(selected_entry)
	tile_view.queue_redraw()
	
	var editable = tile_view.paint >= 0
	edit_terrain_button.disabled = !editable
	move_up_button.disabled = !editable or tile_view.paint == 0
	move_down_button.disabled = !editable or tile_view.paint == BetterTerrain.terrain_count(tileset) - 1
	remove_terrain_button.disabled = !editable
	pick_icon_button.disabled = !editable

	var t = BetterTerrain.get_terrain(tileset, selected_entry) if editable else {valid = false}
	var mode : int = int(t.type) if t.valid else -1
	var is_object : bool = mode == BetterTerrain.TerrainType.OBJECT
	var is_exemplar : bool = mode == BetterTerrain.TerrainType.EXEMPLAR

	for mode_name in TOOL_MODES:
		var button: Button = _tool_button(mode_name)
		if button != null:
			button.visible = mode in TOOL_MODES[mode_name]

	if _slope_button != null:
		_slope_button.visible = t.valid and SLOPE_TERRAIN.uses_terrain(tileset, selected_entry)
		if not _slope_button.visible and _slope_button.button_pressed:
			draw_button.button_pressed = true

	if not (mode in TOOL_MODES["cliff"]) and t.valid and CLIFF_DATA.all_configs(tileset).has(str(t.name)):
		if _cliff_button != null:
			_cliff_button.visible = true

	# Hidden tools must be disarmed so they cannot keep changing painting behavior.
	if is_object and (paint_type.button_pressed or paint_terrain.button_pressed or paint_symmetry.button_pressed):
		object_lone.button_pressed = true
		_on_bit_button_pressed(object_lone)
	elif !is_object and (object_lone.button_pressed or object_joined.button_pressed):
		paint_type.button_pressed = true
		_on_bit_button_pressed(paint_type)
	if is_exemplar and (paint_terrain.button_pressed or paint_symmetry.button_pressed):
		paint_type.button_pressed = true
		_on_bit_button_pressed(paint_type)
	# A hidden Select must not stay the tool in use where painting has a tool of its own.
	if select_tiles.button_pressed and not select_tiles.visible:
		for fallback: Button in [paint_type, object_lone]:
			if fallback.visible:
				fallback.button_pressed = true
				_on_bit_button_pressed(fallback)
				break
	if mode in [BetterTerrain.TerrainType.SCATTER, BetterTerrain.TerrainType.SINGLE] \
			and not select_tiles.button_pressed:
		select_tiles.button_pressed = true
		_on_bit_button_pressed(select_tiles)
	_sync_cliff_rows()
	_sync_scatter_bag()
	_sync_oven_button()
	_sync_collision_mode()


func _tool_button(mode_name: String) -> Button:
	match mode_name:
		"select_tiles": return select_tiles
		"live_test": return live_test_button
		"paint_type": return paint_type
		"paint_terrain": return paint_terrain
		"paint_symmetry": return paint_symmetry
		"object_lone": return object_lone
		"object_joined": return object_joined
		"object_bake": return _oven_button
		"exemplar": return _exemplar_button
		"cliff": return _cliff_button
	return null


func _open_terrain_context(group: String, id: int = -1) -> void:
	if tileset == null or group == SCENES_GROUP:
		return
	var menu := PopupMenu.new()
	menu.name = "TerrainContextMenu"
	add_child(menu)
	# Editor icons, or the plugin's own where the toolbar uses them, so both read as one.
	var item := func(icon: String, text: String, action: int) -> void:
		var texture: Texture2D = load(ICON_DIR + icon) if icon.ends_with(".svg") else get_theme_icon(icon, "EditorIcons")
		menu.add_icon_item(texture, text, action)
		menu.set_item_icon_max_width(menu.get_item_index(action), int(16 * EditorInterface.get_editor_scale()))
	item.call("Add", "Add new terrain in %s" % (group if not group.is_empty() else "General"), 0)
	if id >= 0:
		menu.add_separator()
		item.call("Edit", "Open terrain properties…", 1)
		var terrain := BetterTerrain.get_terrain(tileset, id)
		if terrain.type in TOOL_MODES["cliff"] or CLIFF_DATA.all_configs(tileset).has(str(terrain.name)):
			item.call("CliffFace.svg", "Open cliff editor…", 2)
		if terrain.type == BetterTerrain.TerrainType.MATCH_TILES:
			item.call("Slope.svg", "Set up slopes…", 5)
		if COVERAGE.unsupported(tileset, id).is_empty():
			item.call("MatchTiles.svg", "Complete terrain…", 6)
		var move := PopupMenu.new()
		move.name = "MoveTo"
		menu.add_child(move)
		var groups := [""]
		for entry in BetterTerrain.get_terrain_groups(tileset):
			groups.append(entry.name)
		for index in groups.size():
			move.add_item("General" if groups[index].is_empty() else groups[index], index)
			move.set_item_disabled(index, groups[index] == group)
		move.id_pressed.connect(func(index): _drop_terrain_into_group(id, groups[index]))
		menu.add_submenu_item("Move to", "MoveTo")
		menu.set_item_icon(menu.item_count - 1, get_theme_icon("Folder", "EditorIcons"))
		menu.set_item_icon_max_width(menu.item_count - 1, int(16 * EditorInterface.get_editor_scale()))
		menu.add_separator()
		item.call("Remove", "Delete terrain…", 3)
	menu.add_separator()
	item.call("GroupAll.svg", "Manage terrain groups…", 4)
	menu.id_pressed.connect(func(action):
		if action == 0:
			_on_add_terrain_pressed(group)
		elif action == 4:
			_open_terrain_groups(group)
		else:
			_on_entry_select(id)
			_select_terrain(id)
			match action:
				1: _on_edit_terrain_pressed()
				2: _on_cliff_pressed()
				3: _on_remove_terrain_pressed()
				5: _open_slope_roles()
				6: _open_coverage(id)
	)
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	menu.popup()


func _on_add_terrain_pressed(target_group: Variant = null) -> void:
	if !tileset:
		return
	
	var popup := TERRAIN_PROPERTIES_SCENE.instantiate()
	popup.set_category_data(BetterTerrain.get_terrain_categories(tileset))
	popup.set_group_data(tileset)
	popup.set_object_data(tileset)
	popup.terrain_group = group_filter if target_group == null else str(target_group)
	popup.terrain_name = "New terrain"
	popup.terrain_color = Color.from_hsv(randf(), 0.3 + 0.7 * randf(), 0.6 + 0.4 * randf())
	popup.terrain_icon = ""
	popup.set_icon_data(tileset, -1, {})
	popup.terrain_type = 0
	EditorInterface.popup_dialog_centered(popup)
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Add terrain type", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_add_terrain", popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories, popup.terrain_icon_data(), popup.terrain_group, popup.terrain_object)
		undo_manager.add_undo_method(self, &"perform_remove_terrain", BetterTerrain.terrain_count(tileset))
		undo_manager.commit_action()
	popup.queue_free()
	rebuild_terrain_list()


func _on_edit_terrain_pressed() -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	var categories = BetterTerrain.get_terrain_categories(tileset)
	categories = categories.filter(func(x): return x.id != selected_entry)
	
	var popup := TERRAIN_PROPERTIES_SCENE.instantiate()
	popup.set_category_data(categories)
	popup.set_group_data(tileset)
	popup.set_object_data(tileset, selected_entry)

	t.icon = t.icon.duplicate()

	popup.terrain_name = t.name
	popup.terrain_type = t.type
	popup.terrain_color = t.color
	if t.has("icon") and t.icon.has("path"):
		popup.terrain_icon = t.icon.path
	popup.set_icon_data(tileset, selected_entry, t.get("icon", {}))
	popup.terrain_categories = t.categories
	popup.terrain_group = t.group
	popup.terrain_object = t.get("object", {})
	EditorInterface.popup_dialog_centered(popup)
	await popup.visibility_changed
	if popup.accepted:
		undo_manager.create_action("Edit terrain details", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_edit_terrain", selected_entry, popup.terrain_name, popup.terrain_color, popup.terrain_type, popup.terrain_categories, popup.terrain_icon_data(), popup.terrain_group, popup.terrain_object)
		undo_manager.add_undo_method(self, &"perform_edit_terrain", selected_entry, t.name, t.color, t.type, t.categories, t.icon, t.group, t.get("object", {}))
		if t.type != popup.terrain_type:
			terrain_undo.create_terrain_type_restore_point(undo_manager, tileset)
			terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, selected_entry)
		undo_manager.commit_action()
	popup.queue_free()
	rebuild_terrain_list()


func _on_pick_icon_pressed():
	if selected_entry < 0:
		return
	tile_view.pick_icon_terrain = selected_entry


func _on_pick_icon_focus_exited():
	tile_view.pick_icon_terrain_cancel = true
	pick_icon_button.button_pressed = false


func _on_move_pressed(down: bool) -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	var siblings := _group_siblings(selected_entry)
	var sibling_index := siblings.find(selected_entry)
	if sibling_index < 0:
		return

	var target := sibling_index + (1 if down else -1)
	if target < 0 or target >= siblings.size():
		return

	var index1 : int = selected_entry
	var index2 : int = siblings[target]

	undo_manager.create_action("Reorder terrains", UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.add_undo_method(self, &"perform_swap_terrain", index1, index2)
	undo_manager.commit_action()


var _delete_target := ""


## Remembers whether the last click was on the terrain list or the favorites, for Delete.
func note_click(at: Vector2) -> void:
	_delete_target = ""
	if not is_visible_in_tree():
		return
	if scroll_container.is_visible_in_tree() and scroll_container.get_global_rect().has_point(at):
		_delete_target = "terrain"
	elif _single_bag != null and _single_bag.is_visible_in_tree() and _single_bag.get_global_rect().has_point(at):
		_delete_target = "favorite"


func delete_target() -> String:
	if not is_visible_in_tree() or tileset == null:
		return ""
	match _delete_target:
		"terrain":
			return _delete_target if selected_entry >= 0 and not remove_terrain_button.disabled else ""
		"favorite":
			return _delete_target if _single_bag.selected_index() >= 0 else ""
	return ""


func delete_selected(target: String) -> void:
	match target:
		"terrain":
			_on_remove_terrain_pressed()
		"favorite":
			_single_bag.delete_selected()


func _on_remove_terrain_pressed() -> void:
	if !tileset:
		return
	
	if selected_entry < 0:
		return
	
	# store confirmation in array to pass by ref
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	var whole_set: bool = SLOPE_TERRAIN.is_set_ground(tileset, selected_entry)
	var atlases := _pieces_atlases_of(selected_entry)
	var turns := _terrain_turns(selected_entry)
	var confirmed := [false]
	var popup := ConfirmationDialog.new()
	popup.dialog_text = tr("Are you sure you want to remove {0}?").format([t.name])
	if whole_set:
		popup.dialog_text += "\nIts slopes go with it: the slope pieces, their flipped copies and the slope set-up."
	if not atlases.is_empty():
		popup.dialog_text += "\nThe atlas of pieces made for it goes too, as no other terrain uses it: %s. Its PNG stays on disk." % \
			", ".join(atlases.map(func(a): return a.path.get_file() if not a.path.is_empty() else "atlas %d" % a.id))
	popup.dialog_hide_on_ok = false
	popup.confirmed.connect(func():
		confirmed[0] = true
		popup.hide()
	)
	EditorInterface.popup_dialog_centered(popup)
	await popup.visibility_changed
	popup.queue_free()
	
	if confirmed[0] and whole_set:
		# Ground of a slope set: the hidden slope terrains are only there for it, so they go too
		var before: Array = SLOPE_TERRAIN.snapshot(tileset)
		SLOPE_TERRAIN.remove_set(BetterTerrain, tileset)
		var after: Array = SLOPE_TERRAIN.snapshot(tileset)
		undo_manager.create_action("Remove terrain type and its slopes", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(SLOPE_TERRAIN, &"restore", BetterTerrain, tileset, after)
		undo_manager.add_undo_method(SLOPE_TERRAIN, &"restore", BetterTerrain, tileset, before)
		undo_manager.add_do_method(self, &"_after_set_removed")
		undo_manager.add_undo_method(self, &"_after_set_removed")
		undo_manager.commit_action(false)
		_after_set_removed()
	elif confirmed[0]:
		undo_manager.create_action("Remove terrain type", UndoRedo.MERGE_DISABLE, tileset)
		undo_manager.add_do_method(self, &"perform_remove_terrain", selected_entry)
		undo_manager.add_undo_method(self, &"perform_add_terrain", t.name, t.color, t.type, t.categories, t.icon, t.group)
		for n in range(BetterTerrain.terrain_count(tileset) - 1, selected_entry, -1):
			undo_manager.add_undo_method(self, &"perform_swap_terrain", n, n - 1)
		# Undo runs in the order added: the atlases come back before their tiles' bits do.
		for atlas: Dictionary in atlases:
			undo_manager.add_do_method(tileset, &"remove_source", atlas.id)
			undo_manager.add_undo_method(self, &"_bring_back_pieces_atlas", atlas.src, atlas.id)
		if t.type == BetterTerrain.TerrainType.CATEGORY:
			terrain_undo.create_terrain_type_restore_point(undo_manager, tileset)
		terrain_undo.create_peering_restore_point_specific(undo_manager, tileset, selected_entry)
		# The bits come back without the tiles' turns; these follow them.
		undo_manager.add_undo_method(self, &"_restore_terrain_turns", turns)
		undo_manager.commit_action()


## The atlases of pieces made for a terrain that no other terrain uses:
## [{id, src, path, image}], to go with the terrain.
func _pieces_atlases_of(terrain_id: int) -> Array:
	var out := []
	for s in tileset.get_source_count():
		var id := tileset.get_source_id(s)
		var src := tileset.get_source(id) as TileSetAtlasSource
		if src == null or not src.has_meta(QUARTER_PIECES.GENERATED_META):
			continue
		var mine := false
		var foreign := false
		for t in src.get_tiles_count():
			var coord := src.get_tile_id(t)
			for a in src.get_alternative_tiles_count(coord):
				var type := BetterTerrain.get_tile_terrain_type(src.get_tile_data(coord, src.get_alternative_tile_id(coord, a)))
				if type == terrain_id:
					mine = true
				elif type != BetterTerrain.TileCategory.NON_TERRAIN:
					foreign = true
		if mine and not foreign:
			var path: String = src.texture.resource_path if src.texture != null and src.texture.resource_path.begins_with("res://") else ""
			out.append({id = id, src = src, path = path})
	return out


## Every turn kept on the terrain's tiles: [[source_id, coord, alt, transforms, weight]].
func _terrain_turns(terrain_id: int) -> Array:
	var out := []
	for s in tileset.get_source_count():
		var id := tileset.get_source_id(s)
		var src := tileset.get_source(id) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var coord := src.get_tile_id(t)
			for a in src.get_alternative_tiles_count(coord):
				var alt := src.get_alternative_tile_id(coord, a)
				var td := src.get_tile_data(coord, alt)
				if BetterTerrain.get_tile_terrain_type(td) == terrain_id and not BetterTerrain.get_tile_transforms(td).is_empty():
					out.append([id, coord, alt, BetterTerrain.get_tile_transforms(td), BetterTerrain.get_tile_transform_weight(td)])
	return out


func _restore_terrain_turns(turns: Array) -> void:
	for entry: Array in turns:
		var src := tileset.get_source(entry[0]) as TileSetAtlasSource if tileset.has_source(entry[0]) else null
		if src != null and src.has_alternative_tile(entry[1], entry[2]):
			BetterTerrain.set_tile_transforms(tileset, src.get_tile_data(entry[1], entry[2]), entry[3], entry[4])


# Files are never deleted here: the atlas leaves the tile set in memory, and the tile set on
# disk keeps pointing at the PNG until it is saved, so trashing it broke scenes reopened unsaved.
func _bring_back_pieces_atlas(src: TileSetAtlasSource, id: int) -> void:
	if not tileset.has_source(id):
		tileset.add_source(src, id)


func _after_set_removed() -> void:
	selected_entry = -1
	rebuild_terrain_list()
	update_tile_view_paint()


func rebuild_terrain_list() -> void:
	_sync_cliff_rows()
	for c in terrain_list.get_children():
		terrain_list.remove_child(c)
		c.queue_free()

	_known_groups.clear()
	if !tileset:
		_rebuild_group_bar()
		return

	var groups_by_name := {}
	for g in BetterTerrain.get_terrain_groups(tileset):
		_known_groups[g.name] = true
		groups_by_name[g.name] = g

	var decoration := BetterTerrain.get_terrain(tileset, BetterTerrain.TileCategory.EMPTY)
	var single := BetterTerrain.get_terrain(tileset, BetterTerrain.TileCategory.SINGLE)
	if decoration.valid:
		add_terrain_entry(decoration)
	if single.valid:
		add_terrain_entry(single)
	add_terrain_entry(_collision_entry_terrain())
	add_terrain_entry(_data_entry_terrain())

	var grouped := {"": []}
	for group in groups_by_name:
		grouped[group] = []
	for id in BetterTerrain.get_terrain_display_order(tileset):
		var terrain := BetterTerrain.get_terrain(tileset, id)
		grouped[_display_group_of(terrain)].append(terrain)
	for terrain in grouped[""]:
		add_terrain_entry(terrain)
	var scenes := _scene_tiles() if _scenes_shown() else []
	_scenes_by_group.clear()
	for scene in scenes:
		for group in BetterTerrain.get_scene_tile_groups(tileset, scene.source, scene.id):
			if not _scenes_by_group.has(group):
				_scenes_by_group[group] = []
			_scenes_by_group[group].push_back(scene)
	for group in groups_by_name:
		if not _group_shown(group):
			continue
		terrain_list.add_child(_make_group_header(groups_by_name[group]))
		var group_scenes: Array = _scenes_by_group.get(group, [])
		if grouped[group].is_empty() and group_scenes.is_empty():
			var space := Control.new()
			space.name = "EmptyTerrainGroup"
			space.custom_minimum_size = Vector2(_list_row_width(), 60)
			space.mouse_filter = Control.MOUSE_FILTER_IGNORE
			space.set_meta(GROUP_META, group)
			space.set_meta(&"empty_terrain_group", true)
			terrain_list.add_child(space)
		for terrain in grouped[group]:
			add_terrain_entry(terrain)
		for scene in group_scenes:
			_add_scene_entry(scene, group)
	_add_scene_entries(scenes)

	_rebuild_group_bar()
	_update_group_header_widths()
	_apply_entry_filters()

	if selected_entry >= 0:
		var entry = _entry_for_id(selected_entry)
		if entry:
			entry.set_selected(true)
	elif selected_entry in [COLLISION_ENTRY, DATA_ENTRY]:
		var entry = _entry_for_id(selected_entry)
		if entry:
			entry.selected = true
			entry.queue_redraw()
	_sync_scene_selection()


func add_terrain_entry(terrain:Dictionary):
	var entry = TERRAIN_ENTRY_SCENE.instantiate()
	entry.tileset = tileset
	entry.terrain = terrain
	entry.grid_mode = grid_mode_button.button_pressed
	var settings := EditorInterface.get_editor_settings()
	entry.show_type_icon = not (settings.has_setting(HIDE_TYPE_ICONS_SETTING) and bool(settings.get_setting(HIDE_TYPE_ICONS_SETTING)))
	entry.select.connect(_on_entry_select)
	entry.edit_requested.connect(_on_entry_edit_requested)
	entry.context_requested.connect(func(id): _open_terrain_context(_display_group_of(terrain), id))
	entry.dropped_on.connect(func(source_id: int, target_id: int) -> void:
		_drop_terrain_into_group(source_id, _display_group_of(BetterTerrain.get_terrain(tileset, target_id))))
	entry.set_meta(GROUP_META, _display_group_of(terrain))

	terrain_list.add_child(entry)


func _entry_for_id(id: int):
	for c in terrain_list.get_children():
		if c.has_method("terrain_id") and c.terrain_id() == id and not c.has_meta(SCENE_META):
			return c
	return null


#region Scene tiles

func _scenes_shown() -> bool:
	var settings := EditorInterface.get_editor_settings()
	return not (settings.has_setting(HIDE_SCENES_SETTING) and bool(settings.get_setting(HIDE_SCENES_SETTING)))


static func _scene_key(source_id: int, scene_id: int) -> String:
	return "%d:%d" % [source_id, scene_id]


## Every scene tile of the tile set: {source, id, scene, name}.
func _scene_tiles() -> Array:
	var result := []
	for i in tileset.get_source_count():
		var source_id := tileset.get_source_id(i)
		var source := tileset.get_source(source_id) as TileSetScenesCollectionSource
		if source == null:
			continue
		for n in source.get_scene_tiles_count():
			var scene_id := source.get_scene_tile_id(n)
			var scene := source.get_scene_tile_scene(scene_id)
			if scene == null:
				continue
			var scene_name := scene.resource_path.get_file().get_basename()
			result.push_back({source = source_id, id = scene_id, scene = scene,
				name = scene_name if not scene_name.is_empty() else "Scene %d" % scene_id})
	return result


func _add_scene_entries(scenes: Array) -> void:
	if scenes.is_empty() or not BetterTerrain.get_terrain(tileset, BetterTerrain.TileCategory.SINGLE).valid:
		return
	terrain_list.add_child(_make_scenes_header())
	for scene in scenes:
		_add_scene_entry(scene, SCENES_GROUP)


## Scene tiles paint through the Single tile brush, so each entry is a Single tile entry.
func _add_scene_entry(scene: Dictionary, group: String) -> void:
	var single := BetterTerrain.get_terrain(tileset, BetterTerrain.TileCategory.SINGLE)
	if not single.valid:
		return
	var key := _scene_key(scene.source, scene.id)
	var terrain := single.duplicate()
	terrain.name = scene.name
	terrain.scene = {source = scene.source, id = scene.id, path = scene.scene.resource_path}
	var sprite := _scene_sprite(scene.scene)
	if sprite != null:
		_scene_thumbnails[key] = sprite
		_scene_sprite_keys[key] = true
	if _scene_thumbnails.has(key):
		terrain.thumbnail = _scene_thumbnails[key]
	var settings := EditorInterface.get_editor_settings()
	var entry = TERRAIN_ENTRY_SCENE.instantiate()
	entry.tileset = tileset
	entry.terrain = terrain
	entry.grid_mode = grid_mode_button.button_pressed
	entry.show_type_icon = not (settings.has_setting(HIDE_TYPE_ICONS_SETTING) and bool(settings.get_setting(HIDE_TYPE_ICONS_SETTING)))
	entry.select.connect(func(_id): _on_scene_entry_select(entry))
	entry.context_requested.connect(func(_id): _open_scene_context(entry))
	entry.set_meta(GROUP_META, group)
	entry.set_meta(SCENE_META, key)
	terrain_list.add_child(entry)
	if not _scene_thumbnails.has(key) and not scene.scene.resource_path.is_empty():
		EditorInterface.get_resource_previewer().queue_resource_preview(
			scene.scene.resource_path, self, &"_on_scene_preview", key)


const SCENE_SPRITE_DEPTH := 4


## Reads the scene state so no script runs; instanced scenes are searched too.
static func _scene_sprite(scene: PackedScene, depth := 0) -> Texture2D:
	if scene == null or depth > SCENE_SPRITE_DEPTH:
		return null
	var state := scene.get_state()
	for i in state.get_node_count():
		var props := {}
		for p in state.get_node_property_count(i):
			props[state.get_node_property_name(i, p)] = state.get_node_property_value(i, p)
		if not bool(props.get("visible", true)):
			continue
		var type := String(state.get_node_type(i))
		var texture: Texture2D = null
		if type == "Sprite2D":
			texture = _sprite_frame(props)
		elif type == "AnimatedSprite2D":
			var frames: SpriteFrames = props.get("sprite_frames")
			var animation := StringName(props.get("animation", &"default"))
			if frames != null and frames.has_animation(animation) and frames.get_frame_count(animation) > 0:
				texture = frames.get_frame_texture(animation, clampi(int(props.get("frame", 0)), 0, frames.get_frame_count(animation) - 1))
		elif type == "TextureRect":
			texture = props.get("texture")
		elif type.is_empty() or state.get_node_instance(i) != null:
			texture = _scene_sprite(state.get_node_instance(i), depth + 1)
		if texture != null:
			return texture
	return null


static func _sprite_frame(props: Dictionary) -> Texture2D:
	var texture: Texture2D = props.get("texture")
	if texture == null:
		return null
	var area := Rect2(Vector2.ZERO, texture.get_size())
	if bool(props.get("region_enabled", false)):
		area = props.get("region_rect", area)
	var frames := Vector2i(maxi(1, int(props.get("hframes", 1))), maxi(1, int(props.get("vframes", 1))))
	var cell := area.size / Vector2(frames)
	var frame := int(props.get("frame", 0))
	@warning_ignore("integer_division")
	var at: Vector2i = props.get("frame_coords", Vector2i(frame % frames.x, frame / frames.x))
	var atlas := AtlasTexture.new()
	atlas.atlas = texture
	atlas.region = Rect2(area.position + cell * Vector2(at), cell)
	return atlas


func _make_scenes_header() -> Control:
	var header := HBoxContainer.new()
	header.set_script(GROUP_HEADER_SCRIPT)
	header.set_meta(GROUP_META, SCENES_GROUP)
	var icon := TextureRect.new()
	icon.texture = get_theme_icon("PackedScene", "EditorIcons")
	icon.custom_minimum_size = Vector2(14, 14)
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	header.setup(SCENES_GROUP, _collapsed.has(SCENES_GROUP), icon,
		get_theme_color("font_disabled_color", "Editor"), "Scenes")
	header.accepts_terrains = false
	header.tooltip_text = "Scene tiles of this tile set. They paint like a single tile."
	header.set_row_width(_available_list_width(), _list_row_width())
	header.collapse_toggled.connect(_on_group_collapse_toggled)
	return header


func _on_scene_preview(_path: String, preview: Texture2D, _thumbnail: Texture2D, key: Variant) -> void:
	if preview == null:
		return
	_scene_thumbnails[key] = preview
	if terrain_list == null:
		return
	for c in terrain_list.get_children():
		if c.get_meta(SCENE_META, "") == key:
			c.set_scene_thumbnail(preview)
	update_overlay.emit()


## A scene tile always stays under Scenes; dropping it on Scenes removes it from its source group.
func _drop_scene_into_group(key: String, from_group: String, to_group: String) -> void:
	if tileset == null or to_group.is_empty() or from_group == to_group:
		return
	var scene := _scene_from_key(key)
	var groups := BetterTerrain.get_scene_tile_groups(tileset, scene.x, scene.y)
	var next := groups.duplicate()
	if from_group != SCENES_GROUP:
		next.erase(from_group)
	if to_group != SCENES_GROUP and not next.has(to_group):
		next.push_back(to_group)
	_commit_scene_groups(scene, groups, next)


func _scene_from_key(key: String) -> Vector2i:
	var parts := key.split(":")
	return Vector2i(int(parts[0]), int(parts[1]))


func _commit_scene_groups(scene: Vector2i, before: Array, after: Array) -> void:
	if before == after:
		return
	undo_manager.create_action(tr("Change the groups of a scene tile"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(BetterTerrain, &"set_scene_tile_groups", tileset, scene.x, scene.y, after)
	undo_manager.add_undo_method(BetterTerrain, &"set_scene_tile_groups", tileset, scene.x, scene.y, before)
	undo_manager.add_do_method(self, &"rebuild_terrain_list")
	undo_manager.add_undo_method(self, &"rebuild_terrain_list")
	undo_manager.commit_action()


func _open_scene_context(entry: Control) -> void:
	var key: String = entry.get_meta(SCENE_META)
	var group: String = entry.get_meta(GROUP_META)
	var scene := _scene_from_key(key)
	var groups := BetterTerrain.get_scene_tile_groups(tileset, scene.x, scene.y)
	var names := []
	for g in BetterTerrain.get_terrain_groups(tileset):
		if _group_shown(g.name):
			names.push_back(g.name)
	var menu := PopupMenu.new()
	menu.name = "SceneContextMenu"
	add_child(menu)
	menu.add_separator("Also show in")
	for i in names.size():
		menu.add_check_item(names[i], i)
		menu.set_item_checked(menu.get_item_index(i), groups.has(names[i]))
	if names.is_empty():
		menu.add_item("No groups yet", -1)
		menu.set_item_disabled(menu.item_count - 1, true)
	const REMOVE := 100000
	if group != SCENES_GROUP:
		menu.add_separator()
		menu.add_item("Remove from %s" % group, REMOVE)
	menu.id_pressed.connect(func(id: int) -> void:
		var next := groups.duplicate()
		if id == REMOVE:
			next.erase(group)
		elif next.has(names[id]):
			next.erase(names[id])
		else:
			next.push_back(names[id])
		_commit_scene_groups(scene, groups, next))
	menu.popup_hide.connect(menu.queue_free)
	menu.position = Vector2i(get_screen_transform() * get_local_mouse_position())
	menu.popup()


func _on_scene_entry_select(entry: Control) -> void:
	_on_entry_select(BetterTerrain.TileCategory.SINGLE)
	var scene: Dictionary = entry.terrain.scene
	_set_single_tile(scene.source, Vector2i.ZERO, Vector2i.ONE, scene.id)
	_sync_scene_selection()


func _sync_scene_selection() -> void:
	if tileset == null:
		return
	var single := selected_entry == BetterTerrain.TileCategory.SINGLE
	var block: Dictionary = BetterTerrain.single_block_of(tileset, selected_entry) if single else {}
	var on_scene := false
	for c in terrain_list.get_children():
		if not c.has_meta(SCENE_META):
			continue
		var scene: Dictionary = c.terrain.scene
		var hit: bool = not block.is_empty() and block.source == scene.source and block.alt == scene.id
		on_scene = on_scene or hit
		c.selected = hit
		c.queue_redraw()
	if single:
		var entry = _entry_for_id(BetterTerrain.TileCategory.SINGLE)
		if entry:
			entry.selected = not on_scene
			entry.queue_redraw()

#endregion


func _group_siblings(id: int) -> Array:
	var group := _display_group_of(BetterTerrain.get_terrain(tileset, id))
	var result := []
	for other in BetterTerrain.get_terrain_display_order(tileset):
		if _display_group_of(BetterTerrain.get_terrain(tileset, other)) == group:
			result.push_back(other)
	return result


func perform_add_terrain(terrain_name: String, color: Color, type: int, categories: Array, icon:Dictionary = {}, group: String = "", object: Dictionary = {}) -> void:
	# Undo may restore a terrain after its group was deleted; restore it ungrouped.
	if !group.is_empty() and !_known_groups.has(group):
		group = ""

	if BetterTerrain.add_terrain(tileset, terrain_name, color, type, categories, icon, group, object):
		rebuild_terrain_list()
		_select_terrain(BetterTerrain.terrain_count(tileset) - 1)
		_warn_duplicate_name(terrain_name)


func _select_terrain(id: int) -> void:
	if id < 0:
		return
	for c in terrain_list.get_children():
		if c.has_method("terrain_id") and c.terrain_id() == id:
			if !c.visible:
				return
			c.set_selected(true)
			c.grab_focus()
			return


func perform_remove_terrain(index: int) -> void:
	if index >= BetterTerrain.terrain_count(tileset):
		return
	if BetterTerrain.remove_terrain(tileset, index):
		rebuild_terrain_list()
		update_tile_view_paint()


func perform_swap_terrain(index1: int, index2: int) -> void:
	var lower := mini(index1, index2)
	var higher := maxi(index1, index2)
	var count := BetterTerrain.terrain_count(tileset)
	if lower < 0 or higher >= count:
		return

	if BetterTerrain.swap_terrains(tileset, lower, higher):
		selected_entry = index2
		rebuild_terrain_list()
		update_tile_view_paint()


func perform_edit_terrain(index: int, terrain_name: String, color: Color, type: int, categories: Array, icon: Dictionary = {}, group = null, object: Dictionary = {}) -> void:
	if index >= BetterTerrain.terrain_count(tileset):
		return
	# don't overwrite empty icon
	var valid_icon = icon
	if icon.has("path") and icon.path.is_empty():
		var terrain = BetterTerrain.get_terrain(tileset, index)
		valid_icon = terrain.icon
	if BetterTerrain.set_terrain(tileset, index, terrain_name, color, type, categories, valid_icon, group, object):
		rebuild_terrain_list()
		tile_view.queue_redraw()
	_warn_duplicate_name(terrain_name)


func _on_shuffle_random_pressed():
	BetterTerrain.use_seed = !shuffle_random.button_pressed 


func _on_bit_button_pressed(_button: BaseButton) -> void:
	match select_tiles.button_group.get_pressed_button():
		select_tiles: tile_view.paint_mode = tile_view.PaintMode.SELECT
		paint_type: tile_view.paint_mode = tile_view.PaintMode.PAINT_TYPE
		paint_terrain: tile_view.paint_mode = tile_view.PaintMode.PAINT_PEERING
		paint_symmetry: tile_view.paint_mode = tile_view.PaintMode.PAINT_SYMMETRY
		object_lone: tile_view.paint_mode = tile_view.PaintMode.PAINT_OBJECT_LONE
		object_joined: tile_view.paint_mode = tile_view.PaintMode.PAINT_OBJECT_JOINED
		_: tile_view.paint_mode = tile_view.PaintMode.NO_PAINT
	tile_view.queue_redraw()
	
	symmetry_options.visible = paint_symmetry.button_pressed


func _on_symmetry_selected(index):
	tile_view.paint_symmetry = index


func _on_paste_occurred():
	select_tiles.button_pressed = true


func _on_change_zoom_level(value):
	zoom_slider.value = value


func _on_terrain_updated(index):
	var entry = _entry_for_id(index)
	if !entry:
		return
	entry.terrain = BetterTerrain.get_terrain(tileset, index)
	entry.update()


func canvas_tilemap_transform() -> Transform2D:
	if not tilemap or not tilemap.is_inside_tree():
		return Transform2D.IDENTITY
	
	var transform := tilemap.get_viewport_transform() * tilemap.global_transform
	
	# Handle subviewport
	var editor_viewport := EditorInterface.get_editor_viewport_2d()
	if tilemap.get_viewport() != editor_viewport:
		var container = tilemap.get_viewport().get_parent() as SubViewportContainer
		if container:
			transform = editor_viewport.global_canvas_transform * container.get_transform() * transform
	
	return transform


func canvas_draw(overlay: Control) -> void:
	if not tilemap or not tilemap.is_inside_tree():
		return

	var transform := canvas_tilemap_transform()
	_measure_view(overlay, transform)

	if layer_stale:
		var used := tilemap.get_used_rect()
		if used.size.x > 0 and used.size.y > 0:
			var frame := PackedVector2Array([
				tilemap.map_to_local(used.position),
				tilemap.map_to_local(Vector2i(used.end.x, used.position.y)),
				tilemap.map_to_local(used.end),
				tilemap.map_to_local(Vector2i(used.position.x, used.end.y)),
			])
			frame = transform * frame
			var warn := Color(1.0, 0.6, 0.1)
			overlay.draw_colored_polygon(frame, Color(warn, 0.07))
			var outline := frame.duplicate()
			outline.push_back(frame[0])
			overlay.draw_polyline(outline, warn, 2.0)

	if _is_scatter(selected_entry) and tilemap.tile_set != null:
		var zone: Array = SCATTER_TERRAIN.zone_cells(tilemap, selected_entry)
		if not zone.is_empty() and zone.size() <= MAX_CANVAS_RENDER_TILES:
			var t = BetterTerrain.get_terrain(tileset, selected_entry)
			var zone_tint := Color(t.color, 0.20)
			var zone_size := Vector2(tilemap.tile_set.tile_size)
			for c: Vector2i in zone:
				var cell := PackedVector2Array([
					tilemap.map_to_local(c) - zone_size * 0.5,
					tilemap.map_to_local(c) + Vector2(zone_size.x, -zone_size.y) * 0.5,
					tilemap.map_to_local(c) + zone_size * 0.5,
					tilemap.map_to_local(c) + Vector2(-zone_size.x, zone_size.y) * 0.5,
				])
				overlay.draw_colored_polygon(transform * cell, zone_tint)

	var status_font := get_theme_font("font", "Label")
	if status_font != null:
		var fsize := get_theme_font_size("font_size", "Label")
		var line := _map_status_line()
		var w := status_font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize).x
		var at := Vector2(22, overlay.size.y - 14)
		overlay.draw_rect(Rect2(at.x - 6, at.y - fsize - 4, w + 12, fsize + 12),
			Color(0, 0, 0, 0.55))
		overlay.draw_string(status_font, at, line, HORIZONTAL_ALIGNMENT_LEFT, -1, fsize,
			Color(0.85, 0.92, 1.0))

	if _collision_mode():
		_draw_map_collisions(overlay, transform)
		return
	if _data_mode():
		_draw_map_data(overlay, transform)
		return

	if _map_select_active() and not _map_sel.is_empty():
		var mesh := _map_selection_mesh(Rect2(Vector2.ZERO, overlay.size), transform)
		if not mesh.indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(overlay.get_canvas_item(), mesh.indices, mesh.points, mesh.colors)

	if _map_selecting and tilemap.tile_set != null:
		var sel := Rect2i(_map_select_from, current_position - _map_select_from).abs()
		var box := PackedVector2Array([
			tilemap.map_to_local(sel.position) - Vector2(tilemap.tile_set.tile_size) * 0.5,
			tilemap.map_to_local(Vector2i(sel.end.x, sel.position.y)) + Vector2(tilemap.tile_set.tile_size.x, -tilemap.tile_set.tile_size.y) * 0.5,
			tilemap.map_to_local(sel.end) + Vector2(tilemap.tile_set.tile_size) * 0.5,
			tilemap.map_to_local(Vector2i(sel.position.x, sel.end.y)) + Vector2(-tilemap.tile_set.tile_size.x, tilemap.tile_set.tile_size.y) * 0.5,
		])
		box = transform * box
		overlay.draw_colored_polygon(box, Color(0.4, 0.8, 1.0, 0.12))
		var line := box.duplicate()
		line.push_back(box[0])
		overlay.draw_polyline(line, Color(0.4, 0.8, 1.0), 2.0)

	# Picking doesn't paint, so no brush preview.
	if not draw_overlay or _map_select_active() or picker_armed():
		return

	if selected_entry < 0 and selected_entry != BetterTerrain.TileCategory.SINGLE \
			and paint_mode != PaintMode.ERASE:
		return

	var type = selected_entry
	var terrain := BetterTerrain.get_terrain(tileset, type)
	if !terrain.valid and paint_mode != PaintMode.ERASE:
		return

	var tiles := []

	var erasing: bool = paint_mode == PaintMode.ERASE
	var tint: Color = Color(0.95, 0.35, 0.3) if erasing else terrain.color

	if paint_action == PaintAction.RECT and paint_mode != PaintMode.NO_PAINT:
		var area := Rect2i(initial_click, current_position - initial_click).abs()
		var box := PackedVector2Array([
			tilemap.map_to_local(area.position),
			tilemap.map_to_local(Vector2i(area.end.x, area.position.y)),
			tilemap.map_to_local(area.end),
			tilemap.map_to_local(Vector2i(area.position.x, area.end.y))
		])
		box = transform * box

		# Shortcut fill for large areas
		if not ObjectTerrain.is_mass(tileset, type) and area.size.x > 1 and area.size.y > 1 and area.size.x * area.size.y > MAX_CANVAS_RENDER_TILES:
			overlay.draw_colored_polygon(box, Color(tint, 0.5))
			_draw_outline(overlay, box, tint)
			return

		for y in range(area.position.y, area.end.y + 1):
			for x in range(area.position.x, area.end.x + 1):
				tiles.append(Vector2i(x, y))
		_draw_outline(overlay, box, tint)
	elif paint_action == PaintAction.SLOPE and paint_mode != PaintMode.NO_PAINT:
		_draw_slope_preview(overlay, transform, _slope_plan())
		return
	elif paint_action == PaintAction.LINE and paint_mode != PaintMode.NO_PAINT:
		var cells := _object_brush_cells(type, _get_tileset_line(initial_click, current_position, tileset))
		var line_shape = BetterTerrain.data.cell_polygon(tileset)
		for c in cells:
			var tile_transform := Transform2D(0.0, tilemap.tile_set.tile_size, 0.0, tilemap.map_to_local(c))
			overlay.draw_colored_polygon(transform * tile_transform * line_shape, Color(tint, 0.5))
			_draw_outline(overlay, transform * tile_transform * line_shape, tint)
	elif fill_button.button_pressed:
		tiles = _get_fill_cells(current_position)
		if tiles.size() > MAX_CANVAS_RENDER_TILES:
			tiles.resize(MAX_CANVAS_RENDER_TILES)
	else:
		if draw_button != null and draw_button.button_pressed:
			tiles.append_array(_brush_cells([current_position]))
		else:
			tiles.append(current_position)
	
	tiles = _object_brush_cells(type, tiles)

	if _is_single(type) and not erasing:
		var anchor: Vector2i = initial_click if paint_mode != PaintMode.NO_PAINT else current_position
		tiles = _single_cells(type, tiles, anchor)
		if _draw_single_preview(overlay, transform, tiles, anchor):
			return

	var shape = BetterTerrain.data.cell_polygon(tileset)
	for t in tiles:
		var tile_transform := Transform2D(0.0, tilemap.tile_set.tile_size, 0.0, tilemap.map_to_local(t))
		overlay.draw_colored_polygon(transform * tile_transform * shape, Color(tint, 0.5))


func _measure_view(overlay: Control, transform: Transform2D) -> void:
	if tilemap == null or tilemap.tile_set == null or overlay == null:
		return
	var back := transform.affine_inverse()
	var corners := [Vector2.ZERO, Vector2(overlay.size.x, 0), overlay.size, Vector2(0, overlay.size.y)]
	var lo := Vector2i(1 << 30, 1 << 30)
	var hi := Vector2i(-(1 << 30), -(1 << 30))
	for c in corners:
		var cell: Vector2i = tilemap.local_to_map(back * c)
		lo = Vector2i(mini(lo.x, cell.x), mini(lo.y, cell.y))
		hi = Vector2i(maxi(hi.x, cell.x), maxi(hi.y, cell.y))
	_view_cells = Rect2i(lo - Vector2i.ONE, hi - lo + Vector2i(3, 3))


func _draw_single_preview(overlay: Control, transform: Transform2D, cells: Array,
		anchor: Vector2i) -> bool:
	var block: Dictionary = BetterTerrain.single_block_of(tileset, selected_entry)
	if block.is_empty() or cells.is_empty():
		return false
	var cell_size := Vector2(tilemap.tile_set.tile_size)
	if tileset.get_source(block.source) is TileSetScenesCollectionSource:
		var key := _scene_key(block.source, block.alt)
		var thumbnail: Texture2D = _scene_thumbnails.get(key)
		if thumbnail == null:
			return false
		var drawn := thumbnail.get_size() if _scene_sprite_keys.has(key) else cell_size
		overlay.draw_set_transform_matrix(transform)
		for c: Vector2i in cells:
			overlay.draw_texture_rect(thumbnail, Rect2(tilemap.map_to_local(c) - drawn * 0.5, drawn), false, Color(1, 1, 1, 0.7))
		overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
		return true
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	if src == null or src.texture == null:
		return false

	overlay.draw_set_transform_matrix(transform)
	for c: Vector2i in cells:
		var atlas: Vector2i = BetterTerrain._single_at(block, c, anchor)
		if src.get_tile_at_coords(atlas) != atlas:
			continue
		var region: Rect2i = src.get_tile_texture_region(atlas, block.alt)
		var at := Rect2(tilemap.map_to_local(c) - cell_size * 0.5, cell_size)
		overlay.draw_texture_rect_region(src.texture, at, region, Color(1, 1, 1, 0.7))
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
	return true


func _draw_outline(overlay: Control, poly: PackedVector2Array, color: Color) -> void:
	if poly.size() < 2:
		return
	var line := poly.duplicate()
	line.push_back(poly[0])
	overlay.draw_polyline(line, Color(color, 0.9), 2.0)


func canvas_input(event: InputEvent) -> bool:
	if not tilemap:
		return false
	if _collision_mode() or _data_mode():
		return _collision_canvas_input(event)
	# The WM can swallow a key release (Alt+click); mouse events carry the real modifiers
	if event is InputEventMouse:
		_modifier_stale = _raw_modifier_down() and not _picker_modifier_held(event)
	elif event is InputEventKey:
		_modifier_stale = false
	# Locked support layers can be selected but not painted.
	if SUPPORT_LAYERS.is_locked(tilemap) and event is InputEventMouseButton and not _is_pick_click(event):
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return false
		if event.pressed:
			_ask_unlock(tilemap)
		return true

	if event is InputEventMouseMotion and paint_mode != PaintMode.NO_PAINT:
		var mask := MOUSE_BUTTON_MASK_RIGHT if paint_mode == PaintMode.ERASE else MOUSE_BUTTON_MASK_LEFT
		if (event.button_mask & mask) == 0:
			cancel_paint()
			return true
	if selected_entry < 0 and selected_entry != BetterTerrain.TileCategory.SINGLE \
			and not _map_select_active() and paint_mode != PaintMode.ERASE \
			and not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT) \
			and not _is_pick_click(event):
		return false
	
	draw_overlay = true
	if event is InputEventMouseMotion or event is InputEventMouseButton:
		var canvas_xform := canvas_tilemap_transform()
		var pos := canvas_xform.affine_inverse() * Vector2(event.position)
		var event_position := tilemap.local_to_map(pos)
		_mouse_local = pos
		if paint_action == PaintAction.SLOPE and paint_mode != PaintMode.NO_PAINT and _freehand():
			_free_trail = SLOPE_TERRAIN.free_trail(_free_start, _free_trail, _free_target(), event.shift_pressed,
				_free_smooth())
		prev_position = current_position
		if event is InputEventMouseMotion and event_position == current_position:
			if paint_action == PaintAction.SLOPE and paint_mode != PaintMode.NO_PAINT:
				update_overlay.emit()
			return false
		current_position = event_position
		update_overlay.emit()
	
	if _map_select_active():
		# Handle map shortcuts only in the viewport; Ctrl+X elsewhere may cut scene nodes.
		if event is InputEventKey and event.pressed and not event.echo:
			var ctrl: bool = event.is_command_or_control_pressed()
			match event.keycode:
				KEY_X when ctrl:
					_on_map_sel_action(MapSelAction.CUT)
					return true
				KEY_C when ctrl:
					_on_map_sel_action(MapSelAction.COPY)
					return true
				KEY_V when ctrl:
					_on_map_sel_action(MapSelAction.PASTE)
					return true
				KEY_D when ctrl:
					_on_map_sel_action(MapSelAction.DUPLICATE)
					return true
				KEY_DELETE:
					_on_map_sel_action(MapSelAction.DELETE)
					return true
				KEY_ESCAPE:
					_clear_map_selection()
					return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			_popup_map_menu(get_viewport().get_mouse_position() if get_viewport() else Vector2.ZERO)
			return true
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				_map_sel_mode = 0
				if event.shift_pressed:
					_map_sel_mode = 1
				elif event.is_command_or_control_pressed():
					_map_sel_mode = -1
				if _map_sel_mode == 0 and current_position in _map_sel:
					_map_drag = true
					_map_drag_from = current_position
					_map_drag_delta = Vector2i.ZERO
				else:
					_map_select_from = current_position
					_map_selecting = true
			elif _map_drag:
				_map_drag = false
				if _map_drag_delta != Vector2i.ZERO:
					_copy_map_selection()
					_map_paste_at(_map_sel_rect.position + _map_drag_delta, _map_sel.duplicate(), "Move tiles")
				_map_drag_delta = Vector2i.ZERO
			elif _map_selecting:
				_map_selecting = false
				_capture_map_selection(_map_select_from, current_position, _map_sel_mode)
			update_overlay.emit()
			return true
		if event is InputEventMouseMotion and _map_drag:
			_map_drag_delta = current_position - _map_drag_from
			update_overlay.emit()
			return true
		return event is InputEventMouseMotion and _map_selecting
	
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return false
		var active_button := MOUSE_BUTTON_RIGHT if paint_mode == PaintMode.ERASE else MOUSE_BUTTON_LEFT
		if paint_mode != PaintMode.NO_PAINT and event.button_index != active_button:
			return true
		if not event.pressed and paint_mode == PaintMode.NO_PAINT:
			return false

	var replace_mode = replace_button.button_pressed
	
	var released : bool = event is InputEventMouseButton and !event.pressed
	if released:
		terrain_undo.finish_action()
		var type = selected_entry
		if _is_scatter(type) and paint_mode == PaintMode.PAINT \
				and paint_action in [PaintAction.RECT, PaintAction.LINE]:
			var scatter_cells: Array = _cells_in_area(Rect2i(initial_click, current_position - initial_click).abs()) \
				if paint_action == PaintAction.RECT \
				else _get_tileset_line(initial_click, current_position, tileset)
			undo_manager.create_action(tr("Paint scatter region"), UndoRedo.MERGE_DISABLE, tilemap)
			_scatter_paint(scatter_cells, false, false)
			undo_manager.commit_action()
			paint_mode = PaintMode.NO_PAINT
			update_overlay.emit()
			return true
		if paint_action == PaintAction.RECT and paint_mode != PaintMode.NO_PAINT:
			var area := Rect2i(initial_click, current_position - initial_click).abs()
			# Fill from initial_target to target
			undo_manager.create_action(tr("Draw terrain rectangle"), UndoRedo.MERGE_DISABLE, tilemap)
			var rectangle_cells := _object_brush_cells(type, _cells_in_area(area))
			if ObjectTerrain.is_mass(tileset, type):
				if paint_mode == PaintMode.ERASE:
					for c in rectangle_cells:
						undo_manager.add_do_method(tilemap, &"erase_cell", c)
				elif replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, rectangle_cells, type)
				else:
					undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, rectangle_cells, type)
			elif _is_single(type) and paint_mode == PaintMode.PAINT:
				var box := _single_cells(type, _cells_in_area(area), initial_click)
				if replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, box, type, initial_click)
				else:
					undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, box, type, initial_click)
			else:
				for coord in rectangle_cells:
					if paint_mode == PaintMode.PAINT:
						if replace_mode:
							undo_manager.add_do_method(BetterTerrain, &"replace_cell", tilemap, coord, type)
						else:
							undo_manager.add_do_method(BetterTerrain, &"set_cell", tilemap, coord, type)
					else:
						undo_manager.add_do_method(tilemap, &"erase_cell", coord)
			
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, area)
			_add_post_process(rectangle_cells, paint_mode == PaintMode.ERASE, false)
			if ObjectTerrain.has_mass(tileset):
				terrain_undo.create_tile_restore_point(undo_manager, tilemap, _restore_cells(rectangle_cells))
			terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, area.grow(2))
			undo_manager.commit_action()
			update_overlay.emit()
		elif paint_action == PaintAction.SLOPE and paint_mode != PaintMode.NO_PAINT:
			_apply_slope(_slope_plan())
		elif paint_action == PaintAction.LINE and paint_mode != PaintMode.NO_PAINT:
			undo_manager.create_action(tr("Draw terrain line"), UndoRedo.MERGE_DISABLE, tilemap)
			var cells := _single_cells(type, _object_brush_cells(type, _get_tileset_line(initial_click, current_position, tileset)), initial_click)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, cells, type, initial_click)
				else:
					undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, cells, type, initial_click)
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					undo_manager.add_do_method(tilemap, &"erase_cell", c)
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_cells", tilemap, cells)
			_add_post_process(cells, paint_mode == PaintMode.ERASE, false)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, _restore_cells(cells))
			undo_manager.commit_action()
			update_overlay.emit()
		
		paint_mode = PaintMode.NO_PAINT
		return true
	
	var clicked : bool = event is InputEventMouseButton and event.pressed
	if clicked:
		paint_mode = PaintMode.NO_PAINT
		
		if _is_pick_click(event):
			_pick_at(current_position)
			return true
		if _picker_active():
			return true
		
		paint_action = PaintAction.NO_ACTION
		if rectangle_button.button_pressed:
			paint_action = PaintAction.RECT
		elif line_button.button_pressed:
			paint_action = PaintAction.LINE
		elif _slope_button != null and _slope_button.button_pressed:
			paint_action = PaintAction.SLOPE
		elif draw_button.button_pressed:
			if event.shift_pressed:
				paint_action = PaintAction.LINE
				if event.is_command_or_control_pressed():
					paint_action = PaintAction.RECT
		
		if event.button_index == MOUSE_BUTTON_LEFT:
			paint_mode = PaintMode.PAINT
		elif event.button_index == MOUSE_BUTTON_RIGHT:
			paint_mode = PaintMode.ERASE
			# Freehand erases like the pencil, cell by cell under the mouse
			if paint_action == PaintAction.SLOPE and _freehand():
				paint_action = PaintAction.NO_ACTION
		else:
			return false
	
	if (clicked or event is InputEventMouseMotion) and paint_mode != PaintMode.NO_PAINT:
		if clicked:
			initial_click = current_position
			prev_position = current_position
			_free_start = Vector2i(_free_target().round())
			_free_trail = [_free_target()]
			terrain_undo.action_index += 1
			terrain_undo.action_count = 0
		# Shift mid-stroke turns the rest into a line from where it was pressed, drawn on release.
		if event is InputEventMouseMotion and draw_button.button_pressed \
				and paint_action == PaintAction.NO_ACTION and event.shift_pressed \
				and not event.is_command_or_control_pressed():
			terrain_undo.finish_action()
			paint_action = PaintAction.LINE
			initial_click = prev_position
			update_overlay.emit()
			return true
		var type = selected_entry

		if _is_scatter(type) and paint_mode == PaintMode.PAINT \
				and paint_action == PaintAction.NO_ACTION \
				and (draw_button.button_pressed or fill_button.button_pressed):
			var brushing := draw_button.button_pressed
			var scatter_cells: Array = _brush_cells(_get_tileset_line(prev_position, current_position, tileset)) \
				if brushing else _get_fill_cells(current_position)
			if brushing:
				undo_manager.create_action(tr("Paint scatter region") + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tilemap, true)
			else:
				undo_manager.create_action(tr("Fill scatter region"), UndoRedo.MERGE_DISABLE, tilemap)
			_scatter_paint(scatter_cells, false, brushing)
			undo_manager.commit_action()
			if brushing:
				terrain_undo.action_count += 1
			update_overlay.emit()
			return true

		if paint_action in [PaintAction.LINE, PaintAction.RECT, PaintAction.SLOPE]:
			# if painting as line, execution happens on release. 
			# prevent other painting actions from running.
			pass
		elif draw_button.button_pressed or (paint_mode == PaintMode.ERASE and _slope_button != null \
				and _slope_button.button_pressed and _freehand()):
			undo_manager.create_action(tr("Draw terrain") + str(terrain_undo.action_index), UndoRedo.MERGE_ALL, tilemap, true)
			var stroke := _object_brush_cells(type, _brush_cells(_get_tileset_line(prev_position, current_position, tileset)))
			var cells := _single_cells(type, stroke, initial_click)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					terrain_undo.add_do_method(undo_manager, BetterTerrain, &"replace_cells", [tilemap, cells, type, initial_click])
				else:
					terrain_undo.add_do_method(undo_manager, BetterTerrain, &"set_cells", [tilemap, cells, type, initial_click])
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					terrain_undo.add_do_method(undo_manager, tilemap, &"erase_cell", [c])
			terrain_undo.add_do_method(undo_manager, BetterTerrain, &"update_terrain_cells", [tilemap, cells])
			_add_post_process(cells, paint_mode == PaintMode.ERASE, true)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, _restore_cells(cells))
			undo_manager.commit_action()
			terrain_undo.action_count += 1
		elif fill_button.button_pressed:
			var cells := _single_cells(type, _object_brush_cells(type, _get_fill_cells(current_position)), current_position)
			undo_manager.create_action(tr("Fill terrain"), UndoRedo.MERGE_DISABLE, tilemap)
			if paint_mode == PaintMode.PAINT:
				if replace_mode:
					undo_manager.add_do_method(BetterTerrain, &"replace_cells", tilemap, cells, type, current_position)
				else:
					undo_manager.add_do_method(BetterTerrain, &"set_cells", tilemap, cells, type, current_position)
			elif paint_mode == PaintMode.ERASE:
				for c in cells:
					undo_manager.add_do_method(tilemap, &"erase_cell", c)
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_cells", tilemap, cells)
			_add_post_process(cells, paint_mode == PaintMode.ERASE, false)
			terrain_undo.create_tile_restore_point(undo_manager, tilemap, _restore_cells(cells))
			undo_manager.commit_action()
		
		update_overlay.emit()
		return true
	
	return false


func _add_post_process(cells: Array, erasing: bool, merged: bool) -> void:
	if erasing:
		_scatter_paint(cells, true, merged)
		if cells.all(func(c): return tilemap.get_cell_source_id(c) == -1):
			return
	if not cells.is_empty():
		_mark_cliffs_dirty()
		# Resolve exemplars immediately because their placeholder may also be another terrain tile.
		if tilemap != null and EXEMPLAR_TERRAIN.has_exemplar(tilemap.tile_set) \
				and not (erasing and ObjectTerrain.can_erase_mass_locally(tilemap, cells)):
			if merged:
				terrain_undo.add_do_method(undo_manager, EXEMPLAR_TERRAIN, &"rebuild", [tilemap, BetterTerrain, cells])
			else:
				undo_manager.add_do_method(EXEMPLAR_TERRAIN, &"rebuild", tilemap, BetterTerrain, cells)
	if cells.is_empty() or !ObjectTerrain.has_objects(tileset) or not ObjectTerrain.stroke_affects_objects(tilemap, cells, -1 if erasing else selected_entry):
		return
	if merged:
		terrain_undo.add_do_method(undo_manager, ObjectTerrain, &"fix_cells", [tilemap, cells, erasing, selected_entry])
	else:
		undo_manager.add_do_method(ObjectTerrain, &"fix_cells", tilemap, cells, erasing, selected_entry)
	if ObjectTerrain.has_mass(tileset):
		undo_manager.add_undo_method(ObjectTerrain, &"fix_mass_deferred", tilemap)


func _restore_cells(cells: Array) -> Array:
	if paint_mode == PaintMode.ERASE and cells.all(func(c): return tilemap.get_cell_source_id(c) == -1):
		return cells
	if paint_mode == PaintMode.ERASE and ObjectTerrain.can_erase_mass_locally(tilemap, cells):
		return ObjectTerrain.mass_erase_region(tilemap, cells).keys()
	if not ObjectTerrain.stroke_affects_objects(tilemap, cells, -1 if paint_mode == PaintMode.ERASE else selected_entry):
		return cells
	if ObjectTerrain.has_mass(tileset):
		cells = cells + tilemap.get_used_cells()
	return ObjectTerrain.expand_cells(tilemap, cells) if ObjectTerrain.has_objects(tileset) else cells


func _cells_in_area(area: Rect2i) -> Array:
	var out := []
	for y in range(area.position.y, area.end.y + 1):
		for x in range(area.position.x, area.end.x + 1):
			out.append(Vector2i(x, y))
	return out


func canvas_mouse_exit() -> void:
	draw_overlay = false
	_collision_tip_ready = false
	if _collision_tip_timer != null:
		_collision_tip_timer.stop()
	update_overlay.emit()


func cancel_paint() -> void:
	terrain_undo.finish_action()
	paint_mode = PaintMode.NO_PAINT
	paint_action = PaintAction.NO_ACTION
	update_overlay.emit()


func _shortcut_input(event) -> void:
	if event is InputEventKey:
		if event.keycode == KEY_C and (event.is_command_or_control_pressed() and not event.echo):
			get_viewport().set_input_as_handled()
			tile_view.copy_selection()
		if event.keycode == KEY_V and (event.is_command_or_control_pressed() and not event.echo):
			get_viewport().set_input_as_handled()
			tile_view.paste_selection()


## bresenham alg ported from Geometry2D::bresenham_line()
func _get_line(from:Vector2i, to:Vector2i) -> Array[Vector2i]:
	if from == to:
		return [to]
	
	var points:Array[Vector2i] = []
	var delta := (to - from).abs() * 2
	var step := (to - from).sign()
	var current := from
	
	if delta.x > delta.y:
		@warning_ignore("integer_division")
		var err:int = delta.x / 2
		while current.x != to.x:
			points.push_back(current);
			err -= delta.y
			if err < 0:
				current.y += step.y
				err += delta.x
			current.x += step.x
	else:
		@warning_ignore("integer_division")
		var err:int = delta.y / 2
		while current.y != to.y:
			points.push_back(current)
			err -= delta.x
			if err < 0:
				current.x += step.x
				err += delta.y
			current.y += step.y
	
	points.push_back(current);
	return points;


## half-offset bresenham alg ported from TileMapEditor::get_line
func _get_tileset_line(from:Vector2i, to:Vector2i, ts:TileSet) -> Array[Vector2i]:
	if ts.tile_shape == TileSet.TILE_SHAPE_SQUARE:
		return _get_line(from, to)
	
	var points:Array[Vector2i] = []
	
	var transposed := ts.get_tile_offset_axis() == TileSet.TILE_OFFSET_AXIS_VERTICAL
	if transposed:
		from = Vector2i(from.y, from.x)
		to = Vector2i(to.y, to.x)

	var delta:Vector2i = to - from
	delta = Vector2i(2 * delta.x + abs(posmod(to.y, 2)) - abs(posmod(from.y, 2)), delta.y)
	var step:Vector2i = delta.sign()

	var current := from;
	points.push_back(Vector2i(current.y, current.x) if transposed else current)

	var err := 0
	if abs(delta.y) < abs(delta.x):
		var err_step:Vector2i = 3 * delta.abs()
		while current != to:
			err += err_step.y
			if err > abs(delta.x):
				if step.x == 0:
					current += Vector2i(step.y, 0)
				else:
					current += Vector2i(step.x if bool(current.y % 2) != (step.x < 0) else 0, step.y)
				err -= err_step.x
			else:
				current += Vector2i(step.x, 0)
				err += err_step.y
			points.push_back(Vector2i(current.y, current.x) if transposed else current)
	else:
		var err_step:Vector2i = delta.abs()
		while current != to:
			err += err_step.x
			if err > 0:
				if step.x == 0:
					current += Vector2i(0, step.y)
				else:
					current += Vector2i(step.x if bool(current.y % 2) != (step.x < 0) else 0, step.y)
				err -= err_step.y;
			else:
				if step.x == 0:
					current += Vector2i(0, step.y)
				else:
					current += Vector2i(-step.x if bool(current.y % 2) != (step.x > 0) else 0, step.y)
				err += err_step.y
			points.push_back(Vector2i(current.y, current.x) if transposed else current)
	
	return points


func _on_terrain_enable_id_pressed(id):
	if id in [SourceSelectors.ALL, SourceSelectors.NONE]:
		for i in source_selector_popup.item_count:
			if source_selector_popup.is_item_checkable(i):
				source_selector_popup.set_item_checked(i, id == SourceSelectors.ALL)
	else:
		var index = source_selector_popup.get_item_index(id)
		var checked = source_selector_popup.is_item_checked(index)
		source_selector_popup.set_item_checked(index, !checked)
	
	var disabled_sources : Array[int]
	for i in source_selector_popup.item_count:
		if source_selector_popup.is_item_checkable(i) and !source_selector_popup.is_item_checked(i):
			disabled_sources.append(source_selector_popup.get_item_id(i))
	tile_view.disabled_sources = disabled_sources


func corresponding_tilemap_editor_button(similar: Button) -> Button:
	var editors = EditorInterface.get_base_control().find_children("*", "TileMapLayerEditor", true, false)
	var tile_map_layer_editor = editors[0]
	var buttons = tile_map_layer_editor.find_children("*", "Button", true, false)
	for button: Button in buttons:
		if button.icon == similar.icon:
			return button
	return null


func _on_layer_up_or_down_pressed(button: Button) -> void:
	var matching_button = corresponding_tilemap_editor_button(button)
	if !matching_button:
		return
	
	# Major hack, to reduce flicker hide the tileset editor briefly
	var editors = EditorInterface.get_base_control().find_children("*", "TileSetEditor", true, false)
	var tile_set_editor = editors[0]
	
	matching_button.pressed.emit()
	tile_set_editor.modulate = Color.TRANSPARENT
	await get_tree().process_frame
	await get_tree().process_frame
	force_show_terrains.emit()
	tile_set_editor.modulate = Color.WHITE


func _on_layer_up_pressed() -> void:
	_on_layer_up_or_down_pressed(layer_up)


func _on_layer_down_pressed() -> void:
	_on_layer_up_or_down_pressed(layer_down)


func _on_layer_highlight_toggled(toggled: bool) -> void:
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/highlight_selected_layer", toggled)
	
	var highlight = corresponding_tilemap_editor_button(layer_highlight)
	if highlight:
		highlight.toggled.emit(toggled)


func _on_layer_grid_toggled(toggled: bool) -> void:
	var settings = EditorInterface.get_editor_settings()
	settings.set_setting("editors/tiles_editor/display_grid", toggled)

	var grid = corresponding_tilemap_editor_button(layer_grid)
	if grid:
		grid.toggled.emit(toggled)


func _on_make_floating_toggled(toggled: bool) -> void:
	make_floating_toggled.emit(toggled)


func set_make_floating_pressed(pressed: bool) -> void:
	if make_floating and make_floating.button_pressed != pressed:
		make_floating.set_pressed_no_signal(pressed)


var _cliff_window: Window = null
var _exemplar_window: Window = null
var _cliff_button: Button = null
var _exemplar_button: Button = null


var _brush_size := 1

const BRUSH_SIZES := [1, 2, 3, 4, 5, 6, 7, 8]
var _brush_menu: PopupMenu
var _brush_badge: Label


func _hook_brush_menu() -> void:
	if draw_button == null:
		return
	draw_button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed \
				and event.button_index == MOUSE_BUTTON_RIGHT:
			draw_button.accept_event()
			_popup_brush_menu())
	_update_brush_label()


func _popup_brush_menu() -> void:
	if _brush_menu == null:
		_brush_menu = PopupMenu.new()
		for n in BRUSH_SIZES:
			_brush_menu.add_radio_check_item("%d x %d" % [n, n], n)
		_brush_menu.id_pressed.connect(func(id: int) -> void:
			_brush_size = id
			_update_brush_label()
			update_overlay.emit())
		add_child(_brush_menu)
	for n in BRUSH_SIZES:
		_brush_menu.set_item_checked(_brush_menu.get_item_index(n), n == _brush_size)
	_brush_menu.position = Vector2i(draw_button.get_screen_position() + Vector2(0, draw_button.size.y))
	_brush_menu.reset_size()
	_brush_menu.popup()


func _update_brush_label() -> void:
	if draw_button == null:
		return
	if _brush_badge == null:
		_brush_badge = Label.new()
		_brush_badge.name = "BrushBadge"
		_brush_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_brush_badge.add_theme_font_size_override("font_size", 11)
		_brush_badge.add_theme_color_override("font_color", Color(1, 1, 1))
		_brush_badge.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.7))
		_brush_badge.add_theme_constant_override("outline_size", 2)
		_brush_badge.set_anchors_preset(Control.PRESET_TOP_LEFT)
		draw_button.add_child(_brush_badge)
		draw_button.resized.connect(_place_brush_badge)
	_brush_badge.text = "" if _brush_size == 1 else "%dx" % _brush_size
	_brush_badge.visible = _brush_size > 1
	_place_brush_badge()
	draw_button.tooltip_text = \
		"Draw terrain\nShift: Draw line.\nCtrl/Cmd+Shift: Draw rectangle.\n\n" + \
		"Right-click for the brush size. Now: %d x %d." % [_brush_size, _brush_size]


func _place_brush_badge() -> void:
	if _brush_badge == null or draw_button == null:
		return
	var icon_size := Vector2(16, 16)
	if draw_button.icon != null:
		icon_size = draw_button.icon.get_size()
	var centre := draw_button.size * 0.5
	_brush_badge.reset_size()
	var offset := Vector2(3, -5)
	_brush_badge.position = centre - icon_size * 0.5 + offset


func _object_brush_cells(type: int, cells: Array) -> Array:
	if paint_mode == PaintMode.ERASE:
		if _is_single(type):
			cells = _single_erase_cells(cells)
		return ObjectTerrain.mass_erase_cells(tilemap, cells)
	if not ObjectTerrain.is_mass(tileset, type):
		return cells
	var base := ObjectTerrain.base_rect(ObjectTerrain.object_size(tileset, type),
		ObjectTerrain.object_config(tileset, type))
	var out := {}
	for c in cells:
		var anchor := ObjectTerrain.mass_anchor(c, base.size)
		for y in base.size.y:
			for x in base.size.x:
				out[anchor + Vector2i(x, y)] = true
	return out.keys()


func _brush_cells(cells: Array) -> Array:
	if _brush_size <= 1:
		return cells
	@warning_ignore("integer_division")
	var half := _brush_size / 2
	var seen := {}
	var out := []
	for c: Vector2i in cells:
		for dy in range(-half, _brush_size - half):
			for dx in range(-half, _brush_size - half):
				var p := c + Vector2i(dx, dy)
				if seen.has(p):
					continue
				seen[p] = true
				out.append(p)
	return out


func _add_map_select_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null or draw_button == null:
		return
	_map_select = Button.new()
	_map_select.name = "MapSelect"
	_map_select.toggle_mode = true
	_map_select.button_group = draw_button.button_group
	_icon_or_text(_map_select, ICON_DIR + "MapSelect.svg", ["ListSelect"], "Sel")
	_map_select.toggled.connect(func(on: bool) -> void:
		_map_all_layers.visible = on
		if tile_view != null:
			tile_view.shortcuts_blocked = on
		if not on:
			_clear_map_selection())
	_map_select.tooltip_text = \
		"Select an area of the MAP.\n\n" + \
		"Drag a rectangle and the cells inside it become the cliff window's\n" + \
		"preview, so you check your slots against the shape that actually looks\n" + \
		"wrong instead of an invented one.\n\n" + \
		"Shift-drag adds to the selection, Ctrl-drag takes away, so it can be\n" + \
		"built in several passes. Drag from inside the marks to move them, and\n" + \
		"right-click for cut, copy, paste, duplicate and delete."
	toolbar.add_child(_map_select)
	toolbar.move_child(_map_select, draw_button.get_index())
	_map_all_layers = CheckBox.new()
	_map_all_layers.name = "AllLayers"
	_map_all_layers.text = "All layers"
	_map_all_layers.tooltip_text = "Select and move tiles on every layer in this scene, including instanced scenes."
	_map_all_layers.focus_mode = Control.FOCUS_NONE
	_map_all_layers.hide()
	_map_all_layers.toggled.connect(func(_on): _clear_map_selection())
	toolbar.add_child(_map_all_layers)
	toolbar.move_child(_map_all_layers, _map_select.get_index() + 1)


var _picker: Button
var _picker_select_layer: CheckBox
var _tool_before_pick: BaseButton


func _add_picker_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null or fill_button == null:
		return
	_picker = Button.new()
	_picker.name = "Picker"
	_picker.toggle_mode = true
	_picker.flat = true
	_picker.focus_mode = Control.FOCUS_NONE
	_picker.button_group = draw_button.button_group
	_picker.icon = get_theme_icon("ColorPick", "EditorIcons")
	var key := InputEventKey.new()
	key.keycode = KEY_I
	_picker.shortcut = Shortcut.new()
	_picker.shortcut.events = [key]
	_picker.shortcut_in_tooltip = false
	toolbar.add_child(_picker)
	draw_button.button_group.pressed.connect(func(button: BaseButton) -> void:
		if button != _picker:
			_tool_before_pick = button)
	_tool_before_pick = draw_button
	_update_picker_tooltip()

	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(PICKER_SELECT_LAYER_SETTING):
		settings.set_setting(PICKER_SELECT_LAYER_SETTING, false)
	settings.set_initial_value(PICKER_SELECT_LAYER_SETTING, false, false)
	_picker_select_layer = CheckBox.new()
	_picker_select_layer.name = "SelectLayer"
	_picker_select_layer.text = "Select Layer"
	_picker_select_layer.tooltip_text = "Pick from the topmost visible layer under the cursor and select that\nTileMapLayer in the scene, so painting goes on where the tile came from."
	_picker_select_layer.focus_mode = Control.FOCUS_NONE
	_picker_select_layer.button_pressed = bool(settings.get_setting(PICKER_SELECT_LAYER_SETTING))
	_picker_select_layer.toggled.connect(func(on: bool) -> void: _store_view_mode(PICKER_SELECT_LAYER_SETTING, on))
	_picker_select_layer.hide()
	_picker.toggled.connect(func(_on: bool) -> void: _sync_select_layer())
	toolbar.add_child(_picker_select_layer)


func _picker_active() -> bool:
	return _picker != null and _picker.button_pressed


func _picker_modifier() -> int:
	var settings := EditorInterface.get_editor_settings()
	if settings == null or not settings.has_setting(PICKER_MODIFIER_SETTING):
		return PickerModifier.ALT
	var modifier := int(settings.get_setting(PICKER_MODIFIER_SETTING))
	return modifier if modifier >= 0 and modifier < PICKER_MODIFIER_NAMES.size() else PickerModifier.ALT


func _picker_modifier_held(event: InputEventWithModifiers) -> bool:
	match _picker_modifier():
		PickerModifier.ALT:
			return event.alt_pressed
		PickerModifier.SHIFT:
			# Ctrl+Shift is still the draw tool's rectangle.
			return event.shift_pressed and not event.is_command_or_control_pressed()
	return false


func _is_pick_click(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton) or not event.pressed \
			or event.button_index != MOUSE_BUTTON_LEFT:
		return false
	return _picker_active() or _picker_modifier_held(event)


func _pick_is_tile() -> bool:
	return _is_single(selected_entry)


func _pick_at(cell: Vector2i) -> void:
	var layer := tilemap
	var at := cell
	var jump := _picker_select_layer != null and _picker_select_layer.button_pressed \
		and tilemap.is_inside_tree()
	if jump:
		var found := _visible_layer_at(tilemap.to_global(tilemap.map_to_local(cell)))
		if not found.is_empty():
			layer = found[0]
			at = found[1]
	elif layer.get_cell_source_id(cell) == -1:
		var top := BetterTerrain.top_layer_at(tilemap, cell)
		if top != null and top.tile_set == tileset:
			layer = top
	if _picker_active() and _tool_before_pick != null:
		_tool_before_pick.button_pressed = true
	if jump and layer != tilemap:
		var selection := EditorInterface.get_selection()
		selection.clear()
		selection.add_node(layer)
		EditorInterface.edit_node(layer)
		# The dock may switch tileset first, so pick deferred.
		_pick_from.call_deferred(layer, at)
		return
	_pick_from(layer, at)


# Terrain cells select their terrain, plain tiles go to the single-tile brush.
func _pick_from(layer: TileMapLayer, cell: Vector2i) -> void:
	if not is_instance_valid(layer) or layer.tile_set != tileset:
		return
	var id := BetterTerrain.get_cell(layer, cell)
	var source_id := layer.get_cell_source_id(cell)
	if id >= 0 or (id == BetterTerrain.TileCategory.EMPTY and source_id != -1):
		# Terrain or decoration tile.
		_select_entry(id)
	elif source_id != -1 and tileset.has_source(source_id) \
			and tileset.get_source(source_id) is TileSetAtlasSource:
		# Plain tile, or the whole block if it was painted with one.
		if not _pick_is_tile():
			_select_entry(BetterTerrain.TileCategory.SINGLE)
		var found := _painted_block_at(layer, cell, _multi_tile_blocks())
		if not found.is_empty():
			_set_single_tile(source_id, found.block.origin, found.block.size, found.block.alt)
		else:
			_set_single_tile(source_id, layer.get_cell_atlas_coords(cell), Vector2i.ONE,
				layer.get_cell_alternative_tile(cell))
	update_overlay.emit()


## [layer, cell] of the topmost visible, selectable layer with a tile here, or [].
func _visible_layer_at(point: Vector2) -> Array:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return []
	var layers: Array = root.find_children("*", "TileMapLayer", true, false)
	if root is TileMapLayer:
		layers.push_front(root)
	var best: Array = []
	var best_z := 0
	for found: TileMapLayer in layers:
		var layer := found
		# Support layers count as the layer that own them.
		if SUPPORT_LAYERS.is_support(layer):
			if layer.get_cell_source_id(layer.local_to_map(layer.to_local(point))) == -1:
				continue
			layer = layer.get_parent()
		# Can't select nodes inside instanced scenes.
		if layer.tile_set == null or not layer.is_visible_in_tree() \
				or (layer != root and layer.owner != root):
			continue
		var c := layer.local_to_map(layer.to_local(point))
		if layer.get_cell_source_id(c) == -1:
			continue
		# Same z: later in the tree draws on top.
		var z := _effective_z(found)
		if best.is_empty() or z >= best_z:
			best_z = z
			best = [layer, c]
	return best


func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		z += node.z_index
		if not node.z_as_relative:
			break
		node = node.get_parent()
	return z


# Godot has no eyedropper cursor, so its drawn here.
const PICKER_CURSOR_SVG := """<svg xmlns="http://www.w3.org/2000/svg" width="24" height="24">
<g transform="rotate(45 12 12)" fill="#ffffff" stroke="#101010" stroke-width="1.5" stroke-linejoin="round">
<path d="M9 7V3a3 3 0 0 1 6 0v4h2v2h-3v10l-2 4-2-4V9H7V7z"/>
</g></svg>"""
const PICKER_CURSOR_TIP := Vector2(4.5, 19.5)
const PICKER_ARMED_COLOR := Color(0.44, 0.73, 0.98)

var _picker_cursor: Texture2D
var _picker_lit := false


func picker_cursor() -> Texture2D:
	if _picker_cursor == null:
		var image := Image.new()
		image.load_svg_from_string(PICKER_CURSOR_SVG, EditorInterface.get_editor_scale())
		_picker_cursor = ImageTexture.create_from_image(image)
	return _picker_cursor


func picker_cursor_hotspot() -> Vector2:
	return PICKER_CURSOR_TIP * EditorInterface.get_editor_scale()


var _modifier_stale := false


func picker_modifier_down() -> bool:
	# Mid-stroke the key is for the stroke (Shift line), not the picker.
	if paint_mode != PaintMode.NO_PAINT or _modifier_stale:
		return false
	return _raw_modifier_down()


func _raw_modifier_down() -> bool:
	match _picker_modifier():
		PickerModifier.ALT:
			return Input.is_key_pressed(KEY_ALT)
		PickerModifier.SHIFT:
			return Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_CTRL) \
				and not Input.is_key_pressed(KEY_META)
	return false


## True when a left click would pick instead of paint.
func picker_armed() -> bool:
	# Collisions pick only in Stamp (a tile's shape); Custom data's picker click takes a tile's fields.
	if tilemap == null or _map_select_active() or (_collision_mode() and not _collision_stamp_mode):
		return false
	# In Inspect the key adds to the selection instead.
	if _data_mode():
		return not _data_inspecting() and (_data_panel.pick_armed or picker_modifier_down())
	return _picker_active() or picker_modifier_down()


## Custom data picks from the atlas too, so the eyedropper shows over it.
func mouse_over_data_atlas() -> bool:
	if not _data_mode() or not tile_view.is_visible_in_tree():
		return false
	var frame := tile_view.get_parent() as Control
	return frame.get_global_rect().has_point(frame.get_global_mouse_position())


func set_picker_lit(lit: bool) -> void:
	if _picker == null or lit == _picker_lit:
		return
	_picker_lit = lit
	_sync_select_layer()
	update_overlay.emit()
	for property in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_hover_pressed_color"]:
		if lit:
			_picker.add_theme_color_override(property, PICKER_ARMED_COLOR)
		else:
			_picker.remove_theme_color_override(property)


func _select_entry(id: int) -> void:
	var entry = _entry_for_id(id)
	if entry:
		entry._on_focus_entered()
	else:
		_on_entry_select(id)


# Visible while a pick is armed.
func _sync_select_layer() -> void:
	if _picker_select_layer != null:
		_picker_select_layer.visible = (_picker_active() or _picker_lit) and not (_collision_mode() or _data_mode())


func _update_picker_tooltip() -> void:
	if _picker == null:
		return
	var text := "Pick from the map what is under the cursor (I): a terrain tile selects\nits terrain, any other tile switches to the single-tile brush with it.\nAfter one pick it goes back to the previous tool."
	text += "\n\n%s+click picks with any tool. Change the key in Options." % PICKER_MODIFIER_NAMES[_picker_modifier()]
	_picker.tooltip_text = text


const ALL_LAYERS_SELECTION := preload("res://addons/better-tile-editor/editor/AllLayersSelection.gd")
var _all_selection := ALL_LAYERS_SELECTION.new()
var _map_all_layers: CheckBox
var _map_select: Button
var _map_select_from := Vector2i.ZERO
var _map_selecting := false

var _map_sel: Array = []
var _map_sel_rect := Rect2i()
var _map_sel_mode := 0
## Clipboard format: [offset, source, atlas coordinate, alternative].
var _map_clip: Array = []
var _map_drag := false
var _map_drag_from := Vector2i.ZERO
var _map_drag_delta := Vector2i.ZERO
var _map_menu: PopupMenu

enum MapSelAction { CUT, COPY, PASTE, DUPLICATE, DELETE, CLEAR }

var _slope_button: Button
var _slope_autofill: CheckBox
var _slope_freehand: CheckBox
var _slope_smooth: SpinBox
var _free_start := Vector2i.ZERO
var _free_trail := []
var _slope_editor: Control
var _slope_preview_key := []
var _mouse_local := Vector2.ZERO
var _slope_preview := {}


func _add_slope_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null or draw_button == null:
		return
	_slope_button = Button.new()
	_slope_button.name = "Slope"
	_slope_button.toggle_mode = true
	_slope_button.button_group = draw_button.button_group
	_slope_button.visible = false
	_icon_or_text(_slope_button, ICON_DIR + "Slope.svg", [], "Slope")
	_slope_button.tooltip_text = \
		"Slope: drag to draw the ground's surface.\n\n" + \
		"Across a row or a column it draws a straight line of Ground. Diagonally it draws\n" + \
		"a slope: about as wide as tall is steep, twice as wide is gentle, one step per row.\n" + \
		"It fills Ground below it; started under a ceiling it makes a ceiling slope. Hold\n" + \
		"Shift for a thin diagonal, with no Ground. The preview shows the tiles you'll get.\n" + \
		"Autofill also fills Ground under straight lines, down to the ground.\n" + \
		"Freehand draws like a pencil that follows the mouse; Shift keeps it level.\n" + \
		"Right-drag removes. Set it up in Options > Slopes."
	_slope_button.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			_open_slope_roles())
	toolbar.add_child(_slope_button)
	toolbar.move_child(_slope_button, fill_button.get_index() + 1)
	_slope_autofill = CheckBox.new()
	_slope_autofill.name = "SlopeAutofill"
	_slope_autofill.text = "Autofill"
	_slope_autofill.tooltip_text = "Straight lines also fill Ground down to the ground below them.\nWith no ground in reach they stay a one-row bar."
	_slope_autofill.focus_mode = Control.FOCUS_NONE
	_slope_autofill.hide()
	_slope_button.visibility_changed.connect(_sync_slope_autofill)
	_slope_button.toggled.connect(func(_on: bool) -> void: _sync_slope_autofill())
	toolbar.add_child(_slope_autofill)
	toolbar.move_child(_slope_autofill, _slope_button.get_index() + 1)
	_slope_freehand = CheckBox.new()
	_slope_freehand.name = "SlopeFreehand"
	_slope_freehand.text = "Freehand"
	_slope_freehand.tooltip_text = "Draw like a pencil: the ground follows the mouse, turning into gentle or steep\nslopes or walls by how fast it climbs. Going back takes the last steps away;\nhold Shift to keep it level. Right-drag erases like the pencil."
	_slope_freehand.focus_mode = Control.FOCUS_NONE
	_slope_freehand.hide()
	toolbar.add_child(_slope_freehand)
	toolbar.move_child(_slope_freehand, _slope_autofill.get_index() + 1)
	_slope_smooth = SpinBox.new()
	_slope_smooth.name = "SlopeSmooth"
	_slope_smooth.prefix = "Smooth"
	_slope_smooth.custom_minimum_size.x = 104 * EditorInterface.get_editor_scale()
	_slope_smooth.min_value = 0
	_slope_smooth.max_value = 8
	_slope_smooth.value = 2
	_slope_smooth.tooltip_text = "Bumps and dips one row high and up to this many columns wide are drawn flat,\nso a shaky hand doesn't leave teeth. 0 draws exactly what the mouse did."
	_slope_smooth.focus_mode = Control.FOCUS_NONE
	_slope_smooth.hide()
	_slope_freehand.toggled.connect(func(_on: bool) -> void: _sync_slope_autofill())
	toolbar.add_child(_slope_smooth)


func _sync_slope_autofill() -> void:
	_slope_autofill.visible = _slope_button.visible and _slope_button.button_pressed
	_slope_freehand.visible = _slope_autofill.visible
	_slope_smooth.visible = _slope_freehand.visible and _slope_freehand.button_pressed


func _freehand() -> bool:
	return _slope_freehand != null and _slope_freehand.button_pressed


func _free_smooth() -> int:
	return int(_slope_smooth.value) if _slope_smooth != null else 0


func _free_target() -> Vector2:
	return _mouse_local / Vector2(tilemap.tile_set.tile_size)


func _slope_plan() -> Dictionary:
	var members: Array = SLOPE_TERRAIN.roles(tileset).values()
	var solid := func(c: Vector2i) -> bool: return BetterTerrain.get_cell(tilemap, c) in members
	var autofill := _slope_autofill != null and _slope_autofill.button_pressed
	var terrain_at := func(c: Vector2i) -> int: return BetterTerrain.get_cell(tilemap, c)
	if _freehand():
		var moves: Array = SLOPE_TERRAIN.free_moves(_free_start, _free_trail, _free_smooth())
		return SLOPE_TERRAIN.free_plan(SLOPE_TERRAIN.roles(tileset), solid, _free_start, moves, paint_mode == PaintMode.ERASE, autofill,
			terrain_at)
	var thin := Input.is_key_pressed(KEY_SHIFT)
	if thin and not SLOPE_TERRAIN.thin_ready(BetterTerrain, tileset):
		return {"cells": {}, "erase": [], "label": "Thin diagonals need their pieces: Options > Slopes"}
	return SLOPE_TERRAIN.plan(tileset, solid, initial_click, _slope_offset(), paint_mode == PaintMode.ERASE, thin,
		autofill, terrain_at)


func _slope_offset() -> Vector2:
	return (_mouse_local - tilemap.map_to_local(initial_click)) / Vector2(tilemap.tile_set.tile_size)


func _apply_slope(plan: Dictionary) -> void:
	var cells: Array = plan.cells.keys() + plan.erase
	if cells.is_empty():
		return
	# A TileSet reloaded from disk loses the slope rules, and without them plain ground replaces slope ground
	if SLOPE_TERRAIN.add_rules(BetterTerrain, tileset) > 0:
		BetterTerrain._purge_cache(tileset)
	undo_manager.create_action(tr("Draw slope"), UndoRedo.MERGE_DISABLE, tilemap)
	for c in plan.erase:
		undo_manager.add_do_method(tilemap, &"erase_cell", c)
	for c in plan.cells:
		undo_manager.add_do_method(BetterTerrain, &"set_cell", tilemap, c, plan.cells[c])
	undo_manager.add_do_method(BetterTerrain, &"update_terrain_cells", tilemap, cells)
	_add_post_process(cells, plan.cells.is_empty(), false)
	terrain_undo.create_tile_restore_point(undo_manager, tilemap, _restore_cells(cells))
	undo_manager.commit_action()
	update_overlay.emit()


func _draw_slope_preview(overlay: Control, transform: Transform2D, plan: Dictionary) -> void:
	var key := [initial_click, SLOPE_TERRAIN.snap(_slope_offset()), paint_mode, Input.is_key_pressed(KEY_SHIFT),
		_slope_autofill != null and _slope_autofill.button_pressed]
	if _freehand():
		key = [_free_start, SLOPE_TERRAIN.free_moves(_free_start, _free_trail, _free_smooth()), paint_mode,
			_slope_autofill.button_pressed]
	if key != _slope_preview_key:
		_slope_preview_key = key
		_slope_preview = _slope_result(plan)
	var cell_size := Vector2(tilemap.tile_set.tile_size)
	overlay.draw_set_transform_matrix(transform)
	for c: Vector2i in _slope_preview:
		var tile: Array = _slope_preview[c]
		var at := Rect2(tilemap.map_to_local(c) - cell_size * 0.5, cell_size)
		overlay.draw_rect(at, Color(0.1, 0.1, 0.12, 0.55))
		var src := tileset.get_source(tile[0]) as TileSetAtlasSource
		if src != null and src.texture != null and src.has_alternative_tile(tile[1], tile[2]):
			# Flipped alternatives, as the simple slope set-up makes, are drawn flipped
			var td := src.get_tile_data(tile[1], tile[2])
			var flip := Vector2(-1.0 if td.flip_h else 1.0, -1.0 if td.flip_v else 1.0)
			overlay.draw_set_transform_matrix(transform * Transform2D(0.0, flip, 0.0, at.get_center()))
			overlay.draw_texture_rect_region(src.texture, Rect2(-cell_size * 0.5, cell_size), src.get_tile_texture_region(tile[1]), Color(1, 1, 1, 0.85))
			overlay.draw_set_transform_matrix(transform)
	for c: Vector2i in plan.erase:
		var at := Rect2(tilemap.map_to_local(c) - cell_size * 0.5, cell_size)
		overlay.draw_rect(at, Color(0.95, 0.3, 0.25, 0.35))
		overlay.draw_rect(at, Color(0.95, 0.3, 0.25), false, 1.0)
	overlay.draw_set_transform_matrix(Transform2D.IDENTITY)
	var label: String = plan.label if not plan.label.is_empty() else "Drag across rows and columns to draw a slope"
	var font := get_theme_font("font", "Label")
	var label_at := transform * tilemap.map_to_local(current_position) + Vector2(18, -14)
	var width := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14).x
	overlay.draw_rect(Rect2(label_at - Vector2(6, 16), Vector2(width + 12, 22)), Color(0, 0, 0, 0.7))
	overlay.draw_string(font, label_at, label, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(1, 0.95, 0.7))


# The plan is applied to a copy of the cells around it, so the preview shows the tiles it will end with
func _slope_result(plan: Dictionary) -> Dictionary:
	var touched: Array = plan.cells.keys() + plan.erase
	if touched.is_empty():
		return {}
	if SLOPE_TERRAIN.add_rules(BetterTerrain, tileset) > 0:
		BetterTerrain._purge_cache(tileset)
	var area := Rect2i(touched[0], Vector2i.ONE)
	for c in touched:
		area = area.expand(c)
	area = area.grow(2)
	area.size += Vector2i.ONE
	var copy := TileMapLayer.new()
	copy.tile_set = tileset
	for y in range(area.position.y, area.end.y):
		for x in range(area.position.x, area.end.x):
			var c := Vector2i(x, y)
			if tilemap.get_cell_source_id(c) >= 0:
				copy.set_cell(c, tilemap.get_cell_source_id(c), tilemap.get_cell_atlas_coords(c), tilemap.get_cell_alternative_tile(c))
	for c in plan.erase:
		copy.erase_cell(c)
	for c in plan.cells:
		BetterTerrain.set_cell(copy, c, plan.cells[c])
	BetterTerrain.update_terrain_cells(copy, touched)
	var result := {}
	for y in range(area.position.y + 1, area.end.y - 1):
		for x in range(area.position.x + 1, area.end.x - 1):
			var c := Vector2i(x, y)
			var source := copy.get_cell_source_id(c)
			if source == tilemap.get_cell_source_id(c) and copy.get_cell_atlas_coords(c) == tilemap.get_cell_atlas_coords(c) \
					and copy.get_cell_alternative_tile(c) == tilemap.get_cell_alternative_tile(c):
				continue
			if source >= 0:
				result[c] = [source, copy.get_cell_atlas_coords(c), copy.get_cell_alternative_tile(c)]
	copy.free()
	return result


func _save_slope_roles(chosen: Dictionary) -> void:
	SLOPE_TERRAIN.save_roles(tileset, chosen)


func _add_slope_rules() -> void:
	var added: int = SLOPE_TERRAIN.add_rules(BetterTerrain, tileset)
	EditorInterface.get_editor_toaster().push_toast("Added %d slope rules to the tiles" % added)
	tile_view.queue_redraw()


func _tile_metas() -> Array:
	var metas := []
	for s in tileset.get_source_count():
		var src := tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for i in src.get_tiles_count():
			var coord := src.get_tile_id(i)
			for a in src.get_alternative_tiles_count(coord):
				var td := src.get_tile_data(coord, src.get_alternative_tile_id(coord, a))
				metas.append([td, td.get_meta(BetterTerrain.TERRAIN_META).duplicate(true) if td.has_meta(BetterTerrain.TERRAIN_META) else null])
	return metas


func _restore_tile_metas(metas: Array) -> void:
	for entry in metas:
		if entry[1] == null:
			entry[0].remove_meta(BetterTerrain.TERRAIN_META)
		else:
			entry[0].set_meta(BetterTerrain.TERRAIN_META, entry[1].duplicate(true))
	BetterTerrain._purge_cache(tileset)
	tileset.emit_changed()
	tile_view.queue_redraw()


func _open_slope_roles() -> void:
	if tileset == null:
		return
	if _slope_editor == null:
		_slope_editor = SLOPE_EDITOR_SCRIPT.new()
		_slope_editor.name = "SlopeEditor"
		_slope_editor.roles_changed.connect(func() -> void:
			rebuild_terrain_list()
			update_tile_view_paint())
		add_child(_slope_editor)
	SLOPE_TERRAIN.tidy(BetterTerrain, tileset)
	rebuild_terrain_list()
	# Shown over the dock's content, so it needs no window of its own
	$VBox.hide()
	_slope_editor.open(tileset, undo_manager, self)


func _clear_map_selection() -> void:
	_all_selection.clear_selection()
	if _map_sel.is_empty() and not CLIFF_DATA.has_captured():
		return
	_map_sel = []
	_map_sel_rect = Rect2i()
	_map_drag = false
	_map_drag_delta = Vector2i.ZERO
	CLIFF_DATA.set_captured([])
	_update_map_info()
	if is_instance_valid(_cliff_window):
		_cliff_window.refresh_shapes()
	update_overlay.emit()


func _update_map_info() -> void:
	update_overlay.emit()


const SUPPORT_KIND := {
	"CliffFaces": "cliff faces", "ScatterDecor": "scattered decor",
	"ExemplarEdges": "Patch edges", "LookupEdges": "Patch edges",
}

var _unlock_dialog: ConfirmationDialog


func _ask_unlock(layer: TileMapLayer) -> void:
	if _unlock_dialog != null and _unlock_dialog.visible:
		return
	if _unlock_dialog == null:
		_unlock_dialog = ConfirmationDialog.new()
		_unlock_dialog.title = "Unlock generated layer"
		_unlock_dialog.ok_button_text = "Unlock and edit"
		_unlock_dialog.dialog_autowrap = true
		_unlock_dialog.min_size = Vector2i(520, 0)
		add_child(_unlock_dialog)
	var label := str(layer.name).trim_prefix("_")
	var kind: String = SUPPORT_KIND.get(label, "object layers" if label.begins_with("Mass") else "generated tiles")
	var parent := layer.get_parent()
	_unlock_dialog.dialog_text = ("%s holds the %s that Better Tile Editor generates from %s. "
		+ "It is locked so the generator can keep it in step.\n\n"
		+ "Unlock it to edit it by hand?\n\n"
		+ "While it is unlocked Better Tile Editor stops regenerating it: changes to %s will no "
		+ "longer update this layer, so the two can fall out of step. To hand it back, lock it "
		+ "again from the Scene tree; the next rebuild regenerates it and your hand edits are lost.") \
		% [layer.name, kind, parent.name, parent.name]
	for connection in _unlock_dialog.confirmed.get_connections():
		_unlock_dialog.confirmed.disconnect(connection.callable)
	_unlock_dialog.confirmed.connect(_unlock_support.bind(layer))
	_unlock_dialog.popup_centered()


func _unlock_support(layer: TileMapLayer) -> void:
	if not is_instance_valid(layer):
		return
	undo_manager.create_action(tr("Unlock generated layer"), UndoRedo.MERGE_DISABLE, layer)
	undo_manager.add_do_method(SUPPORT_LAYERS, &"unlock", layer)
	undo_manager.add_undo_method(layer, &"set_meta", &"_edit_lock_", true)
	undo_manager.add_do_method(self, &"_refresh_lock_icons")
	undo_manager.add_undo_method(self, &"_refresh_lock_icons")
	undo_manager.commit_action()


# The Scene tree only redraws lock icons on this signal.
func _refresh_lock_icons() -> void:
	for editor in EditorInterface.get_editor_main_screen().find_children("*", "CanvasItemEditor", true, false):
		editor.emit_signal(&"item_lock_status_changed")
	update_overlay.emit()


func _map_status_line() -> String:
	var out := "%s  %s" % [tilemap.name, current_position]
	if SUPPORT_LAYERS.is_locked(tilemap):
		out += "   generated and locked: click to unlock it for hand editing"
	elif SUPPORT_LAYERS.is_frozen(tilemap):
		out += "   unlocked: no longer regenerated, lock it again to hand it back"
	if not _map_sel.is_empty():
		out += "   %d tiles  %dx%d" % [
			_map_sel.size(), _map_sel_rect.size.x, _map_sel_rect.size.y]
	if not _map_clip.is_empty():
		out += "   %d copied" % _map_clip.size()
	return out


func _lift(coords: Array, origin: Vector2i) -> Array:
	var out := []
	for c in coords:
		out.append([c - origin, tilemap.get_cell_source_id(c),
			tilemap.get_cell_atlas_coords(c), tilemap.get_cell_alternative_tile(c)])
	return out


func _stamp(tm: TileMapLayer, data: Array, origin: Vector2i) -> void:
	for d in data:
		tm.set_cell(origin + d[0], d[1], d[2], d[3])


func _wipe(tm: TileMapLayer, coords: Array) -> void:
	for c in coords:
		tm.erase_cell(c)


## Rect2i.end is exclusive; add one to include the last selected cell.
func _box_of(coords: Array) -> Rect2i:
	if coords.is_empty():
		return Rect2i()
	var lo: Vector2i = coords[0]
	var hi: Vector2i = coords[0]
	for c: Vector2i in coords:
		lo = Vector2i(mini(lo.x, c.x), mini(lo.y, c.y))
		hi = Vector2i(maxi(hi.x, c.x), maxi(hi.y, c.y))
	return Rect2i(lo, hi - lo + Vector2i.ONE)


func _map_paste_at(origin: Vector2i, source_cells: Array, label: String) -> void:
	if _all_layers_active():
		_all_selection.paste(undo_manager, origin, not source_cells.is_empty(), label)
		_sync_all_selection()
		return
	if _map_clip.is_empty() or tilemap == null:
		return
	var target := []
	for d in _map_clip:
		target.append(origin + d[0])
	var dirty: Array = target.duplicate()
	dirty.append_array(source_cells)
	# Two rings cover the edited cells and the neighbours changed by terrain solving.
	var box := _box_of(dirty).grow(2)

	undo_manager.create_action(tr(label), UndoRedo.MERGE_DISABLE, tilemap)
	terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, box)
	if not source_cells.is_empty():
		undo_manager.add_do_method(self, &"_wipe", tilemap, source_cells)
	undo_manager.add_do_method(self, &"_stamp", tilemap, _map_clip, origin)
	undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, box)
	_add_post_process(dirty, false, false)
	undo_manager.commit_action()
	_rebuild_cliffs_now()

	_map_sel = target
	_map_sel_rect = _box_of(target)
	_update_map_info()
	update_overlay.emit()


func _on_map_sel_action(id: int) -> void:
	if tilemap == null:
		return
	if _all_layers_active():
		_on_all_map_sel_action(id)
		return
	match id:
		MapSelAction.COPY:
			_copy_map_selection()
		MapSelAction.CUT:
			if _map_sel.is_empty():
				return
			_copy_map_selection()
			var box := _box_of(_map_sel).grow(2)
			undo_manager.create_action(tr("Cut tiles"), UndoRedo.MERGE_DISABLE, tilemap)
			terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, box)
			undo_manager.add_do_method(self, &"_wipe", tilemap, _map_sel.duplicate())
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, box)
			_add_post_process(_map_sel.duplicate(), true, false)
			undo_manager.commit_action()
			_rebuild_cliffs_now()
			_clear_map_selection()
			return
		MapSelAction.DELETE:
			if _map_sel.is_empty():
				return
			var box := _box_of(_map_sel).grow(2)
			undo_manager.create_action(tr("Delete tiles"), UndoRedo.MERGE_DISABLE, tilemap)
			terrain_undo.create_tile_restore_point_area(undo_manager, tilemap, box)
			undo_manager.add_do_method(self, &"_wipe", tilemap, _map_sel.duplicate())
			undo_manager.add_do_method(BetterTerrain, &"update_terrain_area", tilemap, box)
			_add_post_process(_map_sel.duplicate(), true, false)
			undo_manager.commit_action()
			_rebuild_cliffs_now()
			_clear_map_selection()
			return
		MapSelAction.PASTE:
			_map_paste_at(current_position, [], "Paste tiles")
			return
		MapSelAction.DUPLICATE:
			if _map_sel.is_empty():
				return
			_copy_map_selection()
			_map_paste_at(current_position, [], "Duplicate tiles")
			return
		MapSelAction.CLEAR:
			_clear_map_selection()
			return
	_update_map_info()
	update_overlay.emit()


func _popup_map_menu(at: Vector2) -> void:
	if _map_menu == null:
		_map_menu = PopupMenu.new()
		_map_menu.add_item(tr("Cut"), MapSelAction.CUT)
		_map_menu.add_item(tr("Copy"), MapSelAction.COPY)
		_map_menu.add_item(tr("Paste here"), MapSelAction.PASTE)
		_map_menu.add_item(tr("Duplicate here"), MapSelAction.DUPLICATE)
		_map_menu.add_separator()
		_map_menu.add_item(tr("Delete"), MapSelAction.DELETE)
		_map_menu.add_item(tr("Clear selection"), MapSelAction.CLEAR)
		_map_menu.id_pressed.connect(_on_map_sel_action)
		add_child(_map_menu)
	var has_sel := not _map_sel.is_empty()
	var has_clip := not _all_selection.clipboard.is_empty() if _all_layers_active() else not _map_clip.is_empty()
	for id in [MapSelAction.CUT, MapSelAction.COPY, MapSelAction.DELETE, MapSelAction.CLEAR]:
		_map_menu.set_item_disabled(_map_menu.get_item_index(id), not has_sel)
	_map_menu.set_item_disabled(_map_menu.get_item_index(MapSelAction.PASTE), not has_clip)
	_map_menu.set_item_disabled(_map_menu.get_item_index(MapSelAction.DUPLICATE), not has_sel)
	_map_menu.position = Vector2i(at)
	_map_menu.reset_size()
	_map_menu.popup()


func _map_select_active() -> bool:
	return _map_select != null and _map_select.button_pressed


func _capture_map_selection(a: Vector2i, b: Vector2i, mode: int) -> void:
	if tilemap == null:
		return
	var lo := Vector2i(mini(a.x, b.x), mini(a.y, b.y))
	var hi := Vector2i(maxi(a.x, b.x), maxi(a.y, b.y))
	if _all_layers_active():
		_all_selection.capture(tilemap, EditorInterface.get_edited_scene_root(), Rect2i(lo, hi - lo + Vector2i.ONE), mode)
		_sync_all_selection()
		return
	var inside := []
	for c: Vector2i in tilemap.get_used_cells():
		if c.x >= lo.x and c.x <= hi.x and c.y >= lo.y and c.y <= hi.y:
			inside.append(c)

	var cells: Array = []
	match mode:
		1:
			var seen := {}
			for c in _map_sel:
				seen[c] = true
			cells = _map_sel.duplicate()
			for c in inside:
				if not seen.has(c):
					cells.append(c)
		-1:
			var drop := {}
			for c in inside:
				drop[c] = true
			for c in _map_sel:
				if not drop.has(c):
					cells.append(c)
		_:
			cells = inside

	_map_sel = cells
	_map_sel_rect = _box_of(cells)
	CLIFF_DATA.set_captured(cells)
	_update_map_info()
	if is_instance_valid(_cliff_window):
		_cliff_window.refresh_shapes()


func _add_exemplar_button(toolbar: Node) -> void:
	var lookup := Button.new()
	lookup.name = "ExemplarTerrain"
	_icon_or_text(lookup, ICON_DIR + "Exemplar.svg", ["Tools"], "Roles")
	lookup.tooltip_text = \
		"Read the drawing: works out the selected terrain's roles from the tiles it owns.\n\n" + \
		"The drawing is simply the tiles marked with this terrain. Mark them with the\n" + \
		"paint-type tool by dragging over the whole thing, bank and all; the atlas\n" + \
		"outlines what will be read as you go.\n\n" + \
		"For terrains whose art was drawn as a set piece rather than as an autotile: " + \
		"a pond drawn once is already the terrain laid out, so there is nothing to fill in."
	lookup.focus_mode = Control.FOCUS_NONE
	lookup.pressed.connect(_on_exemplar_pressed)
	toolbar.add_child(lookup)
	var slot := toolbar.get_node_or_null("PaintSymmetry")
	if slot != null:
		toolbar.move_child(lookup, slot.get_index())
	_exemplar_button = lookup


var _oven_button: Button = null
var _oven: Window = null


func _add_oven_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null:
		return
	var b := Button.new()
	b.name = "ObjectBake"
	_icon_or_text(b, ICON_DIR + "ObjectMass.svg", ["Tools"], "Bake")
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(_on_oven_pressed)
	toolbar.add_child(b)
	var slot := toolbar.get_node_or_null("ObjectJoined")
	if slot != null:
		toolbar.move_child(b, slot.get_index() + 1)
	_oven_button = b


const OVEN_READY := \
	"Bake the joined block out of the lone one.\n\n" + \
	"Stacks the drawing against itself and cuts out the piece that repeats,\n" + \
	"which is what the joined block always was."
const OVEN_WAITING := \
	"Disabled until this object has a lone drawing.\n\n" + \
	"Press Lone in the toolbar and click the top-left tile of the drawing\n" + \
	"in the atlas. The oven bakes the other block out of that one."


func _sync_oven_button() -> void:
	if _oven_button == null:
		return
	var is_ready := false
	if tileset != null and _oven_button.visible and selected_entry >= 0:
		is_ready = ObjectTerrain.object_config(tileset, selected_entry).get("lone", []).size() == 2
	_oven_button.disabled = not is_ready
	_oven_button.tooltip_text = OVEN_READY if is_ready else OVEN_WAITING


func _on_oven_pressed() -> void:
	if not _require_terrain("baking"):
		return
	var t = BetterTerrain.get_terrain(tileset, selected_entry)
	if not t.valid or t.type != BetterTerrain.TerrainType.OBJECT:
		return
	if not is_instance_valid(_oven):
		_oven = OBJECT_OVEN_SCRIPT.new()
		add_child(_oven)
		_oven.bake_requested.connect(_on_bake_requested)
	var why: String = _oven.setup(tileset, selected_entry, str(t.name))
	if not why.is_empty():
		_say(why)
		return
	_oven.popup_centered()


func _on_bake_requested(sheet: Image, unit_cells: Vector2i, from: Dictionary) -> void:
	if tileset == null or selected_entry < 0:
		return
	var id := selected_entry
	var before := ObjectTerrain.object_config(tileset, id)
	var after := before.duplicate(true)
	after["size"] = [unit_cells.x, unit_cells.y]
	after["lone"] = [0, 0]

	var previous: Array = OBJECT_BAKE.marked_tiles(tileset, id)

	undo_manager.create_action(tr("Bake object blocks"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(OBJECT_BAKE, &"install", tileset, id, sheet, unit_cells,
		from.tile, previous)
	undo_manager.add_do_method(BetterTerrain, &"set_terrain_object", tileset, id, after)
	undo_manager.add_undo_method(OBJECT_BAKE, &"uninstall", tileset, id, previous)
	undo_manager.add_undo_method(BetterTerrain, &"set_terrain_object", tileset, id, before)
	undo_manager.add_do_method(self, &"_after_bake")
	undo_manager.add_undo_method(self, &"_after_bake")
	undo_manager.commit_action()
	if is_instance_valid(_oven):
		_oven.hide()


func _after_bake() -> void:
	tile_view.refresh_tileset(tileset)
	tile_view.queue_redraw()
	rebuild_terrain_list()
	update_overlay.emit()


func _add_cliff_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null:
		return

	var cliff := Button.new()
	cliff.name = "CliffFaces"
	_icon_or_text(cliff, ICON_DIR + "CliffFace.svg", ["Tools"], "Cliff")
	cliff.tooltip_text = "Cliff faces: configure the south face of the selected terrain"
	cliff.focus_mode = Control.FOCUS_NONE
	cliff.pressed.connect(_on_cliff_pressed)
	toolbar.add_child(cliff)
	_cliff_button = cliff


	_add_exemplar_button(toolbar)
	_add_oven_button()

	_level_spin = SpinBox.new()
	_level_spin.name = "CliffLevel"
	_level_spin.min_value = 0
	_level_spin.max_value = 4
	_level_spin.prefix = "Level "
	_level_spin.custom_minimum_size.x = 100 * EditorInterface.get_editor_scale()
	_level_spin.tooltip_text = \
		"Where this layer sits in the elevation stack.\n\n" + \
		"By default it is its position among the layers that take part, so each\n" + \
		"one up is a level higher. Set it to pull a layer up and everything above\n" + \
		"it follows with the same gaps.\n\n" + \
		"It drives the z band, and the wall height when that has no override of\n" + \
		"its own. The band holds 5 levels: each one takes its ground and the\n" + \
		"faces under it."
	_level_spin.value_changed.connect(_on_cliff_level_changed)
	toolbar.add_child(_level_spin)

	var level_reset := Button.new()
	level_reset.name = "CliffLevelReset"
	level_reset.icon = get_theme_icon("Reload", "EditorIcons")
	level_reset.flat = true
	level_reset.tooltip_text = "Automatic level: follow the layer order"
	level_reset.focus_mode = Control.FOCUS_NONE
	level_reset.pressed.connect(_on_cliff_level_reset)
	toolbar.add_child(level_reset)
	_level_reset = level_reset

	_rows_spin = SpinBox.new()
	_rows_spin.name = "CliffRows"
	_rows_spin.min_value = 0
	_rows_spin.max_value = 16
	_rows_spin.prefix = "Height "
	_rows_spin.custom_minimum_size.x = 110 * EditorInterface.get_editor_scale()
	_rows_spin.tooltip_text = \
		"How many rows of wall this layer drops.\n\n" + \
		"Empty means it follows the layer's level, so each layer up is one row\n" + \
		"taller. Set it to override just this layer, without moving it in the\n" + \
		"stack: the z band still comes from the level, so a taller wall can never\n" + \
		"put a layer behind the one it sits on.\n\n" + \
		"It lives on the generated faces layer, so erasing the terrain clears it."
	_rows_spin.value_changed.connect(_on_cliff_rows_changed)
	toolbar.add_child(_rows_spin)

	var reset := Button.new()
	reset.name = "CliffRowsReset"
	reset.icon = get_theme_icon("Reload", "EditorIcons")
	reset.flat = true
	reset.tooltip_text = "Automatic cliff height: follow the layer's level"
	reset.focus_mode = Control.FOCUS_NONE
	reset.pressed.connect(_on_cliff_rows_reset)
	toolbar.add_child(reset)
	_rows_reset = reset

	var anchor := toolbar.get_node_or_null("SymmetryOptions")
	if anchor != null:
		toolbar.move_child(cliff, anchor.get_index() + 1)
		toolbar.move_child(_rows_spin, anchor.get_index() + 2)
		toolbar.move_child(reset, anchor.get_index() + 3)
		toolbar.move_child(_level_spin, anchor.get_index() + 4)
		toolbar.move_child(level_reset, anchor.get_index() + 5)
	_sync_cliff_rows()


var _rows_spin: SpinBox
var _rows_reset: Button
var _level_spin: SpinBox
var _level_reset: Button
var _rows_syncing := false


func _sync_cliff_rows() -> void:
	if _rows_spin == null:
		return
	var relevant := false
	if tileset != null and selected_entry >= 0:
		var t := BetterTerrain.get_terrain(tileset, selected_entry)
		relevant = t.valid and CLIFF_DATA.all_configs(tileset).has(str(t.name))
	if not relevant and tilemap != null:
		relevant = CLIFF_TERRAIN.find_faces(tilemap) != null
	for c in [_level_spin, _level_reset, _rows_spin, _rows_reset]:
		if c != null:
			c.visible = relevant
	if not relevant:
		return
	# Use read-only find_faces during selection changes; faces_layer can mutate the scene tree.
	var faces = CLIFF_TERRAIN.find_faces(tilemap)
	var has_layer := faces != null
	_rows_spin.editable = true
	_rows_reset.disabled = not has_layer or int(faces.get("cliffRows")) < 0
	_rows_syncing = true
	_rows_spin.value = CLIFF_TERRAIN.rows_for(tilemap) if tilemap != null else 0
	if _level_spin != null:
		var takes_part := tilemap != null and CLIFF_TERRAIN.is_level(tilemap)
		_level_spin.editable = takes_part
		_level_spin.value = CLIFF_TERRAIN.level_of(tilemap) if takes_part else 0
		_level_reset.disabled = not has_layer or int(faces.get("cliffLevel")) < 0
	_rows_syncing = false
	_rows_spin.tooltip_text = \
		"How many rows tall this layer's wall is. Empty means the layer's level,\n" + \
		"which is what a stack of layers uses. Set it by hand when there is no\n" + \
		"stack: a single layer is level 0, the base, and a base grows no wall\n" + \
		"unless this says how tall one should be."


func _on_cliff_rows_changed(v: float) -> void:
	if _rows_syncing or tilemap == null:
		return
	CLIFF_TERRAIN.set_rows_override(tilemap, int(v))
	_rebuild_cliffs_now()
	_sync_cliff_rows()


func _on_cliff_level_changed(v: float) -> void:
	if _rows_syncing or tilemap == null:
		return
	var faces = CLIFF_TERRAIN.find_faces(tilemap)
	if faces == null:
		faces = CLIFF_TERRAIN.faces_layer(tilemap, true)
	if faces == null:
		return
	faces.set("cliffLevel", int(v))
	_rebuild_cliffs_now()
	_sync_cliff_rows()


func _on_cliff_level_reset() -> void:
	if tilemap == null:
		return
	var faces = CLIFF_TERRAIN.find_faces(tilemap)
	if faces != null:
		faces.set("cliffLevel", -1)
	_rebuild_cliffs_now()
	_sync_cliff_rows()


func _on_cliff_rows_reset() -> void:
	if tilemap == null:
		return
	CLIFF_TERRAIN.set_rows_override(tilemap, -1)
	_rebuild_cliffs_now()
	_sync_cliff_rows()


func _icon_or_text(button: Button, own_path: String, names: Array, fallback: String) -> void:
	if ResourceLoader.exists(own_path):
		var tex = load(own_path)
		if tex != null:
			button.icon = tex
			return
	for n in names:
		if has_theme_icon(n, "EditorIcons"):
			button.icon = get_theme_icon(n, "EditorIcons")
			return
	button.text = fallback


func _on_exemplar_pressed() -> void:
	if !_require_terrain("fill in a lookup table"):
		return
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	if !t.valid:
		_say(tr("That terrain could not be read."))
		return
	if t.type != BetterTerrain.TerrainType.EXEMPLAR:
		_say(tr("That terrain is not of the Patch type. Change its type in its properties first."))
		return
	if is_instance_valid(_exemplar_window):
		_exemplar_window.queue_free()
	_exemplar_window = EXEMPLAR_EDITOR_SCRIPT.new()
	get_tree().root.add_child(_exemplar_window)
	_exemplar_window.setup(tileset, selected_entry, t.name, t.color)
	_exemplar_window.config_changed.connect(_mark_cliffs_dirty)
	_exemplar_window.popup_centered()


func _on_cliff_pressed() -> void:
	if !_require_terrain("configure a cliff face"):
		return
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	if !t.valid:
		_say(tr("That terrain could not be read."))
		return
	if is_instance_valid(_cliff_window):
		_cliff_window.queue_free()
	_cliff_window = CLIFF_EDITOR_SCRIPT.new()
	get_tree().root.add_child(_cliff_window)
	_cliff_window.setup(tileset, selected_entry, t.name,
		CLIFF_TERRAIN.rows_for(tilemap) if tilemap != null and CLIFF_TERRAIN.is_level(tilemap) else -1)
	_cliff_window.clear_requested.connect(_clear_cliff_config)
	_cliff_window.config_changed.connect(_mark_cliffs_dirty)
	_cliff_window.config_changed.connect(_sync_cliff_rows)
	_cliff_window.config_changed.connect(_offer_first_wall)
	_cliff_window.popup_centered()


func _clear_cliff_config(ts: TileSet, terrain_name: String) -> void:
	var before := CLIFF_DATA.all_configs(ts).duplicate(true)
	if not before.has(terrain_name):
		return
	var after := before.duplicate(true)
	after.erase(terrain_name)
	undo_manager.create_action(tr("Clear cliff configuration"), UndoRedo.MERGE_DISABLE, ts)
	undo_manager.add_do_method(self, &"_restore_cliff_configs", ts, after)
	undo_manager.add_undo_method(self, &"_restore_cliff_configs", ts, before)
	undo_manager.commit_action()


func _restore_cliff_configs(ts: TileSet, configs: Dictionary) -> void:
	ts.set_meta(CLIFF_DATA.CLIFF_META, configs.duplicate(true))
	ts.emit_changed()
	if is_instance_valid(_cliff_window) and _cliff_window.visible and _cliff_window.tile_set == ts:
		_cliff_window.reload_config()
	if ts == tileset:
		_mark_cliffs_dirty()
		_sync_cliff_rows()


func _offer_first_wall() -> void:
	if tilemap == null or tileset == null or selected_entry < 0:
		return
	if not CLIFF_TERRAIN.is_level(tilemap):
		return
	if CLIFF_TERRAIN.level_of(tilemap) > 0 or CLIFF_TERRAIN.explicit_rows(tilemap) >= 0:
		return
	var t := BetterTerrain.get_terrain(tileset, selected_entry)
	if not t.valid:
		return
	var height := int(CLIFF_DATA.config_of(tileset, str(t.name)).get("height", 2))
	CLIFF_TERRAIN.set_rows_override(tilemap, height)
	_rebuild_cliffs_now()
	_sync_cliff_rows()
	# Said in passing: the wall appeared on its own, and Height in the toolbar is where to change it.
	EditorInterface.get_editor_toaster().push_toast(tr("Cliff walls shown on this layer, %d high. Change it with Height in the toolbar.") % height)


func _on_rebuild_cliffs_pressed() -> void:
	if !tileset:
		_say(tr("Open a TileSet first."))
		return
	if !tilemap:
		_say(tr("Select the TileMapLayer whose cliff faces you want to rebuild."))
		return
	var dry: Dictionary = CLIFF_TERRAIN.rebuild(tilemap, BetterTerrain, true)
	if dry.written == 0 and dry.cleared == 0:
		if not CLIFF_TERRAIN.is_level(tilemap):
			_say(tr("This layer paints no terrain with a cliff sheet, so there is nothing to build."))
		elif CLIFF_TERRAIN.rows_for(tilemap) <= 0:
			_say(tr("This layer's wall height is 0. Raise Height in the toolbar, or the layer's level."))
		else:
			_say(tr("The faces on this layer already match the terrain. Nothing to rebuild."))
		return

	var text := "Rebuild cliff faces on this layer?\n\n%d face cells written, %d taken back." % [dry.written, dry.cleared]
	if not dry.conflicts.is_empty():
		text += "\n%d of them stand over painted ground and will simply draw in front of it." % dry.conflicts.size()
	if dry.get("covered", 0) > 0:
		text += "\n%d more were skipped: a higher layer already covers them, so they would be wall you cannot see." % dry.covered
	if not dry.missing.is_empty():
		var worst := []
		for k in dry.missing.keys():
			worst.append("%s x%d" % [k, dry.missing[k]])
		text += "\n\nEmpty slots these cells asked for (left alone):\n" + ", ".join(worst)
	text += "\n\nOnly the generated layer is written; your own tiles are never touched."

	var popup := ConfirmationDialog.new()
	popup.dialog_text = tr(text)
	add_child(popup)
	popup.confirmed.connect(func() -> void:
		var rep: Dictionary = CLIFF_TERRAIN.rebuild(tilemap, BetterTerrain, false)
		print("[BetterTerrain] Cliffs: %d written, %d cleared, %d adopted, %d covered" % [
			rep.written, rep.cleared, rep.conflicts.size(), rep.get("covered", 0)])
		update_overlay.emit()
	)
	popup.canceled.connect(popup.queue_free)
	popup.popup_centered()


const TILEMAP_CONVERT_HINT := "To convert it, open the TileMap bottom panel with the node selected,\nclick the toolbox icon in the top-right corner and choose\n\"Extract TileMap layers as individual TileMapLayer nodes\"."

var _unsupported_notice: Label


## Notice over the dock for a deprecated TileMap, null clears it.
var _no_tileset_notice: Control
var _watched_layer: TileMapLayer


func show_missing_tileset(layer: TileMapLayer) -> void:
	var missing := layer != null and layer.tile_set == null
	if not missing and _no_tileset_notice == null:
		return
	if _no_tileset_notice == null:
		_no_tileset_notice = CenterContainer.new()
		_no_tileset_notice.name = "NoTileSetNotice"
		_no_tileset_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		var box := VBoxContainer.new()
		box.add_theme_constant_override("separation", 12)
		_no_tileset_notice.add_child(box)
		var text := Label.new()
		text.text = "This TileMapLayer has no TileSet yet.\nCreate one, then add your tileset image as an atlas in Godot's TileSet tab."
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		box.add_child(text)
		var create := Button.new()
		create.name = "CreateTileSet"
		create.text = "Create TileSet"
		create.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		create.pressed.connect(_create_tileset)
		box.add_child(create)
		add_child(_no_tileset_notice)
	if _watched_layer != null and is_instance_valid(_watched_layer) and _watched_layer.changed.is_connected(_on_watched_layer_changed):
		_watched_layer.changed.disconnect(_on_watched_layer_changed)
	_watched_layer = layer if missing else null
	if missing:
		layer.changed.connect(_on_watched_layer_changed)
	_no_tileset_notice.visible = missing
	if _unsupported_notice == null or not _unsupported_notice.visible:
		$VBox.visible = not missing


func _on_watched_layer_changed() -> void:
	if _watched_layer != null and _watched_layer.tile_set != null:
		tileset_created.emit(_watched_layer)


func _create_tileset() -> void:
	if tilemap == null or tilemap.tile_set != null:
		return
	undo_manager.create_action(tr("Create TileSet"), UndoRedo.MERGE_DISABLE, tilemap)
	undo_manager.add_do_property(tilemap, &"tile_set", TileSet.new())
	undo_manager.add_undo_property(tilemap, &"tile_set", null)
	undo_manager.commit_action()


func show_unsupported(node: TileMap) -> void:
	if node == null and _unsupported_notice == null:
		return
	if _unsupported_notice == null:
		_unsupported_notice = Label.new()
		_unsupported_notice.name = "UnsupportedNotice"
		_unsupported_notice.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		_unsupported_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_unsupported_notice.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_unsupported_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		add_child(_unsupported_notice)
	_unsupported_notice.visible = node != null
	$VBox.visible = node == null
	if node != null:
		_unsupported_notice.text = "%s is a TileMap node. Better Tile Editor does not support TileMap nodes, only TileMapLayer nodes.\n\n%s" % [node.name, TILEMAP_CONVERT_HINT]


const OPTION_LABELS := {
	SHOW_REFRESH_SETTING: "Show Refresh button",
	HIDE_NATIVE_TILES_SETTING: "Hide Godot Tiles tab",
	HIDE_NATIVE_PATTERNS_SETTING: "Hide Godot Patterns tab",
	HIDE_NATIVE_TERRAINS_SETTING: "Hide Godot Terrains tab",
	RENAME_TAB_SETTING: "Rename Better Tile Editor and TileMap to Tiles, like a badass",
	SHOW_TILE_GRID_SETTING: "Show tile grid",
	SHOW_EMPTY_ATLAS_SETTING: "Show the atlases' empty space",
	SHOW_ZOOM_SETTING: "Show zoom control",
	SHOW_TOOL_NAMES_SETTING: "Show tool names in the toolbar",
	HIDE_SUPPORT_SETTING: "Hide support layers in scene tree",
	HIDE_TYPE_ICONS_SETTING: "Hide terrain type icons in the list",
	SHOW_HIDDEN_SETTING: "Show the _hidden group (terrains the slope set-up makes)",
	HIDE_SCENES_SETTING: "Hide the Scenes group (the tile set's scene tiles)",
}

var _options_window: AcceptDialog
var _option_checks := {}
var _rebuild_cliffs_button: Button
var _picker_modifier_options: OptionButton
var _reload_button: Button
var _collision_color_button: ColorPickerButton
var _collision_on_map_check: CheckBox


func _add_options_button() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null:
		return
	var settings := EditorInterface.get_editor_settings()
	for setting in OPTION_LABELS:
		if not settings.has_setting(setting):
			settings.set_setting(setting, false)
		settings.set_initial_value(setting, false, false)
	if not settings.has_setting(PICKER_MODIFIER_SETTING):
		settings.set_setting(PICKER_MODIFIER_SETTING, PickerModifier.ALT)
	settings.set_initial_value(PICKER_MODIFIER_SETTING, PickerModifier.ALT, false)
	tile_view.show_grid = bool(settings.get_setting(SHOW_TILE_GRID_SETTING))
	tile_view.trim_empty = not bool(settings.get_setting(SHOW_EMPTY_ATLAS_SETTING))
	zoom_slider_container.visible = bool(settings.get_setting(SHOW_ZOOM_SETTING))
	var options := Button.new()
	options.name = "Options"
	options.icon = get_theme_icon("Tools", "EditorIcons")
	options.tooltip_text = "Options"
	options.flat = true
	options.focus_mode = Control.FOCUS_NONE
	options.pressed.connect(_open_options)
	toolbar.add_child(options)
	var b := Button.new()
	b.name = "ReloadPlugin"
	b.text = "\u21bb"
	b.tooltip_text = "Reload the plugin: picks up changes to the editor scripts without restarting Godot"
	b.focus_mode = Control.FOCUS_NONE
	b.visible = bool(settings.get_setting(SHOW_REFRESH_SETTING))
	b.pressed.connect(_on_reload_plugin_pressed)
	toolbar.add_child(b)
	_reload_button = b
	_build_options_window()
	var live := toolbar.get_node_or_null("LiveTest")
	if live:
		toolbar.move_child(options, live.get_index())
		toolbar.move_child(b, live.get_index())


func _build_options_window() -> void:
	var settings := EditorInterface.get_editor_settings()
	_options_window = AcceptDialog.new()
	_options_window.name = "OptionsWindow"
	_options_window.title = "Better Tile Editor options"
	_options_window.ok_button_text = "Close"
	_options_window.exclusive = false
	_options_window.transient = true
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 14)
	_options_window.add_child(columns)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	columns.add_child(box)
	columns.add_child(VSeparator.new())
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	side.custom_minimum_size.x = 300
	columns.add_child(side)

	box.add_child(_options_heading("Interface"))
	for setting in OPTION_LABELS:
		var check := CheckBox.new()
		check.name = setting.get_file()
		check.text = OPTION_LABELS[setting]
		check.focus_mode = Control.FOCUS_NONE
		check.toggled.connect(_set_option.bind(setting))
		box.add_child(check)
		_option_checks[setting] = check

	side.add_child(_options_heading("Tile picker"))
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "Pick with click while holding"
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	_picker_modifier_options = OptionButton.new()
	_picker_modifier_options.name = "PickerModifier"
	for index in PICKER_MODIFIER_NAMES.size():
		_picker_modifier_options.add_item(PICKER_MODIFIER_NAMES[index], index)
	_picker_modifier_options.tooltip_text = "Holding this key turns a left click on the map into a pick,\nwhatever tool is active."
	_picker_modifier_options.item_selected.connect(func(index: int) -> void:
		settings.set_setting(PICKER_MODIFIER_SETTING, index)
		_update_picker_tooltip())
	row.add_child(_picker_modifier_options)
	side.add_child(row)

	side.add_child(HSeparator.new())
	side.add_child(_options_heading("Collisions"))
	var color_row := HBoxContainer.new()
	var color_label := Label.new()
	color_label.text = "Overlay colour and opacity"
	color_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_label)
	_collision_color_button = ColorPickerButton.new()
	_collision_color_button.name = "CollisionColor"
	_collision_color_button.custom_minimum_size = Vector2(48, 0)
	_collision_color_button.edit_alpha = true
	_collision_color_button.color_changed.connect(func(color: Color) -> void:
		settings.set_setting(COLLISIONS.OVERLAY_COLOR_SETTING, color)
		_sync_collision_mode())
	color_row.add_child(_collision_color_button)
	side.add_child(color_row)
	_collision_on_map_check = CheckBox.new()
	_collision_on_map_check.name = "CollisionOnMap"
	_collision_on_map_check.text = "Show collisions on the map too"
	_collision_on_map_check.focus_mode = Control.FOCUS_NONE
	_collision_on_map_check.toggled.connect(func(on: bool) -> void:
		settings.set_setting(COLLISIONS.OVERLAY_ON_MAP_SETTING, on)
		update_overlay.emit())
	side.add_child(_collision_on_map_check)

	# Actions, not settings, kept apart from them. Slopes are set up from the right-click
	# menu of a Match tiles terrain, where they are used.
	side.add_child(HSeparator.new())
	side.add_child(_options_heading("Actions"))
	_rebuild_cliffs_button = Button.new()
	_rebuild_cliffs_button.text = "Rebuild cliff faces…"
	_rebuild_cliffs_button.tooltip_text = "Preview and rebuild the generated cliff faces on the selected layer."
	_rebuild_cliffs_button.pressed.connect(func() -> void:
		_options_window.hide()
		_on_rebuild_cliffs_pressed())
	side.add_child(_rebuild_cliffs_button)

	_options_window.about_to_popup.connect(_sync_options_window)
	add_child(_options_window)


func _options_heading(text: String) -> Label:
	var heading := Label.new()
	heading.text = text
	heading.add_theme_color_override("font_color", get_theme_color("accent_color", "Editor"))
	return heading


func _open_options() -> void:
	_options_window.popup_centered(Vector2i(820, 0))


func _sync_options_window() -> void:
	var settings := EditorInterface.get_editor_settings()
	for setting in _option_checks:
		_option_checks[setting].set_pressed_no_signal(bool(settings.get_setting(setting)))
	_picker_modifier_options.select(_picker_modifier())
	_collision_color_button.color = COLLISIONS.overlay_color()
	_collision_on_map_check.set_pressed_no_signal(COLLISIONS.overlay_on_map())
	_rebuild_cliffs_button.disabled = tilemap == null or tileset == null


func _set_option(enabled: bool, setting: String) -> void:
	var settings := EditorInterface.get_editor_settings()
	_store_view_mode(setting, enabled)
	tile_view.show_grid = bool(settings.get_setting(SHOW_TILE_GRID_SETTING))
	if setting == SHOW_EMPTY_ATLAS_SETTING:
		tile_view.trim_empty = not enabled
		tile_view.queue_redraw()
	zoom_slider_container.visible = bool(settings.get_setting(SHOW_ZOOM_SETTING))
	_reload_button.visible = bool(settings.get_setting(SHOW_REFRESH_SETTING))
	if setting == SHOW_TOOL_NAMES_SETTING:
		_apply_tool_names()
	if setting in [HIDE_TYPE_ICONS_SETTING, SHOW_HIDDEN_SETTING, HIDE_SCENES_SETTING] and tileset != null:
		rebuild_terrain_list()
	options_changed.emit()


# Defer both toggles because disabling the plugin frees this handler node.
func _on_reload_plugin_pressed() -> void:
	var tree := get_tree()
	var plugin := String(get_script().resource_path).trim_prefix("res://addons/").get_slice("/", 0)
	if plugin.is_empty() or not EditorInterface.is_plugin_enabled(plugin):
		push_warning("Reload: no enabled plugin at addons/%s" % plugin)
		return
	tree.create_timer(0.1).timeout.connect(func() -> void:
		EditorInterface.set_plugin_enabled(plugin, false)
		tree.create_timer(0.1).timeout.connect(func() -> void:
			EditorInterface.set_plugin_enabled(plugin, true)
			print("[BetterTerrain] plugin %s reloaded" % plugin)
		)
	)


func _hook_cliff_level_watch() -> void:
	var insp := EditorInterface.get_inspector()
	if insp != null and not insp.property_edited.is_connected(_on_inspector_property_edited):
		insp.property_edited.connect(_on_inspector_property_edited)


func _on_inspector_property_edited(property: String) -> void:
	if property != "cliffLevel" and property != "cliffRows":
		return
	var obj = EditorInterface.get_inspector().get_edited_object()
	if not (obj is TileMapLayer):
		return
	if str(obj.name) == CLIFF_TERRAIN.FACES_LAYER_NAME:
		obj = obj.get_parent()
	if not (obj is TileMapLayer):
		return
	var rep: Dictionary = CLIFF_TERRAIN.rebuild(obj, BetterTerrain, false)
	if rep.written == 0 and rep.cleared == 0 and rep.conflicts.is_empty():
		return
	var msg := "[BetterTerrain] %s level changed: %d written, %d cleared" % [
		obj.name, rep.written, rep.cleared]
	if not rep.conflicts.is_empty():
		msg += ", %d cells left alone (press Rebuild cliffs to adopt them)" % rep.conflicts.size()
	print(msg)
	update_overlay.emit()


var _order_watch_parent: Node = null
var _order_watch_timer: Timer = null


func _build_order_watch_timer() -> void:
	_order_watch_timer = Timer.new()
	_order_watch_timer.one_shot = true
	_order_watch_timer.wait_time = 0.1
	_order_watch_timer.timeout.connect(_rebuild_cliffs_now)
	add_child(_order_watch_timer)


func _watch_layer_order() -> void:
	# Undo changes bypass paint handlers, so watch history changes for regeneration.
	if undo_manager != null and not undo_manager.version_changed.is_connected(_mark_cliffs_dirty):
		undo_manager.version_changed.connect(_mark_cliffs_dirty)

	var parent: Node = tilemap.get_parent() if tilemap != null else null
	if parent == _order_watch_parent:
		return
	if is_instance_valid(_order_watch_parent) \
			and _order_watch_parent.child_order_changed.is_connected(_on_layer_order_changed):
		_order_watch_parent.child_order_changed.disconnect(_on_layer_order_changed)
	_order_watch_parent = parent
	if parent != null and not parent.child_order_changed.is_connected(_on_layer_order_changed):
		parent.child_order_changed.connect(_on_layer_order_changed)


func _on_layer_order_changed() -> void:
	if _order_watch_timer != null:
		_order_watch_timer.start()


func _rebuild_cliffs_now() -> void:
	if tile_view.editing_rules():
		_mark_cliffs_dirty()
		return
	var targets: Array = []
	if is_instance_valid(_order_watch_parent):
		targets = _order_watch_parent.get_children()
	elif tilemap != null:
		targets = [tilemap]
	if targets.is_empty():
		return

	var changed := false
	for c in targets:
		if c is TileMapLayer:
			var rep: Dictionary = CLIFF_TERRAIN.rebuild(c, BetterTerrain, false)
			changed = changed or rep.written > 0 or rep.cleared > 0
	for c in targets:
		if c is TileMapLayer:
			var lk: Dictionary = EXEMPLAR_TERRAIN.rebuild(c, BetterTerrain)
			changed = changed or lk.region > 0 or lk.edges > 0

	if changed:
		update_overlay.emit()


func _mark_cliffs_dirty() -> void:
	if _order_watch_timer != null:
		_order_watch_timer.start()


func _warn_duplicate_name(terrain_name: String) -> void:
	if tileset == null or terrain_name.is_empty():
		return
	var n := 0
	for i in BetterTerrain.terrain_count(tileset):
		if BetterTerrain.get_terrain(tileset, i).get("name", "") == terrain_name:
			n += 1
	if n > 1:
		_say("%d terrains are called \"%s\". That is allowed, but a cliff sheet goes by name, so they would share one. Rename one of them if that is not what you meant." % [n, terrain_name])


func _say(message: String) -> void:
	var popup := AcceptDialog.new()
	popup.dialog_text = message
	popup.title = tr("Cliff faces")
	add_child(popup)
	popup.confirmed.connect(popup.queue_free)
	popup.canceled.connect(popup.queue_free)
	popup.popup_centered()


func _require_terrain(what: String) -> bool:
	if !tileset:
		_say(tr("Open a TileSet first."))
		return false
	if BetterTerrain.terrain_count(tileset) == 0:
		_say(tr("This TileSet has no terrains yet."))
		return false
	if selected_entry < 0:
		_say(tr("Pick a terrain in the list first: %s belongs to one terrain.") % what)
		return false
	return true


#region what the bucket fills

var _fill_seen: Button = null
var _fill_layer: Button = null
var _fill_rule: VSeparator = null


func _build_fill_scope() -> void:
	var toolbar := get_node_or_null("VBox/Toolbar")
	if toolbar == null or fill_button == null:
		return
	var group := ButtonGroup.new()
	_fill_seen = _fill_scope_button(toolbar, group, "FillSeen", "Bucket: what you see",
		"The bucket fills what LOOKS the same as the cell you click, across the\n" + \
		"layers: a patch painted on a layer above breaks the ground below it in\n" + \
		"two, and the fill stops at it.")
	_fill_layer = _fill_scope_button(toolbar, group, "FillLayer", "Bucket: this layer",
		"The bucket fills the region on the layer you are editing, and ignores\n" + \
		"what any other layer has there.")
	_fill_rule = VSeparator.new()
	_fill_rule.name = "FillScopeRule"
	toolbar.add_child(_fill_rule)

	var at := fill_button.get_index() + 1
	toolbar.move_child(_fill_rule, at)
	toolbar.move_child(_fill_seen, at + 1)
	toolbar.move_child(_fill_layer, at + 2)

	var seen := true
	if Engine.is_editor_hint():
		var settings := EditorInterface.get_editor_settings()
		if settings != null and settings.has_setting(FILL_SCOPE_SETTING):
			seen = bool(settings.get_setting(FILL_SCOPE_SETTING))
	_fill_seen.set_pressed_no_signal(seen)
	_fill_layer.set_pressed_no_signal(not seen)
	_sync_fill_scope()
	fill_button.toggled.connect(func(_on): _sync_fill_scope())


func _fill_scope_button(toolbar: Node, group: ButtonGroup, scope_name: String, text: String,
		tip: String) -> Button:
	var b := Button.new()
	b.name = scope_name
	_icon_or_text(b, ICON_DIR + scope_name + ".svg", [], text)
	b.tooltip_text = "%s\n\n%s" % [text, tip]
	b.toggle_mode = true
	b.button_group = group
	b.flat = true
	b.focus_mode = Control.FOCUS_NONE
	b.toggled.connect(func(on: bool):
		if on:
			_store_view_mode(FILL_SCOPE_SETTING, b == _fill_seen))
	toolbar.add_child(b)
	return b


func _sync_fill_scope() -> void:
	if _fill_seen == null:
		return
	var showing: bool = fill_button != null and fill_button.button_pressed
	_fill_seen.visible = showing
	_fill_layer.visible = showing
	if _fill_rule != null:
		_fill_rule.visible = showing


func _fill_by_sight() -> bool:
	return _fill_layer == null or not _fill_layer.button_pressed

#endregion


#region the scatter bag

const SINGLE_BAG_SCRIPT := preload("res://addons/better-tile-editor/editor/SingleTileBag.gd")
const QUICK_MATCH := preload("res://addons/better-tile-editor/editor/QuickMatch.gd")
const QUICK_ANIMATION_SCRIPT := preload("res://addons/better-tile-editor/editor/QuickAnimation.gd")
const COVERAGE := preload("res://addons/better-tile-editor/editor/TerrainCoverage.gd")
const COVERAGE_WINDOW := preload("res://addons/better-tile-editor/editor/CoverageWindow.gd")
const QUARTER_PIECES := preload("res://addons/better-tile-editor/editor/QuarterPieces.gd")
const QUICK_MATCH_PREVIEW := preload("res://addons/better-tile-editor/editor/QuickMatchPreview.gd")
var _single_bag: HBoxContainer
var _bag_column: VBoxContainer
var _add_favorite_button: Button

func _build_scatter_bag() -> void:
	_scatter_bag = SCATTER_BAG_SCRIPT.new()
	var split := $VBox/HSplit/Editors
	_bag_column = VBoxContainer.new()
	split.add_child(_bag_column)
	split.move_child(_bag_column, 0)
	_bag_column.add_child(_scatter_bag)
	_scatter_bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_single_bag = SINGLE_BAG_SCRIPT.new()
	_single_bag.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_bag_column.add_child(_single_bag)
	_single_bag.entry_selected.connect(func(entry: Dictionary): _set_single_tile(entry.source, entry.origin, entry.size, entry.alt))
	_single_bag.config_changed.connect(_edit_single_favorites)
	_single_bag.collapsed_changed.connect(func(): split.split_offset = 0)
	_add_favorite_button = Button.new()
	_add_favorite_button.flat = true
	_add_favorite_button.focus_mode = Control.FOCUS_NONE
	_add_favorite_button.icon = get_theme_icon("Pin", "EditorIcons")
	_add_favorite_button.tooltip_text = "Add selected tiles to favorites (right-click in the atlas)"
	_add_favorite_button.pressed.connect(_add_single_favorite)
	var toolbar := replace_button.get_parent()
	toolbar.add_child(_add_favorite_button)
	toolbar.move_child(_add_favorite_button, replace_button.get_index() + 1)
	tile_view.favorite_requested.connect(_favorite_from_atlas)
	_build_quick_terrain_buttons(toolbar, _add_favorite_button.get_index() + 1)
	_single_bag.hide()
	_bag_column.hide()
	_add_favorite_button.hide()
	_scatter_bag.visible = false
	_scatter_bag.config_changed.connect(_on_scatter_config_changed)
	_scatter_bag.reroll_requested.connect(_on_scatter_reroll)
	_scatter_bag.apply_requested.connect(_on_scatter_apply)
	tile_view.tile_picked.connect(_on_scatter_picked)
	tile_view.tile_dropped.connect(_on_scatter_dropped)


func _is_scatter(type: int) -> bool:
	if tileset == null or type < 0:
		return false
	var t = BetterTerrain.get_terrain(tileset, type)
	return t.valid and int(t.type) == BetterTerrain.TerrainType.SCATTER


func _sync_scatter_bag() -> void:
	if _scatter_bag == null:
		return
	var is_scatter := _is_scatter(selected_entry)
	_scatter_bag.visible = is_scatter
	var single := _is_single(selected_entry)
	var show_favorites := single and not (tileset.get_meta(SINGLE_BAG_SCRIPT.META, []) as Array).is_empty()
	_bag_column.visible = is_scatter or show_favorites
	if show_favorites and not _single_bag.visible:
		$VBox/HSplit/Editors.split_offset = 0
	_single_bag.visible = show_favorites
	_add_favorite_button.visible = single
	_sync_quick_terrain_buttons()
	tile_view.single_tile_favorites = single
	if single:
		_single_bag.setup(tileset, BetterTerrain.single_block_of(tileset, selected_entry))
		_add_favorite_button.disabled = BetterTerrain.single_block_of(tileset, selected_entry).is_empty()
	tile_view.pick_tiles = is_scatter or _is_single(selected_entry)
	if not is_scatter:
		_sync_scatter_outlines()
		return
	var t = BetterTerrain.get_terrain(tileset, selected_entry)
	_scatter_bag.setup(tileset, selected_entry, str(t.name), t.color)
	_sync_scatter_outlines()


func _sync_scatter_outlines() -> void:
	var entries := []
	if _is_scatter(selected_entry):
		for e in SCATTER_TERRAIN.config_of(tileset, selected_entry).get("bag", []):
			entries.push_back(SCATTER_TERRAIN.normalise_entry(e))
	elif _is_single(selected_entry):
		var block: Dictionary = BetterTerrain.single_block_of(tileset, selected_entry)
		if not block.is_empty():
			entries.push_back({source = block.source, origin = block.origin, size = block.size, weight = 1.0})
	if not entries.is_empty():
		var t = BetterTerrain.get_terrain(tileset, selected_entry)
		tile_view.mark_colour = t.color
	tile_view.marked_blocks = entries
	tile_view.queue_redraw()


func _on_scatter_picked(source_id: int, origin: Vector2i, block_size: Vector2i) -> void:
	if _collision_mode():
		_open_collision_shape(source_id, origin, block_size)
		return
	if _data_mode():
		_data_select_box(source_id, origin, block_size, Input.is_key_pressed(KEY_SHIFT))
		return
	if _is_single(selected_entry):
		_set_single_tile(source_id, origin, block_size)
		return
	if _scatter_bag != null and _scatter_bag.visible:
		_scatter_bag.add_entry(source_id, origin, block_size)


func _on_scatter_dropped(source_id: int, coord: Vector2i) -> void:
	if _is_single(selected_entry):
		return
	if _scatter_bag != null and _scatter_bag.visible:
		_scatter_bag.remove_at(source_id, coord)


func _single_cells(type: int, cells: Array, anchor: Vector2i) -> Array:
	if paint_mode == PaintMode.ERASE or not _is_single(type):
		return cells
	return BetterTerrain.single_block_cells(tileset, type, cells, anchor)


func _is_single(type: int) -> bool:
	if tileset == null:
		return false
	if type == BetterTerrain.TileCategory.SINGLE:
		return true
	if type < 0:
		return false
	var t = BetterTerrain.get_terrain(tileset, type)
	return t.valid and int(t.type) == BetterTerrain.TerrainType.SINGLE


func _set_single_tile(source_id: int, coord: Vector2i, tile_size := Vector2i.ONE, alternate := 0) -> void:
	if tileset == null or not _is_single(selected_entry):
		return
	var id := selected_entry
	var was: Dictionary = BetterTerrain.single_block_of(tileset, id)
	if not was.is_empty() and was.source == source_id and was.origin == coord and was.alt == alternate and was.size == tile_size:
		return
	undo_manager.create_action(tr("Pick the tile"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(BetterTerrain, &"set_single_tile", tileset, source_id, coord, alternate, tile_size, false)
	if was.is_empty():
		undo_manager.add_undo_method(BetterTerrain, &"set_single_tile", tileset, -1, Vector2i.ZERO, 0, Vector2i.ONE, false)
	else:
		undo_manager.add_undo_method(BetterTerrain, &"set_single_tile", tileset, was.source, was.origin, was.alt, was.size, false)
	undo_manager.add_do_method(self, &"_after_single_pick")
	undo_manager.add_undo_method(self, &"_after_single_pick")
	undo_manager.commit_action()


func _after_single_pick() -> void:
	if _is_single(selected_entry):
		var block := BetterTerrain.single_block_of(tileset, selected_entry)
		_single_bag.select_entry(block)
		_add_favorite_button.disabled = block.is_empty()
		_sync_scatter_outlines()
	_sync_scene_selection()
	_sync_quick_terrain_buttons()
	update_overlay.emit()


func _on_scatter_config_changed(cfg: Dictionary) -> void:
	if tileset == null or not _is_scatter(selected_entry):
		return
	var before := SCATTER_TERRAIN.config_of(tileset, selected_entry)
	var id := selected_entry
	# Dragging sends lots of edits, keep one undo step with the first and last value.
	undo_manager.create_action(tr("Edit scatter bag"), UndoRedo.MERGE_ENDS, tileset)
	undo_manager.add_do_method(SCATTER_TERRAIN, &"set_config", tileset, id, cfg, false)
	undo_manager.add_undo_method(SCATTER_TERRAIN, &"set_config", tileset, id, before, false)
	undo_manager.add_do_method(self, &"_queue_scatter_rebuild")
	undo_manager.add_undo_method(self, &"_queue_scatter_rebuild")
	undo_manager.add_do_method(self, &"_sync_scatter_outlines")
	undo_manager.add_undo_method(self, &"_sync_scatter_outlines")
	undo_manager.commit_action()
	update_overlay.emit()


const SCATTER_LIVE_DELAY := 0.15

var _scatter_rebuild_timer: Timer


# After the edits stops: notify the TileSet once and repaint if Live change is on.
func _queue_scatter_rebuild() -> void:
	if _scatter_rebuild_timer == null:
		_scatter_rebuild_timer = Timer.new()
		_scatter_rebuild_timer.one_shot = true
		_scatter_rebuild_timer.wait_time = SCATTER_LIVE_DELAY
		_scatter_rebuild_timer.timeout.connect(_rebuild_scatter_now)
		add_child(_scatter_rebuild_timer)
	_scatter_rebuild_timer.start()


func _rebuild_scatter_now() -> void:
	if tileset == null:
		return
	tileset.emit_changed()
	if tilemap == null or not _is_scatter(selected_entry) \
			or not bool(SCATTER_TERRAIN.config_of(tileset, selected_entry).get("live", false)):
		return
	SCATTER_TERRAIN.rebuild(tilemap)
	update_overlay.emit()


func _on_scatter_reroll() -> void:
	if tileset == null or not _is_scatter(selected_entry):
		return
	var before := SCATTER_TERRAIN.config_of(tileset, selected_entry)
	var after := before.duplicate(true)
	after["seed"] = randi()
	var id := selected_entry
	undo_manager.create_action(tr("Reroll scatter"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(SCATTER_TERRAIN, &"set_config", tileset, id, after)
	undo_manager.add_undo_method(SCATTER_TERRAIN, &"set_config", tileset, id, before)
	if tilemap != null:
		undo_manager.add_do_method(SCATTER_TERRAIN, &"rebuild", tilemap)
		undo_manager.add_undo_method(SCATTER_TERRAIN, &"rebuild", tilemap)
	undo_manager.commit_action()
	update_overlay.emit()


func _on_scatter_apply() -> void:
	if tilemap == null:
		return
	var report: Dictionary = SCATTER_TERRAIN.rebuild(tilemap)
	_say("Scatter: %d cells painted on %s." % [report.written, tilemap.name])
	update_overlay.emit()


func _scatter_paint(cells: Array, erasing: bool, merged: bool) -> void:
	if tilemap == null or cells.is_empty():
		return
	if erasing:
		var hit: Dictionary = SCATTER_TERRAIN.cells_in_any(tilemap, cells)
		if hit.is_empty():
			return
		if merged:
			terrain_undo.add_do_method(undo_manager, SCATTER_TERRAIN, &"remove_everywhere", [tilemap, cells])
		else:
			undo_manager.add_do_method(SCATTER_TERRAIN, &"remove_everywhere", tilemap, cells)
		for id in hit:
			undo_manager.add_undo_method(SCATTER_TERRAIN, &"add_cells", tilemap, int(id), hit[id])
		return
	var fresh: Array = SCATTER_TERRAIN.cells_not_in(tilemap, selected_entry, cells)
	if fresh.is_empty():
		if merged:
			terrain_undo.add_do_method(undo_manager, SCATTER_TERRAIN, &"rebuild", [tilemap])
		else:
			undo_manager.add_do_method(SCATTER_TERRAIN, &"rebuild", tilemap)
		return
	if merged:
		terrain_undo.add_do_method(undo_manager, SCATTER_TERRAIN, &"add_cells", [tilemap, selected_entry, fresh])
	else:
		undo_manager.add_do_method(SCATTER_TERRAIN, &"add_cells", tilemap, selected_entry, fresh)
	undo_manager.add_undo_method(SCATTER_TERRAIN, &"remove_cells", tilemap, selected_entry, fresh)

#endregion


## The pin button keeps the brush picked.
func _add_single_favorite() -> void:
	if not _is_single(selected_entry):
		return
	_add_favorite_entry(BetterTerrain.single_block_of(tileset, selected_entry))


## A right click in the atlas keeps the tile under the mouse, or the whole group picked
## when the click lands inside it; nothing has to be picked first.
func _favorite_from_atlas(source_id: int, coord: Vector2i, alternate: int) -> void:
	if not _is_single(selected_entry):
		return
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return
	var origin := src.get_tile_at_coords(coord)
	if origin == Vector2i(-1, -1):
		return
	var block := BetterTerrain.single_block_of(tileset, selected_entry)
	if not block.is_empty() and block.size != Vector2i.ONE and block.source == source_id \
			and block.alt == alternate and Rect2i(block.origin, block.size).has_point(coord):
		_add_favorite_entry(block)
		return
	_add_favorite_entry({source = source_id, origin = origin, alt = alternate, size = src.get_tile_size_in_atlas(origin)})


func _add_favorite_entry(entry: Dictionary) -> void:
	if entry.is_empty():
		return
	var entries: Array = tileset.get_meta(SINGLE_BAG_SCRIPT.META, []).duplicate(true)
	if not entries.any(func(saved): return SINGLE_BAG_SCRIPT.same_tile(saved, entry)):
		entries.append(entry)
		_edit_single_favorites(entries)
	_single_bag.set_collapsed(false)


func _edit_single_favorites(entries: Array, groups: Variant = null) -> void:
	var before: Array = tileset.get_meta(SINGLE_BAG_SCRIPT.META, []).duplicate(true)
	var before_groups: Array = tileset.get_meta(SINGLE_BAG_SCRIPT.GROUPS_META, []).duplicate(true)
	var after_groups: Array = before_groups if groups == null else groups
	undo_manager.create_action(tr("Edit tile favorites"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"_set_single_favorites", tileset, entries, after_groups)
	undo_manager.add_undo_method(self, &"_set_single_favorites", tileset, before, before_groups)
	undo_manager.commit_action()


func _set_single_favorites(ts: TileSet, entries: Array, groups: Array) -> void:
	ts.set_meta(SINGLE_BAG_SCRIPT.META, entries.duplicate(true))
	ts.set_meta(SINGLE_BAG_SCRIPT.GROUPS_META, groups.duplicate(true))
	ts.emit_changed()
	if ts == tileset:
		_sync_scatter_bag()


func _all_layers_active() -> bool:
	return _map_all_layers != null and _map_all_layers.button_pressed


func _copy_map_selection() -> void:
	if _all_layers_active():
		_all_selection.copy(_map_sel_rect.position)
	else:
		_map_clip = _lift(_map_sel, _map_sel_rect.position)


func _sync_all_selection() -> void:
	_map_sel = _all_selection.projected_cells()
	_map_sel_rect = _box_of(_map_sel)
	CLIFF_DATA.set_captured(_all_selection.selection.get(tilemap, {}).keys())
	_update_map_info()
	if is_instance_valid(_cliff_window):
		_cliff_window.refresh_shapes()
	update_overlay.emit()


func _on_all_map_sel_action(id: int) -> void:
	match id:
		MapSelAction.COPY:
			_copy_map_selection()
		MapSelAction.CUT:
			_copy_map_selection()
			_all_selection.delete(undo_manager, tr("Cut tiles on all layers"))
			_clear_map_selection()
		MapSelAction.DELETE:
			_all_selection.delete(undo_manager, tr("Delete tiles on all layers"))
			_clear_map_selection()
		MapSelAction.PASTE:
			_map_paste_at(current_position, [], "Paste tiles on all layers")
		MapSelAction.DUPLICATE:
			_copy_map_selection()
			_map_paste_at(current_position, [], "Duplicate tiles on all layers")
		MapSelAction.CLEAR:
			_clear_map_selection()
	_update_map_info()


func _arrange_toolbar() -> void:
	var toolbar := $VBox/Toolbar
	var original := toolbar.get_children()
	var basic_frame := PanelContainer.new()
	basic_frame.name = "BasicTools"
	basic_frame.theme = EditorInterface.get_editor_theme()
	basic_frame.theme_type_variation = "PanelContainerTabbarInner"
	toolbar.add_child(basic_frame)
	var basic := HBoxContainer.new()
	basic.add_theme_constant_override("separation", 0)
	basic_frame.add_child(basic)
	for button: Button in [_map_select, draw_button, line_button, rectangle_button, fill_button, _slope_button, replace_button]:
		button.reparent(basic)
		button.flat = false
		button.focus_mode = Control.FOCUS_NONE
		button.add_theme_stylebox_override("normal", get_theme_stylebox("tab_unselected", "TabBarInner"))
		button.add_theme_stylebox_override("hover", get_theme_stylebox("tab_hovered", "TabBarInner"))
		button.add_theme_stylebox_override("pressed", get_theme_stylebox("tab_selected", "TabBarInner"))
		button.add_theme_stylebox_override("hover_pressed", get_theme_stylebox("tab_selected", "TabBarInner"))
	var after_replace := VSeparator.new()
	after_replace.name = "AfterReplace"
	toolbar.add_child(after_replace)
	var context := HBoxContainer.new()
	context.name = "ToolOptions"
	toolbar.add_child(context)
	_map_all_layers.reparent(context)
	var terrain_options := HBoxContainer.new()
	terrain_options.name = "TerrainOptions"
	context.add_child(terrain_options)
	for control: Control in [_picker, _fill_rule, _fill_seen, _fill_layer, _slope_autofill, _slope_freehand, _slope_smooth, _add_favorite_button, _quick_terrain_box, select_tiles, paint_type, paint_terrain, object_lone, object_joined, _oven_button, _exemplar_button, paint_symmetry, symmetry_options, _cliff_button, live_test_button, _collision_mode_box, _data_panel.mode_bar]:
		control.reparent(terrain_options)
	_picker_select_layer.reparent(terrain_options)
	terrain_options.move_child(_picker_select_layer, _picker.get_index() + 1)
	terrain_options.visible = not _map_select_active()
	draw_button.button_group.pressed.connect(func(_button): terrain_options.visible = not _map_select_active())
	toolbar.add_child(VSeparator.new())
	var view_options := HBoxContainer.new()
	view_options.name = "LayerAndView"
	toolbar.add_child(view_options)
	for control: Control in [_rows_spin, _rows_reset, _level_spin, _level_reset, zoom_slider_container, source_selector]:
		control.reparent(view_options)
	var spacer: Control = toolbar.get_node("Spacer")
	toolbar.move_child(spacer, toolbar.get_child_count() - 1)
	var extra := HBoxContainer.new()
	extra.name = "MoreOptions"
	extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	extra.alignment = BoxContainer.ALIGNMENT_END
	toolbar.add_child(extra)
	for control in original:
		if control.get_parent() != toolbar or control == spacer:
			continue
		if control is VSeparator:
			toolbar.remove_child(control)
			control.queue_free()
		else:
			control.reparent(extra)
	_even_toolbar(toolbar)


# Mixed heights left each box at a different height; use the tool button height, centred.
func _even_toolbar(node: Node) -> void:
	var height := roundi(28 * EditorInterface.get_editor_scale())
	for child in node.get_children():
		if not (child is Control) or child is Window:
			continue
		if child is PanelContainer or child is BoxContainer or child is FlowContainer:
			_even_toolbar(child)
			continue
		if child is Separator or child.name == "Spacer":
			continue
		# Framed text buttons (Live test) pad themself taller, trim it.
		if child is Button and not child.flat and child.text != "" and child.get_parent() != null \
				and not (child.get_parent() is BoxContainer and child.get_parent().get_parent() is PanelContainer):
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var box := child.get_theme_stylebox(state).duplicate() as StyleBox
				if box != null:
					box.content_margin_top = 2 * EditorInterface.get_editor_scale()
					box.content_margin_bottom = 2 * EditorInterface.get_editor_scale()
					child.add_theme_stylebox_override(state, box)
		child.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		child.custom_minimum_size.y = maxf(child.custom_minimum_size.y, height)


func _single_erase_cells(cells: Array) -> Array:
	var blocks := _multi_tile_blocks()
	var result := {}
	for cell: Vector2i in cells:
		if result.has(cell):
			continue
		result[cell] = true
		var found := _painted_block_at(tilemap, cell, blocks)
		if not found.is_empty():
			for y in found.block.size.y:
				for x in found.block.size.x:
					result[found.origin + Vector2i(x, y)] = true
	return result.keys()


## Multi-tile favourites plus the current brush, biggest first.
func _multi_tile_blocks() -> Array:
	var blocks: Array = tileset.get_meta(SINGLE_BAG_SCRIPT.META, []).duplicate(true)
	var selected := BetterTerrain.single_block_of(tileset, selected_entry)
	if not selected.is_empty():
		blocks.push_front(selected)
	blocks = blocks.filter(func(block): return block.size != Vector2i.ONE)
	blocks.sort_custom(func(a, b): return a.size.x * a.size.y > b.size.x * b.size.y)
	return blocks


## {block, origin} if the cell is part of a whole painted block, else {}.
func _painted_block_at(layer: TileMapLayer, cell: Vector2i, blocks: Array) -> Dictionary:
	var source := layer.get_cell_source_id(cell)
	var atlas_source: TileSetAtlasSource = null
	if tileset.has_source(source):
		atlas_source = tileset.get_source(source) as TileSetAtlasSource
	var atlas := layer.get_cell_atlas_coords(cell)
	var alternate := layer.get_cell_alternative_tile(cell)
	for block in blocks:
		if source != block.source or alternate != block.alt or not Rect2i(block.origin, block.size).has_point(atlas):
			continue
		var origin: Vector2i = cell - (atlas - block.origin)
		var complete := true
		for y in block.size.y:
			for x in block.size.x:
				var offset := Vector2i(x, y)
				var at := origin + offset
				# Atlas gaps are never painted.
				if atlas_source != null and not atlas_source.has_tile(block.origin + offset):
					continue
				if layer.get_cell_source_id(at) != block.source or layer.get_cell_atlas_coords(at) != block.origin + offset or layer.get_cell_alternative_tile(at) != block.alt:
					complete = false
		if complete:
			return {block = block, origin = origin}
	return {}


func _map_selection_mesh(visible_rect: Rect2, transform: Transform2D) -> Dictionary:
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var layers: Dictionary = _all_selection.selection if _all_layers_active() else {tilemap: _map_sel}
	var active_inverse := tilemap.global_transform.affine_inverse()
	var origin := tilemap.map_to_local(_map_sel_rect.position)
	var displacement := tilemap.to_global(tilemap.map_to_local(_map_sel_rect.position + _map_drag_delta)) - tilemap.to_global(origin)
	for layer: TileMapLayer in layers:
		if not is_instance_valid(layer) or layer.tile_set == null:
			continue
		var layer_transform := transform * active_inverse * layer.global_transform
		var shape: PackedVector2Array = BetterTerrain.data.cell_polygon(layer.tile_set)
		var cell_size := Vector2(layer.tile_set.tile_size)
		for moved in ([false, true] if _map_drag_delta != Vector2i.ZERO else [false]):
			var tint := Color(0.4, 1.0, 0.6, 0.30) if moved else Color(0.4, 0.8, 1.0, 0.28 if _map_drag_delta == Vector2i.ZERO else 0.10)
			for cell: Vector2i in layers[layer]:
				if moved:
					cell = layer.local_to_map(layer.to_local(layer.to_global(layer.map_to_local(cell)) + displacement))
				var center := layer.map_to_local(cell)
				var polygon := PackedVector2Array()
				for corner in shape:
					polygon.append(layer_transform * (center + corner * cell_size))
				var bounds := Rect2(polygon[0], Vector2.ZERO)
				for corner in polygon:
					bounds = bounds.expand(corner)
				if not visible_rect.intersects(bounds):
					continue
				var start := points.size()
				points.append_array(polygon)
				for corner in polygon:
					colors.append(tint)
				for i in range(1, polygon.size() - 1):
					indices.append_array(PackedInt32Array([start, start + i, start + i + 1]))
	return {points = points, colors = colors, indices = indices}


#region Quick terrains from a single-tile block

enum QuickKind { MATCH, PATCH, OBJECT, SCATTER }

# Bank all round plus 3×3 of water, so every inner role exists.
const PATCH_MIN_SIZE := Vector2i(5, 5)
const QUICK_LABELS := {
	QuickKind.MATCH: ["Create quick terrain", "MatchTiles.svg",
		"Create a Match tiles terrain from the selected tiles, reading its joins from the drawing:\na side joins where the fill reaches it. Several shapes can be selected at once;\ncorners are read too when an inner corner is drawn (square tiles only)."],
	QuickKind.PATCH: ["Create Patch", "Exemplar.svg",
		"Create a Patch terrain that reads the selected block like a pond: the outer ring is\nthe bank around the painted shape, the inside is the water and its rim (5×5 or more).\nEmpty cells in the block (a rounded drawing's corners) are made into tiles first."],
	QuickKind.OBJECT: ["Create Object", "ObjectTerrain.svg",
		"Create an Object terrain whose drawing is the whole selection, e.g. a tree.\nEmpty cells in it are made into tiles first. Mark a joined block later to let objects fuse."],
	QuickKind.SCATTER: ["Create quick scatter", "Scatter.svg",
		"Create a Scatter terrain whose bag holds every tile of the selection (two or more)."],
}
const QUICK_TYPES := {
	QuickKind.MATCH: BetterTerrain.TerrainType.MATCH_TILES,
	QuickKind.PATCH: BetterTerrain.TerrainType.EXEMPLAR,
	QuickKind.OBJECT: BetterTerrain.TerrainType.OBJECT,
	QuickKind.SCATTER: BetterTerrain.TerrainType.SCATTER,
}
const QUICK_SUFFIX := {QuickKind.MATCH: "", QuickKind.PATCH: " patch", QuickKind.OBJECT: " object", QuickKind.SCATTER: " scatter"}
# Sides only. Setting the diagonals too fills the whole interior.
const SQUARE_SIDES := {
	TileSet.CELL_NEIGHBOR_RIGHT_SIDE: Vector2i(1, 0),
	TileSet.CELL_NEIGHBOR_BOTTOM_SIDE: Vector2i(0, 1),
	TileSet.CELL_NEIGHBOR_LEFT_SIDE: Vector2i(-1, 0),
	TileSet.CELL_NEIGHBOR_TOP_SIDE: Vector2i(0, -1),
}

var _quick_terrain_box: HBoxContainer
var _quick_buttons := {}
var _quick_animation_button: Button


func _build_quick_terrain_buttons(parent: Control, at: int) -> void:
	_quick_terrain_box = HBoxContainer.new()
	_quick_terrain_box.name = "QuickTerrains"
	_quick_terrain_box.add_theme_constant_override("separation", 0)
	for kind in QUICK_LABELS:
		var b := Button.new()
		b.name = str(QUICK_LABELS[kind][0]).replace(" ", "")
		b.flat = true
		b.focus_mode = Control.FOCUS_NONE
		_icon_or_text(b, ICON_DIR + QUICK_LABELS[kind][1], [], QUICK_LABELS[kind][0])
		b.tooltip_text = "%s\n%s" % [QUICK_LABELS[kind][0], QUICK_LABELS[kind][2]]
		b.pressed.connect(_on_quick_pressed.bind(kind))
		_quick_terrain_box.add_child(b)
		_quick_buttons[kind] = b
	_quick_animation_button = Button.new()
	_quick_animation_button.name = "QuickAnimation"
	_quick_animation_button.flat = true
	_quick_animation_button.focus_mode = Control.FOCUS_NONE
	_icon_or_text(_quick_animation_button, "", ["Animation"], QUICK_ANIMATION_LABEL[0])
	_quick_animation_button.pressed.connect(_open_quick_animation)
	_quick_terrain_box.add_child(_quick_animation_button)
	parent.add_child(_quick_terrain_box)
	parent.move_child(_quick_terrain_box, at)
	_quick_terrain_box.hide()


func _quick_block() -> Dictionary:
	if tileset == null or not _is_single(selected_entry):
		return {}
	var block := BetterTerrain.single_block_of(tileset, selected_entry)
	if block.is_empty() or not (tileset.get_source(block.source) is TileSetAtlasSource):
		return {}
	return block


## Why the selection can't make that type, or "".
func _quick_refusal(kind: int, block: Dictionary) -> String:
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	var rect := Rect2i(block.origin, block.size)
	var whole := true
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not src.has_tile(Vector2i(x, y)):
				whole = false
	match kind:
		QuickKind.MATCH, QuickKind.PATCH:
			# Each tile just need a neighbour to join (3×2 strip, 1×3 path).
			if kind == QuickKind.MATCH and rect.size.x * rect.size.y < 2:
				return "Select at least two tiles, so they have a side to join."
			if kind == QuickKind.PATCH and (rect.size.x < PATCH_MIN_SIZE.x or rect.size.y < PATCH_MIN_SIZE.y):
				return "Select a block of at least %d×%d tiles." % [PATCH_MIN_SIZE.x, PATCH_MIN_SIZE.y]
			# Match tiles treats gaps as outside, a Patch fills them with new tiles.
			if kind == QuickKind.PATCH and not whole:
				if block.alt != 0:
					return "The block has gaps; new tiles can only be made for the base tile, not alternatives."
				if not _atlas_gaps(src, rect).all(func(c): return _can_create_tile(src, c)):
					return "The block has gaps inside a bigger tile; select one where every cell is free or holds a tile."
			if kind == QuickKind.MATCH and tileset.tile_shape != TileSet.TILE_SHAPE_SQUARE:
				return "Only for square tiles."
		QuickKind.SCATTER:
			# A bag of one tile scatters nothing but copies of it.
			var found := {}
			for y in range(rect.position.y, rect.end.y):
				for x in range(rect.position.x, rect.end.x):
					var at := src.get_tile_at_coords(Vector2i(x, y))
					if at != Vector2i(-1, -1):
						found[at] = true
			if found.size() < 2:
				return "Select at least two tiles to scatter."
		QuickKind.OBJECT:
			if rect.size.x * rect.size.y < 2:
				return "Select the whole drawing, at least two tiles."
			if not whole:
				if block.alt != 0:
					return "The drawing has gaps; new tiles can only be made for the base tile, not alternatives."
				if not _atlas_gaps(src, rect).all(func(c): return _can_create_tile(src, c)):
					return "The drawing has gaps inside a bigger tile; select one where every cell is free or holds a tile."
	return ""


func _sync_quick_terrain_buttons() -> void:
	if _quick_terrain_box == null:
		return
	var block := _quick_block()
	_quick_terrain_box.visible = not block.is_empty()
	if block.is_empty():
		return
	for kind in _quick_buttons:
		var why := _quick_refusal(kind, block)
		_quick_buttons[kind].disabled = not why.is_empty()
		_quick_buttons[kind].tooltip_text = "%s\n%s" % [QUICK_LABELS[kind][0], QUICK_LABELS[kind][2]] \
			+ ("" if why.is_empty() else "\n\n" + why)
	var animation_why := _quick_animation_refusal(block)
	_quick_animation_button.disabled = not animation_why.is_empty()
	_quick_animation_button.tooltip_text = "%s\n%s" % QUICK_ANIMATION_LABEL + ("" if animation_why.is_empty() else "\n\n" + animation_why)


func _quick_terrain_name(source_id: int, kind: int) -> String:
	var base := ObjectTerrain.texture_name(tileset, source_id).get_basename()
	if base.is_empty():
		base = "Quick terrain"
	base += QUICK_SUFFIX[kind]
	var taken := {}
	for i in BetterTerrain.terrain_count(tileset):
		taken[str(BetterTerrain.get_terrain(tileset, i).name)] = true
	var candidate := base
	var n := 2
	while taken.has(candidate):
		candidate = "%s %d" % [base, n]
		n += 1
	return candidate


# Match shows what it will make first; the other kinds are made at once.
func _on_quick_pressed(kind: int) -> void:
	if kind != QuickKind.MATCH:
		_create_quick_terrain(kind)
		return
	var block := _quick_block()
	if block.is_empty() or not _quick_refusal(kind, block).is_empty():
		return
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	var tiles := []
	for y in range(block.origin.y, block.origin.y + block.size.y):
		for x in range(block.origin.x, block.origin.x + block.size.x):
			var c := Vector2i(x, y)
			if src.has_tile(c) and src.has_alternative_tile(c, block.alt) and not QUICK_MATCH.blank(src, c):
				tiles.append(c)
	if tiles.is_empty():
		return
	var owners := _terrain_owners(src, tiles, block.alt)
	if not owners.is_empty():
		_show_quick_error(owners)
		return
	var dialog := QUICK_MATCH_PREVIEW.new()
	add_child(dialog)
	dialog.chosen.connect(func(bits: Dictionary, color: Color, follow: bool):
		var options := {bits = bits, color = color}
		var before := BetterTerrain.terrain_count(tileset)
		_create_quick_terrain(QuickKind.MATCH, options)
		if follow and BetterTerrain.terrain_count(tileset) > before:
			_open_coverage.call_deferred(BetterTerrain.terrain_count(tileset) - 1))
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free, CONNECT_DEFERRED)
	dialog.canceled.connect(dialog.queue_free)
	dialog.popup_centered(Vector2i(900, 560) * EditorInterface.get_editor_scale())
	dialog.setup(src, QUICK_MATCH.read(src, tiles), QUICK_MATCH.contrast_color(src, tiles))


## options: bits (Match joins as adjusted, {coords: [bits]}), name, color; otherwise read and
## worked out here.
func _create_quick_terrain(kind: int, options := {}) -> void:
	var block := _quick_block()
	if block.is_empty() or not _quick_refusal(kind, block).is_empty():
		return
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	var rect := Rect2i(block.origin, block.size)
	var tiles := []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			var c := Vector2i(x, y)
			if src.has_tile(c) and src.has_alternative_tile(c, block.alt):
				tiles.append(c)
	# Tiles with nothing drawn are gaps between shapes, not pieces of the terrain.
	if kind == QuickKind.MATCH:
		tiles = tiles.filter(func(c: Vector2i): return not QUICK_MATCH.blank(src, c))
	# Patch and Object read the whole rectangle, so empty cells become tiles.
	var new_tiles: Array = _atlas_gaps(src, rect) if kind in [QuickKind.PATCH, QuickKind.OBJECT] else []
	if tiles.is_empty() and new_tiles.is_empty():
		return
	# One terrain per tile. Scatter only lists tiles, so it takes any.
	if kind != QuickKind.SCATTER:
		var owners := _terrain_owners(src, tiles, block.alt)
		if not owners.is_empty():
			_show_quick_error(owners)
			return
	var tile_metas := []
	for c in tiles:
		var td := src.get_tile_data(c, block.alt)
		tile_metas.append([td, td.get_meta(BetterTerrain.TERRAIN_META).duplicate(true) if td.has_meta(BetterTerrain.TERRAIN_META) else null])
	var before_meta = tileset.get_meta(BetterTerrain.TERRAIN_META).duplicate(true) \
		if tileset.has_meta(BetterTerrain.TERRAIN_META) else null
	var before_tables = tileset.get_meta(EXEMPLAR_DATA.META).duplicate(true) \
		if tileset.has_meta(EXEMPLAR_DATA.META) else null
	var terrain_name: String = options.get("name", _quick_terrain_name(block.source, kind))
	var color: Color = options.get("color", QUICK_MATCH.contrast_color(src, tiles if not tiles.is_empty() else new_tiles))
	undo_manager.create_action(tr("Create %s") % terrain_name, UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_quick_terrain", kind, terrain_name, color, block.source, rect, block.alt, tiles, new_tiles,
		options.get("bits", {}))
	undo_manager.add_undo_method(self, &"_restore_quick_terrain", before_meta, before_tables, tile_metas, block.source, new_tiles)
	undo_manager.commit_action()


func perform_quick_terrain(kind: int, terrain_name: String, color: Color, source_id: int, rect: Rect2i, alt: int, tiles: Array, new_tiles: Array = [], bits: Dictionary = {}) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	tiles = tiles.duplicate()
	for c: Vector2i in new_tiles:
		if not src.has_tile(c):
			src.create_tile(c)
		tiles.append(c)
	var group := group_filter if _known_groups.has(group_filter) else ""
	var object := {}
	match kind:
		QuickKind.OBJECT:
			object = ObjectTerrain.make_config(rect.size, rect.position)
		QuickKind.SCATTER:
			var bag := []
			for c: Vector2i in tiles:
				bag.append(SCATTER_TERRAIN.make_entry(source_id, c, src.get_tile_size_in_atlas(c)))
			object = {bag = bag}
	if not BetterTerrain.add_terrain(tileset, terrain_name, color, QUICK_TYPES[kind], [], {}, group, object):
		return
	var id := BetterTerrain.terrain_count(tileset) - 1
	if kind != QuickKind.SCATTER:
		for c: Vector2i in tiles:
			BetterTerrain.set_tile_terrain_type(tileset, src.get_tile_data(c, alt), id)
	match kind:
		QuickKind.MATCH:
			# Joins read from the drawing; without a readable texture, the neighbours in the block.
			var drawn: Dictionary = bits if not bits.is_empty() else QUICK_MATCH.read(src, tiles)
			var inside := {}
			for c in tiles:
				inside[c] = true
			for c: Vector2i in tiles:
				var td := src.get_tile_data(c, alt)
				# Clear old bits first or they mark the outer ring.
				for key in BetterTerrain.tile_peering_keys(td):
					for type in BetterTerrain.tile_peering_types(td, key):
						BetterTerrain.remove_tile_peering_type(tileset, td, key, type)
					for type in BetterTerrain.tile_not_peering_types(td, key):
						BetterTerrain.remove_tile_not_peering_type(tileset, td, key, type)
				if drawn.has(c):
					for bit: int in drawn[c]:
						BetterTerrain.add_tile_peering_type(tileset, td, bit, id)
					continue
				for neighbor in SQUARE_SIDES:
					if inside.has(c + SQUARE_SIDES[neighbor]):
						BetterTerrain.add_tile_peering_type(tileset, td, neighbor, id)
		QuickKind.PATCH:
			EXEMPLAR_DATA.record_drawing(tileset, id, source_id, rect)
			# Same reading as the Patch editor: outer ring is the bank, inside is water (see "lake").
			var table := EXEMPLAR_DATA.learn_from_block(tileset, id, source_id)
			if not table.is_empty():
				EXEMPLAR_DATA.store_table(tileset, terrain_name, table)
	rebuild_terrain_list()
	_select_terrain(id)


## Terrains (or Decoration) these tiles already belong to.
func _terrain_owners(src: TileSetAtlasSource, tiles: Array, alt: int) -> Array:
	var names := {}
	for c: Vector2i in tiles:
		var type := BetterTerrain.get_tile_terrain_type(src.get_tile_data(c, alt))
		if type == BetterTerrain.TileCategory.EMPTY:
			names["Decoration"] = true
		elif type >= 0:
			names[str(BetterTerrain.get_terrain(tileset, type).name)] = true
	return names.keys()


var _quick_error: AcceptDialog


func _show_quick_error(owners: Array) -> void:
	if _quick_error == null:
		_quick_error = AcceptDialog.new()
		_quick_error.title = "Tiles already in a terrain"
		_quick_error.dialog_autowrap = true
		_quick_error.min_size = Vector2i(460, 0)
		add_child(_quick_error)
	var listed := ", ".join(owners.map(func(n): return "\"%s\"" % n))
	_quick_error.dialog_text = ("Some of the selected tiles already belong to %s. A tile can be part of "
		+ "one terrain only, so no terrain was created.\n\nSelect other tiles, or take these out of %s first.") \
		% [listed, "that terrain" if owners.size() == 1 else "those terrains"]
	_quick_error.popup_centered()


func _atlas_gaps(src: TileSetAtlasSource, rect: Rect2i) -> Array:
	var out := []
	for y in range(rect.position.y, rect.end.y):
		for x in range(rect.position.x, rect.end.x):
			if not src.has_tile(Vector2i(x, y)):
				out.append(Vector2i(x, y))
	return out


func _can_create_tile(src: TileSetAtlasSource, c: Vector2i) -> bool:
	var grid := src.get_atlas_grid_size()
	return c.x < grid.x and c.y < grid.y and src.get_tile_at_coords(c) == Vector2i(-1, -1)


func _restore_quick_terrain(before_meta, before_tables, tile_metas: Array, source_id := -1, new_tiles: Array = []) -> void:
	var created: TileSetAtlasSource = null
	if tileset.has_source(source_id):
		created = tileset.get_source(source_id) as TileSetAtlasSource
	if created != null:
		for c: Vector2i in new_tiles:
			if created.has_tile(c):
				created.remove_tile(c)
	for entry in tile_metas:
		if entry[1] == null:
			entry[0].remove_meta(BetterTerrain.TERRAIN_META)
		else:
			entry[0].set_meta(BetterTerrain.TERRAIN_META, entry[1].duplicate(true))
	if before_meta == null:
		tileset.remove_meta(BetterTerrain.TERRAIN_META)
	else:
		tileset.set_meta(BetterTerrain.TERRAIN_META, before_meta.duplicate(true))
	if before_tables == null:
		tileset.remove_meta(EXEMPLAR_DATA.META)
	else:
		tileset.set_meta(EXEMPLAR_DATA.META, before_tables.duplicate(true))
	BetterTerrain._purge_cache(tileset)
	tileset.emit_changed()
	rebuild_terrain_list()
	update_tile_view_paint()

#endregion


#region Quick animation from a single-tile block

const QUICK_ANIMATION_LABEL := ["Quick animation",
	"Split the selected tiles into equal frames and animate the first one. A frame can be\none tile or a whole block of them. Opens a window to set the frames, speed and mode."]


## The selection in tiles of the first tile's size, or {} when it doesn't start on a tile or split into them.
func _quick_animation_layout(block: Dictionary) -> Dictionary:
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	if src.get_tile_at_coords(block.origin) != block.origin:
		return {}
	var tile_size := src.get_tile_size_in_atlas(block.origin)
	var cells: Vector2i = block.size
	if cells.x % tile_size.x != 0 or cells.y % tile_size.y != 0:
		return {}
	return {src = src, tile_size = tile_size, grid = cells / tile_size}


## Why the selection can't become an animation at all, or "".
func _quick_animation_refusal(block: Dictionary) -> String:
	if block.alt != 0:
		return "Animations belong to the base tile; select base tiles, not alternatives."
	var layout := _quick_animation_layout(block)
	if layout.is_empty():
		return "Start the selection on a tile, and make it a whole number of tiles of that size."
	if layout.grid.x * layout.grid.y < 2:
		return "Select at least two tiles, one per frame."
	return ""


## Which tiles play (those in the first frame) and which go (those in the other frames), or {error}.
func _quick_animation_plan(block: Dictionary, frame_cells: Vector2i, frames: int) -> Dictionary:
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	var rect := Rect2i(block.origin, block.size)
	var grid: Vector2i = rect.size / frame_cells
	if frames < 2 or frames > grid.x * grid.y:
		return {error = "The selection holds %d frames of that size." % (grid.x * grid.y)}
	var first := Rect2i(block.origin, frame_cells)
	var bases := {}
	for y in range(first.position.y, first.end.y):
		for x in range(first.position.x, first.end.x):
			var holder := src.get_tile_at_coords(Vector2i(x, y))
			if holder == Vector2i(-1, -1) or bases.has(holder):
				continue
			if not first.encloses(Rect2i(holder, src.get_tile_size_in_atlas(holder))):
				return {error = "A tile of the first frame crosses into the next one; frames must hold whole tiles."}
			bases[holder] = true
	var doomed := {}
	for i in range(1, frames):
		@warning_ignore("integer_division")
		var corner: Vector2i = block.origin + Vector2i(i % grid.x, i / grid.x) * frame_cells
		for y in frame_cells.y:
			for x in frame_cells.x:
				var holder := src.get_tile_at_coords(corner + Vector2i(x, y))
				if holder == Vector2i(-1, -1) or bases.has(holder):
					continue
				if not rect.has_point(holder):
					return {error = "A tile under the frames starts outside the selection; select whole tiles only."}
				doomed[holder] = true
	return {bases = bases.keys(), doomed = doomed.keys(), columns = grid.x}


func _open_quick_animation() -> void:
	var block := _quick_block()
	if block.is_empty() or not _quick_animation_refusal(block).is_empty():
		return
	var layout := _quick_animation_layout(block)
	var dialog := QUICK_ANIMATION_SCRIPT.new()
	add_child(dialog)
	dialog.setup(layout.src, block.origin, layout.tile_size, layout.grid,
		func(frame_cells: Vector2i, frames: int) -> String: return _quick_animation_plan(block, frame_cells, frames).get("error", ""))
	dialog.animation_accepted.connect(_create_quick_animation.bind(block))
	dialog.popup_centered()


func _create_quick_animation(frame_cells: Vector2i, frames: int, speed: float, mode: int, block: Dictionary) -> void:
	var plan := _quick_animation_plan(block, frame_cells, frames)
	if plan.has("error"):
		return
	var busy := _show_busy(tr("Creating animation…"))
	# Let the notice paint before the work holds the editor.
	await get_tree().process_frame
	await get_tree().process_frame
	var src := tileset.get_source(block.source) as TileSetAtlasSource
	var snapshots := _tile_snapshots(src, plan.doomed + plan.bases)
	var doomed_snapshots := []
	for c: Vector2i in plan.doomed:
		doomed_snapshots.append(snapshots[c])
	var base_snapshots := []
	for c: Vector2i in plan.bases:
		base_snapshots.append(snapshots[c].filter(func(p): return str(p[0]).get_slice("/", 1).begins_with("animation_")))
	var was: Dictionary = BetterTerrain.single_block_of(tileset, selected_entry)
	undo_manager.create_action(tr("Create tile animation"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(self, &"perform_quick_animation", block.source, plan.bases, plan.doomed, frame_cells, plan.columns, frames, speed, mode)
	undo_manager.add_do_method(BetterTerrain, &"set_single_tile", tileset, block.source, block.origin, 0, frame_cells, false)
	undo_manager.add_undo_method(self, &"_restore_quick_animation", block.source, plan.bases, base_snapshots, doomed_snapshots)
	undo_manager.add_undo_method(BetterTerrain, &"set_single_tile", tileset, was.source, was.origin, was.alt, was.size, false)
	undo_manager.add_do_method(self, &"_after_single_pick")
	undo_manager.add_undo_method(self, &"_after_single_pick")
	undo_manager.commit_action()
	busy.hide()
	busy.queue_free()


func _show_busy(text: String) -> PopupPanel:
	var panel := PopupPanel.new()
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(220, 48)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	panel.add_child(label)
	add_child(panel)
	panel.popup_centered()
	return panel


func perform_quick_animation(source_id: int, bases: Array, doomed: Array, frame_cells: Vector2i, columns: int, frames: int, speed: float, mode: int) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	for c: Vector2i in doomed:
		if src.has_tile(c):
			src.remove_tile(c)
	# Shrink every old animation first: its frames may sit where another tile's new ones go.
	for c: Vector2i in bases:
		src.set_tile_animation_frames_count(c, 1)
	for c: Vector2i in bases:
		# Godot steps size + separation per frame, so a frame block of 4 tiles is 1 + 3.
		src.set_tile_animation_separation(c, frame_cells - src.get_tile_size_in_atlas(c))
		src.set_tile_animation_columns(c, columns)
		src.set_tile_animation_speed(c, speed)
		src.set_tile_animation_mode(c, mode)
		src.set_tile_animation_frames_count(c, frames)
		for i in frames:
			src.set_tile_animation_frame_duration(c, i, 1.0)
	_after_atlas_change()


func _restore_quick_animation(source_id: int, bases: Array, base_snapshots: Array, doomed_snapshots: Array) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	for c: Vector2i in bases:
		src.set_tile_animation_frames_count(c, 1)
	for snapshot: Array in doomed_snapshots:
		_apply_snapshot(src, snapshot)
	for snapshot: Array in base_snapshots:
		_apply_snapshot(src, snapshot)
	_after_atlas_change()


## Every stored property of each tile, alternatives and their metadata included, in load order, by coords.
## One pass over the property list: it holds the whole atlas, so a pass per tile is quadratic.
func _tile_snapshots(src: TileSetAtlasSource, coords: Array) -> Dictionary:
	var out := {}
	var by_prefix := {}
	for c: Vector2i in coords:
		out[c] = []
		by_prefix["%d:%d" % [c.x, c.y]] = c
	for p in src.get_property_list():
		var property_name: String = p.name
		var tile := property_name.get_slice("/", 0)
		if not by_prefix.has(tile) or property_name.get_slice_count("/") < 2:
			continue
		var value = src.get(property_name)
		out[by_prefix[tile]].append([property_name, value.duplicate(true) if value is Array or value is Dictionary else value])
	return out


func _apply_snapshot(src: TileSetAtlasSource, snapshot: Array) -> void:
	for p: Array in snapshot:
		src.set(p[0], p[1])


func _after_atlas_change() -> void:
	BetterTerrain._purge_cache(tileset)
	tileset.emit_changed()
	update_tile_view_paint()

#endregion


#region Collisions tool

const COLLISIONS := preload("res://addons/better-tile-editor/editor/Collisions.gd")
const COLLISION_PANEL_SCRIPT := preload("res://addons/better-tile-editor/editor/CollisionPanel.gd")
## List id of the Collisions entry; below every TileCategory so it never names a terrain.
const COLLISION_ENTRY := -10
const COLLISION_COLOR := Color(0.85, 0.2, 0.2)
## Beyond this many cells in view, only used cells are walked for the map overlay.
const MAX_COLLISION_SCAN := 60000

var _collision_panel: PanelContainer
var _collision_layer_index := 0
## Tiles changed by the stroke in progress: key -> [source_id, coords, state before].
var _collision_stroke := {}
var _collision_stroking := false
var _collision_added_layer := false
var _collision_solid := true
var _collision_rect := false
var _collision_from := Vector2i.ZERO
var _tools_off_for_collisions: Array[Button] = []
var _collision_mode_box: HBoxContainer
## Resting the mouse on the map this long lists the shapes under it.
const COLLISION_TIP_DELAY := 0.7
var _collision_tip_timer: Timer
var _collision_tip_ready := false
## Where the mouse rests, in overlay coordinates.
var _collision_tip_at := Vector2.ZERO
var _collision_shape_mode := false
## Stamp: clicks write the copied shape (Shapes.clipboard) instead of a full square.
var _collision_stamp_mode := false
var _collision_stamp_button: Button
var _collision_action := ""
var _collision_shape_window: Window
const COLLISION_SHAPE_EDITOR_SCRIPT := preload("res://addons/better-tile-editor/editor/CollisionShapeEditor.gd")
const SHAPES := preload("res://addons/better-tile-editor/editor/CollisionShapes.gd")


## Solid: clicks make tiles a full square or clear. Shape: clicks open the shape editor.
func _build_collision_mode_buttons() -> void:
	_collision_mode_box = HBoxContainer.new()
	_collision_mode_box.name = "CollisionModes"
	_collision_mode_box.add_theme_constant_override("separation", 0)
	var group := ButtonGroup.new()
	for mode in [["Solid", "SolidBox", "Solid\nLeft click makes a tile a full square, right click clears it."],
			["Shape", "ShapePolygon", "Shape\nClick a tile, or drag over a group in the atlas, to open the shape editor:\ndetect the collision from the sprite and edit its points."],
			["Stamp", "ShapeStamp", "Stamp\nCopy one tile's collision shape onto others: the first click takes a tile's shape,\nthen a click or drag writes it on tiles and a right click clears them.\nAlt+click takes another tile's shape."]]:
		var b := Button.new()
		b.name = mode[0]
		b.set_meta(&"tool_name", mode[0])
		b.flat = true
		b.toggle_mode = true
		b.button_group = group
		b.focus_mode = Control.FOCUS_NONE
		b.button_pressed = mode[0] == "Solid"
		_icon_or_text(b, ICON_DIR + mode[1] + ".svg", [], mode[0])
		b.tooltip_text = mode[2]
		b.toggled.connect(func(on: bool) -> void:
			if on:
				_collision_shape_mode = mode[0] == "Shape"
				_collision_stamp_mode = mode[0] == "Stamp"
				_sync_collision_mode())
		_collision_mode_box.add_child(b)
		if mode[0] == "Stamp":
			_collision_stamp_button = b
	$VBox/Toolbar.add_child(_collision_mode_box)
	_collision_mode_box.hide()


## Copies a tile's shape, on the edited physics layer, to paste or stamp elsewhere.
func _copy_collision(source_id: int, coords: Vector2i) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return
	var cells := src.get_tile_size_in_atlas(coords)
	var lay: Dictionary = SHAPES.layout(src, coords, cells)
	var found: Dictionary = SHAPES.gather(src, tileset, lay, _collision_physics_layer())
	SHAPES.clipboard = SHAPES.make_clip(found.normal, found.one_way, found.margin, lay, cells)
	_sync_collision_clipboard()


func _sync_collision_clipboard() -> void:
	if _collision_panel == null:
		return
	var copied: Dictionary = SHAPES.clipboard
	var pick: String = PICKER_MODIFIER_NAMES[_picker_modifier()]
	var text := SHAPES.describe_clip(copied)
	if _collision_stamp_mode and copied.is_empty():
		text = "Nothing copied yet: click a tile to take its shape."
	_collision_panel.show_clipboard(text, copied, _collision_stamp_mode or not copied.is_empty())
	if _collision_shape_mode:
		_collision_panel.set_keys([["Click", "open the shape editor"], ["Drag in the atlas", "edit a group"]])
	elif _collision_stamp_mode and copied.is_empty():
		_collision_panel.set_keys([["Click a tile", "take its shape"], ["Right click", "clear"]])
	elif _collision_stamp_mode:
		_collision_panel.set_keys([["Left click", "paste the shape"], ["Right click", "clear"], ["%s + click" % pick, "take another shape"]])
	else:
		_collision_panel.set_keys([["Left click", "solid"], ["Right click", "clear"]])


## Stamp takes the shape of the tile clicked: with nothing copied yet, or with the picker's key.
func _collision_takes_shape(event: InputEventWithModifiers) -> bool:
	return _collision_mode() and _collision_stamp_mode \
		and (SHAPES.clipboard.is_empty() or _picker_modifier_held(event))


func _open_collision_shape(source_id: int, origin: Vector2i, cells: Vector2i) -> void:
	if tileset == null or not (tileset.get_source(source_id) is TileSetAtlasSource):
		return
	if is_instance_valid(_collision_shape_window):
		_collision_shape_window.queue_free()
	_collision_shape_window = COLLISION_SHAPE_EDITOR_SCRIPT.new()
	get_tree().root.add_child(_collision_shape_window)
	_collision_shape_window.setup(tileset, source_id, origin, cells, maxi(0, _collision_physics_layer()))
	_collision_shape_window.apply_requested.connect(_apply_collision_shape)
	_collision_shape_window.clipboard_changed.connect(_sync_collision_clipboard)
	# The window's physics layer is the tool's: both show and paint the same one.
	_collision_shape_window.physics_layer_changed.connect(func(index: int) -> void:
		_collision_layer_index = index
		_sync_collision_mode())
	_collision_shape_window.physics_layer_add_requested.connect(func() -> void:
		_add_collision_physics_layer()
		if is_instance_valid(_collision_shape_window):
			_collision_shape_window.show_physics_layer(tileset.get_physics_layers_count() - 1))
	_collision_shape_window.popup_centered()


## per_tile: {coords: [[points, one_way, margin], ...]}, for the base tile and the alternatives
## the scope takes in. Physics layers are added up to the one written to.
func _apply_collision_shape(source_id: int, layer: int, per_tile: Dictionary) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return
	var missing := maxi(0, layer + 1 - tileset.get_physics_layers_count())
	var scope := COLLISIONS.alt_scope()
	undo_manager.create_action(tr("Edit tile collision shape"), UndoRedo.MERGE_DISABLE, tileset)
	for i in missing:
		undo_manager.add_do_method(tileset, &"add_physics_layer")
	for coords: Vector2i in per_tile:
		if not src.has_tile(coords):
			continue
		var alts := COLLISIONS.target_alts(src, coords, scope)
		undo_manager.add_do_method(self, &"_set_collision_state", source_id, coords, layer, COLLISIONS.shape_state(per_tile[coords], alts))
		if missing == 0:
			undo_manager.add_undo_method(self, &"_set_collision_state", source_id, coords, layer, COLLISIONS.tile_state(src, coords, layer, alts))
	for i in missing:
		undo_manager.add_undo_method(tileset, &"remove_physics_layer", tileset.get_physics_layers_count() + missing - 1 - i)
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


func _add_collision_physics_layer() -> void:
	undo_manager.create_action(tr("Add physics layer"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, &"add_physics_layer")
	undo_manager.add_undo_method(tileset, &"remove_physics_layer", tileset.get_physics_layers_count())
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


func _collision_entry_terrain() -> Dictionary:
	return {id = COLLISION_ENTRY, name = "Collisions", color = COLLISION_COLOR, type = -1,
		categories = [], icon = {}, group = "", object = {}, valid = true, collision = true,
		tool_icon = ICON_DIR + "Collision.svg", tool_hint = "Collisions: mark which tiles are solid"}


func _collision_mode() -> bool:
	return selected_entry == COLLISION_ENTRY and tileset != null


func _data_mode() -> bool:
	return selected_entry == DATA_ENTRY and tileset != null


func _build_collision_panel() -> void:
	var editors := $VBox/HSplit/Editors
	var atlas: Control = $VBox/HSplit/Editors/Panel
	var row := HBoxContainer.new()
	row.name = "AtlasRow"
	row.add_theme_constant_override("separation", 0)
	editors.add_child(row)
	editors.move_child(row, atlas.get_index())
	atlas.reparent(row)
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_collision_panel = COLLISION_PANEL_SCRIPT.new()
	row.add_child(_collision_panel)
	_collision_panel.hide()
	_build_data_panel(row)
	_collision_panel.physics_layer_picked.connect(func(index: int) -> void:
		_collision_layer_index = index
		_sync_collision_mode()
		if is_instance_valid(_collision_shape_window):
			_collision_shape_window.show_physics_layer(index))
	_collision_panel.bits_changed.connect(_set_collision_bits)
	_collision_panel.all_layers_toggled.connect(func(on: bool) -> void:
		COLLISIONS.set_show_all_layers(on)
		update_overlay.emit())
	_collision_tip_timer = Timer.new()
	_collision_tip_timer.one_shot = true
	_collision_tip_timer.wait_time = COLLISION_TIP_DELAY
	_collision_tip_timer.timeout.connect(func() -> void:
		_collision_tip_ready = true
		update_overlay.emit())
	add_child(_collision_tip_timer)
	_build_collision_mode_buttons()
	tile_view.collision_marked.connect(func(source_id: int, coord: Vector2i, solid: bool) -> void:
		if not _collision_stroking:
			_collision_begin()
		_collision_mark(source_id, coord, solid))
	tile_view.collision_stroke_ended.connect(_collision_end)
	tile_view.collision_pick_check = func(event: InputEventWithModifiers) -> bool: return _collision_takes_shape(event)
	tile_view.collision_copy_requested.connect(_copy_collision)
	tile_view.collision_paste_requested.connect(func(source_id: int, coord: Vector2i) -> void:
		if SHAPES.clipboard.is_empty():
			return
		_collision_begin()
		_collision_stamp(source_id, coord)
		_collision_end())


## Physics layer the marks go to, or -1 when the tile set has none.
func _collision_physics_layer() -> int:
	var count := tileset.get_physics_layers_count() if tileset != null else 0
	return clampi(_collision_layer_index, 0, count - 1) if count > 0 else -1


func _sync_collision_mode() -> void:
	if _collision_panel == null:
		return
	var collisions := _collision_mode()
	var data := _data_mode()
	# Both tools mark tiles with clicks; collision_mode carries those clicks in the atlas.
	var on := collisions or data
	tile_view.collision_mode = on
	tile_view.collision_shape_mode = collisions and _collision_shape_mode
	if on:
		tile_view.pick_tiles = collisions and _collision_shape_mode
	_collision_mode_box.visible = collisions
	_sync_collision_clipboard()
	tile_view.collision_layer = _collision_physics_layer() if collisions else -1
	tile_view.collision_color = COLLISIONS.overlay_color()
	_collision_panel.visible = collisions
	if collisions:
		_collision_panel.setup(tileset, _collision_physics_layer())
	tile_view.data_mode = data
	_data_panel.mode_bar.visible = data
	tile_view.data_inspect = data and _data_inspecting()
	if data:
		tile_view.pick_tiles = _data_inspecting()
	_data_panel.visible = data
	if data:
		_data_panel.setup(tileset)
		_sync_data_marks()
	if on:
		select_tiles.visible = false
		tile_view.dim_unassigned_tiles = false
	# The toolbar's picker picks brushes for painting terrain; these tools have none to pick.
	if _picker != null:
		_picker.visible = not on
	_sync_select_layer()
	# Only the pencil and the rectangle make sense for marking tiles.
	for button in _tools_off_for_collisions:
		button.disabled = false
	_tools_off_for_collisions.clear()
	if on:
		for button: Button in [_map_select, line_button, fill_button, _slope_button, replace_button]:
			if button == null:
				continue
			button.disabled = true
			_tools_off_for_collisions.append(button)
		if not (draw_button.button_pressed or rectangle_button.button_pressed):
			draw_button.button_pressed = true
	tile_view.queue_redraw()
	update_overlay.emit()


func _collision_canvas_input(event: InputEvent) -> bool:
	if not (event is InputEventMouseButton or event is InputEventMouseMotion):
		return false
	var cell := tilemap.local_to_map(canvas_tilemap_transform().affine_inverse() * Vector2(event.position))
	var last := current_position
	draw_overlay = true
	if event is InputEventMouseMotion:
		_collision_tip_at = event.position
		if _collision_tip_ready:
			_collision_tip_ready = false
			update_overlay.emit()
		_collision_tip_timer.start()
	elif event.pressed:
		_collision_tip_ready = false
		_collision_tip_timer.stop()
	if cell != current_position:
		current_position = cell
		update_overlay.emit()
	if event is InputEventMouseButton:
		if event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			return false
		if event.pressed and _data_mode() and event.button_index == MOUSE_BUTTON_LEFT \
				and (_picker_modifier_held(event) or _data_panel.pick_armed or _data_inspecting()):
			# Inspect selects the tile, Shift adding it, whatever the picker's key is;
			# copying a tile's fields belongs to Paint.
			var picked := _collision_tile_at(_collision_layers(), tilemap.to_global(tilemap.map_to_local(cell)))
			if not picked.is_empty():
				if _data_inspecting():
					_data_select([[picked[0], picked[1]]], event.shift_pressed)
				else:
					_data_pick(picked[0], picked[1])
			return true
		if event.pressed and _data_inspecting():
			return true
		if event.pressed and event.button_index == MOUSE_BUTTON_LEFT and _collision_takes_shape(event):
			var source := _collision_tile_at(_collision_layers(), tilemap.to_global(tilemap.map_to_local(cell)))
			if not source.is_empty():
				_copy_collision(source[0], source[1])
			return true
		if event.pressed and _collision_shape_mode and _collision_mode():
			if event.button_index == MOUSE_BUTTON_LEFT:
				var found := _collision_tile_at(_collision_layers(), tilemap.to_global(tilemap.map_to_local(cell)))
				if not found.is_empty():
					var src := tileset.get_source(found[0]) as TileSetAtlasSource
					_open_collision_shape(found[0], found[1], src.get_tile_size_in_atlas(found[1]))
			return true
		if event.pressed:
			if _collision_stroking:
				return true
			_collision_solid = event.button_index == MOUSE_BUTTON_LEFT
			_collision_rect = rectangle_button.button_pressed
			_collision_from = cell
			_collision_begin()
			if not _collision_rect:
				_collision_mark_cells([cell])
		elif _collision_stroking:
			if _collision_rect:
				_collision_mark_cells(_cells_in_area(Rect2i(_collision_from, cell - _collision_from).abs()))
			_collision_end()
		update_overlay.emit()
		return true
	if _collision_stroking:
		if event.button_mask & (MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT) == 0:
			_collision_end()
		elif not _collision_rect and cell != last:
			_collision_mark_cells(_get_tileset_line(last, cell, tileset))
		return true
	return false


## Marks the tile seen in each of these cells (of the selected layer's grid), once each.
func _collision_mark_cells(cells: Array) -> void:
	var layers := _collision_layers()
	var seen := {}
	for c: Vector2i in cells:
		var found := _collision_tile_at(layers, tilemap.to_global(tilemap.map_to_local(c)))
		if found.is_empty():
			continue
		var key := Vector3i(found[1].x, found[1].y, found[0])
		if seen.has(key):
			continue
		seen[key] = true
		_collision_mark(found[0], found[1], _collision_solid)


## Visible layers of the edited scene drawn with this tile set, selected layer included.
func _collision_layers() -> Array:
	var out: Array = []
	var root: Node = EditorInterface.get_edited_scene_root() if tilemap.is_inside_tree() else null
	if root == null or not root.is_ancestor_of(tilemap):
		root = tilemap
		while root.get_parent() != null and not root.get_parent() is Viewport:
			root = root.get_parent()
	if root != null:
		out = root.find_children("*", "TileMapLayer", true, false)
		if root is TileMapLayer:
			out.push_front(root)
	if not out.has(tilemap):
		out.append(tilemap)
	return out.filter(func(layer: TileMapLayer): return layer.tile_set == tileset \
		and (layer == tilemap or layer.is_visible_in_tree()))


## [source_id, atlas coords] of the atlas tile drawn on top at this point, or [].
func _collision_tile_at(layers: Array, point: Vector2) -> Array:
	var best: Array = []
	var best_z := 0
	for layer: TileMapLayer in layers:
		var c := layer.local_to_map(layer.to_local(point))
		var source_id := layer.get_cell_source_id(c)
		if source_id < 0 or not (tileset.get_source(source_id) is TileSetAtlasSource):
			continue
		# Same z: later in the tree draws on top.
		var z := _effective_z(layer)
		if best.is_empty() or z >= best_z:
			best_z = z
			best = [source_id, layer.get_cell_atlas_coords(c)]
	return best


func _collision_begin() -> void:
	_collision_stroke.clear()
	_collision_stroking = true
	_collision_added_layer = false
	# Holds back the list rebuild each polygon change would queue, as painting rules does.
	tile_view.collision_stroking = true


func _collision_mark(source_id: int, coords: Vector2i, solid: bool) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return
	if _data_mode():
		_data_mark(source_id, coords, solid)
		return
	if tileset.get_physics_layers_count() == 0:
		if not solid:
			return
		tileset.add_physics_layer()
		_collision_added_layer = true
		_collision_layer_index = 0
		_sync_collision_mode()
	if solid and _collision_stamp_mode:
		_collision_stamp(source_id, coords)
		return
	_collision_action = tr("Mark collisions") if solid else tr("Clear collisions")
	_collision_write(source_id, coords, [[COLLISIONS.full_polygon(tileset, src, coords), false, 1.0]] if solid else [])


## Writes the copied shape with this tile as the top-left of the copied block.
func _collision_stamp(source_id: int, coords: Vector2i) -> void:
	var copied: Dictionary = SHAPES.clipboard
	if copied.is_empty():
		return
	# A copied group lands once per stroke, where it was pressed.
	if copied.cells != Vector2i.ONE and not _collision_stroke.is_empty():
		return
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	var lay: Dictionary = SHAPES.layout(src, coords, copied.cells)
	_collision_action = tr("Paste collision shape")
	var per_tile: Dictionary = SHAPES.clip_per_tile(copied, src, tileset, lay)
	for tile_coords: Vector2i in per_tile:
		_collision_write(source_id, tile_coords, per_tile[tile_coords])


## Sets a tile's polygons ([[points, one_way, margin], ...]) on the tile and the alternatives
## the scope takes in, remembering how it was for the stroke's undo step.
func _collision_write(source_id: int, coords: Vector2i, polygons: Array) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return
	var layer := _collision_physics_layer()
	var alts := COLLISIONS.target_alts(src, coords, COLLISIONS.alt_scope())
	var want := COLLISIONS.shape_state(polygons, alts)
	var key := Vector3i(coords.x, coords.y, source_id)
	if not _collision_stroke.has(key):
		var before := COLLISIONS.tile_state(src, coords, layer, alts)
		if before == want:
			return
		_collision_stroke[key] = [source_id, coords, before, alts]
	COLLISIONS.apply_state(src, coords, layer, want)
	tile_view.queue_redraw()
	update_overlay.emit()


## One undo step per stroke; the changes are already applied, so it commits without running.
func _collision_end() -> void:
	if not _collision_stroking:
		return
	_collision_stroking = false
	tile_view.collision_stroking = false
	if _collision_stroke.is_empty() and not _collision_added_layer:
		return
	var layer := _collision_physics_layer()
	undo_manager.create_action(_collision_action, UndoRedo.MERGE_DISABLE, tileset)
	if _collision_added_layer:
		undo_manager.add_do_method(tileset, &"add_physics_layer")
	for entry: Array in _collision_stroke.values():
		var src := tileset.get_source(entry[0]) as TileSetAtlasSource
		if entry.size() > 4:
			# Custom data: [source, coords, before, alts, fields].
			undo_manager.add_do_method(self, &"_set_data_state", entry[0], entry[1],
				CUSTOM_DATA.tile_state(src, entry[1], entry[4], entry[3]))
			undo_manager.add_undo_method(self, &"_set_data_state", entry[0], entry[1], entry[2])
			continue
		undo_manager.add_do_method(self, &"_set_collision_state", entry[0], entry[1], layer,
			COLLISIONS.tile_state(src, entry[1], layer, entry[3]))
		undo_manager.add_undo_method(self, &"_set_collision_state", entry[0], entry[1], layer, entry[2])
	if _collision_added_layer:
		undo_manager.add_undo_method(tileset, &"remove_physics_layer", 0)
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action(false)
	_collision_stroke.clear()
	queue_tiles_changed()
	if _data_mode():
		_sync_data_marks()


func _set_collision_state(source_id: int, coords: Vector2i, layer: int, state: Array) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src != null and layer < tileset.get_physics_layers_count():
		COLLISIONS.apply_state(src, coords, layer, state)


func _set_collision_bits(index: int, collision_layer: int, collision_mask: int) -> void:
	if tileset == null or index >= tileset.get_physics_layers_count():
		return
	undo_manager.create_action(tr("Change physics layer bits"), UndoRedo.MERGE_ENDS, tileset)
	undo_manager.add_do_method(tileset, &"set_physics_layer_collision_layer", index, collision_layer)
	undo_manager.add_do_method(tileset, &"set_physics_layer_collision_mask", index, collision_mask)
	undo_manager.add_undo_method(tileset, &"set_physics_layer_collision_layer", index, tileset.get_physics_layer_collision_layer(index))
	undo_manager.add_undo_method(tileset, &"set_physics_layer_collision_mask", index, tileset.get_physics_layer_collision_mask(index))
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


func _draw_map_collisions(overlay: Control, transform: Transform2D) -> void:
	var mesh := _map_collision_mesh(transform)
	if not mesh.indices.is_empty():
		RenderingServer.canvas_item_add_triangle_array(overlay.get_canvas_item(), mesh.indices, mesh.points, mesh.colors)
	if _collision_tip_ready and not _collision_stroking:
		_draw_collision_tip(overlay, _collision_hits_at(transform.affine_inverse() * _collision_tip_at))
	_draw_hover_cell(overlay, transform)


## The cell (or box) the next click changes.
func _draw_hover_cell(overlay: Control, transform: Transform2D) -> void:
	if not draw_overlay:
		return
	var tint := Color.WHITE if not (_collision_stroking and not _collision_solid) else Color(1.0, 0.6, 0.5)
	var box := Rect2i(current_position, Vector2i.ZERO)
	if _collision_stroking and _collision_rect:
		box = Rect2i(_collision_from, current_position - _collision_from).abs()
	var half := Vector2(tilemap.tile_set.tile_size) * 0.5
	var outline := PackedVector2Array([
		tilemap.map_to_local(box.position) - half,
		tilemap.map_to_local(Vector2i(box.end.x, box.position.y)) + Vector2(half.x, -half.y),
		tilemap.map_to_local(box.end) + half,
		tilemap.map_to_local(Vector2i(box.position.x, box.end.y)) + Vector2(-half.x, half.y),
	])
	_draw_outline(overlay, transform * outline, tint)

## Every visible tile's polygons, in overlay coordinates, as one triangle mesh.
func _map_collision_mesh(transform: Transform2D) -> Dictionary:
	var mesh := COLLISIONS.new_mesh()
	var layer := _collision_physics_layer()
	if layer >= 0 and COLLISIONS.overlay_on_map():
		var drawn := {}
		if COLLISIONS.show_all_layers():
			for i in tileset.get_physics_layers_count():
				drawn[i] = Color(COLLISIONS.layer_color(i), 0.5 if i == layer else 0.28)
		else:
			drawn[layer] = COLLISIONS.overlay_color()
		var shapes := {}
		var view_world := Rect2(tilemap.to_global(tilemap.map_to_local(_view_cells.position)), Vector2.ZERO) \
			.expand(tilemap.to_global(tilemap.map_to_local(_view_cells.end)))
		var to_overlay := transform * tilemap.global_transform.affine_inverse()
		for map_layer: TileMapLayer in _collision_layers():
			var lo := map_layer.local_to_map(map_layer.to_local(view_world.position)) - Vector2i.ONE
			var hi := map_layer.local_to_map(map_layer.to_local(view_world.end)) + Vector2i.ONE
			var area := Rect2i(lo, hi - lo).intersection(map_layer.get_used_rect())
			var cells: Array = []
			if area.get_area() <= MAX_COLLISION_SCAN:
				cells = _cells_in_area(Rect2i(area.position, area.size - Vector2i.ONE)) if area.has_area() else []
			else:
				cells = map_layer.get_used_cells().filter(func(c): return area.has_point(c))
			var layer_transform := to_overlay * map_layer.global_transform
			for c: Vector2i in cells:
				var source_id := map_layer.get_cell_source_id(c)
				if source_id < 0:
					continue
				var coords := map_layer.get_cell_atlas_coords(c)
				var alt := map_layer.get_cell_alternative_tile(c)
				var cell_transform := layer_transform * Transform2D(0.0, map_layer.map_to_local(c))
				for physics: int in drawn:
					var key := [source_id, coords, alt, physics]
					if not shapes.has(key):
						var td := _cell_tile_data(source_id, coords, alt)
						shapes[key] = COLLISIONS.cell_polygons(td, physics, alt & COLLISIONS.FLIP_FLAGS) if td != null else []
					for polygon: PackedVector2Array in shapes[key]:
						COLLISIONS.add_to_mesh(mesh, cell_transform * polygon, drawn[physics])
	return mesh

## The tile data a map cell draws, flips taken off the alternative id, or null.
func _cell_tile_data(source_id: int, coords: Vector2i, alt: int) -> TileData:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	var base := alt & ~COLLISIONS.FLIP_FLAGS
	if src == null or not src.has_tile(coords) or not src.has_alternative_tile(coords, base):
		return null
	return src.get_tile_data(coords, base)


## What collides at a point (selected layer's local coordinates), on every map layer
## and physics layer: [{map_layer, cell, coords, physics, one_way}].
func _collision_hits_at(point: Vector2) -> Array:
	var hits := []
	var world := tilemap.to_global(point)
	for map_layer: TileMapLayer in _collision_layers():
		var local := map_layer.to_local(world)
		var c := map_layer.local_to_map(local)
		var source_id := map_layer.get_cell_source_id(c)
		if source_id < 0:
			continue
		var coords := map_layer.get_cell_atlas_coords(c)
		var alt := map_layer.get_cell_alternative_tile(c)
		var td := _cell_tile_data(source_id, coords, alt)
		if td == null:
			continue
		var inside := local - map_layer.map_to_local(c)
		for physics in tileset.get_physics_layers_count():
			var polygons := COLLISIONS.cell_polygons(td, physics, alt & COLLISIONS.FLIP_FLAGS)
			for i in polygons.size():
				if Geometry2D.is_point_in_polygon(inside, polygons[i]):
					hits.append({map_layer = map_layer, cell = c, coords = coords, physics = physics,
						one_way = td.is_collision_polygon_one_way(physics, i)})
	return hits


func _draw_collision_tip(overlay: Control, hits: Array) -> void:
	if hits.is_empty():
		return
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "Label")
	var lines := []
	for hit: Dictionary in hits:
		lines.append([COLLISIONS.layer_color(hit.physics), "Physics layer %d · on %s%s · tile %s in %s" % [
			hit.physics, COLLISIONS.bits_text(tileset, hit.physics), " · one-way" if hit.one_way else "",
			str(hit.coords), hit.map_layer.name]])
	var line_height := font.get_height(font_size) + 2
	var width := 0.0
	for line: Array in lines:
		width = maxf(width, font.get_string_size(line[1], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var box := Rect2(_collision_tip_at + Vector2(18, 18), Vector2(width + 32, line_height * lines.size() + 10))
	box.position.x = minf(box.position.x, overlay.size.x - box.size.x - 4)
	box.position.y = minf(box.position.y, overlay.size.y - box.size.y - 4)
	overlay.draw_rect(box, Color(0.08, 0.09, 0.11, 0.92))
	overlay.draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
	for i in lines.size():
		var y := box.position.y + 5 + line_height * i
		overlay.draw_rect(Rect2(box.position.x + 8, y + line_height * 0.5 - 5, 10, 10), lines[i][0])
		overlay.draw_string(font, Vector2(box.position.x + 24, y + font.get_ascent(font_size)), lines[i][1],
			HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.93, 1.0))

#endregion


#region Custom data tool

const CUSTOM_DATA := preload("res://addons/better-tile-editor/editor/CustomData.gd")
const DATA_PANEL_SCRIPT := preload("res://addons/better-tile-editor/editor/CustomDataPanel.gd")
## List id of the Custom data entry, next to Collisions'.
const DATA_ENTRY := -11
const DATA_COLOR := Color(0.86, 0.71, 0.42)

var _data_panel: PanelContainer
## Inspect: the selected tiles, [[source_id, coords], ...].
var _data_selection: Array = []


func _data_entry_terrain() -> Dictionary:
	return {id = DATA_ENTRY, name = "Custom data", color = DATA_COLOR, type = -1,
		categories = [], icon = {}, group = "", object = {}, valid = true,
		tool_icon = ICON_DIR + "CustomData.svg", tool_hint = "Custom data: paint the tile set's custom data fields on tiles"}


func _data_inspecting() -> bool:
	return _data_panel != null and _data_panel.mode == _data_panel.Mode.INSPECT


func _build_data_panel(row: Control) -> void:
	_data_panel = DATA_PANEL_SCRIPT.new()
	row.add_child(_data_panel)
	_data_panel.hide()
	$VBox/Toolbar.add_child(_data_panel.mode_bar)
	_data_panel.mode_bar.hide()
	_data_panel.brush_changed.connect(_sync_data_marks)
	_data_panel.view_changed.connect(_sync_data_marks)
	_data_panel.mode_changed.connect(_sync_collision_mode)
	_data_panel.add_requested.connect(_add_data_field)
	_data_panel.rename_requested.connect(_rename_data_field)
	_data_panel.retype_requested.connect(_retype_data_field)
	_data_panel.delete_requested.connect(_delete_data_field)
	_data_panel.inspect_edited.connect(_data_inspect_edit)
	_data_panel.presets_changed.connect(_store_data_presets)
	_data_panel.field_hovered.connect(func(index: int) -> void:
		tile_view.data_hover = index
		tile_view.queue_redraw()
		update_overlay.emit())
	tile_view.data_pick_check = func(event: InputEventWithModifiers) -> bool:
		return _picker_modifier_held(event) or _data_panel.pick_armed
	tile_view.data_pick_requested.connect(_data_pick)
	tile_view.data_preset_key.connect(func(index: int) -> void:
		if _data_panel.mode == _data_panel.Mode.PAINT:
			_data_panel.apply_preset_index(index))


## What the atlas and the map show, and the counts the panel reports.
func _sync_data_marks() -> void:
	tile_view.data_view = _data_panel.view()
	tile_view.data_overview = _data_panel.overview()
	tile_view.data_brush = _data_panel.brush()
	tile_view.data_color = get_theme_color("accent_color", "Editor")
	var selected := {}
	for entry: Array in _data_selection:
		selected[Vector3i(entry[1].x, entry[1].y, entry[0])] = true
	tile_view.data_selected = selected
	_data_panel.set_pick_key(PICKER_MODIFIER_NAMES[_picker_modifier()])
	var matches := 0
	var used := {}
	var ranges := {}
	var brush: Dictionary = tile_view.data_brush
	for s in tileset.get_source_count():
		var src := tileset.get_source(tileset.get_source_id(s)) as TileSetAtlasSource
		if src == null:
			continue
		for t in src.get_tiles_count():
			var td := src.get_tile_data(src.get_tile_id(t), 0)
			if CUSTOM_DATA.matches(td, brush):
				matches += 1
			var set_values := CUSTOM_DATA.tile_values(tileset, td)
			for field: int in set_values:
				used[field] = true
				if CUSTOM_DATA.numeric(tileset.get_custom_data_layer_type(field)):
					var v := float(set_values[field])
					ranges[field] = Vector2(minf(v, ranges[field].x), maxf(v, ranges[field].y)) if ranges.has(field) else Vector2(v, v)
	tile_view.data_ranges = ranges
	_data_panel.set_match_count(matches if not brush.is_empty() else -1)
	_data_panel.set_used(used)
	tile_view.queue_redraw()
	update_overlay.emit()


## Left writes the brush's values, right puts those fields back to their default.
func _data_mark(source_id: int, coords: Vector2i, paint: bool) -> void:
	var brush: Dictionary = _data_panel.brush()
	if brush.is_empty() or _data_inspecting():
		return
	var values := {}
	for field: int in brush:
		values[field] = brush[field] if paint else CUSTOM_DATA.default_for(tileset.get_custom_data_layer_type(field))
	_collision_action = tr("Paint custom data") if paint else tr("Clear custom data")
	_data_write(source_id, coords, values)


## Sets some fields on a tile and the alternatives the scope takes in, remembering how it was
## for the stroke's undo step.
func _data_write(source_id: int, coords: Vector2i, values: Dictionary) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return
	var fields := values.keys()
	var alts := COLLISIONS.target_alts(src, coords, CUSTOM_DATA.alt_scope())
	var want := CUSTOM_DATA.values_state(values, alts)
	var key := Vector3i(coords.x, coords.y, source_id)
	if not _collision_stroke.has(key):
		var before := CUSTOM_DATA.tile_state(src, coords, fields, alts)
		if before == want:
			return
		_collision_stroke[key] = [source_id, coords, before, alts, fields]
	CUSTOM_DATA.apply_state(src, coords, want)
	tile_view.queue_redraw()
	update_overlay.emit()


func _set_data_state(source_id: int, coords: Vector2i, state: Array) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src != null:
		CUSTOM_DATA.apply_state(src, coords, state)
	if _data_mode():
		_refresh_data_selection()
		_sync_data_marks()


## The picker takes a tile's configuration as the brush, to change it or paint it elsewhere.
func _data_pick(source_id: int, coords: Vector2i) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null or not src.has_tile(coords):
		return
	_data_panel.set_mode(_data_panel.Mode.PAINT)
	_data_panel.load_values(CUSTOM_DATA.whole_config(tileset, src.get_tile_data(coords, 0)))
	_data_panel.follow_preset()
	if _data_panel.pick_armed:
		_data_panel._pick_button.button_pressed = false


## Inspect: a box of tiles from the atlas, added to the selection with Shift.
func _data_select_box(source_id: int, origin: Vector2i, cells: Vector2i, add: bool) -> void:
	var src := tileset.get_source(source_id) as TileSetAtlasSource
	if src == null:
		return
	var tiles := []
	for y in cells.y:
		for x in cells.x:
			var at := src.get_tile_at_coords(origin + Vector2i(x, y))
			if at != Vector2i(-1, -1) and not tiles.has([source_id, at]):
				tiles.append([source_id, at])
	_data_select(tiles, add)


func _data_select(tiles: Array, add: bool) -> void:
	if not add:
		_data_selection.clear()
	for tile: Array in tiles:
		if not _data_selection.has(tile):
			_data_selection.append(tile)
	_refresh_data_selection()
	_sync_data_marks()


## The values the selected tiles share per field, MIXED where they differ.
func _refresh_data_selection() -> void:
	var values := {}
	var valid := _data_selection.filter(func(tile: Array):
		var src := tileset.get_source(tile[0]) as TileSetAtlasSource
		return src != null and src.has_tile(tile[1]))
	_data_selection = valid
	for field in tileset.get_custom_data_layers_count():
		var first := true
		for tile: Array in valid:
			var src := tileset.get_source(tile[0]) as TileSetAtlasSource
			var value: Variant = src.get_tile_data(tile[1], 0).get_custom_data_by_layer_id(field)
			if first:
				values[field] = value
				first = false
			elif values[field] != value:
				values[field] = _data_panel.MIXED
				break
	_data_panel.show_selection(values, valid.size())


## Inspect: one value on every selected tile, as one undo step.
func _data_inspect_edit(field: int, value: Variant) -> void:
	if _data_selection.is_empty():
		return
	_collision_begin()
	_collision_action = tr("Set custom data")
	for tile: Array in _data_selection:
		_data_write(tile[0], tile[1], {field: value})
	_collision_end()
	_refresh_data_selection()
	_sync_data_marks()


func _store_data_presets(list: Array) -> void:
	undo_manager.create_action(tr("Change custom data presets"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(CUSTOM_DATA, &"set_presets", tileset, list)
	undo_manager.add_undo_method(CUSTOM_DATA, &"set_presets", tileset, CUSTOM_DATA.presets(tileset))
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


func _add_data_field(field_name: String, type: int) -> void:
	if tileset == null:
		return
	var index := tileset.get_custom_data_layers_count()
	undo_manager.create_action(tr("Add custom data field"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, &"add_custom_data_layer")
	undo_manager.add_do_method(tileset, &"set_custom_data_layer_name", index, field_name)
	undo_manager.add_do_method(tileset, &"set_custom_data_layer_type", index, type)
	undo_manager.add_undo_method(tileset, &"remove_custom_data_layer", index)
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


## Presets name their fields, so a rename carries over to them.
func _rename_data_field(index: int, field_name: String) -> void:
	var old := tileset.get_custom_data_layer_name(index)
	var before := CUSTOM_DATA.presets(tileset)
	var after := before.duplicate(true)
	for preset: Dictionary in after:
		if preset.values.has(old):
			preset.values[field_name] = preset.values[old]
			preset.values.erase(old)
	undo_manager.create_action(tr("Rename custom data field"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, &"set_custom_data_layer_name", index, field_name)
	undo_manager.add_undo_method(tileset, &"set_custom_data_layer_name", index, old)
	undo_manager.add_do_method(CUSTOM_DATA, &"set_presets", tileset, after)
	undo_manager.add_undo_method(CUSTOM_DATA, &"set_presets", tileset, before)
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


## A new type resets the values, so undo puts back the type and every tile's value.
func _retype_data_field(index: int, type: int) -> void:
	var before := tileset.get_custom_data_layer_type(index)
	if before == type:
		return
	undo_manager.create_action(tr("Change custom data field type"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, &"set_custom_data_layer_type", index, type)
	undo_manager.add_undo_method(tileset, &"set_custom_data_layer_type", index, before)
	undo_manager.add_undo_method(CUSTOM_DATA, &"restore_field", tileset, index, CUSTOM_DATA.field_snapshot(tileset, index))
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


func _delete_data_field(index: int) -> void:
	undo_manager.create_action(tr("Delete custom data field"), UndoRedo.MERGE_DISABLE, tileset)
	undo_manager.add_do_method(tileset, &"remove_custom_data_layer", index)
	undo_manager.add_undo_method(tileset, &"add_custom_data_layer", index)
	undo_manager.add_undo_method(tileset, &"set_custom_data_layer_name", index, tileset.get_custom_data_layer_name(index))
	undo_manager.add_undo_method(tileset, &"set_custom_data_layer_type", index, tileset.get_custom_data_layer_type(index))
	undo_manager.add_undo_method(CUSTOM_DATA, &"restore_field", tileset, index, CUSTOM_DATA.field_snapshot(tileset, index))
	undo_manager.add_do_method(self, &"_sync_collision_mode")
	undo_manager.add_undo_method(self, &"_sync_collision_mode")
	undo_manager.commit_action()


## The map follows the atlas: the shown field lit and named, or the tiles holding the whole
## brush outlined; the selection in Inspect outlined in white.
func _draw_map_data(overlay: Control, transform: Transform2D) -> void:
	var field: int = tile_view.data_hover if tile_view.data_hover >= 0 else tile_view.data_view
	if field >= tileset.get_custom_data_layers_count():
		field = -1
	var brush: Dictionary = tile_view.data_brush
	var showing: bool = field >= 0 or tile_view.data_overview \
		or (tile_view.data_view == tile_view.DATA_VIEW_MATCHES and not brush.is_empty()) \
		or (_data_inspecting() and not _data_selection.is_empty())
	if showing:
		var accent := get_theme_color("accent_color", "Editor")
		var mesh := COLLISIONS.new_mesh()
		var outlines := []
		var labels := []
		var shape: PackedVector2Array = BetterTerrain.data.cell_polygon(tileset)
		var cell_size := Vector2(tileset.tile_size)
		var view_world := Rect2(tilemap.to_global(tilemap.map_to_local(_view_cells.position)), Vector2.ZERO) \
			.expand(tilemap.to_global(tilemap.map_to_local(_view_cells.end)))
		var to_overlay := transform * tilemap.global_transform.affine_inverse()
		var looks := {}
		for map_layer: TileMapLayer in _collision_layers():
			var lo := map_layer.local_to_map(map_layer.to_local(view_world.position)) - Vector2i.ONE
			var hi := map_layer.local_to_map(map_layer.to_local(view_world.end)) + Vector2i.ONE
			var area := Rect2i(lo, hi - lo).intersection(map_layer.get_used_rect())
			if not area.has_area() or area.get_area() > MAX_COLLISION_SCAN:
				continue
			var layer_transform := to_overlay * map_layer.global_transform
			for c: Vector2i in _cells_in_area(Rect2i(area.position, area.size - Vector2i.ONE)):
				var source_id := map_layer.get_cell_source_id(c)
				if source_id < 0:
					continue
				var alt := map_layer.get_cell_alternative_tile(c)
				var key := [source_id, map_layer.get_cell_atlas_coords(c), alt]
				if not looks.has(key):
					looks[key] = _data_cell_look(_cell_tile_data(source_id, key[1], alt), field, brush, accent,
						_data_selection.has([source_id, key[1]]))
				var look: Array = looks[key]
				if look[0].a <= 0.0 and not look[2]:
					continue
				var cell := PackedVector2Array()
				for p in shape:
					cell.append(layer_transform * (map_layer.map_to_local(c) + p * cell_size))
				if look[0].a > 0.0:
					COLLISIONS.add_to_mesh(mesh, cell, look[0])
				if look[2] or look[3]:
					outlines.append([cell, Color.WHITE if look[2] else Color(look[0], 1.0)])
				if not look[1].is_empty() and labels.size() < 400:
					labels.append([layer_transform * map_layer.map_to_local(c), look[1]])
		if not mesh.indices.is_empty():
			RenderingServer.canvas_item_add_triangle_array(overlay.get_canvas_item(), mesh.indices, mesh.points, mesh.colors)
		for outline: Array in outlines:
			_draw_outline(overlay, outline[0], outline[1])
		var cell_width := (transform.basis_xform(Vector2(tileset.tile_size.x, 0))).length()
		if cell_width >= 28.0:
			var font := get_theme_font("font", "Label")
			var font_size := clampi(int(cell_width / 5.0), 8, 14)
			var cell_screen := Vector2(cell_width, (transform.basis_xform(Vector2(0, tileset.tile_size.y))).length())
			for entry: Array in labels:
				tile_view.draw_centered_lines(overlay, font, entry[1], Rect2(entry[0] - cell_screen * 0.5, cell_screen), font_size)
	if _collision_tip_ready and not _collision_stroking:
		_draw_data_tip(overlay, transform.affine_inverse() * _collision_tip_at)
	_draw_hover_cell(overlay, transform)


## How a map cell shows: [fill, label, selected, outlined].
func _data_cell_look(td: TileData, field: int, brush: Dictionary, accent: Color, selected: bool) -> Array:
	if td == null:
		return [Color.TRANSPARENT, "", false, false]
	if field >= 0:
		var value: Variant = td.get_custom_data_by_layer_id(field)
		if CUSTOM_DATA.is_set(value, tileset.get_custom_data_layer_type(field)):
			var ranges: Dictionary = tile_view.data_ranges
			var fill := Color(CUSTOM_DATA.heat(float(value), ranges[field]), 0.5) if ranges.has(field) else Color(accent, 0.35)
			return [fill, CUSTOM_DATA.label(tileset, td, field), selected, true]
		return [Color(0, 0, 0, 0.6), "", selected, false]
	var matched: bool = tile_view.data_view == tile_view.DATA_VIEW_MATCHES and CUSTOM_DATA.matches(td, brush)
	var held: String = CUSTOM_DATA.summary(tileset, td) if tile_view.data_overview else ""
	if not held.is_empty():
		return [Color(0, 0, 0, 0.6), held, selected, matched]
	if matched:
		return [Color(accent, 0.3), "", selected, true]
	return [Color.TRANSPARENT, "", selected, false]


## The fields set on the tile seen under the mouse.
func _draw_data_tip(overlay: Control, point: Vector2) -> void:
	var found := _collision_tile_at(_collision_layers(), tilemap.to_global(point))
	if found.is_empty():
		return
	var src := tileset.get_source(found[0]) as TileSetAtlasSource
	var td := src.get_tile_data(found[1], 0)
	var lines := ["Tile %s" % str(found[1])]
	var set_values := CUSTOM_DATA.tile_values(tileset, td)
	for field: int in set_values:
		lines.append("%s = %s" % [tileset.get_custom_data_layer_name(field), CUSTOM_DATA.format(set_values[field])])
	if set_values.is_empty():
		lines.append("No field set")
	var font := get_theme_font("font", "Label")
	var font_size := get_theme_font_size("font_size", "Label")
	var line_height := font.get_height(font_size) + 2
	var width := 0.0
	for line: String in lines:
		width = maxf(width, font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x)
	var box := Rect2(_collision_tip_at + Vector2(18, 18), Vector2(width + 16, line_height * lines.size() + 10))
	box.position.x = minf(box.position.x, overlay.size.x - box.size.x - 4)
	box.position.y = minf(box.position.y, overlay.size.y - box.size.y - 4)
	overlay.draw_rect(box, Color(0.08, 0.09, 0.11, 0.92))
	overlay.draw_rect(box, Color(1, 1, 1, 0.25), false, 1.0)
	for i in lines.size():
		overlay.draw_string(font, Vector2(box.position.x + 8, box.position.y + 5 + line_height * i + font.get_ascent(font_size)),
			lines[i], HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(0.9, 0.93, 1.0) if i > 0 else Color(0.65, 0.72, 0.85))

## Toolbar buttons show their names beside the icons with the "Show tool names" option,
## all of them at once, so one tool does not show text while the next does not.
func _apply_tool_names() -> void:
	var names := {draw_button: "Pencil", line_button: "Line", rectangle_button: "Rectangle",
		fill_button: "Bucket", replace_button: "Replace"}
	if _map_select != null:
		names[_map_select] = "Select"
	if _slope_button != null:
		names[_slope_button] = "Slope"
	for box: Node in [_collision_mode_box, _data_panel.mode_bar if _data_panel != null else null]:
		if box != null:
			for child in box.get_children():
				if child is Button and child.has_meta(&"tool_name"):
					names[child] = child.get_meta(&"tool_name")
	var settings := EditorInterface.get_editor_settings()
	var on := settings.has_setting(SHOW_TOOL_NAMES_SETTING) and bool(settings.get_setting(SHOW_TOOL_NAMES_SETTING))
	for button: Button in names:
		button.text = names[button] if on else ""

#endregion


#region Missing pieces

func _open_coverage(terrain_id: int) -> void:
	var dialog := COVERAGE_WINDOW.new()
	dialog.applied.connect(_apply_coverage.bind(terrain_id))
	add_child(dialog)
	dialog.close_requested.connect(dialog.queue_free)
	dialog.confirmed.connect(dialog.queue_free, CONNECT_DEFERRED)
	dialog.canceled.connect(dialog.queue_free)
	# Filled once open: laid out before, the card flow is one card wide and too tall.
	dialog.popup_centered(Vector2i(1200, 680) * EditorInterface.get_editor_scale())
	dialog.setup(tileset, terrain_id)


func _apply_coverage_turns(added: Array, removed: Array, built: Array = [], terrain_id: int = -1) -> void:
	_apply_coverage({added = added, removed = removed, built = built}, terrain_id)


## Applies the window's plan as one undoable step: turns added to and taken from tiles, the
## fill tiles' variety, and the pieces put together from quarters, in a new atlas.
func _apply_coverage(plan: Dictionary, terrain_id: int) -> void:
	# {TileData: [transforms before, weight before, transforms after, weight after]}
	var lists := {}
	var entry := func(source: Dictionary) -> Array:
		var src := tileset.get_source(source.source_id) as TileSetAtlasSource
		if src == null or not src.has_alternative_tile(source.coord, source.alt):
			return []
		var td := src.get_tile_data(source.coord, source.alt)
		if not lists.has(td):
			var weight := BetterTerrain.get_tile_transform_weight(td)
			lists[td] = [BetterTerrain.get_tile_transforms(td), weight, BetterTerrain.get_tile_transforms(td), weight]
		return lists[td]
	for source: Dictionary in plan.get("added", []):
		var item: Array = entry.call(source)
		if not item.is_empty() and not source.flags in item[2]:
			item[2].append(source.flags)
	for source: Dictionary in plan.get("removed", []):
		var item: Array = entry.call(source)
		if not item.is_empty():
			item[2].erase(source.flags)
	var variety: Dictionary = plan.get("variety", {})
	for tile: Dictionary in variety.get("tiles", []):
		var item: Array = entry.call(tile.merged({alt = 0}))
		if not item.is_empty():
			item[2] = (variety.flags as Array).duplicate()
			item[3] = variety.weight
	for td: TileData in lists.keys():
		if lists[td][0] == lists[td][2] and is_equal_approx(lists[td][1], lists[td][3]):
			lists.erase(td)
	var built: Array = plan.get("built", [])
	var collision: Dictionary = plan.get("collision", {})
	var shape_layer: int = collision.get("layer", 0)
	var corners: Array = plan.get("corners", [])
	if lists.is_empty() and (built.is_empty() or terrain_id < 0) and collision.is_empty() and corners.is_empty():
		return
	undo_manager.create_action("Make missing pieces", UndoRedo.MERGE_DISABLE, tileset)
	# A terrain of sides only read with corners: its drawn tiles, unnotched, get their corner bits.
	for tile: Dictionary in corners:
		var corner_src := tileset.get_source(tile.source_id) as TileSetAtlasSource
		var corner_td := corner_src.get_tile_data(tile.coord, tile.alt)
		for bit: int in tile.bits:
			undo_manager.add_do_method(BetterTerrain, &"add_tile_peering_type", tileset, corner_td, bit, terrain_id)
			undo_manager.add_undo_method(BetterTerrain, &"remove_tile_peering_type", tileset, corner_td, bit, terrain_id)
	for td: TileData in lists:
		undo_manager.add_do_method(BetterTerrain, &"set_tile_transforms", tileset, td, lists[td][2], lists[td][3])
		undo_manager.add_undo_method(BetterTerrain, &"set_tile_transforms", tileset, td, lists[td][0], lists[td][1])
	if not collision.is_empty():
		var layer_count := tileset.get_physics_layers_count()
		if shape_layer >= layer_count:
			shape_layer = layer_count
			undo_manager.add_do_method(tileset, &"add_physics_layer")
			undo_manager.add_undo_method(tileset, &"remove_physics_layer", shape_layer)
		if collision.get("scope", 0) == COVERAGE_WINDOW.Scope.EVERY:
			var sheets := {}
			for tile: Dictionary in collision.get("tiles", []):
				var src := tileset.get_source(tile.source_id) as TileSetAtlasSource
				var td := src.get_tile_data(tile.coord, 0)
				var before: Array = QUARTER_PIECES.get_shapes(td, shape_layer) if shape_layer < layer_count else []
				var image := QUARTER_PIECES.tile_image(tileset, {source_id = tile.source_id, coord = tile.coord, flags = 0}, sheets)
				var mask: int = COVERAGE.normalize(tile.mask, collision.get("type", 0), collision.get("with_corners", true))
				undo_manager.add_do_method(QUARTER_PIECES, &"set_shapes", tileset, td, shape_layer, QUARTER_PIECES.piece_shapes(image, mask, collision))
				undo_manager.add_undo_method(QUARTER_PIECES, &"set_shapes", tileset, td, shape_layer, before)
	if not built.is_empty() and terrain_id >= 0:
		var first: Dictionary = built[0].quarters[0]
		var other: int = plan.get("other", -1)
		var other_name: String = BetterTerrain.get_terrain(tileset, other).name if other >= 0 else ""
		var path: String = QUARTER_PIECES.file_for(tileset, BetterTerrain.get_terrain(tileset, terrain_id).name, first.source_id, other_name)
		var src: TileSetAtlasSource = QUARTER_PIECES.build_source(tileset, terrain_id, built, built[0].size, path)
		var source_id := tileset.get_next_source_id()
		var shapes := {}
		if plan.get("shapes_off", false):
			shapes = {off = true}
		elif not collision.is_empty():
			shapes = collision.merged({layer = shape_layer})
			shapes.erase("tiles")
			shapes.erase("masks")
			# No list means every new piece.
			if collision.has("masks"):
				shapes.only = collision.masks
		undo_manager.add_do_method(self, &"_add_quarter_source", src, source_id, terrain_id, built, shapes,
			other, plan.get("with_corners", true))
		undo_manager.add_undo_method(tileset, &"remove_source", source_id)
	undo_manager.add_do_method(tile_view, &"queue_redraw")
	undo_manager.add_undo_method(tile_view, &"queue_redraw")
	undo_manager.commit_action()


func _add_quarter_source(src: TileSetAtlasSource, source_id: int, terrain_id: int, pieces: Array,
		shapes: Dictionary = {}, other: int = -1, with_corners: bool = true) -> void:
	tileset.add_source(src, source_id)
	QUARTER_PIECES.fill_source(tileset, src, terrain_id, pieces, shapes, other, with_corners)

#endregion
