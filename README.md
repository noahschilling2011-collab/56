# ✈ Flughafen-Job-Simulator

Arbeite dich vom **Check-in-Schalter** über den **Ramp Agent** bis zum **Captain** hoch —
an einem komplett begehbaren Low-Poly-Flughafen mit 1500-m-Runway, PAPI-Befeuerung,
vereinfachter (aber plausibler) Flugphysik und Landungsbewertung.

Das Spiel gibt es **zweimal**:

| Variante | Datei | Starten |
|---|---|---|
| **Browser (Three.js)** | `airport-job-simulator.html` | Datei einfach im Browser öffnen (Three.js kommt per CDN, sonst keine Abhängigkeiten) |
| **Roblox Studio** | `roblox/AirportJobSimulator.rbxlx` | Datei in Roblox Studio öffnen → **Play** drücken |

Fortschritt lebt **nur im Speicher** — kein localStorage, kein DataStore.

---

## Der Mega-Airport

Drei verbundene Terminals: das begehbare **Terminal 1** (Check-in-Halle, Sicherheits-
kontrolle, Passkontrolle, Duty-Free, Einkaufs-Arkade mit Mode/Elektronik/Buchladen/
Souvenirs, Burger- und Pizza-Restaurant, Café, Business-Lounge, Gepäckausgabe-
Karussell, Self-Check-in-Automaten, Infoschalter, Kinderecke) plus **Terminal 2 und 3**
mit langen Gate-Piers (B1–B7, C1–C7) samt Fluggastbrücken und geparkten Jets.
**Zwei Runways** (09/27 und 07/25) mit eigenem Deko-Verkehr, Cargo-Center mit
Frachter und LD-Containern, Flughafenfeuerwehr mit Löschfahrzeugen (Blaulicht!),
Follow-Me-Car, Vorfeldbusse, Catering-LKW, Enteisungsfahrzeug, Tanklager,
**Parkdeck mit 3 begehbaren Ebenen** — und außenrum eine echte Landschaft:
Fluss, See, Stadt-Skyline mit Fernsehturm, Berge, Autobahn mit fahrenden Autos
und drehende Windräder. Dazu Durchsagen-Gong im Terminal.

## Spielablauf

1. **JOB 1 · Check-in-Agent** (Start) — leuchtend blauer Marker hinter Schalter 1.
   8 Passagiere pro Schicht: Name auf Ticket ↔ Pass vergleichen, Flug gegen die
   Abflugtafel prüfen (CLOSED = abweisen!), Gepäck über 23 kg → Gebühr kassieren.
   2–3 Fälle pro Schicht haben Fehler. Richtig = +60 Cr & XP, durchgewunkener Fehler = −40 Cr.
1b. **Sicherheitskontrolle** (ab 750 Credits) — lila Marker am Röntgenband: Handgepäck
   durchleuchten, verbotene Gegenstände konfiszieren.
1c. **Tankwagen-Fahrer** (ab 1000 Credits) — Fuel Depot: beide Jets gegen die Uhr betanken.
1d. **Marshaller** (ab 1500 Credits) — Gate 4: den anrollenden A320 mit Handzeichen einweisen.
2. **JOB 2 · Ramp Agent** (ab 500 Credits) — oranger Marker am Gepäckband.
   Farbcodierte Koffer (blau → LH 452, orange → EW 771) vom Band aufnehmen (E),
   auf den Gepäckwagen laden (max. 6), Wagen fahren (leichter Drift!) und am
   richtigen Jet abladen. 8 Koffer in 3 Minuten; Kollision mit einem Flugzeug kostet.
3. **JOB 3 · Captain** (ab 2000 Credits) — grüner Marker am eigenen Propellerflugzeug.
   Drei Missionen, alle starten und landen auf Runway 09:
   - **Rundflug**: 5 Checkpoint-Ringe, wenig Wind
   - **Platzrunde**: Traffic-Pattern (Querabflug → Gegenanflug → Queranflug → Endanflug) auf ~800 ft
   - **Präzisionslandung**: kurzer Endanflug bei 16 kt Seitenwind, Aufsetzen exakt in der Aufsetzzone

### Flugphysik (kein Arcade)
Auftrieb ~ v² × Anstellwinkel · Stall unter ~50 kt (Nase sackt weg) · Abheben erst
ab ~55 kt Rotationsgeschwindigkeit · geschwindigkeitsabhängige Ruderwirkung ·
**Klappen (F)** in 3 Stufen: mehr Auftrieb & Widerstand, niedrigere Stallspeed ·
**Bodeneffekt** kurz über der Bahn · konstanter Missionswind, der spürbar seitlich
versetzt (Vorhaltewinkel!) · PAPI nutzbar: 2× rot / 2× weiß = perfekter Gleitpfad.

### Das Flugzeug
Cessna-artiger Hochdecker mit Streben, Spinner, Radverkleidungen, Kennzeichen
(D-EJSK), animierten Ruderflächen und Klappen, Propeller-Blur bei hoher Drehzahl,
Positionslichtern (rot/grün), blitzendem Beacon, einziehbarem Fahrwerk und
Motorsound (Browser-Version, Tonhöhe folgt dem Schub).

### Die A380 an den Gates — begehbar!
Die beiden Deko-Jets (und der Deko-Verkehr) sind **Airbus A380**: Doppeldecker-Rumpf,
vier Triebwerke, gepfeilte Flügel, Fahrwerks-Bogies — und seit dem Design-Upgrade
**einzelne Kabinenfenster auf beiden Decks, Airline-Schriftzüge (SKYJET, LUFTAIR,
NORDWIND, SUNLINE, PACIFIC AIR), Logos auf dem Leitwerk und Triebwerks-Spinner
mit Einlauflippe** — genau wie A320, 747, ATR und Bizjet.
Der A380 an **Gate 1** ist von innen begehbar: über die Gangway-Treppe (E) hinein,
durch die Economy-Kabine (2-3-2) mit sitzenden Passagieren, vorbei an der Galley
ins **Cockpit** (Panel mit Displays, Pedestal, Sidesticks) oder die Treppe hoch
aufs **Oberdeck** mit Premium-Bestuhlung (1-2-1). In Roblox läuft man dank echter
Physik einfach die Rampe hinauf; im Browser übernimmt E-Interaktion den Einstieg.

### Der Flughafen
**Gewölbtes Bogendach über Terminal 1** (mit Rippen und Glas-Giebeln) ·
Flughafen-Totem „FLUGHAFEN INTERNATIONAL" an der Vorfahrt · **Flutlichtmasten**
am Vorfeld · gemalte **Stand-Nummern** an den Gates · **drehendes Radar** auf dem
Tower · Umzäunung des gesamten Flugfelds mit Tor an der Zufahrt · **ILS**
(Localizer-Antennenreihen hinter beiden Schwellen + Gleitpfad-Mast) ·
Anflugbefeuerung mit Lauflicht-Strobes an beiden Schwellen · blaue Taxiway-Rand-
befeuerung · Hold-Short-Markierungen mit Runway-Schildern · Gummiabrieb in den
Aufsetzzonen · rote Vorfeld-Sicherheitslinie, Gate-Schilder & Pylonen · Tankwagen,
Gangway-Treppe und Pushback-Tug · Terminal mit Schriftzug, Vordach, beleuchteter
Decke, Absperrbändern, Café-Kiosk, Beschilderung und Pflanzen · Parkplatz mit
Autos · prozedurale Gras-/Asphalt-/Beton-Texturen · driftende Wolken.

### Landungsbewertung
Sinkrate (<200 ft/min = 🧈 Butter · 200–600 okay · >600 hart · >1000 Crash) +
Centerline-Abweichung + Aufsetzzone → **1–5 Sterne**, Bezahlung = Missionsbasis × Sterne.
Ohne Fahrwerk oder neben der Runway = Crash, Respawn am Vorfeld.

## Game-Feel („1-Million-Euro-Polish")

Titelscreen mit animiertem Logo · Sound-Effekte für alles (Kassen-Klingeln,
Erfolgs-Jingle, Level-Up-Fanfare, Reifenquietschen bei der Landung, Crash-Boom,
UI-Klicks, Durchsagen-Gong) · Partikel-Effekte (Konfetti beim Level-Up,
Reifenqualm beim Aufsetzen, Explosion beim Crash) · schwebende Credit-Popups ·
**10 Erfolge** (Taste **J**) vom „Ersten Arbeitstag" bis „🧈 Butterweich" ·
**Minimap** (Taste **M**) mit Live-Position auf dem ganzen Flughafen.

## Steuerung

| Zu Fuß / Wagen | Flug |
|---|---|
| **WASD** Bewegen | **W/S** Pitch (S = ziehen) · **A/D** Roll |
| **Shift** Sprint | **Q/E** Seitenruder + Bugradlenkung |
| **E** Interagieren | **Shift/Strg (o. X)** Schub + / − |
| **H** Steuerungslegende | **G** Fahrwerk · **F** Klappen · **B** Bremse |
| **Maus** Kamera (HTML: Klick = Pointer-Lock) | **C** Verfolger/Cockpit · **R** Reset ans Vorfeld |

## Roblox-Variante

- `roblox/AirportServer.server.lua` — baut den kompletten Flughafen beim Start aus Parts
  (keine externen Assets). Landet in **ServerScriptService**.
- `roblox/AirportClient.client.lua` — gesamte Spiellogik: Jobs, HUD, Interaktionen,
  Wagen- und Flugphysik. Landet in **StarterPlayerScripts** (ausgelegt auf Solo-Play).
- `roblox/build_rbxlx.py` — setzt aus beiden Quellen die fertige
  `AirportJobSimulator.rbxlx` zusammen (nach Änderungen einfach neu ausführen).

Skalierung: **1 m = 2 Studs**; die Flugphysik rechnet intern in Metern und ist
identisch mit der Browser-Version.
