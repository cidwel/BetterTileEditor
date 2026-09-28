@tool
extends Node

const Layers := preload("res://addons/better-tile-editor/SupportLayers.gd")
const CliffTerrain := preload("res://addons/better-tile-editor/CliffTerrain.gd")
const ScatterTerrain := preload("res://addons/better-tile-editor/ScatterTerrain.gd")
const ExemplarTerrain := preload("res://addons/better-tile-editor/ExemplarTerrain.gd")
const ObjectTerrain := preload("res://addons/better-tile-editor/ObjectTerrain.gd")
var hide_layers := false
var _frozen := {}
var _hidden: Array[TreeItem] = []
var _scene_tree: Tree

func _ready() -> void:
	get_tree().node_added.connect(_node_added)
	# Both the Scene tree lock button and the 2D editor emits this.
	for editor in EditorInterface.get_editor_main_screen().find_children("*", "CanvasItemEditor", true, false):
		editor.connect(&"item_lock_status_changed", _on_lock_changed, CONNECT_DEFERRED)
	for dock in EditorInterface.get_base_control().find_children("*", "SceneTreeDock", true, false):
		for editor in dock.find_children("*", "SceneTreeEditor", true, false):
			var trees := editor.find_children("*", "Tree", true, false)
			if not trees.is_empty():
				_scene_tree = trees[0]
				_scene_tree.draw.connect(refresh.call_deferred)
				break

func _exit_tree() -> void:
	_restore_items()

func prepare_scene(root: Node) -> void:
	if root == null:
		return
	for layer in root.find_children("*", "TileMapLayer", true, false):
		if Layers.is_support(layer):
			Layers.prepare(layer)
	_remember_frozen()
	refresh.call_deferred()

func _node_added(node: Node) -> void:
	if Layers.is_support(node):
		_prepare_added.call_deferred(node)

func _prepare_added(node: Node) -> void:
	if is_instance_valid(node):
		Layers.prepare(node)

func _restore_items() -> void:
	for item in _hidden:
		if is_instance_valid(item):
			item.visible = true
	_hidden.clear()

func refresh() -> void:
	_hidden = _hidden.filter(func(item): return is_instance_valid(item))
	if not hide_layers:
		_restore_items()
		return
	if is_instance_valid(_scene_tree) and _scene_tree.get_root() != null:
		_hide_items(_scene_tree.get_root())

func _hide_items(item: TreeItem) -> void:
	var path = item.get_metadata(0)
	if path is NodePath:
		var node := get_node_or_null(path)
		if node != null and Layers.is_support(node) and item.visible:
			if not item in _hidden:
				_hidden.append(item)
			item.visible = false
	for child in item.get_children():
		_hide_items(child)


func _support_layers() -> Array:
	var root := EditorInterface.get_edited_scene_root()
	if root == null:
		return []
	return root.find_children("*", "TileMapLayer", true, false).filter(func(l): return Layers.is_support(l))


func _remember_frozen() -> void:
	_frozen.clear()
	for layer in _support_layers():
		if Layers.is_frozen(layer):
			_frozen[layer.get_instance_id()] = true


# Re-locked layers go back to their generator right away.
func _on_lock_changed() -> void:
	for layer in _support_layers():
		if _frozen.has(layer.get_instance_id()) and Layers.is_locked(layer):
			_regenerate(layer)
	_remember_frozen()


func _regenerate(layer: TileMapLayer) -> void:
	var owner_layer := layer.get_parent() as TileMapLayer
	var bt := get_tree().root.get_node_or_null("BetterTerrain")
	if owner_layer == null or bt == null:
		return
	var label := str(layer.name).trim_prefix("_")
	match label:
		"CliffFaces":
			CliffTerrain.rebuild(owner_layer, bt, false)
		"ScatterDecor":
			ScatterTerrain.rebuild(owner_layer)
		"ExemplarEdges", "LookupEdges":
			ExemplarTerrain.rebuild(owner_layer, bt)
		_:
			if label.begins_with("Mass"):
				ObjectTerrain.fix_mass(owner_layer, false)
	print("[BetterTerrain] %s locked again: regenerated from %s" % [layer.name, owner_layer.name])
