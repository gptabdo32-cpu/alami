extends Node

signal pool_registered(pool_key: StringName, capacity: int)
signal pooled_acquired(pool_key: StringName)
signal pooled_released(pool_key: StringName)

var _templates: Dictionary = {}
var _available: Dictionary = {}
var _capacity: Dictionary = {}
var _parents: Dictionary = {}

func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS

func register_scene_pool(pool_key: StringName, scene: PackedScene, initial_size: int = 0, capacity: int = 32, parent: Node = null) -> void:
	if scene == null:
		return
	_templates[pool_key] = scene
	_capacity[pool_key] = maxi(0, capacity)
	if not _available.has(pool_key):
		_available[pool_key] = []
	if parent != null:
		_parents[pool_key] = parent
	pool_registered.emit(pool_key, _capacity[pool_key])

	var warmup := maxi(0, initial_size)
	for i in range(warmup):
		var node := _create_instance(pool_key)
		if node != null:
			release(node, pool_key)

func has_pool(pool_key: StringName) -> bool:
	return _templates.has(pool_key)

func get_available_count(pool_key: StringName) -> int:
	if not _available.has(pool_key):
		return 0
	var stack: Array = _available.get(pool_key, []) as Array
	return stack.size()

func acquire(pool_key: StringName, parent: Node = null) -> Node:
	if not _templates.has(pool_key):
		return null

	var stack: Array = _available.get(pool_key, []) as Array
	var node: Node = null
	if not stack.is_empty():
		node = stack.pop_back() as Node
		_available[pool_key] = stack
	else:
		node = _create_instance(pool_key)

	if node == null:
		return null

	var target_parent: Node = parent
	if target_parent == null:
		target_parent = _parents.get(pool_key, null) as Node
	if target_parent != null and node.get_parent() != target_parent:
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		target_parent.add_child(node)

	_prepare_for_reuse(node)
	pooled_acquired.emit(pool_key)
	return node

func release(node: Node, pool_key: StringName = &"") -> void:
	if node == null or not is_instance_valid(node):
		return

	var resolved_key: StringName = pool_key
	if resolved_key == &"":
		var meta_key: Variant = node.get_meta("_object_pool_key", &"")
		if meta_key is StringName:
			resolved_key = meta_key
		else:
			resolved_key = StringName(str(meta_key))

	if resolved_key == &"" or not _templates.has(resolved_key):
		node.queue_free()
		return

	_detach_from_parent(node)
	_prepare_for_pool(node)

	var stack: Array = _available.get(resolved_key, []) as Array
	var capacity: int = int(_capacity.get(resolved_key, 0))
	if capacity > 0 and stack.size() >= capacity:
		node.queue_free()
		return

	stack.append(node)
	_available[resolved_key] = stack
	pooled_released.emit(resolved_key)

func clear_pool(pool_key: StringName) -> void:
	if not _available.has(pool_key):
		return
	for node in _available[pool_key]:
		if is_instance_valid(node):
			node.queue_free()
	_available[pool_key] = []

func clear_all() -> void:
	for key in _available.keys():
		clear_pool(key)
	_templates.clear()
	_available.clear()
	_capacity.clear()
	_parents.clear()

func _create_instance(pool_key: StringName) -> Node:
	var scene: PackedScene = _templates.get(pool_key, null) as PackedScene
	if scene == null:
		return null
	var node: Node = scene.instantiate()
	if node == null:
		return null
	node.set_meta("_object_pool_key", pool_key)
	return node

func _prepare_for_reuse(node: Node) -> void:
	node.set_process_mode(Node.PROCESS_MODE_INHERIT)
	if node.has_method("set_sleeping"):
		node.call("set_sleeping", false)

func _prepare_for_pool(node: Node) -> void:
	node.set_process_mode(Node.PROCESS_MODE_DISABLED)
	if node.has_method("set_sleeping"):
		node.call("set_sleeping", true)

func _detach_from_parent(node: Node) -> void:
	var parent := node.get_parent()
	if parent != null:
		parent.remove_child(node)
