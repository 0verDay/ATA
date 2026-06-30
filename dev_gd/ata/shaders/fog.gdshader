shader_type canvas_item;

uniform sampler2D fog_mask : filter_linear;

void fragment() {
	float visible = texture(fog_mask, UV).r;
	COLOR = vec4(0.0, 0.0, 0.0, (1.0 - visible) * 0.82);
}
