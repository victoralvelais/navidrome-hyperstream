#include <flutter/runtime_effect.glsl>

uniform vec2 uSize;
uniform float uRadius;
uniform float uScale;
uniform sampler2D uInput;
out vec4 fragColor;

float roundedDistance(vec2 p, vec2 halfSize, float radius) {
  vec2 q = abs(p) - halfSize + radius;
  return min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
}

void main() {
  vec2 pixel = FlutterFragCoord().xy;
  vec2 halfSize = uSize * 0.5;
  vec2 p = pixel - halfSize;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  float d = roundedDistance(p, halfSize, radius);
  float edge = 1.0 - smoothstep(0.0, 12.0 * uScale, -d);
  vec2 gradient = vec2(
    roundedDistance(p + vec2(1.0, 0.0), halfSize, radius) - d,
    roundedDistance(p + vec2(0.0, 1.0), halfSize, radius) - d
  );
  vec2 normal = gradient / max(length(gradient), 0.001);
  vec2 uv = (pixel - normal * sin(edge * 3.14159265) * 6.0 * uScale) / uSize;
#ifdef IMPELLER_TARGET_OPENGLES
  uv.y = 1.0 - uv.y;
#endif
  vec4 color = texture(uInput, clamp(uv, vec2(0.0), vec2(1.0)));
  float glint = pow(edge, 7.0) * (0.06 + 0.12 * max(0.0, dot(normal, normalize(vec2(-1.0, -1.0)))));
  fragColor = vec4(mix(color.rgb, vec3(color.a), glint), color.a);
}
