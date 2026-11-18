shader_type spatial;
uniform vec4 base_color : source_color = vec4(0.4,0.24,0.18,1.0);
varying vec3 local_point;
void vertex(){ local_point=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; }
float hash(vec2 p){return fract(sin(dot(p,vec2(123.4,471.2)))*43758.5453);}
void fragment(){
    vec2 p=local_point.xz*vec2(1.5,1.8);
    float row=floor(p.y);
    p.x+=mod(row,2.0)*0.5;
    vec2 cell=floor(p);
    vec2 f=fract(p);
    float seam=smoothstep(0.015,0.065,f.x)*smoothstep(0.02,0.13,f.y);
    float variation=hash(cell);
    float footprint=max(length(dFdx(p)),length(dFdy(p)));
    float detail=1.0-smoothstep(0.18,0.8,footprint);
    float tiles=(0.70+variation*0.28)*mix(0.52,1.12,seam);
    ALBEDO=base_color.rgb*mix(0.88,tiles,detail);
    ROUGHNESS=0.88;
    SPECULAR=0.16;
}
