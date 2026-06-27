shader_type canvas_item;

uniform float reveal : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec2 uv = UV - vec2(0.5);
	float angle = atan(uv.y, uv.x);
	angle = -angle + 3.14159 * 0.5;
	angle = mod(angle, 6.28318);
	float norm = angle / 6.28318;
	float covered = step(reveal, norm);
	COLOR.a *= covered;
}
