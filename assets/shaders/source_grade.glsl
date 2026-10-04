// Original INKWAVE HDR grade and Three.js NeutralToneMapping.
#[vertex]
#version 450
void main(){vec2 p=vec2(gl_VertexIndex==1?2.0:0.0,gl_VertexIndex==2?2.0:0.0);gl_Position=vec4(p*2.0-1.0,0.0,1.0);}
#[fragment]
#version 450
layout(set=0,binding=0)uniform sampler2D source_color;
layout(location=0)out vec4 out_color;
layout(push_constant,std430)uniform Params{vec4 size_hurt_flash;vec4 sat_vib_contrast_lift;vec4 shadow_exposure;vec4 high_vignette;}p;
#define uSat p.sat_vib_contrast_lift.x
#define uVib p.sat_vib_contrast_lift.y
#define uContrast p.sat_vib_contrast_lift.z
#define uLift p.sat_vib_contrast_lift.w
#define uShadowTint p.shadow_exposure.xyz
#define uExposure p.shadow_exposure.w
#define uHighTint p.high_vignette.xyz
#define uVignette p.high_vignette.w
#define uHurt p.size_hurt_flash.z
#define uFlash p.size_hurt_flash.w
#define uAspect (p.size_hurt_flash.x/p.size_hurt_flash.y)
#define toneMappingExposure 0.94
vec3 NeutralToneMapping( vec3 color ) {
	const float StartCompression = 0.8 - 0.04;
	const float Desaturation = 0.15;
	color *= toneMappingExposure;
	float x = min( color.r, min( color.g, color.b ) );
	float offset = x < 0.08 ? x - 6.25 * x * x : 0.04;
	color -= offset;
	float peak = max( color.r, max( color.g, color.b ) );
	if ( peak < StartCompression ) return color;
	float d = 1. - StartCompression;
	float newPeak = 1. - d * d / ( peak + d - StartCompression );
	color *= newPeak / peak;
	float g = 1. - 1. / ( Desaturation * ( peak - newPeak ) + 1. );
	return mix( color, vec3( newPeak ), g );
}

void main(){vec2 uv=gl_FragCoord.xy/abs(p.size_hurt_flash.xy);
      vec4 c = texture(source_color, uv);
      if(p.size_hurt_flash.x<0.0){out_color=c;return;}
      c.rgb *= uExposure;
      float l = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
      // vibrance: muted colours gain saturation, already-saturated ones (team ink) barely move
      float mx = max(c.r, max(c.g, c.b)), mn = min(c.r, min(c.g, c.b));
      float chroma = (mx - mn) / max(mx, 1e-4);
      c.rgb = max(mix(vec3(l), c.rgb, uSat + uVib * (1.0 - smoothstep(0.1, 0.7, chroma))), 0.0);
      // contrast in log space around mid grey (keeps HDR highlights ordered), then a cool-shadow / warm-light split tone
      c.rgb = 0.18 * pow(max(c.rgb, vec3(1e-6)) / 0.18, vec3(uContrast)) + uLift;
      // split tone is for the world's neutrals: strongly saturated colours (team ink) keep their exact hue
      float lt = smoothstep(0.015, 0.55, l);
      c.rgb *= mix(vec3(1.0), mix(uShadowTint, uHighTint, lt), 1.0 - 0.85 * smoothstep(0.35, 0.8, chroma));
      vec2 q = (uv - 0.5) * vec2(uAspect, 1.0);
      float r = length(q);
      float v = smoothstep(0.55, 1.25, r);
      c.rgb *= 1.0 - uVignette * v;
      // low health: the HUD draws the coloured edge; here we only drain saturation + darken the rim slightly
      float lum = dot(c.rgb, vec3(0.2126, 0.7152, 0.0722));
      c.rgb = mix(c.rgb, vec3(lum), uHurt * 0.45);
      c.rgb *= 1.0 - uHurt * 0.25 * smoothstep(0.4, 1.2, r);
      c.rgb += uFlash;

out_color=vec4(p.size_hurt_flash.y<0.0?c.rgb:NeutralToneMapping(c.rgb),c.a);}
