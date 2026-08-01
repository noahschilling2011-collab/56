#!/usr/bin/env python3
"""Erzeugt sourcemap.json fuer luau-lsp aus dem src/-Baum.

Ohne Sourcemap kann der Analyzer die require()-Pfade nicht aufloesen und
meldet jede modulueberschreitende Typangabe als unbekannt. Mit Sourcemap
prueft er GHOSTNET wirklich durch.

Aufruf:  python3 tools/make_sourcemap.py
"""
import json
from pathlib import Path

HERE = Path(__file__).resolve().parent.parent
SRC = HERE / "src"

# Ordner unter src/ -> Klassenname im DataModel
SERVICE_CLASS = {
    "ReplicatedStorage": "ReplicatedStorage",
    "ServerScriptService": "ServerScriptService",
    "StarterPlayer": "StarterPlayer",
    "StarterPlayerScripts": "StarterPlayerScripts",
    "Workspace": "Workspace",
    "Lighting": "Lighting",
}


def script_node(path: Path) -> dict:
    name = path.name
    if name.endswith(".server.lua"):
        return {
            "name": name[: -len(".server.lua")],
            "className": "Script",
            "filePaths": [str(path.relative_to(HERE))],
        }
    if name.endswith(".client.lua"):
        return {
            "name": name[: -len(".client.lua")],
            "className": "LocalScript",
            "filePaths": [str(path.relative_to(HERE))],
        }
    return {
        "name": name[: -len(".lua")],
        "className": "ModuleScript",
        "filePaths": [str(path.relative_to(HERE))],
    }


def walk(directory: Path, depth: int) -> dict:
    """Ein Verzeichnis wird zu einem Folder-Knoten (oder einem Service auf
    der obersten Ebene)."""
    class_name = SERVICE_CLASS.get(directory.name, "Folder") if depth <= 1 else "Folder"
    node = {"name": directory.name, "className": class_name, "children": []}

    for entry in sorted(directory.iterdir()):
        if entry.is_dir():
            node["children"].append(walk(entry, depth + 1))
        elif entry.suffix == ".lua":
            node["children"].append(script_node(entry))

    return node


def main() -> None:
    root = {"name": "GHOSTNET", "className": "DataModel", "children": []}
    for entry in sorted(SRC.iterdir()):
        if entry.is_dir():
            root["children"].append(walk(entry, 1))

    out = HERE / "sourcemap.json"
    out.write_text(json.dumps(root, indent=2) + "\n", encoding="utf-8")
    print(f"sourcemap.json geschrieben ({out.stat().st_size} Bytes)")


if __name__ == "__main__":
    main()
