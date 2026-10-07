// CRT: scanlines, a slightly curved screen and dark corners.
uniform float scanlines; // 0.35 [0, 1]
uniform float curvature; // 0.08 [0, 0.3]
uniform float vignette; // 0.4 [0, 1]

vec4 effect(vec2 uv) {
	vec2 centered = uv * 2.0 - 1.0;
	centered *= 1.0 + curvature * dot(centered, centered) * 0.25;
	vec2 bent = centered * 0.5 + 0.5;
	if (bent.x < 0.0 || bent.x > 1.0 || bent.y < 0.0 || bent.y > 1.0) {
		return vec4(0.0, 0.0, 0.0, 1.0);
	}
	vec3 c = pixel(bent).rgb;
	float line = 0.5 + 0.5 * cos(bent.y * resolution.y * 6.2831853);
	c *= 1.0 - scanlines * (1.0 - line);
	c *= 1.0 - vignette * dot(centered, centered) * 0.5;
	return vec4(c, 1.0);
}
