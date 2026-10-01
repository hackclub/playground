~func _ready():
~	screen_size = Vector2(DisplayServer.screen_get_size())
~	animated_sprite.play("Walk_Right")
	area.input_event.connect(_on_area_input)
