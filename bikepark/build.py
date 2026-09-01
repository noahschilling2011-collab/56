#!/usr/bin/env python3
"""Baut aus template.html + strecken.json die fertige, eigenstaendige HTML-Datei."""
import json, sys, os
hier = os.path.dirname(os.path.abspath(__file__))
src  = sys.argv[1] if len(sys.argv) > 1 else os.path.join(hier, "strecken.json")
dst  = sys.argv[2] if len(sys.argv) > 2 else os.path.join(hier, "bikepark-pruefstand.html")
tpl  = open(os.path.join(hier, "template.html"), encoding="utf-8").read()
data = json.load(open(src, encoding="utf-8"))
assert "__STRECKEN_JSON__" in tpl, "Platzhalter fehlt im Template"
# In ein <script type="application/json"> eingebettet: nur </script> muss entschaerft werden.
js = json.dumps(data, ensure_ascii=False, separators=(",", ":")).replace("</", "<\\/")
open(dst, "w", encoding="utf-8").write(tpl.replace("__STRECKEN_JSON__", js))
print(f"geschrieben: {dst}  ({os.path.getsize(dst)/1024:.0f} kB, "
      f"{len(data['strecken'])} Strecken)")
