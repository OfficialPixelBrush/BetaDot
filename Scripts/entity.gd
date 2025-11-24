extends Node3D

var entityId = 0;
var username = "";
var mobId = 0;

func _ready() -> void:
	print("Ready!")

func InitPlayer(eid : int, usr : String):
	entityId = eid;
	username = usr;

func InitMob(eid : int, mob : int):
	entityId = eid;
	mobId = mob;

func BlockPosition(pos: Vector3i):
	self.position = pos;
	print(self.position)
	print(pos)
	
func Position(pos: Vector3i):
	self.position = Vector3(pos)/32.0

func Look(rot: Vector2i):
	self.rotation_degrees.x = (( rot.y / 255.0 ) * 360.0)
	self.rotation_degrees.y = (( rot.x / 255.0 ) * 360.0)
	
func Rotation(rot: Vector3i):
	self.rotation_degrees.x = (( rot.y / 255.0 ) * 360.0)
	self.rotation_degrees.y = (( rot.x / 255.0 ) * 360.0)
	self.rotation_degrees.z = (( rot.z / 255.0 ) * 360.0)

func RelativePosition(off: Vector3i):
	self.position += off / 32.0
