extends CanvasLayer

func _ready():
	hide()

func _input(event):
	if event.is_action_pressed("pause"):
		toggle_pause()

func toggle_pause():
	print("Toggle pause called")
	if get_tree().paused:
		resume_game()
	else:
		pause_game()

func pause_game():
	print("Pausing game")
	get_tree().paused = true
	show()
	Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	print("Mouse mode set to VISIBLE")

func resume_game():
	print("Resuming game")
	get_tree().paused = false
	hide()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	print("Mouse mode set to CAPTURED")

func _on_resume_pressed():
	print("Resume button pressed")
	resume_game()

func _on_restart_pressed():
	print("Restart button pressed")
	get_tree().paused = false
	get_tree().reload_current_scene()

func _on_quit_pressed():
	print("Quit button pressed")
	get_tree().quit()