class_name SplatSourceFeedback
extends RefCounted
## Source Menus._bind/_setFocus UI feedback through the existing native source sound pool.
static func attach(button:BaseButton,sound:String="ui_click")->void:
	if button.has_meta("source_feedback"):return
	button.set_meta("source_feedback",true);button.set_meta("source_click_sound",sound);button.set_meta("source_created_at",Time.get_ticks_msec())
	button.focus_entered.connect(func()->void:
		if Time.get_ticks_msec()-int(button.get_meta("source_created_at",0))>300:play(button,"ui_hover",.035))
	button.mouse_entered.connect(func()->void:
		if button.focus_mode!=Control.FOCUS_NONE and not button.has_focus():button.grab_focus())
	button.pressed.connect(func()->void:
		var id:String=str(button.get_meta("source_click_sound","ui_click"))
		if not id.is_empty():play(button,id))

static func play(node:Node,id:String,volume:float=1.0)->void:
	var cursor:Node=node
	while is_instance_valid(cursor):
		if cursor is InkUI:
			var host:InkUI=cursor as InkUI
			if is_instance_valid(host.main) and host.main.get("audio")!=null:host.main.audio.play(id,{"volume":volume})
			return
		cursor=cursor.get_parent()
