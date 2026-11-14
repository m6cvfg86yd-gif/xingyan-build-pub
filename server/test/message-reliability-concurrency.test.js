'use strict';

const assert = require('assert');
const fs = require('fs');
const os = require('os');
const path = require('path');
const { spawn } = require('child_process');
const { MessageReliabilityStore } = require('../lib/message-reliability');

const root = fs.mkdtempSync(path.join(os.tmpdir(), 'xingyan-message-reliability-concurrency-'));
const databaseFile = path.join(root, 'message-reliability.sqlite3');
const workerCount = 8;
const perWorker = 20;

function runWorker(index) {
    return new Promise((resolve, reject) => {
        const child = spawn(process.execPath, [
            path.join(__dirname, 'helpers', 'message-reliability-worker.js'),
            databaseFile,
            String(index),
            String(perWorker)
        ], {
            stdio: ['ignore', 'pipe', 'pipe'],
            windowsHide: true
        });
        const stdout = [];
        const stderr = [];
        child.stdout.on('data', (chunk) => stdout.push(chunk));
        child.stderr.on('data', (chunk) => stderr.push(chunk));
        child.on('error', reject);
        child.on('exit', (code) => {
            if (code !== 0) {
                reject(new Error('worker failed: ' + Buffer.concat(stderr).toString('utf8')));
                return;
            }
            resolve(JSON.parse(Buffer.concat(stdout).toString('utf8')));
        });
    });
}

async function main() {
    const results = await Promise.all(
        Array.from({ length: workerCount }, (_, index) => runWorker(index))
    );
    const sequences = results.flat().sort((a, b) => a - b);
    assert.strictEqual(sequences.length, workerCount * perWorker);
    assert.deepStrictEqual(
        sequences,
        Array.from({ length: workerCount * perWorker }, (_, index) => index + 1)
    );

    const store = new MessageReliabilityStore({ databaseFile });
    assert.strictEqual(store.messagesAfter('chat-concurrent', 0, 500).length,
        workerCount * perWorker);
    store.close();
    console.log('message-reliability-concurrency: passed');
}

main().catch((error) => {
    console.error(error.stack || error);
    process.exitCode = 1;
}).finally(() => {
    if (process.platform !== 'win32') {
        fs.rmSync(root, { recursive: true, force: true });
    }
});
