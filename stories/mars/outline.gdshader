shader_type spatial;
render_mode unshaded, cull_front, shadows_disabled;

uniform vec4 ink_color : source_color = vec4(0.035,0.008,0.025,1.0);
uniform float outline_width : hint_range(0.0,0.3) = 0.045;
uniform bool radial_normals = false;

void vertex() {
    // Radial expansion keeps the duplicated flat rock faces joined at the hull.
    vec3 extrusion = radial_normals ? normalize(VERTEX) : NORMAL;
    VERTEX += extrusion*outline_width;
}
void fragment() { ALBEDO = ink_color.rgb; }
