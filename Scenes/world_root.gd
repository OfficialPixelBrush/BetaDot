extends Node3D

var playerEntity = preload("res://Scenes/player_entity.tscn")
@onready var grid_map: GridMap = $GridMap

var entities = {}
var time : int = 0;

func AddEntity(entityId : int):
	var pe = playerEntity.instantiate()
	print("Adding entity:", entityId)
	entities[entityId] = pe
	print("Before adding child:", pe, pe.is_inside_tree())
	add_child(pe)
	print("After adding child:", pe, pe.is_inside_tree())
	print("Entity added:", pe)

func GetEntity(entityId : int):
	if (entities.has(entityId)):
		return entities[entityId]
	return null

func RemoveEntity(entityId : int):
	entities[entityId].queue_free()
	entities.erase(entityId)
	
func UpdateTime(t : int):
	time = t

func PlaceBlock(pos : Vector3i, type : int):
	if (type < 1):
		grid_map.set_cell_item(pos,-1)
	else:
		grid_map.set_cell_item(pos,0)
