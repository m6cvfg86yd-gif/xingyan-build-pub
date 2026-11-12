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

  friendRequested(friendship) {
    const id = friendship && friendship.id;
    const fromId = friendship && friendship.fromId;
    const toId = friendship && friendship.toId;
    if (!id || !fromId || !toId) return { status: 'invalid' };
    return this.submit('friendship', pairKey(fromId, toId), 'request', {
      a: fromId,
      b: toId,
      status: 'pending',
      legacyId: id
    }, 'friend-request:' + id);
  }

  friendRejected(friendship) {
    const id = friendship && friendship.id;
    const fromId = friendship && friendship.fromId;
    const toId = friendship && friendship.toId;
    if (!id || !fromId || !toId) return { status: 'invalid' };
    return this.submit('friendship', pairKey(fromId, toId), 'reject', {
      a: fromId,
      b: toId,
      status: 'rejected',
      legacyId: id
    }, 'friend-reject:' + id);
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

  chatMessageShown(chatId, ownerId, messageId) {
    const id = String(chatId || '') + '|' + String(ownerId || '');
    return this.submit('chat_visibility', id, 'message', {
      chatId,
      ownerId,
      messageId: messageId || ''
    }, 'chat-message:' + (messageId || id), { allowAfterTombstone: true });
  }

  chatUnread(chatId, ownerId, unread, legacyEventId) {
    const id = String(chatId || '') + '|' + String(ownerId || '');
    return this.submit('chat_read_state', id, 'unread', {
      chatId,
      ownerId,
      unread: unread === true || Number(unread) > 0
    }, 'chat-unread:' + id + ':' + String(unread === true || Number(unread) > 0)
      + ':' + (legacyEventId || ''));
  }

  chatPinned(chatId, ownerId, pinned, legacyEventId) {
    const id = String(chatId || '') + '|' + String(ownerId || '');
    return this.submit('chat_user_state', id, 'pin', {
      chatId,
      ownerId,
      pinned: pinned === true
    }, 'chat-pin:' + id + ':' + String(pinned === true) + ':' + (legacyEventId || ''));
  }

  chatMemberRemoved(chatId, userId, reason) {
    const id = String(chatId || '') + '|' + String(userId || '');
    return this.submit('chat_membership', id, reason || 'remove-member', {
      chatId,
      userId,
      active: false
    }, 'chat-member-remove:' + id + ':' + (reason || 'kick'), { deleted: true });
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

  momentLiked(momentId, userId, at, legacyEventId) {
    return this.submit('moment_like', momentId + '|' + userId, 'like', {
      momentId,
      userId,
      at: at || ''
    }, 'moment-like:' + momentId + ':' + userId + ':' + (legacyEventId || at || ''),
    { allowAfterTombstone: true });
  }

  momentUnliked(momentId, userId, at, legacyEventId) {
    return this.submit('moment_like', momentId + '|' + userId, 'unlike', {
      momentId,
      userId,
      at: at || ''
    }, 'moment-unlike:' + momentId + ':' + userId + ':' + (legacyEventId || at || ''),
    { deleted: true });
  }

  momentCommentLiked(momentId, commentId, userId, at, legacyEventId) {
    return this.submit('moment_comment_like', momentId + '|' + commentId + '|' + userId,
      'like', {
        momentId,
        commentId,
        userId,
        at: at || ''
      }, 'moment-comment-like:' + momentId + ':' + commentId + ':' + userId + ':'
        + (legacyEventId || at || ''),
      { allowAfterTombstone: true });
  }

  momentCommentUnliked(momentId, commentId, userId, at, legacyEventId) {
    return this.submit('moment_comment_like', momentId + '|' + commentId + '|' + userId,
      'unlike', {
        momentId,
        commentId,
        userId,
        at: at || ''
      }, 'moment-comment-unlike:' + momentId + ':' + commentId + ':' + userId + ':'
        + (legacyEventId || at || ''),
      { deleted: true });
  }

  transferClaimed(transfer, userId) {
    if (!transfer || !transfer.id) return { status: 'invalid' };
    return this.submit('transfer', transfer.id, 'claim', {
      transferId: transfer.id,
      userId: userId || transfer.toId || '',
      fromId: transfer.fromId || '',
      toId: transfer.toId || '',
      amount: transfer.amount,
      state: 'claimed',
      authority: 'payment-ledger'
    }, 'transfer-claim:' + transfer.id);
  }
}

function compareLegacyState(cluster, legacy) {
  const diffs = [];
  const data = legacy || {};
  const chatUserStates = new Map(
    cluster.list('chat_user_state').map((row) => [row.entityId, row])
  );
  const chatReadStates = new Map(
    cluster.list('chat_read_state').map((row) => [row.entityId, row])
  );
  const chatVisibilityStates = new Map(
    cluster.list('chat_visibility').map((row) => [row.entityId, row])
  );
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
    const visibilityOwners = new Set(chat.hiddenFor || []);
    for (const row of chatVisibilityStates.values()) {
      if (row && row.payload && row.payload.chatId === chat.id) {
        visibilityOwners.add(row.payload.ownerId);
      }
    }
    for (const ownerId of visibilityOwners) {
      const expectedHidden = (chat.hiddenFor || []).includes(ownerId);
      const visibilityState = chatVisibilityStates.get(chat.id + '|' + ownerId);
      const actualHidden = !!(visibilityState && visibilityState.deleted);
      if (actualHidden !== expectedHidden) {
        diffs.push({
          kind: 'chat-hidden',
          id: chat.id,
          ownerId,
          expected: expectedHidden
        });
      }
    }
    const stateOwners = new Set(chat.pinnedFor || []);
    for (const ownerId of chat.flaggedUnread || []) stateOwners.add(ownerId);
    for (const row of chatUserStates.values()) {
      if (row && row.payload && row.payload.chatId === chat.id) stateOwners.add(row.payload.ownerId);
    }
    for (const row of chatReadStates.values()) {
      if (row && row.payload && row.payload.chatId === chat.id) stateOwners.add(row.payload.ownerId);
    }
    for (const ownerId of stateOwners) {
      const expectedPinned = (chat.pinnedFor || []).includes(ownerId);
      const pinState = chatUserStates.get(chat.id + '|' + ownerId);
      const actualPinned = !!(pinState && !pinState.deleted
        && pinState.payload && pinState.payload.pinned === true);
      if (actualPinned !== expectedPinned) {
        diffs.push({ kind: 'chat-pin', id: chat.id, ownerId, expected: expectedPinned });
      }
      const expectedUnread = (chat.flaggedUnread || []).includes(ownerId);
      const readState = chatReadStates.get(chat.id + '|' + ownerId);
      const actualUnread = !!(readState && !readState.deleted
        && readState.payload && readState.payload.unread === true);
      if (actualUnread !== expectedUnread) {
        diffs.push({ kind: 'chat-unread', id: chat.id, ownerId, expected: expectedUnread });
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
      for (const like of comment.likes || []) {
        const likeRow = cluster.get(
          'moment_comment_like',
          moment.id + '|' + comment.id + '|' + like.userId
        );
        if (!likeRow || likeRow.deleted) {
          diffs.push({
            kind: 'moment-comment-like',
            id: comment.id,
            userId: like.userId
          });
        }
      }
    }
    for (const like of moment.likes || []) {
      const row = cluster.get('moment_like', moment.id + '|' + like.userId);
      if (!row || row.deleted) diffs.push({ kind: 'moment-like', id: moment.id, userId: like.userId });
    }
  }
  for (const transfer of data.transfers || []) {
    if (!transfer || transfer.status !== 'received') continue;
    const state = cluster.get('transfer', transfer.id);
    const payload = state && !state.deleted ? state.payload || {} : {};
    const mismatches = [];
    if (payload.state !== 'claimed') mismatches.push('state');
    if (payload.authority !== 'payment-ledger') mismatches.push('authority');
    if (String(payload.fromId || '') !== String(transfer.fromId || '')) mismatches.push('fromId');
    if (String(payload.toId || '') !== String(transfer.toId || '')) mismatches.push('toId');
    if (Number(payload.amount) !== Number(transfer.amount)) mismatches.push('amount');
    if (mismatches.length) {
      diffs.push({ kind: 'transfer-claim', id: transfer.id, fields: mismatches });
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
