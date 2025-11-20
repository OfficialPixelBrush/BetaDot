extends Node

signal connected
signal disconnected
signal error

@onready var player: Node3D = $Player
@onready var camera_3d: Camera3D = $Player/Camera3D
@onready var chat_lines: RichTextLabel = $Control/VBoxContainer/ChatLines

var _stream: StreamPeerTCP = StreamPeerTCP.new()
var _status: int = StreamPeerTCP.STATUS_NONE
var packet : PackedByteArray;

@export var ip: String = "127.0.0.1"
@export var port: int = 25565
@export var username: String = "Player"

enum LoginState {
	OFFLINE = 0,
	HANDSHAKE,
	HANDSHAKE_SENT,
	LOGIN,
	LOGIN_SENT,
	POSITION,
	ONLINE
}

enum Packet {
	KEEP_ALIVE = 0x00,
	LOGIN,
	HANDSHAKE,
	CHAT_MESSAGE,
	TIME,
	ENTITY_EQUIPMENT,
	SPAWN_POINT,
	CLICK_ENTITY,
	SET_HEALTH,
	RESPAWN,
	PLAYER_ON_GROUND,
	PLAYER_POSITION,
	PLAYER_LOOK,
	PLAYER_POSITION_LOOK,
	MINE,
	PLACE = 0x0F,
	HOLDING_CHANGE = 0x10,
	USE_BED,
	PLAYER_ANIMATION,
	ENTITY_ACTION,
	SPAWN_PLAYER_ENTITY,
	SPAWN_ITEM_ENTITY,
	COLLECT_ITEM,
	SPAWN_OBJECT_ENTITY,
	SPAWN_MOB_ENTITY,
	SPAWN_PAINTING = 0x19,
	PLAYER_MOVEMENT = 0x1B,
	ENTITY_VELOCITY,
	DESTROY_ENTITY,
	ENTITY,
	ENTITY_RELATIVE_POSITION = 0x1F,
	ENTITY_LOOK = 0x20,
	ENTITY_RELATIVE_POSITION_LOOK = 0x21,
	ENTITY_POSITION_LOOK = 0x22,
	ENTITY_HEALTH_ACTION = 0x26,
	PRE_CHUNK = 0x32,
	CHUNK = 0x33,
	BLOCK_CHANGE = 0x35,
	WINDOW_ITEMS = 0x68,
	DISCONNET = 0xFF
}

var timer := 0.0
var entityId : int = 0;
var worldSeed : int = 0;
var dimension : int = 0;
var loginState : LoginState = LoginState.OFFLINE;

func SendPacket() -> bool:
	EnsureConnection();
	if (_status != StreamPeerTCP.STATUS_CONNECTED):
		return false;
	_stream.put_data(packet)
	packet.clear()
	return true

func WriteString8(v: String):
	WriteShort(v.length())
	for c in v:
		WriteByte(ord(c))

func WriteString16(v: String):
	# Write UTF-16BE length
	WriteShort(v.length())
	# Write each char, big endian
	for c in v:
		WriteByte(0)
		WriteByte(ord(c))

func WriteLong(v: int):
	for i in range(8):
		packet.append((v >> (56 - i * 8)) & 0xFF)

func WriteInteger(v: int):
	for i in range(4):
		packet.append((v >> (24 - i * 8)) & 0xFF)
	
func WriteShort(v: int):
	packet.append((v >> 8) & 0xFF)
	packet.append(v & 0xFF)

func WriteByte(v: int):
	packet.append(v & 0xFF);

func WriteBoolean(v: bool):
	packet.append(v);

func WriteFloat(value: float) -> void:
	var buf = StreamPeerBuffer.new()
	buf.put_float(value)
	buf.seek(0)
	var bytes = buf.data_array
	var val = (bytes[3] << 24) | (bytes[2] << 16) | (bytes[1] << 8) | bytes[0]
	WriteInteger(val)

func WriteDouble(value: float) -> void:
	var buf = StreamPeerBuffer.new()
	buf.put_double(value)
	buf.seek(0)
	var bytes = buf.data_array
	var val = (bytes[7] << 56) | (bytes[6] << 48) | (bytes[5] << 40) | (bytes[4] << 32) | \
			  (bytes[3] << 24) | (bytes[2] << 16) | (bytes[1] << 8) | bytes[0]
	WriteLong(val)
	
func ReadString8() -> String:
	WaitForBytes(2);
	var stringLength = ReadShort();
	WaitForBytes(stringLength);
	var text : String = "";
	for x in range(stringLength):
		text += char(_stream.get_u8());
	return text
	
func ReadLong() -> int:
	WaitForBytes(8)
	var val = swap64(_stream.get_64())
	# convert to signed 64-bit
	if val & 0x8000000000000000:
		val -= 0x10000000000000000
	return val

func ReadInteger() -> int:
	WaitForBytes(4)
	var val = swap32(_stream.get_32())
	# convert to signed 32-bit
	if val & 0x80000000:
		val -= 0x100000000
	return val

func ReadShort() -> int:
	WaitForBytes(2)
	var val = swap16(_stream.get_16())
	# convert to signed 16-bit
	if val & 0x8000:
		val -= 0x10000
	return val

func ReadByte() -> int:
	WaitForBytes(1)
	var val = _stream.get_8()
	# convert to signed 8-bit
	if val & 0x80:
		val -= 0x100
	return val

func ReadBoolean() -> bool:
	return ReadByte() > 0;
	
func swap64(val: int) -> int:
	return ((val >> 56) & 0xFF) | \
		   ((val >> 40) & 0xFF00) | \
		   ((val >> 24) & 0xFF0000) | \
		   ((val >> 8)  & 0xFF000000) | \
		   ((val << 8)  & 0xFF00000000) | \
		   ((val << 24) & 0xFF0000000000) | \
		   ((val << 40) & 0xFF000000000000) | \
		   ((val << 56) & 0xFF00000000000000)

func swap32(val: int) -> int:
	return ((val >> 24) & 0xFF) | \
	((val >> 8) & 0xFF00) | \
	((val << 8) & 0xFF0000) | \
	((val << 24) & 0xFF000000);

func swap16(val: int) -> int:
	return ((val >> 8) & 0xFF) | ((val << 8) & 0xFF00);

func ReadDouble() -> float:
	WaitForBytes(8)
	var val = swap64(_stream.get_64())
	# reinterpret bits as double
	var bytes = PackedByteArray([
		(val >> 56) & 0xFF,
		(val >> 48) & 0xFF,
		(val >> 40) & 0xFF,
		(val >> 32) & 0xFF,
		(val >> 24) & 0xFF,
		(val >> 16) & 0xFF,
		(val >> 8)  & 0xFF,
		val & 0xFF
	])
	var buf = StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(0)
	return buf.get_double()

func ReadFloat() -> float:
	WaitForBytes(4)
	var val = swap32(_stream.get_32())
	# reinterpret bits as float
	var bytes = PackedByteArray([
		(val >> 24) & 0xFF,
		(val >> 16) & 0xFF,
		(val >> 8)  & 0xFF,
		val & 0xFF
	])
	var buf = StreamPeerBuffer.new()
	buf.data_array = bytes
	buf.seek(0)
	return buf.get_float()

func ReadString16() -> String:
	WaitForBytes(2);
	var stringLength = ReadShort();
	WaitForBytes(stringLength*2);
	var text : String = "";
	for x in range(stringLength):
		_stream.get_8();
		text += char(_stream.get_u8());
	return text
	
var tcp_thread: Thread;

func _ready():
	print("Connecting to %s:%d" % [ip, port])
	_stream.connect_to_host(ip, port)
	loginState = LoginState.HANDSHAKE;
	tcp_thread = Thread.new()
	tcp_thread.start(TcpLoop)
	
func _exit_tree():
	tcp_thread.wait_to_finish()

func EnsureConnection():
	_stream.poll()

	var new_status = _stream.get_status()
	if new_status != _status:
		_status = new_status
		match _status:
			StreamPeerTCP.STATUS_NONE:
				print("Disconnected.")
				emit_signal("disconnected")
				loginState = LoginState.OFFLINE;
			StreamPeerTCP.STATUS_CONNECTING:
				print("Connecting…")
			StreamPeerTCP.STATUS_CONNECTED:
				print("Connected.")
				emit_signal("connected")
			StreamPeerTCP.STATUS_ERROR:
				print("Socket error.")
				emit_signal("error")

func _physics_process(_delta: float) -> void:
	if (loginState != LoginState.ONLINE): return
	WritePositionLook();
	
func TcpLoop():
	while (loginState != LoginState.OFFLINE):
		# Wait
		var start = Time.get_ticks_usec()
		while float(Time.get_ticks_usec() - start) / 1_000_000.0 < 1.0/20.0:
			pass
		
		EnsureConnection();
		if (_status != StreamPeerTCP.STATUS_CONNECTED): continue;
		
		while(_stream.get_available_bytes() > 0):
			var packetId = ReadByte();
			match(packetId):
				Packet.KEEP_ALIVE:
					pass
				Packet.LOGIN: # Login
					print("Got Login")
					entityId = ReadInteger();
					ReadString16()
					worldSeed = ReadLong();
					dimension = ReadByte();
					loginState = LoginState.POSITION
				Packet.HANDSHAKE: # Handshake
					print("Got Handshake")
					ReadString16()
					loginState = LoginState.LOGIN
				Packet.SPAWN_POINT:
					print("Got Spawnpoint")
					print(Vector3i(
						ReadInteger(),
						ReadInteger(),
						ReadInteger()
					))
				Packet.TIME:
					print("Got Time")
					print(ReadLong())
				Packet.WINDOW_ITEMS:
					print("Got Window Items")
					ReadByte()
					var payloadSize = ReadShort()
					for i in range(payloadSize):
						var itemId = ReadShort()
						if (itemId > -1):
							ReadByte()
							ReadShort()
					print(payloadSize)
				Packet.CHAT_MESSAGE:
					var text = ReadString16();
					print(text)
					chat_lines.text = text
				Packet.PLAYER_POSITION_LOOK:
					print("Got Pos Look")
					var pos = Vector3.ZERO;
					var rot = Vector2.ZERO;
					pos.x = ReadDouble()
					pos.y = ReadDouble()
					ReadDouble()
					pos.z = ReadDouble()
					rot.x = ReadFloat()
					rot.y = ReadFloat()
					ReadBoolean()
					print(pos)
					player.global_position = pos
					camera_3d.rotation = Vector3(pos.x,pos.y,0)
					if (loginState == LoginState.POSITION):
						loginState = LoginState.ONLINE
				Packet.PRE_CHUNK:
					#print("Got Pre-Chunk")
					ReadInteger()
					ReadInteger()
					ReadBoolean()
				Packet.CHUNK:
					#print("Got Chunk")
					ReadInteger()
					ReadShort()
					ReadInteger()
					ReadByte()
					ReadByte()
					ReadByte()
					var chunkSize = ReadInteger()
					WaitForBytes(chunkSize)
					_stream.get_data(chunkSize)
				Packet.SPAWN_PLAYER_ENTITY:
					ReadInteger()
					ReadString16()
					ReadInteger()
					ReadInteger()
					ReadInteger()
					ReadByte()
					ReadByte()
					ReadShort()
				Packet.ENTITY_EQUIPMENT:
					ReadInteger()
					ReadShort()
					ReadShort()
					ReadShort()
				Packet.ENTITY_POSITION_LOOK:
					ReadInteger()
					ReadInteger()
					ReadInteger()
					ReadInteger()
					ReadByte()
					ReadByte()
				Packet.DESTROY_ENTITY:
					ReadInteger()
				Packet.ENTITY_RELATIVE_POSITION:
					ReadInteger()
					ReadByte()
					ReadByte()
					ReadByte()
				Packet.ENTITY_LOOK:
					ReadInteger()
					ReadByte()
					ReadByte()
				Packet.ENTITY_RELATIVE_POSITION_LOOK:
					ReadInteger()
					ReadByte()
					ReadByte()
					ReadByte()
					ReadByte()
					ReadByte()
				Packet.DISCONNET:
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

func WaitForBytes(bytes : int):
	while(_stream.get_available_bytes() < bytes):
		print(bytes)
		_stream.poll()

func WriteHandshake():
	WriteByte(Packet.HANDSHAKE)
	WriteString16(username)
	SendPacket()

func WriteLogin():
	WriteByte(Packet.LOGIN)
	WriteInteger(14);
	WriteString16(username);
	WriteLong(0);
	WriteByte(0);
	SendPacket()

func WritePositionLook():
	WriteByte(0x0D)
	WriteDouble(-player.global_position.x)
	WriteDouble(player.global_position.y)
	WriteDouble(1.65)
	WriteDouble(-player.global_position.z)
	WriteFloat(-camera_3d.rotation_degrees.z)
	WriteFloat(-camera_3d.rotation_degrees.x)
	WriteBoolean(1)
	SendPacket()
