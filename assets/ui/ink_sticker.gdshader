shader_type canvas_item;
render_mode blend_mix;
// inkwave 联机页的"贴纸"（styles/ui.css 的 --stk / .iw-hubcard / .iw-code__box / .iw-stag / .iw-wchip）：
// 不透明的圆角块 + 白色模切环 + 墨黑粗描边 + 错位的硬投影；块面可以叠 移动斜纹 / 坦克队列图案 / 网点 / 日光放射线。
// 四个圆角各自的半径（网页里每角 border-radius 都不一样，贴纸才不显得机械）。长度单位都是像素。

uniform vec2 quad_size = vec2(300.0, 200.0);
uniform vec2 body_pos = vec2(40.0, 40.0);
uniform vec2 body_size = vec2(220.0, 120.0);
uniform vec4 radii = vec4(24.0, 22.0, 24.0, 23.0);       // 左上 右上 右下 左下
uniform vec4 fill_a : source_color = vec4(0.6, 0.69, 1.0, 1.0);
uniform vec4 fill_b : source_color = vec4(0.18, 0.36, 1.0, 1.0);
uniform vec4 fill_c : source_color = vec4(0.14, 0.26, 0.7, 1.0);
uniform vec3 stops = vec3(-0.4, 0.42, 1.1);              // linear-gradient(165deg, a -40%, b 42%, c 110%)
uniform vec2 grad_dir = vec2(0.2588, 0.9659);            // 165°（y 向下）
uniform float ring_px = 2.5;
uniform vec4 ring_color : source_color = vec4(1.0, 1.0, 1.0, 1.0);
uniform float outline_px = 4.0;
uniform vec4 outline_color : source_color = vec4(0.082, 0.071, 0.11, 1.0);
uniform vec2 shadow_off = vec2(6.7, 8.3);
uniform vec4 shadow_color : source_color = vec4(0.082, 0.071, 0.11, 1.0);
uniform float css_px = 1.0;                              // u / 16
// 图案
uniform float stripes = 0.0;
uniform float stripe_period = 38.4;
uniform float stripe_width = 19.2;
uniform float stripe_phase = 0.0;                       // 流动相位（个周期，0..1）：InkPattern 按真实时钟写，不用 TIME（TIME 会被 Engine.time_scale 加速）
uniform float stripe_alpha = 0.13;
uniform float tanks = 0.0;                               // 坦克队列（网页是鱿鱼队列）
uniform vec4 tank_color : source_color = vec4(1.0, 1.0, 1.0, 0.06);
uniform float dots = 0.0;
uniform vec4 dot_color : source_color = vec4(1.0, 1.0, 1.0, 0.11);
uniform float rays = 0.0;                                // 日光放射线（名牌）
uniform vec2 ray_centre = vec2(0.72, 1.0);               // 相对块面 0..1
uniform float ray_count = 16.0;
uniform vec4 ray_color : source_color = vec4(1.0, 0.77, 0.54, 0.55);
uniform float dome_radius = 16.0;
uniform vec4 dome_color : source_color = vec4(0.72, 0.38, 0.06, 1.0);
uniform float shade_left = 0.0;                          // 名牌左端压暗（linear-gradient(90deg, .28 → 0 40%)）
uniform float inset_shadow = 0.0;                        // 代码格的内凹：顶部一道深影（inset 0 .5u 0 rgba(0,0,0,.5)）
uniform float inset_px = 8.0;
uniform vec4 inset_color : source_color = vec4(0.0, 0.0, 0.0, 0.5);
uniform float inner_ring_px = 2.5;                       // 代码格的内环：inset 0 0 0 .16u rgba(255,255,255,.16)
uniform vec4 inner_ring_color : source_color = vec4(1.0, 1.0, 1.0, 0.16);
uniform float dashed = 0.0;                              // 空代码格的虚线内框
uniform float dash_inset = 8.0;
uniform float dash_radius = 11.0;
uniform vec4 dash_color : source_color = vec4(1.0, 1.0, 1.0, 0.16);
uniform float bottom_shade = 0.0;                        // 已填代码格：inset 0 -.4u 0 #ddd8ea
uniform vec4 bottom_shade_color : source_color = vec4(0.867, 0.847, 0.918, 1.0);
uniform float bottom_shade_px = 6.4;

// 指针互动（网页 _fx：--rx / --ry 的 3D 倾斜 + 悬停时跟着指针的白色高光 .iw-hubcard__ink）
uniform vec2 tilt = vec2(0.0);                           // rotateX / rotateY（弧度）；perspective(900px)
uniform float persp = 900.0;
uniform vec2 warp_centre = vec2(0.0);                    // 倾斜绕着走的中心（画布像素）
uniform vec4 spot = vec4(0.0, 0.0, 1.0, 0.0);            // 高光：中心（块面像素）、半径、强度

void vertex() {
	if (abs(tilt.x) + abs(tilt.y) > 0.00001) {
		// CSS: perspective(P) rotateX(rx) rotateY(ry)；y 向下，正 z 朝向观众
		vec2 p = VERTEX - warp_centre;
		float cx = cos(tilt.x);
		float sx = sin(tilt.x);
		float cy = cos(tilt.y);
		float sy = sin(tilt.y);
		float x1 = p.x * cy;
		float z1 = -p.x * sy;
		float y2 = p.y * cx - z1 * sx;
		float z2 = p.y * sx + z1 * cx;
		VERTEX = warp_centre + vec2(x1, y2) * (persp / (persp - z2));
	}
}

float box_sd(vec2 p, vec2 half_size, vec4 r) {
	float rad = p.x > 0.0 ? (p.y > 0.0 ? r.z : r.y) : (p.y > 0.0 ? r.w : r.x);
	vec2 q = abs(p) - half_size + vec2(rad);
	return min(max(q.x, q.y), 0.0) + length(max(q, vec2(0.0))) - rad;
}

float cover(float d) {
	return clamp(0.5 - d, 0.0, 1.0);
}

vec4 over(vec4 below, vec4 above) {
	float a = above.a + below.a * (1.0 - above.a);
	vec3 rgb = a > 0.0001 ? (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / a : vec3(0.0);
	return vec4(rgb, a);
}

// 一辆坦克的剪影：车体 + 炮塔 + 炮管，绕自己的中心转 angle。
float tank_sd(vec2 p, float angle, float s) {
	float c = cos(angle);
	float n = sin(angle);
	vec2 q = vec2(c * p.x + n * p.y, -n * p.x + c * p.y) / s;
	vec4 hull_r = vec4(1.6);
	float hull = box_sd(q, vec2(7.0, 4.6), hull_r);
	float turret = length(q - vec2(-0.6, 0.0)) - 3.1;
	float barrel = box_sd(q - vec2(5.6, 0.0), vec2(4.6, 0.9), vec4(0.6));
	return min(min(hull, turret), barrel) * s;
}

void fragment() {
	vec2 px = UV * quad_size;
	vec2 half_size = body_size * 0.5;
	vec2 local = px - body_pos;
	vec2 p = local - half_size;
	float d = box_sd(p, half_size, radii);
	float edge = ring_px + outline_px;
	vec4 result = vec4(0.0);

	float shadow_d = box_sd(p - shadow_off, half_size, radii) - edge;
	result = over(result, vec4(shadow_color.rgb, shadow_color.a * cover(shadow_d)));
	result = over(result, vec4(outline_color.rgb, outline_color.a * cover(d - edge)));
	result = over(result, vec4(ring_color.rgb, ring_color.a * cover(d - ring_px)));

	float span = abs(body_size.x * grad_dir.x) + abs(body_size.y * grad_dir.y);
	float t = 0.5 + dot(p, grad_dir) / span;
	vec4 base;
	if (t < stops.y) {
		base = mix(fill_a, fill_b, clamp((t - stops.x) / (stops.y - stops.x), 0.0, 1.0));
	} else {
		base = mix(fill_b, fill_c, clamp((t - stops.y) / (stops.z - stops.y), 0.0, 1.0));
	}
	vec4 body = vec4(base.rgb, base.a);

	if (rays > 0.5) {
		vec2 from = local - body_size * ray_centre;
		float angle = atan(-from.y, from.x);
		if (angle >= 0.0) {
			float wedge = floor(angle / 3.14159265 * ray_count);
			if (mod(wedge, 2.0) < 0.5) {
				body = over(body, ray_color);
			}
		}
		float dome = length(from) - dome_radius;
		body = over(body, vec4(dome_color.rgb, dome_color.a * cover(dome)));
	}
	if (stripes > 0.5) {
		float s = dot(local, vec2(-0.70711, -0.70711)) + stripe_phase * stripe_period;
		float on = step(mod(s, stripe_period), stripe_width);
		body = over(body, vec4(0.0, 0.0, 0.0, stripe_alpha * on));
	}
	if (tanks > 0.5) {
		float tile = 72.0 * css_px;
		vec2 cell = mod(local, vec2(tile));
		float da = tank_sd(cell - vec2(15.0, 14.0) * css_px, -0.384, css_px);
		float db = tank_sd(cell - vec2(51.0, 50.0) * css_px, 0.489, css_px);
		float glyph = max(cover(da), cover(db));
		body = over(body, vec4(tank_color.rgb, tank_color.a * glyph));
	}
	if (dots > 0.5) {
		float cell_px = 10.0 * css_px;
		float dist = length(mod(local, vec2(cell_px)) - vec2(cell_px * 0.5));
		float dot_on = 1.0 - smoothstep(1.3 * css_px, 1.8 * css_px, dist);
		vec2 mdir = vec2(-0.34202, 0.93969);
		float mt = clamp(0.5 + dot(p, mdir) / (abs(body_size.x * mdir.x) + abs(body_size.y * mdir.y)), 0.0, 1.0);
		body = over(body, vec4(dot_color.rgb, dot_color.a * dot_on * (1.0 - smoothstep(0.0, 0.45, mt))));
	}
	if (spot.w > 0.001) {
		float fall = 1.0 - clamp(length(local - spot.xy) / spot.z, 0.0, 1.0);
		body = over(body, vec4(1.0, 1.0, 1.0, spot.w * fall));
	}
	if (shade_left > 0.5) {
		float ls = clamp(local.x / (body_size.x * 0.4), 0.0, 1.0);
		body = over(body, vec4(0.04, 0.03, 0.08, 0.28 * (1.0 - ls)));
	}
	if (dashed > 0.5) {
		float inner = box_sd(p, half_size - vec2(dash_inset), vec4(dash_radius));
		float band = cover(abs(inner) - css_px);
		float dash = step(mod(local.x + local.y, 8.0 * css_px), 4.0 * css_px);
		body = over(body, vec4(dash_color.rgb, dash_color.a * band * dash));
	}
	if (inset_shadow > 0.5) {
		float shifted = box_sd(p - vec2(0.0, inset_px), half_size, radii);
		body = over(body, vec4(inset_color.rgb, inset_color.a * (1.0 - cover(shifted))));
		body = over(body, vec4(inner_ring_color.rgb, inner_ring_color.a * (1.0 - cover(d + inner_ring_px))));
	}
	if (bottom_shade > 0.5) {
		float shifted = box_sd(p + vec2(0.0, bottom_shade_px), half_size, radii);
		body = over(body, vec4(bottom_shade_color.rgb, bottom_shade_color.a * (1.0 - cover(shifted))));
	}
	result = over(result, vec4(body.rgb, body.a * cover(d)));
	COLOR = result;
}
