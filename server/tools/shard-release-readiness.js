#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { buildReleaseReadiness } = require('../lib/shard-release-readiness');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(file), 'utf8'));
}

function readRows(file, key) {
  const value = readJson(file);
  if (Array.isArray(value)) return value;
  return value && Array.isArray(value[key]) ? value[key] : [];
}

function main() {
  const baselineFile = arg('baseline');
  const candidateFile = arg('candidate');
  const allowlistFile = arg('allowlist');
  const routePlanFile = arg('route-plan');
  if (!baselineFile || !candidateFile || !allowlistFile || !routePlanFile) {
    throw new Error('usage: shard-release-readiness.js --baseline FILE '
      + '--candidate FILE --allowlist FILE --route-plan FILE '
      + '[--data DIR] [--out FILE]');
  }
  const dataDir = arg('data');
  const report = buildReleaseReadiness({
    baseline: readJson(baselineFile),
    candidate: readJson(candidateFile),
    allowlist: readJson(allowlistFile),
    routePlan: readJson(routePlanFile),
    users: dataDir
      ? readRows(path.join(dataDir, 'users.json'), 'users')
      : null,
    chats: dataDir
      ? readRows(path.join(dataDir, 'chats.json'), 'chats')
      : null
  });
  const text = JSON.stringify(report, null, 2);
  const out = arg('out');
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      failedChecks: report.failures.map((row) => row.name),
      route: report.route,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 2;
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
