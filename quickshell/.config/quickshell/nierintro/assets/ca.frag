#version 440

// The lens distortion the footage ramps in while the lattice is drawn.
//
// Both effects are radial and share the same geometry: everything is sampled
// along the line from the screen centre through the pixel, so the smear and
// the colour fringing both grow with distance from the centre and vanish in
// the middle of the frame.
//
//   radialAmount - scale spread swept by the taps (the zoom blur)
//   caAmount     - extra scale offset for red (outward) and blue (inward)

layout(location = 0) in vec2 qt_TexCoord0;
layout(location = 0) out vec4 fragColor;

layout(std140, binding = 0) uniform buf {
    mat4 qt_Matrix;
    float qt_Opacity;
    float caAmount;
    float radialAmount;
};

layout(binding = 1) uniform sampler2D source;

const int TAPS = 9;

void main() {
    vec2 dir = qt_TexCoord0 - vec2(0.5);

    vec3 acc = vec3(0.0);
    for (int i = 0; i < TAPS; i++) {
        float t = (float(i) / float(TAPS - 1) - 0.5) * radialAmount;
        acc.r += texture(source, vec2(0.5) + dir * (1.0 + t + caAmount)).r;
        acc.g += texture(source, vec2(0.5) + dir * (1.0 + t)).g;
        acc.b += texture(source, vec2(0.5) + dir * (1.0 + t - caAmount)).b;
    }
    acc /= float(TAPS);

    fragColor = vec4(acc, texture(source, qt_TexCoord0).a) * qt_Opacity;
}
