# Development Log - The Parasites QuickStack

Stand: 2026-05-25

Diese Datei dokumentiert die relevanten Schritte, mit denen QuickStack
entwickelt, getestet, verpackt und fuer die Veroeffentlichung vorbereitet
wurde.

## Ausgangspunkt

QuickStack entstand als UE4SS/Lua-Mod fuer The Parasites
`TP_Alpha_v_0.1.5.0.0`. Das Ziel war ein Hotkey, der Inventarstacks in einen
geoeffneten Container verschiebt, wenn dieser Container denselben Itemtyp
bereits enthaelt.

Gewuenschter Nutzerablauf:

1. Container oeffnen.
2. `Ctrl+F9` druecken.
3. Nur passende Stacks wandern in den Container.
4. unpassende Items, Ausruestung, Waffen und Spezialslots bleiben unberuehrt.

## Recherche

1. UE4SS als technische Basis gewaehlt.
   - Lua-Mod statt Save-Editor, weil das Feature im laufenden UI/Inventar
     passieren muss.
   - UE4SS Runtime wurde in das Release-Paket aufgenommen.

2. UI- und Containerklassen untersucht.
   - relevante Widget-/Containerklasse:
     - `JSIContainer_C`
   - relevante Multiplayer-/Inventory-Komponente:
     - `BP_JigMultiplayer_C`
   - Ziel war, geoeffnete Container und Spielerinventar sicher zu unterscheiden.

3. Container-Metadaten gesucht.
   - Container-ID.
   - Parent-ID.
   - Grid-Groesse.
   - zugehoerige Multiplayer-Komponente.
   - Slot-/Equipment-Container.

4. UE4SS-Property-Zugriff erweitert.
   - Custom Properties fuer primitive Containerwerte registriert.
   - Fallbacks fuer alternative Property-Namen eingebaut.
   - robuste Hilfsfunktionen fuer:
     - `GetPropertyValue`.
     - direktes Indexing.
     - `TArray`-Zugriff.
     - Null-Objekt-Erkennung.
     - Adress-/Objektvergleich.

## Trial and Error

QuickStack benoetigte mehrere Testphasen, weil Inventar- und UI-Objekte im
laufenden Spiel schwer direkt zu erkennen sind.

1. Rohes Container-Probing.
   - `FindAllOf("JSIContainer_C")` wurde genutzt.
   - Containerkandidaten wurden geloggt.
   - Ziel war, sichtbare Container vom Spielerinventar und unsichtbaren
     Hilfscontainern zu trennen.

2. Dry-run- und Candidate-Scans.
   - Es wurden Suchlaeufe ohne Itembewegung eingebaut.
   - Diese gaben Containergruppen, Slots und moegliche Matching Items aus.
   - Riskante Struct-Reads wurden nach einem Crashpfad deaktiviert.

3. Empty-slot- und Slot-Probes.
   - Getestet wurde, welche Slots tatsaechlich Itemdaten tragen.
   - Leere und unbrauchbare Slots wurden herausgefiltert.

4. Single-move-Tests.
   - Zunaechst durfte nur ein Stack bewegt werden.
   - Dadurch wurde die korrekte Server-/Client-Sequenz gesucht, ohne bei Fehlern
     massenhaft Items zu bewegen.

5. Die funktionierende Move-Sequenz.
   - Der stabile Ablauf wurde:

```text
SERVER_RequestMoveItemToAnotherComp
RemoveInventoryItemByRef
CLIENT_ItemRemoved
```

   - Nur der Server-Request allein war nicht genug.
   - Die lokale Quellinventar-Bereinigung war notwendig, damit UI/Clientzustand
     nachvollziehbar bleibt.

6. Mehrfachbewegung mit Delay.
   - Direktes massenhaftes Verschieben in einer engen Schleife wurde verworfen.
   - Der finale Full-QuickStack verschiebt Schritt fuer Schritt.
   - Zwischen Moves liegt ein Delay, damit Spiel und UI Zeit zum Aktualisieren
     haben.

7. Zielcontainer-Anker.
   - Der Zielcontainer wird beim Start des QuickStack-Runs festgehalten.
   - Folgebewegungen suchen denselben Container anhand Adresse, Container-ID und
     Multiplayer-Komponente erneut.
   - Dadurch wird reduziert, dass der Lauf mitten im Prozess in den falschen
     Container kippt.

8. Debug-Hotkeys fuer Public deaktiviert.
   - Probe-/Debugfunktionen blieben im Code zur Wartung erhalten.
   - Public Runtime nutzt aber nur `Ctrl+F9`.
   - `QUICKSTACK_DEBUG_MODE = false`.

## Finaler Code

Der finale Mod-Code liegt in:

```text
COPY_TO_GAME_WIN64/ue4ss/Mods/TheParasitesQuickStack/scripts/main.lua
```

Wichtige Bestandteile:

- Hotkey `Ctrl+F9`.
- Container-/Inventar-Erkennung.
- Gruppierung sichtbarer Container.
- Matching nach Itemtypen, die bereits im Zielcontainer existieren.
- Skip-Logik fuer:
  - ausgeruestete Waffen.
  - Tools.
  - Waffenattachments.
  - Equipment- und Spezialslots.
  - nicht passende Itemtypen.
- server-first Move-Sequenz.
- Schrittweises Full-QuickStack mit Delay.
- Zielcontainer-Anker.
- Cooldown gegen Doppeltrigger.
- Move-Limit als Sicherheit.
- Logdatei neben dem installierten Mod:

```text
ue4ss/Mods/TheParasitesQuickStack/QuickStack.log
```

## Installer und Paket

QuickStack wurde als komplettes portables UE4SS-Paket gebaut.

Release-Struktur:

```text
COPY_TO_GAME_WIN64/
Install_QuickStack.cmd
Uninstall_QuickStack.cmd
scripts/Install_QuickStack.ps1
scripts/Uninstall_QuickStack.ps1
```

Installer-Verhalten:

- fragt den The-Parasites-`Win64`-Ordner ab.
- akzeptiert alternativ `-GameWin64 "<path>"`.
- prueft, dass `TheParasites-Win64-Shipping.exe` vorhanden ist.
- blockiert Installation, wenn The Parasites laeuft.
- sichert vorhandene `dwmapi.dll`/`ue4ss`-Installationen.
- schreibt `last_backup.txt`.
- kopiert den UE4SS-Payload.
- schreibt einen Marker, damit die eigene Installation wieder erkannt wird.

Uninstaller-Verhalten:

- entfernt die installierten QuickStack-Dateien.
- arbeitet mit dem Marker, um nicht blind fremde Installationen zu zerstoeren.
- dokumentiert manuelles Vorgehen fuer bestehende UE4SS-Setups.

## Dokumentation und Repository-Aufbau

Das oeffentliche GitHub-Repository wurde aus dem lokalen Arbeitsprojekt als
bereinigte Staging-Kopie aufgebaut.

Repository:

```text
https://github.com/midnighter90/TheParasites_QuickStack
```

Oeffentliche Dateien:

- `README.md`
- `README_INSTALLATION.txt`
- `CHANGELOG.md`
- `CHANGELOG.txt`
- `RELEASE_NOTES_v1.0.0.md`
- `VERSION.txt`
- `PUBLISHING.md`
- `LICENSE.md`
- `COPYRIGHT_AND_TERMS.txt`
- `THIRD_PARTY_NOTICES.md`
- `THIRD_PARTY_NOTICES.txt`
- `MANIFEST_SHA256.txt`
- `.gitattributes`
- `.gitignore`

Nach dem ersten Upload wurde das Paket public-sicher bereinigt:

- keine persoenlichen Windows-Pfade in oeffentlichen Textdateien.
- kein lokaler Paket-/Source-Pfad im Installer-Marker.
- Installer verlangt den Game-`Win64`-Ordner oder den Parameter `-GameWin64`.
- Debug-/Probe-Hotkeys sind nicht Teil der Public-Bedienung.

## Lizenz- und Copyright-Arbeit

Die Terms wurden bewusst restriktiv gehalten:

- persoenliche, nicht-kommerzielle Nutzung.
- kein Reuploading.
- kein Mirroring.
- kein Reposting.
- kein Repackaging.
- keine bezahlte Distribution.
- keine kommerzielle Nutzung.
- keine Garantie.
- kein Supportversprechen.
- keine Zukunftskompatibilitaet.

UE4SS/RE-UE4SS bleibt unter MIT-Lizenz und wird in den Third-Party Notices mit
Lizenzdatei aufgefuehrt.

## GitHub-/Release-Arbeit

Durchgefuehrte Schritte:

1. lokales Arbeitsprojekt aufgebaut.
2. UE4SS-Payload zusammengestellt.
3. Lua-Mod in `TheParasitesQuickStack` erstellt.
4. Debug-/Probephase durchlaufen.
5. finalen `Ctrl+F9`-Workflow stabilisiert.
6. Installer und Uninstaller gebaut.
7. oeffentliche Staging-Repo-Kopie erzeugt.
8. persoenliche Pfade und lokale Notizen aus dem Public-Paket entfernt.
9. Manifest erzeugt.
10. Release-ZIP gebaut.
11. ZIP entpackt und Manifest geprueft.
12. `main`, `v1.0.0` und Release-Asset auf GitHub bereitgestellt.

## Verifikation

Durchgefuehrt wurden u.a.:

- PowerShell-Syntaxcheck fuer Installer/Uninstaller.
- manuelle/spielnahe QuickStack-Tests mit geoeffnetem Container.
- Single-move-Tests.
- Full-QuickStack-Tests mit Delay.
- Log-Ausgabe geprueft.
- Public-Paket auf persoenliche Pfade gescannt.
- Manifest-Hashes erzeugt und gegen entpacktes ZIP geprueft.
- GitHub-Remote, `main`, `v1.0.0` und Release-ZIP geprueft.

## Ergebnis

QuickStack ist ein portabler UE4SS-Mod fuer The Parasites. Der finale
Nutzerablauf ist:

1. The Parasites schliessen.
2. Release-ZIP entpacken.
3. `Install_QuickStack.cmd` starten.
4. Spiel starten.
5. Container oeffnen.
6. `Ctrl+F9` druecken.

Das finale Feature bewegt nur passende Stacks, nutzt eine getestete
Server-/Client-Move-Sequenz und versucht, Ausruestung und unpassende Items
nicht anzufassen.
