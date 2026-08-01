#!/usr/bin/env python3
"""Baut GhostNet.rbxlx aus dem src/-Baum.

Die .rbxlx ist eine normale Roblox-Studio-Place-Datei (XML). Der Baum unter
src/ wird 1:1 ins DataModel uebernommen:

    src/ReplicatedStorage/Shared/*.lua          -> ModuleScripts
    src/ServerScriptService/**/*.server.lua     -> Scripts
    src/ServerScriptService/**/*.lua            -> ModuleScripts
    src/StarterPlayer/.../UI/*.client.lua       -> LocalScripts

Dazu kommen Baseplate, SpawnLocation und eine dunkle Nachtbeleuchtung,
damit das Neon der Testobjekte ueberhaupt zu sehen ist.

Aufruf:  python3 tools/build_place.py
"""
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SRC = HERE / "src"
OUT = HERE / "GhostNet.rbxlx"


def xml_escape(s: str) -> str:
    return (
        s.replace("&", "&amp;")
        .replace("<", "&lt;")
        .replace(">", "&gt;")
        .replace("\r\n", "\n")
    )


class Ref:
    """Vergibt fortlaufende referent-Ids (RBX0, RBX1, ...)."""

    def __init__(self) -> None:
        self.n = 0

    def next(self) -> str:
        self.n += 1
        return f"RBX{self.n}"


ref = Ref()


def indent(text: str, level: int) -> str:
    pad = "\t" * level
    return "\n".join(pad + line if line else line for line in text.split("\n"))


def script_item(path: Path, level: int) -> str:
    name = path.name
    if name.endswith(".server.lua"):
        class_name, inst_name = "Script", name[: -len(".server.lua")]
    elif name.endswith(".client.lua"):
        class_name, inst_name = "LocalScript", name[: -len(".client.lua")]
    else:
        class_name, inst_name = "ModuleScript", name[: -len(".lua")]

    source = path.read_text(encoding="utf-8")
    # Sicherheitsnetz: rohe Steuerzeichen wuerden die XML-Datei zerlegen.
    for ch in source:
        if ord(ch) < 9 or (13 < ord(ch) < 32):
            raise ValueError(f"{path}: unerlaubtes Steuerzeichen {ord(ch)}")

    body = (
        f'<Item class="{class_name}" referent="{ref.next()}">\n'
        f"\t<Properties>\n"
        f'\t\t<string name="Name">{inst_name}</string>\n'
        f'\t\t<ProtectedString name="Source">{xml_escape(source)}</ProtectedString>\n'
        f"\t</Properties>\n"
        f"</Item>"
    )
    return indent(body, level)


def folder_item(name: str, children: str, level: int) -> str:
    body = (
        f'<Item class="Folder" referent="{ref.next()}">\n'
        f"\t<Properties>\n"
        f'\t\t<string name="Name">{name}</string>\n'
        f"\t</Properties>\n"
        f"{children}\n"
        f"</Item>"
    )
    return indent(body, level)


def walk(directory: Path, level: int) -> str:
    """Gibt die Kind-Items eines Verzeichnisses als XML zurueck."""
    parts = []
    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            inner = walk(entry, level + 1)
            parts.append(folder_item(entry.name, inner, level))
        elif entry.suffix == ".lua":
            parts.append(script_item(entry, level))
    return "\n".join(parts)


def part(name: str, size, pos, color, referent: str, spawn: bool = False) -> str:
    r, g, b = color
    packed = (255 << 24) | (r << 16) | (g << 8) | b
    cls = "SpawnLocation" if spawn else "Part"
    return f"""\t\t<Item class="{cls}" referent="{referent}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">{name}</string>
\t\t\t\t<bool name="Anchored">true</bool>
\t\t\t\t<bool name="CanCollide">true</bool>
\t\t\t\t<CoordinateFrame name="CFrame">
\t\t\t\t\t<X>{pos[0]}</X><Y>{pos[1]}</Y><Z>{pos[2]}</Z>
\t\t\t\t\t<R00>1</R00><R01>0</R01><R02>0</R02>
\t\t\t\t\t<R10>0</R10><R11>1</R11><R12>0</R12>
\t\t\t\t\t<R20>0</R20><R21>0</R21><R22>1</R22>
\t\t\t\t</CoordinateFrame>
\t\t\t\t<Vector3 name="size"><X>{size[0]}</X><Y>{size[1]}</Y><Z>{size[2]}</Z></Vector3>
\t\t\t\t<Color3uint8 name="Color3uint8">{packed}</Color3uint8>
\t\t\t\t<token name="TopSurface">0</token>
\t\t\t\t<token name="BottomSurface">0</token>
\t\t\t</Properties>
\t\t</Item>"""


def main() -> None:
    replicated = walk(SRC / "ReplicatedStorage", 2)
    server = walk(SRC / "ServerScriptService", 2)
    player_scripts = walk(SRC / "StarterPlayer" / "StarterPlayerScripts", 3)

    baseplate = part("Baseplate", (512, 16, 512), (0, -8, 0), (18, 20, 26), ref.next())
    spawn = part("SpawnLocation", (16, 1, 16), (0, 0.5, 10), (0, 90, 105), ref.next(), spawn=True)

    rbxlx = f"""<roblox xmlns:xmime="http://www.w3.org/2005/05/xmlmime" xmlns:xsi="http://www.w3.org/2001/XMLSchema-instance" xsi:noNamespaceSchemaLocation="http://www.roblox.com/roblox.xsd" version="4">
\t<Meta name="ExplicitAutoJoints">true</Meta>
\t<External>null</External>
\t<External>nil</External>
\t<Item class="Workspace" referent="RBX0">
\t\t<Properties>
\t\t\t<string name="Name">Workspace</string>
\t\t\t<float name="Gravity">196.2</float>
\t\t</Properties>
{baseplate}
{spawn}
\t</Item>
\t<Item class="Lighting" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">Lighting</string>
\t\t\t<token name="Technology">4</token>
\t\t\t<string name="TimeOfDay">00:00:00</string>
\t\t\t<bool name="GlobalShadows">true</bool>
\t\t\t<float name="Brightness">1</float>
\t\t\t<float name="EnvironmentDiffuseScale">0.35</float>
\t\t\t<float name="EnvironmentSpecularScale">0.6</float>
\t\t\t<float name="ShadowSoftness">0.3</float>
\t\t\t<Color3 name="Ambient"><R>0.05</R><G>0.06</G><B>0.08</B></Color3>
\t\t\t<Color3 name="OutdoorAmbient"><R>0.08</R><G>0.09</G><B>0.13</B></Color3>
\t\t\t<Color3 name="FogColor"><R>0.03</R><G>0.04</G><B>0.07</B></Color3>
\t\t\t<float name="FogEnd">420</float>
\t\t</Properties>
\t\t<Item class="BloomEffect" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">Bloom</string>
\t\t\t\t<bool name="Enabled">true</bool>
\t\t\t\t<float name="Intensity">0.6</float>
\t\t\t\t<float name="Size">28</float>
\t\t\t\t<float name="Threshold">0.9</float>
\t\t\t</Properties>
\t\t</Item>
\t\t<Item class="ColorCorrectionEffect" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">ColorCorrection</string>
\t\t\t\t<bool name="Enabled">true</bool>
\t\t\t\t<float name="Brightness">0</float>
\t\t\t\t<float name="Contrast">0.12</float>
\t\t\t\t<float name="Saturation">0.08</float>
\t\t\t\t<Color3 name="TintColor"><R>0.9</R><G>0.97</G><B>1</B></Color3>
\t\t\t</Properties>
\t\t</Item>
\t</Item>
\t<Item class="ReplicatedStorage" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">ReplicatedStorage</string>
\t\t</Properties>
{replicated}
\t</Item>
\t<Item class="ServerScriptService" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">ServerScriptService</string>
\t\t</Properties>
{server}
\t</Item>
\t<Item class="StarterPlayer" referent="{ref.next()}">
\t\t<Properties>
\t\t\t<string name="Name">StarterPlayer</string>
\t\t</Properties>
\t\t<Item class="StarterPlayerScripts" referent="{ref.next()}">
\t\t\t<Properties>
\t\t\t\t<string name="Name">StarterPlayerScripts</string>
\t\t\t</Properties>
{player_scripts}
\t\t</Item>
\t</Item>
</roblox>
"""

    OUT.write_text(rbxlx, encoding="utf-8")
    print(f"{OUT.name} geschrieben ({OUT.stat().st_size} Bytes)")


if __name__ == "__main__":
    main()
