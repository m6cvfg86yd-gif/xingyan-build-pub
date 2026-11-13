#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { repairMessageSequences } = require('../lib/shard-message-repair');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = arg('data');
  if (!dataDir) throw new Error('usage: repair-shard-data.js --data DIR '
    + '[--secret FILE] [--dry-run] [--out FILE]');
  const secretFile = arg('secret', path.join(dataDir, 'secret.key'));
  const report = repairMessageSequences({
    messagesDir: path.join(dataDir, 'messages'),
    secret: fs.readFileSync(secretFile, 'utf8').trim(),
    dryRun: process.argv.includes('--dry-run')
  });
  const out = arg('out');
  const text = JSON.stringify(report, null, 2);
  if (out) {
    const file = path.resolve(out);
    fs.mkdirSync(path.dirname(file), { recursive: true });
    const temporary = file + '.' + process.pid + '.tmp';
    fs.writeFileSync(temporary, text, 'utf8');
    fs.renameSync(temporary, file);
    console.log(JSON.stringify({
      ok: report.ok,
      files: report.files,
      messages: report.messages,
      changed: report.changed,
      failed: report.failed,
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
