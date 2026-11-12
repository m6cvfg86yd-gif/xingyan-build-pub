'use strict';

function pairKey(a, b) {
  return [String(a || ''), String(b || '')].sort().join('|');
}

class ShardDomain {
  constructor(options) {
    this.cluster = options && options.cluster;
    this.bus = options && options.bus;
    this.uid = options && options.uid;
    this.now = options && options.now;
    if (!this.cluster) throw new Error('cluster is required');
    if (typeof this.uid !== 'function') throw new Error('uid is required');
    if (typeof this.now !== 'function') this.now = () => new Date().toISOString();
  }

  entity(entityType, entityId) {
    return this.cluster.get(entityType, entityId);
  }

  apply(entityType, entityId, version, operation, payload, options) {
    const event = Object.assign({
      eventId: this.uid('evt'),
      version: Number(version),
      operation,
      payload: payload || {},
      createdAt: this.now()
    }, options || {});
    const result = this.cluster.apply(entityType, entityId, event);
    if (result.status === 'applied' && this.bus) this.bus.publish(event);
    return result;
  }

  relation(a, b) {
    return this.entity('friendship', pairKey(a, b));
  }

  visibility(ownerId, targetId) {
    return this.entity('friend_visibility', String(ownerId) + '|' + String(targetId));
  }

  acceptFriend(a, b, version) {
    return this.apply('friendship', pairKey(a, b), version, 'accept',
      { a: String(a), b: String(b), status: 'accepted' });
  }

  deleteFriend(actorId, targetId, version) {
    const relation = this.relation(actorId, targetId);
    if (!relation || relation.deleted || relation.payload.status !== 'accepted') {
      return { status: 'not-friends' };
    }
    return this.apply('friend_visibility', String(actorId) + '|' + String(targetId),
      version, 'delete', { ownerId: String(actorId), targetId: String(targetId) },
      { deleted: true });
  }

  readdFriend(actorId, targetId, version) {
    return this.apply('friend_visibility', String(actorId) + '|' + String(targetId),
      version, 'readd', { ownerId: String(actorId), targetId: String(targetId) },
      { deleted: false, allowAfterTombstone: true });
  }

  canMessage(senderId, targetId) {
    const relation = this.relation(senderId, targetId);
    if (!relation || relation.deleted || relation.payload.status !== 'accepted') {
      return { allowed: false, reason: 'not-friends' };
    }
    const visibility = this.visibility(senderId, targetId);
    if (visibility && visibility.deleted) {
      return { allowed: false, reason: 'sender-deleted-target' };
    }
    const targetVisibility = this.visibility(targetId, senderId);
    if (targetVisibility && targetVisibility.deleted) {
      return { allowed: false, reason: 'needs-verification' };
    }
    return { allowed: true };
  }

  hideChat(chatId, ownerId, version) {
    return this.apply('chat_visibility', String(chatId) + '|' + String(ownerId),
      version, 'hide', { chatId: String(chatId), ownerId: String(ownerId) },
      { deleted: true });
  }

  showChatForMessage(chatId, ownerId, version) {
    return this.apply('chat_visibility', String(chatId) + '|' + String(ownerId),
      version, 'message', { chatId: String(chatId), ownerId: String(ownerId) },
      { deleted: false, allowAfterTombstone: true });
  }

  chatVisible(chatId, ownerId) {
    const visibility = this.entity('chat_visibility', String(chatId) + '|' + String(ownerId));
    return !visibility || !visibility.deleted;
  }

  dismissGroup(chatId, version) {
    return this.apply('chat', String(chatId), version, 'dismiss',
      { chatId: String(chatId), state: 'dissolved' }, { deleted: true });
  }

  restoreGroup(chatId, version) {
    return this.apply('chat', String(chatId), version, 'restore',
      { chatId: String(chatId), state: 'active' }, { deleted: false });
  }

  claimTransfer(transferId, userId, version, eventId) {
    const identity = String(transferId);
    const current = this.entity('transfer', identity);
    if (current && !current.deleted && current.payload.state === 'claimed') {
      return { status: 'already-claimed', state: current };
    }
    return this.apply('transfer', identity, version, 'claim',
      { transferId: identity, userId: String(userId), state: 'claimed' },
      eventId ? { eventId } : {});
  }
}

module.exports = { ShardDomain, pairKey };
