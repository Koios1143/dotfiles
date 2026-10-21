#version 300 es
// Color vision deficiency simulation (Machado et al. 2009, severity 1.0), applied in linear RGB
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;

vec3 toLinear(vec3 c) { return mix(c / 12.92, pow((c + 0.055) / 1.055, vec3(2.4)), step(0.04045, c)); }
vec3 toSrgb(vec3 c) { return mix(c * 12.92, 1.055 * pow(c, vec3(1.0 / 2.4)) - 0.055, step(0.0031308, c)); }

void main() {
    vec4 px = texture(tex, v_texcoord);
    const mat3 M = mat3(0.367322, 0.860646, -0.227968,  0.280085, 0.672501, 0.047413,  -0.011820, 0.042940, 0.968881);
    vec3 lin = clamp(toLinear(px.rgb) * M, 0.0, 1.0);
    fragColor = vec4(toSrgb(lin), px.a);
}
