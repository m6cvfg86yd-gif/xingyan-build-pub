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

Optional settings:

```text
GROUP_MESSAGE_REMOTE_SHADOW_TIMEOUT_MS=3000
GROUP_MESSAGE_REMOTE_SHADOW_REPORT=/path/to/remote-shadow-report.json
```

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
