extends Resource
class_name Item

@export var id: int
@export var display_name: String
@export var description: String
@export var icon: Texture2D
@export var max_stack_size: int = 99
@export var item_type: DataTypes.ItemType
@export var is_stackable: bool = true

@export var rarity: DataTypes.Rarity
@export var value: int

@export_group("Consumable Properties")
@export var healing_amount: int = 0
@export var duration: float = 0.0

@export_group("Tool Properties")
@export var tool_type: DataTypes.Tools
@export var durability: int = 100
@export var damage: int = 0

@export_group("Placeable Properties")
@export var is_placeable: bool = false
@export var placeable_scene: PackedScene  # Reference to the scene to instantiate
@export var placement_offset: Vector3 = Vector3.ZERO  # Offset for placement position
@export var can_rotate: bool = true  # Whether player can rotate before placing
@export var requires_ground: bool = true  # Whether it needs to be on ground
@export var placement_radius: float = 5.0  # Max distance from player to place

# Optional: Preview material for ghost preview
@export var preview_material: Material

func can_be_placed() -> bool:
	return is_placeable and placeable_scene != null
