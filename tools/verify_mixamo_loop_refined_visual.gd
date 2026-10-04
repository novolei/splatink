extends SceneTree
## Independent pose captures. This does not exercise real movement or MM selection.
func _initialize()->void:_run.call_deferred()
func _run()->void:
	var helper:Node=load("res://tools/mixamo_loop_refined_visual_fixture.gd").new()
	root.add_child(helper)
