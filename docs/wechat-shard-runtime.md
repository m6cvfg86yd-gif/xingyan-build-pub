# WeChat-Grade Shard Runtime

This document defines the required state guarantees for the Xingyan shard layer.
It is intentionally stricter than the current shared-JSON implementation.

## Non-negotiable invariants

1. Every user and every chat has exactly one authoritative shard.
2. A state transition is applied by exactly one writer.
3. Every mutation has an idempotency key and a monotonically increasing entity version.
4. A stale event can never overwrite a newer event.
5. Two different events cannot claim the same entity version.
6. Friend deletion, group removal, and group dissolution use tombstones.
7. A tombstone cannot be bypassed accidentally; resurrection requires an explicit command.
8. Event durability happens before success is returned.
9. Restart replays the append-only log and reconstructs the same state.
10. The API gateway routes reads and writes by owner shard, not by random process.

## Required rollout gates

- Six simulated shards share a temporary event stream.
- Duplicate, delayed, reordered, and retried events produce one result.
- Shard restart before and after an acknowledged write preserves the result.
- Concurrent delete/re-add cannot resurrect a relationship incorrectly.
- Group dissolution remains a permanent tombstone.
- A hidden chat only reappears through an explicit new-message event or user action.
- Payment claim is idempotent and cannot post twice.

Production deployment is forbidden until every gate above passes in the isolated
six-shard harness.
