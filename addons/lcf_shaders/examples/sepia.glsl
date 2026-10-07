// Sepia: an old photograph.
uniform float amount; // 1.0 [0, 1]

vec4 effect(vec2 uv) {
	vec3 c = pixel(uv).rgb;
	vec3 sepia = vec3(
		dot(c, vec3(0.393, 0.769, 0.189)),
		dot(c, vec3(0.349, 0.686, 0.168)),
		dot(c, vec3(0.272, 0.534, 0.131)));
	return vec4(mix(c, min(sepia, vec3(1.0)), amount), 1.0);
}
