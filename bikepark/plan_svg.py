#!/usr/bin/env python3
"""Erzeugt aus einem Streckenplan (JSON) einen SVG-Plan: Draufsicht + Hoehenprofil.

Die Draufsicht wird nicht gemalt, sondern gerechnet: jeder Anlieger und jeder
Wallride biegt die Mittellinie um einen Winkel, der sich aus seiner Laenge und
seiner Neigung ergibt.

    Kurvenradius aus der Querneigung:   R = v^2 / (g * tan(phi))
    Richtungsaenderung ueber die Laenge: dpsi = laenge / R

v ist dabei das TEMPO AN DIESER STELLE, nicht eine Konstante. Mit einer festen
Referenzgeschwindigkeit von 11 m/s werden alle Anlieger drei- bis viermal zu eng
fuer die realen 18-20 m/s, und der Plan zeigt Haarnadeln, wo Weitkurven stehen.

Aufruf: python3 plan_svg.py strecken.json ausgabeordner/
"""
import json, math, sys, os

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

G      = 9.81
BG     = "#0a0a0c"
LINE   = "#4fd1c5"
JUMP   = "#ff9d4d"
WALL   = "#d9a441"
LABEL  = "#8b8b95"
GRID   = "#1c1c22"
ROCK   = "#6b7a8f"
STEEP  = "#3f7d74"

SPRUNG = {"kicker", "tabletop", "step_up", "step_down", "drop", "hip"}
KUERZEL = {"anlieger":"AN","wallride":"WR","tabletop":"TT","kicker":"KI","step_up":"SU",
           "step_down":"SD","drop":"DR","hip":"HI","roller":"RO","steinfeld":"SF",
           "steilstueck":"ST"}


def farbe(typ):
    if typ == "wallride": return WALL
    if typ in SPRUNG:     return JUMP
    if typ == "steinfeld":return ROCK
    if typ == "steilstueck": return STEEP
    return LINE


# ---------------------------------------------------------------- Mittellinie
def tempo_profil(track, hp, schritt=2.0):
    """Grobes Tempo aus dem Hoehenprofil allein - ohne Kurven, ohne Bremsen.
    Wird gebraucht, bevor die Kurven feststehen."""
    L = track["laenge_m"]
    n = int(L/schritt) + 2
    v = [3.0]
    m, CdA, rho = 88.0, 0.48, 1.225
    steinfelder = [(e["start_m"], e["start_m"]+e["laenge_m"])
                   for e in track["elemente"] if e["typ"] == "steinfeld"]
    for i in range(1, n):
        s = i*schritt
        dh = hoehe_bei(hp, s-schritt) - hoehe_bei(hp, s)
        th = math.atan(dh/schritt)
        crr = 0.016 * (3.4 if any(a <= s <= b for a, b in steinfelder) else 1.0)
        vv = max(v[-1], 2.0)
        a = G*math.sin(th) - G*math.cos(th)*crr - 0.5*rho*CdA*vv*vv/m
        v.append(max(2.5, min(28.0, math.sqrt(max(6.25, vv*vv + 2*a*schritt)))))
    return lambda s: v[max(0, min(int(round(s/schritt)), n-1))]


def mittellinie(track, hp, schritt=2.0):
    """Integriert die Strecke in der Draufsicht. Gibt [(s, x, z)] zurueck."""
    L = track["laenge_m"]
    v_bei = tempo_profil(track, hp)
    # Wachsendes psi dreht nach LINKS (rechts = vorwaerts x oben in einem
    # rechtshaendigen Y-Up-System). Muss mit dem 3D-Generator uebereinstimmen.
    kurven = []          # (start, ende, dpsi_pro_meter)
    for e in track["elemente"]:
        if e["typ"] == "anlieger":
            phi = math.radians(e["neigung_grad"])
            v   = v_bei(e["start_m"] + e["laenge_m"]/2)
            R   = max(10.0, min(65.0, v*v / (G * math.tan(phi))))
            vz  = 1 if e["richtung"] == "links" else -1
            kurven.append((e["start_m"], e["start_m"] + e["laenge_m"], vz / R))
        elif e["typ"] == "wallride":
            # Der Wallride zieht weiter als ein Anlieger: der Fahrer laeuft die
            # Wand hoch, statt eng zu ziehen. Wirksame Neigung deshalb 52 Grad.
            v  = v_bei(e["start_m"] + e["laenge_m"]/2)
            R  = max(14.0, min(45.0, v*v / (G * math.tan(math.radians(52)))))
            vz = 1 if e["seite"] == "links" else -1
            kurven.append((e["start_m"], e["start_m"] + e["laenge_m"], vz / R))

    pts, psi, x, z, s = [], 0.0, 0.0, 0.0, 0.0
    while s <= L:
        rate = sum(k for a, b, k in kurven if a <= s < b)
        # Leichte Drift auf Geraden, damit der Plan nicht wie ein Lineal aussieht.
        # Deterministisch aus s, damit derselbe Plan immer gleich aussieht.
        if rate == 0.0:
            rate = 0.0016 * math.sin(s / 61.0) + 0.0011 * math.sin(s / 137.0 + 2.0)
        psi += rate * schritt
        x   += math.sin(psi) * schritt
        z   += math.cos(psi) * schritt
        pts.append((s, x, z))
        s   += schritt
    return pts


def punkt_bei(pts, s):
    if s <= pts[0][0]:  return pts[0][1], pts[0][2]
    if s >= pts[-1][0]: return pts[-1][1], pts[-1][2]
    i = min(int(s / (pts[1][0] - pts[0][0])), len(pts) - 2)
    a, b = pts[i], pts[i + 1]
    t = (s - a[0]) / (b[0] - a[0]) if b[0] > a[0] else 0
    return a[1] + t * (b[1] - a[1]), a[2] + t * (b[2] - a[2])


def hoehe_bei(hp, s):
    if s <= hp[0]["s_m"]:  return hp[0]["hoehe_m"]
    if s >= hp[-1]["s_m"]: return hp[-1]["hoehe_m"]
    for i in range(len(hp) - 1):
        a, b = hp[i], hp[i + 1]
        if a["s_m"] <= s <= b["s_m"]:
            t = (s - a["s_m"]) / (b["s_m"] - a["s_m"])
            return a["hoehe_m"] + t * (b["hoehe_m"] - a["hoehe_m"])
    return hp[-1]["hoehe_m"]


# ------------------------------------------------------------------- Symbole
def symbol(typ, cx, cy, col):
    """Jeder Typ hat eine eigene FORM, nicht nur eine eigene Farbe -
    der Plan bleibt so auch in Graustufen und fuer Farbfehlsichtige lesbar."""
    s = ''
    if typ == "anlieger":
        s = f'<path d="M{cx-5:.1f},{cy+4:.1f} A6,6 0 0 1 {cx+5:.1f},{cy+4:.1f}" fill="none" stroke="{col}" stroke-width="2"/>'
    elif typ == "wallride":
        s = (f'<rect x="{cx-2:.1f}" y="{cy-7:.1f}" width="4" height="14" fill="{col}"/>'
             f'<path d="M{cx+2:.1f},{cy+7:.1f} L{cx+8:.1f},{cy+7:.1f}" stroke="{col}" stroke-width="1.5" fill="none"/>')
    elif typ == "tabletop":
        s = f'<path d="M{cx-7:.1f},{cy+5:.1f} L{cx-3:.1f},{cy-5:.1f} L{cx+3:.1f},{cy-5:.1f} L{cx+7:.1f},{cy+5:.1f} Z" fill="{col}"/>'
    elif typ == "kicker":
        s = (f'<path d="M{cx-7:.1f},{cy+5:.1f} L{cx-1:.1f},{cy-6:.1f} L{cx-1:.1f},{cy+5:.1f} Z" fill="{col}"/>'
             f'<path d="M{cx+3:.1f},{cy+5:.1f} L{cx+8:.1f},{cy+1:.1f}" stroke="{col}" stroke-width="2" fill="none"/>')
    elif typ == "step_up":
        s = f'<path d="M{cx-7:.1f},{cy+5:.1f} L{cx-1:.1f},{cy+5:.1f} L{cx-1:.1f},{cy-2:.1f} L{cx+7:.1f},{cy-2:.1f} L{cx+7:.1f},{cy-6:.1f}" fill="none" stroke="{col}" stroke-width="2"/>'
    elif typ == "step_down":
        s = f'<path d="M{cx-7:.1f},{cy-6:.1f} L{cx-7:.1f},{cy-2:.1f} L{cx+1:.1f},{cy-2:.1f} L{cx+1:.1f},{cy+5:.1f} L{cx+7:.1f},{cy+5:.1f}" fill="none" stroke="{col}" stroke-width="2"/>'
    elif typ == "drop":
        s = (f'<path d="M{cx-6:.1f},{cy-4:.1f} L{cx:.1f},{cy-4:.1f} L{cx:.1f},{cy+6:.1f}" fill="none" stroke="{col}" stroke-width="2.5"/>'
             f'<path d="M{cx:.1f},{cy+6:.1f} L{cx+6:.1f},{cy+6:.1f}" stroke="{col}" stroke-width="1.5" fill="none"/>')
    elif typ == "hip":
        s = (f'<path d="M{cx-7:.1f},{cy+5:.1f} L{cx-1:.1f},{cy-6:.1f} L{cx-1:.1f},{cy+5:.1f} Z" fill="{col}"/>'
             f'<path d="M{cx+1:.1f},{cy-2:.1f} L{cx+8:.1f},{cy-5:.1f}" stroke="{col}" stroke-width="2" fill="none"/>'
             f'<path d="M{cx+8:.1f},{cy-5:.1f} l-3,-0.5 l1.5,2.5 Z" fill="{col}"/>')
    elif typ == "roller":
        s = f'<path d="M{cx-8:.1f},{cy+3:.1f} q2.7,-7 5.3,0 q2.7,-7 5.3,0 q2.7,-7 5.3,0" fill="none" stroke="{col}" stroke-width="2"/>'
    elif typ == "steinfeld":
        s = ''.join(f'<circle cx="{cx+dx:.1f}" cy="{cy+dy:.1f}" r="1.6" fill="{col}"/>'
                    for dx, dy in [(-6,2),(-2,-3),(2,3),(6,-1),(-4,-1),(4,1),(0,0)])
    elif typ == "steilstueck":
        s = ''.join(f'<path d="M{cx-6:.1f},{cy-5+i*5:.1f} L{cx:.1f},{cy-1+i*5:.1f} L{cx+6:.1f},{cy-5+i*5:.1f}" '
                    f'fill="none" stroke="{col}" stroke-width="1.8"/>' for i in range(2))
    return s


# ----------------------------------------------------------------------- SVG
def baue_svg(track):
    L  = track["laenge_m"]
    HM = track["hoehendifferenz_m"]
    el = track["elemente"]
    hp = track.get("hoehenprofil")
    if not hp or len(hp) < 2:                      # Notfallprofil: gleichmaessiges Gefaelle
        hp = [{"s_m": round(i*L/12, 1), "hoehe_m": round(HM*(1-i/12), 1)} for i in range(13)]
    pts = mittellinie(track, hp)

    W, H = 1240, 1030
    # --- Panel A: Draufsicht ---
    ax0, ay0, aw, ah = 60, 92, W - 120, 508
    # Die Strecke laeuft in einer beliebigen Richtung den Hang hinunter und fuellt
    # das Panel sonst nur zu einem Viertel. Deshalb der Winkel gesucht, bei dem
    # der eingepasste Massstab am groessten wird - reine Darstellung, die
    # Geometrie bleibt unveraendert.
    best, sc, rot = 0.0, 1.0, 0.0
    for k in range(72):
        a_ = k * math.pi / 36
        ca, sa = math.cos(a_), math.sin(a_)
        rx = [p[1]*ca - p[2]*sa for p in pts]
        rz = [p[1]*sa + p[2]*ca for p in pts]
        c = min((aw - 40) / max(max(rx) - min(rx), 1),
                (ah - 40) / max(max(rz) - min(rz), 1))
        if c > best: best, sc, rot = c, c, a_
    ca, sa = math.cos(rot), math.sin(rot)
    pts = [(p[0], p[1]*ca - p[2]*sa, p[1]*sa + p[2]*ca) for p in pts]
    xs = [p[1] for p in pts]; zs = [p[2] for p in pts]
    ox = ax0 + (aw - (max(xs) - min(xs)) * sc) / 2 - min(xs) * sc
    oz = ay0 + (ah - (max(zs) - min(zs)) * sc) / 2 - min(zs) * sc
    P = lambda x, z: (ox + x * sc, oz + z * sc)

    # --- Panel B: Hoehenprofil ---
    bx0, by0, bw, bh = 60, 660, W - 120, 250
    X = lambda s: bx0 + s / L * bw
    Y = lambda h: by0 + bh - h / HM * bh

    o = [f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {W} {H}" width="{W}" height="{H}" '
         f'font-family="ui-monospace,SFMono-Regular,Menlo,Consolas,monospace">',
         f'<rect width="{W}" height="{H}" fill="{BG}"/>',
         f'<text x="60" y="42" fill="#e6e6ea" font-size="21">{track["name"]}</text>',
         f'<text x="60" y="63" fill="{LABEL}" font-size="11">{L:.0f} m &#183; {HM:.0f} hm &#183; '
         f'{HM/L*100:.1f} % Durchschnittsgef&#228;lle &#183; {len(el)} Elemente</text>',
         f'<text x="60" y="84" fill="{LABEL}" font-size="11">DRAUFSICHT &#8212; Kurvenradien aus '
         f'Neigung und &#246;rtlichem Tempo gerechnet (R = v&#178;/g&#183;tan&#966;)</text>']

    # Draufsicht: Startmarke, Linie, Zielmarke
    x0, z0 = P(pts[0][1], pts[0][2]); x1, z1 = P(pts[-1][1], pts[-1][2])
    d = "M" + " L".join(f"{P(p[1],p[2])[0]:.1f},{P(p[1],p[2])[1]:.1f}" for p in pts)
    o.append(f'<path d="{d}" fill="none" stroke="{LINE}" stroke-width="2.4" stroke-linejoin="round"/>')
    # 100-m-Marken auf der Linie
    for m in range(0, int(L) + 1, 100):
        px, pz = P(*punkt_bei(pts, m))
        o.append(f'<circle cx="{px:.1f}" cy="{pz:.1f}" r="1.8" fill="{LABEL}"/>')
        if m % 200 == 0:
            o.append(f'<text x="{px+5:.1f}" y="{pz-4:.1f}" fill="{LABEL}" font-size="11">{m}</text>')
    o.append(f'<circle cx="{x0:.1f}" cy="{z0:.1f}" r="5" fill="none" stroke="#e6e6ea" stroke-width="2"/>'
             f'<text x="{x0+9:.1f}" y="{z0+4:.1f}" fill="#e6e6ea" font-size="11">START</text>')
    o.append(f'<rect x="{x1-4:.1f}" y="{z1-4:.1f}" width="8" height="8" fill="#e6e6ea"/>'
             f'<text x="{x1+9:.1f}" y="{z1+4:.1f}" fill="#e6e6ea" font-size="11">ZIEL</text>')

    # Elementsymbole in der Draufsicht, mit Nummer
    for i, e in enumerate(el, 1):
        mid = e["start_m"] + footprint(e) / 2
        px, pz = P(*punkt_bei(pts, mid))
        # Versatz senkrecht zur Linie, damit das Symbol die Linie nicht verdeckt
        a, b = punkt_bei(pts, max(mid - 6, 0)), punkt_bei(pts, min(mid + 6, L))
        dx, dz = b[0] - a[0], b[1] - a[1]
        n = math.hypot(dx, dz) or 1
        nx, nz = -dz / n * 17, dx / n * 17
        cx, cy = px + nx, pz + nz
        col = farbe(e["typ"])
        o.append(f'<path d="M{px:.1f},{pz:.1f} L{cx:.1f},{cy:.1f}" stroke="{GRID}" stroke-width="1"/>')
        o.append(symbol(e["typ"], cx, cy, col))
        o.append(f'<text x="{cx:.1f}" y="{cy-10:.1f}" fill="{LABEL}" font-size="11" text-anchor="middle">{i}</text>')

    # --- Hoehenprofil ---
    o.append(f'<text x="60" y="632" fill="{LABEL}" font-size="11">H&#214;HENPROFIL &#8212; '
             f'x: Strecke in m, y: H&#246;he in m</text>')
    for h in range(0, int(HM) + 1, 50):
        o.append(f'<path d="M{bx0},{Y(h):.1f} L{bx0+bw},{Y(h):.1f}" stroke="{GRID}" stroke-width="1"/>')
        o.append(f'<text x="{bx0-8}" y="{Y(h)+4:.1f}" fill="{LABEL}" font-size="11" text-anchor="end">{h}</text>')
    for m in range(0, int(L) + 1, 200):
        o.append(f'<path d="M{X(m):.1f},{by0} L{X(m):.1f},{by0+bh}" stroke="{GRID}" stroke-width="1"/>')
        o.append(f'<text x="{X(m):.1f}" y="{by0+bh+18:.1f}" fill="{LABEL}" font-size="11" text-anchor="middle">{m}</text>')

    prof = "M" + " L".join(f"{X(p['s_m']):.1f},{Y(p['hoehe_m']):.1f}" for p in hp)
    # Steilstuecke im Profil hervorheben
    for e in el:
        if e["typ"] != "steilstueck": continue
        a, b = e["start_m"], e["start_m"] + e["laenge_m"]
        o.append(f'<path d="M{X(a):.1f},{Y(hoehe_bei(hp,a)):.1f} L{X(b):.1f},{Y(hoehe_bei(hp,b)):.1f}" '
                 f'stroke="{STEEP}" stroke-width="7" stroke-linecap="round" opacity="0.55"/>')
    o.append(f'<path d="{prof}" fill="none" stroke="{LINE}" stroke-width="2.4"/>')

    # Regelzonen markieren
    o.append(f'<path d="M{bx0},{by0+bh} L{X(150):.1f},{by0+bh}" stroke="#e6e6ea" stroke-width="3"/>'
             f'<text x="{X(75):.1f}" y="{by0+bh+34:.1f}" fill="{LABEL}" font-size="11" text-anchor="middle">'
             f'0&#8211;150 m sprungfrei</text>')
    o.append(f'<path d="M{X(L-120):.1f},{by0+bh} L{bx0+bw},{by0+bh}" stroke="#e6e6ea" stroke-width="3"/>'
             f'<text x="{X(L-60):.1f}" y="{by0+bh+34:.1f}" fill="{LABEL}" font-size="11" text-anchor="middle">'
             f'letzte 120 m</text>')
    o.append(f'<path d="M{X(L*0.6):.1f},{by0} L{X(L*0.6):.1f},{by0+bh} L{X(L*0.7):.1f},{by0+bh} '
             f'L{X(L*0.7):.1f},{by0}" fill="none" stroke="{JUMP}" stroke-width="1" stroke-dasharray="3 3"/>'
             f'<text x="{X(L*0.65):.1f}" y="{by0-32:.1f}" fill="{JUMP}" font-size="11" text-anchor="middle">'
             '60&#8211;70 %: gr&#246;&#223;ter Sprung</text>')

    # Elemente im Profil
    for i, e in enumerate(el, 1):
        mid = e["start_m"] + footprint(e) / 2
        cx, cy = X(mid), Y(hoehe_bei(hp, mid))
        col = farbe(e["typ"])
        yv = max(by0 + 12, cy - 22 if i % 2 else cy - 40)
        o.append(f'<path d="M{cx:.1f},{cy:.1f} L{cx:.1f},{yv+8:.1f}" stroke="{GRID}" stroke-width="1"/>')
        o.append(symbol(e["typ"], cx, yv, col))
        o.append(f'<text x="{cx:.1f}" y="{yv-10:.1f}" fill="{LABEL}" font-size="11" text-anchor="middle">{i}</text>')

    # Legende
    lx, ly = 60, 996
    for j, (t, txt) in enumerate([("anlieger","Anlieger"),("wallride","Wallride"),("tabletop","Tabletop"),
                                  ("kicker","Kicker"),("step_up","Step-up"),("step_down","Step-down"),
                                  ("drop","Drop"),("hip","Hip"),("roller","Roller"),
                                  ("steinfeld","Steinfeld"),("steilstueck","Steilst&#252;ck")]):
        px = lx + j * 108
        o.append(symbol(t, px + 8, ly, farbe(t)))
        o.append(f'<text x="{px+20}" y="{ly+4}" fill="{LABEL}" font-size="11">{txt}</text>')

    o.append('</svg>')
    return "\n".join(o)


if __name__ == "__main__":
    data = json.load(open(sys.argv[1], encoding="utf-8"))
    out = sys.argv[2] if len(sys.argv) > 2 else "."
    os.makedirs(out, exist_ok=True)
    tracks = data["strecken"] if isinstance(data, dict) and "strecken" in data else [data]
    for t in tracks:
        key = t.get("key") or t["name"].lower().replace(" ", "-")
        p = os.path.join(out, f"plan-{key}.svg")
        open(p, "w", encoding="utf-8").write(baue_svg(t))
        print("geschrieben:", p)
