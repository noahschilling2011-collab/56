-- ShopData · EINE Wahrheit fuer alle 13 Shops.
-- Server baut die Geometrie daraus, Client baut Prompts + Kauf-Panels daraus.
-- pos = Anker der Geometrie (Meter) · rotation = Blickrichtung der Front (Yaw)
-- Interaktionspunkt = pos + Frontrichtung * 4.4 (leitet der Client ab -> passt immer zur Geometrie)
-- ebene: 1 = Erdgeschoss, 2 = Food-Court-Galerie (Boden bei 4.78 m)
-- fassade = false: Shop hat (noch) eigene Spezial-Geometrie im Server, keine Standard-Fassade
-- items: { Name, Preis, Effekt } · Effekt: xpN | boost | glasses | phones | souvenir

local ShopData = {
	{
		id = "burger", name = "🍔 Burger Palace", akzentfarbe = Color3.fromRGB(194, 59, 46),
		pos = { x = -62, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "🍔 Burger", 12, "xp6" }, { "🍟 Menü Groß", 20, "xp12" }, { "🥤 Cola", 5, "xp3" } },
	},
	{
		id = "pizza", name = "🍕 Pizza Milano", akzentfarbe = Color3.fromRGB(42, 122, 74),
		pos = { x = -46, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "🍕 Pizza Margherita", 15, "xp8" }, { "🥟 Calzone", 18, "xp10" }, { "☕ Espresso", 6, "boost" } },
	},
	{
		id = "mode", name = "👗 Mode Boutique", akzentfarbe = Color3.fromRGB(201, 95, 160),
		pos = { x = 14, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "🕶 Sonnenbrille", 45, "glasses" }, { "🧢 Basecap", 25, "xp5" }, { "🧣 Schal", 18, "xp5" } },
	},
	{
		id = "elektronik", name = "📱 Elektronik", akzentfarbe = Color3.fromRGB(42, 109, 181),
		pos = { x = 30, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "🎧 Kopfhörer", 60, "phones" }, { "🔋 Powerbank", 25, "xp5" }, { "🔌 Reiseadapter", 15, "xp5" } },
	},
	{
		id = "apotheke", name = "➕ Apotheke", akzentfarbe = Color3.fromRGB(42, 157, 92),
		pos = { x = 48, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "💊 Vitamin-Booster", 15, "boost" }, { "🩹 Pflaster", 6, "xp3" }, { "💊 Reisetabletten", 10, "xp5" } },
	},
	{
		id = "presse", name = "📰 Presse & Tabak", akzentfarbe = Color3.fromRGB(138, 146, 158),
		pos = { x = 64, z = 297.8 }, ebene = 1, rotation = math.pi,
		items = { { "📖 Magazin", 8, "xp6" }, { "🗺 Reiseführer", 14, "xp10" }, { "🍬 Kaugummi", 3, "xp2" } },
	},
	{
		id = "buchladen", name = "📚 Buchladen", akzentfarbe = Color3.fromRGB(138, 106, 58),
		pos = { x = 72.6, z = 250 }, ebene = 1, rotation = -math.pi / 2,
		items = { { "📕 Roman", 12, "xp10" }, { "🔎 Krimi", 15, "xp12" }, { "🧸 Kinderbuch", 9, "xp6" } },
	},
	{
		id = "souvenirs", name = "🎁 Souvenirs", akzentfarbe = Color3.fromRGB(201, 164, 79),
		pos = { x = 72.6, z = 266 }, ebene = 1, rotation = -math.pi / 2,
		items = { { "✈ Mini-A380", 30, "souvenir" }, { "🔑 Schlüsselanhänger", 10, "xp5" }, { "❄ Schneekugel", 16, "xp8" } },
	},
	{
		id = "dutyfree", name = "✨ Duty Free", akzentfarbe = Color3.fromRGB(141, 95, 201),
		pos = { x = 50, z = 289 }, ebene = 1, rotation = math.pi, fassade = false, -- Regal-Geometrie bleibt bis Phase 2
		items = { { "🌸 Parfüm", 40, "xp15" }, { "🍫 Schokolade XXL", 18, "xp10" }, { "🧴 Sonnencreme", 12, "xp5" } },
	},
	{
		id = "cafe", name = "☕ Café am Gate", akzentfarbe = Color3.fromRGB(255, 215, 94),
		pos = { x = 62, z = 282 }, ebene = 1, rotation = math.pi, fassade = false, -- Kiosk-Geometrie bleibt bis Phase 2
		items = { { "☕ Kaffee", 6, "boost" }, { "☕ Cappuccino", 8, "boost" }, { "🥐 Croissant", 7, "xp5" } },
	},
	{
		id = "sushi", name = "🍣 Sushi Bar", akzentfarbe = Color3.fromRGB(42, 143, 143),
		pos = { x = 14, z = 296.5 }, ebene = 2, rotation = math.pi,
		items = { { "🍣 Sushi-Box", 22, "xp15" }, { "🍜 Miso-Suppe", 9, "xp6" }, { "🍵 Grüner Tee", 5, "boost" } },
	},
	{
		id = "taco", name = "🌮 Taco Loco", akzentfarbe = Color3.fromRGB(224, 120, 32),
		pos = { x = 32, z = 296.5 }, ebene = 2, rotation = math.pi,
		items = { { "🌮 Taco-Teller", 16, "xp10" }, { "🌯 Burrito", 18, "xp12" }, { "🍋 Limonade", 5, "xp3" } },
	},
	{
		id = "eiscafe", name = "🍦 Eiscafé Venezia", akzentfarbe = Color3.fromRGB(201, 95, 160),
		pos = { x = 52, z = 296.5 }, ebene = 2, rotation = math.pi,
		items = { { "🍨 Eisbecher", 10, "xp8" }, { "🧇 Waffel", 8, "xp6" }, { "🥤 Milchshake", 9, "boost" } },
	},
}

return ShopData
