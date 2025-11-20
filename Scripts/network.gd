class_name Network

signal connected
signal disconnected
signal error

var _stream: StreamPeerTCP = StreamPeerTCP.new()
var _status: int = StreamPeerTCP.STATUS_NONE
var packet : PackedByteArray;

# --- Basics ---
func ConnectToHost(ip : String, port : int):
	print("Connecting to %s:%d" % [ip, port])
	_stream.connect_to_host(ip, port)

func EnsureConnection():
	_stream.poll()

	var new_status = _stream.get_status()
	if new_status != _status:
		_status = new_status
		match _status:
			StreamPeerTCP.STATUS_NONE:
				print("Disconnected.")
				emit_signal("disconnected")
			StreamPeerTCP.STATUS_CONNECTING:
				print("Connecting…")
			StreamPeerTCP.STATUS_CONNECTED:
				print("Connected.")
				emit_signal("connected")
			StreamPeerTCP.STATUS_ERROR:
				print("Socket error.")
				emit_signal("error")

func SendPacket() -> bool:
	EnsureConnection();
	if (_status != StreamPeerTCP.STATUS_CONNECTED):
		return false;
	_stream.put_data(packet)
	packet.clear()
	return true
	
func WaitForBytes(bytes : int):
	while(_stream.get_available_bytes() < bytes):
		#print(bytes)
		_stream.poll()

func Connected() -> bool:
	return _status == StreamPeerTCP.STATUS_CONNECTED

func Empty() -> bool:
	return _stream.get_available_bytes() <= 0


# --- Write Data ---

func WriteBoolean(v: bool):
	packet.append(v);

func WriteByte(v: int):
	packet.append(v & 0xFF);
	
func WriteShort(v: int):
	packet.append((v >> 8) & 0xFF)
	packet.append(v & 0xFF)

func WriteInteger(v: int):
	for i in range(4):
		packet.append((v >> (24 - i * 8)) & 0xFF)

func WriteLong(v: int):
	for i in range(8):
		packet.append((v >> (56 - i * 8)) & 0xFF)

func WriteFloat(value: float) -> void:
	var buf = StreamPeerBuffer.new()
	buf.put_float(value)
	buf.seek(0)
	var bytes = buf.data_array
	# interpret the float as a 32-bit int
	var val = bytes[0] | (bytes[1] << 8) | (bytes[2] << 16) | (bytes[3] << 24)
	WriteInteger(val)

func WriteDouble(value: float) -> void:
	var buf = StreamPeerBuffer.new()
	buf.put_double(value)
	buf.seek(0)
	var bytes = buf.data_array
	var val = (bytes[7] << 56) | (bytes[6] << 48) | (bytes[5] << 40) | (bytes[4] << 32) | \
			  (bytes[3] << 24) | (bytes[2] << 16) | (bytes[1] << 8) | bytes[0]
	WriteLong(val)

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

# --- Read ---

func ReadBoolean() -> bool:
	return ReadByte() > 0;

func ReadByte() -> int:
	WaitForBytes(1)
	var val = _stream.get_8()
	# convert to signed 8-bit
	if val & 0x80:
		val -= 0x100
	return val

func ReadShort() -> int:
	WaitForBytes(2)
	var val = swap16(_stream.get_16())
	# convert to signed 16-bit
	if val & 0x8000:
		val -= 0x10000
	return val

func ReadInteger() -> int:
	WaitForBytes(4)
	var val = swap32(_stream.get_32())
	# convert to signed 32-bit
	if val & 0x80000000:
		val -= 0x100000000
	return val

func ReadLong() -> int:
	WaitForBytes(8)
	var val = swap64(_stream.get_64())
	# convert to signed 64-bit
	if val & 0x8000000000000000:
		val -= 0x10000000000000000
	return val

func ReadFloat() -> float:
	WaitForBytes(4)
	var val = _stream.get_32()
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

func ReadDouble() -> float:
	WaitForBytes(8)
	var val = _stream.get_64()
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
	
func ReadString8() -> String:
	WaitForBytes(2);
	var stringLength = ReadShort();
	WaitForBytes(stringLength);
	var text : String = "";
	for x in range(stringLength):
		text += char(_stream.get_u8());
	return text

func ReadString16() -> String:
	WaitForBytes(2);
	var stringLength = ReadShort();
	WaitForBytes(stringLength*2);
	var text : String = "";
	for x in range(stringLength):
		_stream.get_8();
		text += char(_stream.get_u8());
	return text

func ReadChunkData(chunkSize : int) -> PackedByteArray:
	WaitForBytes(chunkSize)
	return PackedByteArray(_stream.get_data(chunkSize)[1])


# --- Byte-Endianess Changers ---
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
