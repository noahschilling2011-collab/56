#!/usr/bin/env python3
"""Baut AirportJobSimulator.rbxlx aus den beiden Lua-Quellen.

Die .rbxlx ist eine normale Roblox-Studio-Place-Datei (XML):
- ReplicatedStorage/ShopData          (ModuleScript) -> eine Wahrheit fuer alle Shops
- ServerScriptService/AirportEconomy  (Script)     -> leaderstats, Remotes, DataStore
- ServerScriptService/Services/*      (ModuleScripts) -> Zone/Flight/Inventory
- ServerScriptService/AirportServer   (Script)     -> baut den Flughafen
- StarterPlayerScripts/AirportClient  (LocalScript) -> Jobs, HUD, Flugphysik

Aufruf:  python3 build_rbxlx.py
"""
import xml.dom.minidom
from pathlib import Path

HERE = Path(__file__).parent


def xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\r\n", "\n")
    )


server_src = xml_escape((HERE / "AirportServer.server.lua").read_text(encoding="utf-8"))
client_src = xml_escape((HERE / "AirportClient.client.lua").read_text(encoding="utf-8"))
shopdata_src = xml_escape((HERE / "ShopData.module.lua").read_text(encoding="utf-8"))
economy_src = xml_escape((HERE / "AirportEconomy.server.lua").read_text(encoding="utf-8"))
zone_src = xml_escape((HERE / "ZoneService.module.lua").read_text(encoding="utf-8"))
flight_src = xml_escape((HERE / "FlightService.module.lua").read_text(encoding="utf-8"))
inventory_src = xml_escape((HERE / "InventoryService.module.lua").read_text(encoding="utf-8"))
admin_src = xml_escape((HERE / "AdminService.module.lua").read_text(encoding="utf-8"))

rbxlx = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
	<Meta name="ExplicitAutoJoints">true</Meta>
	<External>null</External>
	<External>nil</External>
	<Item class="Workspace" referent="RBX0">
		<Properties>
			<string name="Name">Workspace</string>
		</Properties>
	</Item>
	<Item class="Players" referent="RBX13">
		<Properties>
			<string name="Name">Players</string>
			<bool name="CharacterAutoLoads">true</bool>
			<int name="MaxPlayersInternal">12</int>
			<int name="PreferredPlayersInternal">8</int>
		</Properties>
	</Item>
	<Item class="Lighting" referent="RBX9">
		<Properties>
			<string name="Name">Lighting</string>
			<token name="Technology">4</token>
			<string name="TimeOfDay">15:00:00</string>
			<bool name="GlobalShadows">true</bool>
			<float name="Brightness">2.2</float>
			<float name="EnvironmentDiffuseScale">0.5</float>
			<float name="EnvironmentSpecularScale">0.6</float>
			<float name="ShadowSoftness">0.2</float>
			<Color3 name="Ambient"><R>0.27</R><G>0.28</G><B>0.31</B></Color3>
			<Color3 name="OutdoorAmbient"><R>0.5</R><G>0.52</G><B>0.55</B></Color3>
		</Properties>
		<Item class="Atmosphere" referent="RBX10">
			<Properties>
				<string name="Name">Atmosphere</string>
				<float name="Density">0.35</float>
				<float name="Offset">0.25</float>
				<float name="Glare">0.2</float>
				<float name="Haze">1.4</float>
				<Color3 name="Color"><R>0.8</R><G>0.78</G><B>0.75</B></Color3>
				<Color3 name="Decay"><R>0.42</R><G>0.44</G><B>0.49</B></Color3>
			</Properties>
		</Item>
		<Item class="BloomEffect" referent="RBX11">
			<Properties>
				<string name="Name">Bloom</string>
				<bool name="Enabled">true</bool>
				<float name="Intensity">0.35</float>
				<float name="Size">24</float>
				<float name="Threshold">1.1</float>
			</Properties>
		</Item>
		<Item class="ColorCorrectionEffect" referent="RBX12">
			<Properties>
				<string name="Name">ColorCorrection</string>
				<bool name="Enabled">true</bool>
				<float name="Brightness">0.02</float>
				<float name="Contrast">0.05</float>
				<float name="Saturation">0.03</float>
				<Color3 name="TintColor"><R>1</R><G>0.976</G><B>0.945</B></Color3>
			</Properties>
		</Item>
	</Item>
	<Item class="ReplicatedStorage" referent="RBX6">
		<Properties>
			<string name="Name">ReplicatedStorage</string>
		</Properties>
		<Item class="ModuleScript" referent="RBX7">
			<Properties>
				<string name="Name">ShopData</string>
				<ProtectedString name="Source">{shopdata_src}</ProtectedString>
			</Properties>
		</Item>
	</Item>
	<Item class="ServerScriptService" referent="RBX1">
		<Properties>
			<string name="Name">ServerScriptService</string>
		</Properties>
		<Item class="Script" referent="RBX2">
			<Properties>
				<string name="Name">AirportServer</string>
				<ProtectedString name="Source">{server_src}</ProtectedString>
			</Properties>
		</Item>
		<Item class="Script" referent="RBX8">
			<Properties>
				<string name="Name">AirportEconomy</string>
				<ProtectedString name="Source">{economy_src}</ProtectedString>
			</Properties>
		</Item>
		<Item class="Folder" referent="RBX14">
			<Properties>
				<string name="Name">Services</string>
			</Properties>
			<Item class="ModuleScript" referent="RBX15">
				<Properties>
					<string name="Name">ZoneService</string>
					<ProtectedString name="Source">{zone_src}</ProtectedString>
				</Properties>
			</Item>
			<Item class="ModuleScript" referent="RBX16">
				<Properties>
					<string name="Name">FlightService</string>
					<ProtectedString name="Source">{flight_src}</ProtectedString>
				</Properties>
			</Item>
			<Item class="ModuleScript" referent="RBX17">
				<Properties>
					<string name="Name">InventoryService</string>
					<ProtectedString name="Source">{inventory_src}</ProtectedString>
				</Properties>
			</Item>
			<Item class="ModuleScript" referent="RBX18">
				<Properties>
					<string name="Name">AdminService</string>
					<ProtectedString name="Source">{admin_src}</ProtectedString>
				</Properties>
			</Item>
		</Item>
	</Item>
	<Item class="StarterPlayer" referent="RBX3">
		<Properties>
			<string name="Name">StarterPlayer</string>
		</Properties>
		<Item class="StarterPlayerScripts" referent="RBX4">
			<Properties>
				<string name="Name">StarterPlayerScripts</string>
			</Properties>
			<Item class="LocalScript" referent="RBX5">
				<Properties>
					<string name="Name">AirportClient</string>
					<ProtectedString name="Source">{client_src}</ProtectedString>
				</Properties>
			</Item>
		</Item>
	</Item>
</roblox>
"""

out = HERE / "AirportJobSimulator.rbxlx"
out.write_text(rbxlx, encoding="utf-8")
xml.dom.minidom.parseString(rbxlx)  # Validierung: wirft bei kaputtem XML
print(f"OK: {out} ({out.stat().st_size} Bytes), XML valide")
