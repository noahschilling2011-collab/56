-- AirportEconomy · nur noch Verdrahtung (Phase 3).
-- Die Logik lebt in Services/: InventoryService (Zustand, Remotes, DataStore,
-- Job-Tokens, Kosmetik, Boarding-Paesse), FlightService (eine Wahrheit fuer
-- Fluege), ZoneService (Zonen + Schranken).

local ServicesF = script.Parent:WaitForChild("Services")
local FlightService = require(ServicesF:WaitForChild("FlightService"))
local InventoryService = require(ServicesF:WaitForChild("InventoryService"))
local ZoneService = require(ServicesF:WaitForChild("ZoneService"))
local AdminService = require(ServicesF:WaitForChild("AdminService"))

FlightService.init()
InventoryService.init(FlightService)
ZoneService.init(InventoryService.zoneProvider(), FlightService)
ZoneService.setAdminCheck(AdminService.isAdmin)
AdminService.init(InventoryService, FlightService)

print("[AirportEconomy] Services verdrahtet: Flight -> Inventory -> Zone -> Admin")
