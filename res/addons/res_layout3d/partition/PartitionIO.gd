extends Resource
class_name PartitionIO

const InitBSP := preload("res://addons/res_layout3d/partition/InitBSP.gd")

static func from_program_rect_seed(prog: ArchitecturalProgram, grid_step := 0.1) -> Partition:
	return InitBSP.build(prog, grid_step)
