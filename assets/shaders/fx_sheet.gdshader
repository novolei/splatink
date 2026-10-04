shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
// Port of fx.js SHELL_FRAG: stretched wet sheets tear into holes and ribbons over 0.2–0.34 s.
uniform vec3 sun_direction = vec3(-0.5, 0.8, 0.3);
uniform vec3 sky_color : source_color = vec3(0.62, 0.76, 0.97);
uniform vec3 sun_color : source_color = vec3(1.0);
varying vec4 ink;
varying vec4 state;
varying vec3 sheet_normal;
varying vec3 world_point;
float hash3(vec3 p) { return fract(sin(dot(p, vec3(127.1, 311.7, 74.7))) * 43758.5453123); }
float noise3(vec3 p) {
	vec3 i = floor(p); vec3 f = fract(p); vec3 u = f * f * (3.0 - 2.0 * f);
	float a = mix(hash3(i), hash3(i + vec3(1, 0, 0)), u.x);
	float b = mix(hash3(i + vec3(0, 1, 0)), hash3(i + vec3(1, 1, 0)), u.x);
	float c = mix(hash3(i + vec3(0, 0, 1)), hash3(i + vec3(1, 0, 1)), u.x);
	float d = mix(hash3(i + vec3(0, 1, 1)), hash3(i + vec3(1, 1, 1)), u.x);
	return mix(mix(a, b, u.y), mix(c, d, u.y), u.z);
}
void vertex() {
	ink = COLOR; state = INSTANCE_CUSTOM;
	vec3 n = normalize(VERTEX);
	float seed = state.g * 31.0;
	float t = state.r;
	float wobble = sin(n.x * 5.1 + seed + t * 7.0) * sin(n.y * 4.3 + seed * 1.7 + t * 5.3) * sin(n.z * 4.7 + seed * 0.6 - t * 6.1);
	wobble += 0.5 * sin(n.x * 11.0 - n.z * 9.0 + seed * 2.1 + t * 9.0);
	float jet = max(noise3(n * 3.3 + seed) - 0.52, 0.0) * 2.1;
	float radial = 1.0 + wobble * state.b + jet * jet * 0.55 * (1.0 - state.a);
	vec3 off = n;
	off.xy *= 1.0 + state.a * 0.4 * smoothstep(0.0, 0.9, n.z);
	off.z *= mix(1.0, 0.62, state.a);
	VERTEX = off * radial;
	sheet_normal = n;
	world_point = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
}
void fragment() {
	vec3 n = normalize(sheet_normal);
	float seed = state.g * 31.0;
	float t = state.r;
	float texture_noise = noise3(n * 2.4 + seed) * 0.6 + noise3(n * 6.1 + seed * 1.9) * 0.4;
	float threshold = mix(0.3, 1.04, smoothstep(0.0, 0.78, t)) + (1.0 - ink.a) * 0.6;
	threshold += state.a * 1.3 * smoothstep(0.3, 0.78, n.z);
	float distance_to_camera = length(CAMERA_POSITION_WORLD - world_point);
	threshold += (1.0 - smoothstep(0.8, 3.0, distance_to_camera)) * (0.35 + 0.5 * t);
	float m = texture_noise - threshold;
	float coverage = smoothstep(-max(fwidth(m), 0.0001), max(fwidth(m), 0.0001), m);
	if (coverage < 0.002) { discard; }
	vec3 view_direction = normalize(CAMERA_POSITION_WORLD - world_point);
	vec3 normal_world = normalize((INV_VIEW_MATRIX * vec4(NORMAL, 0.0)).xyz);
	float facing = dot(normal_world, view_direction);
	float inside = step(facing, 0.0);
	vec3 nf = normal_world * mix(1.0, -1.0, inside);
	vec3 light = normalize(sun_direction);
	vec3 color = ink.rgb * (0.5 + 0.6 * clamp(dot(nf, light) * 0.65 + 0.35, 0.0, 1.0));
	color *= mix(1.0, 0.58, inside);
	float rim = 1.0-smoothstep(0.0,0.09,m);
	color *= 1.0+0.3*rim;
	vec3 reflected = reflect(-view_direction, nf);
	float fresnel = pow(1.0 - abs(facing), 3.0) * (1.0 - inside);
	color = mix(color, sky_color * 1.25, fresnel * 0.32);
	color += sun_color * (pow(clamp(dot(reflected, light), 0.0, 1.0), 70.0) * 3.2+rim*.12) * (1.0 - inside);
	ALBEDO = color;
	ALPHA = coverage;
}
