'use strict';

const { hash } = require('./shard-snapshot');

async function request(base, method, route, value, internalToken) {
  const headers = {};
  if (value !== undefined) headers['Content-Type'] = 'application/json';
  if (internalToken) headers['X-Internal-Token'] = internalToken;
  const response = await fetch(String(base).replace(/\/+$/, '') + route, {
    method,
    headers,
    body: value === undefined ? undefined : JSON.stringify(value)
  });
  let data = {};
  try {
    data = await response.json();
  } catch (_) { }
  if (!response.ok || data.ok === false) {
    const error = new Error(data.error || 'cell request failed');
    error.status = response.status;
    error.data = data;
    throw error;
  }
  return data;
}

function sequenceSummary(messages) {
  const ids = new Set();
  const sequences = new Set();
  const duplicateIds = [];
  const duplicateSequences = [];
  const gaps = [];
  let expected = 1;
  let firstSeq = 0;
  let lastSeq = 0;
  for (const message of messages || []) {
    const id = String(message && message.id || '');
    const seq = Math.floor(Number(message && message.seq) || 0);
    if (id && ids.has(id)) duplicateIds.push(id);
    if (id) ids.add(id);
    if (seq > 0 && sequences.has(seq)) duplicateSequences.push(seq);
    if (seq > 0) sequences.add(seq);
    if (!firstSeq || (seq > 0 && seq < firstSeq)) firstSeq = seq;
    if (seq > lastSeq) lastSeq = seq;
    if (seq !== expected) {
      if (gaps.length < 500) gaps.push({ expected, actual: seq });
    }
    expected = seq + 1;
  }
  return {
    count: (messages || []).length,
    firstSeq,
    lastSeq,
    duplicateIds,
    duplicateSequences,
    gaps,
    hash: hash(messages || [])
  };
}

async function readMessages(base, groupId, internalToken, pageSize, maxMessages) {
  const rows = [];
  let cursor = 0;
  while (true) {
    const page = await request(
      base,
      'GET',
      '/internal/groups/' + encodeURIComponent(groupId)
        + '/message-page?afterSeq=' + cursor + '&limit=' + pageSize,
      undefined,
      internalToken
    );
    rows.push(...(page.messages || []));
    if (rows.length > maxMessages) {
      throw new Error('pilot group exceeds max message limit');
    }
    if (!page.messages || !page.messages.length || !page.hasMore) break;
    const next = Number(page.lastSeq) || 0;
    if (next <= cursor) throw new Error('cell message cursor did not advance');
    cursor = next;
  }
  return rows;
}

async function inspectPilotGroup(options) {
  const opts = options || {};
  const sourceUrl = String(opts.sourceUrl || '').replace(/\/+$/, '');
  const targetUrl = String(opts.targetUrl || '').replace(/\/+$/, '');
  const groupId = String(opts.groupId || '').trim();
  const internalToken = String(opts.internalToken || '');
  const pageSize = Math.max(1, Math.min(500, Number(opts.pageSize) || 500));
  const maxMessages = Math.max(1, Number(opts.maxMessages) || 100000);
  if (!sourceUrl || !targetUrl || !groupId) {
    throw new Error('sourceUrl, targetUrl and groupId are required');
  }
  if (sourceUrl === targetUrl) throw new Error('source and target must be different cells');

  const [sourceHealth, targetHealth] = await Promise.all([
    request(sourceUrl, 'GET', '/internal/health', undefined, internalToken),
    request(targetUrl, 'GET', '/internal/health', undefined, internalToken)
  ]);
  const [sourceMeta, targetMeta, sourceMessages, targetMessages] = await Promise.all([
    request(sourceUrl, 'GET',
      '/internal/groups/' + encodeURIComponent(groupId) + '/export-metadata',
      undefined, internalToken),
    request(targetUrl, 'GET',
      '/internal/groups/' + encodeURIComponent(groupId) + '/export-metadata',
      undefined, internalToken),
    readMessages(sourceUrl, groupId, internalToken, pageSize, maxMessages),
    readMessages(targetUrl, groupId, internalToken, pageSize, maxMessages)
  ]);
  const sourceSequence = sequenceSummary(sourceMessages);
  const targetSequence = sequenceSummary(targetMessages);
  const checks = {
    sourceAndTargetDistinct: sourceUrl !== targetUrl,
    sourceHealthy: sourceHealth.ok === true,
    targetHealthy: targetHealth.ok === true,
    membershipPresent: Array.isArray(sourceMeta.membership)
      && sourceMeta.membership.length > 0,
    messagesPresent: sourceMessages.length > 0,
    uniqueMessageIds: sourceSequence.duplicateIds.length === 0,
    uniqueSequences: sourceSequence.duplicateSequences.length === 0,
    contiguousSequences: sourceSequence.gaps.length === 0
  };
  return {
    ok: Object.values(checks).every(Boolean),
    groupId,
    checks,
    source: {
      cellId: sourceHealth.cellId || '',
      messages: sourceSequence,
      membershipPeriods: (sourceMeta.membership || []).length,
      deletionHash: hash(sourceMeta.deletions || {}),
      cursorHash: hash(sourceMeta.cursors || [])
    },
    target: {
      cellId: targetHealth.cellId || '',
      messages: targetSequence,
      membershipPeriods: (targetMeta.membership || []).length
    }
  };
}

module.exports = {
  inspectPilotGroup,
  sequenceSummary
};
