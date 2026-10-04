shader_type canvas_item;
render_mode blend_mix;
uniform float focus_outline=1.0;
// inkwave 的 chunky 按钮底板（styles/ui.css .iw-btn）：圆角深底 + 内描环 + 底唇 + 聚焦时的墨团填充 + 主按钮的斜纹。
// 一张四边形画完全部层（SDF 圆角，自带抗锯齿）；文字 / 图标是上层的普通节点。所有长度单位都是像素（脚本按 u 换算好传进来）。

uniform vec2 quad_size = vec2(100.0, 40.0);   // 整张四边形（含底唇 / 软投影的外扩）
uniform vec2 body_pos = vec2(0.0, 0.0);       // 按钮主体左上角在四边形内的位置
uniform vec2 body_size = vec2(100.0, 40.0);
uniform float radius = 12.0;
uniform vec4 bg : source_color = vec4(0.078, 0.063, 0.125, 0.9);          // --bg
uniform vec4 fill : source_color = vec4(1.0, 0.541, 0.078, 1.0);          // --fill（聚焦时的墨团色）
uniform vec4 focus_accent:source_color=vec4(1.,.54,.078,1.);
uniform vec4 lip_rest : source_color = vec4(0.0, 0.0, 0.0, 0.45);         // 0 .42u 0 rgba(0,0,0,.45)
uniform vec4 lip_focus : source_color = vec4(0.082, 0.071, 0.11, 1.0);    // 0 .5u 0 var(--k)
uniform vec4 ring_rest : source_color = vec4(1.0, 1.0, 1.0, 0.1);         // inset 0 0 0 2px rgba(255,255,255,.1)
uniform vec4 ring_focus : source_color = vec4(0.0, 0.0, 0.0, 0.15);
uniform float lip_rest_px = 6.0;
uniform float lip_focus_px = 8.0;
uniform float ring_px = 2.0;
uniform float shadow_blur_px = 24.0;          // 聚焦时的软投影 0 1u 1.5u rgba(0,0,0,.3)
uniform float shadow_drop_px = 16.0;
uniform float focus : hint_range(0.0, 1.0) = 0.0;   // 0..1：颜色 / 唇的过渡
uniform float blob : hint_range(0.0, 1.0) = 0.0;    // 墨团缩放 0..1（ease-out 由脚本给）
uniform vec2 blob_origin = vec2(0.0, 0.5);          // 0..1，相对按钮主体
uniform float stripes : hint_range(0.0, 1.0) = 0.0; // 主按钮 / 联机键的移动斜纹
uniform float stripe_period_px = 24.0;
uniform float stripe_width_px = 10.0;
uniform float stripe_phase = 0.0;                   // 流动相位（个周期，0..1）：脚本按真实时钟写（InkPattern），不用 TIME——TIME 会被 Engine.time_scale 加速
uniform vec2 stripe_axis = vec2(0.906, 0.423);      // 斜纹法线（115°）
uniform float stripe_alpha = 0.1225;           // 白 .35 × 层不透明度 .35
uniform float dots : hint_range(0.0, 1.0) = 0.0;   // 联机键的网点（.iw-btn--online::before：11px 格、点半径 1.4px、层不透明度 .5、6 s 漂 44,-22）
uniform float dot_cell_px = 11.0;
uniform float dot_radius_px = 1.4;
uniform vec2 dot_phase = vec2(0.0);                 // 网点漂移相位（个格）；图案向 +x / -y 走，和网页 background-position → (44, -22) 一致
uniform float dot_alpha = 0.14;                     // 白 .28 × .5

float box_sd(vec2 p, vec2 half_size, float r) {
	vec2 q = abs(p) - half_size + vec2(r);
	return length(max(q, vec2(0.0))) + min(max(q.x, q.y), 0.0) - r;
}

float cover(float d) {
	return clamp(0.5 - d, 0.0, 1.0);
}

vec4 over(vec4 below, vec4 above) {
	float a = above.a + below.a * (1.0 - above.a);
	vec3 rgb = a > 0.0001 ? (above.rgb * above.a + below.rgb * below.a * (1.0 - above.a)) / a : vec3(0.0);
	return vec4(rgb, a);
}

void fragment() {
	vec2 px = UV * quad_size;
	vec2 half_size = body_size * 0.5;
	vec2 centre = body_pos + half_size;
	float d_body = box_sd(px - centre, half_size, radius);
	float lip_px = mix(lip_rest_px, lip_focus_px, focus);
	float d_lip = box_sd(px - centre - vec2(0.0, lip_px), half_size, radius);
	vec4 result = vec4(0.0);

	// 软投影（只有聚焦时才有）
	float d_shadow = box_sd(px - centre - vec2(0.0, shadow_drop_px), half_size, radius);
	float soft = (1.0 - smoothstep(-shadow_blur_px * 0.5, shadow_blur_px, d_shadow)) * 0.3 * focus;
	result = over(result, vec4(0.0, 0.0, 0.0, soft));
	// Keyboard focus uses the original white/ink/accent stack outside the face.
	float focus_edge = cover(d_body - 8.0) * (1.0-cover(d_body));
	vec3 edge_ink=mix(vec3(.082,.071,.11),focus_accent.rgb,step(5.5,d_body));
	edge_ink=mix(edge_ink,vec3(1.0),step(2.0,d_body)*(1.0-step(4.5,d_body)));
	result=over(result,vec4(edge_ink,focus_edge*focus*focus_outline));

	// 底唇：半透明黑（静止）→ 墨黑实色（聚焦）
	vec4 lip = mix(lip_rest, lip_focus, focus);
	result = over(result, vec4(lip.rgb, lip.a * cover(d_lip)));

	// 主体
	result = over(result, vec4(bg.rgb, bg.a * cover(d_body)));

	// 斜纹（在墨团下面）：115° 的 repeating-linear-gradient
	if (stripes > 0.0) {
		vec2 local = px - body_pos;
		float along = dot(local, stripe_axis) + stripe_phase * stripe_period_px;
		float band = mod(along, stripe_period_px);
		float on = step(band, stripe_width_px);
		result = over(result, vec4(1.0, 1.0, 1.0, on * stripe_alpha * stripes * cover(d_body)));
	}

	// 网点（在墨团下面）
	if (dots > 0.0) {
		vec2 cell = mod(px - body_pos - dot_phase * dot_cell_px, vec2(dot_cell_px));
		float dist = length(cell - vec2(dot_cell_px * 0.5));
		float on = 1.0 - smoothstep(dot_radius_px, dot_radius_px + 0.5, dist);
		result = over(result, vec4(1.0, 1.0, 1.0, on * dot_alpha * dots * cover(d_body)));
	}

	// 墨团填充：以 blob_origin 为中心、半径 = 主体宽 × 1.3 × blob 的圆，被按钮主体裁切
	if (blob > 0.001) {
		vec2 origin_px = body_pos + blob_origin * body_size;
		float reach = body_size.x * 1.3 * blob;
		float wob = 1.0 + 0.045 * sin(atan(px.y - origin_px.y, px.x - origin_px.x) * 2.0 + 0.8);
		float edge = length(px - origin_px) - reach * wob;
		float inside = cover(edge) * cover(d_body);
		vec2 g = (px - origin_px) / max(reach * 2.0, 1.0) + vec2(0.5);
		float gloss = smoothstep(0.4, 0.0, distance(g, vec2(0.7, 0.3))) * 0.28;
		result = over(result, vec4(mix(fill.rgb, vec3(1.0), gloss), fill.a * inside));
	}

	// 内描环：静止 = 白 .1，聚焦 = 黑 .15
	vec4 ring = mix(ring_rest, ring_focus, focus);
	float ring_cover = cover(d_body) * (1.0 - cover(d_body + ring_px));
	result = over(result, vec4(ring.rgb, ring.a * ring_cover));

	COLOR = result;
}
