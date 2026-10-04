float gInkKeep=0.0,gInkNear=0.0,gInkS=0.0,gWake=0.0;vec2 gPdx=vec2(0.0),gPdy=vec2(0.0);

  if (face_data.y > 0.5) {
    vec2 pdx = dFdx(UV2), pdy = dFdy(UV2);
    float texFoot = max(length(pdx), length(pdy)) / texel;
    float gk = min(1.0, 8.0 / max(texFoot, 1e-4));
    gPdx = pdx * gk; gPdy = pdy * gk;
    vec4 pnt = paintAt(UV2,gPdx,gPdy);
    float near = 1.0 - smoothstep(0.9, 2.4, texFoot);
    vec4 gX = vec4(0.0), gY = vec4(0.0);                   // per-texel gradients of all four channels
    vec4 l2 = textureLod(paint_atlas, UV2, 2.0);
    float seam2 = l2.r / max(l2.a, 1e-3);
    if (near > 0.0 && l2.a > 0.002 && (l2.a < 0.998 || pnt.a < 0.998 || (seam2 > 0.006 && seam2 < 0.994))) {
      vec4 cX, cY;
      vec4 cub = paintCubic(UV2, cX, cY);
      pnt = mix(pnt, cub, near);
      gX = cX * near; gY = cY * near;
    }
    gInkNear = near;
    float amt = pnt.a;
    float fw = fwidth(amt);
    float w = clamp(fw * 0.8, 0.008, 0.25);
    gInk = smoothstep(0.5 - w, 0.5 + w, amt);
    float ia = 1.0 / max(amt, 0.02);
    float tRaw = clamp(pnt.r * ia, 0.0, 1.0);
    // crisp, pixel-anti-aliased colour border between the teams (no muddy mixed-colour fringe)
    float wT = clamp(fwidth(tRaw) * 0.75, 0.012, 0.2);
    float tm = smoothstep(0.5 - wT, 0.5 + wT, tRaw);
    float wet = clamp(pnt.g * ia, 0.0, 1.0);
    float fresh = smoothstep(0.3, 0.97, wet);               // visibly wet for ≈ 4 s after landing
    gFresh = fresh * gInk;
    float tone = clamp(pnt.b * ia, 0.0, 1.0);
    bool wallF = abs(world_normal.y) < 0.5;
    vec3 Tf = normalize(face_tangent - world_normal * dot(face_tangent, world_normal)), Bf = cross(world_normal, Tf);
    // world-space direction toward the sun (the scene's only directional light)
    vec3 sunW=normalize(sun_direction);
    vec2 sunF = vec2(dot(sunW, Tf), dot(sunW, Bf));        // sun direction in the face's (u, v) plane
    // thickness profile: 0 at the edge → 1 on the flat top (≈2–3 texels in). Floors pool (tall rounded lip, taller
    // while fresh); walls hold a thinner clinging film that lets the surface relief show through a little.
    float s = clamp((amt - 0.5) * 1.7, 0.0, 1.0);
    float hs = 1.0 - (1.0 - s) * (1.0 - s);
    gInkS = hs;
    float thick = (wallF ? 0.6 : 1.0) * (1.0 + 0.5 * fresh);
    gInkKeep = wallF ? 0.32 * (1.0 - 0.5 * fresh) : 0.0;
    vec2 gradA = vec2(gX.a, gY.a);
    gInkD = gradA * 2.0 * (1.0 - s) * 1.7 * 1.9 * gInk * thick;
    // where the two teams' inks meet: the newer (wetter) ink rides over the older one on a rounded lip; two inks of
    // the same age meet in a soft crease between their rounded edges
    vec2 gT = (vec2(gX.r, gY.r) - tRaw * gradA) * ia;       // d(team share) per texel
    float gTl = length(gT);
    float seam = 0.0, seamShadow = 0.0;
    if (gTl > 0.03 && amt > 0.6) {
      vec2 sn = gT / gTl;                                    // across the seam, toward team B
      float x = (tRaw - 0.5) / gTl;                          // signed distance to the midline, texels
      float e1 = exp(-x * x / 1.7), e2 = exp(-x * x / 0.8);
      seam = e1 * smoothstep(0.03, 0.14, gTl) * near;
      vec2 gW = (vec2(gX.g, gY.g) - wet * gradA) * ia;
      float newer = clamp(dot(gW, sn) / gTl * 1.6, -1.0, 1.0);   // +1: team B's side is the newer, wetter ink
      float dh = newer * 2.4 * e1 / 2.3 + 0.9 * 2.0 * x / 0.8 * e2 * (1.0 - 0.6 * abs(newer));
      gInkD += sn * dh * seam * gInk * thick;
      // the lower (older) side sits in the lip's shadow; the crease itself is a thin dark line
      seamShadow = seam * (0.45 * max(0.0, -x * newer) * e1 + 0.55 * e2 * (1.0 - 0.7 * abs(newer)));
    }
    vec3 team = mix(team_a, team_b, tm);
    vec3 inkCol = team * (0.93 + 0.13 * tone);
    // translucent thin lip reads lighter and a touch more saturated; the thick body a little deeper
    float lip = (1.0 - hs) * near;
    inkCol = mix(inkCol, inkCol * 1.16 + team * 0.05, lip * 0.35);
    inkCol *= 1.0 - 0.05 * hs;
    inkCol *= 1.0 - 0.3 * seamShadow * gInk;
    // fresh ink: a touch brighter + richer for the first moments, settling to its dry colour
    inkCol *= 1.0 + 0.07 * fresh * fresh;
    gInkCol = inkCol;
    float halo = smoothstep(0.06, 0.5, amt) * (1.0 - gInk) * near;
    if (!wallF) {
      // ink sits ON the ground: the lip throws a soft contact shadow, heavier on the side away from the sun
      vec2 outN = -gradA / max(length(gradA), 1e-4);
      float away = clamp(0.55 - 0.9 * dot(outN, normalize(sunF + 1e-4)) * length(sunF), 0.25, 1.3);
      halo *= smoothstep(0.4, 0.85, world_normal.y) * away;
      base *= mix(vec3(1.0), team * 0.45 + 0.3, halo * 0.5);
    } else {
      // walls: the edge soaks into the surface — a damp, slightly tinted halo instead of a shadow
      base *= mix(vec3(1.0), team * 0.35 + 0.5, halo * 0.55);
    }
    base = mix(base, gInkCol, gInk);
  }