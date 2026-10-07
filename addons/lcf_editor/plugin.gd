@tool
extends EditorPlugin

const ProjectDock := preload("res://addons/lcf_editor/project_dock.gd")

var dock: Control


func _enter_tree() -> void:
	dock = ProjectDock.new()
	dock.name = "LCF Project"
	add_control_to_dock(DOCK_SLOT_LEFT_UL, dock)


func _exit_tree() -> void:
	if dock:
		remove_control_from_docks(dock)
		dock.queue_free()
		dock = null
