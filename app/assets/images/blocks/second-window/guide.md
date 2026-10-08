# Let's give your pet a second window!

Pets are more fun when they can drop things! In Godot, an extra window is a `Window` node.

![A pet on a Windows desktop. The cursor picks it up and drops it, and a heart appears at its feet in a window of its own. The pet walks away and the heart stays where it is.](images/result.gif)

I made mine drop a heart every time you drop it, and the heart stays put while the pet walks away, but what your pet does with its second window is up to you.

## Add a Window

In the Scene panel (top left), click + to add a new node.

type Window into the search bar, select it, and click Create.

![The Create New Node window, with Window typed in the search box and Window picked in the list.](images/1-add-the-node.png)

anything you want inside the window goes under it in the Scene panel, like a Sprite2D for a picture.

## Let it leave your pet’s window

Right now a Window is drawn inside the window it’s in, so anything past your pet’s 200 pixel edge gets cut off. to change that we need to adjust the project’s settings.

Click Project > Project Settings…

search for Embed Subwindows, it’s under Display > Window, and turn it off.

![Project Settings searched for embed, with Display, Window selected and Embed Subwindows off.](images/2-embed-subwindows.png)

## Size and position

select your Window, and set Size in the inspector on the right. Position is where it sits on your screen, in pixels, counting from the top left corner. Now that we turned Embed Subwindows off it’s a spot on the screen, not a spot in your pet’s window.

![The Inspector for Window, with Position and Size highlighted.](images/3-size-and-position.png)

you can set it from code too, run

```gdscript
$Window.position = Vector2i(400, 300)
```

## No border, no background

open Flags in the inspector, and turn on Borderless and Transparent.

![The Flags section of the Inspector for Window, with Visible, Borderless and Transparent highlighted. Borderless and Transparent are on.](images/4-flags.png)

then scroll down to Viewport and turn on Transparent BG too.

![The Viewport part of the Inspector for Window, with Transparent BG highlighted and on.](images/5-transparent-bg.png)

Transparent only works because your pet’s project already has Per Pixel Transparency on, you turned it on when you made the pet see through.

## Show it

a Window starts out visible. If you don’t want it yet, turn off Visible, it’s at the top of Flags, then whenever you want it to appear, run

```gdscript
$Window.show()
```

and `hide()` makes it go away again.

That’s it!

## Want more?

You can change the title, keep the window on top of everything, stop it from taking focus, let clicks pass through it, and a lot more. It’s all in the [Window docs](https://docs.godotengine.org/en/stable/classes/class_window.html).
