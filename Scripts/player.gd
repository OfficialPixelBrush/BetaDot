extends CharacterBody3D

const SPEED = 2.0
const SENS = 0.002

@onready var cam: Camera3D = $Camera3D

func _ready():
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)

func _input(event):
	if event is InputEventMouseMotion:
		rotation.y -= event.relative.x * SENS
		cam.rotation.x -= event.relative.y * SENS
		cam.rotation.x = clamp(cam.rotation.x, deg_to_rad(-89), deg_to_rad(89))

func _physics_process(delta):
	if Input.is_action_pressed("ui_cancel"):
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
	
	if not is_on_floor():
		velocity += get_gravity() * delta		

	var input_dir := Input.get_vector("Strafe Left", "Strafe Right", "Backward", "Forward")
	var dir = Vector3.ZERO

	var forward = -transform.basis.z
	var right = transform.basis.x

	dir += forward * input_dir.y
	dir += right * input_dir.x
	dir = dir.normalized()

	if dir != Vector3.ZERO:
		velocity.x = dir.x * SPEED
		velocity.z = dir.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	move_and_slide()
