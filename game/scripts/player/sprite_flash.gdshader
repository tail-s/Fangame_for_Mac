shader_type canvas_item;
// Hit flash / charge tint for character sprites: blends the sprite towards `tint`.

uniform vec4 tint : source_color = vec4(1.0);
uniform float amount : hint_range(0.0, 1.0) = 0.0;

void fragment() {
	vec4 c = texture(TEXTURE, UV) * COLOR;
	c.rgb = mix(c.rgb, tint.rgb, amount);
	COLOR = c;
}
