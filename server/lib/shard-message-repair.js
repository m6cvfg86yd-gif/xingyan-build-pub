'use strict';

const crypto = require('crypto');
const fs = require('fs');
const path = require('path');
const { SecurityVault } = require('./security-vault');

function legacyKey(secret, chatId) {
  return crypto.createHmac('sha256', String(secret || ''))
    .update('msg:' + String(chatId))
    .digest();
}

function openStoredMessage(secret, chatId, line, vault) {
  const stored = JSON.parse(line);
  if (!stored || stored.e !== 1) return { message: stored, envelope: null };
  if (stored.kv) {
    if (!vault) throw new Error('keyring is required for versioned messages');
    return {
      message: vault.openJson('message', chatId, stored, null),
      envelope: stored
    };
  }
  const decipher = crypto.createDecipheriv(
    'aes-256-gcm',
    legacyKey(secret, chatId),
    Buffer.from(stored.iv, 'base64')
  );
  decipher.setAuthTag(Buffer.from(stored.tag, 'base64'));
  const plain = Buffer.concat([
    decipher.update(Buffer.from(stored.ct, 'base64')),
    decipher.final()
  ]);
  return {
    message: JSON.parse(plain.toString('utf8')),
    envelope: stored
  };
}

function sealStoredMessage(secret, chatId, message, envelope, vault) {
  if (envelope && envelope.kv) return JSON.stringify(vault.sealJson('message', chatId, message));
  if (envelope && envelope.e === 1) {
    const iv = crypto.randomBytes(12);
    const cipher = crypto.createCipheriv('aes-256-gcm', legacyKey(secret, chatId), iv);
    const ciphertext = Buffer.concat([
      cipher.update(Buffer.from(JSON.stringify(message), 'utf8')),
      cipher.final()
    ]);
    return JSON.stringify({
      e: 1,
      iv: iv.toString('base64'),
      tag: cipher.getAuthTag().toString('base64'),
      ct: ciphertext.toString('base64')
    });
  }
  return JSON.stringify(message);
}

function repairMessageSequences(options) {
  const opts = options || {};
  const messagesDir = path.resolve(String(opts.messagesDir || ''));
  const secret = String(opts.secret || '');
  if (!messagesDir) throw new Error('messagesDir is required');
  if (!secret) throw new Error('secret is required');
  const dataDir = path.dirname(messagesDir);
  const vault = fs.existsSync(path.join(dataDir, 'keyring.json'))
    ? new SecurityVault({ dataDir, rootMaterial: secret })
    : null;
  const dryRun = opts.dryRun === true;
  const report = {
    version: 1,
    ok: true,
    dryRun,
    files: 0,
    messages: 0,
    changed: 0,
    failed: 0,
    chats: []
  };
  const names = fs.readdirSync(messagesDir)
    .filter((name) => name.endsWith('.jsonl'))
    .sort();
  for (const name of names) {
    const chatId = name.slice(0, -'.jsonl'.length);
    const file = path.join(messagesDir, name);
    const lines = fs.readFileSync(file, 'utf8').split('\n').filter((line) => line.trim());
    const out = [];
    let lastSeq = 0;
    let changed = 0;
    let failed = 0;
    for (let index = 0; index < lines.length; index += 1) {
      let opened;
      try {
        opened = openStoredMessage(secret, chatId, lines[index], vault);
      } catch (_) {
        failed += 1;
        out.push(lines[index]);
        continue;
      }
      const message = opened.message;
      if (!message || typeof message !== 'object') {
        failed += 1;
        out.push(lines[index]);
        continue;
      }
      const seq = Number(message.seq) || 0;
      const nextSeq = seq > lastSeq ? seq : lastSeq + 1;
      if (message.chatId !== chatId || nextSeq !== seq) {
        message.chatId = chatId;
        message.seq = nextSeq;
        out.push(sealStoredMessage(secret, chatId, message, opened.envelope, vault));
        changed += 1;
      } else {
        out.push(lines[index]);
      }
      lastSeq = nextSeq;
      report.messages += 1;
    }
    report.files += 1;
    if (changed || failed) {
      report.chats.push({ chatId, messages: lines.length, changed, failed });
    }
    report.changed += changed;
    report.failed += failed;
    if (!dryRun && changed) {
      const temporary = file + '.' + process.pid + '.repair.tmp';
      fs.writeFileSync(temporary, out.join('\n') + (out.length ? '\n' : ''), 'utf8');
      fs.renameSync(temporary, file);
    }
  }
  report.ok = report.failed === 0;
  return report;
}

module.exports = { repairMessageSequences };
