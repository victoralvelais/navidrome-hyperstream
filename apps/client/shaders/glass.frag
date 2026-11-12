#include <flutter/runtime_effect.glsl>

// Impeller supplies input dimensions; bounds describe the actual control in
// physical render-target coordinates. A clipped backdrop can be screen-sized.
uniform vec2 uSize;
uniform vec4 uBounds;
uniform float uRadius;
uniform float uScale;
uniform float uSoftness;
uniform sampler2D uInput;
out vec4 fragColor;

float roundedDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

vec4 sampleBackdrop(vec2 pixel) {
  vec2 uv = pixel / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  return texture(uInput, clamp(uv, vec2(0.0), vec2(1.0)));
}

// Project every refracted/blurred tap into the rounded surface, with a half-pixel
// inset. Adjacent rows and controls must not bleed into its rim or corners.
vec2 surfaceSample(vec2 pixel, vec2 center, vec2 halfSize, float radius) {
  vec2 safeHalf = max(halfSize - vec2(0.5), vec2(0.0));
  float safeRadius = clamp(radius - 0.5, 0.0, min(safeHalf.x, safeHalf.y));
  vec2 core = safeHalf - vec2(safeRadius);
  vec2 local = pixel - center;
  vec2 nearest = clamp(local, -core, core);
  vec2 delta = local - nearest;
  return center + nearest + delta * min(1.0, safeRadius / max(length(delta), 0.001));
}

float gaussianWeight(int offset) {
  if (offset == 0) return 6.0;
  if (offset == -1 || offset == 1) return 4.0;
  return 1.0;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 halfSize = uBounds.zw * 0.5;
  vec2 p = pixel - uBounds.xy - halfSize;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  float d = roundedDistance(p, halfSize, radius);
  // ImageFilter can process more than the final Flutter clip. Never alter that
  // exterior: the old max(0, -d) gave every exterior pixel maximum refraction.
  if (d >= 0.0) {
    fragColor = sampleBackdrop(pixel);
    return;
  }
  float inside = max(0.0, -d);
  float epsilon = max(0.5, uScale * 0.5);
  vec2 gradient = vec2(
    roundedDistance(p + vec2(epsilon, 0.0), halfSize, radius) -
      roundedDistance(p - vec2(epsilon, 0.0), halfSize, radius),
    roundedDistance(p + vec2(0.0, epsilon), halfSize, radius) -
      roundedDistance(p - vec2(0.0, epsilon), halfSize, radius)
  );
  vec2 normal = gradient / max(length(gradient), 0.001);
  float bevel = min(8.0 * uScale, min(halfSize.x, halfSize.y) * 0.35);
  float t = clamp(inside / max(bevel, 0.001), 0.0, 1.0);
  // Quarter-circle lens: strong displacement at the lip, smoothly returning
  // to the unwarped center. The folded rim creates a distinct inner edge.
  float profile = 1.0 - sqrt(max(0.0, 1.0 - (1.0 - t) * (1.0 - t)));
  float depth = min(8.0 * uScale, min(halfSize.x, halfSize.y) * 0.3);
  vec2 refracted = pixel - normal * profile * depth;
  float soften = uSoftness * (0.35 + 0.65 * smoothstep(0.0, 1.0, t));
  vec2 center = uBounds.xy + halfSize;
  // A small normalized Gaussian kernel diffuses text instead of producing the
  // distinct copies of the previous five widely spaced, cross-shaped samples.
  vec4 color = vec4(0.0);
  for (int y = -2; y <= 2; y++) {
    for (int x = -2; x <= 2; x++) {
      vec2 tap = surfaceSample(refracted + vec2(float(x), float(y)) * soften,
                               center, halfSize, radius);
      color += sampleBackdrop(tap) * gaussianWeight(x) * gaussianWeight(y) / 256.0;
    }
  }
  float edge = 1.0 - smoothstep(0.0, 4.0 * uScale, inside);
  float lighting = dot(normal, normalize(vec2(-0.7, -1.0)));
  color.rgb *= 1.0 - edge * 0.12 * max(0.0, -lighting);
  color.rgb = mix(color.rgb, vec3(color.a), edge * 0.15 * max(0.0, lighting));
  fragColor = color;
}
