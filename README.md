# refdata-update

Hält die Referenzdaten einer INTERLIS-Validierung aktuell. Eine Validierung mit Referenzdaten (etwa DMAV mit `--refmapping`) holt die Referenzdaten aus einem INTERLIS-Repository, das in den Modell-Repositories steht: `ilidata.xml` nennt die Datensätze, das Mapping ordnet sie einem Scope zu, und die Dateien liegen unter den Pfaden, die `ilidata.xml` angibt. Damit die Prüfungen gegen einen aktuellen Stand laufen, müssen diese Dateien regelmässig neu bezogen werden.

Das erledigt das Image `ghcr.io/geowerkstatt/refdata-update`. Es bezieht die konfigurierten Dateien beim Start des Containers und danach nach Zeitplan, und es ersetzt jede Datei erst, wenn der neue Stand vollständig vorliegt. Eingesetzt wird es von [geopilot](https://github.com/geowerkstatt/geopilot) für die DMAV-Validierung.

## Betrieb

```yaml
services:
  refdata-update:
    image: ghcr.io/geowerkstatt/refdata-update:v1
    restart: unless-stopped
    environment:
      TZ: Europe/Zurich
      REFDATA_UPDATE_SCHEDULE: 0 1 * * *
    volumes:
      - ./repositories/dmav@0.1.1:/refdata
      - ./refdata-sources.yaml:/config/sources.yaml:ro

  # Bietet das Repository dem Validator als %REPOSITORIES/dmav@0.1.1 an
  ilitools-wrapper:
    # ...
    volumes:
      - ./repositories:/repositories:ro
```

| Einstellung | Bedeutung |
| --- | --- |
| Volume `/refdata` | Wurzel des Refdata-Repositorys mit seiner `ilidata.xml`, schreibbar. Dasselbe Verzeichnis bietet der ilitools-wrapper dem Validator an. |
| Datei `/config/sources.yaml` | Die Quellen, siehe unten. Nur lesend. |
| `REFDATA_UPDATE_SCHEDULE` | Zeitplan in Cron-Syntax mit fünf Feldern, Standard `0 1 * * *` (täglich um 1 Uhr). |
| `TZ` | Zeitzone des Zeitplans, etwa `Europe/Zurich`. Ohne Angabe gilt UTC. |
| `REFDATA_UPDATE_MAX_AGE_HOURS` | Nach wie vielen Stunden ohne fehlerfreien Lauf der Container als `unhealthy` gilt, Standard `36`. Bei einem selteneren Zeitplan entsprechend höher setzen. |

`ilidata.xml`, das Mapping und alle Dateien, die nicht in den Quellen stehen, fasst der Job nicht an. Sie legt der Betreiber in `/refdata` ab und pflegt sie selbst.

Den Validator erreicht das Repository am einfachsten direkt: Der [ilitools-wrapper](https://github.com/geowerkstatt/ilitools-wrapper) bietet jedes Verzeichnis unter seinem Mount `/repositories` als `%REPOSITORIES/<id>` in den Modell-Repositories an und liest es an Ort, ohne Download und ohne Cache ([geowerkstatt/geopilot#1075](https://github.com/geowerkstatt/geopilot/issues/1075)). Ein Webserver davor geht ebenfalls, dann gilt die Grenze durch den Cache weiter unten.

Einen Lauf ausserhalb des Zeitplans startet `docker compose exec refdata-update refdata-update`.

## Quellen

Eine YAML-Liste, ein Eintrag pro Quelle. Jede Quelle wird pro Lauf einmal heruntergeladen. Eine einzelne Datei nennt ihr Ziel mit `destination`; aus einem ZIP-Archiv zählt `extract` die Einträge auf, die entpackt werden, jeder mit seinem Ziel:

```yaml
# Eine Datei
- source: https://example.ch/daten/gemeinden.xtf
  destination: dmav_V1_1/refdata/Gemeinden95_2_4.xtf

# Ein Archiv: entry ist der Pfad im Archiv, destination das Ziel
- source: https://data.geo.admin.ch/ch.swisstopo-vd.ortschaftenverzeichnis_plz/ortschaftenverzeichnis_plz/ortschaftenverzeichnis_plz_2056.xtf.zip
  extract:
    - entry: AMTOVZ_INTERLIS24/OfficialIndexOfLocalities_V1_0.xtf
      destination: dmav_V1_1/refdata/OfficialIndexOfLocalities_V1_0.xtf
```

- `destination` ist relativ zu `/refdata` und muss ein `<path>` sein, den die `ilidata.xml` in `/refdata` nennt: ilivalidator erreicht Referenzdaten nur über deren Id, eine Datei, die der Index nicht nennt, würde nie gelesen. Ein anderes Ziel wird nicht bezogen und gilt als Fehler, ebenso ein Pfad mit führendem `/` oder mit `..`. Ohne lesbare `ilidata.xml` in `/refdata` bricht der Lauf ab.
- Nur `http` und `https` werden bezogen. Eine Quelle nennt entweder `destination` oder `extract`, nicht beides.
- Eine Vorlage mit den Referenzdaten des [DMAV-Repositorys](https://github.com/geowerkstatt/DMAV_ilivalidator), die Bundesdatensätze mit ihren Quellen, liegt in [`sources.example.yaml`](sources.example.yaml). HFP1 fehlt darin bewusst: swisstopo liefert LFP1 und HFP1 bei jedem Export mit derselben Basket-Id, und ilivalidator lädt dann nicht beide ("BID ... already exists"). Bis das mit der Quelle geklärt ist, bleibt die HFP1-Datei des DMAV-Repositorys stehen ([geowerkstatt/geopilot#1030](https://github.com/geowerkstatt/geopilot/issues/1030)).

Eine neue Quelle braucht ausser ihrem Eintrag hier:

1. einen Eintrag in der `ilidata.xml` mit einer Id und dem Pfad, den die Quelle als `destination` nennt;
2. ein Modell der Daten, das der Validator über seine Modell-Repositories findet: aus einem öffentlichen Repository oder als `.ili` im Repository samt Eintrag in dessen `ilimodels.xml`. Die Daten selbst stehen dort nicht;
3. einen Eintrag im Mapping für jeden Scope, der die Daten braucht, mit `ilidata:<Id>`;
4. keine eingecheckte oder mitgelieferte Kopie der Datei: Der Job würde sie überschreiben, jede Datei hat genau eine Herkunft.

## Verhalten bei Fehlern

Jede Datei wird neben ihrem Ziel heruntergeladen oder entpackt und erst dann über das Ziel umbenannt, wenn sie vollständig ist und nach einem INTERLIS-Transfer aussieht. Scheitert der Bezug, liefert die Quelle etwa eine Fehlerseite oder fehlt ein Eintrag im Archiv, bleibt der letzte Stand liegen, und das Log nennt Ziel und Quelle. Die übrigen Dateien werden trotzdem bezogen. Ein Lauf, der noch nicht fertig ist, wenn der nächste fällig wird, lässt diesen aus.

Damit veraltete Daten nicht unbemerkt bleiben, etwa weil eine Quelle umgezogen ist, meldet der Healthcheck des Images den Container als `unhealthy`, sobald der letzte Lauf ohne Fehler länger als `REFDATA_UPDATE_MAX_AGE_HOURS` zurückliegt. Beim Standard von 36 Stunden und einem nächtlichen Lauf ist das rund zwölf Stunden nach dem ersten gescheiterten Lauf der Fall. Sichtbar ist das in `docker compose ps` und in Portainer; das Log nennt die Quelle, die gescheitert ist. Nach dem Start bleibt der Container 30 Minuten im Zustand `starting`, damit der erste Lauf auch grosse Dateien beziehen kann.

Die Aktualisierung ist pro Datei atomar, nicht über alle Dateien zusammen: Eine Prüfung, die während eines Laufs startet, kann alte und neue Dateien mischen.

## Grenze: Cache des Validators

Bietet der ilitools-wrapper das Repository aus einem Verzeichnis an, gibt es diese Grenze nicht: ilivalidator liest die Dateien an Ort, was der Job ersetzt, gilt ab der nächsten Validierung.

Kommt das Repository dagegen über eine URL, hält ili2c Dateien daraus im Cache (Index 24 Stunden, Datensätze wie das Mapping 12 Stunden). Dateien in einem Unterordner, also die Referenzdaten unter `refdata/`, liest ili2c heute nie aus dem Cache ([claeis/ili2c#165](https://github.com/claeis/ili2c/issues/165)), darum prüft jeder Lauf gegen den neusten Stand. Eine neue Id in `ilidata.xml` oder im Mapping findet ilivalidator dagegen erst, wenn der Cache abgelaufen ist; ein Zurücksetzen des Caches bietet der Wrapper nicht an ([geowerkstatt/geopilot#1043](https://github.com/geowerkstatt/geopilot/issues/1043)).

## Versionen

Jeder Push auf `main` publiziert das Image als `edge` und als `v<VERSION>.<Run-Nummer>` (`VERSION` im Wurzelverzeichnis) und legt ein GitHub-Pre-Release an. Wird ein Pre-Release zum Release erklärt, erhält sein Image zusätzlich `latest` und `v<Major>`. Für den Betrieb einen festen Tag pinnen; was sich ändert, steht im [CHANGELOG](CHANGELOG.md).

## Entwicklung

Der Self-Check `test.sh` läuft beim Bauen der Test-Stage gegen einen lokalen Webserver und braucht kein Netz:

```bash
docker build --target test .
```

Er deckt Ersetzen, Archive mit mehreren Einträgen bei einem Download, fehlgeschlagene Bezüge, ungültige Inhalte und Quellen, abgewiesene Pfade, den Exit-Code und den Zeitstempel für den Healthcheck ab. Die CI baut dieselbe Stage bei jedem Push.
