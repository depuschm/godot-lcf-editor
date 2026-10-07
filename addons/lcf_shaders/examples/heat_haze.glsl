// Heat haze: the picture ripples sideways, e.g. in a desert or near lava.
uniform float amplitude; // 1.5 [0, 6]
uniform float speed; // 2.0 [0, 10]

vec4 effect(vec2 uv) {
	float wave = sin(uv.y * resolution.y * 0.15 + time * speed);
	vec2 shifted = uv + vec2(wave * amplitude / resolution.x, 0.0);
	return pixel(shifted);
}
