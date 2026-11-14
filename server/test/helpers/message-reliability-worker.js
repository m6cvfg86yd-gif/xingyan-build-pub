'use strict';

const { MessageReliabilityStore } = require('../../lib/message-reliability');

const databaseFile = process.argv[2];
const worker = Number(process.argv[3]);
const count = Number(process.argv[4]);
const store = new MessageReliabilityStore({ databaseFile });
const sequences = [];

for (let index = 0; index < count; index += 1) {
    const result = store.reserveMessage({
        id: `m-${worker}-${index}`,
        chatId: 'chat-concurrent',
        senderId: `user-${worker}`,
        clientId: `client-${worker}-${index}`,
        content: `message-${worker}-${index}`
    });
    sequences.push(result.seq);
}

store.close();
process.stdout.write(JSON.stringify(sequences));
