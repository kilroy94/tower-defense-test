class_name AudioUtils
extends RefCounted


static func play_world_sound(context_node: Node, world_position: Vector3, stream: AudioStream, volume_db: float = 0.0) -> void:
	if context_node == null or not is_instance_valid(context_node) or stream == null:
		return

	var scene_root := context_node.get_tree().current_scene
	if scene_root == null:
		scene_root = context_node.get_tree().root

	var player := AudioStreamPlayer3D.new()
	player.stream = stream
	player.volume_db = volume_db
	player.position = world_position
	player.finished.connect(player.queue_free)
	scene_root.add_child(player)
	player.play()
