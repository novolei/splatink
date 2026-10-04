// Original levelMaterial.js surface detail, including stair relief, drainage, coping, weathering and stage-owned surface slots.
vec3 gTexMod=vec3(1.0);float gTexPaint=1.0;vec3 gTexN=vec3(0.0,0.0,1.0);vec4 gTexORM=vec4(1.0,.8,0.0,.5);float gTexStr=0.0;vec4 gStair=vec4(0.0);float gTexKeep=0.0;float gTexAlpha=1.0;float gInk=0.0;vec3 gInkCol=vec3(0.0);float gInkH=0.0;vec2 gInkD=vec2(0.0);float gRib=0.0;float gFresh=0.0;
  vec2 fu = UV;
  float pattern = face_data.x;
if(grate){
  // bar grating: 4 cm bars on a 7 cm pitch one way, 2 cm cross-bars every 20 cm; holes are cut out
  {
    float gw = fwidth(fu.x) + 1e-4;
    float bx = 1.0 - smoothstep(0.02 - gw, 0.02 + gw, abs(fract(fu.x / 0.07 + 0.5) - 0.5) * 0.07);
    float by = 1.0 - smoothstep(0.01 - gw, 0.01 + gw, abs(fract(fu.y / 0.2 + 0.5) - 0.5) * 0.2);
    float edge = 1.0 - smoothstep(0.05, 0.06, min(min(fu.x, fsz0(face_data).x - fu.x), min(fu.y, fsz0(face_data).y - fu.y)));
    float solid = max(max(bx, by), edge);
    if (abs(world_normal.y) < 0.5) solid = 1.0;
    if (solid < 0.5) discard;
  }
}
  vec2 fsz = face_data.zw;
  vec3 base = COLOR.rgb;
  float rough = 0.82;
  float big = fbm(world_pos.xz * 0.18 + world_pos.y * 0.1);
  float fine = vnoise(fu * 9.0);
#ifdef USE_TEXLIB
  {
    int pid = int(pattern + 0.5);
    bool vertical = abs(world_normal.y) < 0.5;
    // per-slot remaps: ramp / asphalt / yard sides → concrete, car-deck edge → plating, gelcoat tops → planks
    if (vertical) pid = int(tints[pid].z + 0.5); else if (world_normal.y > 0.5) pid = int(tints[pid].w + 0.5);
    vec4 tl = slots[pid]; vec4 tt = tints[pid];
    // stairs / ramps: sample in the ramp's own frame — u across, v downhill from the top landing — with v phase-locked so
    // a whole number of steps fits the visible flight (the slab runs 0.6 m on under the floor at its low end, level.js)
    vec2 tuv = fu * tl.y;
    vec4 sp = stairs[pid];
    vec2 tA = vec2(1.0, 0.0), tD = vec2(0.0, 1.0);
    if (sp.x > 0.0 && world_normal.y > 0.5) {
      bool alongU = abs(face_tangent.y) > 0.02;                                   // x-running ramps: face u runs up/down the slope
      float sg = alongU ? sign(face_tangent.y) : sign(world_normal.z * face_tangent.x - world_normal.x * face_tangent.z);   // uphill = +axis?
      float fa = alongU ? fu.x : fu.y, fcr = alongU ? fu.y : fu.x;
      float La = alongU ? fsz.x : fsz.y, Wd = alongU ? fsz.y : fsz.x;
      float dTop = sg > 0.0 ? La - fa : fa;
      if (dTop > La - 0.3) { sg = -sg; dTop = La - dTop; }                   // bevel past the crest: visible fragments never sit in the buried tail
      float Lv = max(La - 0.6, sp.x);
      float Ps = Lv / max(1.0, floor(Lv / sp.x + 0.5));
      tuv = vec2(fcr * tl.y, dTop / (Ps * sp.y));
      tA = alongU ? vec2(0.0, 1.0) : vec2(1.0, 0.0);
      tD = alongU ? vec2(-sg, 0.0) : vec2(0.0, -sg);
      gStair = vec4(fcr, Wd, sp.w, dTop / Ps);
      gTexKeep = sp.z;
    }
    TexlibSample ts = texlibSample(t_albedo, t_normal, t_orm, tuv, tl.x, int(tl.z), int(tl.w));
    ts.normal = vec3(ts.normal.x * tA + ts.normal.y * tD, ts.normal.z);      // back into the face's (u, v) frame
    base = tt.x > 1.5 ? ts.albedo.rgb + COLOR.rgb * ts.albedo.a * 1.25
         : (tt.x > 0.5 ? COLOR.rgb * ts.albedo.rgb * 1.25 : ts.albedo.rgb);
    base *= texlibMacro(world_pos.xz + world_pos.y * 0.7);
    base *= mix(1.0, ts.orm.r, 0.85);                            // cavity occlusion in grout / seams / grooves
    gTexMod = (tt.x > 1.5 ? vec3(ts.albedo.a * 1.25) : (tt.x > 0.5 ? ts.albedo.rgb * 1.25 : vec3(1.0))) * mix(1.0, ts.orm.r, 0.85);
    gTexPaint = tt.x > 1.5 ? clamp(ts.albedo.a * 1.45, 0.0, 1.0) : 1.0;
    rough = ts.orm.g;
    gTexN = ts.normal; gTexORM = ts.orm; gTexStr = tt.y; gTexAlpha = ts.albedo.a;
    if(grate){
      if (texlibCoverage(ts.albedo.a, fu * tl.y, 512.0) < 0.5 && !vertical) discard;
    }
  }
  if (pattern < 0.5) {
  } else if (pattern < 1.5) {
    // court markings over the pavers
    float rr = length(world_pos.xz);
    float wr = fwidth(rr);
    float mark = 1.0 - smoothstep(0.09 - wr, 0.09 + wr, abs(rr - 9.5));
    float wz = fwidth(world_pos.z);
    mark = max(mark, (1.0 - smoothstep(0.07 - wz, 0.07 + wz, abs(world_pos.z))) * step(9.5, abs(world_pos.x)));
    mark *= 0.75 + 0.25 * step(0.35, vnoise(world_pos.xz * 6.0));
    if (world_normal.y > 0.5) base = mix(base, vec3(0.97, 0.96, 0.92), mark * 0.9);
  } else if (pattern > 3.5 && pattern < 4.5) {
    float edge = 1.0 - smoothstep(0.16, 0.2, min(fu.x, fsz.x - fu.x));
    if (world_normal.y > 0.5) { base = mix(base, vec3(0.93, 0.72, 0.12), edge * 0.95); rough = mix(rough, 0.6, edge); }
  } else if (pattern > 7.5 && pattern < 8.5) {
    float e = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
    float band = 1.0 - smoothstep(0.34, 0.36, e);
    float chev = step(0.5, fract((fu.x + fu.y) * 1.6));
    if (world_normal.y > 0.5) base = mix(base, mix(vec3(0.95, 0.76, 0.1), vec3(0.12), chev), band * step(0.05, e));
  } else if (pattern > 8.5 && pattern < 9.5) {
    float e = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
    float bed = smoothstep(0.24, 0.27, e) * step(0.5, world_normal.y);
    vec3 grass = vec3(0.32, 0.55, 0.22) * (0.8 + 0.35 * fbm(fu * 6.0));
    base = mix(base, grass, bed);
    rough = mix(rough, 0.95, bed);
    gTexStr *= 1.0 - bed;
  } else if (pattern > 9.5 && pattern < 10.5 && abs(world_normal.y) >= 0.5) {
      vec2 wp = world_pos.xz;
      float ax = abs(wp.x), az = abs(wp.y);
      float mw = fwidth(ax) + 1e-4;
      float dash = step(0.45, fract(az / 3.0));
      float lane = (1.0 - smoothstep(0.07 - mw, 0.07 + mw, abs(ax - 11.5))) * dash * step(4.0, az);
      float bay = (1.0 - smoothstep(0.05 - mw, 0.05 + mw, abs(fract((ax - 2.0) / 2.6) - 0.5) * 2.6)) * step(24.5, az) * step(az, 27.0) * step(ax, 8.0);
      float sx = wp.x * sign(wp.y);
      vec2 hz = vec2(sx - 4.0, az - 17.0);
      float inZone = step(abs(hz.x), 2.0) * step(abs(hz.y), 1.0);
      float hatch = step(0.5, fract((wp.x + wp.y) * 1.25)) * inZone;
      float border = inZone * (1.0 - step(abs(hz.x), 1.9) * step(abs(hz.y), 0.9));
      float wear = 0.9 + 0.1 * smoothstep(0.2, 0.5, vnoise(wp * 3.0));
      float paintM = clamp(lane + hatch * 0.9 + border, 0.0, 1.0) * wear;
      base = mix(base, vec3(0.95, 0.74, 0.18), paintM);
      base = mix(base, vec3(0.93, 0.93, 0.9), bay * wear);
      rough = mix(rough, 0.7, max(paintM, bay));
  }
  // ---- modelled detail (shader-only, no layout change) ----
  {
    int pid = int(pattern + 0.5);
    vec2 wp = world_pos.xz;
    float ef = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
    bool isTop = world_normal.y > 0.6;
    bool isWall = abs(world_normal.y) < 0.5;
    // floors: soft grime patches, sun-bleached warm areas and smoother traffic-polished patches (sheen at grazing sun)
    if (isTop && (pid == 1 || pid == 16 || pid == 10 || pid == 2 || pid == 8 || pid == 17 || pid == 19 || pid == 21)) {
      float m1 = vnoise(wp * 0.09 + 5.3), m2 = vnoise(wp * 0.31 + 1.7), m3 = vnoise(wp * 1.3);
      float grime = smoothstep(0.52, 0.86, m1 * 0.65 + m2 * 0.35);
      base *= 1.0 - 0.075 * grime * (0.7 + 0.3 * m3);
      base *= mix(vec3(1.0), vec3(1.025, 1.005, 0.965), smoothstep(0.42, 0.12, m1));
      rough = mix(rough, rough * 0.72, smoothstep(0.62, 0.9, m2) * 0.7);
    }
    // stone coping on exposed tops of walls / platforms / parapets, with a drip-groove shadow under the cap
    if (pid == 0 || pid == 2 || pid == 3 || pid == 13 || pid == 15 || pid == 16 || pid == 23) {
      float cop = 0.0, groove = 0.0;
      float cw = mix(0.2, 0.26, step(3.0, min(fsz.x, fsz.y)));
      if (isTop) {
        cop = min(fsz.x, fsz.y) < 1.15 ? 1.0 : 1.0 - smoothstep(cw - 0.008, cw + 0.008, ef);
        groove = (1.0 - smoothstep(0.004, 0.012, abs(ef - cw))) * step(1.15, min(fsz.x, fsz.y));
      } else if (isWall && face_flags.x > 0.5) {
        float dt = fsz.y - fu.y;
        cop = 1.0 - smoothstep(0.1, 0.108, dt);
        groove = 1.0 - smoothstep(0.005, 0.016, abs(dt - 0.118));
      }
      vec3 stone = vec3(0.9, 0.885, 0.845) * (0.95 + 0.07 * vnoise(fu * 9.0) + 0.03 * vnoise(fu * 41.0));
      base = mix(base, stone * texlibMacro(wp + world_pos.y * 0.7), cop);
      rough = mix(rough, 0.72, cop);
      gTexStr *= 1.0 - 0.8 * cop;
      base *= 1.0 - 0.28 * groove;
    }
    // ramps: anti-slip grooves across the slope
    if (pid == 4 && isTop) {
      vec3 Tt = normalize(face_tangent - world_normal * dot(face_tangent, world_normal)), Bb = cross(world_normal, Tt);
      vec2 up2 = vec2(Tt.y, Bb.y);
      float along = dot(fu, up2 / max(length(up2), 1e-4));
      float g = gridLine(along, 0.32, 0.016);
      base *= 1.0 - 0.2 * g;
      rough = mix(rough, 0.95, g);
    }
    // containers: rust streaks bleeding from the top rail and corners, dirt toward the bottom
    if (pid == 5 && isWall) {
      float st = vnoise(vec2(dot(wp, vec2(0.707)) * 5.5 + world_pos.x * 0.8, world_pos.y * 0.35));
      float fromTop = smoothstep(fsz.y * 0.25, fsz.y, fu.y);
      float rust = smoothstep(0.6, 0.92, st) * (0.35 + 0.65 * fromTop);
      rust = max(rust, (1.0 - smoothstep(0.05, 0.3, ef)) * smoothstep(0.45, 0.8, vnoise(fu * 3.0)) * 0.8);
      base = mix(base, vec3(0.42, 0.2, 0.1) * (0.8 + 0.4 * vnoise(fu * 11.0)), rust * 0.42);
      rough = mix(rough, 0.85, rust);
      base *= mix(0.84, 1.0, smoothstep(0.0, 0.7, fu.y));
    }
    // stairs / ramps: soft contact shadow along the stringers / kick plates / cheek walls the props put at both sides;
    // the stone stair is worn smoother and paler down its middle, the steel stair's plate polished along the walking line
    if (gStair.z > 0.5) {
      float e = min(gStair.x, gStair.y - gStair.x);
      float kind = gStair.z;
      float sw = kind < 1.5 ? 0.16 : (kind < 2.5 ? 0.3 : (kind < 3.5 ? 0.14 : 0.12));
      base *= 1.0 - (kind < 2.5 ? 0.26 : 0.2) * (1.0 - smoothstep(0.0, sw, e));
      float mid = 1.0 - smoothstep(0.18, 0.42, abs(gStair.x / max(gStair.y, 0.01) - 0.5));
      if (kind > 1.5 && kind < 2.5) { base *= 1.0 + 0.05 * mid; rough = mix(rough, rough * 0.78, mid); }
      if (kind < 1.5) rough = mix(rough, rough * 0.85, mid * (1.0 - gTexPaint));
    }
    // painted render / timber cladding: rain-washed grime streaks hanging from the top edge of each wall face
    if ((pid == 23 || pid == 22) && isWall) {
      float fromTop = fsz.y - fu.y;
      float st = 0.6 * vnoise(vec2(fu.x * 1.9, fromTop * 0.3 + 7.1)) + 0.4 * vnoise(vec2(fu.x * 6.3, fromTop * 0.8 + 2.3));
      float streak = smoothstep(0.5, 0.85, st) * exp(-fromTop * 0.75);
      base *= 1.0 - 0.2 * streak;
      rough = mix(rough, 0.9, streak * 0.6);
    }
    // boatyard: galvanised slot drain round the tug's wash-down bay (Alpha-half coordinates; the 180° twin follows)
    if (pid == 21 && isTop) {
      vec2 q = wp.y > 0.0 ? -wp : wp;
      vec2 d = abs(q - vec2(17.5, -18.4)) - vec2(4.4, 7.0);
      float sd = length(max(d, 0.0)) + min(max(d.x, d.y), 0.0);
      float e = abs(sd), aw = fwidth(e) + 1e-4;
      float chan = 1.0 - smoothstep(0.08 - aw, 0.08 + aw, e);
      float lip = (1.0 - smoothstep(0.105 - aw, 0.105 + aw, e)) * (1.0 - chan);
      float run = d.x > d.y ? q.y : q.x;
      float fw = fwidth(run) + 1e-5;
      float slot = smoothstep(0.3 - fw / 0.025, 0.3 + fw / 0.025, abs(fract(run / 0.025) - 0.5) * 2.0);
      float bar = mix(0.4, slot, clamp(0.025 / (fw * 4.0) - 0.5, 0.0, 1.0));
      base = mix(base, mix(vec3(0.025), vec3(0.34, 0.35, 0.36), bar), chan);
      base = mix(base, vec3(0.4, 0.41, 0.42) * (0.9 + 0.2 * fine), lip * 0.85);
      rough = mix(rough, 0.48, max(chan * bar, lip));
      gTexORM.b = mix(gTexORM.b, 0.75, max(chan * bar, lip));
      gTexStr *= 1.0 - max(chan, lip);
      base *= mix(vec3(1.0), vec3(0.94, 0.9, 0.87), step(sd, -0.105) * 0.8);   // the bay floor: darker, run-off stained
      // world-scale (non-repeating) oil drips and a worn service-lane wheel track beside the bay
      float oilW = smoothstep(0.68, 0.88, 0.65 * vnoise(q * 0.9 + 13.1) + 0.35 * vnoise(q * 3.1 + 2.7));
      base *= 1.0 - 0.26 * oilW * (1.0 - chan);
      rough = mix(rough, 0.62, oilW * 0.5);
      float tx = q.x - (12.15 + 0.25 * sin(q.y * 0.37));
      float track = (1.0 - smoothstep(0.1, 0.17, min(abs(tx - 0.85), abs(tx + 0.85)))) * step(q.y, -7.6) * (0.5 + 0.5 * vnoise(q * vec2(1.3, 0.35)));
      base *= 1.0 - 0.1 * track;
      rough = mix(rough, rough * 0.85, track);
    }
  }
  if (false) { if (pattern < 0.5) {   // legacy procedural chain below is compiled out of use
#else
  base *= 0.93 + 0.1 * big;
  if (pattern < 0.5) {
#endif
    // plain painted concrete
    base *= 0.97 + 0.05 * fine;
  } else if (pattern < 1.5) {
    // deck: 2 m concrete slabs with dark joints, tone per slab, speckle
    vec2 cell = floor(fu / 2.0);
    base *= 0.95 + 0.08 * h21(cell);
    float j = max(gridLine(fu.x, 2.0, 0.018), gridLine(fu.y, 2.0, 0.018));
    base *= 1.0 - 0.28 * j;
    base *= 0.96 + 0.06 * step(0.93, h21(floor(fu * 22.0)));
    // painted court markings: centre ring + halfway line (slightly worn)
    float rr = length(world_pos.xz);
    float wr = fwidth(rr);
    float mark = 1.0 - smoothstep(0.09 - wr, 0.09 + wr, abs(rr - 9.5));
    float wz = fwidth(world_pos.z);
    mark = max(mark, (1.0 - smoothstep(0.07 - wz, 0.07 + wz, abs(world_pos.z))) * step(9.5, abs(world_pos.x)));
    mark *= 0.75 + 0.25 * step(0.35, vnoise(world_pos.xz * 6.0));
    if (world_normal.y > 0.5) base = mix(base, vec3(0.97, 0.96, 0.92), mark * 0.9);
    rough = 0.86;
  } else if (pattern < 2.5) {
    // tiles: 0.5 m tiles with lighter grout
    vec2 cell = floor(fu / 0.5);
    base *= 0.94 + 0.09 * h21(cell + 3.1);
    float j = max(gridLine(fu.x, 0.5, 0.012), gridLine(fu.y, 0.5, 0.012));
    base = mix(base, base * 0.78 + 0.08, j);
    rough = 0.6;
  } else if (pattern < 3.5) {
    // concrete wall: formwork bands + tie holes + low grime
    float band = gridLine(fu.y, 1.2, 0.01);
    base *= 1.0 - 0.14 * band;
    vec2 tp = vec2(fract(fu.x / 1.2) - 0.5, fract(fu.y / 1.2 - 0.25) - 0.5) * 1.2;
    base *= 1.0 - 0.35 * (1.0 - smoothstep(0.02, 0.035, length(tp)));
    base *= 0.94 + 0.06 * smoothstep(0.0, 0.9, fu.y);
    rough = 0.9;
  } else if (pattern < 4.5) {
    // ramps: grip grooves + yellow safety edges
    float g = gridLine(fu.y, 0.35, 0.02);
    base *= 1.0 - 0.18 * g;
    float edge = 1.0 - smoothstep(0.16, 0.2, min(fu.x, fsz.x - fu.x));
    if (world_normal.y > 0.5) base = mix(base, vec3(0.93, 0.72, 0.12), edge * 0.95);
    rough = 0.75;
  } else if (pattern < 5.5) {
    // shipping container: vertical corrugation ribs
    float rib = sin(fu.x / 0.28 * 6.2831);
    gRib = rib;
    base *= 0.92 + 0.1 * rib;
    float frame = 1.0 - smoothstep(0.08, 0.1, min(min(fu.y, fsz.y - fu.y), min(fu.x, fsz.x - fu.x)));
    base = mix(base, base * 0.7, frame);
    base *= 0.95 + 0.07 * fbm(fu * vec2(3.0, 0.7));
    rough = 0.55;
  } else if (pattern < 6.5) {
    // wood planks
    float pl = gridLine(fu.y, 0.26, 0.008);
    float plank = floor(fu.y / 0.26);
    float grain = fbm(vec2(fu.x * 0.7 + h21(vec2(plank)) * 30.0, fu.y * 18.0));
    base *= 0.84 + 0.22 * grain;
    base *= 1.0 - 0.35 * pl;
    float frame = 1.0 - smoothstep(0.1, 0.12, min(min(fu.y, fsz.y - fu.y), min(fu.x, fsz.x - fu.x)));
    base = mix(base, base * 0.82, frame * step(fsz.x, 3.0) * step(fsz.y, 3.0));
    rough = 0.78;
  } else if (pattern < 7.5) {
    // metal railing: brushed + rivets
    base *= 0.92 + 0.08 * vnoise(vec2(fu.x * 40.0, fu.y * 1.5));
    vec2 rp = vec2(fract(fu.x / 0.8) - 0.5, fu.y - fsz.y + 0.12) * vec2(0.8, 1.0);
    base *= 1.0 - 0.3 * (1.0 - smoothstep(0.02, 0.03, length(rp)));
    rough = 0.45;
  } else if (pattern < 8.5) {
    // spawn deck: tiles + chevron hazard band around the edges
    vec2 cell = floor(fu / 0.6);
    base *= 0.95 + 0.06 * h21(cell + 7.7);
    float j = max(gridLine(fu.x, 0.6, 0.01), gridLine(fu.y, 0.6, 0.01));
    base *= 1.0 - 0.15 * j;
    float e = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
    float band = 1.0 - smoothstep(0.34, 0.36, e);
    float chev = step(0.5, fract((fu.x + fu.y) * 1.6));
    if (world_normal.y > 0.5) base = mix(base, mix(vec3(0.95, 0.76, 0.1), vec3(0.12), chev), band * step(0.05, e));
    rough = 0.65;
  } else if (pattern > 9.5 && pattern < 10.5) {
    if (abs(world_normal.y) < 0.5) {
      // slab edges / trench walls read as poured concrete
      base = base * 1.18 * (0.95 + 0.05 * fine);
      base *= 1.0 - 0.12 * gridLine(fu.y, 1.2, 0.01);
      rough = 0.9;
    } else {
      base *= 0.92 + 0.08 * vnoise(fu * 3.0) + 0.04 * (vnoise(fu * 37.0) - 0.5) * (1.0 - smoothstep(0.02, 0.06, length(fwidth(fu))));
      rough = 0.92;
      // container-yard markings (world space, symmetric under the map's 180° rotation)
      vec2 wp = world_pos.xz;
      float ax = abs(wp.x), az = abs(wp.y);
      float mw = fwidth(ax) + 1e-4;
      // dashed yellow lane dividers at x = ±11.5
      float dash = step(0.45, fract(az / 3.0));
      float lane = (1.0 - smoothstep(0.07 - mw, 0.07 + mw, abs(ax - 11.5))) * dash * step(4.0, az);
      // white bay lines beside the base containers
      float bay = (1.0 - smoothstep(0.05 - mw, 0.05 + mw, abs(fract((ax - 2.0) / 2.6) - 0.5) * 2.6)) * step(24.5, az) * step(az, 27.0) * step(ax, 8.0);
      // hatched safety zone at the foot of each central ramp
      float sx = wp.x * sign(wp.y);           // 180°-rotation-symmetric x (ramps sit at x=-4,z<0 and x=+4,z>0)
      vec2 hz = vec2(sx - 4.0, az - 17.0);
      float inZone = step(abs(hz.x), 2.0) * step(abs(hz.y), 1.0);
      float hatch = step(0.5, fract((wp.x + wp.y) * 1.25)) * inZone;
      float border = inZone * (1.0 - step(abs(hz.x), 1.9) * step(abs(hz.y), 0.9));
      float wear = 0.9 + 0.1 * smoothstep(0.2, 0.5, vnoise(wp * 3.0));
      base = mix(base, vec3(0.95, 0.74, 0.18), clamp(lane + hatch * 0.9 + border, 0.0, 1.0) * wear);
      base = mix(base, vec3(0.93, 0.93, 0.9), bay * wear);
    }
  } else if (pattern > 10.5 && pattern < 11.5) {
    // painted steel panels: 1.2 m panels with seams + bolt rows
    float seam = max(gridLine(fu.x, 1.2, 0.008), gridLine(fu.y, 1.2, 0.008));
    base *= 1.0 - 0.22 * seam;
    base *= 0.95 + 0.06 * fbm(fu * 1.3);
    rough = 0.5;
  } else if (pattern > 11.5 && pattern < 12.5) {
    base *= 0.9;
    rough = 0.45;
  } else if (pattern > 15.5 && pattern < 16.5) {
    // pavers: 2 m slabs
    vec2 cell = floor(fu / 2.0);
    base *= 0.95 + 0.07 * h21(cell + 1.3);
    float j = max(gridLine(fu.x, 2.0, 0.02), gridLine(fu.y, 2.0, 0.02));
    base *= 1.0 - 0.25 * j;
    rough = 0.84;
  } else if (pattern > 12.5) {
    base *= 0.95 + 0.05 * fine;
    rough = 0.7;
  } else {
    // planter: stone rim with grass bed on top
    float e = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
    float bed = smoothstep(0.24, 0.27, e) * step(0.5, world_normal.y);
    vec3 grass = vec3(0.32, 0.55, 0.22) * (0.8 + 0.35 * fbm(fu * 6.0));
    base = mix(base * (0.95 + 0.05 * fine), grass, bed);
    rough = mix(0.8, 0.95, bed);
  }
#ifdef USE_TEXLIB
  }
#endif
  // murals / signage
  if (face_flags.z > -0.5) {
    // atlas rect (mA) + placement on the face in metres (mB: x0, xLen, y0, yLen; xLen < 0 = strip repeating every
    // -xLen face heights, yLen <= 0 = full face height) + weathering (mC: surface shows through, paint damage cuts it)
    int mi = int(face_flags.z + 0.5);
    vec4 mA = mural_rect[mi], mB = mural_place[mi];
    vec2 mC = mural_fx[mi];
    float my = mB.w > 0.0 ? (fu.y - mB.z) / mB.w : fu.y / fsz.y;
    float mx = mB.y < 0.0 ? fu.x / (-mB.y * fsz.y) : clamp((fu.x - mB.x) / mB.y, 0.0005, 0.9995);
    vec2 muv = vec2(mA.x + mA.y * mx, mA.z + mA.w * clamp(my, 0.004, 0.996));
    vec4 mc = texture(mural_atlas, vec2(muv.x, 1.0-muv.y));
    mc.rgb *= mix(vec3(1.0), gTexMod, mC.x);
    mc.a *= mix(1.0, gTexPaint, mC.y);
    base = mix(base, mc.rgb * (0.92 + 0.1 * big), mc.a * 0.96);
  }
  // crisp modelled edges: thin bright chamfer + soft inner shadow
  float e = min(min(fu.x, fsz.x - fu.x), min(fu.y, fsz.y - fu.y));
  float ew = fwidth(e);
  // (edges are real bevel geometry now; the old painted chamfer lines drew seams where faces stack)
  // contact darkening at the foot of walls that stand on something
  if (face_flags.x > 0.5 && face_flags.y > 0.5) {
    base *= mix(0.55, 1.0, smoothstep(0.0, 0.85, fu.y));
  }
