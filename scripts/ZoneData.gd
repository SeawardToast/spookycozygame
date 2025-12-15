extends Resource
class_name ZoneData

@export var id: int = 1
@export var type: String = "Kitchen"
@export var polygon: PackedVector2Array = PackedVector2Array()
@export var color: Color = Color(0.5, 0.5, 1, 0.3)  # semi-transparent
@export var name: String = ""
@export var floor: int = 1
@export var position: Vector2 = Vector2(0, 0)
