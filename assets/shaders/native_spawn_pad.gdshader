// Port of the original INKWAVE decor.js PAD_FRAG.
shader_type spatial;
render_mode unshaded, cull_disabled;
varying vec2 vUv; varying vec3 vW; varying vec3 vN;
void vertex(){vUv=vec2(UV.x,1.0-UV.y);vW=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;vN=mat3(MODEL_MATRIX)*NORMAL;}


float dHash(vec2 p){ vec3 p3 = fract(vec3(p.xyx) * 0.1031); p3 += dot(p3, p3.yzx + 33.33); return fract((p3.x + p3.y) * p3.z); }
float dNoise(vec2 p){ vec2 i = floor(p), f = fract(p); vec2 u = f*f*(3.0-2.0*f);
  return mix(mix(dHash(i), dHash(i+vec2(1.0,0.0)), u.x), mix(dHash(i+vec2(0.0,1.0)), dHash(i+vec2(1.0,1.0)), u.x), u.y); }

uniform vec3 uColor;
uniform float uTime;
uniform float uPulse;
uniform float uPulseT;
uniform sampler2D uEmblem;


void fragment(){
  vec2 q = vUv * 2.0 - 1.0; float r = length(q); float a = atan(q.y, q.x + 1e-5);
  if (r > 1.0) discard;
  vec3 V = normalize(CAMERA_POSITION_WORLD - vW);
  // glossy dark base with a soft sky reflection band and a moving sun glint
  vec3 base = mix(vec3(0.035, 0.04, 0.055), vec3(0.075, 0.085, 0.11), smoothstep(1.0, 0.0, r));
  float fres = pow(max(1.0 - clamp(V.y, 0.0, 1.0), 0.0), 3.0);
  base += vec3(0.16, 0.2, 0.26) * fres;
  // pooled ink in the centre: slow liquid swirl, wet highlight
  float n = dNoise(q * 3.2 + vec2(uTime * 0.25, -uTime * 0.18)) * 0.6 + dNoise(q * 7.0 - uTime * 0.3) * 0.4;
  float pool = smoothstep(0.58, 0.5, r + (n - 0.5) * 0.06);
  vec3 ink = uColor * (0.42 + 0.3 * n) + vec3(0.9) * pow(n, 7.0) * 1.4;
  base = mix(base, ink, pool);
  // emblem (white squid) in the pool
  vec2 eu = q / 0.46 * 0.5 + 0.5;
  float em = (eu.x > 0.0 && eu.x < 1.0 && eu.y > 0.0 && eu.y < 1.0) ? texture(uEmblem, vec2(eu.x,1.0-eu.y)).a : 0.0;
  base = mix(base, vec3(1.0) * (0.9 + 0.2 * uPulse), em * pool);
  // rings: bright outer rim, inner rim, dashed rotating track, radial ticks, chevrons pointing out
  float glow = 0.0;
  glow += smoothstep(0.022, 0.0, abs(r - 0.955)) * 1.3;
  glow += smoothstep(0.014, 0.0, abs(r - 0.6)) * 0.95;
  float dash = step(0.5, fract(a / 6.2831853 * 36.0 + uTime * 0.25));
  glow += smoothstep(0.018, 0.0, abs(r - 0.79)) * dash * 0.8;
  float tick = step(0.8, fract(a / 6.2831853 * 72.0)) * smoothstep(0.035, 0.0, abs(r - 0.88));
  glow += tick * 0.45;
  float sa = mod(a - uTime * 0.35, 6.2831853 / 6.0) - 3.14159265 / 6.0;
  vec2 pc = vec2(r - 0.7, sa * 0.7);
  float chev = smoothstep(0.02, 0.0, abs(pc.x - abs(pc.y) * 0.9)) * step(abs(pc.y), 0.07) * step(-0.06, pc.x);
  glow += chev * 0.9;
  // breathing idle + spawn pulse wave
  glow *= 0.85 + 0.15 * sin(uTime * 2.2);
  float wave = uPulse * smoothstep(0.09, 0.0, abs(r - uPulseT * 1.35)) * (1.0 - smoothstep(0.7, 1.35, uPulseT * 1.35));
  vec3 col = base + uColor * glow * 2.6 + (uColor * 2.2 + vec3(1.2)) * wave * 2.2;
  col += uColor * pool * uPulse * 0.8;
  // metal lip just inside the rim
  col = mix(col, vec3(0.5, 0.52, 0.56) * (0.6 + 0.6 * fres), smoothstep(0.975, 0.99, r));
  ALBEDO = col;
  
}
