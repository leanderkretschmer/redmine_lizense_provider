# redmine_lizense_provider — Redmine-Plugin „Lizenzen“ für multiRDP

Verwaltet Lizenzen für den multiRDP-Client (macOS/Windows): Administratoren legen
Lizenzen an, füllen die Vorgabe (Server und RemoteApps) und teilen sie Benutzern zu.
Der Client meldet sich an Redmine an, wartet auf die Gerätefreigabe durch den Benutzer,
holt Vorgabe, Einstellungen und WireGuard-Konfiguration und schreibt eigene
Einstellungen zurück.

Sprache: Deutsch (Code-Kommentare, Oberfläche), englische Übersetzung in `en.yml`.

---

## Umgebung, gegen die gebaut wurde (Abschnitt 3 der Vorgabe)

| Punkt | Befund |
|---|---|
| Redmine | **6.1.2** (stable), Ruby 3.4.9, Rails **7.2.2.1**, MariaDB (mysql2) |
| `ActiveRecord::Encryption` | vorhanden, aber von Redmine **nicht konfiguriert** (keine Rails-Credentials). Das Plugin konfiguriert es selbst, siehe „Verschlüsselungsschlüssel“. |
| Einhängepunkte | `view_layouts_base_body_bottom` ✔ und `view_my_account_contextual` ✔ existieren in `app/views/layouts/base.html.erb` bzw. `app/views/my/account.html.erb`. **`view_layouts_base_sidebar` gibt es nicht** — der Link „Lizenzen“ sitzt deshalb oben rechts in „Mein Konto“ (contextual). |
| HTTPS | Redmine läuft hinter Caddy (`pm.dev.cratchmere.net`), TLS wird dort terminiert; Caddy setzt `X-Forwarded-Proto`, Rails erkennt das über `request.ssl?`. Aufrufe über HTTP werden mit `403 {"error":"https_erforderlich"}` abgewiesen, nicht umgeleitet. |

---

## Einbau

Das Plugin muss im Verzeichnis **`plugins/redmine_lizense_provider`** liegen (Kennung =
Repo-Name); Redmine leitet die Plugin-Kennung aus dem Verzeichnisnamen ab, ein anderer
Name führt zu `PluginNotFound`. Frühere Fassungen hießen `multirdp_licenses`; `init.rb`
benennt deren Migrationseinträge in `schema_migrations` beim ersten Start automatisch um.

```bash
cd /usr/src/redmine
git clone https://github.com/leanderkretschmer/redmine_lizense_provider plugins/redmine_lizense_provider
bundle exec rake redmine:plugins:migrate RAILS_ENV=production
# Verschlüsselungsschlüssel anlegen (siehe unten), dann Redmine neu starten
```

Im Containerfile der Dev-Instanz entspricht das den anderen Plugin-Zeilen:

```dockerfile
RUN git clone -b main https://github.com/leanderkretschmer/redmine_lizense_provider plugins/redmine_lizense_provider/ && cd plugins/redmine_lizense_provider && git checkout <commit>
```

Zusätzliche Gems werden nicht benötigt.

## Rücknahme

```bash
bundle exec rake redmine:plugins:migrate NAME=redmine_lizense_provider VERSION=0 RAILS_ENV=production
rm -rf plugins/redmine_lizense_provider
```

Die vier Tabellen (`multirdp_licenses`, `multirdp_grants`, `multirdp_devices`,
`multirdp_events`) werden dabei entfernt; alle Migrationen sind umkehrbar.

---

## Verschlüsselungsschlüssel

WireGuard-Konfigurationen (`multirdp_grants.secrets`) werden mit
`ActiveRecord::Encryption` (AES-256-GCM) verschlüsselt abgelegt. Ein Datenbankabzug
allein reicht nicht, um sie zu lesen.

Der Schlüssel wird in dieser Reihenfolge gesucht:

1. Umgebungsvariable **`MULTIRDP_KEY`** (für Docker die einfachste Form, z. B. über
   `.env` und `environment:` in `compose.yaml`).
2. Datei **`config/multirdp_key`** im Redmine-Wurzelverzeichnis (nur der Schlüssel,
   eine Zeile). Liegt **nicht im Repo**; im Container muss sie als Volume gemountet
   werden, sonst geht sie beim Neubau verloren.
3. In der Testumgebung ein fester Testschlüssel.

Mindestlänge 32 Zeichen; erzeugen z. B. mit `openssl rand -hex 32`.

Hat die Redmine-Instanz `ActiveRecord::Encryption` bereits selbst konfiguriert
(Rails-Credentials), wird diese Konfiguration unverändert benutzt.

**Ohne Schlüssel** läuft das Plugin, zeigt in der Verwaltung eine Warnung, und das
Hinterlegen einer VPN-Konfiguration wird abgewiesen. **Ein Schlüsselwechsel macht alle
hinterlegten Konfigurationen unlesbar** — vorher Konfigurationen neu hinterlegen oder
den Schlüssel sichern. Er gehört in dieselbe Sicherung wie die Datenbank, aber nicht in
dieselbe Datei.

---

## Aufbau (Entscheidungen, Abschnitt 15)

```
init.rb                          Registrierung, Admin-Menü, Hooks, Verschlüsselung
config/routes.rb                 alle Routen (siehe unten)
config/locales/{de,en}.yml       alle Texte
db/migrate/001…004               vier Tabellen
lib/multirdp_licenses.rb         Konstanten (Fristen, Grenzen)
lib/multirdp_licenses/
  encryption.rb                  Schlüssel laden, ActiveRecord::Encryption konfigurieren
  data_schema.rb                 Normalisierung/Prüfung von data und settings
  icon_validator.rb              PNG-Prüfung (quadratisch, ≤1024 px, ≤256 KiB)
  rate_limiter.rb                Anmeldeversuche je IP (über multirdp_events)
  hooks.rb                       View-Hooks
app/models/multirdp_{license,grant,device,event}.rb
app/controllers/
  multirdp_api_controller.rb           /multirdp/api/v1/*   (Client)
  multirdp_my_licenses_controller.rb   /my/licenses         (Benutzer)
  multirdp_licenses_controller.rb      /admin/multirdp/licenses  (Admin)
  multirdp_grants_controller.rb        /admin/multirdp/grants    (Admin)
app/mailers/multirdp_mailer.rb   Freigabe-Mail über Redmines Mailer
app/views/…                      Formulare, Listen, Hook-Partials, Mail
assets/                          CSS für das Freigabefenster, JS für das Vorgabe-Formular
test/                            Unit-, Funktions- und Integrationstests
```

### Routen

| Zweck | Route |
|---|---|
| Client-Schnittstelle | `POST/DELETE /multirdp/api/v1/session`, `GET /multirdp/api/v1/license`, `PUT /multirdp/api/v1/settings`, `GET /multirdp/api/v1/secrets/:server_id`; `PUT/PATCH/POST/DELETE /multirdp/api/v1/data` → immer 403 |
| Mein Konto | `GET /my/licenses`; `POST /my/licenses/devices/:id/{approve,deny,revoke}` |
| Verwaltung | `resources /admin/multirdp/licenses` (+ `GET …/:id/data` = JSON-Ansicht), `POST /admin/multirdp/licenses/:license_id/grants` (mehrere Benutzer), `GET/PATCH/DELETE /admin/multirdp/grants/:id`, `POST …/grants/:id/secrets`, `DELETE …/grants/:id/secrets/:server_id`, `POST /admin/multirdp/devices/:id/revoke` |

Alle Verwaltungs- und Benutzer-Routen laufen über Redmines Sitzung mit CSRF-Schutz;
Freigeben/Ablehnen/Sperren sind ausschließlich `POST`. Die Schnittstelle ist von
Redmines Sitzungs- und CSRF-Filtern ausgenommen und authentifiziert nur über das
Gerätetoken (`Authorization: Bearer …`). Das Token ist **kein** Redmine-API-Schlüssel
und wird von keinem anderen Redmine-Endpunkt akzeptiert.

### Formular für `data`

Ein Formular mit Zeilen je Server und je RemoteApp (`assets/javascripts/multirdp_licenses.js`
klont Vorlagen aus `<template>`-Elementen, vergibt UUIDs im Browser; der Server vergibt
fehlende UUIDs nach). Das Symbol wird als PNG hochgeladen und als Base64 in `data`
abgelegt; beim Bearbeiten bleibt ein vorhandenes Symbol erhalten, sofern nicht „Symbol
entfernen“ angehakt oder eine neue Datei gewählt wird. `knownApplicationIds` wird
kommagetrennt gepflegt. Das erzeugte JSON ist über „Erzeugtes JSON ansehen“ zu sehen.

### Datenmodell — Abweichungen/Ergänzungen zur Vorgabe

- `multirdp_licenses.grace_days` (Abschnitt 10), Voreinstellung 14.
- `multirdp_devices.public_key` (Vorbereitung Weg B, Abschnitt 8): wird bei
  `POST /session` optional als `device.public_key` angenommen und in der Verwaltung je
  Gerät angezeigt. **Das ist ein Vorschlag zur Erweiterung der Schnittstelle**; der
  Client muss ihn nicht senden.
- `multirdp_events.user_id` ist nullbar (fehlgeschlagene Anmeldungen haben keinen Benutzer).
- `settings_revision` beginnt bei **0** („noch nie geschrieben“); `revision` bei 1.
- Ein Benutzer kann **höchstens eine wirksame multiRDP-Zuteilung** gleichzeitig haben
  (Modellprüfung), weil `GET /license` genau eine Lizenz liefert. Eine zweite Zuteilung
  ist möglich, sobald die erste ausgesetzt, entzogen oder abgelaufen ist.
- Text-Spalten `data`, `settings`, `secrets`, `detail` sind `MEDIUMTEXT` (16 MB), weil
  Symbole als Base64 in `data` liegen.

### Zustände

| Zuteilung (`status` + Ableitung) | Client bekommt |
|---|---|
| `active`, nicht abgelaufen | 200 |
| `active`, `valid_until` in der Vergangenheit | `403 {"error":"abgelaufen"}` |
| `revoked` | `403 {"error":"entzogen"}` |
| `suspended` | `403 {"error":"entzogen"}` — **siehe offene Fragen** |

| Gerät | Client bekommt |
|---|---|
| `pending`, jünger als 15 Minuten | `202 {"status":"pending"}` |
| `pending`, älter als 15 Minuten | wird auf `denied` gesetzt, `403 {"error":"geraet_gesperrt"}` |
| `denied`, `revoked` | `403 {"error":"geraet_gesperrt"}` |
| `approved` | 200 |

Weitere Fehlerkennungen der Schnittstelle (alle JSON `{"error": …}`):
`https_erforderlich` (403), `anmeldung_fehlgeschlagen` (401), `keine_lizenz` (403),
`zu_viele_versuche` (429, mehr als 10 Anmeldeversuche je IP und Stunde),
`zu_viele_anfragen` (429, mehr als 5 offene Freigabeanfragen je Benutzer),
`token_ungueltig` (401), `revision_konflikt` (409, mit aktuellem Stand im Rumpf),
`data_schreibgeschuetzt` (403), `ungueltige_einstellungen` (422, mit `detail`),
`kein_geheimnis` (404), `ungueltige_anfrage` (400/422), `nicht_gefunden` (404).

### `GET /license`

Antwort wie in Abschnitt 6, zusätzlich `grace_days`. `ETag`/`If-None-Match` wird
unterstützt (schwacher ETag aus Lizenz-ID, `revision`, `settings_revision`, Änderungszeit
der Zuteilung und Geräte-ID); `last_seen_at`/`last_seen_ip` werden bei jedem Aufruf
gesetzt, auch bei 304.

### `PUT /settings`

Es werden nur die drei Bereiche `transfer`, `workspace`, `ownApps` angenommen;
unbekannte Bereiche auf oberster Ebene führen zu 422 statt stillschweigendem Verwerfen.
Innerhalb der Bereiche werden die bekannten Felder auf ihren Typ geprüft, unbekannte
Felder werden durchgereicht (vorwärtskompatibel). Symbole in `ownApps` unterliegen
denselben Regeln wie in `data`. Nutzlast höchstens 4 MB. Der Schreibvorgang läuft unter
Zeilensperre, damit zwei Geräte nicht gleichzeitig dieselbe Fassung überschreiben.

### Anmeldebegrenzung

Zählt Einträge `login_attempt` in `multirdp_events` je IP (erfolgreich oder nicht) und
weist ab 10 Versuchen je Stunde mit 429 ab. Bewusst über die Datenbank statt über den
Cache, damit die Grenze bei mehreren Anwendungsprozessen und ohne gemeinsamen Cache-Store
gilt. Hinter dem Reverse-Proxy ist `request.remote_ip` die Client-IP aus
`X-Forwarded-For`.

### Zwei-Faktor-Anmeldung

`POST /session` prüft nur Benutzername und Kennwort (`User.try_to_login`, damit LDAP
mitspielt). Ein zweiter Faktor von Redmine wird dort **nicht** abgefragt; die
Gerätefreigabe in der Redmine-Oberfläche (die bei aktivem 2FA nur nach vollständiger
Anmeldung erreichbar ist) übernimmt diese Rolle.

### Protokoll

`multirdp_events` ist nur anhängbar (`readonly?` nach dem Anlegen). Protokolliert werden:
Lizenz angelegt/geändert/gelöscht, Zuteilung erteilt/geändert/entzogen/gelöscht, Gerät
angefragt/freigegeben/abgelehnt/abgelaufen/gesperrt, Einstellungen geschrieben,
VPN-Konfiguration hinterlegt/gelöscht/**abgerufen** (mit Gerät, Zeit, IP, Server-ID),
Anmeldeversuch, Abmeldung. Kein Eintrag enthält Kennwörter, Token oder
Konfigurationsinhalte; `password`, `token`, `secrets`, `wireguard_config` sind zusätzlich
in `filter_parameters` eingetragen.

### Mail

Bei jeder Geräteanfrage geht eine Mail an den Benutzer (Redmines `Mailer`, `deliver_later`).
Ein fehlgeschlagener Versand bricht die Anmeldung nicht ab.

---

## Was nicht synchronisiert wird (Abschnitt 9)

RDP-Kennwörter, Pfade freigegebener Ordner, installierte Verknüpfungen und gelernte
Fenster-Zuordnungen — absichtlich nicht, siehe Vorgabe. Nicht stillschweigend nachbauen.

---

## Tests

```bash
bundle exec rake redmine:plugins:test NAME=redmine_lizense_provider RAILS_ENV=test
```

65 Tests / 296 Zusicherungen: Einheitentests (Modelle, Symbolprüfung, Verschlüsselung
im Datenbankabzug), Funktionstests (Verwaltung, „Mein Konto“, Rechte, keine
Massenzuweisung) und ein Integrationstest, der die Abnahmeschritte 2–10 über die
Schnittstelle durchspielt (HTTPS-Zwang, Freigabefenster im Layout, ETag/304, 409-Konflikt,
403-Gründe, 429-Grenze, kein Klartext im Abzug, Token gilt nicht als Redmine-API-Schlüssel).

Der Test-Helper setzt `ActionMailer::Base.delivery_method = :test`, weil die
Instanz einen SMTP-Versand für alle Umgebungen vorgeben kann.

Hinweise zur Dev-Instanz (Docker-Image): Die Testgruppe der Gems ist im Image nicht
installiert (`bundle config without development:test`), und `redmine_issue_repeat` fragt
beim Laden eine Tabelle ab, sodass `db:migrate` auf einer leeren Testdatenbank scheitert.
Für den Testlauf wurde die Tabellenstruktur der Dev-Datenbank nach `redmine_test`
kopiert und die Testgruppe im Container nachinstalliert.

---

## Offene Fragen an den Auftraggeber (Abschnitt 15)

1. **`suspended` → Grund für den Client.** Die Schnittstelle kennt nur `entzogen`,
   `abgelaufen`, `geraet_gesperrt`. Eine ausgesetzte Zuteilung wird derzeit als
   `entzogen` gemeldet. Vorschlag: vierten Grund `ausgesetzt` in die Schnittstelle
   aufnehmen (beide Seiten).
2. **Weg B (Schlüsselpaar je Gerät):** vorbereitet (`public_key` je Gerät, Anzeige beim
   Administrator, optionales Feld `device.public_key` in `POST /session`). Der Umstieg
   ohne Schema-Änderung ist möglich; ob und wann, ist zu entscheiden.
3. **RDP-Kennwörter** werden nicht synchronisiert (Abschnitt 9). Falls doch gewünscht:
   eigene Entscheidung mit eigener Prüfung.
4. **`mac/RRConfig.h`** war in dieser Umgebung nicht vorhanden; die Felder wurden
   eins zu eins aus Abschnitt 5 der Vorgabe übernommen. Abweichungen im Modell der App
   bitte melden, nicht raten.
5. **Mitbestimmung:** zentrale Speicherung von Mitarbeitereinstellungen und
   Zugriffsprotokolle — vor der Einführung klären.
