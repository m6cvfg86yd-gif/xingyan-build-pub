'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { createShardShadowService } = require('../lib/shard-shadow-service');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-shard-shadow-service-'));

try {
  const disabled = createShardShadowService({
    enabled: '0',
    dataDir: path.join(root, 'disabled'),
    shardCount: 6
  });
  assert.strictEqual(disabled.enabled, false);
  assert.deepStrictEqual(disabled.observe('friends.request', {}), { status: 'disabled' });
  assert.strictEqual(fs.existsSync(path.join(root, 'disabled', 'shard-shadow')), false);

  let uidCounter = 0;
  let clock = 0;
  const service = createShardShadowService({
    enabled: '1',
    dataDir: path.join(root, 'enabled'),
    shardCount: 6,
    uid: (prefix) => prefix + '-' + (++uidCounter),
    now: () => new Date(1700000000000 + (++clock)).toISOString()
  });
  assert.strictEqual(service.enabled, true);

  const friendship = {
    id: 'shadow-friend-1',
    fromId: 'shadow-alice',
    toId: 'shadow-bob',
    status: 'accepted'
  };
  assert.strictEqual(service.observe('friends.request', { friendship }).status, 'applied');
  assert.strictEqual(service.observe('friends.request', { friendship }).status, 'duplicate');
  assert.strictEqual(service.observe('friends.respond', {
    friendship,
    accept: true
  }).status, 'applied');

  const hide = {
    chatId: 'shadow-chat-1',
    ownerId: 'shadow-alice',
    eventId: 'shadow-hide-1'
  };
  assert.strictEqual(service.observe('chats.hide', hide).status, 'applied');
  assert.strictEqual(service.observe('chats.hide', hide).status, 'duplicate');
  assert.strictEqual(service.observe('chats.messages.create', {
    chatId: hide.chatId,
    messageId: 'shadow-message-1',
    recipientIds: [hide.ownerId]
  })[0].status, 'applied');

  for (const eventId of ['pin-1', 'pin-2', 'pin-3']) {
    const result = service.observe('chats.pin', {
      chatId: hide.chatId,
      ownerId: hide.ownerId,
      pinned: eventId !== 'pin-2',
      eventId
    });
    assert.strictEqual(result.status, 'applied');
  }
  for (const [unread, eventId] of [[true, 'unread-1'], [false, 'read-1'], [true, 'unread-2']]) {
    const result = service.observe('chats.unread', {
      chatId: hide.chatId,
      ownerId: hide.ownerId,
      unread,
      eventId
    });
    assert.strictEqual(result.status, 'applied');
  }

  const moment = {
    id: 'shadow-moment-1',
    authorId: 'shadow-alice',
    content: 'shadow compare'
  };
  assert.strictEqual(service.observe('moments.publish', { moment }).status, 'applied');
  assert.strictEqual(service.observe('moments.comment', {
    momentId: moment.id,
    comment: {
      id: 'shadow-comment-1',
      userId: 'shadow-bob',
      content: 'shadow comment'
    }
  }).status, 'applied');

  const likeToggles = [
    ['moments.like', true, 'like-1', 'shadow-bob'],
    ['moments.like', false, 'unlike-1', 'shadow-bob'],
    ['moments.like', true, 'like-2', 'shadow-bob']
  ];
  for (const [routeId, liked, eventId, userId] of likeToggles) {
    const result = service.observe(routeId, {
      momentId: moment.id,
      userId,
      liked,
      at: eventId,
      eventId
    });
    assert.strictEqual(result.status, 'applied', routeId + ': ' + eventId);
  }

  const commentLikeToggles = [
    ['moments.comment-like', true, 'comment-like-1', 'shadow-alice'],
    ['moments.comment-like', false, 'comment-unlike-1', 'shadow-alice'],
    ['moments.comment-like', true, 'comment-like-2', 'shadow-alice']
  ];
  for (const [routeId, liked, eventId, userId] of commentLikeToggles) {
    const result = service.observe(routeId, {
      momentId: moment.id,
      commentId: 'shadow-comment-1',
      userId,
      liked,
      at: eventId,
      eventId
    });
    assert.strictEqual(result.status, 'applied', routeId + ': ' + eventId);
  }

  const transfer = {
    id: 'shadow-transfer-1',
    fromId: 'shadow-alice',
    toId: 'shadow-bob',
    amount: 1.25,
    status: 'received'
  };
  assert.strictEqual(service.observe('transfers.claim', {
    transfer,
    userId: transfer.toId
  }).status, 'applied');
  assert.strictEqual(service.observe('transfers.claim', {
    transfer,
    userId: transfer.toId
  }).status, 'duplicate');

  const legacy = {
    friendships: [friendship],
    chats: [{
      id: hide.chatId,
      hiddenFor: [],
      pinnedFor: [hide.ownerId],
      flaggedUnread: [hide.ownerId]
    }],
    moments: [{
      id: moment.id,
      authorId: moment.authorId,
      content: moment.content,
      likes: [{ userId: 'shadow-bob', at: 'like-2' }],
      comments: [{
        id: 'shadow-comment-1',
        userId: 'shadow-bob',
        content: 'shadow comment',
        likes: [{ userId: 'shadow-alice', at: 'comment-like-2' }]
      }]
    }],
    transfers: [transfer]
  };
  const comparison = service.compare(legacy);
  assert.strictEqual(comparison.ok, true, JSON.stringify(comparison.diffs));
  assert.strictEqual(service.cluster.verify().ok, true);
  const report = service.audit(legacy);
  assert.strictEqual(report.ok, true, JSON.stringify(report.diffs));
  const storedReport = JSON.parse(fs.readFileSync(service.reportFile, 'utf8'));
  assert.strictEqual(storedReport.ok, true);
  assert.strictEqual(Number.isInteger(storedReport.migration.friendships), true);
  const divergentLegacy = JSON.parse(JSON.stringify(legacy));
  divergentLegacy.friendships.push({
    id: 'shadow-missing-friend',
    fromId: 'missing-a',
    toId: 'missing-b',
    status: 'accepted'
  });
  const divergence = service.audit(divergentLegacy);
  assert.strictEqual(divergence.ok, false);
  assert.ok(fs.existsSync(service.diffHistoryFile));

  const reopened = createShardShadowService({
    enabled: '1',
    dataDir: path.join(root, 'enabled'),
    shardCount: 6,
    uid: (prefix) => prefix + '-reopen-' + (++uidCounter),
    now: () => new Date(1700000100000 + (++clock)).toISOString()
  });
  assert.strictEqual(reopened.compare(legacy).ok, true);

  assert.deepStrictEqual(service.observe('contacts.list', {}), {
    status: 'read-observed',
    routeId: 'contacts.list'
  });
  assert.strictEqual(service.observe('not-a-route', {}).status, 'unmapped');

  console.log('shard-shadow-service: passed');
} finally {
  fs.rmSync(root, { recursive: true, force: true });
}
