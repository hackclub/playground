~	if window_position.x <= 0 or window_position.x >= screen_size.x - window_size.x:
~		direction.x *= -1
		animated_sprite.flip_h = !animated_sprite.flip_h
