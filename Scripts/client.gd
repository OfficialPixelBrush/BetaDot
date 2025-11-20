extends Node

@onready var player: Node3D = $Player
@onready var camera_3d: Camera3D = $Player/Camera3D
@onready var chat_lines: RichTextLabel = $Control/VBoxContainer/ChatLines

@onready var root = get_tree().current_scene

@export var ip: String = "127.0.0.1"
@export var port: int = 25565
@export var username: String = "Player"

@onready var net = preload("res://Scripts/network.gd").new()

enum LoginState {
	OFFLINE = 0,
	HANDSHAKE,
	HANDSHAKE_SENT,
	LOGIN,
	LOGIN_SENT,
	POSITION,
	ONLINE
}

var timer := 0.0
var entityId : int = 0;
var worldSeed : int = 0;
var dimension : int = 0;
var loginState : LoginState = LoginState.OFFLINE;

func _ready():
	net.ConnectToHost(ip,port)
	loginState = LoginState.HANDSHAKE;

func _physics_process(_delta: float) -> void:
	HandlePackets()
	if (loginState != LoginState.ONLINE): return
	WritePositionLook();
	
func HandlePackets():	
	net.EnsureConnection();
	if (!net.Connected()): return;
	
	while(!net.Empty()):
		var packetId = net.ReadByte();
		match(packetId):
			Enum.Packet.KEEP_ALIVE:
				pass
			Enum.Packet.LOGIN: # Login
				print("Got Login")
				entityId = net.ReadInteger();
				net.ReadString16()
				worldSeed = net.ReadLong();
				dimension = net.ReadByte();
				loginState = LoginState.POSITION
			Enum.Packet.HANDSHAKE: # Handshake
				print("Got Handshake")
				net.ReadString16()
				loginState = LoginState.LOGIN
			Enum.Packet.SPAWN_POINT:
				print("Got Spawnpoint")
				player.spawn = Vector3i(
					net.ReadInteger(),
					net.ReadInteger(),
					net.ReadInteger()
				)
				print(player.spawn)
			Enum.Packet.TIME:
				root.UpdateTime(net.ReadLong())
			Enum.Packet.WINDOW_ITEMS:
				print("Got Window Items")
				net.ReadByte()
				var payloadSize = net.ReadShort()
				for i in range(payloadSize):
					var itemId = net.ReadShort()
					if (itemId > -1):
						net.ReadByte()
						net.ReadShort()
				print(payloadSize)
			Enum.Packet.CHAT_MESSAGE:
				var text = net.ReadString16();
				print(text)
				chat_lines.text = text
			Enum.Packet.PLAYER_POSITION_LOOK:
				print("Got Pos Look")
				var pos = Vector3.ZERO;
				var rot = Vector2.ZERO;
				pos.x = net.ReadDouble()
				pos.y = net.ReadDouble()
				net.ReadDouble()
				pos.z = net.ReadDouble()
				rot.x = net.ReadFloat()
				rot.y = net.ReadFloat()
				net.ReadBoolean()
				player.global_position = pos
				print(rot)
				camera_3d.global_rotation_degrees.x = -rot.y
				player.global_rotation_degrees.y = -rot.x
				if (loginState == LoginState.POSITION):
					loginState = LoginState.ONLINE
			Enum.Packet.PRE_CHUNK:
				#print("Got Pre-Chunk")
				net.ReadInteger()
				net.ReadInteger()
				net.ReadBoolean()
			Enum.Packet.CHUNK:
				#print("Got Chunk")
				var pos = Vector3i(net.ReadInteger(),net.ReadShort(),net.ReadInteger())
				var areaSize = Vector3i(net.ReadByte()+1,net.ReadByte()+1,net.ReadByte()+1)
				var chunkData = net.ReadChunkData(net.ReadInteger())
				DecompressChunk(pos,areaSize,chunkData)
			Enum.Packet.SPAWN_PLAYER_ENTITY:
				print("Spawn Player")
				var eid = net.ReadInteger()
				root.AddEntity(eid)
				# Get info
				var e = root.GetEntity(eid)
				e.Init(eid,net.ReadString16());
				e.BlockPosition(Vector3i(net.ReadInteger(),net.ReadInteger(),net.ReadInteger()))
				e.Look(Vector2i(net.ReadByte(),net.ReadByte()))
				net.ReadShort()
			Enum.Packet.ENTITY_EQUIPMENT:
				net.ReadInteger()
				net.ReadShort()
				net.ReadShort()
				net.ReadShort()
			Enum.Packet.ENTITY_POSITION_LOOK:
				var e = root.GetEntity(net.ReadInteger())
				e.Position(Vector3i(net.ReadInteger(),net.ReadInteger(),net.ReadInteger()))
				e.Look(Vector2i(net.ReadByte(),net.ReadByte()))
			Enum.Packet.DESTROY_ENTITY:
				root.RemoveEntity(net.ReadInteger())
			Enum.Packet.ENTITY_RELATIVE_POSITION:
				var e = root.GetEntity(net.ReadInteger())
				e.RelativePosition(Vector3i(net.ReadInteger(),net.ReadInteger(),net.ReadInteger()))
			Enum.Packet.ENTITY_LOOK:
				var e = root.GetEntity(net.ReadInteger())
				e.Look(Vector2i(net.ReadByte(),net.ReadByte()))
			Enum.Packet.ENTITY_RELATIVE_POSITION_LOOK:
				var e = root.GetEntity(net.ReadInteger())
				e.RelativePosition(Vector3i(net.ReadInteger(),net.ReadInteger(),net.ReadInteger()))
				e.Look(Vector2i(net.ReadByte(),net.ReadByte()))
			Enum.Packet.BLOCK_CHANGE:
				var pos = Vector3i(net.ReadInteger(),net.ReadByte(),net.ReadInteger())
				print(pos)
				root.PlaceBlock(pos,net.ReadByte())
				net.ReadByte()
			Enum.Packet.PLAYER_ANIMATION:
				net.ReadInteger()
				net.ReadByte()
			Enum.Packet.EFFECT:
				net.ReadInteger()
				var _pos = Vector3i(net.ReadInteger(),net.ReadByte(),net.ReadInteger())
				net.ReadInteger()
			Enum.Packet.ENTITY_METADATA:
				net.ReadInteger()
				var value = net.ReadByte();
				while (value != 127):
					value = net.ReadByte();
					print(value)
			Enum.Packet.DISCONNET:
				print("Disconnected by Server!")
				loginState = LoginState.OFFLINE
			_:
				print("Unknown! (0x%X)" % packetId)

	match(loginState):
		LoginState.HANDSHAKE:
			WriteHandshake()
			loginState = LoginState.HANDSHAKE_SENT
		LoginState.LOGIN:
			WriteLogin()
			loginState = LoginState.LOGIN_SENT

func WriteHandshake():
	net.WriteByte(Enum.Packet.HANDSHAKE)
	net.WriteString16(username)
	net.SendPacket()

func WriteLogin():
	net.WriteByte(Enum.Packet.LOGIN)
	net.WriteInteger(14);
	net.WriteString16(username);
	net.WriteLong(0);
	net.WriteByte(0);
	net.SendPacket()

func WritePositionLook():
	net.WriteByte(0x0D)
	net.WriteDouble(player.global_position.x)
	net.WriteDouble(player.global_position.y)
	net.WriteDouble(1.65)
	net.WriteDouble(player.global_position.z)
	net.WriteFloat(180.0-player.global_rotation_degrees.y)
	net.WriteFloat(-camera_3d.global_rotation_degrees.x)
	net.WriteBoolean(1)
	net.SendPacket()

func PosToIndex(pos : Vector3i) -> int:
	return pos.y + (pos.z*128) + (pos.x*16*128)

func DecompressChunk(pos: Vector3i, size: Vector3i, data: PackedByteArray):
	var expected_size = int((size.x * size.y * size.z) * 2.5)  # example if each block is 2 bytes
	var decompressed = data.decompress_dynamic(expected_size, FileAccess.COMPRESSION_DEFLATE)
	for x in range(size.x):
		for z in range(size.z):
			for y in range(size.y):
				var off = Vector3i(x,y,z);
				var flipped_off = Vector3i(x, y, z)
				root.PlaceBlock(pos+flipped_off, decompressed[PosToIndex(off)])
