#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { inventoryData } = require('../lib/shard-data-inventory');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = arg('data');
  if (!dataDir) throw new Error('usage: shard-data-inventory.js --data DIR '
    + '[--secret FILE] [--source ID] [--out FILE]');
  const secretFile = arg('secret');
  const secret = secretFile ? fs.readFileSync(secretFile, 'utf8').trim() : '';
  const report = inventoryData({
    dataDir,
    secret,
    sourceId: arg('source', ''),
    baselineDate: arg('baseline-date', ''),
    publicDir: arg('public', '')
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
      counts: report.counts,
      issues: report.issueCount,
      errors: report.errorCount,
      warnings: report.warningCount,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text);
  }
  if (!report.ok) process.exitCode = 2;
}

if (require.main === module) {
  try { main(); }
  catch (error) {
    console.error(error.stack || error);
    process.exitCode = 1;
  }
}
