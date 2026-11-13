#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const {
  buildPlacementReport,
  buildPlacementReportFromEntries
} = require('../lib/shard-data-placement');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function main() {
  const dataDir = arg('data');
  const manifest = arg('manifest');
  if (!dataDir && !manifest) {
    throw new Error('usage: shard-data-placement.js '
      + '(--data DIR [--shallow] | --manifest FILE) [--out FILE]');
  }
  const report = manifest
    ? buildPlacementReportFromEntries(
      JSON.parse(fs.readFileSync(path.resolve(manifest), 'utf8')),
      { shallowKnownDirectories: true }
    )
    : buildPlacementReport(dataDir, {
      shallowKnownDirectories: process.argv.includes('--shallow')
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
      files: report.files,
      bytes: report.bytes,
      byPlacement: report.byPlacement,
      unclassified: report.unclassified.length,
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
