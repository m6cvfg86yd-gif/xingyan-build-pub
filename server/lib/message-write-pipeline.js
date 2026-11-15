'use strict';

function requiredStore(options, name) {
  const store = options && options[name];
  if (!store) throw new Error(name + ' is required');
  return store;
}

class MessageWritePipeline {
  constructor(options) {
    const opts = options || {};
    this.reliability = requiredStore(opts, 'reliability');
    this.threadStore = requiredStore(opts, 'threadStore');
    this.now = typeof opts.now === 'function'
      ? opts.now
      : () => new Date().toISOString();
    this.chatTails = new Map();
  }

  async runExclusive(chatId, work) {
    const key = String(chatId || '');
    const previous = this.chatTails.get(key) || Promise.resolve();
    let release;
    const gate = new Promise((resolve) => { release = resolve; });
    const tail = previous.then(() => gate);
    this.chatTails.set(key, tail);
    await previous.catch(() => {});
    try {
      return await work();
    } finally {
      release();
      if (this.chatTails.get(key) === tail) this.chatTails.delete(key);
    }
  }

  async hasThreadMessage(chatId, messageId) {
    if (typeof this.threadStore.hasMessage === 'function') {
      return (await this.threadStore.hasMessage(chatId, messageId)) === true;
    }
    const rows = await this.threadStore.read(chatId);
    return (rows || []).some((row) => String(row && row.id || '') === messageId);
  }

  async append(chatId, input) {
    const chat = String(chatId || '');
    if (!chat) throw new Error('chatId is required');
    const message = Object.assign({}, input || {}, { chatId: chat });
    return this.runExclusive(chat, async () => {
      const reserved = this.reliability.reserveMessage(message);
      const persisted = reserved.message;
      const messageId = String(persisted && persisted.id || '');
      if (!messageId) throw new Error('reliability returned no message id');
      const alreadyStored = await this.hasThreadMessage(chat, messageId);
      if (alreadyStored) {
        return {
          ok: true,
          duplicate: reserved.duplicate === true,
          storageRepaired: false,
          eventId: reserved.eventId || '',
          message: persisted,
          seq: Number(reserved.seq)
        };
      }
      try {
        await this.threadStore.append(chat, persisted);
      } catch (error) {
        return {
          ok: false,
          durable: true,
          storagePending: true,
          duplicate: reserved.duplicate === true,
          eventId: reserved.eventId || '',
          message: persisted,
          seq: Number(reserved.seq),
          error: String(error && error.message || error)
        };
      }
      return {
        ok: true,
        duplicate: reserved.duplicate === true,
        storageRepaired: reserved.duplicate === true,
        eventId: reserved.eventId || '',
        message: persisted,
        seq: Number(reserved.seq)
      };
    });
  }

  async appendMany(chatId, inputs) {
    const results = [];
    for (const input of Array.isArray(inputs) ? inputs : []) {
      results.push(await this.append(chatId, input));
    }
    return results;
  }
}

module.exports = { MessageWritePipeline };
