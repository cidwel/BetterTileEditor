@tool
extends RefCounted

const NAMES := ["CliffFaces", "ScatterDecor", "ExemplarEdges", "LookupEdges"]
const PREPARED := &"_better_terrain_support"

static func is_support(node: Node) -> bool:
	if not node is TileMapLayer or not node.get_parent() is TileMapLayer:
		return false
	var label := str(node.name).trim_prefix("_")
	return label in NAMES or (label.begins_with("Mass") and label.trim_prefix("Mass").is_valid_int())

static func prepare(layer: TileMapLayer) -> void:
	var label := str(layer.name).trim_prefix("_")
	if label == "LookupEdges":
		label = "ExemplarEdges"
	layer.name = "_" + label
	# Lock only once, after that the lock belongs to the user.
	if not layer.has_meta(PREPARED):
		layer.set_meta(PREPARED, true)
		layer.set_meta("_edit_lock_", true)

static func is_locked(node: Node) -> bool:
	return is_support(node) and bool(node.get_meta("_edit_lock_", false))

## Unlocked support layers are hand edited, generators leave them alone.
static func is_frozen(node: Node) -> bool:
	return node != null and is_support(node) and node.has_meta(PREPARED) \
		and not bool(node.get_meta("_edit_lock_", false))

static func unlock(layer: TileMapLayer) -> void:
	layer.set_meta(PREPARED, true)
	layer.remove_meta("_edit_lock_")

static func find_layer(parent: Node, label: String) -> TileMapLayer:
	var layer := parent.get_node_or_null(NodePath(label))
	if layer == null:
		layer = parent.get_node_or_null(NodePath(label.trim_prefix("_")))
	return layer as TileMapLayer
