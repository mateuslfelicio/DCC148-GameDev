shader_type canvas_item;

uniform float progress : hint_range(0.0, 1.0) = 0.0;
uniform vec4 color : source_color = vec4(0.0, 0.0, 0.0, 1.0);
uniform float softness : hint_range(0.01, 0.5) = 0.15;
uniform bool reverse = false;

void fragment() {
    // 0.0 no canto superior esquerdo, 1.0 no inferior direito
    float d = (UV.x + UV.y) * 0.5;

    // a borda vai de 0 até 1 + softness, então no fim cobre tudo
    float edge = progress * (1.0 + softness);
    float a = clamp((edge - d) / softness, 0.0, 1.0);

    if (reverse) a = 1.0 - a;

    COLOR = vec4(color.rgb, a * color.a);
}