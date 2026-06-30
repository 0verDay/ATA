class_name ItemDef

# Rarity colours
const COLOR_GREEN  := Color(0.294, 0.765, 0.294)
const COLOR_BLUE   := Color(0.329, 0.584, 0.941)
const COLOR_PURPLE := Color(0.690, 0.318, 0.918)
const COLOR_GOLD   := Color(0.961, 0.816, 0.180)

# 4 placeholder item types, one per rarity
# w/h are in inventory grid cells
static var TYPES : Array = [
	{ "id": "herb",    "name": "草药",   "w": 1, "h": 1, "value":  50,  "color": COLOR_GREEN  },
	{ "id": "medkit",  "name": "医疗包", "w": 1, "h": 2, "value": 200,  "color": COLOR_BLUE   },
	{ "id": "circuit", "name": "电路板", "w": 2, "h": 1, "value": 450,  "color": COLOR_PURPLE },
	{ "id": "crystal", "name": "晶核",   "w": 2, "h": 2, "value": 950,  "color": COLOR_GOLD   },
]
