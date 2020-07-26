tool
extends SpatialMaterial

const DEFAULT_SPATIAL_CODE := """
shader_type spatial;
render_mode blend_mix,depth_draw_opaque,cull_back,diffuse_burley,specular_schlick_ggx;
uniform vec4 albedo : hint_color;
uniform sampler2D texture_albedo : hint_albedo;
uniform float specular;
uniform float metallic;
uniform float roughness : hint_range(0,1);
uniform float point_size : hint_range(0,128);
uniform vec3 uv1_scale;
uniform vec3 uv1_offset;
uniform vec3 uv2_scale;
uniform vec3 uv2_offset;

void vertex() {
	UV=UV*uv1_scale.xy+uv1_offset.xy;
}

void fragment() {
	vec2 base_uv = UV;
	vec4 albedo_tex = texture(texture_albedo,base_uv);
	ALBEDO = albedo.rgb * albedo_tex.rgb;
	METALLIC = metallic;
	ROUGHNESS = roughness;
	SPECULAR = specular;
}
"""

const TEXTURE_PARAMS := [
	"texture_albedo", "texture_metallic",
	"texture_roughness", "texture_emission",
	"texture_normal", "texture_rim",
	"texture_clearcoat", "texture_flowmap",
	"texture_ambient_occlusion", "texture_depth",
	"texture_subsurface_scattering", "texture_transmission",
	"texture_refraction", "texture_detail_mask",
	"texture_detail_albedo", "texture_detail_normal"
]

const DEFAULT_VARIATION := preload("default_variation_texture.tres")

# Exported variables
var variation_texture: Texture
var uv1_break_tiling := true setget set_uv1_break_tiling
var uv2_break_tiling := false setget set_uv2_break_tiling
var uv1_random_rotation := 180.0
var uv2_random_rotation := 180.0
var uv1_blending := 0.4
var uv2_blending := 0.4

var sampler_code := ""
var prev_shader_code := ""
var tile_breaker_quality := 0
var original_shader: RID
var adjusted_shader: RID

var dirty_shader := true


func transform_material() -> String:
	var code := VisualServer.shader_get_code(
			VisualServer.material_get_shader(get_rid())
	)

	if prev_shader_code != code:
		dirty_shader = true
	if not dirty_shader:
		return ""
	prev_shader_code = code

	# When a material is first created, it does not immediately have shader code.
	# This makes sure that it will initially work.
	if code.empty():
		code = DEFAULT_SPATIAL_CODE

	# replace texture functions with textureNoTile.
	var texture_func := TileBreaker.find_texture_function(code)
	var is_triplanar := false
	while texture_func:
		var tex_uv_layer := 1
		if not texture_func.texture in TEXTURE_PARAMS:
			tex_uv_layer = 0
		elif texture_func.texture in ["texture_detail_mask", "texture_detail_albedo", "texture_detail_normal"] and detail_uv_layer == DETAIL_UV_2:
			tex_uv_layer = 2
		elif texture_func.texture == "texture_emission" and emission_on_uv2:
			tex_uv_layer = 2
		elif texture_func.texture == "texture_ambient_occlusion" and ao_on_uv2:
			tex_uv_layer = 2
		
		if (tex_uv_layer == 1 and uv1_break_tiling) or (tex_uv_layer == 2 and uv2_break_tiling):
			code = code.insert(TileBreaker.find_closing_bracket(code, texture_func.bracket), ",uv1_random_rotation,uv1_blending" if tex_uv_layer == 1 else ",uv2_random_rotation,uv2_blending")
			code.erase(texture_func.index, len("texture" if not is_triplanar else "triplanar_texture"))
			code = code.insert(texture_func.index, "textureNoTile" if not is_triplanar else "triplanarTextureNoTile")
		
		var triplanar_func = TileBreaker.find_texture_function(code, "triplanar_texture", texture_func.index+1)
		texture_func = TileBreaker.find_texture_function(code, "texture", texture_func.index+1)

		if not triplanar_func.empty() and (texture_func.empty() or triplanar_func.index < texture_func.index):
			texture_func = triplanar_func
			is_triplanar = true
		else:
			is_triplanar = false

	# Insert new texture function right after shader_type.
	var shader_type_line_end := code.find(";")
	if shader_type_line_end == -1:
		return ""
	code = code.insert(shader_type_line_end + 1, """
		uniform float uv1_random_rotation;
		uniform float uv2_random_rotation;
		uniform float uv1_blending;
		uniform float uv2_blending;"""\
	.replace("\n\t\t", "\n") + sampler_code +\
	(TileBreaker.SAMPLER_CODE.triplanar.replace("\n\t\t", "\n") if (uv1_triplanar or uv2_triplanar) else ""))

	dirty_shader = false
	return code


func set_uv1_break_tiling(value: bool) -> void:
	uv1_break_tiling = value
	dirty_shader = true


func set_uv2_break_tiling(value: bool) -> void:
	uv2_break_tiling = value
	dirty_shader = true


func _init() -> void:
	if not VisualServer.is_connected("frame_pre_draw", self, "_update"):
		VisualServer.connect("frame_pre_draw", self, "_update")
	if not VisualServer.is_connected("frame_post_draw", self, "_post_draw"):
		VisualServer.connect("frame_post_draw", self, "_post_draw")
	sampler_code = TileBreaker.get_sampler_code()
	adjusted_shader = VisualServer.shader_create()
	dirty_shader = true
	
	yield(VisualServer, "frame_post_draw")
	preload("tile_breaker_cleanup.gd").new(self)

func _update() -> void:
	if tile_breaker_quality != ProjectSettings.get_setting("rendering/quality/tile_breaker/quality"):
		tile_breaker_quality = ProjectSettings.get_setting("rendering/quality/tile_breaker/quality")
		sampler_code = TileBreaker.get_sampler_code()
		property_list_changed_notify()
		dirty_shader = true
	
	if adjusted_shader:
		var code := transform_material()
		if not code.empty():
			VisualServer.shader_set_code(adjusted_shader, code)
		VisualServer.material_set_param(get_rid(), "variation", variation_texture if variation_texture else DEFAULT_VARIATION)
		VisualServer.material_set_param(get_rid(), "uv1_random_rotation", deg2rad(uv1_random_rotation))
		VisualServer.material_set_param(get_rid(), "uv2_random_rotation", deg2rad(uv2_random_rotation))
		VisualServer.material_set_param(get_rid(), "uv1_blending", uv1_blending)
		VisualServer.material_set_param(get_rid(), "uv2_blending", uv2_blending)
		original_shader = VisualServer.material_get_shader(get_rid())
		VisualServer.material_set_shader(get_rid(), adjusted_shader)


func _post_draw() -> void:
	VisualServer.material_set_shader(get_rid(), original_shader)


func _get_property_list() -> Array:
	var properties := [
		{name="TileBreaker", type=TYPE_NIL, usage=PROPERTY_USAGE_CATEGORY}
	]
	if ProjectSettings.get_setting("rendering/quality/tile_breaker/quality") == 0:
		properties.append({name="variation_texture", type=TYPE_OBJECT, hint=PROPERTY_HINT_RESOURCE_TYPE, hint_string="Texture"})
	properties += [
		{name="UV 1", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="uv1_"},
		{name="uv1_break_tiling", type=TYPE_BOOL},
		{name="uv1_random_rotation", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,180"},
		{name="uv1_blending", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,1"},
		{name="UV 2", type=TYPE_NIL, usage=PROPERTY_USAGE_GROUP, hint_string="uv2_"},
		{name="uv2_break_tiling", type=TYPE_BOOL},
		{name="uv2_random_rotation", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,180"},
		{name="uv2_blending", type=TYPE_REAL, hint=PROPERTY_HINT_RANGE, hint_string="0,1"}
	]
	return properties


func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if adjusted_shader:
			VisualServer.free_rid(adjusted_shader)
