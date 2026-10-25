# Mac Spaces Wallpaper Manager

[English](README.md) | **Deutsch**

Ich habe Mac Spaces Wallpaper Manager für den eigenen Gebrauch entwickelt. Die fertige Universal-App gibt es unter [GitHub Releases](https://github.com/DWegmann/MacSpacesWallpaperManager/releases/latest). Fehler und Vorschläge kannst du über ein [GitHub-Issue](https://github.com/DWegmann/MacSpacesWallpaperManager/issues) melden.

> **Nichtkommerzielle Weiterverwendung:** Der ursprüngliche Projektcode darf unter der [PolyForm Noncommercial License 1.0.0](LICENSE.md) verwendet, verändert und weitergegeben werden. Diese Lizenz erlaubt keine kommerzielle Nutzung.

Native macOS-App für eigene Bilderordner pro Desktop-Space und Bildschirm. Geschrieben mit SwiftUI und AppKit, mit Sparkle 2 für App-Updates. Ein Universal-Binary unterstützt **Apple Silicon (ARM64) und Intel (x86_64), ab macOS 13 Ventura**.

**macOS 26 Tahoe ist ausdrücklich als Ziel vorgesehen.** Die Mindestversion der App ist macOS 13, die des optionalen Direktmodus macOS 14; beide schließen macOS 26 ein. Es werden keine ausschließlich ab macOS 27 verfügbaren öffentlichen APIs benötigt. Der Direktmodus prüft das vorgefundene private Speicherformat vor jeder Änderung und bleibt standardmäßig ausgeschaltet.

## Funktionen

- Eigene Bilderordner pro Desktop-Space und Bildschirm, auf Wunsch einschließlich Unterordnern.
- Galerie mit Vorschauen, manueller Bildauswahl sowie zufälliger oder alphabetischer Reihenfolge.
- Automatischer Bildwechsel beim Betreten eines Spaces oder in festen Intervallen.
- Gemeinsame Bearbeitung mehrerer Spaces, Bildanpassung und eigene Hintergrundfarben.
- Menüleistensteuerung, Pause und optionaler Start bei der Anmeldung.
- Optionaler experimenteller Direktmodus für inaktive Spaces mit lokalen Sicherungen und Rücknahme.
- Lokale Bildverarbeitung; abschaltbare Update-Prüfung über GitHub und Installation per Klick.

## Lizenz

Der ursprüngliche Projektcode wird unter der **PolyForm Noncommercial License 1.0.0** veröffentlicht, analog zu [Lichtblick](https://github.com/DWegmann/Lichtblick). Maßgeblich ist der vollständige [Lizenztext](LICENSE.md). Bei Weitergabe müssen der Lizenztext oder seine URL sowie die erforderlichen Hinweise erhalten bleiben.

Required Notice: Copyright 2026 Dominic Wegmann

Die Lizenz gilt für die ursprünglichen Projektbestandteile, soweit entsprechende Rechte bestehen. Der Quellcode ist zur nichtkommerziellen Weiterverwendung öffentlich verfügbar („source available“); die kommerzielle Einschränkung entspricht keiner Open-Source-Lizenz im Sinne der OSI.

## Download und erster Start

1. Lade [Mac-Spaces-Wallpaper-Manager-universal.zip](https://github.com/DWegmann/MacSpacesWallpaperManager/releases/latest/download/Mac-Spaces-Wallpaper-Manager-universal.zip) aus dem aktuellen Release herunter. Dieselbe App läuft auf Apple-Silicon- und Intel-Macs ab macOS 13. Xcode oder Entwicklerwerkzeuge sind nicht erforderlich.
2. Entpacke das ZIP per Doppelklick im Finder und verschiebe **Mac Spaces Wallpaper Manager.app** in den Ordner **Programme**.
3. Starte die App per Doppelklick.

Die veröffentlichte App ist **ad-hoc signiert und nicht von Apple notarisiert**. macOS kann den ersten Start blockieren, weil der Entwickler nicht verifiziert oder die App nicht auf Schadsoftware geprüft werden kann. Wenn du diesem Download vertraust, kannst du die App nach Apples Anleitung einzeln freigeben:

1. Versuche einmal, die App zu öffnen, und schließe die Warnung, ohne die App in den Papierkorb zu bewegen.
2. Öffne **Systemeinstellungen → Datenschutz & Sicherheit** und scrolle zum Abschnitt **Sicherheit**.
3. Klicke bei der Meldung zu Mac Spaces Wallpaper Manager auf **Dennoch öffnen**.
4. Bestätige gegebenenfalls mit deinem Passwort oder Touch ID und anschließend im Dialog mit **Öffnen**.

Danach kannst du die App wie gewohnt aus dem Programme-Ordner starten. Die Freigabe gilt für diese App; Gatekeeper oder System Integrity Protection (SIP) müssen dafür nicht abgeschaltet werden. Siehe auch [Apples Anleitung zum Öffnen nicht notarisierter Apps](https://support.apple.com/de-de/102445). Auf einem verwalteten Mac kann die Richtlinie deiner Organisation die Freigabe verhindern.

## App selbst bauen

Beim ersten Build lädt Swift Package Manager Sparkle 2.10.0 von GitHub herunter. Lizenzhinweise stehen in [ThirdPartyNotices.md](ThirdPartyNotices.md) und werden in die App übernommen.

Voraussetzung für den App-Build: Xcode oder die Xcode Command Line Tools mit Swift 5.9 oder neuer. Für die XCTest-Tests wird vollständiges Xcode benötigt.

```sh
git clone https://github.com/DWegmann/MacSpacesWallpaperManager.git
cd MacSpacesWallpaperManager
```

```sh
./Scripts/build-app.sh --open
```

Ergebnis:

- `dist/Mac Spaces Wallpaper Manager.app`: fertige Universal-App, lokal ad-hoc signiert.
- `dist/Mac-Spaces-Wallpaper-Manager-universal.zip`: ZIP zum Weitergeben.

Die App kann in den Programme-Ordner kopiert werden. Für den optionalen Start bei Anmeldung empfiehlt sich dieser Ort. Für Entwicklung `Package.swift` in Xcode öffnen oder `./Scripts/swift-task.sh build` ausführen.

Die Skripte bevorzugen ein installiertes `/Applications/Xcode.app`; eine explizite Auswahl über `DEVELOPER_DIR` hat Vorrang. In einer eingeschränkten Entwicklungsumgebung auf einem externen Volume kann der Build-Cache mit `WALLPAPER_BUILD_ROOT=/private/tmp/MacSpacesWallpaperManager-build ./Scripts/build-app.sh` auf das temporäre lokale Volume verlegt werden.

Ein installiertes **macOS-26-SDK** wird automatisch bevorzugt, auch wenn die ausgewählte Xcode-Version neuer ist. Mit `WALLPAPER_MACOS_SDK=/absoluter/Pfad/MacOSX26.sdk ./Scripts/build-app.sh` lässt sich ein SDK ausdrücklich wählen. Ohne installiertes 26-SDK wird das ausgewählte macOS-SDK verwendet; das Deployment Target bleibt 13.0. Das verwendete SDK wird im Build ausgegeben und als `DTSDKName` im App-Bundle festgehalten. Eine höhere SDK-Version ist keine höhere Mindestversion zum Ausführen der App.

## Benutzung

Ab Version 1.3.0 prüft die App standardmäßig täglich auf neue Versionen. **Nach Updates suchen …** ist im App-Menü, in der Menüleiste und unter **Einstellungen → Updates** verfügbar. Dort lässt sich die automatische Prüfung ausschalten; die manuelle Prüfung bleibt verfügbar. Download und Installation startest du per Klick. Anschließend wird die App neu gestartet. Update-Feed und ZIP werden mit einem eigenen Ed25519-Schlüssel geprüft; es werden keine Bilder oder Ordnerpfade übertragen und kein Systemprofil gesendet. GitHub erhält die üblichen Verbindungsdaten einer Download-Anfrage.

Ältere Versionen müssen einmal manuell durch eine Version ab 1.3.0 ersetzt werden. Der Update-Feed ist verfügbar, sobald das erste Release mit `appcast.xml` veröffentlicht wurde. Hinweise zum Erstellen und Veröffentlichen signierter Updates stehen in [UPDATING.md](UPDATING.md).

1. Gewünschten Desktop in der Seitenleiste auswählen. Weitere Desktops vorher in Mission Control anlegen.
2. **Bilderordner auswählen**. Im Standardmodus wird ein erstes Bild auf dem sichtbaren Desktop gesetzt; ein inaktiver Desktop erhält es beim nächsten Besuch. Der zusätzliche Direktmodus kann auch inaktive Desktops sofort aktualisieren.
3. **Unterordner einbeziehen** schaltet die rekursive Suche ein oder aus; standardmäßig ist sie eingeschaltet.
4. Optional ein Bild in der Galerie auswählen, die Darstellung ändern oder einen automatischen Bildwechsel einstellen.

Jeder Space hat eigene Einstellungen: Ordner, Rekursion, Bildauswahl, Darstellung, Reihenfolge und Wechselintervall. Zufällige Auswahl vermeidet direkte Wiederholungen, sofern mindestens zwei Bilder verfügbar sind. Alphabetische Reihenfolge verwendet natürliche Dateinamensortierung.

### Einstellungen für mehrere Spaces

Über **Auswählen** neben „Deine Spaces“ wird die Mehrfachauswahl geöffnet. Die gewünschten Desktop-Zeilen lassen sich anhaken; **Alle** neben einem Bildschirm wählt dessen Spaces aus. In der gemeinsamen Bearbeitung stehen außerdem **Alle auswählen** und **Auswahl leeren** zur Verfügung.

Anschließend die gewünschten Änderungen anhaken: Bilderordner, Unterordner, Bildwechsel, Darstellung, Hintergrundfarbe, Reihenfolge oder Aktivierung. **Auf … Spaces anwenden** übernimmt ausschließlich diese Felder für die ausgewählten Spaces. Nicht angehakte Einstellungen und die anderen Spaces bleiben erhalten. Bestehende Bildauswahlen werden beibehalten, solange kein neuer Ordner zugeordnet wird. Ein neuer gemeinsamer Ordner setzt die Bildauswahl der betroffenen Spaces zurück und wird für sie neu eingelesen. Mit **Fertig** oder **Mehrfachauswahl beenden** geht es zurück zur Einzelbearbeitung.

### Hintergrundfarbe beim Anpassen

Bei der Darstellung **An Bildschirm anpassen** erscheint **Hintergrundfarbe** mit einer nativen Farbauswahl. Die Farbe füllt die freien Flächen neben beziehungsweise über dem Bild und ist in der Vorschau sichtbar. Der aktuelle Farbname (etwa **Silber**) beziehungsweise der Hexwert wird direkt angezeigt. **Auf Schwarz zurücksetzen** setzt die Farbe zurück. Sie wird pro Space gespeichert und funktioniert im Standardmodus und im optionalen Direktmodus. In der Mehrfachauswahl lässt sich dieselbe Farbe auf mehrere Spaces übertragen; die Darstellung wird dabei nur geändert, wenn auch „Darstellung ändern“ angehakt ist. Vorhandene Einstellungen ohne Farbangabe verwenden weiterhin Schwarz.

Automatischer Wechsel: manuell, bei erneutem Betreten eines Spaces, alle 5/15/30 Minuten, stündlich oder täglich. Im Standardmodus holen inaktive Desktops einen fälligen Wechsel beim nächsten Besuch nach; mit eingeschaltetem Direktmodus werden auch inaktive Desktops aktualisiert. Während des Ruhezustands wird kein Timer abgearbeitet. Neue oder entfernte Dateien werden mit **Ordner neu einlesen** übernommen. Der Timer prüft alle 15 Sekunden, sodass Intervalle entsprechend leicht verzögert sein können.

Das Fenster kann geschlossen werden; die App läuft in der Menüleiste weiter. Dort gibt es **Nächstes Hintergrundbild**, **Automatik pausieren** und **Beenden**. `⌘R` aktualisiert die Spaces, `⇧⌘N` setzt das nächste Bild für sichtbare, aktivierte Spaces. In den Einstellungen (`⌘,`) lässt sich der Anmeldestart einschalten.

## Zusätzlicher Direktmodus für inaktive Spaces

Unter **Einstellungen → Direktmodus (experimentell) → Auch inaktive Spaces sofort aktualisieren** lässt sich der inoffizielle Weg einschalten. Die Option ist bei neuen und vorhandenen Installationen standardmäßig ausgeschaltet. Sie benötigt macOS 14 oder neuer und eine lesbare `Index.plist`.

Im Direktmodus gelten Bildauswahl, Darstellung und Wechselintervalle auch für inaktive, zugeordnete Desktop-Spaces. Ein Wechsel zwischen Desktops ist dafür nicht nötig. Änderungen mehrerer Spaces werden kurz gesammelt, damit der Hintergrunddienst möglichst nur einmal neu gestartet wird.

Der Modus ändert ausschließlich `Spaces[Space-UUID].Displays[Bildschirm-UUID].Desktop` in `~/Library/Application Support/com.apple.wallpaper/Store/Index.plist`. Andere Spaces, die Bildschirm- und Space-Standardwerte sowie Bildschirmschoner werden beibehalten. Fehlt ein Bildschirm-Eintrag, wird eine eigene Zuordnung aus dem vorhandenen Space-Standard angelegt. Die macOS-Einstellung **Auf allen Spaces anzeigen** muss vorher ausgeschaltet sein. Gekoppelte Hintergrund-/Bildschirmschoner-Einträge und unbekannte Formate werden abgewiesen; dafür kann der Standardmodus verwendet werden.

Vor jeder tatsächlichen Änderung entsteht eine lokale Sicherung. Der Hintergrunddienst `WallpaperAgent` des angemeldeten Benutzers wird für die kurze Schreibphase angehalten und anschließend neu gestartet. Ein unabhängiger Hilfsprozess setzt ihn spätestens nach drei Sekunden fort, falls die App während der Schreibphase beendet wird. **Beim Bildwechsel kann der Hintergrund dabei kurz flackern.** Dieser Hinweis steht auch direkt bei der experimentellen Option in den Einstellungen. Dateischreibzugriffe erfolgen atomar; konkurrierende Änderungen werden vor dem Schreiben und nach dem Neuladen geprüft. Bei einem Fehler versucht die App, die eigene Änderung zurückzunehmen, deaktiviert den Direktmodus und pausiert die Automatik. Der Grund und der Sicherungsort werden angezeigt. Danach kann im Standardmodus fortgefahren werden.

**Letzte Direktmodus-Änderung rückgängig machen …** in den Einstellungen stellt nur die zuletzt betroffenen Desktop-Hintergründe wieder her und pausiert die Automatik. Wurde ein betroffener Hintergrund inzwischen außerhalb der App geändert, wird die Rücknahme abgebrochen. Spätere Änderungen an anderen Spaces oder vorhandenen Bildschirmschonern bleiben erhalten.

Die zehn neuesten Sicherungen liegen unter `~/Library/Application Support/SpacePaper/WallpaperBackups/`. Jede enthält `before.plist`, `after.plist` und ein gezieltes Rücknahmeprotokoll `undo.plist`; die Dateien sind nur für den Benutzer lesbar. Die Einstellungen bieten einen Knopf zum Öffnen der Sicherungen im Finder. Der Direktmodus ist nicht von Apple unterstützt und kann nach macOS-Updates eine Anpassung benötigen. Das Grundverfahren ist beispielsweise in [backgrounds](https://github.com/ThomasBPG/backgrounds/blob/main/wallhaven-wallpaper.py) und [wallall](https://github.com/TresChar/wallall) nachvollziehbar; diese App schreibt gezielt einzelne Zuordnungen statt einen gemeinsamen Hintergrund für alle Spaces.

## Grenzen von macOS

Apple stellt [NSWorkspace.setDesktopImageURL](https://developer.apple.com/documentation/appkit/nsworkspace/setdesktopimageurl(_:for:options:)) zum Setzen eines Bildschirmhintergrunds und [Space-Wechsel-Benachrichtigungen](https://developer.apple.com/documentation/appkit/nsworkspace/activespacedidchangenotification) bereit. Eine öffentliche Schnittstelle zum Auflisten und stabilen Identifizieren aller Spaces fehlt.

Mac Spaces Wallpaper Manager lädt deshalb zwei **nur lesende, nicht öffentliche SkyLight-Funktionen** dynamisch. Das Datenformat ist unter anderem in der [Implementierung von Hammerspoon](https://github.com/Hammerspoon/hammerspoon/blob/master/extensions/spaces/spaces.lua) nachvollziehbar. UUIDs identifizieren Desktops unabhängig von ihrer Reihenfolge und temporären Nummer. Im Standardmodus werden Hintergrundbilder über die öffentliche AppKit-Schnittstelle gesetzt; der optionale Direktmodus schreibt die private macOS-Hintergrunddatei.

- Im Standardmodus wird eine Zuordnung für einen inaktiven Space erst angewendet, wenn du ihn besuchst und Mac Spaces Wallpaper Manager läuft. Der zusätzliche Direktmodus kann sie bereits vorher setzen. Die App wechselt nicht selbständig zwischen Spaces.
- Normale Desktop-Spaces werden unterstützt; Vollbild- und Split-View-Spaces werden ausgelassen.
- Mehrere Bildschirme werden separat behandelt, auch bei gemeinsam verwalteten Spaces. Abgetrennte Bildschirme behalten ihre gespeicherten Zuordnungen.
- Wird ein Space gelöscht und neu angelegt, erhält er eine neue Identität und muss neu konfiguriert werden.
- Nach einem macOS-Update kann die Space-Erkennung eine Anpassung benötigen. Bei fehlgeschlagener Erkennung erfolgen keine Hintergrundänderungen.
- Wegen der privaten Erkennung ist die App für direkte Distribution vorgesehen, nicht für den Mac App Store. Es sind weder Bedienungshilfen noch Bildschirmaufnahme oder ein Abschalten von SIP erforderlich.
- Ein parallel aktiver macOS-Diashow-Wechsel oder eine andere Wallpaper-App kann die Auswahl überschreiben. Für die betroffenen Desktops deren automatische Rotation ausschalten.

## Bilder und Daten

JPEG, PNG, HEIC, TIFF und weitere von macOS ImageIO lesbare Bildformate werden automatisch erkannt. Die App liest Bildmetadaten ein und erzeugt verkleinerte, zwischengespeicherte Vorschauen. Versteckte Dateien, Paket-Inhalte und symbolische Verknüpfungen werden übersprungen. Fehlerhafte Bilder und nicht lesbare Unterordner werden mit einem Hinweis gemeldet. Eine beschädigte Bilddatei kann beim eigentlichen Setzen dennoch einen zusätzlichen macOS-Fehler auslösen.

Originale bleiben unverändert in deinem Ordner. Bilder und Ordnerzuordnungen werden lokal verarbeitet. Ausschließlich die Update-Funktion greift auf GitHub zu; automatische Prüfungen lassen sich abschalten. Einstellungen und Ordner-Lesezeichen liegen atomar gespeichert unter:

```text
~/Library/Application Support/SpacePaper/configuration.json
```

Der bisherige interne Datenordner und die Bundle-ID bleiben bei der Umbenennung erhalten, damit bestehende Zuordnungen weiterhin geladen werden.

Bei einer beschädigten oder unbekannten Einstellungsdatei stoppt die App automatische Änderungen und erhält die Datei. Über **Einstellungsdatei im Finder zeigen** lässt sich diese nach Beenden der App sichern und für einen Neustart umbenennen.

## Prüfen

```sh
./Scripts/swift-task.sh test
"./dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager" --diagnostics
"./dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager" --direct-store-check
lipo -archs "dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager"
codesign --verify --deep --strict "dist/Mac Spaces Wallpaper Manager.app"
```

`--diagnostics` liest die tatsächlichen Desktop-UUIDs, sichtbaren Spaces und Bildschirme aus, ohne Einstellungen zu laden oder Hintergrundbilder zu ändern. `--direct-store-check` prüft eine gezielte Änderung und deren vollständige Rücknahme ausschließlich im Speicher gegen die vorhandene macOS-Datei; dabei werden weder Dateien geschrieben noch Prozesse signalisiert. Ein erfolgreicher Prüfmodus bestätigt das erkannte Speicherformat, nicht die tatsächliche Darstellung nach einem Dienst-Neustart.

Die Tests prüfen rekursive Suche, natürliche Sortierung, beschädigte Dateien, Symlink-Zyklen, Abbruch, mehrere Bildschirme, Vollbildfilterung, persistente Identität, Bildauswahl, Intervalle und Datenspeicherung. Sammeländerungen werden auf die gewählten Spaces und ausdrücklich angegebenen Felder beschränkt; Farbwerte und die Rückwärtskompatibilität bestehender Einstellungen werden ebenfalls geprüft. Für den Direktmodus werden gezielte Änderungen einschließlich Hintergrundfarbe, Unicode-Pfade, Sicherungen, Rücknahme, externe Änderungen, fehlgeschlagenes Neuladen, Wiederherstellungsfehler, Zugriffsrechte und die begrenzte Sicherungsanzahl mit temporären Dateien und einem simulierten Hintergrunddienst geprüft. Die echten Hintergrund-Einstellungen werden von den automatisierten Tests nicht geändert.

Für den praktischen Funktionstest: zwei normale Desktops anlegen, verschiedene Testordner zuordnen, zwischen ihnen wechseln und Rekursion an/aus prüfen. Danach Bildauswahl, Timer, Pause, Neustart und gegebenenfalls einen weiteren Bildschirm prüfen. Ein Intel-Build kann auf einem Apple-Silicon-Mac erzeugt und geprüft werden; ein echter Intel-Laufzeittest erfordert einen Intel-Mac.

Für die Kompatibilitätsprüfung mit macOS 26 werden App und Tests gegen das macOS-26-SDK gebaut. Die Mach-O-Angaben lassen sich mit `xcrun vtool -show-build "dist/Mac Spaces Wallpaper Manager.app/Contents/MacOS/MacSpacesWallpaperManager"` kontrollieren: `minos` bezeichnet die Mindestversion, `sdk` das SDK beim Kompilieren. Ein SDK-Build und Tests auf einem neueren Host ersetzen keinen Laufzeittest auf einem echten macOS-26-System, insbesondere für den inoffiziellen Direktmodus.

## Signieren für Distribution

```sh
SIGNING_IDENTITY='Developer ID Application: DEIN NAME (TEAMID)' ./Scripts/build-app.sh
xcrun notarytool submit dist/Mac-Spaces-Wallpaper-Manager-universal.zip --keychain-profile DEIN_PROFIL --wait
xcrun stapler staple "dist/Mac Spaces Wallpaper Manager.app"
```

Der GitHub-Download ist ad-hoc signiert und nicht notarisiert; dafür gilt die Anleitung zum ersten Start weiter oben. Für eine mit Developer ID signierte und notarisierte Variante werden eigene Apple-Zugangsdaten für die obigen Befehle benötigt. Nach dem Stapeln für die Weitergabe ein neues ZIP mit `ditto -c -k --sequesterRsrc --keepParent "dist/Mac Spaces Wallpaper Manager.app" dist/Mac-Spaces-Wallpaper-Manager-notarized.zip` erzeugen.

## Projektstruktur

- `Sources/MacSpacesWallpaperManager`: SwiftUI-Oberfläche, App-Zustand, Menüleiste und Einstellungen.
- `Sources/WallpaperCore`: Space-Erkennung, Bildsuche, Konfiguration und optionaler Direktmodus.
- `Tests/WallpaperCoreTests`: Tests mit temporären Dateien und simuliertem Hintergrunddienst.
- `Resources/Info.plist`: App-Metadaten und Mindestversion.
- `Scripts`: SDK-Auswahl, Swift-Builds und Erstellung der Universal-App.
- `Tools/GenerateIcon.swift`: Erzeugung des App-Icons.
- `Scripts/prepare-update.sh`, `ReleaseNotes`, `UPDATING.md`: signierte Update-Pakete und Release-Ablauf.

Build-Ergebnisse und lokale Entwicklungsdateien werden über `.gitignore` ausgeschlossen. Fehler und Vorschläge können als [GitHub-Issue](https://github.com/DWegmann/MacSpacesWallpaperManager/issues) gemeldet werden. Bei Problemen mit der Space-Erkennung bitte macOS-Version, Architektur, Bildschirmkonfiguration und eine bereinigte Fehlermeldung angeben.
