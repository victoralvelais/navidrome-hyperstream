#include <flutter/runtime_effect.glsl>

// Local logical coordinates: this is an alpha mask, not a backdrop filter.
uniform vec2 uSize;
uniform float uRadius;
uniform float uFeather;
out vec4 fragColor;

void main() {
  vec2 halfSize = uSize * 0.5;
  float radius = min(uRadius, min(halfSize.x, halfSize.y));
  vec2 q = abs(FlutterFragCoord().xy - halfSize) - halfSize + radius;
  float distance = min(max(q.x, q.y), 0.0) + length(max(q, 0.0)) - radius;
  float feather = min(uFeather, min(halfSize.x, halfSize.y) * 0.8);
  float alpha = smoothstep(0.0, max(feather, 0.001), -distance);
  fragColor = vec4(alpha);
}
