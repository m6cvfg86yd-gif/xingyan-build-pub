'use strict';

class GroupCellRouter {
  constructor(options) {
    const opts = options || {};
    this.cells = opts.cells || {};
    this.routeStore = opts.routeStore || null;
    this.routes = new Map();
    if (!Object.keys(this.cells).length) throw new Error('at least one cell is required');
  }

  assign(groupId, cellId, epoch) {
    const group = String(groupId || '');
    const cell = String(cellId || '');
    if (!group || !this.cells[cell]) throw new Error('valid group and cell are required');
    const previous = this.route(group);
    const nextEpoch = epoch == null
      ? (previous ? previous.epoch + 1 : 1)
      : Math.floor(Number(epoch) || 0);
    if (nextEpoch <= 0) throw new Error('positive epoch is required');
    if (previous && nextEpoch < previous.epoch) {
      return { ok: false, stale: true, previous };
    }
    const route = {
      groupId: group,
      cellId: cell,
      epoch: nextEpoch,
      status: 'active',
      sourceCellId: '',
      targetCellId: ''
    };
    if (this.routeStore) {
      const stored = this.routeStore.set(route);
      if (!stored.ok) return stored;
      this.routes.set(group, stored.route);
      return { ok: true, route: stored.route };
    }
    this.routes.set(group, route);
    return { ok: true, route };
  }

  beginMigration(groupId, targetCellId, epoch) {
    const group = String(groupId || '');
    const target = String(targetCellId || '');
    const current = this.route(group);
    if (!current) throw new Error('group is not assigned');
    if (!this.cells[target]) throw new Error('target cell does not exist');
    const nextEpoch = epoch == null ? current.epoch + 1 : Math.floor(Number(epoch) || 0);
    if (nextEpoch <= current.epoch) {
      return { ok: false, stale: true, route: current };
    }
    const route = Object.assign({}, current, {
      epoch: nextEpoch,
      status: 'migrating',
      sourceCellId: current.cellId,
      targetCellId: target
    });
    if (this.routeStore) {
      const stored = this.routeStore.set(route);
      if (!stored.ok) return stored;
      this.routes.set(group, stored.route);
      return { ok: true, route: stored.route };
    }
    this.routes.set(group, route);
    return { ok: true, route };
  }

  completeMigration(groupId, epoch) {
    const group = String(groupId || '');
    const current = this.route(group);
    if (!current || current.status !== 'migrating') {
      return { ok: false, route: current || null, error: 'group is not migrating' };
    }
    const value = Math.floor(Number(epoch) || 0);
    if (value !== current.epoch) {
      return { ok: false, stale: true, route: current };
    }
    const route = Object.assign({}, current, {
      cellId: current.targetCellId,
      status: 'active',
      sourceCellId: '',
      targetCellId: ''
    });
    if (this.routeStore) {
      const stored = this.routeStore.set(route);
      if (!stored.ok) return stored;
      this.routes.set(group, stored.route);
      return { ok: true, route: stored.route };
    }
    this.routes.set(group, route);
    return { ok: true, route };
  }

  route(groupId) {
    const group = String(groupId || '');
    if (this.routeStore) {
      const stored = this.routeStore.get(group);
      if (stored) this.routes.set(group, stored);
      return stored;
    }
    return this.routes.get(group) || null;
  }

  owner(groupId) {
    const route = this.route(groupId);
    if (!route) return null;
    return route.status === 'migrating' ? route.sourceCellId : route.cellId;
  }

  cellFor(groupId) {
    const owner = this.owner(groupId);
    return owner ? this.cells[owner] : null;
  }

  checkOwner(groupId, claimedCellId) {
    const route = this.route(groupId);
    if (!route) return { ok: false, reason: 'unassigned', route: null };
    const owner = this.owner(groupId);
    if (String(claimedCellId || '') !== owner) {
      return { ok: false, reason: 'wrong-cell', owner, route };
    }
    return { ok: true, owner, route };
  }

  async send(groupId, claimedCellId, senderId, message) {
    const owner = this.checkOwner(groupId, claimedCellId);
    if (!owner.ok) return { ok: false, routed: false, error: owner.reason };
    const result = await this.cells[owner.owner].send(groupId, senderId, message);
    if (!result.ok || owner.route.status !== 'migrating') return result;
    const target = this.cells[owner.route.targetCellId];
    if (!target) {
      return Object.assign({}, result, {
        dualWrite: { ok: false, error: 'target-cell-missing' }
      });
    }
    try {
      const mirrored = await target.mirror(
        groupId,
        senderId,
        result.message,
        { fanout: false }
      );
      return Object.assign({}, result, { dualWrite: mirrored });
    } catch (error) {
      return Object.assign({}, result, {
        dualWrite: {
          ok: false,
          error: String(error && error.message || error)
        }
      });
    }
  }

  async read(groupId, claimedCellId, options) {
    const owner = this.checkOwner(groupId, claimedCellId);
    if (!owner.ok) return {
      ok: false,
      routed: false,
      error: owner.reason,
      messages: [],
      lastSeq: 0,
      hasMore: false
    };
    return this.cells[owner.owner].read(Object.assign({}, options, { groupId }));
  }

  async markRead(groupId, claimedCellId, userId, deviceId, seq) {
    const owner = this.checkOwner(groupId, claimedCellId);
    if (!owner.ok) return false;
    return this.cells[owner.owner].markRead(groupId, userId, deviceId, seq);
  }
}

module.exports = { GroupCellRouter };
