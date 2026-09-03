# Abstand zu einem kommerziellen AAA-MTB-Spiel

Bestandsaufnahme des Bikepark-Prüfstands gegen das, was Descenders, Lonely
Mountains: Downhill oder Riders Republic tatsächlich tun. Grundlage: der
gelesene Code und Screenshots aus dem laufenden Spiel, nicht aus dem Gedächtnis.

Reihenfolge nach Wirkung auf den Eindruck „echtes Spiel", nicht nach Aufwand.
Was noch offen ist, steht als offen drin — keine Punkte, die nur gut aussehen.

## Vorbemerkung: drei Grenzen, die bleiben

**Fahrer und Rad waren gesperrt — sind es nicht mehr.** Der ursprüngliche
Auftrag klammerte beides aus („werden separat erstellt"). Solange das galt, war
„sieht aus wie ein veröffentlichtes Spiel" nicht erreichbar, sondern nur „alles
außer Fahrer und Rad ist auf dem Niveau" — ein Spieler schaut die ganze Zeit
darauf. Die Sperre wurde später aufgehoben: erst fürs Rad („Fahrradqualität wie
Riders Republic"), dann für den Fahrer. Beide sind inzwischen ausgebaut, das Rad
mit echten Bauteilen, der Fahrer mit Fullface-Helm und Proportionen je Charakter.

Was als Grenze bleibt: die Figur besteht weiter aus Primitiven. Kein Rig, also
keine Gewichtsverlagerung, kein Stoff, keine Texturen auf Trikot oder Rahmen.
Der Sprung von „Rohrmodell" auf „liest sich als Downhill-Fahrer" ist gemacht;
der Sprung auf ein geskinntes Modell braucht ein GLB — der Ladeweg dafür steht
und ist getestet (siehe `glb-modell.md`).

**Bildrate ist hier nicht messbar.** Getestet wird headless mit SwiftShader,
also Software-Rendering mit Sekunden pro Frame. Draw Calls, Dreiecke, Texturen
und Speicher sind messbar; fps nicht. Jede Zahl zur Bildrate wäre erfunden.

**Ton ist hier nicht hörbar.** Der Audiograph lässt sich vermessen (Pegel je
Untergrund, kein Übersteuern), aber ob er gut klingt, kann ich nicht sagen.

## Die 20 Punkte

### Fahrgefühl und Physik

**1. Es gibt keinen Sturz.** `f.stuerze` zählt Randkontakte und zieht 28 %
Tempo ab — der Fahrer fährt weiter. Damit kostet ein Fehler Zehntelsekunden
statt eines Laufs, und Fahren am Limit ist keine Entscheidung mehr. Das ist der
größte Einzelunterschied zu jedem MTB-Spiel: dort ist der Sturz die zentrale
Konsequenz, an der Kamera, Ton, UI und Wiedereinstieg hängen.

**2. Der Fahrer ist ein einzelner Punkt.** Vorder- und Hinterrad landen immer
gleichzeitig. Ein echtes Spiel trennt sie: Nose-Case, Rear-Case, Vorderrad
zuerst in der Anliegerwand. Ohne das gibt es keine Nose-Dive-Landung und kein
Abfangen mit dem Hinterrad.

**3. Kein Manual, kein Wheelie, kein Scrub.** Die Gewichtsverlagerung (Q/E)
wirkt auf den Nasenwinkel und die Landungsbewertung, hebt aber kein Vorderrad
und trägt kein Tempo über einen Rollerabschnitt.

**4. Keine Tricks in der Luft.** In der Luft passiert nur das Kippen der Nase.
Kein Whip, kein Table, keine Rotation — und damit auch keine Punkte, kein Risiko
beim Landen einer angefangenen Drehung.

**5. Kein Gangwechsel und keine Trittfrequenz.** `tritt/max(vs,1.2)` ist eine
Hyperbel ohne Getriebe. Über 40 km/h tritt der Fahrer faktisch ins Leere, was
richtig ist, aber es gibt keine spürbare Beschleunigungscharakteristik.

**6. Bremsen sind eine Achse.** Vorder- und Hinterbremse sind zusammengefasst.
Ein MTB-Spiel trennt sie: hinten blockieren für den Drift, vorne für die
Verzögerung, beides zusammen für den Überschlag.

### Animation

**7. Die Animation liest die Physik kaum.** `animiereFahrzeug` bekommt den
kompletten Fahrerzustand und nutzt davon Geschwindigkeit, Bodenkontakt und
Landungsstoß. Nicht genutzt: Lenkeinschlag (das Vorderrad dreht sich nie),
Rutschen, Bremsen, Gewichtsverlagerung, Federweg der Gabel getrennt vom Dämpfer.

**8. Kein Übergang zwischen Zuständen.** Beim Abheben, Landen, Bremsen und
Rutschen gibt es keine eigene Pose — der Fahrer sitzt immer gleich da.

### Welt

**9. Anliegerwände sind glatte Kegelflächen.** Keine Oberkante, kein
Erdaufwurf, keine unterschiedliche Verdichtung zwischen Fahrspur und Wangen.
Im Screenshot bei Station 210 gut zu sehen: eine gleichmäßige braune Fläche.

**10. Der Trailrand ist ein harter Schnitt.** Zwischen Fahrfläche und Gras
liegt keine Übergangszone. In echt: aufgefahrene Kante, loses Material,
Grasbüschel, die in die Spur ragen.

**11. Die Vegetation wiederholt sich sichtbar.** Dieselben Kegelbäume in
gleicher Größe und Ausrichtung, Grasbüschel in identischer Größe im Raster.
Keine Neigung, keine Alterstaffelung, keine Lücken oder Dickichte.

**12. Kein Streudetail auf dem Trail.** Keine Wurzeln, keine eingewachsenen
Steine, keine Pfützen, kein Laub in den Kurvenausgängen. Der Untergrundwechsel
existiert im Material, aber nicht als Objekt.

**13. Kein Himmelsdetail.** Preetham-Himmel ohne Wolken. Ein AAA-Titel hat
mindestens eine Wolkenschicht mit Parallaxe, oft mit Schattenwurf.

### Beleuchtung

**14. Die Selbstverschattung am Trailrand ist schwach.** GTAO ist aktiv, aber
die Kante zwischen Trail und Böschung liest sich flach. Ein Kontaktschatten dort
ist das, was Geometrie erst plastisch macht.

**15. Nur ein Wetterzustand.** Tageszeiten sind wählbar, aber es gibt keinen
Dunst in Bodennähe, keine Sonnenstrahlen durch die Bäume, keinen Regen, keine
Änderung des Grips mit dem Wetter.

### Ton

**16. Der Ton reagiert nicht auf den Raum.** Rollgeräusch, Wind und Zuschauer
sind da, aber es gibt keinen Hall im Waldabschnitt gegen den offenen Hang, kein
Echo an der Felswand, keine Verdeckung.

**17. Keine Reifen-Slip-Kurve.** Rutschen hat einen eigenen Kanal, aber das
Geräusch ändert nicht die Tonhöhe mit dem Schlupf.

### Rennablauf und UI

**18. Kein Rennablauf.** Kein Countdown, keine Sektorzeiten, kein Geist, kein
Vergleich zur Bestzeit während der Fahrt. Die Bestzeit steht erst im Ziel.

**19. Keine Wiederholung.** Ein AAA-Titel zeigt nach dem Lauf die beste Stelle
noch einmal aus einer anderen Kamera. Die Daten dafür (Position je Frame)
existieren, sie werden nur nicht aufgezeichnet.

### Performance

**20. Kein Sichtbarkeitssystem über die Streckenlänge.** Es gibt Sichtweiten-
Culling und LOD für Bäume, aber der Park (Zäune, Schilder, Zuschauer, Zelte)
und das Gelände liegen als ganze Objekte in der Szene. Bei 80 Draw Calls und
1,1 Mio. Dreiecken auf „hoch" ist das heute tragbar; ob es auf schwacher
Hardware reicht, ist von hier aus nicht feststellbar.

## Reihenfolge der Bearbeitung

1. Sturz (Punkt 1) — verbindet Physik, Kamera, Ton und UI
2. Animation an die Physik hängen (7, 8) — sichtbar in jedem Frame
3. Trailrand und Anliegerkante (9, 10, 14) — der Blick liegt dauernd darauf
4. Vegetationsvarianz und Streudetail (11, 12)
5. Rennablauf (18)

Alles darunter erst, wenn das darüber geprüft läuft.
