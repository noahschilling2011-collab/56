-- AirportEconomy · nur noch Verdrahtung (Phase 3).
-- Die Logik lebt in Services/: InventoryService (Zustand, Remotes, DataStore,
-- Job-Tokens, Kosmetik, Boarding-Paesse), FlightService (eine Wahrheit fuer
-- Fluege), ZoneService (Zonen + Schranken).

local ServicesF = script.Parent:WaitForChild("Services")
local FlightService = require(ServicesF:WaitForChild("FlightService"))
local InventoryService = require(ServicesF:WaitForChild("InventoryService"))
local ZoneService = require(ServicesF:WaitForChild("ZoneService"))

FlightService.init()
InventoryService.init(FlightService)
ZoneService.init(InventoryService.zoneProvider(), FlightService)

print("[AirportEconomy] Services verdrahtet: Flight -> Inventory -> Zone")
