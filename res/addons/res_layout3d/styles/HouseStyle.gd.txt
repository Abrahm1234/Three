extends Resource
class_name HouseStyle

@export var profiles := {
	"Living": {"w": 1.2, "h": 1.2, "spacing": 2.0},
	"Bedroom": {"w": 1.0, "h": 1.2, "spacing": 1.6},
	"Kitchen": {"w": 0.8, "h": 0.9, "spacing": 1.4},
	"Bathroom": {"w": 0.6, "h": 0.6, "spacing": 1.2},
}
@export var sill_height_m := 0.9
@export var window_mat: Material
