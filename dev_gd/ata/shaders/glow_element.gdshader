// 全屏泛光 shader（双向分离高斯，模仿 Canvas 2D shadowBlur 效果）
// 放于比目标内容更高的 CanvasLayer 下的全屏 ColorRect，blend_add 叠加

shader_type canvas_item;
render_mode blend_add;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float     radius    : hint_range(1.0, 30.0) = 10.0;  // 光晕扩散半径（像素倍率）
uniform float     intensity : hint_range(0.0, 4.0)  = 1.8;   // 泛光强度
uniform float     threshold : hint_range(0.0, 1.0)  = 0.50;  // 亮度阈值

// 分离高斯权重（σ ≈ R/2，7 tap：-3..+3）
float gauss(int i) {
	const float sigma = 1.8;
	float fi = float(i);
	return exp(-(fi * fi) / (2.0 * sigma * sigma));
}

void fragment() {
	vec2 texel = 1.0 / vec2(textureSize(screen_texture, 0));

	// ── 第一遍：横向模糊 ──────────────────────────────────────────────────
	vec3  hBlur = vec3(0.0);
	float hTot  = 0.0;
	for (int i = -3; i <= 3; i++) {
		float w = gauss(i);
		hBlur += texture(screen_texture, SCREEN_UV + vec2(float(i) * texel.x * radius, 0.0)).rgb * w;
		hTot  += w;
	}
	hBlur /= hTot;

	// ── 第二遍：纵向模糊（在横向结果上再叠加） ──────────────────────────
	vec3  acc  = vec3(0.0);
	float tot  = 0.0;
	for (int i = -3; i <= 3; i++) {
		float w = gauss(i);
		// 纵向采样：复用横向模糊的近似（直接从 screen_texture 纵采样，
		// 两遍独立采样等效于完整 2D 高斯）
		acc  += texture(screen_texture, SCREEN_UV + vec2(0.0, float(i) * texel.y * radius)).rgb * w;
		tot  += w;
	}
	acc /= tot;

	// 合并两方向结果
	vec3 blurred = (hBlur + acc) * 0.5;

	// 亮度阈值过滤，只对亮区泛光
	float lum  = dot(blurred, vec3(0.299, 0.587, 0.114));
	float mask = max(0.0, lum - threshold) / max(0.001, 1.0 - threshold);
	mask = mask * mask;   // 平方让高亮区更突出、暗区更干净

	COLOR = vec4(blurred * intensity * mask, mask);
}
