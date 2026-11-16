shader_type spatial;
render_mode cull_back;

// Dense candy: opaque depth and stable collision, with wrap/translucency cues.
uniform vec4 low_color : source_color = vec4(0.24, 0.018, 0.045, 1.0);
uniform vec4 soil_color : source_color = vec4(0.84, 0.18, 0.085, 1.0);
uniform vec4 high_color : source_color = vec4(1.0, 0.40, 0.22, 1.0);
uniform vec4 rock_color : source_color = vec4(0.72, 0.035, 0.12, 1.0);
uniform bool is_rock = false;
uniform float roughness : hint_range(0.05, 0.6) = 0.22;
uniform float gloss_strength : hint_range(0.0, 3.0) = 1.7;
uniform float wrap_amount : hint_range(0.0, 0.8) = 0.25;
uniform float subsurface_strength : hint_range(0.0, 1.0) = 0.10;
uniform float ink_strength : hint_range(0.0, 0.3) = 0.08;
uniform float height_min = -5.0;
uniform float height_max = 6.0;
varying vec3 world_position;
varying vec3 world_normal;

void vertex() {
    world_position = (MODEL_MATRIX * vec4(VERTEX, 1.0)).xyz;
    world_normal = normalize(MODEL_NORMAL_MATRIX * NORMAL);
}

void fragment() {
    float altitude = clamp((world_position.y - height_min) / max(height_max-height_min,0.01), 0.0, 1.0);
    float slope = 1.0 - max(normalize(world_normal).y, 0.0);
    vec3 pigment = mix(low_color.rgb, soil_color.rgb, smoothstep(0.02,0.65,altitude));
    pigment = mix(pigment,high_color.rgb,smoothstep(0.55,1.0,altitude)*0.65);
    pigment = mix(pigment, low_color.rgb, slope*0.23);
    if (is_rock) {
        pigment = mix(rock_color.rgb,high_color.rgb,altitude*0.20);
    }
    // World-anchored, antialiased printed dots. No screen-space sliding.
    vec2 cell = fract(world_position.xz*1.35)-0.5;
    float distance_to_dot = length(cell);
    float aa = max(fwidth(distance_to_dot),0.025);
    float dots = 1.0-smoothstep(0.10-aa,0.10+aa,distance_to_dot);
    pigment *= 1.0-dots*ink_strength;
    ALBEDO = pigment;
    ROUGHNESS = roughness;
    SPECULAR = 0.9;
    METALLIC = 0.0;
    CLEARCOAT = 0.6;
    CLEARCOAT_ROUGHNESS = 0.12;
    // Nocturne uses Compatibility: rim and wrap lighting simulate subsurface glow.
    BACKLIGHT = pigment*0.18;
    float rim = pow(1.0-clamp(dot(normalize(NORMAL),normalize(VIEW)),0.0,1.0),3.0);
    EMISSION = pigment*rim*0.16;
}

void light() {
    // Three lit bands, including light attenuation and real shadow maps.
    float wrapped = clamp((dot(NORMAL,LIGHT)+wrap_amount)/(1.0+wrap_amount),0.0,1.0);
    float illumination = wrapped*ATTENUATION;
    float band = illumination < 0.24 ? 0.10 : (illumination < 0.65 ? 0.48 : 1.0);
    DIFFUSE_LIGHT += LIGHT_COLOR*band/PI;
    vec3 half_direction = normalize(LIGHT+VIEW);
    float gloss = pow(max(dot(NORMAL,half_direction),0.0),mix(110.0,20.0,roughness));
    SPECULAR_LIGHT += LIGHT_COLOR*gloss*gloss_strength*ATTENUATION;
}
