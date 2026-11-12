'use strict';

const { pairKey } = require('./shard-domain');

class LegacyShadowRecorder {
  constructor(options) {
    this.gateway = options && options.gateway;
    if (!this.gateway) throw new Error('gateway is required');
  }

  submit(entityType, entityId, operation, payload, key, options) {
    const opts = options || {};
    return this.gateway.submit({
      entityType,
      entityId,
      operation,
      payload,
      eventId: 'legacy:' + (key || (operation + ':' + entityId)),
      deleted: opts.deleted === true,
      allowAfterTombstone: opts.allowAfterTombstone === true
    });
  }

  friendAccepted(friendship) {
    const id = friendship && friendship.id;
    const fromId = friendship && friendship.fromId;
    const toId = friendship && friendship.toId;
    if (!id || !fromId || !toId) return { status: 'invalid' };
    return this.submit('friendship', pairKey(fromId, toId), 'accept', {
      a: fromId,
      b: toId,
      status: 'accepted',
      legacyId: id
    }, 'friend-accept:' + id);
  }

  friendRemoved(actorId, targetId, legacyEventId) {
    const id = String(actorId || '') + '|' + String(targetId || '');
    return this.submit('friend_visibility', id, 'delete', {
      ownerId: actorId,
      targetId
    }, 'friend-remove:' + (legacyEventId || id), { deleted: true });
  }

  chatHidden(chatId, ownerId, legacyEventId) {
    const id = String(chatId || '') + '|' + String(ownerId || '');
    return this.submit('chat_visibility', id, 'hide', {
      chatId,
      ownerId
    }, 'chat-hide:' + (legacyEventId || id), { deleted: true });
  }

  groupDismissed(chatId, legacyEventId) {
    return this.submit('chat', chatId, 'dismiss', {
      chatId,
      state: 'dissolved'
    }, 'chat-dismiss:' + (legacyEventId || chatId), { deleted: true });
  }

  momentPublished(moment) {
    if (!moment || !moment.id) return { status: 'invalid' };
    return this.submit('moment', moment.id, 'publish', {
      momentId: moment.id,
      authorId: moment.authorId || '',
      content: moment.content || '',
      createdAt: moment.createdAt || ''
    }, 'moment-publish:' + moment.id);
  }

  momentCommented(momentId, comment) {
    if (!comment || !comment.id) return { status: 'invalid' };
    return this.submit('moment_comment', momentId + '|' + comment.id, 'publish', {
      momentId,
      commentId: comment.id,
      userId: comment.userId || '',
      content: comment.content || ''
    }, 'moment-comment:' + momentId + ':' + comment.id);
  }

  momentLiked(momentId, userId, at) {
    return this.submit('moment_like', momentId + '|' + userId, 'like', {
      momentId,
      userId,
      at: at || ''
    }, 'moment-like:' + momentId + ':' + userId);
  }

  transferClaimed(transfer, userId) {
    if (!transfer || !transfer.id) return { status: 'invalid' };
    return this.submit('transfer', transfer.id, 'claim', {
      transferId: transfer.id,
      userId: userId || transfer.toId || '',
      state: 'claimed'
    }, 'transfer-claim:' + transfer.id);
  }
}

function compareLegacyState(cluster, legacy) {
  const diffs = [];
  const data = legacy || {};
  for (const friendship of data.friendships || []) {
    if (!friendship || friendship.status !== 'accepted') continue;
    const state = cluster.get('friendship', pairKey(friendship.fromId, friendship.toId));
    if (!state || state.deleted || state.payload.status !== 'accepted') {
      diffs.push({ kind: 'friendship', id: friendship.id || '', expected: 'accepted' });
    }
  }
  for (const chat of data.chats || []) {
    if (!chat || !chat.id) continue;
    if (chat.dismissed) {
      const state = cluster.get('chat', chat.id);
      if (!state || !state.deleted) diffs.push({ kind: 'chat-dismiss', id: chat.id });
    }
    for (const ownerId of chat.hiddenFor || []) {
      const state = cluster.get('chat_visibility', chat.id + '|' + ownerId);
      if (!state || !state.deleted) {
        diffs.push({ kind: 'chat-hidden', id: chat.id, ownerId });
      }
    }
  }
  for (const moment of data.moments || []) {
    if (!moment || !moment.id) continue;
    const state = cluster.get('moment', moment.id);
    if (!state || state.deleted) diffs.push({ kind: 'moment', id: moment.id });
    for (const comment of moment.comments || []) {
      const row = cluster.get('moment_comment', moment.id + '|' + comment.id);
      if (!row || row.deleted) diffs.push({ kind: 'moment-comment', id: comment.id });
    }
    for (const like of moment.likes || []) {
      const row = cluster.get('moment_like', moment.id + '|' + like.userId);
      if (!row || row.deleted) diffs.push({ kind: 'moment-like', id: moment.id, userId: like.userId });
    }
  }
  for (const transfer of data.transfers || []) {
    if (!transfer || transfer.status !== 'received') continue;
    const state = cluster.get('transfer', transfer.id);
    if (!state || state.payload.state !== 'claimed') {
      diffs.push({ kind: 'transfer-claim', id: transfer.id });
    }
  }
  return { ok: diffs.length === 0, checked: {
    friendships: (data.friendships || []).length,
    chats: (data.chats || []).length,
    moments: (data.moments || []).length,
    transfers: (data.transfers || []).length
  }, diffs };
}

module.exports = { LegacyShadowRecorder, compareLegacyState };
