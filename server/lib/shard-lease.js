'use strict';

const fs = require('fs');
const path = require('path');

function sleep(ms) {
  Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms);
}

class ShardLeaseManager {
  constructor(options) {
    const opts = options || {};
    this.dataDir = String(opts.dataDir || '');
    this.ownerId = String(opts.ownerId || '');
    this.now = typeof opts.now === 'function' ? opts.now : () => Date.now();
    this.ttlMs = Math.max(1000, Number(opts.ttlMs) || 30000);
    if (!this.dataDir) throw new Error('lease dataDir is required');
    if (!this.ownerId) throw new Error('lease ownerId is required');
    this.dir = path.join(this.dataDir, 'leases');
    this.cache = new Map();
    fs.mkdirSync(this.dir, { recursive: true });
  }

  file(shard) {
    return path.join(this.dir, 'shard-' + Number(shard) + '.json');
  }

  lockFile(shard) {
    return path.join(this.dir, 'shard-' + Number(shard) + '.lock');
  }

  withLock(shard, operation) {
    const lock = this.lockFile(shard);
    let fd = null;
    for (let attempt = 0; attempt < 400; attempt += 1) {
      try {
        fd = fs.openSync(lock, 'wx');
        break;
      } catch (error) {
        if (!error || error.code !== 'EEXIST') throw error;
        try {
          const stat = fs.statSync(lock);
          if (Date.now() - stat.mtimeMs > 5000) fs.unlinkSync(lock);
        } catch (_) { /* retry */ }
        sleep(5);
      }
    }
    if (fd == null) throw new Error('shard lease lock timeout');
    try {
      return operation();
    } finally {
      fs.closeSync(fd);
      try { fs.unlinkSync(lock); } catch (_) { /* already removed */ }
    }
  }

  read(shard, force) {
    const file = this.file(shard);
    let signature = '';
    try {
      const stat = fs.statSync(file, { bigint: true });
      signature = String(stat.size) + ':' + String(stat.mtimeNs);
    } catch (_) {
      this.cache.delete(Number(shard));
      return null;
    }
    const cached = this.cache.get(Number(shard));
    if (!force && cached && cached.signature === signature) return cached.lease;
    try {
      const lease = JSON.parse(fs.readFileSync(file, 'utf8'));
      this.cache.set(Number(shard), { signature, lease });
      return lease;
    } catch (_) {
      this.cache.delete(Number(shard));
      return null;
    }
  }

  write(shard, lease) {
    const file = this.file(shard);
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, JSON.stringify(lease), 'utf8');
    fs.renameSync(temporary, file);
    this.cache.delete(Number(shard));
    return lease;
  }

  acquire(shard) {
    const index = Number(shard);
    return this.withLock(index, () => {
      const current = this.read(index, true);
      const at = Number(this.now());
      if (current && current.ownerId !== this.ownerId && Number(current.expiresAt) > at) {
        throw new Error('shard lease is held by ' + current.ownerId);
      }
      if (current && current.ownerId === this.ownerId && Number(current.expiresAt) > at) {
        return this.write(index, Object.assign({}, current, {
          expiresAt: at + this.ttlMs
        }));
      }
      return this.write(index, {
        shard: index,
        ownerId: this.ownerId,
        epoch: (Number(current && current.epoch) || 0) + 1,
        acquiredAt: at,
        expiresAt: at + this.ttlMs
      });
    });
  }

  validate(shard) {
    const current = this.read(shard, false);
    const at = Number(this.now());
    if (!current || current.ownerId !== this.ownerId) {
      return { ok: false, reason: 'not-owner', lease: current };
    }
    if (Number(current.expiresAt) <= at) {
      return { ok: false, reason: 'expired', lease: current };
    }
    return { ok: true, lease: current };
  }

  renew(shard) {
    const index = Number(shard);
    return this.withLock(index, () => {
      const current = this.read(index, true);
      const at = Number(this.now());
      if (!current || current.ownerId !== this.ownerId || Number(current.expiresAt) <= at) {
        throw new Error('cannot renew a lost shard lease');
      }
      return this.write(index, Object.assign({}, current, {
        expiresAt: at + this.ttlMs
      }));
    });
  }

  release(shard) {
    const index = Number(shard);
    return this.withLock(index, () => {
      const current = this.read(index, true);
      if (current && current.ownerId === this.ownerId) {
        fs.unlinkSync(this.file(index));
      }
      return true;
    });
  }
}

module.exports = { ShardLeaseManager };
