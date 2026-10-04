extends SceneTree
## Only a late-loaded resource/FK contract, never a locomotion feel acceptance.
func _initialize()->void:
	_run.call_deferred()

func _run()->void:
	var source:Script=load("res://tools/mixamo_loop_refined_fixture.gd") as Script
	if source==null:quit(1);return
	var helper:Node=source.new()
	root.add_child(helper)
