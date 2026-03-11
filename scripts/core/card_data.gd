extends Resource
class_name CardData

@export var card_id: String = ""
@export var name: String = ""
@export var description: String = ""
@export var card_kind: String = "passive" # passive | active
@export var rarity: String = "common" # common | uncommon | rare
@export var payload: Dictionary = {}

func to_dict() -> Dictionary:
	return {
		"card_id": card_id,
		"name": name,
		"description": description,
		"card_kind": card_kind,
		"rarity": rarity,
		"payload": payload.duplicate(true),
	}

static func from_dict(data: Dictionary) -> CardData:
	var card: CardData = CardData.new()
	card.card_id = String(data.get("card_id", ""))
	card.name = String(data.get("name", ""))
	card.description = String(data.get("description", ""))
	card.card_kind = String(data.get("card_kind", "passive"))
	card.rarity = String(data.get("rarity", "common"))
	card.payload = (data.get("payload", {}) as Dictionary).duplicate(true)
	return card
