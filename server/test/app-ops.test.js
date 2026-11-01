'use strict';

const assert = require('assert');
const {
  isOpsUser,
  isOpsWebAuthPath,
  isProtectedOpsPath
} = require('../lib/app-ops');

assert.strictEqual(isOpsUser({
  id: 'u_2883edf4d038a117',
  username: 'wzy245441545'
}), true);
assert.strictEqual(isOpsUser({
  id: 'u_2883edf4d038a117',
  username: 'linyu2200'
}), false);
assert.strictEqual(isOpsUser({ id: 'u_other', ops: true }), false);
assert.strictEqual(isOpsUser({ id: 'u_other', admin: true }), false);
assert.strictEqual(isOpsUser({
  id: 'u_2883edf4d038a117',
  username: 'wzy245441545',
  banned: true
}), false);
assert.strictEqual(isOpsUser({
  id: 'u_2883edf4d038a117',
  username: 'wzy245441545',
  frozen: true
}), false);
assert.strictEqual(isOpsUser({
  id: 'u_2883edf4d038a117',
  username: 'wzy245441545',
  disabled: true
}), false);
assert.strictEqual(isOpsUser(null), false);

assert.strictEqual(isProtectedOpsPath(['manage']), true);
assert.strictEqual(isProtectedOpsPath(['ops', 'mall']), true);
assert.strictEqual(isProtectedOpsPath(['ops', 'account']), true);
assert.strictEqual(isProtectedOpsPath(['ops', 'login']), false);
assert.strictEqual(isProtectedOpsPath(['ops', 'session']), false);
assert.strictEqual(isProtectedOpsPath(['ops', 'logout']), false);
assert.strictEqual(isProtectedOpsPath(['chats']), false);
assert.strictEqual(isOpsWebAuthPath(['ops', 'login']), true);
assert.strictEqual(isOpsWebAuthPath(['ops', 'mall']), false);

console.log('app-ops policy ok');
