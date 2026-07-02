shader_type canvas_item;

uniform sampler2D SCREEN_TEXTURE : hint_screen_texture, filter_linear_mipmap;
uniform float blur_lod : hint_range(0.0, 8.0) = 4.0;

void fragment() {
	COLOR = textureLod(SCREEN_TEXTURE, SCREEN_UV, blur_lod);
}
