'use strict';

/*
 * 星言反洗钱（AML）核心。
 *
 * 边界：
 * - 这里是可运行的产品级 AML 工作流，不是监管认证，也不替代持牌机构、律师或
 *   第三方名单服务。制裁/PEP/负面新闻名单由运营导入，最终报送必须人工复核。
 * - 资金交易只在 authorize() 返回 allow 后继续。命中制裁、内部黑名单或账户
 *   支付限制时默认拒绝；命中金额、频率、拆分、对手方等规则时进入人工审核。
 * - 证据事件写入独立、只追加的 journal；状态文件仅保存可检索的当前快照。
 */

const crypto = require('crypto');

const DEFAULT_RULES = Object.freeze({
  enabled: true,
  failClosed: true,
  singleReviewAmount: 5000,
  singleBlockAmount: 100000,
  rollingDayReviewAmount: 20000,
  rollingDayBlockAmount: 200000,
  highRiskReviewAmount: 1000,
  newAccountDays: 7,
  newAccountReviewAmount: 2000,
  velocityWindowMinutes: 10,
  velocityReviewCount: 8,
  pairWindowHours: 24,
  pairReviewCount: 3,
  structuringWindowHours: 24,
  structuringRatio: 0.8,
  structuringReviewCount: 3,
  rapidFlowWindowHours: 24,
  rapidFlowRatio: 0.7,
  reviewScore: 40,
  blockScore: 90,
  rescreenHours: 24,
  retentionYears: 10,
  highRiskCountries: [],
  kycRequiredForOutgoing: true
});

const KYC_NAMES = {
  unverified: '未实名',
  basic: '基础实名',
  enhanced: '增强实名',
  pending_review: '待持续尽调',
  rejected: '尽调未通过'
};

const RISK_NAMES = {
  low: '低风险',
  medium: '中风险',
  high: '高风险',
  critical: '严重风险'
};

const LIST_TYPES = ['sanctions', 'pep', 'adverse_media', 'internal'];
const LIST_TYPE_NAMES = {
  sanctions: '制裁名单',
  pep: '政治公众人物',
  adverse_media: '负面新闻',
  internal: '内部黑名单'
};

function isoNow(value) {
  const t = value == null ? Date.now() : value;
  const d = t instanceof Date ? t : new Date(t);
  return Number.isNaN(d.getTime()) ? new Date().toISOString() : d.toISOString();
}

function finite(value, fallback) {
  const n = Number(value);
  return Number.isFinite(n) ? n : fallback;
}

function clamp(value, min, max) {
  return Math.max(min, Math.min(max, value));
}

function money(value) {
  const n = Number(value);
  if (!Number.isFinite(n)) return 0;
  return Math.round(n * 100) / 100;
}

function cleanText(value, max) {
  return String(value == null ? '' : value).trim().slice(0, max || 200);
}

function normalizeName(value) {
  return String(value == null ? '' : value)
    .normalize('NFKC')
    .toLowerCase()
    .replace(/[^\p{L}\p{N}]+/gu, '');
}

function normalizeCountry(value) {
  return cleanText(value, 12).toUpperCase();
}

function nameSimilarity(a, b) {
  const x = normalizeName(a);
  const y = normalizeName(b);
  if (!x || !y) return 0;
  if (x === y) return 1;
  const shorter = x.length <= y.length ? x : y;
  const longer = x.length > y.length ? x : y;
  if (shorter.length >= 3 && longer.indexOf(shorter) >= 0) {
    return 0.92 + 0.06 * (shorter.length / longer.length);
  }
  const rows = x.length + 1;
  const cols = y.length + 1;
  const prev = new Array(cols);
  const curr = new Array(cols);
  for (let j = 0; j < cols; j += 1) prev[j] = j;
  for (let i = 1; i < rows; i += 1) {
    curr[0] = i;
    for (let j = 1; j < cols; j += 1) {
      const cost = x[i - 1] === y[j - 1] ? 0 : 1;
      curr[j] = Math.min(prev[j] + 1, curr[j - 1] + 1, prev[j - 1] + cost);
    }
    for (let j = 0; j < cols; j += 1) prev[j] = curr[j];
  }
  return 1 - prev[cols - 1] / Math.max(x.length, y.length);
}

function splitAliases(value) {
  if (Array.isArray(value)) {
    return Array.from(new Set(value.map((x) => cleanText(x, 120)).filter(Boolean))).slice(0, 30);
  }
  return Array.from(new Set(String(value == null ? '' : value)
    .split(/[|;；、\n]+/)
    .map((x) => cleanText(x, 120))
    .filter(Boolean))).slice(0, 30);
}

function splitIdHashes(value) {
  if (Array.isArray(value)) {
    return Array.from(new Set(value.map((x) => cleanText(x, 200).toLowerCase()).filter(Boolean))).slice(0, 20);
  }
  return Array.from(new Set(String(value == null ? '' : value)
    .split(/[|;；,\s]+/)
    .map((x) => cleanText(x, 200).toLowerCase())
    .filter(Boolean))).slice(0, 20);
}

function parseCsv(text) {
  const rows = [];
  let row = [];
  let field = '';
  let quoted = false;
  const src = String(text == null ? '' : text).replace(/^\uFEFF/, '');
  for (let i = 0; i < src.length; i += 1) {
    const ch = src[i];
    if (quoted) {
      if (ch === '"' && src[i + 1] === '"') {
        field += '"';
        i += 1;
      } else if (ch === '"') {
        quoted = false;
      } else {
        field += ch;
      }
    } else if (ch === '"') {
      quoted = true;
    } else if (ch === ',') {
      row.push(field);
      field = '';
    } else if (ch === '\n') {
      row.push(field.replace(/\r$/, ''));
      if (row.some((x) => String(x).trim())) rows.push(row);
      row = [];
      field = '';
    } else {
      field += ch;
    }
  }
  row.push(field.replace(/\r$/, ''));
  if (row.some((x) => String(x).trim())) rows.push(row);
  if (!rows.length) return [];
  if (rows[0].length === 1 && rows[0][0].split(/\t/).length > 1) {
    return rows.map((one) => one[0].split(/\t/));
  }
  return rows;
}

function parseListInput(value) {
  if (Array.isArray(value)) return value;
  const text = String(value == null ? '' : value).trim();
  if (!text) return [];
  if (text[0] === '[' || text[0] === '{') {
    const parsed = JSON.parse(text);
    if (Array.isArray(parsed)) return parsed;
    if (parsed && Array.isArray(parsed.items)) return parsed.items;
    if (parsed && parsed.name) return [parsed];
  }
  const rows = parseCsv(text);
  if (!rows.length) return [];
  const header = rows[0].map((x) => String(x).trim().toLowerCase());
  const known = ['type', 'name', 'aliases', 'idhashes', 'country', 'dob', 'source', 'sourceref'];
  const hasHeader = known.some((x) => header.indexOf(x) >= 0);
  const offset = hasHeader ? 1 : 0;
  return rows.slice(offset).map((cols) => ({
    type: hasHeader ? cols[header.indexOf('type')] : cols[0],
    name: hasHeader ? cols[header.indexOf('name')] : cols[1],
    aliases: hasHeader ? cols[header.indexOf('aliases')] : cols[2],
    idHashes: hasHeader ? cols[header.indexOf('idhashes')] : cols[3],
    country: hasHeader ? cols[header.indexOf('country')] : cols[4],
    dob: hasHeader ? cols[header.indexOf('dob')] : cols[5],
    source: hasHeader ? cols[header.indexOf('source')] : cols[6],
    sourceRef: hasHeader ? cols[header.indexOf('sourceref')] : cols[7]
  }));
}

function normalizeListEntry(entry, metadata) {
  const type = LIST_TYPES.indexOf(String(entry && entry.type || '').toLowerCase()) >= 0
    ? String(entry.type).toLowerCase() : 'internal';
  const name = cleanText(entry && entry.name, 160);
  const idHashes = splitIdHashes(entry && entry.idHashes);
  if (!name && !idHashes.length) return null;
  const aliases = splitAliases(entry && entry.aliases);
  const now = metadata.now;
  return {
    id: metadata.uid('aml_list'),
    type,
    name,
    aliases,
    idHashes,
    country: normalizeCountry(entry && entry.country),
    dob: cleanText(entry && entry.dob, 20),
    source: cleanText(entry && entry.source, 120) || '人工导入',
    sourceRef: cleanText(entry && entry.sourceRef, 200),
    note: cleanText(entry && entry.note, 300),
    active: true,
    createdAt: now,
    createdBy: metadata.actor || 'system',
    disabledAt: '',
    disabledBy: '',
    disableReason: ''
  };
}

class AmlEngine {
  constructor(options) {
    const o = options || {};
    this.dataDir = o.dataDir || '';
    this.readState = o.readState;
    this.writeState = o.writeState;
    this.appendJournal = o.appendJournal;
    this.readJournal = o.readJournal;
    this.hmac = o.hmac;
    this.uid = o.uid;
    this.now = o.now || isoNow;
    this.state = this.loadState();
    this.recoverJournalHead();
  }

  emptyState() {
    return {
      version: 1,
      profiles: {},
      lists: [],
      cases: [],
      reports: [],
      transactions: [],
      rules: Object.assign({}, DEFAULT_RULES),
      lastEventHash: '',
      eventCount: 0,
      updatedAt: this.now()
    };
  }

  loadState() {
    let state = null;
    try {
      state = this.readState ? this.readState('aml.json', null) : null;
    } catch (error) {
      throw new Error('AML 状态读取失败：' + String(error && error.message || error));
    }
    if (!state || typeof state !== 'object') return this.emptyState();
    const base = this.emptyState();
    const out = Object.assign(base, state);
    out.profiles = state.profiles && typeof state.profiles === 'object' ? state.profiles : {};
    out.lists = Array.isArray(state.lists) ? state.lists : [];
    out.cases = Array.isArray(state.cases) ? state.cases : [];
    out.reports = Array.isArray(state.reports) ? state.reports : [];
    out.transactions = Array.isArray(state.transactions) ? state.transactions : [];
    out.rules = Object.assign({}, DEFAULT_RULES, state.rules || {});
    out.eventCount = Math.max(0, finite(state.eventCount, 0));
    return out;
  }

  save() {
    this.state.updatedAt = this.now();
    if (this.writeState) this.writeState('aml.json', this.state);
  }

  clockMs() {
    const t = Date.parse(String(this.now()));
    return Number.isFinite(t) ? t : Date.now();
  }

  recoverJournalHead() {
    if (!this.readJournal) return;
    let rows = [];
    try {
      rows = this.readJournal(0);
    } catch (error) {
      throw new Error('AML 证据日志读取失败：' + String(error && error.message || error));
    }
    if (!Array.isArray(rows) || !rows.length) return;
    let changed = false;
    let last = null;
    for (const event of rows) {
      if (!event || event.corrupt) continue;
      last = event;
      const payload = event.payload || {};
      const tx = payload.transaction;
      if (event.type === 'transaction.authorized' && tx && tx.id) {
        if (!this.state.transactions.some((x) => x.id === tx.id)) {
          this.state.transactions.push(tx);
          changed = true;
        }
        if (payload.caseId && !this.getCase(payload.caseId)) {
          const reasons = Array.isArray(payload.reasons) ? payload.reasons : [];
          this.state.cases.unshift({
            id: payload.caseId,
            userId: tx.userId,
            username: tx.username || '',
            nickname: '',
            transactionId: tx.id,
            status: 'open',
            severity: tx.decision === 'block' ? 'critical' : 'medium',
            decision: tx.decision,
            score: Number(tx.score) || 0,
            reasonCodes: reasons.map((x) => x.code),
            reasons,
            amount: tx.amount,
            channel: tx.channel,
            direction: tx.direction,
            counterpartyId: tx.counterpartyId || '',
            counterpartyName: tx.counterpartyName || '',
            assignedTo: '',
            reviewers: [],
            resolution: '',
            reportId: '',
            createdAt: tx.at || event.at,
            updatedAt: event.at,
            closedAt: ''
          });
          changed = true;
        }
      }
      if ((event.type === 'transaction.completed' || event.type === 'transaction.failed')
          && payload.transactionId) {
        const hit = this.state.transactions.find((x) => x.id === payload.transactionId);
        const nextStatus = event.type === 'transaction.completed' ? 'completed' : 'failed';
        if (hit && hit.status !== nextStatus) {
          hit.status = nextStatus;
          hit.completedAt = event.at;
          if (payload.externalRef) hit.externalRef = payload.externalRef;
          changed = true;
        }
      }
    }
    if (last) {
      const journalSeq = Number(last.seq) || 0;
      const stateSeq = Number(this.state.eventCount) || 0;
      if (stateSeq > journalSeq) {
        throw new Error('AML 证据日志比状态快照短，拒绝启动以避免丢失审计记录');
      }
      if (stateSeq === journalSeq && this.state.lastEventHash
          && this.state.lastEventHash !== last.hash) {
        throw new Error('AML 证据日志链头与状态快照不一致，拒绝启动');
      }
      if (Number(last.seq) > Number(this.state.eventCount || 0)) {
        this.state.eventCount = Number(last.seq);
        changed = true;
      }
      if (last.hash && last.hash !== this.state.lastEventHash) {
        this.state.lastEventHash = last.hash;
        changed = true;
      }
    }
    if (changed) this.save();
  }

  rules() {
    return Object.assign({}, DEFAULT_RULES, this.state.rules || {});
  }

  updateRules(patch, actor) {
    const next = Object.assign({}, this.rules());
    const numeric = [
      'singleReviewAmount', 'singleBlockAmount', 'rollingDayReviewAmount',
      'rollingDayBlockAmount', 'highRiskReviewAmount', 'newAccountDays',
      'newAccountReviewAmount', 'velocityWindowMinutes', 'velocityReviewCount',
      'pairWindowHours', 'pairReviewCount', 'structuringWindowHours',
      'structuringRatio', 'structuringReviewCount', 'rapidFlowWindowHours',
      'rapidFlowRatio', 'reviewScore', 'blockScore', 'rescreenHours',
      'retentionYears'
    ];
    numeric.forEach((key) => {
      if (patch && patch[key] !== undefined && Number.isFinite(Number(patch[key]))) {
        next[key] = Number(patch[key]);
      }
    });
    if (patch && patch.enabled !== undefined) next.enabled = !!patch.enabled;
    /* 故障关闭必须始终开启。AML 不可用时继续动钱不符合资金系统安全边界。 */
    next.failClosed = true;
    if (patch && patch.kycRequiredForOutgoing !== undefined) {
      next.kycRequiredForOutgoing = !!patch.kycRequiredForOutgoing;
    }
    if (patch && patch.highRiskCountries !== undefined) {
      next.highRiskCountries = Array.isArray(patch.highRiskCountries)
        ? patch.highRiskCountries.map(normalizeCountry).filter(Boolean).slice(0, 100)
        : String(patch.highRiskCountries).split(/[,\s|;]+/).map(normalizeCountry).filter(Boolean).slice(0, 100);
    }
    next.singleBlockAmount = Math.max(next.singleReviewAmount, next.singleBlockAmount);
    next.rollingDayBlockAmount = Math.max(next.rollingDayReviewAmount, next.rollingDayBlockAmount);
    next.reviewScore = clamp(next.reviewScore, 1, 100);
    next.blockScore = clamp(next.blockScore, next.reviewScore, 200);
    next.structuringRatio = clamp(next.structuringRatio, 0.1, 1);
    next.rapidFlowRatio = clamp(next.rapidFlowRatio, 0.1, 1);
    const before = this.state.rules;
    this.state.rules = next;
    this.audit('rules.updated', {
      actor: actor || 'system',
      before,
      after: next
    });
    this.save();
    return next;
  }

  ensureProfile(user, extra) {
    if (!user || !user.id) throw new Error('AML 用户画像缺少 userId');
    const now = this.now();
    const current = this.state.profiles[user.id] || {
      userId: user.id,
      username: cleanText(user.username, 80),
      nickname: cleanText(user.nickname, 80),
      name: '',
      idHash: '',
      kycLevel: 0,
      kycStatus: 'unverified',
      manualRisk: '',
      riskLevel: 'low',
      riskScore: 0,
      pep: false,
      sanctioned: false,
      adverseMedia: false,
      country: '',
      nationality: '',
      occupation: '',
      sourceOfFunds: '',
      restricted: {
        moneyOut: false,
        until: 0,
        reason: '',
        caseId: ''
      },
      lastScreenedAt: '',
      nextReviewAt: '',
      createdAt: now,
      updatedAt: now
    };
    current.username = cleanText(user.username, 80) || current.username;
    current.nickname = cleanText(user.nickname, 80) || current.nickname;
    if (user.realName) current.name = cleanText(user.realName, 160);
    if (user.idCardHash) current.idHash = cleanText(user.idCardHash, 200).toLowerCase();
    const bankCount = Array.isArray(user.bankCards) ? user.bankCards.length : 0;
    if (current.idHash) {
      current.kycLevel = Math.max(Number(current.kycLevel) || 0, bankCount > 0 ? 2 : 1);
      if (!current.kycStatus || current.kycStatus === 'unverified') {
        current.kycStatus = bankCount > 0 ? 'enhanced' : 'basic';
      }
    } else if (!current.idHash) {
      current.kycStatus = current.kycStatus === 'rejected' ? 'rejected' : 'unverified';
    }
    ['country', 'nationality', 'occupation', 'sourceOfFunds'].forEach((key) => {
      if (extra && extra[key] !== undefined) current[key] = cleanText(extra[key], key === 'sourceOfFunds' ? 300 : 80);
      else if (user[key] !== undefined && user[key] !== null && current[key] === '') {
        current[key] = cleanText(user[key], key === 'sourceOfFunds' ? 300 : 80);
      }
    });
    current.country = normalizeCountry(current.country);
    current.nationality = normalizeCountry(current.nationality);
    if (extra && extra.contactChanged === true) current.contactChangedAt = now;
    if (current.restricted && current.restricted.until && current.restricted.until < this.clockMs()) {
      current.restricted = {
        moneyOut: false,
        until: 0,
        reason: '',
        caseId: current.restricted.caseId || ''
      };
    }
    current.updatedAt = now;
    this.state.profiles[user.id] = current;
    return current;
  }

  syncUser(user, extra, actor) {
    if (user && user.amlExempt) {
      return { profile: null, screening: { matches: [] }, skipped: 'legacy-customer-exempt' };
    }
    const profile = this.ensureProfile(user, extra);
    const screening = this.screen({
      name: profile.name,
      idHash: profile.idHash,
      dob: user && user.dob,
      country: profile.country || profile.nationality
    });
    this.applyScreening(profile, screening);
    this.audit('profile.synced', {
      userId: profile.userId,
      actor: actor || 'system',
      profile: this.publicProfile(profile),
      matchCount: screening.matches.length
    });
    this.save();
    return { profile: this.publicProfile(profile), screening };
  }

  screen(input) {
    const name = cleanText(input && input.name, 160);
    const idHash = cleanText(input && input.idHash, 200).toLowerCase();
    const dob = cleanText(input && input.dob, 20);
    const country = normalizeCountry(input && input.country);
    const matches = [];
    for (const item of this.state.lists) {
      if (!item || !item.active) continue;
      let confidence = 0;
      let matchedOn = '';
      if (idHash && Array.isArray(item.idHashes) && item.idHashes.indexOf(idHash) >= 0) {
        confidence = 1;
        matchedOn = 'idHash';
      } else if (name) {
        const best = Math.max(nameSimilarity(name, item.name),
          ...(Array.isArray(item.aliases) ? item.aliases.map((x) => nameSimilarity(name, x)) : [0]));
        if (best >= 0.88) {
          confidence = best;
          matchedOn = 'name';
        }
      }
      if (!matchedOn || confidence < 0.88) continue;
      if (matchedOn !== 'idHash' && dob && item.dob
          && String(dob).slice(0, 10) !== String(item.dob).slice(0, 10)) {
        confidence = Math.max(0.5, confidence - 0.45);
      }
      if (matchedOn !== 'idHash' && country && item.country
          && country !== normalizeCountry(item.country)) {
        confidence = Math.max(0.5, confidence - 0.08);
      }
      const exact = matchedOn === 'idHash' || confidence >= 0.999;
      matches.push({
        listId: item.id,
        type: item.type,
        typeName: LIST_TYPE_NAMES[item.type] || item.type,
        name: item.name,
        matchedOn,
        exact,
        confidence: Math.round(confidence * 1000) / 1000,
        source: item.source || '',
        sourceRef: item.sourceRef || ''
      });
    }
    matches.sort((a, b) => b.confidence - a.confidence);
    return {
      screenedAt: this.now(),
      matches: matches.slice(0, 20)
    };
  }

  applyScreening(profile, screening) {
    const matches = screening && Array.isArray(screening.matches) ? screening.matches : [];
    profile.sanctionMatches = matches.filter((x) => x.type === 'sanctions' || x.type === 'internal');
    profile.pepMatches = matches.filter((x) => x.type === 'pep');
    profile.adverseMediaMatches = matches.filter((x) => x.type === 'adverse_media');
    profile.sanctioned = profile.sanctionMatches.some((x) => x.exact);
    profile.sanctionPotential = profile.sanctionMatches.some((x) => !x.exact);
    profile.pep = profile.pepMatches.length > 0;
    profile.adverseMedia = profile.adverseMediaMatches.length > 0;
    profile.lastScreenedAt = screening ? screening.screenedAt : '';
    const hours = Math.max(1, finite(this.rules().rescreenHours, 24));
    profile.nextReviewAt = new Date(this.clockMs() + hours * 3600000).toISOString();
    if (profile.sanctioned) profile.riskLevel = 'critical';
    else if (profile.sanctionPotential && profile.riskLevel !== 'critical') profile.riskLevel = 'high';
    else if (profile.pep && profile.riskLevel !== 'critical') profile.riskLevel = 'high';
    else if (profile.adverseMedia && profile.riskLevel === 'low') profile.riskLevel = 'medium';
    profile.updatedAt = this.now();
    return profile;
  }

  publicProfile(profile) {
    if (!profile) return null;
    return {
      userId: profile.userId,
      username: profile.username,
      nickname: profile.nickname,
      nameMask: profile.name ? (profile.name.slice(0, 1) + '*'.repeat(Math.max(1, profile.name.length - 1))) : '',
      kycLevel: Number(profile.kycLevel) || 0,
      kycStatus: profile.kycStatus || 'unverified',
      kycStatusName: KYC_NAMES[profile.kycStatus] || profile.kycStatus,
      riskLevel: profile.riskLevel || 'low',
      riskLevelName: RISK_NAMES[profile.riskLevel] || profile.riskLevel,
      riskScore: Math.round(Number(profile.riskScore) || 0),
      lastRiskScore: Math.round(Number(profile.lastRiskScore) || 0),
      pep: !!profile.pep,
      sanctioned: !!profile.sanctioned,
      sanctionPotential: !!profile.sanctionPotential,
      adverseMedia: !!profile.adverseMedia,
      country: profile.country || '',
      nationality: profile.nationality || '',
      occupation: profile.occupation || '',
      sourceOfFunds: profile.sourceOfFunds || '',
      restricted: Object.assign({}, profile.restricted || {}),
      lastScreenedAt: profile.lastScreenedAt || '',
      nextReviewAt: profile.nextReviewAt || '',
      sanctionMatches: profile.sanctionMatches || [],
      pepMatches: profile.pepMatches || [],
      adverseMediaMatches: profile.adverseMediaMatches || [],
      createdAt: profile.createdAt,
      updatedAt: profile.updatedAt
    };
  }

  isMoneyOutRestricted(userId) {
    const profile = this.state.profiles[String(userId || '')];
    if (!profile || !profile.restricted || !profile.restricted.moneyOut) return null;
    if (profile.restricted.until && profile.restricted.until <= this.clockMs()) {
      profile.restricted.moneyOut = false;
      profile.restricted.until = 0;
      this.save();
      return null;
    }
    return {
      reason: profile.restricted.reason || '账号处于反洗钱审查限制中',
      caseId: profile.restricted.caseId || '',
      until: profile.restricted.until || 0
    };
  }

  recentCompletedTransactions(userId) {
    const cutoff = this.clockMs() - Math.max(
      finite(this.rules().rollingDayWindowHours, 24),
      finite(this.rules().pairWindowHours, 24),
      finite(this.rules().structuringWindowHours, 24),
      finite(this.rules().rapidFlowWindowHours, 24)
    ) * 3600000;
    return this.state.transactions.filter((x) => x && x.status === 'completed'
      && Date.parse(x.at || '') >= cutoff
      && (!userId || x.userId === userId || x.counterpartyId === userId));
  }

  authorize(user, transaction, context) {
    const tx = transaction || {};
    if (user && user.amlExempt) {
      return {
        id: '',
        decision: 'allow',
        allowed: true,
        score: 0,
        reasons: [],
        profile: null,
        bypassed: true,
        exempt: true
      };
    }
    const rules = this.rules();
    if (!rules.enabled) {
      return {
        id: this.uid('aml_tx'),
        decision: 'allow',
        allowed: true,
        score: 0,
        reasons: [],
        profile: null,
        bypassed: true
      };
    }
    const profile = this.ensureProfile(user, context && context.profile);
    const amount = money(tx.amount);
    if (!(amount > 0)) throw new Error('AML 交易金额必须大于 0');
    const now = this.now();
    const screening = this.screen({
      name: profile.name,
      idHash: profile.idHash,
      dob: user && user.dob,
      country: profile.country || profile.nationality
    });
    this.applyScreening(profile, screening);
    const reasons = [];
    const add = (code, label, severity, score, evidence) => {
      reasons.push({
        code,
        label,
        severity,
        score: Number(score) || 0,
        evidence: evidence || ''
      });
    };

    const hardSanctions = screening.matches.filter((x) =>
      (x.type === 'sanctions' || x.type === 'internal') && x.exact);
    const fuzzySanctions = screening.matches.filter((x) =>
      (x.type === 'sanctions' || x.type === 'internal') && !x.exact);
    if (hardSanctions.length) {
      add('sanctions_match', '命中制裁或内部黑名单', 'block', 120,
        hardSanctions.map((x) => x.typeName + '：' + x.name
          + '（' + Math.round(x.confidence * 100) + '%）').join('；'));
    } else if (fuzzySanctions.length) {
      add('sanctions_fuzzy_match', '疑似命中制裁或内部黑名单，需人工排除误报', 'review', 75,
        fuzzySanctions.map((x) => x.typeName + '：' + x.name
          + '（' + Math.round(x.confidence * 100) + '%）').join('；'));
    }
    if (screening.matches.some((x) => x.type === 'pep')) {
      add('pep_match', '命中政治公众人物名单', 'review', 60,
        screening.matches.filter((x) => x.type === 'pep').map((x) => x.name).join('；'));
    }
    if (screening.matches.some((x) => x.type === 'adverse_media')) {
      add('adverse_media', '命中负面新闻或风险舆情', 'review', 35,
        screening.matches.filter((x) => x.type === 'adverse_media').map((x) => x.name).join('；'));
    }
    const restriction = this.isMoneyOutRestricted(profile.userId);
    if (restriction && (tx.direction || 'out') === 'out') {
      add('account_restricted', '账号支付权限处于 AML 审查限制中', 'block', 120, restriction.reason);
    }
    if (profile.kycStatus === 'rejected') {
      add('kyc_rejected', '持续尽调未通过', 'block', 110, '需要管理员重新审核身份资料');
    }
    if (rules.kycRequiredForOutgoing && (tx.direction || 'out') === 'out'
        && Number(profile.kycLevel) < 1) {
      add('kyc_required', '未完成基础实名', 'block', 100, '转出资金前必须完成实名认证');
    }
    if (amount >= rules.singleBlockAmount) {
      add('single_block_amount', '单笔金额触发强制审核阈值', 'block', 95,
        '¥' + amount.toFixed(2) + ' ≥ ¥' + Number(rules.singleBlockAmount).toFixed(2));
    } else if (amount >= rules.singleReviewAmount) {
      add('single_review_amount', '单笔大额交易', 'review', 45,
        '¥' + amount.toFixed(2) + ' ≥ ¥' + Number(rules.singleReviewAmount).toFixed(2));
    }

    const completed = this.recentCompletedTransactions(profile.userId);
    const dayCutoff = this.clockMs() - 24 * 3600000;
    const dayOutgoing = completed.filter((x) => x.userId === profile.userId
      && x.direction === 'out' && Date.parse(x.at || '') >= dayCutoff);
    const dayAmount = money(dayOutgoing.reduce((sum, x) => sum + money(x.amount), 0) + amount);
    if (dayAmount >= rules.rollingDayBlockAmount) {
      add('rolling_day_block', '24 小时累计金额触发强制审核阈值', 'block', 100,
        '累计 ¥' + dayAmount.toFixed(2));
    } else if (dayAmount >= rules.rollingDayReviewAmount) {
      add('rolling_day_review', '24 小时累计金额偏高', 'review', 45,
        '累计 ¥' + dayAmount.toFixed(2));
    }

    const velocityCutoff = this.clockMs() - Math.max(1, rules.velocityWindowMinutes) * 60000;
    const velocity = completed.filter((x) => x.userId === profile.userId
      && Date.parse(x.at || '') >= velocityCutoff).length + 1;
    if (velocity >= rules.velocityReviewCount) {
      add('velocity', '短时间内交易频率异常', velocity >= rules.velocityReviewCount + 3 ? 'block' : 'review',
        velocity >= rules.velocityReviewCount + 3 ? 90 : 40,
        rules.velocityWindowMinutes + ' 分钟内第 ' + velocity + ' 笔');
    }

    if (tx.counterpartyId) {
      const pairCutoff = this.clockMs() - Math.max(1, rules.pairWindowHours) * 3600000;
      const pairCount = completed.filter((x) => x.userId === profile.userId
        && x.counterpartyId === tx.counterpartyId
        && Date.parse(x.at || '') >= pairCutoff).length + 1;
      if (pairCount >= rules.pairReviewCount) {
        add('counterparty_velocity', '同一对手方交易过于频繁', 'review', 35,
          rules.pairWindowHours + ' 小时内第 ' + pairCount + ' 笔');
        const counterpart = this.state.profiles[tx.counterpartyId];
        if (counterpart && (counterpart.sanctioned || counterpart.riskLevel === 'critical')) {
          add('counterparty_high_risk', '对手方处于高风险或制裁命中状态', 'block', 100,
            counterpart.nickname || counterpart.username || tx.counterpartyId);
        }
      }
    } else if (tx.counterpartyName) {
      const counterpartMatch = this.screen({ name: tx.counterpartyName });
      if (counterpartMatch.matches.some((x) =>
        (x.type === 'sanctions' || x.type === 'internal') && x.exact)) {
        add('counterparty_sanctions_match', '对手方疑似命中制裁或内部黑名单', 'block', 110,
          counterpartMatch.matches.map((x) => x.name).join('；'));
      } else if (counterpartMatch.matches.some((x) =>
        (x.type === 'sanctions' || x.type === 'internal') && !x.exact)) {
        add('counterparty_sanctions_fuzzy', '对手方疑似命中制裁名单，需人工排除误报', 'review', 70,
          counterpartMatch.matches.map((x) => x.name).join('；'));
      }
    }

    const structureCutoff = this.clockMs() - Math.max(1, rules.structuringWindowHours) * 3600000;
    const reviewFloor = rules.singleReviewAmount * rules.structuringRatio;
    const nearThreshold = completed.filter((x) => x.userId === profile.userId
      && x.direction === 'out'
      && Date.parse(x.at || '') >= structureCutoff
      && money(x.amount) >= reviewFloor
      && money(x.amount) < rules.singleReviewAmount)
      .length + (amount >= reviewFloor && amount < rules.singleReviewAmount ? 1 : 0);
    if (nearThreshold >= rules.structuringReviewCount) {
      add('structuring', '疑似拆分交易规避单笔阈值', 'review', 55,
        rules.structuringWindowHours + ' 小时内出现 ' + nearThreshold + ' 笔接近阈值的交易');
    }

    const rapidCutoff = this.clockMs() - Math.max(1, rules.rapidFlowWindowHours) * 3600000;
    const rapidIn = money(completed.filter((x) => x.userId === profile.userId
      && x.direction === 'in' && Date.parse(x.at || '') >= rapidCutoff)
      .reduce((sum, x) => sum + money(x.amount), 0));
    if ((tx.direction || 'out') === 'out' && rapidIn > 0
        && amount + dayAmount >= rapidIn * rules.rapidFlowRatio) {
      add('rapid_in_out', '资金快进快出', 'review', 45,
        rules.rapidFlowWindowHours + ' 小时内流入 ¥' + rapidIn.toFixed(2)
          + '，当前转出 ¥' + amount.toFixed(2));
    }

    if (rules.highRiskCountries.indexOf(profile.country) >= 0
        || rules.highRiskCountries.indexOf(profile.nationality) >= 0) {
      add('high_risk_country', '高风险国家或地区', 'review', 45,
        profile.country || profile.nationality);
    }
    const accountAgeDays = user && user.createdAt
      ? Math.max(0, (this.clockMs() - Date.parse(user.createdAt)) / 86400000) : 0;
    if (accountAgeDays < rules.newAccountDays && amount >= rules.newAccountReviewAmount) {
      add('new_account_amount', '新账号大额交易', 'review', 35,
        '账号 ' + accountAgeDays.toFixed(0) + ' 天，金额 ¥' + amount.toFixed(2));
    }
    if (profile.riskLevel === 'high' || profile.riskLevel === 'critical') {
      if (amount >= rules.highRiskReviewAmount) {
        add('high_risk_profile_amount', '高风险客户交易', 'review', 40,
          '风险等级 ' + (RISK_NAMES[profile.riskLevel] || profile.riskLevel));
      }
    }

    const score = Math.min(200, reasons.reduce((sum, x) => sum + x.score, 0));
    const hasBlock = reasons.some((x) => x.severity === 'block') || score >= rules.blockScore;
    const hasReview = reasons.some((x) => x.severity === 'review') || score >= rules.reviewScore;
    const decision = hasBlock ? 'block' : (hasReview ? 'review' : 'allow');
    profile.lastRiskScore = score;
    profile.riskScore = score;
    if (decision === 'block' && (profile.sanctioned || reasons.some((x) => x.code === 'sanctions_match'))) {
      profile.riskLevel = 'critical';
      profile.restricted = {
        moneyOut: true,
        until: 0,
        reason: '命中制裁或内部黑名单，等待人工复核',
        caseId: profile.restricted && profile.restricted.caseId || ''
      };
    } else if (decision === 'review' && profile.riskLevel === 'low') {
      profile.riskLevel = 'medium';
    }

    const id = this.uid('aml_tx');
    const transactionRow = {
      id,
      userId: profile.userId,
      username: profile.username,
      channel: cleanText(tx.channel, 40) || 'payment',
      direction: tx.direction === 'in' ? 'in' : 'out',
      amount,
      counterpartyId: cleanText(tx.counterpartyId, 80),
      counterpartyName: cleanText(tx.counterpartyName, 160),
      requestId: cleanText(tx.requestId, 100),
      externalRef: cleanText(tx.externalRef, 100),
      note: cleanText(tx.note, 300),
      decision,
      score,
      status: decision === 'allow' ? 'pending' : (decision === 'block' ? 'blocked' : 'held'),
      at: now,
      completedAt: '',
      context: {
        ip: cleanText(context && context.ip, 80),
        device: cleanText(context && context.device, 200),
        source: cleanText(context && context.source, 80)
      }
    };
    this.state.transactions.push(transactionRow);
    if (this.state.transactions.length > 20000) {
      this.state.transactions = this.state.transactions.slice(-20000);
    }
    let amlCase = null;
    if (decision !== 'allow') {
      const severity = decision === 'block' ? 'critical'
        : (score >= 70 ? 'high' : (score >= 40 ? 'medium' : 'low'));
      amlCase = {
        id: this.uid('aml_case'),
        userId: profile.userId,
        username: profile.username,
        nickname: profile.nickname,
        transactionId: id,
        status: 'open',
        severity,
        decision,
        score,
        reasonCodes: reasons.map((x) => x.code),
        reasons,
        amount,
        channel: transactionRow.channel,
        direction: transactionRow.direction,
        counterpartyId: transactionRow.counterpartyId,
        counterpartyName: transactionRow.counterpartyName,
        assignedTo: '',
        reviewers: [],
        resolution: '',
        reportId: '',
        createdAt: now,
        updatedAt: now,
        closedAt: ''
      };
      this.state.cases.unshift(amlCase);
      transactionRow.caseId = amlCase.id;
      if (profile.restricted && !profile.restricted.caseId) profile.restricted.caseId = amlCase.id;
    }
    profile.updatedAt = now;
    const event = this.audit('transaction.authorized', {
      transaction: transactionRow,
      caseId: amlCase ? amlCase.id : '',
      profile: {
        userId: profile.userId,
        riskLevel: profile.riskLevel,
        riskScore: profile.riskScore,
        kycStatus: profile.kycStatus
      },
      screening,
      reasons,
      actor: cleanText(context && context.actor, 80) || 'system'
    });
    if (this.state.profiles[profile.userId]) this.state.profiles[profile.userId] = profile;
    this.save();
    return {
      id,
      eventId: event.id,
      caseId: amlCase ? amlCase.id : '',
      decision,
      allowed: decision === 'allow',
      score,
      reasons,
      profile: this.publicProfile(profile),
      screening
    };
  }

  complete(transactionId, success, detail) {
    const row = this.state.transactions.find((x) => x.id === transactionId);
    if (!row) return null;
    if (row.status !== 'pending') return row;
    row.status = success ? 'completed' : 'failed';
    row.completedAt = this.now();
    if (detail && detail.externalRef) row.externalRef = cleanText(detail.externalRef, 100);
    if (detail && detail.note) row.note = cleanText(detail.note, 300);
    this.audit(success ? 'transaction.completed' : 'transaction.failed', {
      transactionId,
      userId: row.userId,
      externalRef: row.externalRef,
      success: !!success,
      detail: detail || {}
    });
    this.save();
    return row;
  }

  importLists(input, metadata) {
    const rows = parseListInput(input);
    if (!rows.length) throw new Error('没有可导入的名单记录');
    if (rows.length > 10000) throw new Error('单次最多导入 10000 条名单');
    const actor = cleanText(metadata && metadata.actor, 80) || 'system';
    const seen = new Set(this.state.lists.map((x) => [
      x.type, normalizeName(x.name), x.sourceRef || '', (x.idHashes || []).join(',')
    ].join('|')));
    const added = [];
    const skipped = [];
    rows.forEach((inputRow) => {
      const row = normalizeListEntry(inputRow, {
        now: this.now(),
        uid: this.uid,
        actor
      });
      if (!row) {
        skipped.push({ reason: '缺少姓名或证件哈希', row: inputRow });
        return;
      }
      const key = [row.type, normalizeName(row.name), row.sourceRef || '', row.idHashes.join(',')].join('|');
      if (seen.has(key)) {
        skipped.push({ reason: '重复记录', row: row.name || row.idHashes[0] });
        return;
      }
      seen.add(key);
      this.state.lists.unshift(row);
      added.push(row);
    });
    this.audit('lists.imported', {
      actor,
      added: added.length,
      skipped: skipped.length,
      source: cleanText(metadata && metadata.source, 120)
    });
    this.save();
    return { added, skipped, total: this.state.lists.length };
  }

  disableList(id, actor, reason) {
    const row = this.state.lists.find((x) => x.id === id);
    if (!row) throw new Error('名单记录不存在');
    if (!row.active) return row;
    row.active = false;
    row.disabledAt = this.now();
    row.disabledBy = cleanText(actor, 80) || 'system';
    row.disableReason = cleanText(reason, 300);
    this.audit('lists.disabled', {
      id,
      actor: row.disabledBy,
      reason: row.disableReason,
      entry: row
    });
    this.save();
    return row;
  }

  listLists(options) {
    const o = options || {};
    const q = cleanText(o.q, 120).toLowerCase();
    const type = cleanText(o.type, 30);
    const active = o.active === undefined ? null : !!o.active;
    return this.state.lists.filter((x) => {
      if (type && x.type !== type) return false;
      if (active !== null && !!x.active !== active) return false;
      if (!q) return true;
      return [x.name, (x.aliases || []).join(' '), x.source, x.sourceRef]
        .join(' ').toLowerCase().indexOf(q) >= 0;
    }).slice(0, Math.max(1, Math.min(5000, Number(o.limit) || 500)));
  }

  updateProfile(userId, patch, actor) {
    const profile = this.state.profiles[userId];
    if (!profile) throw new Error('AML 用户画像不存在');
    const before = this.publicProfile(profile);
    if (patch) {
      ['country', 'nationality', 'occupation', 'sourceOfFunds'].forEach((key) => {
        if (patch[key] !== undefined) profile[key] = cleanText(patch[key], key === 'sourceOfFunds' ? 300 : 80);
      });
      profile.country = normalizeCountry(profile.country);
      profile.nationality = normalizeCountry(profile.nationality);
      if (patch.manualRisk !== undefined) {
        profile.manualRisk = ['low', 'medium', 'high', 'critical'].indexOf(patch.manualRisk) >= 0
          ? patch.manualRisk : '';
      }
      if (patch.kycStatus !== undefined && KYC_NAMES[patch.kycStatus]) {
        profile.kycStatus = patch.kycStatus;
      }
      if (profile.manualRisk) profile.riskLevel = profile.manualRisk;
    }
    profile.updatedAt = this.now();
    this.audit('profile.updated', {
      userId,
      actor: cleanText(actor, 80) || 'system',
      before,
      after: this.publicProfile(profile)
    });
    this.save();
    return this.publicProfile(profile);
  }

  listProfiles(options) {
    const o = options || {};
    const q = cleanText(o.q, 120).toLowerCase();
    const risk = cleanText(o.risk, 20);
    return Object.values(this.state.profiles)
      .filter((p) => !risk || p.riskLevel === risk)
      .filter((p) => !q || [p.username, p.nickname, p.name, p.country]
        .join(' ').toLowerCase().indexOf(q) >= 0)
      .map((p) => this.publicProfile(p))
      .sort((a, b) => {
        const rank = { critical: 4, high: 3, medium: 2, low: 1 };
        return (rank[b.riskLevel] || 0) - (rank[a.riskLevel] || 0)
          || String(b.updatedAt).localeCompare(String(a.updatedAt));
      })
      .slice(0, Math.max(1, Math.min(1000, Number(o.limit) || 200)));
  }

  getCase(id) {
    return this.state.cases.find((x) => x.id === id) || null;
  }

  listCases(options) {
    const o = options || {};
    const status = cleanText(o.status, 30);
    const severity = cleanText(o.severity, 20);
    const q = cleanText(o.q, 120).toLowerCase();
    return this.state.cases.filter((x) => {
      if (status && x.status !== status) return false;
      if (severity && x.severity !== severity) return false;
      if (!q) return true;
      return [x.id, x.username, x.nickname, x.transactionId, x.reasonCodes.join(' ')]
        .join(' ').toLowerCase().indexOf(q) >= 0;
    }).slice(0, Math.max(1, Math.min(2000, Number(o.limit) || 200)));
  }

  caseDetail(id) {
    const row = this.getCase(id);
    if (!row) return null;
    const tx = this.state.transactions.find((x) => x.id === row.transactionId) || null;
    const profile = this.state.profiles[row.userId];
    const report = row.reportId ? this.state.reports.find((x) => x.id === row.reportId) || null : null;
    return {
      case: row,
      transaction: tx,
      profile: profile ? this.publicProfile(profile) : null,
      report
    };
  }

  reviewCase(id, action, body, metadata) {
    const row = this.getCase(id);
    if (!row) throw new Error('AML 案件不存在');
    const act = cleanText(action, 40);
    const note = cleanText(body && (body.note || body.resolution), 1000);
    const actor = cleanText(metadata && metadata.actor, 80) || 'system';
    if (!note && ['clear', 'close', 'restrict', 'release', 'escalate', 'report'].indexOf(act) >= 0) {
      throw new Error('这个处置必须填写复核意见');
    }
    if (metadata && metadata.dualReview && ['restrict', 'release', 'close_report'].indexOf(act) >= 0) {
      const second = cleanText(metadata.secondReviewerId, 80);
      if (!second || second === cleanText(actor, 80)) {
        throw new Error('该处置需要另一个管理员进行二次复核');
      }
    }
    if (act === 'assign') {
      row.assignedTo = cleanText(body && body.assignedTo, 80) || actor;
      row.status = 'reviewing';
    } else if (act === 'escalate') {
      row.status = 'escalated';
      row.severity = 'critical';
      const profile = this.state.profiles[row.userId];
      if (profile) {
        profile.riskLevel = 'critical';
        profile.updatedAt = this.now();
      }
    } else if (act === 'restrict') {
      row.status = 'escalated';
      const profile = this.state.profiles[row.userId];
      if (!profile) throw new Error('案件用户画像不存在');
      const hours = Math.max(0, Math.min(8760, finite(body && body.hours, 0)));
      profile.restricted = {
        moneyOut: true,
        until: hours ? this.clockMs() + hours * 3600000 : 0,
        reason: note,
        caseId: row.id
      };
      profile.riskLevel = 'high';
      profile.updatedAt = this.now();
      row.resolution = note;
    } else if (act === 'release' || act === 'clear') {
      const profile = this.state.profiles[row.userId];
      if (profile) {
        if (profile.sanctioned) {
          throw new Error('账号仍命中有效制裁或内部黑名单，不能直接解除；请先处理名单命中并重新筛查');
        }
        profile.restricted = {
          moneyOut: false,
          until: 0,
          reason: '',
          caseId: ''
        };
        profile.manualRisk = profile.manualRisk || 'low';
        profile.riskLevel = profile.manualRisk;
        profile.updatedAt = this.now();
      }
      row.status = 'closed';
      row.resolution = note || (act === 'clear' ? '复核后排除风险' : '解除限制');
      row.closedAt = this.now();
    } else if (act === 'close') {
      const profile = this.state.profiles[row.userId];
      if (profile && profile.restricted && profile.restricted.moneyOut) {
        throw new Error('账号仍有 AML 支付限制，请先走 release 解除后再结案');
      }
      row.status = 'closed';
      row.resolution = note;
      row.closedAt = this.now();
    } else if (act === 'report') {
      row.status = 'escalated';
      const report = this.createReport(row.id, body, { actor });
      row.reportId = report.id;
      row.resolution = note;
    } else {
      throw new Error('未知处置动作');
    }
    const review = {
      at: this.now(),
      action: act,
      actor,
      secondReviewerId: cleanText(metadata && metadata.secondReviewerId, 80),
      note
    };
    row.reviewers = Array.isArray(row.reviewers) ? row.reviewers : [];
    row.reviewers.push(review);
    row.updatedAt = this.now();
    this.audit('case.reviewed', { caseId: row.id, action: act, note, actor });
    this.save();
    return this.caseDetail(row.id);
  }

  autoNarrative(row, body) {
    const t = this.state.transactions.find((x) => x.id === row.transactionId) || {};
    const reasons = (row.reasons || []).map((x) => x.label + '（' + x.evidence + '）').join('；');
    return cleanText(body && body.narrative, 8000) || [
      '客户 ' + (row.nickname || row.username || row.userId) + ' 于 ' + row.createdAt
        + ' 通过 ' + row.channel + ' 发起' + (row.direction === 'in' ? '收款' : '付款')
        + '，金额 ' + money(row.amount).toFixed(2) + ' 元。',
      '系统风险评分 ' + row.score + '，处置建议 ' + row.decision + '。',
      '触发指标：' + reasons,
      '交易编号：' + (row.transactionId || '') + '；对手方：' + (row.counterpartyName || row.counterpartyId || '未提供')
    ].join('\n');
  }

  createReport(caseId, body, metadata) {
    const row = this.getCase(caseId);
    if (!row) throw new Error('AML 案件不存在');
    const actor = cleanText(metadata && metadata.actor, 80) || 'system';
    let report = row.reportId
      ? this.state.reports.find((x) => x.id === row.reportId)
      : null;
    if (!report) {
      report = {
        id: this.uid('aml_report'),
        caseId,
        userId: row.userId,
        subject: row.nickname || row.username || row.userId,
        status: 'draft',
        typology: cleanText(body && body.typology, 120) || '可疑交易',
        narrative: '',
        indicators: (row.reasons || []).map((x) => x.code),
        amount: money(row.amount),
        currency: 'CNY',
        transactionIds: [row.transactionId],
        createdAt: this.now(),
        createdBy: actor,
        submittedAt: '',
        authorityRef: '',
        reviews: []
      };
      this.state.reports.unshift(report);
      row.reportId = report.id;
    }
    report.typology = cleanText(body && body.typology, 120) || report.typology;
    report.narrative = this.autoNarrative(row, body);
    report.status = body && body.ready === true ? 'ready' : 'draft';
    report.updatedAt = this.now();
    report.reviews = Array.isArray(report.reviews) ? report.reviews : [];
    report.reviews.push({
      at: this.now(),
      actor,
      action: report.status === 'ready' ? 'ready' : 'draft_saved'
    });
    this.audit('report.saved', {
      reportId: report.id,
      caseId,
      actor,
      status: report.status
    });
    this.save();
    return report;
  }

  submitReport(id, body, metadata) {
    const report = this.state.reports.find((x) => x.id === id);
    if (!report) throw new Error('AML 报告不存在');
    if (report.status === 'submitted') throw new Error('报告已经登记为已报送');
    const actor = cleanText(metadata && metadata.actor, 80) || 'system';
    if (metadata && metadata.dualReview) {
      const second = cleanText(metadata.secondReviewerId, 80);
      if (!second || second === actor) throw new Error('报送登记需要另一个管理员进行二次复核');
    }
    const ref = cleanText(body && body.authorityRef, 200);
    if (!ref) throw new Error('请填写监管或受理机构回执编号');
    report.status = 'submitted';
    report.submittedAt = this.now();
    report.authorityRef = ref;
    report.submittedBy = actor;
    report.note = cleanText(body && body.note, 1000);
    this.audit('report.submitted', {
      reportId: report.id,
      caseId: report.caseId,
      actor,
      authorityRef: ref
    });
    this.save();
    return report;
  }

  exportReport(id) {
    const report = this.state.reports.find((x) => x.id === id);
    if (!report) throw new Error('AML 报告不存在');
    const row = this.getCase(report.caseId);
    const tx = row ? this.state.transactions.find((x) => x.id === row.transactionId) : null;
    return {
      generatedAt: this.now(),
      schema: 'xingyan-aml-suspicious-transaction-v1',
      report,
      case: row,
      transaction: tx,
      profile: row ? this.publicProfile(this.state.profiles[row.userId]) : null
    };
  }

  sweep(users, options) {
    const list = Array.isArray(users) ? users : [];
    const limit = Math.max(1, Math.min(2000, Number(options && options.limit) || 200));
    let screened = 0;
    for (const user of list.slice(0, limit)) {
      if (!user || !user.id || user.bot || user.amlExempt) continue;
      const profile = this.ensureProfile(user);
      const due = !profile.lastScreenedAt
        || Date.parse(profile.lastScreenedAt || '') <= this.clockMs() - this.rules().rescreenHours * 3600000;
      if (!due) continue;
      const screening = this.screen({
        name: profile.name,
        idHash: profile.idHash,
        country: profile.country || profile.nationality
      });
      this.applyScreening(profile, screening);
      screened += 1;
    }
    if (screened) {
      this.audit('screening.sweep', { screened });
      this.save();
    }
    return { screened };
  }

  overview() {
    const activeLists = this.state.lists.filter((x) => x.active);
    const open = this.state.cases.filter((x) => ['open', 'reviewing', 'escalated'].indexOf(x.status) >= 0);
    return {
      generatedAt: this.now(),
      rules: this.rules(),
      stats: {
        profiles: Object.keys(this.state.profiles).length,
        activeListEntries: activeLists.length,
        sanctions: activeLists.filter((x) => x.type === 'sanctions').length,
        pep: activeLists.filter((x) => x.type === 'pep').length,
        adverseMedia: activeLists.filter((x) => x.type === 'adverse_media').length,
        internal: activeLists.filter((x) => x.type === 'internal').length,
        openCases: open.length,
        criticalCases: open.filter((x) => x.severity === 'critical').length,
        highRiskProfiles: Object.values(this.state.profiles)
          .filter((x) => x.riskLevel === 'high' || x.riskLevel === 'critical').length,
        restrictedProfiles: Object.values(this.state.profiles)
          .filter((x) => x.restricted && x.restricted.moneyOut).length,
        draftReports: this.state.reports.filter((x) => x.status !== 'submitted').length,
        submittedReports: this.state.reports.filter((x) => x.status === 'submitted').length,
        transactions24h: this.state.transactions
          .filter((x) => Date.parse(x.at || '') >= this.clockMs() - 86400000).length
      },
      recentCases: this.state.cases.slice(0, 12),
      recentReports: this.state.reports.slice(0, 8)
    };
  }

  audit(type, payload) {
    const body = {
      seq: this.state.eventCount + 1,
      id: this.uid('aml_evt'),
      at: this.now(),
      type: cleanText(type, 80),
      payload: payload || {},
      prevHash: this.state.lastEventHash || ''
    };
    body.hash = this.hmac
      ? this.hmac(JSON.stringify(body))
      : crypto.createHash('sha256').update(JSON.stringify(body)).digest('hex');
    if (this.appendJournal) this.appendJournal(body);
    this.state.eventCount = body.seq;
    this.state.lastEventHash = body.hash;
    return body;
  }

  events(limit) {
    if (!this.readJournal) return [];
    const max = Math.max(1, Math.min(5000, Number(limit) || 200));
    return this.readJournal(max).slice(-max).reverse();
  }

  verifyEvents() {
    if (!this.readJournal) return { ok: false, checked: 0, failures: [{ code: 'journal-unavailable' }] };
    const rows = this.readJournal(0);
    let prev = '';
    const failures = [];
    rows.forEach((row) => {
      if (!row) return;
      if (String(row.prevHash || '') !== prev) {
        failures.push({ id: row.id || '', code: 'broken-chain', seq: row.seq });
      }
      const copy = Object.assign({}, row);
      delete copy.hash;
      const expect = this.hmac
        ? this.hmac(JSON.stringify(copy))
        : crypto.createHash('sha256').update(JSON.stringify(copy)).digest('hex');
      if (expect !== row.hash) {
        failures.push({ id: row.id || '', code: 'bad-hmac', seq: row.seq });
      }
      prev = row.hash || '';
    });
    return { ok: failures.length === 0, checked: rows.length, failures };
  }
}

module.exports = {
  AmlEngine,
  DEFAULT_RULES,
  LIST_TYPES,
  LIST_TYPE_NAMES,
  KYC_NAMES,
  RISK_NAMES,
  normalizeName,
  nameSimilarity,
  parseListInput
};
