extends Control

@onready var sprite: Sprite2D = $Sprite
@onready var queue_label: Label = get_node_or_null("QueueNumberLabel")


@export var tex_down: Texture2D
@export var tex_up: Texture2D
@export var tex_left: Texture2D
@export var tex_right: Texture2D

# After-haircut variants
@export var tex_style_1: Texture2D
@export var tex_style_2: Texture2D
@export var tex_style_3: Texture2D
@export var tex_style_4: Texture2D
@export var tex_style_5: Texture2D
@export var tex_style_6: Texture2D


func _ready() -> void:
	if tex_down:
		sprite.texture = tex_down


func face_direction(dir: Vector2) -> void:
	if dir.length() == 0.0:
		return

	if abs(dir.x) > abs(dir.y):
		# horizontal
		if dir.x > 0.0 and tex_right:
			sprite.texture = tex_right
		elif dir.x < 0.0 and tex_left:
			sprite.texture = tex_left
	else:
		# vertical
		if dir.y > 0.0 and tex_down:
			sprite.texture = tex_down
		elif dir.y < 0.0 and tex_up:
			sprite.texture = tex_up


func apply_random_new_style() -> void:
	var options: Array[Texture2D] = []
	if tex_style_1: options.append(tex_style_1)
	if tex_style_2: options.append(tex_style_2)
	if tex_style_3: options.append(tex_style_3)
	if tex_style_4: options.append(tex_style_4)
	if tex_style_5: options.append(tex_style_5)
	if tex_style_6: options.append(tex_style_6)

	if options.is_empty():
		return

	var idx := randi() % options.size()
	sprite.texture = options[idx]


func set_queue_number(n: int) -> void:
	if queue_label:
		queue_label.text = str(n)
