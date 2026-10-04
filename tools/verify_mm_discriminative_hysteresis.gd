extends SceneTree
## Load the fixture only after this tree has initialized. No static Avatar,
## matcher, database, or extension-resource preload in this scratch entry.
func _initialize()->void:
	_load_fixture.call_deferred()

func _load_fixture()->void:
	create_timer(70.0).timeout.connect(func():push_error("MM_DISCRIMINATIVE entry watchdog");quit(1))
	var script:Script=load("res://tools/mm_discriminative_hysteresis_fixture.gd")
	if script==null:push_error("MM_DISCRIMINATIVE fixture load failed");quit(1);return
	var fixture:Node=script.new()
	root.add_child(fixture)
