#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { reconcileLegacyLedger } = require('../lib/payment-opening-balance');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = arg('data');
  const secretFile = arg('secret');
  if (!dataDir || !secretFile) {
    throw new Error('usage: reconcile-legacy-wallets.js --data DIR --secret FILE '
      + '[--at ISO] [--backup DIR] [--apply] [--out FILE]');
  }
  const report = reconcileLegacyLedger({
    dataDir,
    secret: fs.readFileSync(path.resolve(secretFile), 'utf8').trim(),
    at: arg('at', '2026-11-13T00:00:00.000Z'),
    backupDir: arg('backup', ''),
    apply: process.argv.includes('--apply')
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
      apply: report.apply,
      differences: report.differences,
      walletDifferences: report.walletDifferences,
      businessDifferences: report.businessDifferences,
      recorded: report.recorded,
      duplicates: report.duplicates,
      backupDir: report.backupDir,
      afterDifferences: report.after && report.after.differences
        ? report.after.differences.length
        : null,
      out: file
    }, null, 2));
  } else {
    process.stdout.write(text + '\n');
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
