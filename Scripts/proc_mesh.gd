extends MeshInstance3D

signal chunk_built

var array_mesh: ArrayMesh

enum Face {
	UP,DOWN,LEFT,RIGHT,FORWARD,BACK
}

const _light_lut : Array[float] = [ 0.035, 0.044, 0.055, 0.069, 0.086, 0.107, 0.134, 0.168, 0.21, 0.262, 0.328, 0.41, 0.512, 0.64, 0.8, 1.0 ]

var _static_body: StaticBody3D
var _chunk_state : Enum.ChunkState = Enum.ChunkState.UNLOADED
var _thread: Thread

func set_chunk_state(new_state : Enum.ChunkState) -> void:
	_chunk_state = new_state
	
func get_chunk_state() -> Enum.ChunkState:
	return _chunk_state

func generate_chunk_async(size: Vector3i, data: PackedByteArray) -> void:
	if _thread and _thread.is_alive():
		_thread.wait_to_finish()
	_thread = Thread.new()
	_thread.start(_build_mesh.bind(size, data))

func _build_mesh(size: Vector3i, data: PackedByteArray) -> void:
	print("Building mesh!")
	# Do NOT touch the scene tree here — no add_child, no node creation
	set_chunk_state(Enum.ChunkState.BUILDING_MESH)

	# --- Pass 1: count visible faces ---
	var face_count := 0
	for x in range(size.x):
		for z in range(size.z):
			for y in range(size.y):
				var off := Vector3i(x, y, z)
				if _get_block(off, size, data) == 0:
					continue
				if _get_block(off + Vector3i( 0, 1, 0), size, data) == 0: face_count += 1
				if _get_block(off + Vector3i( 0,-1, 0), size, data) == 0: face_count += 1
				if _get_block(off + Vector3i(-1, 0, 0), size, data) == 0: face_count += 1
				if _get_block(off + Vector3i( 1, 0, 0), size, data) == 0: face_count += 1
				if _get_block(off + Vector3i( 0, 0,-1), size, data) == 0: face_count += 1
				if _get_block(off + Vector3i( 0, 0, 1), size, data) == 0: face_count += 1

	# --- Pre-allocate arrays ---
	var verts  := PackedVector3Array(); verts.resize(face_count * 4)
	var norms  := PackedVector3Array(); norms.resize(face_count * 4)
	var uvs    := PackedVector2Array(); uvs.resize(face_count * 4)
	var inds   := PackedInt32Array();   inds.resize(face_count * 6)
	var cols   := PackedColorArray(); cols.resize(face_count * 4)

	# --- Pass 2: fill arrays ---
	var face_idx := 0
	for x in range(size.x):
		for z in range(size.z):
			for y in range(size.y):
				var off := Vector3i(x, y, z)
				var block = _get_block(off, size, data)
				if block == 0:
					continue
				var ox := float(off.x)
				var oy := float(off.y)
				var oz := float(off.z)
				var textures : Array[Enum.Textures] = _get_block_textures(block)
				var lights = [0,0]
				if _get_block(off + Vector3i( 0, 1, 0), size, data) == 0:
					lights = _get_light(off + Vector3i( 0, 1, 0), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.UP, textures[0])
				if _get_block(off + Vector3i( 0,-1, 0), size, data) == 0:
					lights = _get_light(off + Vector3i( 0, -1, 0), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.DOWN, textures[1])
				if _get_block(off + Vector3i(-1, 0, 0), size, data) == 0:
					lights = _get_light(off + Vector3i(-1, 0, 0), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.LEFT, textures[2])
				if _get_block(off + Vector3i( 1, 0, 0), size, data) == 0:
					lights = _get_light(off + Vector3i( 1, 0, 0), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.RIGHT, textures[3])
				if _get_block(off + Vector3i( 0, 0,-1), size, data) == 0:
					lights = _get_light(off + Vector3i( 0, 0,-1), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.FORWARD, textures[4])
				if _get_block(off + Vector3i( 0, 0, 1), size, data) == 0:
					lights = _get_light(off + Vector3i( 0, 0, 1), size, data)
					face_idx = _write_quad(verts, norms, uvs, inds, cols, face_idx, ox, oy, oz, lights, Face.BACK, textures[5])

	# --- Build trimesh shape HERE on the worker thread (expensive) ---
	var shape: Shape3D = null
	if face_count > 0:
		var temp_mesh := ArrayMesh.new()
		var surface_array: Array = []
		surface_array.resize(Mesh.ARRAY_MAX)
		surface_array[Mesh.ARRAY_VERTEX] = verts
		surface_array[Mesh.ARRAY_NORMAL] = norms
		surface_array[Mesh.ARRAY_TEX_UV] = uvs
		surface_array[Mesh.ARRAY_INDEX]  = inds
		surface_array[Mesh.ARRAY_COLOR]  = cols
		temp_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
		print("Generating collision...")
		shape = temp_mesh.create_trimesh_shape()

	var built := [verts, norms, uvs, inds, cols, shape]
	print("Built mesh!")
	call_deferred("_apply_mesh", built)

func _all_sides(texture: Enum.Textures) -> Array[Enum.Textures]:
	return [
		texture,
		texture,
		texture,
		texture,
		texture,
		texture
	]

func _get_block_textures(block : int) -> Array[Enum.Textures]:
	match(block):
		1:
			return _all_sides(Enum.Textures.STONE)
		2:
			return [
				Enum.Textures.GRASS_TOP,
				Enum.Textures.DIRT,
				Enum.Textures.GRASS_SIDE,
				Enum.Textures.GRASS_SIDE,
				Enum.Textures.GRASS_SIDE,
				Enum.Textures.GRASS_SIDE,
			]
		3:
			return _all_sides(Enum.Textures.DIRT)
		4:
			return _all_sides(Enum.Textures.COBBLESTONE)
		5:
			return _all_sides(Enum.Textures.PLANKS)
		7:
			return _all_sides(Enum.Textures.BEDROCK)
		8:
			return _all_sides(Enum.Textures.WATER)
		9:
			return _all_sides(Enum.Textures.WATER)
		10:
			return _all_sides(Enum.Textures.LAVA)
		11:
			return _all_sides(Enum.Textures.LAVA)
		12:
			return _all_sides(Enum.Textures.SAND)
		13:
			return _all_sides(Enum.Textures.GRAVEL)
		14:
			return _all_sides(Enum.Textures.GOLD_ORE)
		15:
			return _all_sides(Enum.Textures.IRON_ORE)
		16:
			return _all_sides(Enum.Textures.COAL_ORE)
		17:
			return [
				Enum.Textures.LOG_TOP,
				Enum.Textures.LOG_TOP,
				Enum.Textures.OAK_LOG_SIDE,
				Enum.Textures.OAK_LOG_SIDE,
				Enum.Textures.OAK_LOG_SIDE,
				Enum.Textures.OAK_LOG_SIDE,
			]
		18:
			return _all_sides(Enum.Textures.OAK_LEAVES_FAST)
		19:
			return _all_sides(Enum.Textures.SPONGE)
		20:
			return _all_sides(Enum.Textures.GLASS)
		31:
			return _all_sides(Enum.Textures.TALLGRASS)
		37:
			return _all_sides(Enum.Textures.DANDELION)
		38:
			return _all_sides(Enum.Textures.ROSE)
		39:
			return _all_sides(Enum.Textures.BROWN_MUSHROOM)
		40:
			return _all_sides(Enum.Textures.RED_MUSHROOM)
		41:
			return _all_sides(Enum.Textures.GOLD_BLOCK)
		42:
			return _all_sides(Enum.Textures.IRON_BLOCK)
		43:
			return [
				Enum.Textures.STONE_SLAB_TOP,
				Enum.Textures.STONE_SLAB_TOP,
				Enum.Textures.STONE_SLAB_SIDE,
				Enum.Textures.STONE_SLAB_SIDE,
				Enum.Textures.STONE_SLAB_SIDE,
				Enum.Textures.STONE_SLAB_SIDE,
			]
		45:
			return _all_sides(Enum.Textures.BRICKS)
		46:
			return [
				Enum.Textures.TNT_TOP,
				Enum.Textures.TNT_BOTTOM,
				Enum.Textures.TNT_SIDE,
				Enum.Textures.TNT_SIDE,
				Enum.Textures.TNT_SIDE,
				Enum.Textures.TNT_SIDE,
			]
		47:
			return [
				Enum.Textures.PLANKS,
				Enum.Textures.PLANKS,
				Enum.Textures.BOOKSHELF,
				Enum.Textures.BOOKSHELF,
				Enum.Textures.BOOKSHELF,
				Enum.Textures.BOOKSHELF,
			]
		48:
			return _all_sides(Enum.Textures.MOSSY_COBBLESTONE)
		49:
			return _all_sides(Enum.Textures.OBSIDIAN)
		50:
			return _all_sides(Enum.Textures.TORCH)
		52:
			return _all_sides(Enum.Textures.MOB_SPAWNER)
		83:
			return _all_sides(Enum.Textures.SUGARCANE)
	return [
		Enum.Textures.CRAFTING_TABLE_TOP,
		Enum.Textures.PLANKS,
		Enum.Textures.CRAFTING_TABLE_SIDE,
		Enum.Textures.CRAFTING_TABLE_SIDE,
		Enum.Textures.CRAFTING_TABLE_FRONT,
		Enum.Textures.CRAFTING_TABLE_FRONT
	]

func _apply_mesh(built: Array) -> void:
	print("Applying mesh...")
	# Runs on the main thread — scene tree modifications are safe here
	if !array_mesh:
		array_mesh = ArrayMesh.new()
		mesh = array_mesh
	array_mesh.clear_surfaces()
	var surface_array: Array = []
	surface_array.resize(Mesh.ARRAY_MAX)
	surface_array[Mesh.ARRAY_VERTEX] = built[0]
	surface_array[Mesh.ARRAY_NORMAL] = built[1]
	surface_array[Mesh.ARRAY_TEX_UV] = built[2]
	surface_array[Mesh.ARRAY_INDEX]  = built[3]
	surface_array[Mesh.ARRAY_COLOR]  = built[4]
	array_mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, surface_array)
	array_mesh.surface_set_material(0, preload("res://Shaders/default_block.tres"))
	print("Applied mesh!")

	# Shape was already built on the worker thread — just assign it here (cheap)
	var shape: Shape3D = built[5]
	_apply_collision(shape)
	print("Chunk is ready!")

func _apply_collision(shape: Shape3D) -> void:
	set_chunk_state(Enum.ChunkState.BUILDING_COLLISION)

	if _static_body:
		_static_body.queue_free()
		_static_body = null

	if shape == null:
		set_chunk_state(Enum.ChunkState.READY)
		return

	_static_body = StaticBody3D.new()
	var col := CollisionShape3D.new()
	col.shape = shape
	_static_body.add_child(col)
	add_child(_static_body)
	set_chunk_state(Enum.ChunkState.READY)
	chunk_built.emit()

func ValueToColor(value : float) -> Color:
	return Color(value,value,value,1.0)

func _write_quad(
		verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array,   inds: PackedInt32Array,
		cols: PackedColorArray,
		face_idx: int, ox: float, oy: float, oz: float,
		lights: Array[int],
		face: Face,
		texture: Enum.Textures) -> int:

	const texScale := 1.0 / 16.0
	var texX := float(texture % 16) * texScale
	@warning_ignore("integer_division")
	var texY := float(texture / 16) * texScale
	var vi   := face_idx * 4
	var ii   := face_idx * 6
	var face_shade = 1.0

	match face:
		Face.UP:
			verts[vi+0] = Vector3(ox+0.0, oy+0.5, oz+1.0)
			verts[vi+1] = Vector3(ox+1.0, oy+0.5, oz+1.0)
			verts[vi+2] = Vector3(ox+1.0, oy+0.5, oz+0.0)
			verts[vi+3] = Vector3(ox+0.0, oy+0.5, oz+0.0)
			norms[vi+0] = Vector3.UP; norms[vi+1] = Vector3.UP
			norms[vi+2] = Vector3.UP; norms[vi+3] = Vector3.UP
			face_shade = 1.0
		Face.DOWN:
			verts[vi+0] = Vector3(ox+0.0, oy-0.5, oz+0.0)
			verts[vi+1] = Vector3(ox+1.0, oy-0.5, oz+0.0)
			verts[vi+2] = Vector3(ox+1.0, oy-0.5, oz+1.0)
			verts[vi+3] = Vector3(ox+0.0, oy-0.5, oz+1.0)
			norms[vi+0] = Vector3.DOWN; norms[vi+1] = Vector3.DOWN
			norms[vi+2] = Vector3.DOWN; norms[vi+3] = Vector3.DOWN
			face_shade = 0.5
		Face.LEFT:
			verts[vi+0] = Vector3(ox+0.0, oy+0.5, oz+0.0)
			verts[vi+1] = Vector3(ox+0.0, oy-0.5, oz+0.0)
			verts[vi+2] = Vector3(ox+0.0, oy-0.5, oz+1.0)
			verts[vi+3] = Vector3(ox+0.0, oy+0.5, oz+1.0)
			norms[vi+0] = Vector3.LEFT; norms[vi+1] = Vector3.LEFT
			norms[vi+2] = Vector3.LEFT; norms[vi+3] = Vector3.LEFT
			face_shade = 0.6
		Face.RIGHT:
			verts[vi+0] = Vector3(ox+1.0, oy+0.5, oz+1.0)
			verts[vi+1] = Vector3(ox+1.0, oy-0.5, oz+1.0)
			verts[vi+2] = Vector3(ox+1.0, oy-0.5, oz+0.0)
			verts[vi+3] = Vector3(ox+1.0, oy+0.5, oz+0.0)
			norms[vi+0] = Vector3.RIGHT; norms[vi+1] = Vector3.RIGHT
			norms[vi+2] = Vector3.RIGHT; norms[vi+3] = Vector3.RIGHT
			face_shade = 0.6
		Face.FORWARD:
			verts[vi+0] = Vector3(ox+1.0, oy+0.5, oz+0.0)
			verts[vi+1] = Vector3(ox+1.0, oy-0.5, oz+0.0)
			verts[vi+2] = Vector3(ox+0.0, oy-0.5, oz+0.0)
			verts[vi+3] = Vector3(ox+0.0, oy+0.5, oz+0.0)
			norms[vi+0] = Vector3.FORWARD; norms[vi+1] = Vector3.FORWARD
			norms[vi+2] = Vector3.FORWARD; norms[vi+3] = Vector3.FORWARD
			face_shade = 0.8
		Face.BACK:
			verts[vi+0] = Vector3(ox+0.0, oy+0.5, oz+1.0)
			verts[vi+1] = Vector3(ox+0.0, oy-0.5, oz+1.0)
			verts[vi+2] = Vector3(ox+1.0, oy-0.5, oz+1.0)
			verts[vi+3] = Vector3(ox+1.0, oy+0.5, oz+1.0)
			norms[vi+0] = Vector3.BACK; norms[vi+1] = Vector3.BACK
			norms[vi+2] = Vector3.BACK; norms[vi+3] = Vector3.BACK
			face_shade = 0.8
	#if (lights[0] > lights[1]):
	#	face_shade *= _light_lut[lights[0]]
	#else:
	#	face_shade *= _light_lut[lights[1]]
	cols[vi+0] = ValueToColor(face_shade)
	if (_is_colored(texture)):
		cols[vi+0] *= _biome_color()
	cols[vi+1] = cols[vi+0]
	cols[vi+2] = cols[vi+0]
	cols[vi+3] = cols[vi+0]
	
	uvs[vi+0] = Vector2(texX+texScale, texY)
	uvs[vi+1] = Vector2(texX+texScale, texY+texScale)
	uvs[vi+2] = Vector2(texX,          texY+texScale)
	uvs[vi+3] = Vector2(texX,          texY)

	inds[ii+0] = vi+0; inds[ii+1] = vi+2; inds[ii+2] = vi+1
	inds[ii+3] = vi+0; inds[ii+4] = vi+3; inds[ii+5] = vi+2

	return face_idx + 1

func _is_colored(texture_id : Enum.Textures):
	return (
		texture_id == Enum.Textures.GRASS_TOP or\
		texture_id == Enum.Textures.OAK_LEAVES or\
		texture_id == Enum.Textures.OAK_LEAVES_FAST or\
		texture_id == Enum.Textures.GRASS_SIDE_COLOR or\
		texture_id == Enum.Textures.GRASS_TOP_COLOR or\
		texture_id == Enum.Textures.TALLGRASS or\
		texture_id == Enum.Textures.FERN
	)

func _biome_color() -> Color:
	return Color("#4EBA31")

func _get_light(pos: Vector3i, size: Vector3i, data: PackedByteArray) -> Array[int]:
	if pos.x < 0 or pos.x >= size.x: return [0,0]
	if pos.y < 0 or pos.y >= size.y: return [0,0]
	if pos.z < 0 or pos.z >= size.z: return [0,0]
	
	var base_size = size.x * size.y * size.z
	@warning_ignore("integer_division")
	var block_light = base_size + base_size/2
	var sky_light = base_size + base_size
	
	var index = pos.y + (pos.z * size.y) + (pos.x * size.z * size.y)
	if index < 0 or index >= data.size(): return [0,0]  # safety net
	@warning_ignore("integer_division")
	var byte_index = index / 2
	if (index % 2 == 0):
		return [ data[block_light + byte_index] & 0x0F,
				 data[sky_light   + byte_index] & 0x0F ]
	else:
		return [ (data[block_light + byte_index] & 0xF0) >> 4,
				 (data[sky_light   + byte_index] & 0xF0) >> 4 ]

func _get_block(pos: Vector3i, size: Vector3i, data: PackedByteArray) -> int:
	if pos.x < 0 or pos.x >= size.x: return 0
	if pos.y < 0 or pos.y >= size.y: return 0
	if pos.z < 0 or pos.z >= size.z: return 0
	var index = pos.y + (pos.z * size.y) + (pos.x * size.z * size.y)
	if index < 0 or index >= data.size(): return 0  # safety net
	return data[index]
