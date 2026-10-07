// Night: darker, bluer and a little desaturated.
uniform float strength; // 0.7 [0, 1]
uniform vec3 tint; // color 0.45, 0.55, 1.0

vec4 effect(vec2 uv) {
	vec3 c = pixel(uv).rgb;
	float gray = dot(c, vec3(0.299, 0.587, 0.114));
	vec3 night = mix(c, vec3(gray), 0.5) * tint * 0.6;
	return vec4(mix(c, night, strength), 1.0);
}
