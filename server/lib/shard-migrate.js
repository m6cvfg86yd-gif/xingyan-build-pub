'use strict';

const { pairKey } = require('./shard-domain');

function apply(cluster, entityType, entityId, version, operation, payload, options) {
  return cluster.apply(entityType, entityId, Object.assign({
    eventId: 'migrate:' + entityType + ':' + entityId + ':' + version + ':' + operation,
    version,
    operation,
    payload: payload || {},
    createdAt: 'migration'
  }, options || {}));
}

function migrateLegacyState(options) {
  const cluster = options && options.cluster;
  if (!cluster) throw new Error('cluster is required');
  const counts = {
    friendships: 0,
    chatVisibility: 0,
    chatPins: 0,
    chatReads: 0,
    chatMemberships: 0,
    groupsDissolved: 0,
    moments: 0,
    comments: 0,
    likes: 0,
    transfers: 0,
    skipped: 0
  };

  for (const friendship of options.friendships || []) {
    if (!friendship || friendship.status !== 'accepted' || !friendship.fromId || !friendship.toId) {
      counts.skipped += 1;
      continue;
    }
    const id = pairKey(friendship.fromId, friendship.toId);
    apply(cluster, 'friendship', id, 1, 'accept', {
      a: friendship.fromId,
      b: friendship.toId,
      status: 'accepted',
      legacyId: friendship.id || ''
    });
    counts.friendships += 1;
  }

  for (const chat of options.chats || []) {
    if (!chat || !chat.id) {
      counts.skipped += 1;
      continue;
    }
    apply(cluster, 'chat', chat.id, 1,
      chat.dismissed ? 'dismiss' : 'create',
      {
        chatId: chat.id,
        type: chat.type || 'direct',
        ownerId: chat.ownerId || '',
        memberIds: Array.isArray(chat.memberIds) ? chat.memberIds.slice() : [],
        state: chat.dismissed ? 'dissolved' : 'active'
      },
      { deleted: !!chat.dismissed });
    if (chat.dismissed) counts.groupsDissolved += 1;
    for (const ownerId of chat.hiddenFor || []) {
      apply(cluster, 'chat_visibility', chat.id + '|' + ownerId, 1, 'hide', {
        chatId: chat.id,
        ownerId
      }, { deleted: true });
      counts.chatVisibility += 1;
    }
    for (const ownerId of chat.pinnedFor || []) {
      apply(cluster, 'chat_user_state', chat.id + '|' + ownerId, 1, 'pin', {
        chatId: chat.id,
        ownerId,
        pinned: true
      });
      counts.chatPins += 1;
    }
    for (const ownerId of chat.flaggedUnread || []) {
      apply(cluster, 'chat_read_state', chat.id + '|' + ownerId, 1, 'unread', {
        chatId: chat.id,
        ownerId,
        unread: true
      });
      counts.chatReads += 1;
    }
    for (const memberId of chat.memberIds || []) {
      apply(cluster, 'chat_membership', chat.id + '|' + memberId, 1, 'join', {
        chatId: chat.id,
        userId: memberId,
        active: true
      });
      counts.chatMemberships += 1;
    }
  }

  for (const moment of options.moments || []) {
    if (!moment || !moment.id) {
      counts.skipped += 1;
      continue;
    }
    apply(cluster, 'moment', moment.id, 1, 'publish', {
      momentId: moment.id,
      authorId: moment.authorId || '',
      content: moment.content || '',
      images: Array.isArray(moment.images) ? moment.images.slice() : [],
      createdAt: moment.createdAt || ''
    });
    counts.moments += 1;
    for (const comment of moment.comments || []) {
      const commentId = String(comment.id || '');
      if (!commentId) {
        counts.skipped += 1;
        continue;
      }
      apply(cluster, 'moment_comment', moment.id + '|' + commentId, 1, 'publish', {
        momentId: moment.id,
        commentId,
        userId: comment.userId || '',
        content: comment.content || '',
        at: comment.at || ''
      });
      counts.comments += 1;
      for (const like of comment.likes || []) {
        if (!like.userId) {
          counts.skipped += 1;
          continue;
        }
        apply(cluster, 'moment_comment_like',
          moment.id + '|' + commentId + '|' + like.userId, 1, 'like', {
            momentId: moment.id,
            commentId,
            userId: like.userId,
            at: like.at || ''
          });
        counts.likes += 1;
      }
    }
    for (const like of moment.likes || []) {
      if (!like.userId) {
        counts.skipped += 1;
        continue;
      }
      apply(cluster, 'moment_like', moment.id + '|' + like.userId, 1, 'like', {
        momentId: moment.id,
        userId: like.userId,
        at: like.at || ''
      });
      counts.likes += 1;
    }
  }

  for (const transfer of options.transfers || []) {
    if (!transfer || !transfer.id) {
      counts.skipped += 1;
      continue;
    }
    if (transfer.status === 'received') {
      apply(cluster, 'transfer', transfer.id, 1, 'claim', {
        transferId: transfer.id,
        userId: transfer.toId || '',
        fromId: transfer.fromId || '',
        toId: transfer.toId || '',
        amount: transfer.amount,
        state: 'claimed',
        authority: 'payment-ledger',
        legacyStatus: transfer.status
      });
      counts.transfers += 1;
    } else if (transfer.status === 'pending' || transfer.status === 'refunded') {
      apply(cluster, 'transfer', transfer.id, 1, transfer.status, {
        transferId: transfer.id,
        userId: transfer.toId || '',
        fromId: transfer.fromId || '',
        toId: transfer.toId || '',
        amount: transfer.amount,
        state: transfer.status,
        authority: 'payment-ledger',
        legacyStatus: transfer.status
      });
      counts.transfers += 1;
    } else {
      counts.skipped += 1;
    }
  }

  return counts;
}

module.exports = { migrateLegacyState };
