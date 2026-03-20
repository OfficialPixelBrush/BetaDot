extends Node3D

enum EntityType {
	None,
	Mob,
	Item,
	Obj,
	Player,
}

var entityId = 0;
var username = "";
var entityType : EntityType = EntityType.None
var typeId = 0;

func InitPlayer(eid : int, usr : String):
	entityType = EntityType.Player
	entityId = eid;
	username = usr;

func InitObject(eid : int, tid : int):
	entityType = EntityType.Obj
	entityId = eid;
	typeId = tid;

func InitMob(eid : int, tid : int):
	entityType = EntityType.Mob
	entityId = eid;
	typeId = tid;

func InitItem(eid : int, itemId : int):
	entityType = EntityType.Item
	entityId = eid;
	typeId = itemId;

func BlockPosition(pos: Vector3i):
	self.position = pos;
	#print(self.position)
	#print(pos)
	
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
	self.position += Vector3(off)/32.0
