'use strict';

/*
 * App 内置运维权限的唯一来源。
 *
 * users.json 里的 ops/admin 只是历史展示字段，不能作为授权依据。账号一旦
 * 误写入这些字段，如果服务端直接信任，就会把普通用户提升为运维账号。
 */
const APP_OPS_ID = 'u_2883edf4d038a117';
const APP_OPS_USERNAME = 'wzy245441545';

function isOpsUser(user) {
  if (!user || user.banned || user.frozen || user.disabled) return false;
  return String(user.id || '') === APP_OPS_ID
    && String(user.username || '').trim().toLowerCase() === APP_OPS_USERNAME;
}

function isOpsWebAuthPath(parts) {
  return Array.isArray(parts) && parts[0] === 'ops'
    && ['login', 'session', 'logout'].includes(parts[1]);
}

function isProtectedOpsPath(parts) {
  if (!Array.isArray(parts) || !parts.length) return false;
  if (parts[0] === 'manage') return true;
  return parts[0] === 'ops' && !isOpsWebAuthPath(parts);
}

module.exports = {
  APP_OPS_ID,
  APP_OPS_USERNAME,
  isOpsUser,
  isOpsWebAuthPath,
  isProtectedOpsPath
};
