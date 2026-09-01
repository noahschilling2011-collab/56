# Bikepark — Streckenplan und Prüfstand

Drei Bikepark-Abfahrten als **feste Streckendefinition** statt Zufallsgenerator: bei jedem
Run liegt derselbe Sprung an derselben Stelle.

| Datei | Was drin ist |
|---|---|
| `strecken.json` | Die Elementlisten. Das ist die Quelle, alles andere wird daraus erzeugt. |
| `bikepark-pruefstand.html` | Fertige Datei. Baut die Strecke aus dem JSON und lässt sie fahren. |
| `plan-*.svg` | Draufsicht + Höhenprofil je Strecke. |
| `validate.py` | Prüft ein JSON gegen alle Bau- und Strukturregeln. |
| `plan_svg.py` | Erzeugt die SVG-Pläne. |
| `build.py` | `template.html` + `strecken.json` → fertige HTML. |
| `template.html` | Quelle der HTML, mit `__STRECKEN_JSON__` als Platzhalter. |

```bash
python3 validate.py strecken.json      # Regeln prüfen, Exit 1 bei Fehlern
python3 plan_svg.py  strecken.json .   # SVG-Pläne
python3 build.py                       # bikepark-pruefstand.html neu bauen
python3 -m http.server 8000            # dann http://localhost:8000/bikepark-pruefstand.html
```

Die HTML **braucht einen Server**. Per Doppelklick öffnet sie sich mit leerem Bild, weil
ES-Module unter `file://` von der CORS-Regel blockiert werden. Das ist Browser-Verhalten,
kein Fehler in der Datei.

---

## Zwei Konventionen, die man falsch verstehen kann

**`richtung` und `seite` sind die KURVENRICHTUNG, nicht die Bauseite.**
Die Bank steht immer auf der Kurvenaußenseite — bei einer Linkskurve also rechts vom Fahrer.
Das gilt für Anlieger und Wallride gleich, deshalb ist die Regel „Anlieger vor dem Wallride in
dieselbe Richtung" physikalisch stimmig: beide beschreiben dieselbe Drehung.

Der naive Gegenentwurf („seite = wo die Wand steht") kehrt die Bedeutung um: eine Wand links
vom Fahrer drückt ihn nach rechts, ist also eine Rechtskurve. Dann müsste vor einem
`seite: links`-Wallride ein `richtung: rechts`-Anlieger stehen — die Regel läse sich falsch
herum. Deshalb diese Wahl.

**`hoehe_m` beim Wallride ist die Höhe der Wand über ihrem eigenen Fuß**, nicht über der
Trailmitte. Der Trailboden ist zur Wand hin leicht geneigt; diese 14° kommen nicht dazu.

---

## Warum die Querneigung eine Funktion ist und keine Zahl

Die naheliegende Umsetzung eines Wallrides — „Querneigung lokal von 31° auf 70–85° hochziehen" —
funktioniert nicht. Wenn der *ganze* Querschnitt auf 80° kippt, gibt es keine Fläche mehr, auf
der man ankommt und auf die man zurückkommt. Der Fahrer müsste sich permanent mit Fliehkraft
oben halten, wie im Steilwandzelt. Die dafür nötige Geschwindigkeit auf einem Wandradius von
25 m: `v = √(g·R·tan 80°) = √(9,81 · 25 · 5,67) ≈ 37 m/s = 134 km/h`. Auf einer Bikepark-Strecke
gibt es das nicht.

Ein echter Wallride ist Trailboden **plus** aufsteigende Seitenwand. Die Neigung hängt also von
der Querposition ab. In `querV(qs, u)`:

```
x        Querposition, 0 in der Trailmitte, positiv nach kurvenaußen
kante    breite/2 − FILLET       wo der Boden in die Wand übergeht
W        FILLET + h/tan φ        horizontale Ausdehnung der Wandkurve
p        1 + FILLET·tan φ / h    Exponent

v(x) = Bodenneigung bis zur kante,  danach  + h · ((x−kante)/W)^p
```

Der Exponent ist nicht geraten: er ist so gewählt, dass die Neigung an der Oberkante **exakt φ**
ist und die Wand dort **exakt h** erreicht. Am Fuß ist die Ableitung dagegen null, es gibt also
keine harte Kante, in die man fährt.

Nachgemessen im Prüfstand bei `hoehe_m: 3,0`, `neigung_grad: 78`:
Wandhöhe über dem Fuß **3,00 m**, Grundfläche **0,64 m** = `3/tan 78°`. Stimmt.

Derselbe Mechanismus baut die Anliegerwange — ein Anlieger ist ein niedriger, flacherer
Wallride. Ein Codepfad, zwei Elemente.

---

## Was der Prüfstand sonst noch anders macht als erwartet

**Kollision ohne Raycast.** Die Fahrfläche ist analytisch: `hoehe(s) + querV(qs, u)`. Ein
Raycast gegen das Mesh wäre teurer und an der Drop-Kante mehrdeutig — dort träfe der Strahl
zwei Flächen.

**Der Absprung entsteht von selbst.** Die Höhe wird immer ballistisch integriert und danach
gegen die Fläche geklemmt. Auf der Kickerrampe ist `vy = dh/ds · vs` positiv; hinter der Lippe
fällt die Fläche weg und der Fahrer ist in der Luft. Es gibt keine Sonderregel „hier abspringen".

**Der Drop ist nicht senkrecht, sondern 0,35 m lang.** Bei exakt null Lauflänge entstehen
entartete Dreiecke. 0,35 m sind bei 1,5 m Stationsabstand schmal genug, dass es sich wie eine
Kante fährt.

**Der Querschnitt wird nach Bogenlänge abgetastet.** Bei 78° liegen 3 m Höhe auf 0,64 m
Grundfläche. Gleichmäßige Abtastung in `x` gäbe der ganzen Wand drei Stützpunkte.

**Der Trail liegt im Hang, nicht auf einem Rücken.** Bergseits eine Anschnittsböschung,
talseits ein Abfall. Welche Seite bergseits ist, folgt aus der Falllinie der Gesamtstrecke.

---

## Die beiden Räder

Der Unterschied ist nicht kosmetisch:

| | MTB | eMTB |
|---|---|---|
| Systemmasse | 88 kg | 113 kg |
| CdA | 0,48 m² | 0,50 m² |
| Rollwiderstand | 0,016 | 0,019 |
| Motor | — | 620 W bis 25 km/h |
| Kontrolle in der Luft | 5,2 m/s² | 3,6 m/s² |

Das eMTB schiebt aus langsamen Stellen heraus mit, ist aber träger in der Luft und verzeiht
eine verpasste Landung schlechter. Die Werte sind plausible Größenordnungen, keine Messwerte
an einem realen Rad.

## Die GLB-Datei

Liegt `mtb-emtb-fahrerin.glb` neben der HTML, wird sie geladen, eingemessen und auf 1,80 m
skaliert. Über ihren Inhalt wird **nichts** angenommen: keine Node-Namen, keine Materialien,
keine Achsenkonvention. Fehlt sie, fährt ein Ersatzfahrer aus Primitiven.

Schaut die Fahrerin nach dem Laden rückwärts, steht die Blickrichtung der Datei anders als
angenommen — dann `GLB_DREHUNG` in der HTML von `Math.PI` auf `0` setzen.

---

## Nachgemessen

Alle Zahlen aus einem headless gefahrenen Lauf (`window.bikepark.schritt` in festen
8-ms-Schritten, Vollgas, ohne Bremsen und ohne Lenken — also eine untere Zeitschranke;
wer in die Anlieger bremst, ist langsamer).

| Strecke | Rad | Zeit | ø | max | Luftzeit | Randkontakte |
|---|---|---|---|---|---|---|
| Downhill Republic | MTB | 2:33 | 45 km/h | 77 km/h | 32,9 s | 4 |
| Downhill Republic | eMTB | 2:27 | 47 km/h | 79 km/h | 32,8 s | 4 |
| Alpin | MTB | 2:44 | 42 km/h | 79 km/h | 39,6 s | 1 |
| Alpin | eMTB | 2:37 | 44 km/h | 81 km/h | 37,9 s | 1 |
| Canyon | MTB | 2:21 | 48 km/h | 76 km/h | 24,7 s | 3 |
| Canyon | eMTB | 2:13 | 51 km/h | 78 km/h | 23,3 s | 3 |

Vorgabe war „etwa 3 Minuten für einen guten Fahrer". 2:33 bei Vollgas ohne Bremsen passt
dazu: mit realistischem Bremsen in den Anliegern landet man um 3:00.

Der Alpin-Charakter zeigt sich in der Luftzeit (39,6 s gegen 24,7 s bei Canyon), der
Canyon-Charakter im Schnitt (48 gegen 42 km/h).

### Der Fund, der die Zahlen erst brauchbar gemacht hat

Im ersten Durchlauf hatte Canyon **29 Randkontakte**, die anderen 1 bis 7. Ursache: die
Kurvenradien kamen aus einer festen Referenzgeschwindigkeit von 11 m/s.

```
R = v² / (g · tan φ)
40°-Anlieger:  bei 11 m/s → R = 14,7 m
               bei 20 m/s → R = 48,6 m nötig
```

Jeder Anlieger war also drei- bis viermal zu eng für das Tempo, mit dem der Fahrer
tatsächlich ankommt — er wurde oben über die Bank getragen. Der Generator schätzt jetzt in
einem ersten Durchgang das Tempo aus dem Höhenprofil (Schwerkraft, Luft- und Rollwiderstand,
Steinfelder bremsend) und leitet daraus jeden Radius ab. **29 → 3 Randkontakte.**

Nebeneffekt: die Draufsicht zeigt jetzt Weitkurven statt Haarnadeln — was einer echten
Lift-Strecke deutlich näher kommt.
