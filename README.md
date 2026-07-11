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

## Spielablauf

1. **JOB 1 · Check-in-Agent** (Start) — leuchtend blauer Marker hinter Schalter 1.
   8 Passagiere pro Schicht: Name auf Ticket ↔ Pass vergleichen, Flug gegen die
   Abflugtafel prüfen (CLOSED = abweisen!), Gepäck über 23 kg → Gebühr kassieren.
   2–3 Fälle pro Schicht haben Fehler. Richtig = +60 Cr & XP, durchgewunkener Fehler = −40 Cr.
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

### Der Flughafen
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
