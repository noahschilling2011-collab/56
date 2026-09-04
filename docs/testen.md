# Das Spiel testen

Alles hier ist am gebauten Stand ausprobiert, nicht aus dem Code abgeleitet.
Wo ich etwas nicht prüfen konnte, steht das ausdrücklich dabei — das ist
gleichzeitig die Liste, bei der du gebraucht wirst.

---

## 1. Datei holen

Die Datei ist `bikepark-pruefstand.html` im Branch
`claude/bikepark-game-aaa-upgrade-o570as` (PR #4). Eine einzige Datei, 532 KB,
keine weiteren Dateien nötig.

Am schnellsten über GitHub: PR #4 → Files changed → bei
`bikepark-pruefstand.html` auf **View file** → **Download raw file**.

Oder per Git:

```
git clone https://github.com/noahschilling2011-collab/56.git
cd 56
git checkout claude/bikepark-game-aaa-upgrade-o570as
```

---

## 2. Starten — zwei Wege

### Weg A: Doppelklick

**Funktioniert.** Getestet: Menü lädt, Spiel startet (`laeuft: true`), alle fünf
Räder und alle vier Charaktere sind da.

Ein Vorbehalt zur Messung: in meiner Umgebung ist `unpkg.com` gesperrt, ich habe
die Three.js-Dateien deshalb lokal gespiegelt und mit demselben CORS-Header
ausgeliefert, den unpkg sendet. Der Ladeweg ist damit derselbe — aber es ist ein
Nachbau, nicht der echte Abruf. Sollte es bei dir per Doppelklick hängen, ist das
die erste Stelle zum Nachsehen (Konsole `F12`, Tab „Network").

Eine Bedingung: **Internetverbindung muss stehen.** Three.js wird zur Laufzeit
von `unpkg.com` geladen, es liegt nicht in der Datei. Ohne Netz bleibt der
Bildschirm nach dem Klick auf „Abfahrt" hängen.

Eine Einschränkung: **Ein eigenes GLB-Modell wird per Doppelklick nicht
geladen.** Chrome verbietet `fetch` auf `file://`. Gemessene Konsolenmeldung:

```
Fetch API cannot load file:///.../mtb-emtb-fahrerin.glb.
URL scheme "file" is not supported.
GLB nicht geladen (Failed to fetch) — Rohrmodell aktiv
```

Das ist kein Absturz — das Spiel fällt sauber auf das gebaute Modell zurück.
Aber dein GLB siehst du so nie. Dafür brauchst du Weg B.

### Weg B: Lokaler Server

Nötig, sobald du ein eigenes GLB testen willst. In dem Ordner, in dem die
HTML-Datei liegt:

```
python3 -m http.server 8000
```

oder, wenn Node da ist:

```
npx serve .
```

Dann im Browser `http://localhost:8000/bikepark-pruefstand.html` öffnen.

VS Code mit der Erweiterung *Live Server* tut dasselbe per Rechtsklick →
„Open with Live Server".

---

## 3. Startmenü

| | Auswahl |
|---|---|
| **Strecken** | Downhill Republic · Alpin · Canyon — alle 1900 m, 300 hm, 15,8 % |
| **Räder** | Santa Cruz V10 · DH — Enduro 170 — Dirt Hardtail — eMTB — E-Roller |
| **Charaktere** | Mia · Lenny · Sam · Nora |
| **Gegner** | Keine · 2 · 4 · 6 · 8 |

„Keine" macht daraus ein Zeitfahren; ab 2 fährt ein Feld mit KI-Gegnern mit.

---

## 4. Tasten

Jede einzeln gedrückt und die Wirkung an den Steuerungsachsen gemessen.

### Fahren

| Taste | Wirkung | gemessen |
|---|---|---|
| `W` / `↑` | Gas | `gas: true`, `gasWert 0.56` — am Pfeil gemessen; `W` über die Vorwärtsbewegung belegt |
| `S` / `↓` | Bremse | `bremse: 1` |
| `A` / `←` | links | `quer: -0.77` |
| `D` / `→` | rechts | `quer: 1` |
| `Q` | Gewicht nach vorn | `gewicht: -0.83` |
| `E` | Gewicht nach hinten | `gewicht: 0.69` |
| `Leertaste` | Bunnyhop — halten lädt vor, loslassen springt | `hopLadung: 0.29` |
| `Shift` oder `Strg` | Pumpen (in Senken drücken, auf Kuppen entlasten) | `pump: true` |

Die Zwischenwerte sind kein Zufall: die Achsen sind gerampt, nicht an/aus. Ein
kurzer Tastendruck gibt weniger als ein gehaltener — deshalb `0.77` statt `1`.

### Ansicht und Wechsel

| Taste | Wirkung — gemessen |
|---|---|
| `C` | Kamera: Verfolgung → Cockpit → Weit → zurück |
| `1`–`5` | Rad wechseln, in der Reihenfolge des Menüs |
| `F` | Charakter wechseln (mia → lenny → sam → nora) |
| `M` | Ton aus / an — HUD zeigt „Ton aus" bzw. „Ton an" |
| `R` | Neustart |
| `Esc` oder `P` | Pause |

### Debug — nur sinnvoll mit Gegnern

| Taste | Wirkung — gemessen |
|---|---|
| `K` | KI-Overlay ein/aus |
| `J` | nächster Fahrer im Overlay |

Das Overlay zeigt echte Entscheidungswerte, keine Anzeige-Attrappe. So sah es
im Test aus (4 Gegner, Downhill Republic):

```
Speed Demon  (1/4)
Strategie  angriff
Linie      mitte  Ziel u 0 (ist -0.13)
Sektion    -1
Tempo      0.4 m/s
```

`J` schaltet auf `Beginner (2/4)` weiter. **Ohne Gegner ist das Overlay leer** —
es hat dann nichts anzuzeigen.

---

## 5. Pausemenü (`Esc`)

Enthält mehr, als der Name vermuten lässt:

- **Qualität:** Hoch · Mittel · Sparsam — im Lauf umschaltbar, kein Neustart nötig.
  Fang bei Rucklern hier an.
- **Tageszeit:** Morgen · Mittag · Nachmittag · Abend. Die Knöpfe sind da; dass
  sie Sonnenstand und Licht umstellen, steht so im Code — durchgeklickt habe ich
  sie nicht.
- **Trainingslager:** 10 / 25 / 50 Runden. Die Gegner fahren die Strecke ohne
  Rendern immer wieder und behalten, was ihre Rundenzeit messbar verbessert.
  Läuft mit Fortschrittsbalken, jederzeit abbrechbar.
- Weiter · Neustart · Streckenwahl

Was die Qualitätsstufen konkret abschalten:

| | Pixelratio | Schatten | AO | Bloom | Gras |
|---|---|---|---|---|---|
| Hoch | 2 | 2048 | ja | ja | 100 % |
| Mittel | 1,5 | 1024 | nein | ja | 50 % |
| Sparsam | 1 | aus | nein | nein | aus |

---

## 6. Worauf es beim Testen wirklich ankommt

Das Folgende konnte ich **nicht** prüfen. Nicht aus Nachlässigkeit — es geht
hier technisch nicht. Getestet wird headless mit SwiftShader, also
Software-Rendering mit Sekunden pro Bild, ohne Ton und ohne Eingabegeräte.

### Bildrate

Jede fps-Zahl von mir wäre erfunden. Messbar sind Draw Calls und Dreiecke, nicht
Bilder pro Sekunde.

Prüf das so: Auf **Hoch** starten, Downhill Republic, 4 Gegner. Wenn es ruckelt,
im Pausemenü auf **Mittel**, dann **Sparsam** — und sag mir, ab welcher Stufe es
flüssig wird und wo es am stärksten einbricht (Wald? Zielbereich mit den
Zuschauern? Beim Landen?). Diese Antwort brauche ich, um überhaupt zu wissen,
wo optimiert werden muss.

### Ton

Der Audiograph ist vermessen — Pegel je Untergrund, kein Übersteuern. **Ob er
gut klingt, weiß ich nicht.** Hör auf: Rollgeräusch beim Wechsel Erde → Fels →
Holz, Wind mit steigendem Tempo, Absprung, Landung, Sturz, Vögel, Zuschauer im
Zielbereich.

### Fahrgefühl

Das Wichtigste und das, was ich am wenigsten beurteilen kann. Die Physik ist auf
Zahlen geprüft (Reibkreis, Bremswege, Sprungweiten), aber ob es sich *gut
anfühlt*, entscheidet sich beim Fahren:

- Lenkt es zu träge oder zu nervös?
- Bremst es glaubwürdig, oder steht das Rad zu abrupt?
- Sind die Sprünge zu weit oder zu kurz?
- Ist der Bunnyhop brauchbar oder nur Dekoration?
- Fühlt sich der Unterschied zwischen V10 und Dirt Hardtail echt an?

### Gegen die KI fahren

Die Gegner sind gemessen unterschiedlich, aber ob es Spaß macht, gegen sie zu
fahren, ist eine andere Frage. Fahr mit 4 Gegnern und achte darauf, ob sie sich
wie Fahrer verhalten oder wie Verkehrshütchen — und ob sie zu schnell oder zu
langsam sind.

### Gamepad und Touch

Der Code liest beides, geprüft ist nur der Tastaturweg. Wenn du ein Gamepad hast
oder es auf dem Handy öffnest: sag, ob es reagiert.

### Safari

`backdrop-filter` ist dort historisch heikel. Die Panels tragen auch ohne ihn,
aber gesehen habe ich es nicht.

---

## 7. Dein eigenes GLB einbauen

1. Datei `mtb-emtb-fahrerin.glb` **neben** die HTML-Datei legen
2. Über einen lokalen Server öffnen (Weg B — per Doppelklick geht es nicht)
3. Konsole öffnen (`F12`)

Läuft es, siehst du **keine** Warnung. Läuft es nicht, sagt die Konsole warum —
zum Beispiel bei einem Export in Zentimetern:

```
Modellhöhe 158.50 m — erwartet wird etwa 1,80 m.
```

Skaliert wird **nicht** automatisch, und das ist Absicht: Radstand und Radradius
stehen in `BIKES.bau` und die Physik rechnet damit. Automatisches Skalieren
würde die Physik still verfälschen.

Welche Knotennamen, Materialnamen und Maße das Modell braucht, steht vollständig
in [`glb-modell.md`](glb-modell.md). `glb-vorlage.glb` im selben Ordner ist eine
getestete Beispieldatei — lade die zuerst, dann weißt du, dass der Weg steht,
bevor du dein eigenes Modell debuggst.

---

## 8. Wenn etwas nicht geht

**Nach „Abfahrt" bleibt der Ladebildschirm stehen** → Internet weg. Three.js
kommt von unpkg.

**Konsole zeigt `GLB nicht geladen` und es läuft trotzdem** → normal, solange
kein eigenes GLB da ist. Das gebaute Modell greift.

**Es ruckelt** → Pausemenü, Qualität runter. Dann sag mir, welche Stufe.

**Es ruckelt auch auf Sparsam** → melde Grafikkarte und Browser, das ist ein
echter Befund.

**Tasten reagieren nicht** → einmal ins Bild klicken. Die Tastatur hängt am
Fenster, nicht am Canvas; nach einem Klick ins Menü kann der Fokus woanders
liegen.

---

## 9. Debug-Konsole

Bei offener Konsole (`F12`) ist `window.bikepark` da. Nützlich:

```js
bikepark.setzeQualitaet('niedrig')   // 'hoch' | 'mittel' | 'niedrig'
bikepark.gegnerZahl = 6              // 0 bis 8, greift beim nächsten Start
bikepark.kamMode = 1                 // 0 Verfolgung, 1 Cockpit, 2 Weit
bikepark.fahrer.s                    // Position auf der Strecke in Metern
bikepark.fahrer.vs                   // Tempo in m/s
bikepark.gegner.length               // Größe des Feldes
bikepark.ein                         // was die Steuerung gerade liefert
bikepark.ladeStand.zeiten            // Dauer jedes Ladeschritts
```

`bikepark.ein` ist am nützlichsten, wenn sich die Steuerung falsch anfühlt — es
zeigt, was ankommt, bevor die Physik es verarbeitet:

```js
{gas: false, gasWert: 0, bremse: 0, quer: 0, gewicht: 0,
 pump: false, hop: 0, hopLadung: 0, quelle: 'tastatur'}
```

`quelle` sagt, welches Eingabegerät zuletzt gegriffen hat — `'tastatur'`,
und bei Gamepad oder Touch entsprechend. Damit lässt sich prüfen, ob ein
Gamepad überhaupt erkannt wird.

`bikepark.ladeStand.zeiten` ist die einzige echte Performance-Zahl, die du ohne
Werkzeug bekommst — Millisekunden ab Klick auf „Abfahrt", je Aufbauschritt:

```js
{fahrzeug: 6, material: 1668, strecke: 1883, gelaende: 2422,
 wald: 3524, park: 3786, licht: 4198, rad: 6518}
```

Das sind meine Zahlen aus dem Software-Rendering und deshalb viel zu hoch. Auf
deiner Hardware wird es deutlich schneller sein — interessant ist nicht der
Absolutwert, sondern welcher Schritt den größten Sprung macht.
