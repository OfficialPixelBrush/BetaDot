shader_type spatial;

uniform sampler2D tex : filter_nearest, repeat_disable;
uniform vec2 offset;

void vertex() {
	// Called for every vertex the material is visible on.
}

void fragment() {
	ALBEDO = (texture(tex,(UV/8.0))).xyz;
	// Called for every pixel the material is visible on.
}

//void light() {
//	// Called for every pixel for every light affecting the material.
//	// Uncomment to replace the default light processing function with this one.
//}
