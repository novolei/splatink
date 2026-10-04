// Port of the original INKWAVE decor.js BARRIER_FRAG.
shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_never, blend_add;
varying vec2 vUv; varying vec3 vW; varying vec3 vN;
void vertex(){vUv=vec2(UV.x,1.0-UV.y);vW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=mat3(MODEL_MATRIX)*NORMAL;}

uniform vec3 uColor; uniform float uTime; uniform float uAlpha; uniform float uPulse;
  
void fragment(){
  float h = vUv.y;
  // hex lattice on the cylinder
  vec2 p = vec2(vUv.x * 64.0, h * 9.0);
  p.x += step(1.0, mod(floor(p.y), 2.0)) * 0.5;
  vec2 f = fract(p) - 0.5;
  float hexEdge = smoothstep(0.43, 0.49, max(abs(f.x) * 1.15 + abs(f.y) * 0.6, abs(f.y) * 1.2));
  float scan = smoothstep(0.08, 0.0, abs(fract(h * 1.4 - uTime * 0.45) - 0.5) - 0.44);
  float fade = pow(max(1.0 - h, 0.0), 1.6);
  float base = smoothstep(0.0, 0.06, h);
  vec3 V = normalize(CAMERA_POSITION_WORLD - vW);
  float rim = pow(max(1.0 - abs(dot(normalize(vN), V)), 0.0), 2.0);
  float a = (uAlpha + uPulse * 0.5) * fade * base * (0.25 + 0.75 * hexEdge + scan * 0.6) * (0.55 + 0.45 * rim);
  a += smoothstep(0.035, 0.0, h) * (0.5 + uAlpha);
  ALBEDO = uColor * (1.5 + uPulse); ALPHA =  a;
  
}
