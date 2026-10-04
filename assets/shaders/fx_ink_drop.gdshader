shader_type spatial;
render_mode unshaded, cull_disabled, depth_prepass_alpha;
// INKWAVE fx.js DROP_FRAG: wet-ink Fresnel, teardrop capsule, backlit transmission.
uniform vec3 sun_direction = vec3(-0.5, 0.8, 0.3);
uniform vec3 camera_right = vec3(1.0, 0.0, 0.0);
uniform vec3 camera_up = vec3(0.0, 1.0, 0.0);
uniform vec3 camera_back = vec3(0.0, 0.0, 1.0);
uniform vec3 sky_color : source_color = vec3(0.62, 0.76, 0.97);
uniform vec3 ground_color : source_color = vec3(0.22, 0.15, 0.32);
uniform vec3 sun_color : source_color = vec3(1.0);
varying vec4 ink_color;
varying vec4 state;
varying vec2 velocity_axis;

void vertex() {
	ink_color = COLOR;
	state = INSTANCE_CUSTOM;
	vec3 axis_world = MODEL_MATRIX[1].xyz;
	vec2 axis_view = vec2(dot(axis_world, camera_right), dot(axis_world, camera_up));
	velocity_axis = length(axis_view) > 1e-10 ? normalize(axis_view) : vec2(0.0, 1.0);
	// Original DROP_VERT pushes every projected vertex 0.6 radii toward the eye.
	vec4 projected = MODELVIEW_MATRIX * vec4(VERTEX, 1.0);
	projected.xyz += normalize(-projected.xyz) * state.r * 0.6;
	POSITION = PROJECTION_MATRIX * projected;
}

void fragment() {
	vec2 p = UV * 2.0 - 1.0;
	float tail = clamp((state.g - 1.15) / 1.1, 0.0, 1.0);
	float yc = 0.42 * tail;
	float rh = 1.0 - yc;
	float rt = mix(rh, 0.1, tail);
	vec2 A = vec2(0.0, -yc);
	vec2 B = vec2(0.0, 1.0 - rt);
	vec2 pa = p - A;
	vec2 ba = B - A;
	float h = tail > 0.0 ? clamp(dot(pa, ba) / max(dot(ba, ba), 0.00001), 0.0, 1.0) : 0.0;
	vec2 o = pa - ba * h;
	float radius = mix(rh, rt, h);
	float sd = length(o) - radius;
	float coverage = 1.0 - smoothstep(-max(fwidth(sd), 0.0001), max(fwidth(sd), 0.0001), sd);
	if (coverage < 0.002) { discard; }
	vec2 q = o / max(radius, 0.001);
	float z = sqrt(max(1.0 - dot(q, q), 0.0));
	vec2 across = vec2(velocity_axis.y, -velocity_axis.x);
	vec3 n = normalize(vec3(across * q.x - velocity_axis * q.y, z + 0.05));
	vec3 L = normalize(vec3(dot(sun_direction, camera_right), dot(sun_direction, camera_up), dot(sun_direction, camera_back)));
	vec3 up = vec3(camera_right.y, camera_up.y, camera_back.y);
	float edge = 1.0 - z;
	float gloss = state.b;
	vec3 ambient = mix(ground_color, sky_color, dot(n, up) * 0.5 + 0.5);
	vec3 base = ink_color.rgb * (ambient * 0.55 + sun_color * clamp(dot(n, L) * 0.6 + 0.4, 0.0, 1.0) * 0.8 + 0.14);
	vec2 sun_xy = normalize(vec2(dot(L.xy, across), dot(L.xy, velocity_axis)) + vec2(0.0001));
	float transmission = pow(clamp(-dot(vec2(q.x, -q.y), sun_xy), 0.0, 1.0), 1.5) * (0.35 + 0.65 * edge);
	base += ink_color.rgb * (ink_color.rgb + 0.25) * transmission * 0.7 * gloss;
	base *= mix(1.0, 0.6, pow(edge, 2.2) * gloss);
	vec3 reflected = reflect(vec3(0.0, 0.0, -1.0), n);
	vec3 environment = mix(ground_color * 0.7, sky_color * 1.4, smoothstep(-0.15, 0.35, dot(reflected, up)));
	float fresnel = (0.04 + 0.96 * pow(edge, 4.0)) * gloss;
	vec3 color = mix(base, environment, fresnel * 0.42);
	float spec = clamp(dot(reflected, L), 0.0, 1.0);
	color += sun_color * (pow(spec, 150.0) * 7.0 + pow(spec, 16.0) * 0.28) * gloss;
	ALBEDO = color * mix(0.85, 1.0, gloss);
	ALPHA = coverage * ink_color.a * state.a;
}
