tool
extends EditorPlugin

var button: MenuButton
var selected_material: Material

func handles(object: Object) -> bool:
	if object is SpatialMaterial:
		button.show()
		return true
	button.hide()
	return false


func edit(object: Object) -> void:
	selected_material = object

	var icon: Texture
	while not icon:
		icon = load("res://addons/silicon.vfx.tilebreaker/tile_breaker.svg")
		yield(get_tree(), "idle_frame")

	if selected_material.get_script() == preload("spatial_tile_breaker.gd"):
		button.get_popup().set_item_id(0, 1)
		button.get_popup().set_item_text(0, "Remove Tile Breaker")
	else:
		button.get_popup().set_item_id(0, 0)
		button.get_popup().set_item_text(0, "Add Tile Breaker")
	button.get_popup().set_item_icon(0, icon)


func _enter_tree() -> void:
	button = MenuButton.new()
	button.flat = true
	button.icon = get_editor_interface().get_base_control().get_icon("SpatialMaterial", "EditorIcons")
	button.text = "SpatialMaterial"
	button.visible = false
	button.get_popup().add_item("Add Tile Breaker", 0)
	add_control_to_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, button)

	if not button.get_popup().is_connected("index_pressed", self, "_on_button_pressed"):
		button.get_popup().connect("index_pressed", self, "_on_button_pressed")

	if not ProjectSettings.has_setting("rendering/quality/tile_breaker/quality"):
		ProjectSettings.set_setting("rendering/quality/tile_breaker/quality", 1)
	ProjectSettings.add_property_info({
		name = "rendering/quality/tile_breaker/quality",
		type = TYPE_INT,
		hint = PROPERTY_HINT_ENUM,
		hint_string = "Low,Medium,High"
	})

	print("Tile breaker has enter tree")


func _on_button_pressed(index: int) -> void:
	match button.get_popup().get_item_id(0):
		0: # Add Tile Breaker
			selected_material.set_script(preload("spatial_tile_breaker.gd"))
		1: # Remove Tile Breaker
			selected_material.set_script(null)
	edit(selected_material)


func _exit_tree() -> void:
	remove_control_from_container(EditorPlugin.CONTAINER_SPATIAL_EDITOR_MENU, button)
	print("Tile breaker has exit tree")
