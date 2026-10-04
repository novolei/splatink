// Original source ShaderMaterial 9.
shader_type spatial;
render_mode unshaded,cull_disabled,fog_disabled;
varying vec3 source_camera;
varying vec2 vUv; 
uniform sampler2D map:filter_linear_mipmap; uniform vec3 uFog; uniform float uF; uniform vec2 uV; 
      
void vertex(){source_camera=CAMERA_POSITION_WORLD;vec2 sourceUv=vec2(UV.x,1.0-UV.y); vUv = sourceUv; POSITION = PROJECTION_MATRIX * MODELVIEW_MATRIX * vec4(VERTEX, 1.0); }
void fragment(){vec4 sourceOutput=vec4(0.0); vec4 t = texture(map, vec2(vUv.x, uV.x + vUv.y * uV.y)); if (t.a < 0.5) discard;
        vec3 c = t.rgb * t.rgb * 1.6;
        float h = mix(1.0, 0.45, vUv.y);
        sourceOutput = vec4(mix(c, uFog, uF * h), 1.0); ALBEDO=sourceOutput.rgb;}
