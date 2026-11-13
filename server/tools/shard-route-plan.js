#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildRoutePlan, verifyRoutePlan } = require('../lib/shard-route-plan');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file, fallback) {
  try {
    return JSON.parse(fs.readFileSync(file, 'utf8'));
  } catch (_) {
    return fallback;
  }
}

function rowsOf(value, key) {
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function writeJson(file, value) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  const temporary = file + '.' + process.pid + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(value, null, 2), 'utf8');
  fs.renameSync(temporary, file);
}

function main() {
  const dataDir = arg('data');
  const file = arg('file');
  if (!dataDir && !file) {
    throw new Error('usage: shard-route-plan.js '
      + '(--data DIR --topology ID --shards N --ports CSV --out FILE | '
      + '--file FILE [--data DIR])');
  }
  let plan;
  if (file) {
    plan = JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
  } else {
    const shardCount = Number(arg('shards'));
    const ports = String(arg('ports') || '').split(',')
      .map((value) => value.trim())
      .filter(Boolean);
    const users = rowsOf(readJson(path.join(dataDir, 'users.json'), { users: [] }), 'users');
    const chats = rowsOf(readJson(path.join(dataDir, 'chats.json'), { chats: [] }), 'chats');
    plan = buildRoutePlan({
      users,
      chats,
      shardCount,
      ports,
      topologyId: arg('topology', ''),
      baselineDate: arg('baseline-date', ''),
      createdAt: arg('created-at', '')
    });
  }

  const users = dataDir
    ? rowsOf(readJson(path.join(dataDir, 'users.json'), { users: [] }), 'users')
    : null;
  const chats = dataDir
    ? rowsOf(readJson(path.join(dataDir, 'chats.json'), { chats: [] }), 'chats')
    : null;
  const verification = verifyRoutePlan(plan, { users, chats });
  const out = arg('out');
  const result = Object.assign({}, verification, {
    ok: verification.ok,
    plannedUsers: plan.counts && plan.counts.users,
    plannedChats: plan.counts && plan.counts.chats
  });
  if (out && !file) {
    writeJson(path.resolve(out), plan);
    result.out = path.resolve(out);
  }
  process.stdout.write(JSON.stringify(result, null, 2) + '\n');
  if (!verification.ok) process.exitCode = 2;
}

if (require.main === module) {
  try {
    main();
  } catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}

module.exports = { main };
