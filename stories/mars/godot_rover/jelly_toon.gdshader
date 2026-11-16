// Jelly toon shader: hard comic shadow band + candy highlight + translucent rim.
// Godot 4.x, identical result in Compatibility, Mobile and Forward+.
//
// Colors are exact: the surface shows shadow_color where no light reaches it
// and base_color where it is lit. Light color and energy are ignored on
// purpose (classic cel shading), only direction and shadows matter.
//
// Implementation note: light() only outputs 0..1 masks and the color travels
// through ALBEDO / EMISSION. Writing colors into DIFFUSE_LIGHT directly comes
// out too bright in the Compatibility renderer.
shader_type spatial;
render_mode ambient_light_disabled;

uniform vec3 base_color : source_color = vec3(1.0, 0.38, 0.62);
uniform vec3 shadow_color : source_color = vec3(0.6, 0.15, 0.45);
uniform vec3 rim_color : source_color = vec3(1.0, 0.8, 0.9);

uniform float shadow_threshold : hint_range(0.0, 1.0) = 0.12;  // shadow -> base cut
uniform float band_softness : hint_range(0.001, 0.2) = 0.01;   // edge anti-aliasing
uniform float gloss : hint_range(0.0, 1.0) = 1.0;              // highlight strength
uniform float gloss_power : hint_range(1.0, 256.0) = 48.0;     // higher = smaller highlight
uniform float rim_amount : hint_range(0.0, 1.0) = 0.45;        // fake SSS rim strength
uniform float rim_width : hint_range(0.0, 1.0) = 0.82;         // lower = wider rim

void fragment() {
	// Unlit floor (shadow color + rim) comes from EMISSION; light() adds the rest.
	ALBEDO = max(base_color - shadow_color, vec3(0.0));
	METALLIC = 0.0;
	SPECULAR = 0.0;
	ROUGHNESS = 1.0;
	float facing = 1.0 - clamp(dot(NORMAL, VIEW), 0.0, 1.0);
	float rim = smoothstep(rim_width - band_softness, rim_width + band_softness, facing) * rim_amount;
	EMISSION = mix(shadow_color, rim_color, rim);
}

void light() {
	float ndl = dot(NORMAL, LIGHT);
	float lit = clamp(ndl, 0.0, 1.0) * ATTENUATION;
	float band = smoothstep(shadow_threshold - band_softness, shadow_threshold + band_softness, lit);
	DIFFUSE_LIGHT = max(DIFFUSE_LIGHT, vec3(band));

	vec3 h = normalize(VIEW + LIGHT);
	float spec = pow(max(dot(NORMAL, h), 0.0), gloss_power) * ATTENUATION * step(0.0, ndl);
	float hard = smoothstep(0.5 - band_softness, 0.5 + band_softness, spec) * gloss;
	SPECULAR_LIGHT = max(SPECULAR_LIGHT, vec3(hard));
}
