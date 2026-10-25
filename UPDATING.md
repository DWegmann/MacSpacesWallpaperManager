# App-Updates veröffentlichen

Die App verwendet Sparkle 2.10.0. Der Update-Feed liegt als Release-Asset unter
`https://github.com/DWegmann/MacSpacesWallpaperManager/releases/latest/download/appcast.xml`.
GitHub liefert diesen Feed aus dem als **Latest** markierten stabilen Release aus.
Es ist kein eigener Server und keine GitHub-Pages-Konfiguration nötig.

Automatische Prüfungen sind standardmäßig täglich aktiv und abschaltbar. Download
und Installation benötigen einen Klick; automatische Installation ist auch im
Sparkle-Dialog deaktiviert. Sowohl Feed als auch ZIP werden mit Ed25519 geprüft.
Die App sendet kein Systemprofil und keine Bilder oder Ordnerzuordnungen.

## Schlüssel einmalig sichern

Der Veröffentlichungsschlüssel wurde im macOS-Schlüsselbund dieses Macs angelegt:

- Dienst: `https://sparkle-project.org`
- Account: `app.spacepaper.mac`
- Name: `Private key for signing Sparkle updates`
- Öffentlicher Schlüssel: `SUPublicEDKey` in `Resources/Info.plist`

Der private Schlüssel gehört weder ins Repository noch in Release-Assets. Eine
verschlüsselte Sicherung in einem Passwortmanager oder einem vergleichbaren Tresor
ist erforderlich, bevor dieser Mac oder sein Schlüsselbund ersetzt wird. Sparkle
kann den Schlüssel mit `generate_keys --account app.spacepaper.mac -x DATEI`
exportieren und mit `-f DATEI` auf einem anderen Mac wieder importieren. Die
exportierte Datei ist ein unverschlüsseltes Geheimnis: nur an einem geschützten Ort
außerhalb des Repositories erstellen, sicher übertragen und danach entfernen.

Die Werkzeuge lassen sich nach einem Build über den folgenden Wrapper aufrufen:

```sh
./Scripts/sparkle-tool.sh generate_keys --account app.spacepaper.mac -p
```

Das zeigt ausschließlich den öffentlichen Schlüssel. Bei eigenem Build-Cache muss
für alle Skripte derselbe `WALLPAPER_BUILD_ROOT` gesetzt sein. Beim ersten Zugriff
eines Sparkle-Werkzeugs kann macOS eine Schlüsselbund-Bestätigung verlangen.
Bei fehlendem oder unpassendem Schlüssel bricht das Release-Skript ab. Es erzeugt
keinen Ersatzschlüssel und überschreibt den öffentlichen Schlüssel nicht.

## Release vorbereiten

1. `CFBundleShortVersionString` und `CFBundleVersion` in `Resources/Info.plist`
   erhöhen. Die numerische Buildnummer muss bei jeder veröffentlichten Version
   steigen; Sparkle verwendet sie zum Versionsvergleich.
2. Änderungsnotizen unter `ReleaseNotes/vVERSION.md` anlegen.
3. Bauen und prüfen:

   ```sh
   ./Scripts/swift-task.sh test
   ./Scripts/build-app.sh
   python3 Scripts/test-updates.py
   ```

   Die Update-Integrationstests verwenden eine eigene Test-App, einen lokalen
   HTTP-Server auf `127.0.0.1` und einen wegwerfbaren Testschlüssel. Sie prüfen
   Feed-Erzeugung, Signaturen, manipulierte Daten, Versionsvergleich und die
   Speicherung der Update-Einstellung. Die eigentliche Wallpaper-App wird dabei
   nicht gestartet und kein Update installiert.

4. Falls mit Developer ID verteilt wird, `SIGNING_IDENTITY` wie in der README
   setzen, danach notarisieren und das Ticket an die App stapeln. Erst anschließend
   das Update vorbereiten. Sparkle-Signaturen ersetzen Apples Signierung und
   Notarisierung nicht. Ad-hoc-Builds verwenden weiterhin die in der README
   beschriebene manuelle Freigabe beim ersten Start.
5. Das lokale Release-Paket erzeugen, beispielsweise:

   ```sh
   ./Scripts/prepare-update.sh v1.3.0
   ```

   Optional lässt sich der Pfad zu einer anderen Markdown-Datei als zweites Argument
   angeben. Das Skript prüft, dass der Tag zur gebauten Version passt und der
   Schlüsselbund-Schlüssel dem öffentlichen Schlüssel der App entspricht. Es
   verpackt die finale App erneut, erzeugt mit Sparkles `generate_appcast` einen
   signierten Feed mit eingebetteten Release Notes und prüft Feed-Signatur,
   ZIP-Signatur, Download-URL und Dateigröße. Die Werkzeuge können beim ersten
   Zugriff auf den Schlüssel eine Bestätigung verlangen.

   Die Dateien liegen unter `dist/updates/v1.3.0/`. Ein vorhandener Release-Ordner
   wird nicht überschrieben. Für einen neuen Versuch diesen Ordner zuerst sichern
   oder entfernen. Nach Änderungen an der App, am ZIP oder Feed neu erzeugen und
   signieren; signierte Dateien dürfen nicht nachträglich bearbeitet werden.

## Auf GitHub veröffentlichen

Ein neues Release zunächst als Entwurf für den passenden Tag erstellen und diese
beiden Dateien gemeinsam anhängen:

- `Mac-Spaces-Wallpaper-Manager-universal.zip`
- `appcast.xml`

Die Markdown-Notizen aus `ReleaseNotes` außerdem als Release-Beschreibung verwenden.
Die gleichnamige `.md`-Datei im Ausgabeordner muss nicht hochgeladen werden, da die
Notizen im signierten Feed eingebettet sind. Nach der Prüfung den Entwurf
veröffentlichen und als **Latest** markieren. Das lokale Skript lädt nichts hoch.

ZIP und Feed müssen aus demselben Skriptlauf stammen und zum selben Tag gehören.
Der Feed enthält feste Download-URLs mit diesem Tag; veröffentlichte ZIPs nicht
nachträglich ersetzen. Korrekturen als neue Version mit höherer Buildnummer
veröffentlichen.

Vor der ersten Veröffentlichung existiert die Feed-URL noch nicht. Eine manuelle
Prüfung zeigt dann einen Downloadfehler. Nach Veröffentlichung prüfen, dass die
oben genannte Feed-URL die signierte XML-Datei liefert und eine ältere Testversion
das Update erkennt. Für einen tatsächlichen Installations-/Neustarttest eine
separate Testkopie verwenden.

Versionen vor 1.3.0 besitzen noch keinen Updater und müssen einmal manuell ersetzt
werden. Einstellungen bleiben durch die bestehende Bundle-ID und den bisherigen
Datenordner erhalten.

Der erste Feed enthält nur die aktuelle Universal-Version für macOS 13 oder neuer.
Sollte eine spätere Version die Mindestanforderungen erhöhen, den Feed um die letzte
für ältere Systeme geeignete Version ergänzen, statt diese aus dem Feed zu entfernen.
