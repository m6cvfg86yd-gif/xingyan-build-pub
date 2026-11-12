'use strict';

const VALID_STATUS = new Set(['pending', 'shadow', 'covered']);
const REQUIRED_FIELDS = ['id', 'method', 'path', 'family', 'entityTypes', 'events', 'status'];

function validateCoverageManifest(manifest) {
  const failures = [];
  const routes = manifest && Array.isArray(manifest.routes) ? manifest.routes : [];
  if (!routes.length) failures.push({ code: 'empty-manifest' });
  const ids = new Set();
  const endpoints = new Set();
  for (const route of routes) {
    const id = String(route && route.id || '');
    for (const field of REQUIRED_FIELDS) {
      if (route == null || route[field] == null || route[field] === '') {
        failures.push({ code: 'missing-field', id, field });
      }
    }
    if (!id || ids.has(id)) failures.push({ code: 'duplicate-or-empty-id', id });
    ids.add(id);
    const method = String(route && route.method || '').toUpperCase();
    const path = String(route && route.path || '');
    const endpointKey = method + ' ' + path;
    if (!method || !path || endpoints.has(endpointKey)) {
      failures.push({ code: 'duplicate-or-empty-route', id, endpoint: endpointKey });
    }
    endpoints.add(endpointKey);
    if (!VALID_STATUS.has(route && route.status)) {
      failures.push({ code: 'invalid-status', id, status: route && route.status });
    }
    if (!Array.isArray(route && route.entityTypes) || !route.entityTypes.length) {
      failures.push({ code: 'missing-entity-types', id });
    }
    if (!Array.isArray(route && route.events) || !route.events.length) {
      failures.push({ code: 'missing-events', id });
    }
  }
  return {
    ok: failures.length === 0,
    routes: routes.length,
    failures
  };
}

function coverageSummary(manifest) {
  const routes = manifest && Array.isArray(manifest.routes) ? manifest.routes : [];
  const byStatus = { pending: 0, shadow: 0, covered: 0 };
  const byFamily = {};
  for (const route of routes) {
    if (byStatus[route.status] != null) byStatus[route.status] += 1;
    const family = String(route.family || 'unknown');
    byFamily[family] = (byFamily[family] || 0) + 1;
  }
  return {
    total: routes.length,
    ready: routes.length > 0 && byStatus.covered === routes.length,
    byStatus,
    byFamily
  };
}

module.exports = { validateCoverageManifest, coverageSummary };
