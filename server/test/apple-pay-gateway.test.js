'use strict';

const assert = require('assert');
const {
  appleValidationHost,
  validateMerchantUrl,
  validateApplePayToken,
  ApplePayMerchantProvider,
  ApplePayNetworkProcessor
} = require('../lib/apple-pay-gateway');

async function main() {
  assert.strictEqual(appleValidationHost('apple-pay-gateway.apple.com'), true);
  assert.strictEqual(appleValidationHost('apple-pay-gateway-cert.apple.com'), true);
  assert.strictEqual(appleValidationHost('apple-pay-gateway-nc-pod1.apple.com'), true);
  assert.strictEqual(appleValidationHost('apple.com.evil.example'), false);
  assert.throws(
    () => validateMerchantUrl('http://apple-pay-gateway.apple.com/paymentSession'),
    /untrusted/
  );
  assert.throws(
    () => validateMerchantUrl('https://apple.com.evil.example/paymentSession'),
    /untrusted/
  );

  const unavailable = new ApplePayMerchantProvider({});
  assert.strictEqual(unavailable.available(), false);
  await assert.rejects(
    () => unavailable.createSession('https://apple-pay-gateway.apple.com/paymentSession'),
    /not configured/
  );
  let requested = null;
  const provider = new ApplePayMerchantProvider({
    merchantIdentifier: 'merchant.com.xingyan',
    domainName: 'pay.xingyan.example',
    displayName: 'Xingyan Pay',
    cert: 'client-cert',
    key: 'client-key',
    request: async (options, body) => {
      requested = { options, body: JSON.parse(body) };
      return { statusCode: 200, body: { epochTimestamp: 1, signature: 'test' } };
    }
  });
  const session = await provider.createSession(
    'https://apple-pay-gateway.apple.com/paymentSession'
  );
  assert.strictEqual(session.signature, 'test');
  assert.strictEqual(requested.body.merchantIdentifier, 'merchant.com.xingyan');
  assert.strictEqual(requested.body.initiativeContext, 'pay.xingyan.example');

  const token = {
    transactionIdentifier: 'apple-transaction-1',
    paymentData: {
      data: 'encrypted-payment-data',
      signature: 'apple-signature',
      header: { ephemeralPublicKey: 'public-key', publicKeyHash: 'hash' },
      version: 'EC_v1'
    },
    paymentMethod: { type: 'credit', network: 'Visa', displayName: 'Visa 4242' }
  };
  assert.strictEqual(validateApplePayToken(token), token);
  assert.throws(() => validateApplePayToken({
    transactionIdentifier: 'bad',
    paymentData: 'encrypted',
    number: '4242424242424242'
  }), /raw card data/);
  assert.throws(() => validateApplePayToken({ paymentData: 'encrypted' }), /invalid/);

  const disconnected = new ApplePayNetworkProcessor({});
  assert.strictEqual(disconnected.available(), false);
  assert.throws(() => disconnected.authorize(token, {}), /not connected/);

  const calls = [];
  const connected = new ApplePayNetworkProcessor({
    provider: 'licensed-psp',
    processor: {
      authorize: () => { calls.push('authorize'); return { reference: 'auth-1' }; },
      capture: () => { calls.push('capture'); return { reference: 'capture-1' }; },
      refund: () => { calls.push('refund'); return { reference: 'refund-1' }; },
      void: () => { calls.push('void'); return { reference: 'void-1' }; }
    }
  });
  assert.strictEqual(connected.authorize(token, { amountCents: 100 }).reference, 'auth-1');
  assert.strictEqual(connected.capture('auth-1', 100, 'CNY').reference, 'capture-1');
  assert.strictEqual(connected.refund('capture-1', 50, 'CNY').reference, 'refund-1');
  assert.strictEqual(connected.void('auth-1').reference, 'void-1');
  assert.deepStrictEqual(calls, ['authorize', 'capture', 'refund', 'void']);

  console.log('apple-pay-gateway: passed');
}

main().catch((error) => {
  console.error(error.stack || error);
  process.exitCode = 1;
});
