# simpl-orchestration-local

A local evaluation stack for the Simpl-Open orchestration platform.  
Built for exploration and demonstration — **not for production use.**

---

## ⚠️ Purpose & Scope

This repository provides a **sandbox environment** to explore the Simpl-Open asset orchestration platform on a local machine. It is intended for:

- Evaluating the asset-orchestrator API and Dagster workflow engine
- Demonstrating data anonymisation pipeline capabilities
- Understanding how the orchestration components fit together

**This is not a production deployment.** Several components have been simplified or disabled for local use:

- **IAA / EU Login** — identity and access authentication is disabled; there is no credential validation or eIDAS integration
- **Vault** — HashiCorp Vault is present in the stack but unused; secrets are passed as plain environment variables
- **Kafka auth** — running in PLAINTEXT mode with no SASL authentication
- **TLS** — no TLS anywhere in the stack
- **Pipeline execution** — uses `DefaultRunLauncher` (subprocess) instead of `K8sRunLauncher` (Kubernetes jobs); behaviour differs from production
- **OTEL** — observability is disabled by default
- **field-level-pseudo-anonymisation** — has a dependency conflict in this build and is not registered in Dagster

For production deployment, follow the official documentation:

- **Asset Orchestrator** — [Installation Guide](https://code.europa.eu/simpl/simpl-open/development/orchestration-platform/asset-orchestrator/-/blob/main/README.md?ref_type=heads)
- **Dagster** — [Deployment Guide](https://code.europa.eu/simpl/simpl-open/development/orchestration-platform/dagster-dev-local/-/blob/main/README.md?ref_type=heads)

---

## Prerequisites

| Requirement | Minimum | Notes |
|---|---|---|
| Docker Desktop or OrbStack | Latest stable | Must be running before you start |
| `git` | Any recent version | For cloning repositories |
| RAM allocated to Docker | **16 GB** | 11 GB is not sufficient — the stack peaks at ~12–13 GB during build |
| Disk space | **20 GB free** | Images total ~8 GB; build cache adds more |
| CPU | 4 cores recommended | Build time scales with core count |

> The source repositories are publicly accessible — no GitLab account or Personal Access Token required.

### Setting Docker memory on Mac

By default Docker Desktop on Mac may be configured with insufficient memory:

1. Open **Docker Desktop**
2. Click the gear icon (Settings) → **Resources**
3. Set **Memory** to at least **16 GB**
4. Click **Apply & Restart**

On OrbStack, memory limits are managed automatically.

---

## Quick Start

```bash
# 1. Extract the deployment package into an empty folder
mkdir simpl-orchestration-local && cd simpl-orchestration-local
tar -xzf simpl-orchestration-local.tar.gz

# 2. Make the launcher executable (if needed)
chmod +x start.sh

# 3. Run
./start.sh

# 4. Optional: also run Bruno API smoke tests after startup
./start.sh --run-tests
```

The first run takes **10–15 minutes** — Docker needs to clone the repositories and build several images from source. Subsequent runs use the layer cache and start in under a minute.

---

## Service URLs

Once running:

| Service | URL | Notes |
|---|---|---|
| Asset Orchestrator API | http://localhost:8080/v1/swagger-ui.html | Swagger UI |
| Asset Orchestrator health | http://localhost:8080/v1/actuator/health | Should return `UP` |
| Dagster UI | http://localhost:3001 | Workflow engine |
| Kafka UI | http://localhost:9081 | Browse Kafka topics |
| Mailpit | http://localhost:8027 | Outgoing email capture |
| PostgreSQL (app) | localhost:5435 | DB: `asset_orchestrator` |
| PostgreSQL (Dagster) | localhost:5434 | DB: `dagster` |

---

## Seed Data

The database is seeded automatically on first startup with sample catalog assets, workflow definitions, and run history (SUCCESS, FAILURE, and RUNNING states).

To customise, edit the CSV files in `seed/csv/` before starting:

| File | Contents |
|---|---|
| `seed/csv/catalog_assets.csv` | Catalog assets (original_id, type, description, provider email) |
| `seed/csv/workflows.csv` | Workflow definitions (repository, job name, code location) |

To re-seed after editing:

```bash
docker compose run --rm seed
```

---

## Dagster Quickstart

Once the stack is running, open the Dagster UI at **http://localhost:3001**.

### What you will see

Click **Jobs** in the left sidebar to see all 6 registered jobs:

| Job | Type | Notes |
|---|---|---|
| `k_anonymity_job` | Local CSV | ✅ Works out of the box — uses sample data |
| `l_diversity_job` | Local CSV | ✅ Works out of the box — uses sample data |
| `t_closeness_job` | Local CSV | ✅ Works out of the box — uses sample data |
| `k_anonymity_job_s3` | S3 | Requires S3/MinIO configuration |
| `l_diversity_job_s3` | S3 | Requires S3/MinIO configuration |
| `t_closeness_job_s3` | S3 | Requires S3/MinIO configuration |

> **Note:** The **Overview** page may appear empty — this is normal. Navigate directly to **Jobs** in the left sidebar.

### Pipeline input

The local jobs read from `/data/sample_input.csv` inside the container. This file is pre-loaded with 20 synthetic records:

| Column | Description |
|---|---|
| `Name` | Identifier — will be suppressed during anonymisation |
| `Age` | Quasi-identifier — generalised using `simpl_age` hierarchy |
| `Zipcode` | Non-sensitive attribute |
| `Gender` | Quasi-identifier — generalised using `simpl_gender` hierarchy |
| `Disease` | Sensitive attribute — protected by anonymisation |

### Pipeline output

After a successful run, the anonymised dataset is written to `/data/output_k_anonymity.csv` inside the container. Retrieve it with:

```bash
docker exec simpl-dagster-anonymisation cat /data/output_k_anonymity.csv
```

The output contains the same columns with:
- `Name` suppressed (removed or masked)
- `Age` and `Gender` generalised into ranges/groups (e.g. `[25-30]`, `*`)
- Records that cannot satisfy the privacy constraint suppressed entirely

The **Metadata** tab of each step in the run view shows an anonymisation report with privacy metrics:

| Metric | Description |
|---|---|
| k-anonymity | Minimum records sharing the same quasi-identifier values |
| l-diversity | Diversity of sensitive attributes within each equivalence class |
| t-closeness | Distance between attribute distributions |
| Suppression rate | Fraction of records removed to meet the privacy constraint |

### Running a job — step by step

1. Click **Jobs** in the left sidebar
2. Click **`k_anonymity_job`**
3. Click **Launchpad** (top right)
4. Replace the entire config editor content with:

```yaml
ops:
  read_csv_to_df:
    config:
      input_path: /data/sample_input.csv
  apply_k_anonymity:
    config:
      ident:
        - Name
      quasi_identifiers:
        - Age
        - Gender
      sensitive_attributes:
        - Disease
      k: 3
      supp_level: 50.0
      generalisation_hierarchies:
        Age: simpl_age
        Gender: simpl_gender
  write_df_to_csv:
    config:
      output_path: /data/output_k_anonymity.csv
```

5. Verify **"Config is valid"** is shown, then click **Launch Run**
6. Click the run to follow step-by-step progress and logs

### Modifying the sample data

The sample CSV is baked into the container image at build time. To use your own data:

**Option A — Replace before building:**  
Edit `dagster-patches/sample_data.csv` before running `./start.sh`. The file must have the same columns (`Name`, `Age`, `Zipcode`, `Gender`, `Disease`) or update the Launchpad config to match your columns.

**Option B — Copy into a running container:**
```bash
docker cp /path/to/your/data.csv simpl-dagster-anonymisation:/data/sample_input.csv
```
Then launch the job. No restart needed.

### Using S3 instead

The S3 variants (`k_anonymity_job_s3` etc.) are also registered. Add a MinIO container to the stack:

```bash
docker run -d --name minio \
  --network <yourfolder>_dagster_network \
  -p 9000:9000 -p 9001:9001 \
  -e MINIO_ROOT_USER=minioadmin \
  -e MINIO_ROOT_PASSWORD=minioadmin \
  quay.io/minio/minio server /data --console-address ":9001"
```

Upload a CSV via http://localhost:9001, then reference it in the `_s3` job Launchpad config.

---

## Bruno API Smoke Tests

[Bruno](https://www.usebruno.com/) is an open-source API client (comparable to Postman) that stores test collections as plain `.bru` files directly in the repository — git-friendly and CI-compatible.

### Running the tests

Tests run automatically when using the `--run-tests` flag:

```bash
./start.sh --run-tests
```

Results stream live to your terminal. After completion, a summary table is shown:

```
📊 Execution Summary
┌───────────────┬────────────────────────┐
│ Metric        │         Result         │
├───────────────┼────────────────────────┤
│ Status        │         ✓ PASS         │
├───────────────┼────────────────────────┤
│ Requests      │ 6 (6 Passed, 0 Failed) │
...
```

To run tests against an already-running stack:

```bash
docker compose --profile tests up bruno-smoke-test
docker compose logs bruno-smoke-test
```

### What the tests cover

| # | Test | What it validates |
|---|---|---|
| 01 | Health Check | App is UP, actuator returns status 200 |
| 02 | Workflow Definitions | Seeded asset has definitions, correct asset ID, required fields, at least one active |
| 03 | Dagster Integration | Dagster reachable, code locations registered, anonymisation location present by name |
| 04 | Create Catalog Asset | POST creates a new asset record, returns 201 |
| 05 | Verify Seed Data | Clinical trials asset has definitions, association titles, YAML config, at least one active |
| 06 | Dagster Integration Health | Full health check confirms status UP |

### Using Bruno desktop

To browse and run tests interactively:

1. Download [Bruno](https://www.usebruno.com/downloads)
2. Open Bruno → **Open Collection** → select the `bruno/` folder
3. Select the `local` environment (top right)
4. Click **Run Collection** or run individual requests

The `local` environment points to `http://localhost:8080/v1` — works when the stack is running on your Mac.

---

## Stopping

```bash
# Stop containers, keep data volumes
docker compose down

# Stop and wipe all data (clean slate for next run)
docker compose down -v
```

---

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│  dagster_network (Docker bridge)                            │
│                                                             │
│  ┌──────────────────┐   GraphQL    ┌─────────────────────┐  │
│  │ asset-orchestrator│ ──────────► │ dagster-webserver   │  │
│  │ :8080             │             │ :3001               │  │
│  └────────┬──────────┘             └──────────┬──────────┘  │
│           │                                   │  gRPC       │
│           ▼                                   ▼             │
│  ┌────────────────┐              ┌────────────────────────┐  │
│  │ postgres       │              │ dagster-anonymisation  │  │
│  │ :5435          │              │ :4000                  │  │
│  └────────────────┘              └────────────────────────┘  │
│                                                             │
│  ┌────────────────┐                                         │
│  │ dagster-postgres│                                        │
│  │ :5434          │                                         │
│  └────────────────┘                                         │
│                                                             │
│  kafka:9093   kafka-ui:9081   mailpit:1026/8027            │
│  otel-collector:4320/4321                                   │
└─────────────────────────────────────────────────────────────┘
```

**Key design decisions:**
- Dagster runs as Docker containers with `DefaultRunLauncher` — no Kubernetes required
- Pipeline code locations connect via gRPC on the internal Docker network
- `workspace.yaml` is bind-mounted and reloaded on webserver restart
- Seed data is loaded after the app healthcheck passes, guaranteeing Flyway migrations have completed
- `dagster.yaml` configures compute logs and artifact storage to `/data` inside the code location container, avoiding permission issues with the default `/opt/dagster` path

---

## Troubleshooting

### Out of memory during build
```
Killed
ERROR: failed to solve: process "/bin/sh -c pip install..." did not complete successfully
```
Or a container exits unexpectedly with code 137.

**Cause:** Docker does not have enough memory allocated. The build peaks at 12–13 GB.  
**Fix:** Open Docker Desktop → Settings → Resources → increase Memory to at least **16 GB** → Apply & Restart. Then run `docker compose down -v` and `./start.sh` again.

If you cannot allocate 16 GB, comment out the `dagster-pseudo-anonymisation` service in `docker-compose.yml` — it is the largest image (~3.5 GB) and not required for the primary evaluation.

---

### Docker credential error during build
```
error getting credentials - err: exec: "docker-credential-desktop": executable file not found in $PATH
```
**Cause:** Docker's credential helper is configured but not available on PATH. Common on Mac after a Docker Desktop install.  
**Fix:**
```bash
sed -i '' 's/"credsStore"[^,]*,\?//g' ~/.docker/config.json
```
Or open `~/.docker/config.json`, delete the line containing `"credsStore"`, save, and retry. Alternatively restart Docker Desktop from the menu bar.

---

### Clone failed
```
fatal: repository 'https://code.europa.eu/...' not found
```
**Cause:** Network issue or repository URL has changed.  
**Fix:** Check your internet connection. Try cloning manually: `git clone https://code.europa.eu/simpl/simpl-open/development/orchestration-platform/asset-orchestrator.git`

---

### Port already in use
```
Bind for 0.0.0.0:8080 failed: port is already allocated
```
**Cause:** Another process is using that port.  
**Fix:** Find what's using it: `lsof -i :8080`. Stop that process, or change the left-hand port number in `docker-compose.yml` (e.g. `"8081:8080"`).

---

### Asset orchestrator exits on startup
```
BrokerNotAvailableException
```
**Cause:** Kafka isn't ready yet. The app has `fatal-if-broker-not-available: true`.  
**Fix:** Wait 30 seconds and restart: `docker compose restart asset-orchestrator`

---

### `/v1/workflows` returns 502
```json
{"type": "urn:problem-type:simpl:externalServiceError", "status": 502}
```
**Cause:** Dagster webserver not yet healthy.  
**Fix:** Wait for `simpl-dagster-webserver` to show as healthy: `docker compose ps`. Usually resolves within 60 seconds of startup.

---

### Dagster shows no code locations
**Cause:** The workspace.yaml inside the container has the old baked-in version.  
**Fix:** `start.sh` handles this automatically via a webserver restart. If it persists:
```bash
docker compose restart docker_dagster_webserver
```

---

### Seed data not appearing in API
**Cause:** Seed container ran before the app was fully ready.  
**Fix:**
```bash
docker compose run --rm seed
```

---

### Build fails on pom.xml version error
```
'version' must be a constant version but is '${env.PROJECT_RELEASE_VERSION:unknown}'
```
**Cause:** `.env.local` is missing or `PROJECT_RELEASE_VERSION` is not set.  
**Fix:** Confirm `.env.local` exists in the same folder as `docker-compose.yml` and contains `PROJECT_RELEASE_VERSION=local`.

---

### Dagster job fails with permission error on `/opt/dagster`
```
PermissionError: [Errno 13] Permission denied: '/opt/dagster'
```
**Cause:** The code location container doesn't have write access to the default Dagster home path.  
**Fix:** This is configured correctly in the current build via `DAGSTER_HOME=/data/dagster_home`. If you see this on an older build, do a clean rebuild:
```bash
docker compose down -v
docker compose build --no-cache dagster-anonymisation
./start.sh
```
