shader_type canvas_item;
// CanvasGroup shader for enemies, bosses and their shots: turns the flat vector
// drawing into the same pixel-art look as the baked character sprites.
//   - 1 px dark outline around solid shapes
//   - edge bevel: a pixel whose upper neighbour is a different colour region gets
//     the light tone, one whose lower neighbour differs gets the shadow tone
//   - darker inner line where a region meets another on its left / right
// Translucent pixels (telegraphs, glows, frozen overlay) pass through untouched.
// Pre-shaded art (baked sprites, which already have outlines) opts out by being
// drawn at alpha ~0.98 (PRESHADED): it passes through and gets no extra outline.
// Works per game pixel because the 2D canvas renders at 384x216 and is scaled up.

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_nearest;
uniform vec4 outline_color : source_color = vec4(0.05, 0.08, 0.16, 1.0);
uniform float solid = 0.8;
uniform float edge = 0.09;
const float PRE_LO = 0.95;
const float PRE_HI = 0.992;

bool preshaded(vec4 c) {
	return c.a >= PRE_LO && c.a < PRE_HI;
}

bool outlines(vec4 c) {
	return c.a >= solid && !preshaded(c);
}

vec4 px(vec2 uv) {
	vec4 c = textureLod(screen_texture, uv, 0.0);
	if (c.a > 0.0001) {
		c.rgb /= c.a;
	}
	return c;
}

bool differs(vec4 a, vec4 b) {
	if (b.a < solid) {
		return true;
	}
	vec3 d = abs(a.rgb - b.rgb);
	return d.r + d.g + d.b > edge * 3.0;
}

void fragment() {
	vec2 d = SCREEN_PIXEL_SIZE;
	vec4 c = px(SCREEN_UV);
	vec4 up = px(SCREEN_UV + vec2(0.0, -d.y));
	vec4 dn = px(SCREEN_UV + vec2(0.0, d.y));
	vec4 lf = px(SCREEN_UV + vec2(-d.x, 0.0));
	vec4 rt = px(SCREEN_UV + vec2(d.x, 0.0));
	if (preshaded(c)) {
		COLOR = vec4(c.rgb, 1.0);
	} else if (c.a < solid) {
		if (outlines(up) || outlines(dn) || outlines(lf) || outlines(rt)) {
			COLOR = outline_color;
		} else {
			COLOR = c;
		}
	} else {
		vec3 col = c.rgb;
		float lum = dot(col, vec3(0.299, 0.587, 0.114));
		if (differs(c, up)) {
			col = mix(col, vec3(1.0, 0.98, 0.92), 0.32);
		} else if (differs(c, dn)) {
			col = col * vec3(0.62, 0.64, 0.78);
		} else if ((differs(c, lf) && lf.a >= solid && dot(lf.rgb, vec3(0.299, 0.587, 0.114)) > lum)
				|| (differs(c, rt) && rt.a >= solid && dot(rt.rgb, vec3(0.299, 0.587, 0.114)) > lum)) {
			col = col * 0.72;
		}
		COLOR = vec4(col, 1.0);
	}
}
