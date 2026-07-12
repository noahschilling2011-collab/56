#!/usr/bin/env python3
"""Baut AirportJobSimulator.rbxlx aus den beiden Lua-Quellen.

Die .rbxlx ist eine normale Roblox-Studio-Place-Datei (XML):
- ReplicatedStorage/ShopData          (ModuleScript) -> eine Wahrheit fuer alle Shops
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

rbxlx = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
	<Meta name="ExplicitAutoJoints">true</Meta>
	<External>null</External>
	<External>nil</External>
	<Item class="Workspace" referent="RBX0">
		<Properties>
			<string name="Name">Workspace</string>
		</Properties>
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
