#!/usr/bin/env node
'use strict';

const fs = require('fs');
const path = require('path');
const { planGroupCells } = require('../lib/group-cell-route-plan');

function arg(name, fallback) {
  const index = process.argv.indexOf('--' + name);
  return index >= 0 ? process.argv[index + 1] : fallback;
}

function readJson(file) {
  return JSON.parse(fs.readFileSync(path.resolve(String(file || '')), 'utf8'));
}

function groupRows(value) {
  if (Array.isArray(value)) return value;
  if (Array.isArray(value && value.groups)) return value.groups;
  if (Array.isArray(value && value.chats)) {
    return value.chats.filter((chat) =>
      !chat.type || String(chat.type).toLowerCase() === 'group'
    );
  }
  if (Array.isArray(value && value.assignments)) return value.assignments;
  return [];
}

function main() {
  const input = arg('input', '');
  const output = arg('output', '');
  const cellIds = String(arg('cells', '')).split(',');
  const previousFile = arg('previous', '');
  if (!input || !output) {
    throw new Error('--input and --output are required');
  }
  const groups = groupRows(readJson(input));
  const previousAssignments = previousFile ? readJson(previousFile) : [];
  const plan = planGroupCells({ groups, cellIds, previousAssignments });
  const target = path.resolve(output);
  fs.mkdirSync(path.dirname(target), { recursive: true });
  const temporary = target + '.tmp';
  fs.writeFileSync(temporary, JSON.stringify(plan, null, 2), 'utf8');
  fs.renameSync(temporary, target);
  process.stdout.write(JSON.stringify({
    output: target,
    groupCount: plan.groupCount,
    cellIds: plan.cellIds,
    maxSkew: plan.maxSkew,
    assignmentHash: plan.assignmentHash
  }) + '\n');
}

try {
  main();
} catch (error) {
  console.error(error.stack || error);
  process.exitCode = 1;
}
