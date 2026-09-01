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

## Was `laenge_m` bedeutet — je nach Typ

So, wie es im Bikepark gesagt wird, und so, wie die Elementabstände in den Plänen es verlangen:

| Typ | `laenge_m` ist … | dazu kommen |
|---|---|---|
| tabletop, hip | die Länge des **Tisches** (Lippe bis Landungsbeginn) | Absprung `2H/tan 38°` davor, Landung gleich lang dahinter |
| step_up, step_down | Gap + Landung | Absprung davor |
| kicker | Anlauf + Gap + Landung, der ganze Footprint | nichts |

Der Grund: eine 2-m-Lippe bei 38° braucht 5,3 m Anlauf. „Tabletop 9 m lang, 2 m hoch" kann
also kein 9-m-Footprint sein — sonst wäre die Rampe 48° steil und würfe den Fahrer 15 m hoch
(gemessen, im ersten Durchlauf). Mit Tischlängen-Semantik stoßen die Elemente einer
Rhythmus-Sektion fast aneinander (2–4 m Luft), genau wie Regel 4 es will; in allen drei
Strecken gab es dabei genau eine Überlappung von 1,8 m.

`validate.py` und `plan_svg.py` rechnen denselben Footprint wie `sprungGeometrie()` in der HTML.

## Nachgemessen

Test-Fahrer: fährt Vollgas, bremst aber vor jedem Sprung mit 0,7 g auf das Zieltempo am
Rampenfuß — wie ein Fahrer, der die Strecke kennt. Kein Treten, kein Pumpen. Eine Landung
zählt als getroffen, wenn sie auf der Landung liegt (bis 1,5 m vor dem Landungsbeginn
toleriert); „hart" ist eine Normalgeschwindigkeit über 6 m/s beim Aufsetzen.

| Strecke | Zeit | Luftzeit | Sprünge getroffen | zu kurz | zu lang | harte Landungen |
|---|---|---|---|---|---|---|
| Downhill Republic | 2:45 | 27,4 s | 21 / 21 | 0 | 0 | 3 |
| Alpin | 2:46 | 27,8 s | 20 / 20 | 0 | 0 | 8 |
| Canyon | 2:25 | 20,2 s | 12 / 13 | 1 (2 m) | 0 | 6 |

Vorgabe war „etwa 3 Minuten für einen guten Fahrer". Ein Fahrer, der die Anlieger nicht
kennt und öfter bremst, liegt darüber.

Die harten Landungen sind fast alle Kicker-Landungen knapp auf dem Knuckle statt auf dem
Hang dahinter — casen, nicht stürzen.

### Was die Messung an den Strecken geändert hat

21 Elemente wurden nach der Messung angepasst; jede Änderung steht im `notiz`-Satz des
Elements. Das Muster ist immer dasselbe: **das zweite und dritte Glied einer Kette ist
kleiner als das erste.** Drei gleich hohe Tables im Abstand von 12 m sind ohne Treten
nicht zu fahren — die Rampe des zweiten frisst das Landetempo des ersten. Echte Bikeparks
bauen Ketten deshalb abnehmend.

Ein Element wurde getauscht: der größte Sprung von Downhill Republic (Kicker, 12 m Gap,
braucht 40 km/h am Rampenfuß) stand als zweites Kettenglied hinter einem 1,8-m-Table und kam
mit 29 km/h an. Jetzt ist er das erste Glied, direkt aus dem Steilstück, der Table folgt.

Zwei Strecken hatten Kicker mit `laenge_m: 8` bei 9–12 m Gap — die Designer von Alpin und
Canyon hatten die Länge anders gelesen als bei Downhill Republic. Der Validator prüft das
jetzt (`laenge_m ≥ 3 + Gap + 0,3·Gap`).

### Was am Modell falsch war und jetzt stimmt

Jeder Punkt kam aus der Messung, keiner aus dem Gefühl:

- **Absprungrampen als Smoothstep** über 38 % der Länge: bei 2,5 m Höhe auf 3,4 m ist die
  Mitte 48° steil, und der Fahrer löst sich *vor* der Lippe. Jetzt: Parabel, am Fuß flach,
  an der Lippe exakt der Lippenwinkel (Tables 38°, Kicker 42°, Step-down 22°).
- **Kicker-Rampen 3–4 m hoch** statt 0,8–2,3: die Parabel lief über den ganzen Anlauf.
  Jetzt: Rampe nur `2H/tanα` lang, davor flacher Anlauf.
- **Steigung mit zentraler Differenz** (±0,4 m): einen halben Meter vor der Lippe sah sie
  schon die Grube dahinter und zog den Fahrer *nach unten*, bevor er abhob. Jetzt rückwärts
  geschaut — die Fläche, auf der man ist.
- **Energie aus dem Nichts auf der Rampe**: `vy = tanα·vs` kam zu `vs` dazu, statt aus ihm
  zu werden. Jetzt ist `vs` die Geschwindigkeit entlang der Fläche, horizontal kommt man mit
  `vs·cosθ` voran, und beim Abheben wird sie zerlegt. Umgekehrt gibt die Landung Tempo
  zurück: der ankommende Vektor wird auf den Landehang projiziert.
- **Keine Federung**: eine Punktmasse hob über jeden 16-cm-Stein ab. Steinfelder liegen jetzt
  nur noch im Mesh (die Physik sieht erhöhten Rollwiderstand), und Wellen bis 1,5 g und
  0,48 m Federweg werden „geschluckt".
- **Anlieger als 17°-Ebene**: die README behauptete die Potenzkurve, der Code hatte sie nur
  für Wallrides. Jetzt ist der Anlieger derselbe Codepfad. Der Fahrer nutzt die Wangen zu
  50–70 % statt 5–24 %.
- **Bremse bei 1,3 g**: mehr, als Schotter hergibt. Jetzt 0,7 g.

## Die beiden Räder

Der Unterschied ist nicht kosmetisch:

| | MTB | eMTB |
|---|---|---|
| Systemmasse | 88 kg | 113 kg |
| CdA | 0,48 m² | 0,50 m² |
| Rollwiderstand | 0,016 | 0,019 |
| Motor | — | 620 W bis 25 km/h |
| Kontrolle in der Luft | 5,2 m/s² | 3,6 m/s² |
| schluckt Wellen bis | 0,48 m | 0,42 m |

Das eMTB schiebt aus langsamen Stellen heraus mit, ist aber träger in der Luft und verzeiht
eine verpasste Landung schlechter. Die Werte sind plausible Größenordnungen, keine Messwerte
an einem realen Rad.

Ohne GLB-Datei baut sich das Rad aus Rohren: Rahmen, Gabel, Dämpfer, 16 Speichen je
Laufrad, Kurbel mit Pedalen, Fahrerin in Angriffsposition. Beim eMTB dickes Unterrohr mit
Akku, Motorgehäuse am Tretlager, Display am Lenker. Animiert werden Räder (mit dem Tempo),
Kurbel (beim Treten), Federung (Feder-Dämpfer, Stoß bei der Landung, leichtes Ausfedern in
der Luft) und die Hocke der Fahrerin. Etwa 14 Draw Calls pro Rad.

## Die GLB-Datei

Liegt `mtb-emtb-fahrerin.glb` neben der HTML, wird sie geladen, eingemessen und auf 1,80 m
skaliert. Über ihren Inhalt wird **nichts** angenommen: keine Node-Namen, keine Materialien,
keine Achsenkonvention. Sie wird deshalb auch nicht animiert — dafür müsste ich wissen, welche
Nodes Räder und Kurbel sind.

Schaut die Fahrerin nach dem Laden rückwärts, steht die Blickrichtung der Datei anders als
angenommen — dann `GLB_DREHUNG` in der HTML von `Math.PI` auf `0` setzen.

## HUD: Zieltempo

Sobald eine Lippe näher als 70 m ist, zeigt das HUD, welches Tempo am Rampenfuß die Landung
trifft. Das ist keine Schätzung, sondern die ballistische Rechnung gegen die echte Fläche
(`zielTempo()`), plus `2·g·H`, weil die Rampe Tempo kostet. Orange = zu schnell, blau = zu
langsam. Damit ist Bremsen vor dem Sprung ein Spielelement, kein Ratespiel.
