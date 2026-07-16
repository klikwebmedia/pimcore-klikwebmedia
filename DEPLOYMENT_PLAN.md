# Pimcore CE deployment plan — Dokploy + pimcore.klikwebmedia.com

Doel: Pimcore Community Edition (demo-variant, met voorbeelddata) volledig automatisch
uitrollen op een bestaande Dokploy-instantie, bereikbaar via `https://pimcore.klikwebmedia.com`,
zodanig dat een LLM-agent dit end-to-end kan uitvoeren met alleen:
- een Dokploy API key (`x-api-key`)
- GitHub-toegang (repo aanmaken + Actions secrets zetten)
- DNS-toegang voor `klikwebmedia.com` (of een mens die één A-record zet)

Gekozen richting (o.b.v. eerdere keuzes):
- **Pimcore demo package** (`pimcore/demo`) — inclusief voorbeelddata.
- **GitHub Actions bouwt het image → ghcr.io**, Dokploy trekt alleen een kant-en-klaar image
  binnen. Geen Dokploy↔GitHub OAuth-koppeling nodig → 100% API-automatiseerbaar.
- **Geen OpenSearch** in de stack (lichter, kan later toegevoegd worden).

---

## 1. Architectuur

```mermaid
flowchart LR
    subgraph GitHub
        R[repo: pimcore-klikwebmedia] -->|push main| A[GitHub Actions]
        A -->|build & push| G[ghcr.io image]
        A -->|POST compose.deploy| D
    end
    subgraph "Dokploy host"
        D[Dokploy API] --> C[compose: pimcore]
        C --> NG[nginx]
        C --> PHP[php-fpm + supervisor\n(bevat Pimcore code)]
        C --> DB[(MariaDB)]
        C --> RD[(Redis)]
        NG -->|:9000| PHP
        PHP --> DB
        PHP --> RD
    end
    U[pimcore.klikwebmedia.com] -->|Traefik + Let's Encrypt| NG
```

Waarom dit ontwerp:
- Het officiële `pimcore/pimcore` image bevat **alleen PHP (fpm/cli)**, geen nginx — dus nginx
  staat als apart service in de compose (bevestigd via de pimcore/docker README).
- Applicatiecode + vendor/ worden **in het image gebakken** door GitHub Actions (multi-stage
  build met Composer), niet via een bind-mount of git-clone-at-runtime. Dat maakt de Dokploy-kant
  triviaal: alleen een `image:` referentie, geen build-context nodig op de server.
- Persistente data (db, uploads, gegenereerde thumbnails, cache) staat in **named volumes**, los
  van het image, zodat elke herdeploy de data niet aanraakt.

---

## 2. Wat ik (of de uitvoerende LLM) nog nodig heb

| Item | Waarvoor | Opmerking |
|---|---|---|
| Dokploy base URL + API key | Alle Dokploy API-calls (`x-api-key` header) | Jij hebt deze al |
| `serverId` van de Dokploy-server waar dit op moet draaien | `compose.create` | Op te vragen via `GET /server.all` |
| GitHub account/organisatie | Repo aanmaken, Actions secrets, ghcr.io package | Genoemd als beschikbaar |
| DNS-toegang voor `klikwebmedia.com` | A-record `pimcore` → publiek IP van de Dokploy-server | Enige stap die (tenzij de DNS-provider ook een API biedt) mogelijk handmatig blijft |
| Resource-check op de server | Draait er al genoeg vrij (v)CPU/RAM naast andere Dokploy-apps? | Aanbevolen minimum voor deze stack: **2 vCPU / 4GB RAM** vrij |

Zonder de bovenste twee (API key + serverId) kan geen enkele Dokploy-call gedaan worden — dat zijn
de harde blockers om van plan naar uitvoering te gaan.

---

## 3. Stappenplan (uitvoeringsvolgorde)

### Stap 1 — GitHub repository voorbereiden
1. Nieuwe repo aanmaken, bv. `klikwebmedia/pimcore-klikwebmedia` (privé of publiek — publiek is
   simpeler omdat Dokploy dan geen registry-credentials nodig heeft om het ghcr.io-image te pullen).
2. Project genereren:
   `COMPOSER_MEMORY_LIMIT=-1 composer create-project --no-scripts pimcore/demo .`
3. De meegeleverde bestanden uit dit plan toevoegen: `docker/Dockerfile`,
   `docker/docker-entrypoint.sh`, `docker-compose.yml`, `.github/workflows/build-and-deploy.yml`.
4. Committen en pushen naar `main`.

### Stap 2 — Eerste image build
GitHub Actions (zie workflow hieronder) bouwt bij elke push naar `main` automatisch een image en
pusht het naar `ghcr.io/<org>/pimcore-klikwebmedia:latest`. Voor de allereerste keer: gewoon de
initiële push doen, of de workflow handmatig triggeren (`workflow_dispatch`).

### Stap 3 — Dokploy: project + omgeving + compose aanmaken (API)
```bash
DOKPLOY_URL="https://<jouw-dokploy-host>"
API_KEY="<...>"

# 1. Project
curl -sX POST "$DOKPLOY_URL/api/project.create" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"pimcore-klikwebmedia","description":"Pimcore CE demo"}'
# -> projectId

# 2. Environment
curl -sX POST "$DOKPLOY_URL/api/environment.create" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"name":"production","projectId":"<projectId>"}'
# -> environmentId

# 3. Compose aanmaken met de docker-compose.yml inhoud als string
curl -sX POST "$DOKPLOY_URL/api/compose.create" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d @compose-create-payload.json
# -> composeId
```
`compose-create-payload.json` bevat `{"name":"pimcore","environmentId":"<...>","composeFile":"<inhoud van docker-compose.yml>","serverId":"<serverId>"}`.

### Stap 4 — Environment variables zetten
```bash
curl -sX POST "$DOKPLOY_URL/api/compose.update" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d '{
    "composeId":"<composeId>",
    "env":"MYSQL_ROOT_PASSWORD=<genereer>\nMYSQL_PASSWORD=<genereer>\nMYSQL_DATABASE=pimcore\nMYSQL_USER=pimcore\nAPP_SECRET=<genereer>\nPIMCORE_ADMIN_USER=admin\nPIMCORE_ADMIN_PASSWORD=<genereer>\nIMAGE_TAG=ghcr.io/<org>/pimcore-klikwebmedia:latest"
  }'
```
Genereer wachtwoorden/secrets willekeurig (bv. `openssl rand -hex 24`) — nooit hardcoden in git.

### Stap 5 — Eerste deploy
```bash
curl -sX POST "$DOKPLOY_URL/api/compose.deploy" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d '{"composeId":"<composeId>"}'
```
De `docker-entrypoint.sh` in het php-image detecteert bij eerste start dat Pimcore nog niet
geïnstalleerd is en voert automatisch `assets:install`, `pimcore-install` en `cache:clear` uit
(idempotent — bij herdeploys gebeurt dit niet opnieuw).

### Stap 6 — Domein + HTTPS koppelen
```bash
curl -sX POST "$DOKPLOY_URL/api/domain.create" \
  -H "x-api-key: $API_KEY" -H "Content-Type: application/json" \
  -d '{
    "host":"pimcore.klikwebmedia.com",
    "composeId":"<composeId>",
    "serviceName":"nginx",
    "port":80,
    "https":true,
    "certificateType":"letsencrypt"
  }'
```

### Stap 7 — DNS
Bij de DNS-provider van `klikwebmedia.com` een **A-record** toevoegen:
`pimcore.klikwebmedia.com → <publiek IP van de Dokploy-server>`.
Let's Encrypt (HTTP-01 via Traefik) kan het certificaat pas uitgeven zodra dit DNS-record actief is.

### Stap 8 — Doorlopende deploys (CI/CD)
De GitHub Actions workflow roept na een succesvolle image-push automatisch
`POST /api/compose.deploy` aan (met `composeId` als repo-secret) — elke push naar `main` update
dus vanzelf de live omgeving. Geen polling, geen Dokploy-GitHub-koppeling nodig.

### Stap 9 — Validatie
- `https://pimcore.klikwebmedia.com` → publieke demo-frontend
- `https://pimcore.klikwebmedia.com/admin` → Pimcore backend, inloggen met
  `PIMCORE_ADMIN_USER` / `PIMCORE_ADMIN_PASSWORD`
- Certificaat geldig (Let's Encrypt), geen mixed content
- Logs controleren via Dokploy UI/API (`compose` deployment logs) op installatie-fouten

---

## 4. Secrets-overzicht (waar leeft wat)

| Secret | Plek | Nooit in git |
|---|---|---|
| `DOKPLOY_API_KEY` | GitHub Actions repo secret | ✅ |
| `DOKPLOY_URL`, `DOKPLOY_COMPOSE_ID` | GitHub Actions repo secret/variable | — |
| DB-wachtwoorden, `APP_SECRET`, admin-wachtwoord | Dokploy compose environment variables (via `compose.update`) | ✅ |
| ghcr.io image | Publiek package (aanbevolen) zodat Dokploy zonder registry-credentials kan pullen | — |

---

## 5. Resource-inschatting

Zonder OpenSearch/RabbitMQ/Mercure: nginx + php + mariadb + redis draait comfortabel op
**2 vCPU / 4GB RAM**. Mocht de Dokploy-server dit naast andere apps moet delen, hou rekening met
MariaDB (~512MB–1GB) en de php-fpm workers (~256–512MB per worker, aantal workers tunen via
`PM_MAX_CHILDREN`).

---

## 6. Bekende aannames om te verifiëren vóór eerste build

- Exacte PHP-tag van `pimcore/pimcore` die matcht met `pimcore/demo`'s `composer.json`
  PHP-requirement (bv. `php8.3-supervisord-latest`) — controleren na `composer create-project`.
- Het exacte entrypoint-pad van de officiële image (voor de `exec`-regel onderaan
  `docker-entrypoint.sh`) — te verifiëren met
  `docker run --rm --entrypoint sh pimcore/pimcore:<tag> -c 'cat /usr/local/bin/*entrypoint* 2>/dev/null || true'`
  vóórdat de Dockerfile production-ready is.
- Of `pimcore/demo` een messenger-transport nodig heeft die RabbitMQ vereist (anders volstaat de
  Doctrine/database-transport, wat de stack simpel houdt zonder RabbitMQ).

---

## 7. Volgende stap

Zodra jij akkoord geeft: geef de Dokploy API key + base URL en de `serverId` door (of laat me eerst
`GET /server.all` uitvoeren als je me tijdelijk toegang geeft), dan voer ik stap 1 t/m 9 hierboven
automatisch uit en rapporteer ik na elke stap het resultaat, vóór ik doorga naar de volgende
onomkeerbare actie (DNS, eerste publieke deploy).
