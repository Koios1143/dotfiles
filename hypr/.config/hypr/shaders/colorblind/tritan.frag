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
    const mat3 M = mat3(1.255528, -0.076749, -0.178779,  -0.078411, 0.930809, 0.147602,  0.004733, 0.691367, 0.303900);
    vec3 lin = clamp(toLinear(px.rgb) * M, 0.0, 1.0);
    fragColor = vec4(toSrgb(lin), px.a);
}
