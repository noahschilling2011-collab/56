#!/usr/bin/env python3
"""Prueft Bikepark-Streckenplaene mechanisch gegen Struktur- und Bauregeln.

Aufruf:  python3 validate.py strecken.json
Exit 0 = keine Fehler, Exit 1 = Fehler gefunden.
"""
import json, sys, math

# --- Footprint eines Elements. MUSS mit sprungGeometrie() in template.html uebereinstimmen. ---
# laenge_m bedeutet je nach Typ:  tabletop/hip = Tischlaenge, step_up/step_down = Gap+Landung,
# kicker = Rampe+Gap+Landung. Absprung/Landung kommen bei den ersten beiden dazu.
LIPPE_GRAD = {"tabletop": 38, "kicker": 42, "step_up": 40, "step_down": 22, "hip": 40}

def footprint(e):
    t, L = e["typ"], e.get("laenge_m", 0) or 0
    tanA = math.tan(math.radians(LIPPE_GRAD.get(t, 30)))
    if t in ("tabletop", "hip"): return 2 * (2 * e["hoehe_m"] / tanA) + L
    if t == "step_up":           return 2 * (0.6 * e["hoehenversatz_m"] + 0.4) / tanA + L
    if t == "step_down":         return 2 * 0.5 / tanA + L
    return L

def el_ende(e): return e["start_m"] + footprint(e)

SPRUNG = {"kicker", "tabletop", "step_up", "step_down", "drop", "hip"}

# typ -> (pflichtfelder, wertebereiche{feld:(min,max)}, enums{feld:[...]})
SPEC = {
    "anlieger":    (["laenge_m","richtung","neigung_grad","hoehe_m","breite_m"],
                    {"hoehe_m":(0.6,1.8),"neigung_grad":(25,45),"breite_m":(2.5,6.0),"laenge_m":(6,60)},
                    {"richtung":["links","rechts"]}),
    "wallride":    (["laenge_m","seite","hoehe_m","neigung_grad","material"],
                    {"hoehe_m":(1.8,4.5),"neigung_grad":(70,85),"laenge_m":(10,25)},
                    {"seite":["links","rechts"],"material":["holz","beton"]}),
    "tabletop":    (["laenge_m","hoehe_m","breite_m"],
                    {"laenge_m":(3,9),"hoehe_m":(1.0,3.0),"breite_m":(2.5,6.0)}, {}),
    # laenge_m beim Kicker ist Rampe + Gap + Landung. Die Aufgabenstellung nennt
    # dafuer keine Grenze; 28 m deckt einen 14-m-Gap mit Rampe und Landung ab.
    "kicker":      (["laenge_m","absprunghoehe_m","gapweite_m","grubentiefe_m"],
                    {"absprunghoehe_m":(0.6,2.5),"gapweite_m":(2,14),"grubentiefe_m":(0.0,1.5),
                     "laenge_m":(3,28)}, {}),
    "step_up":     (["laenge_m","hoehenversatz_m"],
                    {"laenge_m":(3,9),"hoehenversatz_m":(0.3,2.5)}, {}),
    "step_down":   (["laenge_m","hoehenversatz_m"],
                    {"laenge_m":(3,14),"hoehenversatz_m":(0.3,3.0)}, {}),
    "drop":        (["hoehe_m"], {"hoehe_m":(0.2,0.9),"laenge_m":(0,0)}, {}),
    "hip":         (["laenge_m","hoehe_m","seitenversatz_m","richtung"],
                    {"laenge_m":(3,12),"hoehe_m":(0.8,2.5),"seitenversatz_m":(0.5,3.0)},
                    {"richtung":["links","rechts"]}),
    "roller":      (["laenge_m","anzahl","hoehe_m"],
                    {"hoehe_m":(0.3,1.2),"anzahl":(2,10),"laenge_m":(6,60)}, {}),
    "steinfeld":   (["laenge_m"], {"laenge_m":(8,60)}, {}),
    "steilstueck": (["laenge_m","gefaelle_prozent"],
                    {"laenge_m":(20,140),"gefaelle_prozent":(18,45)}, {}),
}

FUELLWORT = ["sorgt fuer flow","sorgt für flow","macht spass","macht spaß","fuer den flow",
             "für den flow","sieht gut aus","bringt abwechslung","ist spassig","ist spaßig"]


def groesse(e):
    """Ein Mass fuer 'wie gross ist dieser Sprung' - zum Finden des groessten."""
    t = e["typ"]
    if t == "kicker":    return e.get("gapweite_m", 0) + e.get("absprunghoehe_m", 0)
    if t == "tabletop":  return e.get("laenge_m", 0) * 0.8 + e.get("hoehe_m", 0)
    if t == "step_up":   return e.get("laenge_m", 0) * 0.7 + e.get("hoehenversatz_m", 0)
    if t == "step_down": return e.get("laenge_m", 0) * 0.7 + e.get("hoehenversatz_m", 0)
    if t == "hip":       return e.get("laenge_m", 0) * 0.7 + e.get("hoehe_m", 0)
    if t == "drop":      return e.get("hoehe_m", 0)
    return 0


def pruefe(track):
    F, W = [], []          # Fehler (hart), Warnungen (weich)
    name = track.get("name", "?")
    L = track["laenge_m"]
    HM = track["hoehendifferenz_m"]
    el = track["elemente"]

    def f(msg): F.append(f"[{name}] {msg}")
    def w(msg): W.append(f"[{name}] {msg}")

    # --- Struktur ---
    for i, e in enumerate(el):
        t = e.get("typ")
        if t not in SPEC:
            f(f"#{i}: unbekannter typ {t!r}"); continue
        pflicht, bereiche, enums = SPEC[t]
        for p in pflicht:
            if p not in e: f(f"#{i} {t} @{e.get('start_m')}m: Feld {p} fehlt")
        for k, (lo, hi) in bereiche.items():
            if k in e and not (lo <= e[k] <= hi):
                f(f"#{i} {t} @{e.get('start_m')}m: {k}={e[k]} ausserhalb {lo}-{hi}")
        for k, ok in enums.items():
            if k in e and e[k] not in ok:
                f(f"#{i} {t} @{e.get('start_m')}m: {k}={e[k]!r} nicht in {ok}")
        erlaubt = set(pflicht) | {"typ", "start_m", "notiz"} | ({"laenge_m"} if t == "drop" else set())
        for k in e:
            if k not in erlaubt: w(f"#{i} {t} @{e.get('start_m')}m: unbekanntes Feld {k!r}")
        n = (e.get("notiz") or "").strip()
        if len(n) < 25: f(f"#{i} {t} @{e.get('start_m')}m: notiz zu kurz/leer (Regel 9)")
        elif any(x in n.lower() for x in FUELLWORT) and len(n) < 70:
            w(f"#{i} {t} @{e.get('start_m')}m: notiz klingt nach Fuellsatz (Regel 9)")

    # Kicker: laenge_m ist Anlauf + Gap + Landung. Anlauf mindestens 3 m, Landung 0,3·Gap.
    for i, e in enumerate(el):
        if e.get("typ") == "kicker" and "gapweite_m" in e and "laenge_m" in e:
            noetig = 3 + e["gapweite_m"] + max(3, 0.3*e["gapweite_m"])
            if e["laenge_m"] < noetig - 1e-6:
                f(f"#{i} kicker @{e['start_m']}m: laenge_m={e['laenge_m']} < Anlauf 3 + Gap {e['gapweite_m']} "
                  f"+ Landung {max(3, 0.3*e['gapweite_m']):.1f} = {noetig:.1f}")

    # Sortierung + Ueberlappung
    for i in range(len(el) - 1):
        a, b = el[i], el[i + 1]
        if b["start_m"] < a["start_m"]:
            f(f"#{i}->#{i+1}: nicht aufsteigend ({a['start_m']} -> {b['start_m']})")
        ende_a = el_ende(a)
        if ende_a > b["start_m"] + 1e-6:
            f(f"#{i} {a['typ']} endet @{ende_a:.1f}m (Footprint), #{i+1} {b['typ']} startet @{b['start_m']}m "
              f"- Ueberlappung {ende_a - b['start_m']:.1f}m")
    if el:
        e_l = el_ende(el[-1])
        if e_l > L: f(f"letztes Element endet @{e_l:.1f}m > Streckenlaenge {L}m")

    # --- Regel 3: erste 150 m ohne Sprung ---
    for i, e in enumerate(el):
        if e["typ"] in SPRUNG and e["start_m"] < 150:
            f(f"Regel 3: #{i} {e['typ']} @{e['start_m']}m liegt in den ersten 150 m")

    # --- Regel 7: letzte 120 m ohne Sprung/Wallride, aber mit Anlieger ---
    zone = L - 120
    for i, e in enumerate(el):
        if el_ende(e) > zone and e["typ"] in SPRUNG | {"wallride"}:
            f(f"Regel 7: #{i} {e['typ']} @{e['start_m']}m reicht in die letzten 120 m (ab {zone}m)")
    if not any(e["typ"] == "anlieger" and e["start_m"] >= zone for e in el):
        f(f"Regel 7: kein Anlieger in den letzten 120 m (ab {zone}m)")

    # --- Regel 2: Wallride-Dichte ---
    wr = [e for e in el if e["typ"] == "wallride"]
    maxwr = min(4, int(L // 500))
    if len(wr) > maxwr:
        f(f"Regel 2: {len(wr)} Wallrides, erlaubt sind {maxwr} (1 pro 500 m, max 4)")
    for i in range(len(wr) - 1):
        d = wr[i+1]["start_m"] - wr[i]["start_m"]
        if d < 500: f(f"Regel 2: Wallrides @{wr[i]['start_m']}m und @{wr[i+1]['start_m']}m nur {d}m auseinander")

    # --- Regel 1: Anlieger gleicher Richtung vor jedem Wallride ---
    for e in wr:
        vor = [x for x in el if x["typ"] == "anlieger" and x["start_m"] < e["start_m"]]
        if not vor:
            f(f"Regel 1: Wallride @{e['start_m']}m hat keinen Anlieger davor")
        else:
            a = vor[-1]
            luecke = e["start_m"] - (a["start_m"] + a.get("laenge_m", 0))
            if luecke > 40:
                f(f"Regel 1: Wallride @{e['start_m']}m - naechster Anlieger endet {luecke:.0f}m davor (max 40)")
            if a.get("richtung") != e.get("seite"):
                f(f"Regel 1: Wallride @{e['start_m']}m seite={e.get('seite')}, "
                  f"Anlieger davor richtung={a.get('richtung')} - muss gleich sein")
        nach = [x for x in el if x["start_m"] >= e["start_m"] + e.get("laenge_m", 0)]
        if not nach or nach[0]["start_m"] - (e["start_m"] + e.get("laenge_m", 0)) > 60:
            f(f"Regel 1: Wallride @{e['start_m']}m hat keine Ausleitung dahinter (Element binnen 60 m)")

    # --- Regel 4: Rhythmus-Sektionen ---
    # Ab welchem Abstand endet eine Sektion? Massgeblich ist die Zeit, nicht die
    # Laenge: bei 40-55 km/h (11-15 m/s) sind 35 m rund 2,5 s - so lange bleibt
    # man ohne Bremsen und Treten im Rhythmus. Ein engerer Wert (15 m = 1 s)
    # zerlegt echte Dreier-Ketten faelschlich in Einzelspruenge.
    SEKTIONSLUECKE = 35
    sekt, akt = [], []
    for e in el:
        if e["typ"] in SPRUNG:
            if akt and e["start_m"] - el_ende(akt[-1]) > SEKTIONSLUECKE:
                sekt.append(akt); akt = []
            akt.append(e)
        elif akt and e["typ"] in {"anlieger", "wallride", "steinfeld", "steilstueck"}:
            sekt.append(akt); akt = []
    if akt: sekt.append(akt)
    for s in sekt:
        if len(s) == 1:
            w(f"Regel 4: Einzelsprung {s[0]['typ']} @{s[0]['start_m']}m (Sektion aus 3-6 erwuenscht)")
        elif len(s) == 2:
            w(f"Regel 4: nur 2 Elemente ab @{s[0]['start_m']}m (3-6 erwuenscht)")
        elif len(s) > 6:
            f(f"Regel 4: {len(s)} Sprungelemente am Stueck ab @{s[0]['start_m']}m (max 6)")
    for i in range(len(sekt) - 1):
        a_ende = el_ende(sekt[i][-1])
        pause = sekt[i+1][0]["start_m"] - a_ende
        if pause < 80:
            f(f"Regel 4: nur {pause:.0f}m Erholung zwischen Sektion @{sekt[i][0]['start_m']}m "
              f"und @{sekt[i+1][0]['start_m']}m (min 80)")
        elif pause > 150:
            w(f"Regel 4: {pause:.0f}m Erholung nach Sektion @{sekt[i][0]['start_m']}m (Richtwert 80-150)")

    # --- Regel 5: Steinfeld vor Anlieger ---
    for i, e in enumerate(el):
        if e["typ"] != "steinfeld": continue
        nach = [x for x in el[i+1:] if x["start_m"] - (e["start_m"] + e["laenge_m"]) <= 45]
        if not any(x["typ"] == "anlieger" for x in nach):
            f(f"Regel 5: Steinfeld @{e['start_m']}m - kein Anlieger binnen 45 m danach")

    # --- Regel 6: groesster Sprung bei 60-70 % ---
    spr = [e for e in el if e["typ"] in SPRUNG]
    if spr:
        top = max(spr, key=groesse)
        p = top["start_m"] / L
        if not (0.58 <= p <= 0.72):
            f(f"Regel 6: groesster Sprung ({top['typ']} @{top['start_m']}m) liegt bei "
              f"{p*100:.0f}% statt 60-70% ({L*0.6:.0f}-{L*0.7:.0f}m)")

    # --- Regel 8: Steilstueck leitet ein ---
    for i, e in enumerate(el):
        if e["typ"] != "steilstueck": continue
        ende = e["start_m"] + e["laenge_m"]
        nach = [x for x in el[i+1:] if x["start_m"] - ende <= 40]
        if not nach:
            f(f"Regel 8: Steilstueck @{e['start_m']}m leitet in nichts hinein (nichts binnen 40 m)")

    # --- Hoehenprofil ---
    hp = track.get("hoehenprofil")
    if not hp:
        f("hoehenprofil fehlt")
    else:
        if abs(hp[0]["hoehe_m"] - HM) > 2:  f(f"hoehenprofil startet bei {hp[0]['hoehe_m']} statt {HM}")
        if abs(hp[-1]["hoehe_m"]) > 2:      f(f"hoehenprofil endet bei {hp[-1]['hoehe_m']} statt 0")
        if abs(hp[-1]["s_m"] - L) > 5:      f(f"hoehenprofil endet @{hp[-1]['s_m']}m statt {L}m")
        for i in range(len(hp) - 1):
            if hp[i+1]["hoehe_m"] > hp[i]["hoehe_m"] + 1e-6:
                f(f"hoehenprofil steigt bei s={hp[i+1]['s_m']}m an")
            if hp[i+1]["s_m"] <= hp[i]["s_m"]:
                f(f"hoehenprofil: s_m nicht aufsteigend bei Index {i+1}")
        # Steilstuecke gegen Profil
        for e in el:
            if e["typ"] != "steilstueck": continue
            g = profil_gefaelle(hp, e["start_m"], e["start_m"] + e["laenge_m"])
            if g is not None and abs(g - e["gefaelle_prozent"]) > 8:
                f(f"Steilstueck @{e['start_m']}m: deklariert {e['gefaelle_prozent']}%, "
                  f"Profil liefert {g:.0f}%")

    # --- Luecken ---
    grenzen = [0.0] + [el_ende(e) for e in el]
    starts  = [e["start_m"] for e in el] + [L]
    for i in range(len(starts)):
        d = starts[i] - grenzen[i]
        if d > 180: w(f"Luecke von {d:.0f}m zwischen @{grenzen[i]:.0f}m und @{starts[i]:.0f}m")

    if not (24 <= len(el) <= 34):
        w(f"{len(el)} Elemente (Zielbereich 24-34)")
    return F, W


def profil_gefaelle(hp, s0, s1):
    h0, h1 = hoehe_bei(hp, s0), hoehe_bei(hp, s1)
    if h0 is None or h1 is None or s1 <= s0: return None
    return (h0 - h1) / (s1 - s0) * 100


def hoehe_bei(hp, s):
    if s <= hp[0]["s_m"]:  return hp[0]["hoehe_m"]
    if s >= hp[-1]["s_m"]: return hp[-1]["hoehe_m"]
    for i in range(len(hp) - 1):
        a, b = hp[i], hp[i+1]
        if a["s_m"] <= s <= b["s_m"]:
            t = (s - a["s_m"]) / (b["s_m"] - a["s_m"])
            return a["hoehe_m"] + t * (b["hoehe_m"] - a["hoehe_m"])
    return None


if __name__ == "__main__":
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    tracks = data["strecken"] if isinstance(data, dict) and "strecken" in data else [data]
    nf = nw = 0
    for t in tracks:
        F, W = pruefe(t)
        nf += len(F); nw += len(W)
        print(f"\n=== {t.get('name')}: {len(F)} Fehler, {len(W)} Warnungen, {len(t['elemente'])} Elemente ===")
        for x in F: print("  FEHLER ", x)
        for x in W: print("  warnung", x)
    print(f"\nGESAMT: {nf} Fehler, {nw} Warnungen")
    sys.exit(1 if nf else 0)
