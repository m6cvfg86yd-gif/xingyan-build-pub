# Billion-scale foundation baseline

Date: 2026-11-15

## Production guardrails

- Stable rollback package: `2611150742`
- Stable Git tag: `stable-2611150742`
- Development branch: `codex/million-scale-foundation`
- Main branch and production shards are not changed by this work.
- Message reliability and shard migration remain default-off until shadow
  reconciliation reports zero unexplained differences.

## Required data invariants

1. Every outgoing message has a stable client ID and server message ID.
2. Each conversation has a monotonic sequence.
3. Message persistence, conversation summary updates, and event publication are
   one transaction.
4. Duplicate client IDs return the original message.
5. Device delivery and read cursors are monotonic.
6. Payment ledger records are idempotent and reference a unique payment intent.
7. Chat metadata and payment authority never share mutable JSON state.

## Baseline checks passed

- Message reliability, concurrency, and backfill
- Message cursor/since paging
- Offline outbox retry, concurrent client-ID deduplication, and restart ordering
- Chat actions and group presence
- Shard coverage, placement, routing, runtime, lease, and message repair
- Shard shadow service and release readiness
- Payment database, concurrent debit, ledger, startup recovery, and real chain
- Upload integrity, favorites sync, and Moment delete persistence

## Next implementation gates

1. Add production-safe shadow verification and mismatch reporting.
2. Run the offline-outbox and reconnect contract on physical devices with
   airplane-mode transitions and forced process termination.
3. Reconcile every shard before any topology cutover.
4. Keep payment settlement disabled until independent ledger reconciliation is
   clean.

## Durable event publication

Cluster facts are the source of truth. The mutation gateway attempts an
idempotent event-bus publication after the fact is applied. If publication
fails, the write remains durable and reports `busPending`; retrying the same
command repairs the event exactly once without creating a second message or
event. `syncFromCluster` is the reconciliation fallback for a longer outage.

## Message write pipeline

`server/lib/message-write-pipeline.js` defines the storage-neutral append
contract for the next message plane. Each conversation has one in-process
write queue; sequence reservation, idempotency metadata, and the message
Outbox are committed through the reliability store before the thread storage
append.

If thread storage fails, the message remains durable and the result reports
`storagePending`. Retrying the same `clientId` repairs the thread exactly once
without allocating a new sequence or duplicating the Outbox event. The contract
is tested with concurrent duplicate retries and 120 parallel ordered appends.

## Group message plane

`server/lib/group-message-plane.js` separates durable group writes from
fanout. Small groups use asynchronous per-member events; groups above the
configured threshold publish one group-timeline signal and enqueue bounded
partition jobs for notification workers. The send request never performs a
synchronous all-member fanout.

Membership visibility is evaluated with `joinedSeq` and `leftSeq`, so joins and
leaves do not retroactively expose or hide the wrong historical sequence.
Unread counts are derived from latest, read, and cleared cursors rather than
copying every group message into every member inbox.

`server/lib/group-membership-store.js` persists membership periods with
`joinedSeq` and `leftSeq`. Join, leave, and rejoin keep separate periods, so
historical visibility remains correct after membership changes. Active member
pages and counts are queried directly from the covering period instead of
loading the entire group member list.

`server/lib/group-timeline-service.js` provides cursor-based group reads.
New members start at their `joinedSeq`; departed members can only read before
`leftSeq`; cleared history is applied as a lower bound. Unread counts use the
latest group sequence and per-device read cursor rather than per-member message
copies.

`server/lib/group-notification-worker.js` consumes bounded group member
partitions for offline notifications. Online members are skipped because they
already receive the group timeline signal. Push records carry an idempotency
key of `groupId:seq:userId`, so queue retries do not create duplicate alerts.

`server/lib/group-message-cell.js` assembles the durable write, membership,
fanout, timeline, and cursor components into restartable isolated cells. The
cell integration test runs two cells side by side, verifies data and fanout
isolation, then restarts one cell and confirms sequence continuity.

Group deletion uses server-side tombstones rather than immediate physical
deletion. `group-deletion-store` records user hides, per-user cleared sequence,
global recall, and global takedown states. Timeline reads apply these states
before returning messages, so stale clients and delayed create events cannot
resurrect hidden content.

`group-message-shadow` mirrors real group messages into isolated shadow cells
using their existing message ID and sequence. It runs the new membership,
fanout, and notification model without changing legacy responses, and writes a
deterministic-style operational report for duplicate, denied, conflict, and
import counts.

The production server enables this observer only when
`GROUP_MESSAGE_SHADOW_ENABLED=1`; the default is off. Shadow errors are logged
and never alter legacy message responses. The chat action regression passes
with the shadow flag enabled.

`server/lib/remote-group-cell-shadow.js` adds the first production-safe remote
Cell hook. It mirrors legacy group messages to a token-protected Cell over HTTP,
updates shadow membership periods in sequence order, and writes a bounded
atomic report. It is disabled by default, never blocks the legacy sender
response, and does not change ownership routes or epochs. Configuration and the
promotion gate are documented in `docs/group-cell-production-hook.md`.
The remote shadow queue is bounded and protected by an exponential-backoff
circuit breaker, so an unavailable Cell cannot grow memory without limit or
receive uninterrupted retry traffic.

`server/lib/group-cell-registry.js` maintains multi-node health and capacity
state. It excludes failed or draining Cells, records latency and consecutive
failures, and can select a healthy node only when its weighted capacity remains
available.

The multi-process registry drill covers three live local Cells: one node is
terminated, the registry removes it from selection, the process is restarted,
and the node returns to the healthy pool. Capacity saturation is exercised
separately.

`server/dev/group-cell-cluster.js` provides a resident local supervisor for
multi-node drills. It atomically reports health and restart state and restarts
unexpected child exits with capped exponential backoff. It binds only to
loopback and is not a production deployment tool.

The same conversation-cell kernel is validated for direct chats with two active
members. Direct-chat remote shadowing remains an explicit opt-in and preserves
the same sequence, membership-period, deletion, and cursor invariants.

## Durable push handoff

`server/lib/push-delivery-outbox.js` stores APNs deliveries in SQLite before
delivery. It provides idempotent dedupe keys, lease-based claiming across
workers, bounded retries, sent/failed state, and invalid-token removal. The
production hook remains default-off through `PUSH_DELIVERY_OUTBOX_ENABLED`.
Batch enqueue is transactional: the 20,000-job local probe currently commits in
about 126 ms on the development host, while two workers claim through leases
without duplicate delivery.

`server/lib/apns-http2-pool.js` keeps persistent production and sandbox HTTP/2
sessions instead of creating one connection per notification. It multiplexes
requests, queues above the concurrency limit, rejects queue overflow without
unbounded memory growth, and reconnects after session close/GOAWAY. A 20,000-job
fake-transport probe completed in about 386 ms with 16 total sessions and 3,200
in-flight requests. Real Apple throughput remains a separate sandbox gate.

`server/tools/apns-sandbox-probe.js` performs that real gate against APNs
sandbox and reports success count, throughput, P50/P95/P99 latency, session
count, active requests, overflow, and reconnect statistics. It never prints the
private signing key.

## Device sync contract

When `MESSAGE_RELIABILITY_ENABLED=1`, `GET /api/sync/state` pages through every
conversation for the authenticated device and returns `lastSeq`,
`deliveredSeq`, `readSeq`, and `hasDelta`. `POST /api/sync/ack` accepts up to
1,000 monotonic delivery acknowledgements and persists them in one transaction.
Chat membership and device identity are validated before any cursor changes.
The client adoption of this endpoint is a separate release gate.

The HTTP integration gate covers two devices for one account, per-device
delivery isolation, batch acknowledgement, server restart persistence, and new
delta creation after a later message.

`server/lib/group-cell-route-plan.js` creates deterministic incremental plans
without writing route state. Existing assignments remain stable, while new
groups are balanced across Cells with a stable hash tie-breaker. The companion
CLI only writes a reviewable plan file; it cannot mutate live routes.

`server/lib/group-cell-route-import.js` previews and imports those plans without
overwriting existing ownership. Dry-run uses a read-only SQLite connection.
Apply requires the exact plan hash and performs the initial route inserts in one
transaction; any conflicting assignment aborts the whole batch.

`server/lib/group-cell-pilot-gate.js` is the read-only entry gate for pilot
migrations. It rejects duplicate message IDs, duplicate or non-contiguous
sequences, missing membership, equal source/target endpoints, and unhealthy
Cells before any migration checkpoint or route mutation can begin.

`server/lib/group-cell-router.js` enforces one owning cell per group and an
epoch for online migration. During migration, reads and writes stay on the
source cell while the target is populated. Completion switches ownership only
with the expected epoch, after which the old cell is fenced from writes.

`server/lib/group-route-store.js` persists the same route and epoch in a
transactional SQLite table. Two independent router instances see one shared
ownership state, stale epochs cannot overwrite newer routes, and migration
status survives process restarts.

`server/dev/group-cell-server.js` exposes isolated cells as separate HTTP
processes for staging tests. The multiprocess test starts two cells, rejects
writes to the wrong cell, mirrors historical messages into the target, performs
cross-process dual-write during migration, fences the old cell after the epoch
switch, and verifies the target timeline.

`server/lib/remote-group-migration-worker.js` performs the same migration over
real HTTP between two cells. It exports/imports metadata, pages historical
messages, writes through the target mirror endpoint, compares messages,
membership, deletions and cursors, then switches the persisted route epoch.
While migration is active, successful source writes are mirrored to the target
with historical fanout suppressed; source response remains authoritative.

`server/lib/group-migration-worker.js` persists a resumable checkpoint while
copying messages, membership periods, deletion tombstones, and device cursors.
It supports source writes during migration through router dual-write, compares
all four data groups before completion, and switches ownership only when the
epoch and hashes match.

`server/lib/durable-group-queue.js` persists group notification and partition
jobs with unique deduplication keys, worker leases, expired-lease recovery,
retry scheduling, acknowledgement, and restart-safe counters.

## Read-only message audit

`server/tools/message-consistency-audit.js` compares each message JSONL file
with the reliability metadata without calling the writable reliability store.
It uses SQLite `immutable=1`, rejects databases with uncheckpointed WAL/journal
data, and never creates sidecar files beside the source database.

The report checks duplicate and cross-chat message IDs, duplicate client IDs,
sequence gaps and ordering, malformed or undecryptable rows, missing or extra
reliability rows, payload drift, and `chat_sequence.last_seq` mismatches. Issue
rows are deterministically sorted and the report includes a stable fingerprint
that excludes timestamps.

Audit a checkpointed offline snapshot:

```powershell
node server/tools/message-consistency-audit.js `
  --data DATA_DIR `
  --secret SECRET_FILE `
  --source SHARD_ID `
  --out REPORT.json
```

An active WAL must be checkpointed by its owner or copied with the shard's
normal snapshot process. The audit intentionally refuses to guess at
uncheckpointed data and does not repair any mismatch it finds.

Release readiness can require one audit report per shard:

```powershell
node server/tools/shard-release-readiness.js `
  --baseline BASELINE.json `
  --candidate CANDIDATE.json `
  --allowlist ALLOWLIST.json `
  --route-plan ROUTE_PLAN.json `
  --message-audit SHARD_0_AUDIT.json `
  --message-audit SHARD_1_AUDIT.json `
  --require-message-audit `
  --message-matrix SHARD_MATRIX_AUDIT.json `
  --require-message-matrix `
  --out RELEASE_READINESS.json
```

This gate rejects missing reports, writable or incomplete audits, suppressed
issues, missing fingerprints, and a shard-wide message count that differs from
the candidate inventory. Strict matrix mode also requires the matrix shard
count to equal the route-plan topology and the aggregate message count to equal
the candidate inventory.

For an offline copy containing all shard snapshots, run the matrix audit once
with a shared read-only index:

```json
{
  "offlineRoot": "copies",
  "expectedMessages": 123456,
  "shards": [
    {
      "sourceId": "server-a-shard-0",
      "dataDir": "copies/server-a/shard-0",
      "databaseFile": "copies/server-a/shard-0/message-reliability.sqlite3",
      "secretFile": "secrets/server-a.key"
    }
  ]
}
```

```powershell
node server/tools/message-consistency-audit-matrix.js `
  --config OFFLINE_SHARDS.json `
  --offline-root C:\isolated-shard-copies `
  --out SHARD_MATRIX_AUDIT.json
```

The matrix detects a conversation or message ID appearing in more than one
shard, detects client-ID reuse across shards, and verifies the aggregate
message count. `offlineRoot` is mandatory in the CLI and every shard directory
and reliability database must resolve inside it. It only reads the configured
offline copies and refuses any path outside that isolation boundary.

The local reliability probe creates its own operating-system temporary
database, runs configurable multi-process reservations, and verifies contiguous
sequences, message count, event count, and durable chat sequence:

```powershell
node server/tools/message-reliability-probe.js `
  --workers 8 `
  --per-worker 500 `
  --out RELIABILITY_PROBE.json
```

The probe has no option for an existing database path, so it cannot be pointed
at a live shard. Its report contains a sequence digest and summary by default;
`--include-sequences` is available only for small diagnostic runs.

Topology expansion can be planned without moving data:

```powershell
node server/tools/shard-rebalance-plan.js `
  --route-plan ROUTE_PLAN_6.json `
  --target-shards 7 `
  --target-topology server-a-shards-7 `
  --assignments-out REBALANCED_7_ASSIGNMENTS.json `
  --moves-out REBALANCE_MOVES.json `
  --out REBALANCE_PLAN.json
```

The planner preserves every existing assignment except the deterministic
subset needed to fill newly added shards. It reports movement percentage,
before/after shard counts, maximum deviation, assignment hash, and a stable
move digest. It only writes planning artifacts and never executes a migration.

The isolated fault drill covers lease expiry, old-writer fencing, transient and
persistent event-bus outages, duplicate repair, reconciliation, and restart
verification:

```powershell
node server/tools/shard-fault-drill.js --out SHARD_FAULT_DRILL.json
```

The drill always creates its own temporary directory and has no option for a
live shard path.
