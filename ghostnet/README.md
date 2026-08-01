# GHOSTNET — Phase 1

Open-World-Cyberpunk-Hacker-Spiel für Roblox. Alles Hacken ist Fiktion:
stilisierte Minispiele auf einem Fake-Betriebssystem.

Phase 1 liefert den Kern: **HackService + Node-Breach + drei Testobjekte.**

---

## Sofort ausprobieren

```
GhostNet.rbxlx  ->  in Roblox Studio öffnen  ->  Play
```

Vor dir stehen drei Ziele. Hingehen, **[E]** drücken, Rätsel lösen.

| Ziel | Schwierigkeit | Effekt bei Erfolg |
|---|---|---|
| CAM-07 (links) | 2 | Kamera kippt weg und geht 30 s aus |
| SEC-DOOR (Mitte) | 4 | Tür fährt 12 s in den Boden |
| ATM (rechts) | 6 | Auszahlung mit Funken, 300 s Cooldown |

### Node-Breach in einem Satz

Vom **S** zum **E** einen Pfad legen, dabei **alle R** mitnehmen. `#` ist ICE
und blockiert. Zusätzlich steckt **getarntes ICE** im Gitter — das sieht aus
wie ein freier Knoten und kostet beim Reintappen einen Versuch. Auf den
vorletzten Knoten klicken nimmt einen Schritt zurück.

---

## Aufbau

```
src/
  ReplicatedStorage/Shared/
    Config.lua           alle Balancing-Zahlen, sonst nichts
    Types.lua            Luau-Typen für Server und Client
    Remotes.lua          legt die Remote-Objekte an
    UITheme.lua          Farben, Rahmen, Scanlines, Tippanimation
  ServerScriptService/
    GhostNetServer.server.lua   Bootstrap
    Systems/
      HackService.lua           Sessions, Validierung, Abschluss
      HackTargets.lua           Registry der hackbaren Parts
      HackEffects.lua           OnSuccess-ID -> Weltaktion
      EconomyService.lua        Crypto und Rig-Werte
      RateLimiter.lua           Token-Bucket pro Spieler und Remote
      Minigames/NodeBreach.lua  Minispiel A
    World/TestTargets.server.lua  die drei Testobjekte
  StarterPlayer/StarterPlayerScripts/UI/
    HackUI.client.lua    Fake-OS-Fenster
    HUD.client.lua       Wallet, Ziel-Prompt, Meldungen
```

---

## Ein neues Hack-Ziel hinzufügen

**Ohne eine Zeile Code.** Part in Workspace setzen, Tag `GhostNetHackable`
vergeben, Attribute setzen. Fehlende Attribute kommen aus
`Config.TargetDefaults`.

| Attribut | Typ | Bedeutung |
|---|---|---|
| `Difficulty` | number 1–10 | Gittergröße, Zeit, Belohnung, Trace |
| `HackType` | string | `NodeBreach` (weitere ab Phase 4) |
| `Reward` | number | Crypto; weglassen = aus Difficulty berechnet |
| `TraceGain` | number | weglassen = `Difficulty × 4` |
| `Cooldown` | number | Sekunden pro Spieler; weglassen = 90 |
| `RequiredLevel` | number | nötiges Rig-Tier |
| `OnSuccess` | string | `Offline`, `CameraOffline`, `DoorOpen`, `AtmPayout` |
| `DownTime` | number | wie lange der Effekt hält |
| `DisplayName` | string | Name im HUD |

Der Server vergibt beim Start automatisch `TargetId` und `Offline`.

---

## Server-Autorität

Der Client schickt ausschließlich Eingaben — *„ich habe Knoten 14 geklickt"*.
Nie ein Ergebnis, nie eine Zeit, nie einen Betrag. Der Server führt
Rätselzustand, Uhr, Versuche, Distanz und Cooldown.

Bei **jeder** Eingabe prüft der Server neu:

- Rate-Limit (Token-Bucket, Limits in `Config.RateLimits`)
- Session gehört dem Absender und ist nicht abgeschlossen
- Schrittzähler ist exakt der erwartete — derselbe Schritt wirkt nie zweimal
- Deadline nach `workspace:GetServerTimeNow()`
- Abstand Spieler↔Ziel **zur Oberfläche**, nicht zum Mittelpunkt
- Payload-Form und Wertebereich

Dazu ein Wachhund mit 4 Hz, der Zeit und Distanz auch dann prüft, wenn der
Client gar nichts sendet. Weglaufen bricht den Hack ab.

Die Lösung verlässt den Server nie. Getarntes ICE wird dem Client als freier
Knoten geschickt und erst beim Reintappen aufgedeckt.

---

## Werkzeuge

```
python3 tools/build_place.py       # baut GhostNet.rbxlx aus src/
python3 tools/make_sourcemap.py    # sourcemap.json für luau-lsp
python3 tools/test_nodebreach.py   # Headless-Test des Generators
```

Der Test braucht den `luau`-Interpreter im Pfad (oder als Argument) und
prüft 3.000 erzeugte Gitter darauf, dass sie lösbar sind, dass kein ICE auf
dem Lösungspfad liegt, dass alle Relays erreichbar sind und dass ungültige
Eingaben abgelehnt werden.

Wer mit **Rojo** arbeitet: `default.project.json` liegt bereit, der
`src/`-Baum bildet das DataModel 1:1 ab.

---

## Stand

**Fertig in Phase 1**

- Generisches Hack-System, Ziele sind reine Attribut-Sets
- Node-Breach vollständig serverseitig validiert
- Fake-OS-UI mit Scanlines, Tippanimation, Timer, RAM-Chips
- HUD mit Wallet, Ziel-Prompt und Ablehnungsgründen
- Rate-Limits auf allen drei Client-Remotes

**Noch nicht drin** (kommt laut Plan)

- Phase 2: TraceService, Cyber-Police, SaveService — `TraceDelta` wird
  bereits korrekt berechnet und mitgeschickt, aber noch nicht angewendet
- Phase 3: Aufträge, Verkauf im Versteck, Rig-Upgrades — alle Rig-Werte
  stehen auf Stufe 1, die Formeln rechnen aber schon mit ihnen
- Phase 4: Signal-Match, Code-Crack, Ice-Breaker, Zonen, Fraktionen
