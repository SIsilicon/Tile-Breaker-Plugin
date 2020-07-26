tool
extends VisualShaderNodeCustom
class_name VisualShaderNodeTextureNoTile


func _get_name():
	return "TextureNoTile"


func _get_category() -> String:
	return "SpecialTextures"


func _get_description():
	return "A texture sampler that removes visible patterns from tiling textures. It's best used on textures meant to not have a pattern, i.e. are stochastic."


func _get_return_icon_type():
	return VisualShaderNode.PORT_TYPE_VECTOR


func _get_input_port_count():
	return 4


func _get_input_port_name(port):
	match port:
		0:
			return "uv"
		1:
			return "rotation"
		2:
			return "blending"
		3:
			return "sampler2D"


func _get_input_port_type(port):
	match port:
		0:
			return VisualShaderNode.PORT_TYPE_VECTOR
		1:
			return VisualShaderNode.PORT_TYPE_SCALAR
		2:
			return VisualShaderNode.PORT_TYPE_SCALAR
		3:
			return VisualShaderNode.PORT_TYPE_SAMPLER


func _get_output_port_count():
	return 2


func _get_output_port_name(port):
	match port:
		0:
			return "rgb"
		1:
			return "alpha"


func _get_output_port_type(port):
	match port:
		0:
			return VisualShaderNode.PORT_TYPE_VECTOR
		1:
			return VisualShaderNode.PORT_TYPE_SCALAR


func _get_global_code(mode):
	return TileBreaker.get_sampler_code()


func _get_code(input_vars, output_vars, mode, type):
	var temp_var := "ntile_" + String(get_instance_id())
	input_vars[0] = input_vars[0] if input_vars[0] else "UV"
	input_vars[1] = input_vars[1] if input_vars[1] else "0.0"
	input_vars[2] = input_vars[2] if input_vars[2] else "0.2"
	
	return \
		("	vec4 "+ temp_var +" = textureNoTile(%s, %s.xy, %s, %s);\n" +\
		"	%s = "+ temp_var +".rgb;\n" +\
		"	%s = "+ temp_var +".a;\n") %\
		[input_vars[3], input_vars[0], input_vars[1], input_vars[2], output_vars[0], output_vars[1]]


func _init() -> void:
	set_input_port_default_value(1, 0.0)
	set_input_port_default_value(2, 0.2)
