'use strict';

const formatterCache = new Map();

function normalizeBillTimeZone(value) {
  const zone = String(value || '').trim().slice(0, 64);
  if (!zone) return 'UTC';
  try {
    new Intl.DateTimeFormat('en-US', { timeZone: zone }).format();
    return zone;
  } catch (_) {
    return 'UTC';
  }
}

function formatterFor(timeZone) {
  const zone = normalizeBillTimeZone(timeZone);
  if (formatterCache.has(zone)) return formatterCache.get(zone);
  const formatter = new Intl.DateTimeFormat('en-CA', {
    timeZone: zone,
    year: 'numeric',
    month: '2-digit',
    day: '2-digit'
  });
  if (formatterCache.size < 32) formatterCache.set(zone, formatter);
  return formatter;
}

function billDateKey(value, timeZone) {
  const date = value instanceof Date ? value : new Date(value);
  if (!(date instanceof Date) || Number.isNaN(date.getTime())) return '';
  const parts = formatterFor(timeZone).formatToParts(date);
  const part = (type) => (parts.find((item) => item.type === type) || {}).value || '';
  const year = part('year');
  const month = part('month');
  const day = part('day');
  return year && month && day ? year + '-' + month + '-' + day : '';
}

function billMonthKey(value, timeZone) {
  return billDateKey(value, timeZone).slice(0, 7);
}

function amountCents(value) {
  const number = Number(value);
  return Number.isFinite(number) ? Math.round(number * 100) : 0;
}

function summarizeBills(rows, month, timeZone) {
  const scope = String(month || '');
  const inScope = (Array.isArray(rows) ? rows : [])
    .filter((row) => row && billMonthKey(row.createdAt, timeZone) === scope);
  const sum = (list) => list.reduce((total, row) => total + amountCents(row.amount), 0) / 100;
  const outgoing = inScope.filter((row) =>
    row.direction === 'out' && (row.status === 'pending' || row.status === 'received'));
  const income = inScope.filter((row) =>
    row.direction === 'in' && row.status === 'received');
  return {
    out: sum(outgoing),
    in: sum(income),
    pendingOut: inScope.filter((row) => row.direction === 'out' && row.status === 'pending').length,
    pendingIn: inScope.filter((row) => row.direction === 'in' && row.status === 'pending').length,
    count: inScope.length,
    month: scope
  };
}

module.exports = {
  normalizeBillTimeZone,
  billDateKey,
  billMonthKey,
  summarizeBills
};
