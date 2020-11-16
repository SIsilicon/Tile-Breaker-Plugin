tool
extends Reference

# RIDs don't get saved well in tscn files, so storing it in an Array solves the issue.
var adjusted_shader := [] # RID inside
var material: Material

func clean(material: Material) -> void:
	self.material = material
	self.adjusted_shader.append(material.adjusted_shader)
	if material.has_meta("_tile_breaker_cleanup"):
		material.remove_meta("_tile_breaker_cleanup")
	material.set_meta("_tile_breaker_cleanup", self)
	material.connect("script_changed", self, "_on_script_changed")


func _on_script_changed() -> void:
	VisualServer.free_rid(adjusted_shader[0])
	VisualServer.disconnect("frame_pre_draw", material, "_update")
	VisualServer.disconnect("frame_post_draw", material, "_post_draw")
	material.remove_meta("_tile_breaker_cleanup")
