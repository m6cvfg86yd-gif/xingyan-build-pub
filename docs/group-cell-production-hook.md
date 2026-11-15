# Group Cell production shadow hook

The first production hook is read-only with respect to legacy message delivery.
Every successful legacy group write is mirrored asynchronously to one remotely
deployed group Cell. The legacy response, fanout, unread count, and push path
remain authoritative.

## Default state

The hook is disabled unless all of the following are configured:

```text
GROUP_MESSAGE_REMOTE_SHADOW_ENABLED=1
GROUP_MESSAGE_CELL_ENDPOINTS=shadow-cell=http://10.0.0.12:6199
GROUP_MESSAGE_SHADOW_CELL_ID=shadow-cell
GROUP_CELL_INTERNAL_TOKEN=<random-private-token>
```

Multi-node health registration is independently controlled:

```text
GROUP_CELL_REGISTRY_ENABLED=1
GROUP_CELL_REGISTRY_INTERVAL_MS=15000
GROUP_CELL_REGISTRY_TIMEOUT_MS=2500
```

The registry periodically checks every configured Cell, excludes unhealthy or
draining nodes from selection, records latency and consecutive failures, and
supports optional per-Cell capacity and used-weight limits. Configured tokens
are never included in snapshots.

The registry resilience regression starts three isolated Cell processes, kills
one node, verifies it is excluded from selection, restarts it, and verifies
recovery. It also verifies that a node at its configured weight capacity stops
receiving new groups.

For a resident isolated cluster, use the local supervisor:

```powershell
node server/dev/group-cell-cluster.js `
  --cells cell-a=6201,cell-b=6202,cell-c=6203 `
  --data-root C:\isolated\group-cells `
  --route-db C:\isolated\group-routes.sqlite3 `
  --status-file C:\isolated\group-cluster-status.json `
  --internal-token <private-token>
```

The supervisor binds the child Cells to `127.0.0.1`, writes health and restart
state atomically, and restarts an unexpected child exit with capped exponential
backoff. It does not deploy to a production host.

Optional settings:

```text
GROUP_MESSAGE_REMOTE_SHADOW_TIMEOUT_MS=3000
GROUP_MESSAGE_REMOTE_SHADOW_MAX_PENDING=2000
GROUP_MESSAGE_REMOTE_SHADOW_BACKOFF_MS=5000
GROUP_MESSAGE_REMOTE_SHADOW_REPORT=/path/to/remote-shadow-report.json
GROUP_MESSAGE_REMOTE_SHADOW_INCLUDE_DIRECT=0
```

Set `GROUP_MESSAGE_REMOTE_SHADOW_INCLUDE_DIRECT=1` only after direct-chat
validation. The conversation Cell uses the same reliability, ordering,
membership-period, deletion, and cursor kernel as group chats.

Durable APNs handoff is independently controlled:

```text
PUSH_DELIVERY_OUTBOX_ENABLED=1
PUSH_DELIVERY_OUTBOX_MAX_ATTEMPTS=8
PUSH_DELIVERY_OUTBOX_INTERVAL_MS=1000
PUSH_DELIVERY_OUTBOX_FILE=/isolated/push-delivery-outbox.sqlite3
```

When enabled, each device delivery is committed before the APNs request.
Workers claim jobs with a lease, retry with exponential backoff, deduplicate by
message/device, and remove APNs-rejected tokens. The table is partitioned by the
local server/shard; it is not a single global queue.

The Cell endpoint must expose:

- `GET /internal/health`
- `POST /internal/groups/:groupId/join`
- `POST /internal/groups/:groupId/leave`
- `POST /internal/groups/:groupId/shadow`

All group routes require `X-Internal-Token` when the Cell is configured with a
token. The health route remains available to private-network monitoring.

## Safety behavior

- The hook queues messages in legacy sequence order.
- Network errors and Cell conflicts never change the sender response.
- Failures are recorded in a bounded report capped at 500 rows.
- Pending shadow work is bounded; excess shadow copies are dropped and counted
  rather than consuming unbounded memory.
- Network, authentication, and Cell 5xx failures open an exponential-backoff
  circuit. Successful delivery closes it immediately.
- Membership joins and leaves update the shadow periods without touching the
  production `chats.json` or production shard data.
- The report is atomically rewritten every 30 seconds and on process exit.
- No Cell route becomes authoritative in this mode. No epoch changes and no
  migration completion occur.

## Promotion gate

Do not enable live Cell reads or writes until the shadow report has:

1. zero unexplained errors;
2. zero duplicate or conflicting message IDs;
3. zero denied sender events;
4. membership-period counts matching legacy group membership;
5. a complete stored-message audit for the selected pilot groups.

The next step after shadow verification is an explicit pilot route assignment,
not a full shard cutover.

## Deterministic route planning

`server/lib/group-cell-route-plan.js` creates a deterministic assignment plan
without opening or writing a route database. Existing valid assignments are
preserved. Only new groups are placed, choosing the least-loaded Cell with a
stable group/Cell hash as the tie-breaker. Load is weighted by a compressed
logarithm of member count, so a very large group has more influence without
dominating an entire Cell. The plan reports both group count and weighted load.

Create an offline plan from a sanitized group manifest:

```powershell
node server/tools/group-cell-route-plan.js `
  --input GROUP_MANIFEST.json `
  --cells cell-a,cell-b,cell-c `
  --output GROUP_CELL_PLAN.json
```

Use the prior plan as `--previous GROUP_CELL_PLAN.json` when adding groups or a
new Cell. The tool only writes the requested plan file and never changes
`group_cell_routes`, epochs, Cell data, or production shard files.

Preview importing that plan into an isolated route database:

```powershell
node server/tools/group-cell-route-import.js `
  --plan GROUP_CELL_PLAN.json `
  --route-db ISOLATED_ROUTES.sqlite3 `
  --output ROUTE_IMPORT_PREVIEW.json
```

Dry-run opens the route database read-only. An approved import requires the
exact plan hash:

```powershell
node server/tools/group-cell-route-import.js `
  --plan GROUP_CELL_PLAN.json `
  --route-db ISOLATED_ROUTES.sqlite3 `
  --output ROUTE_IMPORT_RESULT.json `
  --apply `
  --confirm IMPORT:<assignmentHash>
```

Import never changes an existing route. Conflicting assignments abort the
entire batch, and rerunning the same exact plan is idempotent.

## Pilot migration gate

`server/tools/group-cell-pilot-gate.js` performs a read-only preflight against
two Cells. It checks health, membership presence, message count, duplicate IDs,
duplicate sequences, continuity, deletion hashes, cursor hashes, and source/target
separation.

```powershell
$env:GROUP_CELL_INTERNAL_TOKEN = '<private-token>'
node server/tools/group-cell-pilot-gate.js `
  --source-url http://10.0.0.11:6199 `
  --target-url http://10.0.0.12:6199 `
  --group group-id `
  --output PILOT_PREFLIGHT.json
```

An actual pilot migration is never implicit. It additionally requires the route
database, source/target Cell IDs, a positive epoch, a checkpoint directory, and
the exact confirmation string:

```text
MIGRATE:<groupId>:<targetCellId>:<epoch>
```

The worker performs the existing dual-write migration, compares messages,
membership, deletions, and cursors, then changes the route epoch only when all
four hashes match.
