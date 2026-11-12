# 星言反洗钱（AML）

## 当前能力

- 客户尽调画像：基础实名、增强实名、职业、常住国家、国籍、资金来源、风险等级、持续重筛。
- 名单筛查：制裁、政治公众人物（PEP）、负面新闻、内部黑名单；支持姓名、别名、证件哈希和国家。
- 误伤控制：证件哈希和精确姓名可自动拦截；近似姓名只进入人工复核，不自动冻结。
- 实时监控：单笔大额、24 小时累计、频率、同对手方次数、拆分交易、快进快出、新账号大额、高风险国家。
- 拦截策略：命中有效制裁、内部黑名单、未实名转出或 AML 支付限制时拒绝；其他高风险交易进入案件队列。
- 冻结与限制：可按案件限制转出，也可解除；有效制裁命中不能直接解除。
- 双人复核：后台开启 `dualReview` 后，限制、解除和报送登记需要另一个管理员复核。
- 可疑交易报告：自动整理交易、指标、客户画像和叙述草稿，支持导出 JSON，人工报送后登记回执。
- 审计证据：独立 `aml-events.jsonl`，AES-256-GCM 加密，HMAC 链式校验，只追加；启动时从日志恢复链头。
- 故障关闭：AML 初始化、日志或决策失败时，资金转出暂停，不允许“风控坏了继续扣钱”。

## 数据文件

| 文件 | 内容 |
|---|---|
| `data/aml.json` | 客户画像、名单当前版本、案件、报告和监控规则（加密） |
| `data/aml-events.jsonl` | 只追加 AML 证据事件（逐行加密 + 哈希链） |

不得手工删除 AML 证据日志。名单停用是状态变更，不是删除记录。

## 后台接口

所有接口要求后台 `payments` 权限；写操作还要求管理员再次输入自己的后台密码。

```text
GET  /api/ops/aml
GET  /api/ops/aml/profiles
GET  /api/ops/aml/profile?uid=...
GET  /api/ops/aml/lists
GET  /api/ops/aml/cases
GET  /api/ops/aml/cases/:id
GET  /api/ops/aml/reports
GET  /api/ops/aml/report/:id
GET  /api/ops/aml/events
GET  /api/ops/aml/integrity

POST /api/ops/aml/rules
POST /api/ops/aml/lists/import
POST /api/ops/aml/lists/disable
POST /api/ops/aml/profile
POST /api/ops/aml/screening/run
POST /api/ops/aml/cases/:id/review
POST /api/ops/aml/reports/:id/submit
```

管理后台侧边栏「金融风控 → 反洗钱 AML」提供名单导入、客户风险、案件复核、报告导出和规则配置。

## 已接入资金入口

- 转账发起与收款
- 扫码付款
- 红包发送与领取
- 零钱充值、提现
- 经营账户提现
- 会员、商城、动态眼睛等余额消费
- 所有通过 `applyMoney()` 的其他转出消费

系统退款、后台调账和支付自检显式绕过自动 AML 决策，但仍进入资金总账。

## 测试

```powershell
node server/test/aml.test.js
node server/test/aml-system.test.js
node server/test/aml-failclosed.test.js
node server/test/payment-ledger.test.js
```

`aml-system` 使用临时数据目录真实启动服务，验证正常转账、制裁拦截、名单撤销、重筛解除、大额人工审核、证据链和账本一致性，不会连接或修改线上用户数据。

## 真钱上线门槛

当前 `realMoneyEnabled` 强制为 `false`。以下条件全部完成前，不得接真实资金：

1. 接入正式制裁/PEP/负面新闻数据供应商，并约定自动更新和版本回滚。
2. 资金状态迁移到数据库事务、行锁和 outbox，取消跨 JSON 文件的非原子写入。
3. 接入持牌支付机构和银行结算，完成逐日对账、差异工单和冲正流程。
4. 由法务确认适用辖区、报告模板、阈值、保存年限、保密和禁止泄密（tipping-off）流程。
5. 指定反洗钱负责人、独立复核人、值班与升级机制。
6. 完成压力、故障注入、权限、灾备、数据恢复和真实机构联调验收。

缺少任何一项，只能作为 AML 功能开发和内部演练环境，不能对外宣称已合规或可承载真钱。
