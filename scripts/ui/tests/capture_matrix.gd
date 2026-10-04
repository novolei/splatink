extends SceneTree
## Run only through tools/run_godot.ps1, with a GPU display. Does not write user settings.
## --script res://scripts/ui/tests/capture_matrix.gd -- --matrix-output=res://shots/ui-native-matrix
const Game=preload("res://scripts/ink_game.gd")
const Fixture=preload("res://scripts/ui/lab_fixture.gd")
const VARIANTS:Array[String]=["loading","title","main","mode","setup","loadout","locker","settings","howto","credits","pause","results","online","lobby","hud","settings-video","settings-audio","settings-gameplay","locker-hair","locker-face","locker-outfit","setup-boss","hud-charger","hud-map","news-1","news-2"]
var game:InkGame
var directory:String="res://shots/ui-native-matrix"
var report:Dictionary={"viewport":[1280,720],"fixture":"tools/ui-lab.js","source_directory":"shots/reference/ui","pages":[],"failures":[]}
var settle_seconds:float=2.0
var targets:Array[String]=VARIANTS.duplicate()

func _initialize()->void:
	for argument:String in OS.get_cmdline_user_args():
		if argument.begins_with("--matrix-output="):directory=argument.trim_prefix("--matrix-output=")
		elif argument.begins_with("--matrix-pages="):targets.assign(argument.trim_prefix("--matrix-pages=").split(",",false))
		elif argument.begins_with("--matrix-settle="):settle_seconds=clampf(float(argument.trim_prefix("--matrix-settle=")),1.5,10.0)
	create_timer(300).timeout.connect(func()->void:push_error("UI matrix watchdog expired");quit(1))
	_run.call_deferred()

func _run()->void:
	if DisplayServer.get_name()=="headless":push_error("UI matrix needs a GPU window to compare rendered UI pixels");quit(1);return
	root.size=Vector2i(1280,720)
	DisplayServer.window_set_size(Vector2i(1280,720))
	root.content_scale_size=Vector2i(1280,720)
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	game=Game.new();root.add_child(game)
	game._args["smoke"]="ui-matrix";game._args["ui-fixture"]=true
	game.ui.fixture_mode=true
	await create_timer(.2).timeout
	for variant:String in targets:
		_reset()
		game._open_fixture_page(variant)
		await create_timer(maxf(settle_seconds,8.0) if variant=="results" else settle_seconds).timeout
		await process_frame
		await RenderingServer.frame_post_draw
		var file:String=directory.path_join(variant+".png")
		var error:Error=root.get_texture().get_image().save_png(ProjectSettings.globalize_path(file))
		var page:Dictionary={"variant":variant,"page":game.ui.page,"path":file,"reference":"res://shots/reference/ui/"+variant+".png","save_error":error,"in_match":game.ui.in_match,"menu_visible":game.ui._menu.visible,"draw_calls":int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME)),"objects":int(Performance.get_monitor(Performance.RENDER_TOTAL_OBJECTS_IN_FRAME)),"controls":[]}
		_scan(game.ui.root,page.controls)
		report.pages.append(page)
		if error!=OK:report.failures.append({"variant":variant,"error":error_string(error)})
		_write_json(directory.path_join(variant+".json"),page)
		print("UI_MATRIX ",variant," ",file," controls=",page.controls.size()," draws=",page.draw_calls)
	_reset()
	_write_json(directory.path_join("matrix.json"),report)
	print("UI_MATRIX_COMPLETE pages=",report.pages.size()," failures=",report.failures.size())
	quit(0 if report.failures.is_empty() else 1)

func _reset()->void:
	game.state="menu";game.paused=false;paused=false
	game.ui._page_token+=1;game.ui._wipe.abort()
	game.ui._paused=false;game.ui.in_match=false
	if is_instance_valid(game.ui._news):game.ui._news.queue_free();game.ui._news=null
	if is_instance_valid(game.ui._modal):game.ui.close_modal()
	game.ui.hud.hide();game.ui.hud.set_map_open(false);game.ui.boss_hud.clear()
	game.ui._menu.show();game.ui._backdrop.show()
	game.ui.page="";game.ui._history.clear()
	game.ui.settings_tab=0;game.ui.settings_row=0;game.ui.locker_tab=0
	game.ui.locker_focus={"key":"preset","index":0}
	Input.mouse_mode=Input.MOUSE_MODE_VISIBLE
	Input.warp_mouse(Vector2(1279,0))

func _scan(node:Node,rows:Array)->void:
	if node is Control and not node.is_visible_in_tree():return
	if node is Label or node is BaseButton or node is LineEdit:
		var text:String=node.get("text") if node is Label or node is Button or node is LineEdit else ""
		if node is SplatInkButton:text=node.source_label
		if not text.is_empty():
			var rect:Rect2=node.get_global_rect()
			rows.append({"type":node.get_class(),"text":text,"rect":[snappedf(rect.position.x,.01),snappedf(rect.position.y,.01),snappedf(rect.size.x,.01),snappedf(rect.size.y,.01)],"font_size":node.get_theme_font_size("font_size"),"color":node.get_theme_color("font_color").to_html(true),"focused":node.has_focus()})
	for child:Node in node.get_children():_scan(child,rows)

func _write_json(path:String,data:Dictionary)->void:
	var file:FileAccess=FileAccess.open(path,FileAccess.WRITE)
	if file==null:report.failures.append({"file":path,"error":FileAccess.get_open_error()});return
	file.store_string(JSON.stringify(data,"\t"));file.close()
