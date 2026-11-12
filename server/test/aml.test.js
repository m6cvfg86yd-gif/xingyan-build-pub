'use strict';

const assert = require('assert');
const crypto = require('crypto');
const { AmlEngine } = require('../aml');

const state = {};
const journal = [];
let sequence = 0;
let nowMs = Date.parse('2026-11-12T02:00:00.000Z');
const uid = (prefix) => prefix + '_' + (++sequence);
const hmac = (payload) => crypto.createHmac('sha256', 'aml-test-secret')
  .update(payload).digest('hex');

const aml = new AmlEngine({
  readState: (name, fallback) => state[name] || fallback,
  writeState: (name, value) => {
    state[name] = JSON.parse(JSON.stringify(value));
  },
  appendJournal: (row) => journal.push(JSON.parse(JSON.stringify(row))),
  readJournal: (limit) => {
    const copy = JSON.parse(JSON.stringify(journal));
    return limit ? copy.slice(-limit) : copy;
  },
  hmac,
  uid,
  now: () => new Date(nowMs).toISOString()
});

const user = {
  id: 'u_payer',
  username: 'payer',
  nickname: '付款人',
  realName: '张三',
  idCardHash: hmac('idcard:test'),
  bankCards: [{ id: 'bank_1' }],
  createdAt: '2026-10-01T00:00:00.000Z',
  balance: 500000
};

aml.syncUser(user, {}, 'test');

const imported = aml.importLists([
  {
    type: 'sanctions',
    name: 'Bad Actor',
    aliases: 'Bad A.;BAD ACTOR',
    country: 'XX',
    source: '测试制裁名单',
    sourceRef: 'S-100'
  },
  {
    type: 'pep',
    name: 'Alice Politician',
    aliases: ['A. Politician'],
    source: '测试 PEP 名单',
    sourceRef: 'P-100'
  },
  {
    type: 'adverse_media',
    name: 'Risk Merchant',
    source: '测试舆情名单',
    sourceRef: 'M-100'
  },
  {
    type: 'internal',
    name: '内部黑名单用户',
    source: '内部',
    sourceRef: 'I-100'
  },
  {
    type: 'sanctions',
    name: 'ID Only Match',
    idHashes: [hmac('idcard:id-only-list')],
    source: '测试制裁名单',
    sourceRef: 'S-ID-100'
  }
], { actor: 'test-admin', source: 'unit-fixture' });

assert.strictEqual(imported.added.length, 5, 'five screening entries must import');
assert.strictEqual(imported.skipped.length, 0);

const fuzzy = aml.screen({ name: 'bad actor', country: 'XX' });
assert.ok(fuzzy.matches.some((x) => x.type === 'sanctions' && x.confidence >= 0.99),
  'normalized sanctions name must match exactly');

const aliasMatch = aml.screen({ name: 'A. Politician' });
assert.ok(aliasMatch.matches.some((x) => x.type === 'pep'),
  'PEP aliases must be screened');

const sanctionedUser = {
  id: 'u_sanctioned',
  username: 'blocked_user',
  nickname: '测试对象',
  realName: 'Bad Actor',
  idCardHash: hmac('idcard:blocked'),
  createdAt: '2026-10-01T00:00:00.000Z'
};
const blocked = aml.authorize(sanctionedUser, {
  channel: 'transfer',
  direction: 'out',
  amount: 10,
  counterpartyId: 'u_target',
  requestId: 'req_sanctioned'
}, { actor: 'u_sanctioned', ip: '127.0.0.1' });
assert.strictEqual(blocked.decision, 'block', 'sanctions hit must hard block');
assert.ok(blocked.reasons.some((x) => x.code === 'sanctions_match'));
assert.ok(blocked.caseId, 'hard block must open a case');
assert.strictEqual(aml.isMoneyOutRestricted('u_sanctioned').caseId !== '', true,
  'sanctions hit must restrict outgoing money');

const fuzzySanctions = aml.authorize({
  id: 'u_sanction_fuzzy',
  username: 'fuzzy_sanction',
  nickname: '近似名',
  realName: 'Bad Actorr',
  idCardHash: hmac('idcard:fuzzy-sanction'),
  createdAt: '2026-10-01T00:00:00.000Z'
}, {
  channel: 'transfer',
  direction: 'out',
  amount: 10,
  requestId: 'req_fuzzy_sanction'
}, { actor: 'u_sanction_fuzzy' });
assert.strictEqual(fuzzySanctions.decision, 'review',
  'fuzzy sanctions names must go to manual review instead of being hard blocked');
assert.ok(fuzzySanctions.reasons.some((x) => x.code === 'sanctions_fuzzy_match'));
assert.strictEqual(aml.isMoneyOutRestricted('u_sanction_fuzzy'), null,
  'fuzzy sanctions match must not freeze the account automatically');

const pepUser = {
  id: 'u_pep',
  username: 'pep_user',
  nickname: 'PEP',
  realName: 'Alice Politician',
  idCardHash: hmac('idcard:pep'),
  createdAt: '2026-10-01T00:00:00.000Z'
};
const pepReview = aml.authorize(pepUser, {
  channel: 'transfer',
  direction: 'out',
  amount: 100,
  counterpartyId: 'u_target',
  requestId: 'req_pep'
}, { actor: 'u_pep' });
assert.strictEqual(pepReview.decision, 'review', 'PEP hit must enter manual review');
assert.ok(pepReview.reasons.some((x) => x.code === 'pep_match'));

const large = aml.authorize(user, {
  channel: 'transfer',
  direction: 'out',
  amount: 5000,
  counterpartyId: 'u_target',
  requestId: 'req_large'
}, { actor: user.id });
assert.strictEqual(large.decision, 'review', 'large transfer must enter manual review');
assert.ok(large.reasons.some((x) => x.code === 'single_review_amount'));

const belowLimit = aml.authorize(user, {
  channel: 'transfer',
  direction: 'out',
  amount: 100,
  counterpartyId: 'u_target',
  requestId: 'req_ok'
}, { actor: user.id });
assert.strictEqual(belowLimit.decision, 'allow', 'ordinary small transfer must pass');
aml.complete(belowLimit.id, true, { externalRef: 'tr_ok' });
assert.strictEqual(aml.state.transactions.find((x) => x.id === belowLimit.id).status, 'completed');

const idOnlyBlocked = aml.authorize({
  id: 'u_id_only',
  username: 'id_only',
  nickname: '证件命中',
  realName: 'Different Name',
  idCardHash: hmac('idcard:id-only-list'),
  createdAt: '2026-10-01T00:00:00.000Z'
}, {
  channel: 'transfer',
  direction: 'out',
  amount: 10,
  requestId: 'id_hash_block'
}, { actor: 'u_id_only' });
assert.strictEqual(idOnlyBlocked.decision, 'block', 'ID hash must screen independently of name');
assert.ok(idOnlyBlocked.reasons.some((x) => x.code === 'sanctions_match'));

const adverse = aml.authorize({
  id: 'u_adverse',
  username: 'adverse',
  nickname: '舆情',
  realName: 'Risk Merchant',
  idCardHash: hmac('idcard:adverse'),
  createdAt: '2026-10-01T00:00:00.000Z'
}, {
  channel: 'transfer',
  direction: 'out',
  amount: 100,
  requestId: 'adverse_review'
}, { actor: 'u_adverse' });
assert.strictEqual(adverse.decision, 'review');
assert.ok(adverse.reasons.some((x) => x.code === 'adverse_media'));

aml.updateRules({ highRiskCountries: ['ZZ'] }, 'test-admin');
const highCountry = aml.authorize({
  id: 'u_country',
  username: 'country',
  nickname: '高风险地区',
  realName: 'Normal Person',
  idCardHash: hmac('idcard:country'),
  country: 'ZZ',
  createdAt: '2026-10-01T00:00:00.000Z'
}, {
  channel: 'transfer',
  direction: 'out',
  amount: 100,
  requestId: 'country_review'
}, { actor: 'u_country' });
assert.notStrictEqual(highCountry.decision, 'allow');
assert.ok(highCountry.reasons.some((x) => x.code === 'high_risk_country'));
aml.updateRules({ highRiskCountries: [] }, 'test-admin');

const newAccount = aml.authorize({
  id: 'u_new_account',
  username: 'new_account',
  nickname: '新账号',
  realName: 'New Person',
  idCardHash: hmac('idcard:new'),
  createdAt: new Date(nowMs - 86400000).toISOString()
}, {
  channel: 'transfer',
  direction: 'out',
  amount: 2000,
  requestId: 'new_account_review'
}, { actor: 'u_new_account' });
assert.notStrictEqual(newAccount.decision, 'allow');
assert.ok(newAccount.reasons.some((x) => x.code === 'new_account_amount'));

const forcedBlock = aml.authorize(user, {
  channel: 'transfer',
  direction: 'out',
  amount: 100000,
  requestId: 'forced_block'
}, { actor: user.id });
assert.strictEqual(forcedBlock.decision, 'block');
assert.ok(forcedBlock.reasons.some((x) => x.code === 'single_block_amount'));

const rapidUser = {
  id: 'u_rapid',
  username: 'rapid',
  nickname: '快进快出',
  realName: 'Rapid Flow',
  idCardHash: hmac('idcard:rapid'),
  createdAt: '2026-10-01T00:00:00.000Z'
};
const rapidIn = aml.authorize(rapidUser, {
  channel: 'transfer_claim',
  direction: 'in',
  amount: 1000,
  counterpartyId: 'u_rapid_source',
  requestId: 'rapid_in'
}, { actor: rapidUser.id });
assert.strictEqual(rapidIn.decision, 'allow');
aml.complete(rapidIn.id, true);
const rapidOut = aml.authorize(rapidUser, {
  channel: 'transfer',
  direction: 'out',
  amount: 750,
  counterpartyId: 'u_rapid_dest',
  requestId: 'rapid_out'
}, { actor: rapidUser.id });
assert.notStrictEqual(rapidOut.decision, 'allow');
assert.ok(rapidOut.reasons.some((x) => x.code === 'rapid_in_out'));

aml.updateRules({ velocityReviewCount: 3, structuringReviewCount: 3 }, 'test-admin');
assert.strictEqual(aml.rules().velocityReviewCount, 3);
for (let i = 0; i < 2; i += 1) {
  const d = aml.authorize(user, {
    channel: 'transfer',
    direction: 'out',
    amount: 10,
    counterpartyId: 'u_velocity_' + i,
    requestId: 'velocity_' + i
  }, { actor: user.id });
  if (d.decision === 'allow') aml.complete(d.id, true);
}
const velocity = aml.authorize(user, {
  channel: 'transfer',
  direction: 'out',
  amount: 10,
  counterpartyId: 'u_velocity_last',
  requestId: 'velocity_last'
}, { actor: user.id });
assert.notStrictEqual(velocity.decision, 'allow',
  'velocity rule must hold or block; completed='
    + aml.recentCompletedTransactions(user.id).length + ', rules='
    + JSON.stringify(aml.rules()));
assert.ok(velocity.reasons.some((x) => x.code === 'velocity'),
  'velocity reason missing: ' + JSON.stringify(velocity.reasons));

const structUser = {
  id: 'u_struct',
  username: 'structurer',
  nickname: '拆分测试',
  realName: '李四',
  idCardHash: hmac('idcard:struct'),
  bankCards: [{ id: 'bank_2' }],
  createdAt: '2026-10-01T00:00:00.000Z'
};
aml.updateRules({ velocityReviewCount: 99, structuringRatio: 0.8, structuringReviewCount: 3 }, 'test-admin');
for (let i = 0; i < 2; i += 1) {
  const d = aml.authorize(structUser, {
    channel: 'transfer',
    direction: 'out',
    amount: 4990,
    counterpartyId: 'u_struct_target',
    requestId: 'struct_ok_' + i
  }, { actor: structUser.id });
  assert.strictEqual(d.decision, 'allow', 'structuring baseline must pass before threshold');
  aml.complete(d.id, true);
}
const structured = aml.authorize(structUser, {
  channel: 'transfer',
  direction: 'out',
  amount: 4990,
  counterpartyId: 'u_struct_target',
  requestId: 'struct_alert'
}, { actor: structUser.id });
assert.notStrictEqual(structured.decision, 'allow', 'third near-threshold transfer must alert');
assert.ok(structured.reasons.some((x) => x.code === 'structuring'));

const caseDetail = aml.caseDetail(blocked.caseId);
assert.ok(caseDetail && caseDetail.case && caseDetail.transaction, 'case detail must include transaction evidence');

assert.throws(() => aml.reviewCase(blocked.caseId, 'restrict', { note: '冻结' }, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-a'
}), /另一个管理员/, 'dual review must reject self-approval');

const restricted = aml.reviewCase(blocked.caseId, 'restrict', {
  note: '监管复核期间限制转出',
  hours: 24
}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
});
assert.strictEqual(restricted.case.status, 'escalated');
assert.strictEqual(restricted.profile.restricted.moneyOut, true);

assert.throws(() => aml.reviewCase(blocked.caseId, 'close', {
  note: '尝试直接结案'
}, { actor: 'admin-a' }), /支付限制/, 'restricted case must not close without release');

assert.throws(() => aml.reviewCase(blocked.caseId, 'release', {
  note: '尝试绕过制裁命中'
}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
}), /制裁|黑名单/, 'release must not bypass an active sanctions match');

const pepRestricted = aml.reviewCase(pepReview.caseId, 'restrict', {
  note: 'PEP 持续尽调期间限制'
}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
});
assert.strictEqual(pepRestricted.profile.restricted.moneyOut, true);

const released = aml.reviewCase(pepReview.caseId, 'release', {
  note: 'PEP 来源审核完成，排除风险'
}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
});
assert.strictEqual(released.case.status, 'closed');
assert.strictEqual(released.profile.restricted.moneyOut, false);

const reportCase = aml.reviewCase(structured.caseId, 'report', {
  note: '提交可疑交易报告草稿',
  typology: 'STR 测试',
  narrative: '客户在短时间内连续拆分多笔交易。'
}, { actor: 'admin-a' });
assert.ok(reportCase.report && reportCase.report.id, 'report action must create a report');
assert.strictEqual(reportCase.report.status, 'draft');

const ready = aml.createReport(structured.caseId, {
  typology: 'STR 测试',
  narrative: '客户在 24 小时内连续发起三笔接近阈值的交易。',
  ready: true
}, { actor: 'admin-a' });
assert.strictEqual(ready.status, 'ready');

assert.throws(() => aml.submitReport(ready.id, {}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
}), /回执编号/, 'submitted report requires regulator reference');

const submitted = aml.submitReport(ready.id, {
  authorityRef: 'TEST-STR-20261112-001',
  note: '已人工报送测试受理机构'
}, {
  actor: 'admin-a',
  dualReview: true,
  secondReviewerId: 'admin-b'
});
assert.strictEqual(submitted.status, 'submitted');
assert.ok(submitted.authorityRef);

const exported = aml.exportReport(submitted.id);
assert.strictEqual(exported.schema, 'xingyan-aml-suspicious-transaction-v1');
assert.strictEqual(exported.report.id, submitted.id);
assert.ok(exported.transaction && exported.profile);

const listToDisable = aml.listLists({ q: 'Risk Merchant', active: true })[0];
assert.ok(listToDisable, 'imported adverse-media entry must be searchable');
aml.disableList(listToDisable.id, 'admin-a', '名单版本更新');
assert.strictEqual(aml.screen({ name: 'Risk Merchant' }).matches
  .some((x) => x.listId === listToDisable.id), false, 'disabled list entries must not match');

const integrity = aml.verifyEvents();
assert.strictEqual(integrity.ok, true,
  'AML evidence chain must verify: ' + JSON.stringify(integrity.failures));
assert.ok(integrity.checked >= 10);

const recoveredState = {};
const recovered = new AmlEngine({
  readState: (name, fallback) => recoveredState[name] || fallback,
  writeState: (name, value) => { recoveredState[name] = JSON.parse(JSON.stringify(value)); },
  appendJournal: () => {},
  readJournal: (limit) => {
    const copy = JSON.parse(JSON.stringify(journal));
    return limit ? copy.slice(-limit) : copy;
  },
  hmac,
  uid: (prefix) => prefix + '_recover_' + (++sequence),
  now: () => new Date(nowMs).toISOString()
});
assert.strictEqual(recovered.state.eventCount, journal[journal.length - 1].seq,
  'journal replay must recover the event sequence after a crash');
assert.strictEqual(recovered.state.lastEventHash, journal[journal.length - 1].hash,
  'journal replay must recover the last evidence hash');
assert.ok(recovered.state.transactions.some((x) => x.id === belowLimit.id && x.status === 'completed'),
  'journal replay must recover completed transaction state');

assert.throws(() => new AmlEngine({
  readState: () => ({
    version: 1,
    eventCount: 999,
    lastEventHash: 'state-ahead-of-journal'
  }),
  writeState: () => {},
  readJournal: () => JSON.parse(JSON.stringify(journal)),
  hmac,
  uid: (prefix) => prefix + '_truncated_' + (++sequence),
  now: () => new Date(nowMs).toISOString()
}), /证据日志比状态快照短/, 'startup must fail closed when evidence journal is truncated');

if (journal.length > 2) {
  journal[journal.length - 1].payload.tampered = true;
  const tampered = aml.verifyEvents();
  assert.strictEqual(tampered.ok, false, 'AML evidence chain must detect tampering');
  assert.ok(tampered.failures.some((x) => x.code === 'bad-hmac'));
}

const overview = aml.overview();
assert.ok(overview.stats.openCases >= 1);
assert.ok(overview.stats.profiles >= 4);
assert.ok(overview.stats.submittedReports >= 1);
assert.ok(overview.stats.restrictedProfiles >= 1, 'sanctions profile remains restricted by default');

console.log('aml: passed (' + journal.length + ' evidence events)');
