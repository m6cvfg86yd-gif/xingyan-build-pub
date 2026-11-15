'use strict';

class DeviceSyncService {
  constructor(options) {
    const opts = options || {};
    this.reliability = opts.reliability;
    this.listChats = opts.listChats;
    if (!this.reliability) throw new Error('reliability is required');
    if (typeof this.listChats !== 'function') throw new Error('listChats is required');
  }

  state(options) {
    const opts = options || {};
    const userId = String(opts.userId || '');
    const deviceId = String(opts.deviceId || '');
    const cursor = String(opts.cursor || '');
    const limit = Math.max(1, Math.min(200, Number(opts.limit) || 50));
    if (!userId || !deviceId) throw new Error('userId and deviceId are required');
    const chats = this.listChats(userId)
      .filter((chat) => chat && chat.id)
      .sort((left, right) => String(left.id) < String(right.id) ? -1
        : (String(left.id) > String(right.id) ? 1 : 0));
    const start = cursor
      ? chats.findIndex((chat) => String(chat.id) > cursor)
      : 0;
    const offset = start < 0 ? chats.length : start;
    const page = chats.slice(offset, offset + limit);
    const items = page.map((chat) => {
      const chatId = String(chat.id);
      const lastSeq = Math.max(
        Math.max(0, Number(chat.seq) || 0),
        this.reliability.lastSequence(chatId)
      );
      const deviceCursor = this.reliability.deviceCursor(userId, deviceId, chatId);
      return {
        chatId,
        lastSeq,
        deliveredSeq: deviceCursor.deliveredSeq,
        readSeq: deviceCursor.readSeq,
        hasDelta: lastSeq > deviceCursor.deliveredSeq
      };
    });
    return {
      deviceId,
      items,
      nextCursor: items.length ? items[items.length - 1].chatId : cursor,
      hasMore: offset + page.length < chats.length
    };
  }

  acknowledge(options) {
    const opts = options || {};
    const userId = String(opts.userId || '');
    const deviceId = String(opts.deviceId || '');
    if (!userId || !deviceId) throw new Error('userId and deviceId are required');
    const memberChats = new Set(
      this.listChats(userId).map((chat) => String(chat && chat.id || ''))
    );
    const accepted = [];
    const rejected = [];
    for (const row of Array.isArray(opts.items) ? opts.items : []) {
      const chatId = String(row && row.chatId || '');
      const seq = Math.max(0, Math.floor(Number(row && row.seq) || 0));
      if (!chatId || !seq || !memberChats.has(chatId)) {
        rejected.push({ chatId, seq, reason: 'not-a-member-or-invalid-seq' });
      } else {
        accepted.push({ chatId, seq });
      }
    }
    return {
      acknowledged: this.reliability.ackDeviceMany(userId, deviceId, accepted),
      rejected
    };
  }
}

module.exports = { DeviceSyncService };
