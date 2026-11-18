shader_type spatial;
render_mode cull_disabled, diffuse_lambert_wrap, specular_disabled;
uniform sampler2D leaf_texture : source_color, filter_linear_mipmap_anisotropic;
uniform vec4 tint : source_color = vec4(0.74,0.89,0.65,1.0);
void vertex() {
    vec3 world=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz;
    float weight=clamp(VERTEX.y*0.4,0.0,1.0);
    VERTEX.x+=sin(TIME*1.25+world.x*0.19+world.z*0.12)*0.035*weight;
    NORMAL=normalize(mix(NORMAL,vec3(0.0,1.0,0.0),0.62));
}
void fragment() {
    vec4 leaf=texture(leaf_texture,UV);
    ALBEDO=leaf.rgb*tint.rgb;
    ALPHA=leaf.a;
    ALPHA_SCISSOR_THRESHOLD=0.25;
    ROUGHNESS=1.0;
    BACKLIGHT=ALBEDO*0.16;
}
