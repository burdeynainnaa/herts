class_name Health
extends Node
## Hit points for anything that can be hurt. Combat code calls apply_damage();
## listeners react to the signals (HUD bars, hit reactions, death).

signal damaged(amount: float, source: Node)
signal healed(amount: float)
signal died(source: Node)
signal changed(current: float, maximum: float)

@export var max_health: float = 100.0

var current: float = 0.0


func _ready() -> void:
	current = max_health


func is_dead() -> bool:
	return current <= 0.0


func ratio() -> float:
	return current / max_health if max_health > 0.0 else 0.0


func apply_damage(amount: float, source: Node = null) -> void:
	if is_dead() or amount <= 0.0:
		return
	current = maxf(current - amount, 0.0)
	damaged.emit(amount, source)
	changed.emit(current, max_health)
	if is_dead():
		died.emit(source)


func heal(amount: float) -> void:
	if is_dead() or amount <= 0.0:
		return
	current = minf(current + amount, max_health)
	healed.emit(amount)
	changed.emit(current, max_health)


func reset() -> void:
	current = max_health
	changed.emit(current, max_health)
