extends RigidBody2D

@export var engine_power = 500
@export var spin_power = 8000

@export var bullet_scene : PackedScene
@export var fire_rate = 0.25

@export var max_shield = 100.0
@export var shield_regen = 5.0

signal lives_changed
signal dead
signal shield_changed

var reset_pos = false
var lives = 0: set = set_lives

var can_shoot = true

var thrust = Vector2.ZERO
var rotation_dir = 0

enum {INIT, ALIVE, INVULNERABLE, DEAD}
var state = INIT

var shield = 0: set = set_shield

var screensize = Vector2.ZERO

# Called when the node enters the scene tree for the first time.
func _ready() -> void:
	change_state(ALIVE)
	screensize = get_viewport_rect().size
	$GunCooldown.wait_time = fire_rate

# Called every frame. 'delta' is the elapsed time since the previous frame.
func _process(delta: float) -> void:
	get_input()
	shield += shield_regen * delta

func _physics_process(delta: float) -> void:
	constant_force = thrust
	constant_torque = rotation_dir * spin_power

func _integrate_forces(physics_state: PhysicsDirectBodyState2D) -> void:
	var xform = physics_state.transform
	xform.origin.x = wrapf(xform.origin.x, 0, screensize.x)
	xform.origin.y = wrapf(xform.origin.y, 0, screensize.y)
	physics_state.transform = xform
	
	if reset_pos:
		physics_state.transform.origin = screensize/2
		reset_pos = false

# ----------------------------------------------------------------------------
func change_state(new_state : int) -> void:
	match new_state:
		INIT:
			$CollisionShape2D.set_deferred("disabled", true)
			$Sprite2D.modulate.a = 0.5
		ALIVE:
			$CollisionShape2D.set_deferred("disabled", false)
			$Sprite2D.modulate.a = 1.0
		INVULNERABLE:
			$CollisionShape2D.set_deferred("disabled", true)
			$Sprite2D.modulate.a = 0.5
			$Explosion/InvulnerabilityTimer.start()
		DEAD:
			$CollisionShape2D.set_deferred("disabled", true)
			$Sprite2D.hide()
			$EngineSound.stop()
			linear_velocity = Vector2.ZERO
			dead.emit()
	state = new_state

func get_input() -> void:
	$Exhaust.emitting = false
	thrust = Vector2.ZERO
	if state in [DEAD, INIT]:
		return
	if Input.is_action_pressed("thrust"):
		thrust = transform.x * engine_power
		if not $EngineSound.playing:
			$EngineSound.play()
		$Exhaust.emitting = true
	else:
		$EngineSound.stop()
	rotation_dir = Input.get_axis("rotate_left", "rotate_right")
	if Input.is_action_pressed("shoot") and can_shoot:
		shoot()

func shoot() -> void:
	if state == INVULNERABLE:
		return
	can_shoot = false
	$GunCooldown.start()
	var b = bullet_scene.instantiate()
	get_tree().root.add_child(b)
	b.start($Muzzle.global_transform)
	$LaserSound.play()


func _on_gun_cooldown_timeout() -> void:
	can_shoot = true

func set_lives(value : int) -> void:
	lives = value
	lives_changed.emit(lives)
	if lives <= 0:
		change_state(DEAD)
	else:
		change_state(INVULNERABLE)
		shield = max_shield


func reset() -> void:
	reset_pos = true
	$Sprite2D.show()
	lives = 3
	change_state(ALIVE)


func _on_invulnerability_timer_timeout() -> void:
	change_state(ALIVE)


func _on_body_entered(body: Node) -> void:
	if body.is_in_group("rocks"):
		shield -= body.size * 25
		body.explode()

func explode() -> void:
	$Explosion.show()
	$Explosion/AnimationPlayer.play("explosion")
	await $Explosion/AnimationPlayer.animation_finished
	$Explosion.hide()

func set_shield(value : int) -> void:
	value = min(value, max_shield)
	shield = value
	shield_changed.emit(shield / max_shield)
	if shield <= 0:
		lives -= 1
		explode()
