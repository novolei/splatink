  vec2 slope = gInkD;

  if (gInk > 0.01) {
    // gel micro-surface: soft swells so reflections break into wet highlights. Mip-filtered (fades to flat by itself
    // at distance). Walls stretch it vertically. Fresh ink is smoother (surface tension) and sways very gently while it
    // settles; dry ink shows a little more texture.
    vec2 gp = UV * (abs(world_normal.y) < 0.5 ? vec2(0.9, 0.42) : vec2(0.75));
    float fr2 = gFresh * gFresh;
    gp += vec2(clock * 0.011, -clock * 0.007) + fr2 * 0.022 * vec2(sin(clock * 2.3), cos(clock * 1.9));
#ifdef USE_TEXLIB
    if (gel_layer >= 0.0) {
      vec2 gx = dFdx(gp), gy = dFdy(gp);
      vec3 gn = textureGrad(t_normal, vec3(gp, gel_layer), gx, gy).xyz * 2.0 - 1.0;
      slope += -gn.xy / max(gn.z, 0.3) * (0.95 - 0.5 * gFresh) * gInk * gInkS;
    }
#else
    {
      const float e = 0.06;
      vec2 q = gp * 2.2;
      float hx = vnoise(q + vec2(e, 0.0)) - vnoise(q - vec2(e, 0.0));
      float hy = vnoise(q + vec2(0.0, e)) - vnoise(q - vec2(0.0, e));
      float gf = 1.0 - smoothstep(0.03, 0.12, length(fwidth(world_pos)));
      slope += vec2(hx, hy) / (2.0 * e) * 0.035 * gf * gInk;
    }
#endif
  }
#ifndef USE_TEXLIB
  if (face_data.x > 4.5 && face_data.x < 5.5) {
    // corrugation on containers (only where not inked), analytic derivative
    slope.x += (1.0 - gInk) * -sin(UV.x / 0.28 * 6.2831) * 0.35;
  }
#endif
  vec3 T = normalize(face_tangent - world_normal * dot(face_tangent, world_normal));
  vec3 Bt = cross(world_normal, T);
  if (gInk > 0.01) {
    // swim wakes: the ink itself ripples where a squid swims. Each trail segment sheds an expanding ripple (a stadium
    // around the path — their envelope opens into the V-wake) and the submerged body pushes up a glossy mound with a
    // small bow ridge at speed. Height field → analytic gradient in the face's tangent plane.
    vec3 wS = vec3(0.0); float wG = 0.0;
    for (int s = 0; s < 4; s++) {
      vec4 Bd = wake_bounds[s];
      if (Bd.w <= 0.0 || distance(world_pos, Bd.xyz) > Bd.w) continue;
      for (int i = 0; i < 11; i++) {
        vec4 A0 = wake_points[s * 12 + i], A1 = wake_points[s * 12 + i + 1];
        if (A0.w < -1.0 || A1.w < -1.0) continue;
        vec3 ab = A1.xyz - A0.xyz;
        float t = clamp(dot(world_pos - A0.xyz, ab) / max(dot(ab, ab), 1e-6), 0.0, 1.0);
        float age = clock - mix(A0.w, A1.w, t);
        if (age <= 0.0 || age > 1.15) continue;
        vec3 D = world_pos - (A0.xyz + ab * t);
        D -= world_normal * dot(D, world_normal);
        float d = length(D);
        float r = 0.1 + age * 0.95, w = 0.075 + age * 0.085;
        float x = d - r;
        float env = exp(-x * x / (w * w));
        if (env < 0.003) continue;
        float fade = 1.0 - age / 1.15;
        fade *= fade * smoothstep(0.0, 0.05, age);
        float amp = 0.0135 * fade;
        float dh = amp * env * (-2.0 * x / (w * w) * cos(x * 25.0) - 25.0 * sin(x * 25.0));
        wS += D * (dh / max(d, 1e-4));
        wG += env * fade * 0.6;
      }
      vec4 H = swimmers[s], F = swimmer_dirs[s];
      if (H.w > 0.002) {
        vec3 D = world_pos - H.xyz;
        D -= world_normal * dot(D, world_normal);
        vec3 Fp = F.xyz - world_normal * dot(F.xyz, world_normal);
        float fl = length(Fp);
        Fp = fl > 1e-3 ? Fp / fl : T;
        float al = dot(D, Fp);
        vec3 Cv = D - Fp * al;
        float ac = length(Cv);
        vec3 Cn = Cv / max(ac, 1e-4);
        // mound over the body (sits a touch behind the head, stretches with speed)
        float am = al + 0.1, La = 0.3 + 0.2 * F.w, Lc = 0.19;
        float hm = 0.05 * H.w * exp(-(am * am) / (La * La) - (ac * ac) / (Lc * Lc));
        // bow ridge pushed ahead of the head
        float ab2 = al - 0.3, hb = 0.022 * H.w * F.w * exp(-(ab2 * ab2) / 0.012 - (ac * ac) / 0.07);
        wS += Fp * (-2.0 * am / (La * La) * hm - 2.0 * ab2 / 0.012 * hb) + Cn * (-2.0 * ac / (Lc * Lc) * hm - 2.0 * ac / 0.07 * hb);
        wG += hm * 16.0 + hb * 20.0;
      }
    }
    // clamp the slope so crests never flip the normal; fade with distance like the gel (no shimmer on far floors)
    float wl = length(wS);
    if (wl > 0.9) wS *= 0.9 / wl;
    float wFar = 1.0 - smoothstep(0.05, 0.16, length(fwidth(world_pos)));
    slope += vec2(dot(wS, T), dot(wS, Bt)) * gInk * wFar;
    gWake = clamp(wG, 0.0, 1.0) * gInk * wFar;
  }

  if (gInk > 0.01) {
    // ripples: a wave packet runs out from every impact / footstep / dive, thinning as it spreads; the crests catch
    // the light (glossier). Height field → analytic gradient in the face plane.
    vec3 rS = vec3(0.0); float rG = 0.0;
    for (int i = 0; i < 24; i++) {
      vec4 Pr = ripples[i], Qr = ripple_params[i];
      float age = clock - Pr.w;
      if (age <= 0.0 || age >= Qr.w) continue;
      vec3 D = world_pos - Pr.xyz;
      float off = dot(D, world_normal);
      if (abs(off) > 0.4) continue;                          // another surface
      D -= world_normal * off;
      float front = Qr.z * age;
      float d = length(D);
      float x = d - front;
      float sg = Qr.y * 0.8;
      if (x > sg * 3.0 || x < -Qr.y * 4.0) continue;
      float env = exp(-x * x / (sg * sg));
      float k = 6.2831853 / Qr.y;
      float fade = 1.0 - age / Qr.w;
      fade *= fade * smoothstep(0.0, 0.03, age);
      float amp = Qr.x * fade / (1.0 + d * 1.6);
      float dh = amp * env * (-2.0 * x / (sg * sg) * cos(k * x) - k * sin(k * x));
      rS += D * (dh / max(d, 1e-4));
      rG += env * fade * min(Qr.x * 90.0, 1.0);
    }
    float rl = length(rS);
    if (rl > 0.75) rS *= 0.75 / rl;
    float rFar = 1.0 - smoothstep(0.05, 0.18, length(fwidth(world_pos)));
    slope += vec2(dot(rS, T), dot(rS, Bt)) * gInk * rFar;
    gWake = max(gWake, clamp(rG * 0.5, 0.0, 1.0) * gInk * rFar);
  }
  vec3 nBase = world_normal;
#ifdef USE_TEXLIB
  // surface relief from the texture library; ink fills the grooves so the relief fades out under it
  // (on corrugated metal the ink still follows the ribs)
  float keep = max((face_data.x > 4.5 && face_data.x < 5.5) ? 0.55 : 0.0, gTexKeep);   // containers + stairs
  nBase = texlibPerturbNormal(gTexN, T, Bt, world_normal, gTexStr * (1.0 - gInk * (1.0 - max(keep, gInkKeep))));
#endif
  vec3 wn = normalize(nBase - slope.x * T - slope.y * Bt);

NORMAL=normalize(mat3(VIEW_MATRIX)*wn);
