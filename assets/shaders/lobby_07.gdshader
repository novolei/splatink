// Original source ShaderMaterial 7.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
varying vec3 source_camera;
varying vec3 vDir; 

      uniform float uTime; uniform vec3 uGlow; 
      
float lsH(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float lsN(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(lsH(i), lsH(i + vec2(1, 0)), u.x), mix(lsH(i + vec2(0, 1)), lsH(i + vec2(1, 1)), u.x), u.y); }
float lsF(vec2 p) { float s = 0.0, a = 0.5; for (int i = 0; i < 4; i++) { s += a * lsN(p); p = mat2(vec2(1.6,1.2),vec2(-1.2,1.6)) * p + 7.1; a *= 0.5; } return s / 0.9375; }

      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vec4 w = MODEL_MATRIX * vec4(VERTEX, 1.0); vDir = w.xyz - source_camera; POSITION = PROJECTION_MATRIX * VIEW_MATRIX * w; POSITION.z = POSITION.w * 0.000001; }
void fragment(){vec4 sourceOutput=vec4(0.0);
        vec3 d = normalize(vDir); float e = d.y;
        vec3 zen = vec3(0.006, 0.012, 0.045), mid = vec3(0.02, 0.05, 0.14), hor = vec3(0.07, 0.12, 0.2);
        vec3 c = mix(hor, mid, smoothstep(0.0, 0.25, e)); c = mix(c, zen, smoothstep(0.2, 0.75, e));
        float toward = smoothstep(0.2, 1.0, -d.z);
        c += uGlow * exp(-max(e, 0.0) * 9.0) * (0.25 + 0.75 * toward);
        // thin high cloud streaks catching the city light from below
        vec2 cp = d.xz / max(e + 0.12, 0.05);
        float cl = smoothstep(0.55, 0.8, lsF(cp * vec2(0.35, 1.2) + vec2(uTime * 0.004, 0.0)));
        c = mix(c, uGlow * 0.35 + vec3(0.03, 0.04, 0.07), cl * 0.55 * smoothstep(0.02, 0.2, e) * smoothstep(0.9, 0.3, e));
        sourceOutput = vec4(c, 1.0);
      ALBEDO=sourceOutput.rgb;}
