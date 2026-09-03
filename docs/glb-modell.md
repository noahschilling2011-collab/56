# Was ein eigenes Fahrzeugmodell mitbringen muss

Das Spiel lädt `mtb-emtb-fahrerin.glb` aus dem Ordner neben der HTML-Datei.
Liegt sie nicht da, fährt das Rohrmodell aus Primitiven — die Seite läuft
trotzdem, es sieht nur schlechter aus.

`docs/glb-vorlage.glb` in diesem Ordner ist eine minimale Datei mit exakt der
Struktur, die unten steht. Sie ist absichtlich hässlich: sie prüft den
Ladeweg, nicht die Optik. Zum Nachbauen im Modellprogramm öffnen.

Dieser Ladeweg ist getestet, nicht behauptet: mit der Vorlage geladen, alle
Pivots gefunden, Räder rollen, Vorderrad lenkt 15°, Charakterwechsel färbt,
Draw Calls von 10 auf 2 verschmolzen, keine Konsolenfehler.

## Maße und Lage

- **Meter.** Die Datei wird **nicht** skaliert. Wer in Zentimetern exportiert,
  bekommt ein 158 m hohes Fahrzeug — dafür gibt es beim Start eine Meldung mit
  der gemessenen Höhe.
- **Boden bei y = 0.** Die Reifenunterkante berührt y = 0. Weicht das um mehr
  als 12 cm ab, meldet das Spiel es.
- **Blick nach +z.** Das Vorderrad liegt bei positivem z (in der Vorlage
  z = +0,632), das Hinterrad bei negativem.
- **In x zentriert.** Die Mittelebene des Rads liegt bei x = 0.
- **Gesamthöhe etwa 1,80 m** (Fahrerin auf dem Rad). Toleriert wird 1,35 bis
  2,30 m ohne Meldung.

Warum nicht automatisch skalieren: Radstand und Radradius stehen in
`BIKES[...].modell.bau` und die Physik rechnet daraus. Ein skaliertes Modell
wäre optisch richtig und physikalisch falsch — das Rad würde neben der
Fahrfläche laufen oder in ihr stecken.

## Knotennamen

Diese Namen sind der Vertrag. Fehlt einer, fällt genau die Funktion aus, die
daran hängt; alles andere läuft weiter.

| Name | wofür | fehlt er, dann |
|---|---|---|
| `wheel_front` | Vorderrad, alle Teile die mitdrehen | Rad dreht nicht, Vorderrad lenkt nicht |
| `wheel_rear` | Hinterrad | Rad dreht nicht, kein sichtbarer Drift |
| `chainring` | Kettenblatt | dreht nicht mit der Kurbel |
| `crank_arm` | Kurbelarme | dreht nicht |
| `pedal` | Pedale | drehen nicht mit |
| `rider_female` | Gruppe mit allem, was zur Fahrerin gehört | keine Haltungswechsel |
| `ponytail` | Zopf | wird nicht je Charakter geschaltet |
| `helmet_peak` | Helmschirm | wird nicht je Charakter geschaltet |
| `motor_box` | Motorgehäuse | bleibt beim MTB sichtbar |
| `battery_downtube` | Akku im Unterrohr | bleibt beim MTB sichtbar |

Mehrere Knoten dürfen denselben Namen tragen — `wheel_front` an Reifen, Felge,
Speichen und Bremsscheibe ist richtig, sie werden zu einem Drehpivot
zusammengefasst. Der Pivot landet im gemeinsamen Mittelpunkt, also muss die
Nabe geometrisch in der Mitte des Rads liegen.

Die Räder hängen am Halter, nicht am federnden Rahmen — sie federn nicht mit,
weil die Federung als Rahmenbewegung dargestellt wird.

## Materialnamen

Über den Materialnamen laufen die Farben. Die Charakterauswahl setzt vier
davon zur Laufzeit um, der Rest bleibt wie modelliert.

| Name | wird gesetzt von |
|---|---|
| `jersey` | Charakterauswahl (Trikot) |
| `kit_pants` | Charakterauswahl (Hose) |
| `helmet` | Charakterauswahl (Helm) |
| `skin` | Charakterauswahl (Haut) |
| `hair` | Charakterauswahl (Haar) |
| `frame_charcoal` | beim MTB auf die Akzentfarbe des Rads |
| `raw_alu`, `tire_rubber`, `anodized_gold` | nichts — Farbe kommt aus dem Modell |

Alles, was nicht in der Tabelle steht, behält seine Modellfarbe. Reifen also
im Modell schwarz einfärben, nicht grau lassen.

## Was das Modell zusätzlich hergeben könnte

Die Animation nutzt heute Lenkeinschlag, Nicken, Federung und vier
Fahrerhaltungen. Mehr ginge mit mehr Knoten — das sind Vorschläge, keine
Pflicht, und dafür müsste die Animation erweitert werden:

- **Lenkkopf** als eigener Knoten über `wheel_front`: dann dreht der ganze
  Lenker mit, nicht nur das Rad um seine Nabe.
- **Gabel getrennt** in Standrohr und Tauchrohr: echter Federweg vorn statt
  einer gemeinsamen Rahmenbewegung.
- **Gliedmaßen der Fahrerin** einzeln benannt (Oberarm, Unterarm, Ober- und
  Unterschenkel, Kopf): heute lässt sich nur die ganze Gruppe bewegen, deshalb
  bleiben die Arme bei jeder Haltung am selben Punkt.

## Prüfen, ob es sitzt

Datei neben die HTML legen, Seite über einen Server öffnen (`python3 -m
http.server` — per `file://` blockiert CORS die GLB-Datei), Konsole offen
lassen. Ohne Meldung ist alles gefunden. Sonst steht dort, welcher Knoten
fehlt oder was mit den Maßen nicht stimmt.
