# SRN Yes/No Claim Protocol Spec

## 1. 文档目标

本文档给出一份站在 ad network 视角的实现规格说明，用于支持如下现实约束下的 SRN 归因流程：

- MMP 持有全量 conversion。
- MMP 对每个 conversion 向每个 ad network 发起 claim request。
- ad network 只能返回 `yes/no`。
- MMP 负责最终 winner adjudication，例如 last click。
- MMP 向 winner network 发送确认请求。

本文的目标不是追求理论上最强的零泄露协议，而是在保留现实接口约束的前提下，把 ad network 的额外泄露压到最低，并保留后续做后台安全结算与审计的空间。

## 2. 设计目标与非目标

### 2.1 设计目标

- 让 network 能高效回答 `eligible_to_claim(conversion_query) -> bool`
- 避免 network 暴露原始点击/曝光日志
- 限制 MMP 通过重复探测恢复 network 的 coverage map
- 为 winner confirmation 提供可审计、不可复用的 claim token
- 支持后续 aggregate verification / settlement

### 2.2 非目标

- 不在前台 claim API 中实现多方 MPC 裁决
- 不在前台 claim API 中传输明细级 click / impression metadata
- 不把该协议直接当作最终报表层协议

## 3. 参与方

- Advertiser App：集成 MMP SDK 与 ad network SDK 的 app
- MMP SDK：采集 conversion，并生成供 MMP 服务端使用的查询材料
- Network SDK：在设备侧生成或缓存 network-specific claim token / join key
- MMP Server：持有 conversion log，向各 network 发送 claim request
- Network Claim Service：ad network 的 claim 查询服务
- Network Event Index：ad network 内部的可 claim 候选索引
- MMP Adjudicator：执行 last click 或其他 winner selection
- Network Finalize Service：接收 winner confirmation
- Optional Settlement Service：执行后台对账、aggregate verification 或 PJC

## 4. 信任与威胁模型

### 4.1 ad network 要保护的资产

- 用户级点击 / 曝光覆盖
- 匹配成功率
- campaign coverage
- click / impression 时间分布
- loser claims
- 内部归因与风控规则

### 4.2 主要对手

- 好奇但遵守接口的 MMP
- 通过重复查询或字段微调进行探测的 MMP
- 可利用日志、监控、失败重试做侧信道分析的内部系统

### 4.3 核心原则

- MMP 只应获得 `yes/no` 与必要的 claim token
- Network 内部要把“回答 yes/no”与“暴露 claim 细节”彻底分离

## 5. 高层架构

### 5.1 前台协议

前台协议采用 membership-style claim protocol。

外部接口：

- 输入：一个规范化的 `conversion_query`
- 输出：
  - `claim = yes/no`
  - `claim_token`，仅当 `yes` 时返回

内部实现：

- Network 内部将该查询映射到 `eligible_to_claim(conversion_query)` 的布尔决策

### 5.2 后台协议

后台协议用于以下场景：

- aggregate verification
- settlement
- reconciliation
- fraud analytics

这里可以使用：

- PJC / PI-Sum
- PSI cardinality
- confidential aggregation

前后台分离是本 spec 的核心设计原则。

## 6. 数据模型

### 6.1 设备侧数据对象

#### NetworkTouchToken

设备侧由 Network SDK 生成或缓存的触达令牌。

字段：

- `network_id`
- `token_version`
- `touch_type`，例如 click 或 impression
- `touch_time_bucket`
- `campaign_ref`
- `adset_ref`
- `creative_ref`
- `opaque_match_key`
- `expiry_ts`
- `sdk_signature`

约束：

- `opaque_match_key` 应为 task-specific、短生命周期、不可逆
- 不应是长期稳定用户标识的直接哈希

#### ConversionRecord

由 MMP SDK 或 MMP 服务端维护的转化对象。

字段：

- `conversion_id`
- `app_id`
- `event_name`
- `conversion_ts`
- `conversion_time_bucket`
- `value`
- `currency`
- `device_scoped_query_key`
- `query_nonce`
- `query_schema_version`

### 6.2 Network 内部索引对象

#### ClaimableTouchRecord

Network 内部可 claim 候选记录。

字段：

- `opaque_match_key`
- `touch_type`
- `touch_ts`
- `touch_time_bucket`
- `campaign_ref`
- `attribution_priority`
- `eligibility_expiry_ts`
- `fraud_state`
- `dedupe_state`
- `record_mac`

#### ClaimIndex

推荐采用分层索引，而不是单一主键表。

一级索引：

- key: `opaque_match_key`
- value: candidate record list pointer

二级过滤：

- `touch_time_bucket`
- `touch_type`
- `campaign_ref`
- `eligibility_expiry_ts`

辅助结构：

- dedupe cache
- replay cache
- finalize cache
- policy version registry

## 7. ad network 内索引设计

### 7.1 设计目标

- 在高 QPS 下快速回答 yes/no
- 不把完整原始日志暴露给 claim service
- 把 claim 逻辑所需字段与分析所需字段隔离

### 7.2 推荐的双层存储

#### 层 1：Hot Claim Index

用途：

- 直接服务 claim query

特点：

- 只保留 claim 决策所需最小字段
- TTL 明确
- 支持按 `opaque_match_key + time bucket` 快速过滤

推荐字段：

- `opaque_match_key`
- `touch_type`
- `touch_ts`
- `campaign_ref`
- `priority_score`
- `eligibility_expiry_ts`
- `fraud_state`
- `dedupe_state`

#### 层 2：Cold Event Store

用途：

- 内部审计
- 对账
- 模型训练
- 离线分析

特点：

- 不直接暴露给前台 claim service
- 不参与同步 yes/no 决策路径

### 7.3 查询路径

1. 用 `opaque_match_key` 命中一级索引
2. 用 `conversion_time_bucket` 和 attribution window 过滤候选
3. 按 `touch_type`、priority、fraud gate 和 dedupe rule 筛掉无效记录
4. 若剩余候选非空，则返回 `yes`
5. 同时铸造 `claim_token`

### 7.4 防探测设计

- 对同一 `conversion_id` 或等价 `query_hash` 建立 replay cache
- 限制同一 query 在固定窗口内的可重试次数
- 将时间戳离散到 bucket，减少边界探测价值
- 对异常 probing 模式打审计标签

## 8. SDK 设计

### 8.1 Network SDK 职责

- 在设备侧生成 network-specific touch token
- 对触达事件做最小化编码
- 将 token 或其派生物上送 network
- 严格控制 token 生命周期

### 8.2 MMP SDK 职责

- 记录 conversion
- 生成供 MMP claim request 使用的 `conversion_query`
- 不要求知道各 network 的内部索引结构

### 8.3 设备侧交互建议

推荐模式：

1. 用户发生 ad touch
2. Network SDK 生成 `NetworkTouchToken`
3. token 被缓存于设备侧，并按策略同步给 network backend
4. 用户发生 conversion
5. MMP SDK 生成 `ConversionRecord`
6. MMP 服务端基于该 record 对各 network 发起 claim request

### 8.4 不推荐模式

- 直接把长期稳定 ID 从 SDK 明文送到 claim API
- 让 MMP SDK 参与 network 私有规则判断
- 在设备侧暴露完整 network claimability 逻辑

## 9. API 规格

### 9.1 MMP -> Network Claim API

请求对象：`ClaimRequest`

字段：

- `request_id`
- `mmp_id`
- `network_id`
- `conversion_id`
- `query_hash`
- `query_schema_version`
- `conversion_ts_bucket`
- `event_name`
- `app_id`
- `device_scoped_query_key`
- `query_nonce`
- `sent_at`
- `request_signature`

说明：

- `device_scoped_query_key` 应是规范化、不可逆、时间受限的 query key
- `query_hash` 用于 replay detection 与审计

返回对象：`ClaimResponse`

字段：

- `request_id`
- `network_id`
- `claim`
- `claim_token`
- `policy_version`
- `response_expiry_ts`
- `response_signature`

约束：

- `claim = no` 时，`claim_token` 为空
- `claim = yes` 时，`claim_token` 为必填
- 不返回 click ts、campaign、touch_type 等额外信息

### 9.2 Claim Token 结构

`claim_token` 应为 network 签名的 opaque blob。

推荐绑定字段：

- `request_id`
- `conversion_id`
- `query_hash`
- `network_id`
- `policy_version`
- `issued_at`
- `expiry_ts`
- `token_nonce`

作用：

- 防止 claim 结果被跨上下文复用
- 为 finalize 提供可验证输入
- 便于追责与审计

### 9.3 MMP -> Network Finalize API

请求对象：`FinalizeRequest`

字段：

- `request_id`
- `conversion_id`
- `network_id`
- `claim_token`
- `winner_model`
- `finalized_at`
- `request_signature`

返回对象：`FinalizeResponse`

字段：

- `request_id`
- `accepted`
- `settlement_ref`
- `response_signature`

## 10. 交互时序

### 10.1 正常路径

1. 用户触发 ad touch
2. Network SDK 生成 `NetworkTouchToken`
3. Network backend 将 token 映射成 `ClaimableTouchRecord` 并写入 `Hot Claim Index`
4. 用户发生 conversion
5. MMP SDK / MMP Server 形成 `ClaimRequest`
6. MMP 向每个 network 发送 `ClaimRequest`
7. Network Claim Service 执行 `eligible_to_claim(conversion_query)`
8. Network 返回 `ClaimResponse`
9. MMP 收集多家 network 的 yes/no
10. MMP 用既定规则执行 winner adjudication
11. MMP 向 winner network 发送 `FinalizeRequest`
12. winner network 校验 `claim_token` 并确认
13. 可选：后台执行 settlement / reconciliation

### 10.2 内部 `eligible_to_claim()` 决策流程

1. 校验 request schema、签名、nonce、replay policy
2. 从 `device_scoped_query_key` 生成或查找 `opaque_match_key`
3. 查询 `Hot Claim Index`
4. 根据 attribution window 过滤记录
5. 应用 touch precedence 规则
6. 执行 fraud / dedupe / campaign eligibility 校验
7. 若有至少一个可 claim 候选，则生成 `claim_token`
8. 返回 `yes`
9. 否则返回 `no`

## 11. Winner adjudication 建议

虽然 winner adjudication 发生在 MMP 侧，但从 ad network 视角，推荐施加以下约束：

- 裁决规则必须预先约定并版本化
- 不应要求 network 在 claim API 中回传额外排序字段
- 若需要更强保护，winner adjudication 可迁移到 TEE

在当前 yes/no 约束下，推荐的裁决模式是：

- MMP 收到多家 `yes`
- 按预定义 last click / SRN 优先级 / deterministic tie-break 规则裁决
- winner-only finalize

## 12. 安全控制

### 12.1 Query 最小化

- query key 必须 task-specific
- query key 必须受时间窗约束
- query key 不应直接复用稳定用户标识

### 12.2 Replay Protection

- `request_id`
- `query_hash`
- `query_nonce`

三者至少应有两者参与去重策略。

### 12.3 Rate Limiting

- 每 advertiser / app / network 的 claim QPS 上限
- 每 conversion 的查询上限
- 每 query hash 的短窗限频

### 12.4 Logging Hygiene

- 不在前台日志中记录明细触达记录
- 不把 loser 候选写入可广泛访问的调试日志
- 调试模式需受额外审批和 sampling 限制

### 12.5 Token Security

- `claim_token` 必须短 TTL
- token 必须单次使用
- finalize 后 token 应立即失效

## 13. 后台对账与 PJC 接口

### 13.1 为什么还需要后台 PJC

前台 yes/no 只解决 claim。

但在以下场景中，仍然需要更强的 set-based cryptography：

- aggregate conversion verification
- billing reconciliation
- campaign-level settlement
- dispute handling

### 13.2 推荐模式

- 前台：membership-style yes/no
- 后台：PJC / PI-Sum

示例：

- MMP 与 network 周期性运行 PJC
- 输出 campaign-level matched conversions 与 matched value sum
- 不暴露逐条用户级明细

## 14. MVP 实施建议

### 14.1 第一步

- 实现 `Hot Claim Index`
- 实现 `ClaimRequest` / `ClaimResponse`
- 实现 `claim_token`
- 实现 replay cache 和 finalize cache

### 14.2 第二步

- 引入 query bucket 化
- 引入 risk scoring 和 probing detection
- 引入 winner-only finalize 流程

### 14.3 第三步

- 增加后台 PJC / PI-Sum 对账原型
- 增加 TEE adjudication 可选路径

## 15. 一页式结论

- 在 yes/no 约束下，前台 claim API 应采用 membership-style 设计。
- ad network 内部实现不应是“裸集合查询”，而应是 `eligible_to_claim()` 决策引擎。
- `Hot Claim Index` 与 `Cold Event Store` 必须分离。
- `claim_token` 是协议中非常关键的约束点。
- 前台尽量只暴露 yes/no，后台再使用 PJC / PI-Sum 做聚合验证与结算。

## 16. Worked Examples

本节用具体样例把前文中的抽象结构落地，便于产品、后端、SDK 与算法团队讨论。

### 16.1 端到端单条样例

假设：

- 用户在 2026-04-16 10:01:12 点击了 Network A 的广告
- 用户在 2026-04-16 10:04:35 点击了 Network B 的广告
- 用户在 2026-04-16 10:20:08 完成了一次 purchase conversion
- MMP 需要向 Network A、Network B、Network C 发起 claim request
- 归因规则是：
  - 仅 click-through
  - 归因窗口 7 天
  - 多家都 claim 时按 last click 选 winner

#### 16.1.1 设备侧触达事件

Network A 在设备侧生成：

```json
{
  "network_id": "netA",
  "token_version": "v1",
  "touch_type": "click",
  "touch_time_bucket": "2026-04-16T10:00:00Z/5m",
  "campaign_ref": "cmp_A_42",
  "adset_ref": "adset_A_9",
  "creative_ref": "creative_A_3",
  "opaque_match_key": "omk_b8db2f5d7d2a",
  "expiry_ts": "2026-04-23T10:01:12Z",
  "sdk_signature": "sig_netA_dev_001"
}
```

Network B 在设备侧生成：

```json
{
  "network_id": "netB",
  "token_version": "v1",
  "touch_type": "click",
  "touch_time_bucket": "2026-04-16T10:00:00Z/5m",
  "campaign_ref": "cmp_B_91",
  "adset_ref": "adset_B_4",
  "creative_ref": "creative_B_6",
  "opaque_match_key": "omk_b8db2f5d7d2a",
  "expiry_ts": "2026-04-23T10:04:35Z",
  "sdk_signature": "sig_netB_dev_001"
}
```

说明：

- 为了便于示例，这里两家 network 最终都能对同一个 `opaque_match_key` 建立匹配。
- 实际实现中，这个 key 不一定长这样，但应该是 task-specific、短生命周期、不可逆的。

#### 16.1.2 MMP 形成 conversion query

```json
{
  "conversion_id": "conv_20260416_00017",
  "app_id": "com.example.shop",
  "event_name": "purchase",
  "conversion_ts": "2026-04-16T10:20:08Z",
  "conversion_time_bucket": "2026-04-16T10:20:00Z/5m",
  "value": 59.99,
  "currency": "USD",
  "device_scoped_query_key": "qk_9f2e1d5174",
  "query_nonce": "n_7d2a8e",
  "query_schema_version": "claim_v1"
}
```

#### 16.1.3 MMP 向三家 network 询问

- Network A：命中候选 click，返回 `yes`
- Network B：命中候选 click，返回 `yes`
- Network C：无候选记录，返回 `no`

MMP 收到的结果：

```json
[
  {
    "network_id": "netA",
    "claim": "yes",
    "claim_token": "ctok_netA_a1"
  },
  {
    "network_id": "netB",
    "claim": "yes",
    "claim_token": "ctok_netB_b1"
  },
  {
    "network_id": "netC",
    "claim": "no",
    "claim_token": null
  }
]
```

#### 16.1.4 MMP 裁决

MMP 按 last click 模型比较：

- Network A click time: `10:01:12Z`
- Network B click time: `10:04:35Z`

因此 winner 为 Network B。

最终只向 Network B 发送 finalize。

#### 16.1.5 这个样例暴露了什么

MMP 知道：

- A 和 B 都 claim
- C 没有 claim
- 最终 B 赢

MMP 不应知道：

- A、B 的原始日志明细
- loser 的更多 metadata
- A 或 B 内部为什么 claim 的全部规则细节

### 16.2 API 请求/响应样例

### 16.2.1 ClaimRequest 示例

```json
{
  "request_id": "req_20260416_1001_00017_netA",
  "mmp_id": "mmp_demo",
  "network_id": "netA",
  "conversion_id": "conv_20260416_00017",
  "query_hash": "qh_26f4ad7d",
  "query_schema_version": "claim_v1",
  "conversion_ts_bucket": "2026-04-16T10:20:00Z/5m",
  "event_name": "purchase",
  "app_id": "com.example.shop",
  "device_scoped_query_key": "qk_9f2e1d5174",
  "query_nonce": "n_7d2a8e",
  "sent_at": "2026-04-16T10:20:11Z",
  "request_signature": "sig_mmp_44f1"
}
```

### 16.2.2 ClaimResponse yes 示例

```json
{
  "request_id": "req_20260416_1001_00017_netA",
  "network_id": "netA",
  "claim": "yes",
  "claim_token": "eyJuZXR3b3JrX2lkIjoibmV0QSIsInJlcXVlc3RfaWQiOiJyZXFfMjAyNjA0MTZfMTAwMV8wMDAxN19uZXRBIiwiY29udmVyc2lvbl9pZCI6ImNvbnZfMjAyNjA0MTZfMDAwMTciLCJwb2xpY3lfdmVyc2lvbiI6InB2XzIwMjYwNDE2XzAxIiwiZXhwaXJ5X3RzIjoiMjAyNi0wNC0xNlQxMDoyNTowMFoiLCJ0b2tlbl9ub25jZSI6InRuX2ExIn0=.sigA",
  "policy_version": "pv_20260416_01",
  "response_expiry_ts": "2026-04-16T10:25:00Z",
  "response_signature": "sig_netA_resp_7c1"
}
```

### 16.2.3 ClaimResponse no 示例

```json
{
  "request_id": "req_20260416_1001_00017_netC",
  "network_id": "netC",
  "claim": "no",
  "claim_token": null,
  "policy_version": "pv_20260416_01",
  "response_expiry_ts": "2026-04-16T10:25:00Z",
  "response_signature": "sig_netC_resp_0d8"
}
```

### 16.2.4 FinalizeRequest 示例

```json
{
  "request_id": "fin_20260416_00017_netB",
  "conversion_id": "conv_20260416_00017",
  "network_id": "netB",
  "claim_token": "eyJuZXR3b3JrX2lkIjoibmV0QiIsInJlcXVlc3RfaWQiOiJyZXFfMjAyNjA0MTZfMTAwMV8wMDAxN19uZXRCIiwiY29udmVyc2lvbl9pZCI6ImNvbnZfMjAyNjA0MTZfMDAwMTciLCJwb2xpY3lfdmVyc2lvbiI6InB2XzIwMjYwNDE2XzAxIiwiZXhwaXJ5X3RzIjoiMjAyNi0wNC0xNlQxMDoyNTowMFoiLCJ0b2tlbl9ub25jZSI6InRuX2IxIn0=.sigB",
  "winner_model": "last_click_v1",
  "finalized_at": "2026-04-16T10:20:16Z",
  "request_signature": "sig_mmp_fin_2a4"
}
```

### 16.2.5 FinalizeResponse 示例

```json
{
  "request_id": "fin_20260416_00017_netB",
  "accepted": true,
  "settlement_ref": "set_20260416_7751",
  "response_signature": "sig_netB_fin_8a2"
}
```

### 16.3 ad network 内部索引样例

假设 Network A 的 `Hot Claim Index` 中存在如下三条记录：

```json
[
  {
    "opaque_match_key": "omk_b8db2f5d7d2a",
    "touch_type": "click",
    "touch_ts": "2026-04-16T10:01:12Z",
    "touch_time_bucket": "2026-04-16T10:00:00Z/5m",
    "campaign_ref": "cmp_A_42",
    "attribution_priority": 100,
    "eligibility_expiry_ts": "2026-04-23T10:01:12Z",
    "fraud_state": "clear",
    "dedupe_state": "unused",
    "record_mac": "mac_1"
  },
  {
    "opaque_match_key": "omk_b8db2f5d7d2a",
    "touch_type": "impression",
    "touch_ts": "2026-04-16T09:55:00Z",
    "touch_time_bucket": "2026-04-16T09:55:00Z/5m",
    "campaign_ref": "cmp_A_42",
    "attribution_priority": 10,
    "eligibility_expiry_ts": "2026-04-17T09:55:00Z",
    "fraud_state": "clear",
    "dedupe_state": "unused",
    "record_mac": "mac_2"
  },
  {
    "opaque_match_key": "omk_ffffeeee1111",
    "touch_type": "click",
    "touch_ts": "2026-04-16T10:03:45Z",
    "touch_time_bucket": "2026-04-16T10:00:00Z/5m",
    "campaign_ref": "cmp_A_99",
    "attribution_priority": 100,
    "eligibility_expiry_ts": "2026-04-23T10:03:45Z",
    "fraud_state": "clear",
    "dedupe_state": "unused",
    "record_mac": "mac_3"
  }
]
```

对于 `device_scoped_query_key = qk_9f2e1d5174`，Network A 内部映射到 `opaque_match_key = omk_b8db2f5d7d2a`，于是 claim service 的判断过程是：

1. 找到两条候选记录：一条 click、一条 impression
2. conversion 时间是 `10:20:08Z`
3. click 在 7 天 click-through 窗口内
4. fraud_state = `clear`
5. dedupe_state = `unused`
6. 因为 click 已足够支持 claim，所以返回 `yes`

如果内部 policy 是 click 优先于 impression，则：

- yes/no 决策不需要把两条记录都暴露给 MMP
- MMP 也不需要知道这里其实还有一条 impression 候选

### 16.4 replay / probing 攻击反例

下面是一个 MMP 试图探测 attribution boundary 的错误做法。

假设同一个 conversion 被重复询问三次，只是轻微修改时间：

```json
[
  {
    "conversion_id": "conv_probe_01",
    "conversion_ts_bucket": "2026-04-16T10:20:00Z/5m",
    "device_scoped_query_key": "qk_9f2e1d5174"
  },
  {
    "conversion_id": "conv_probe_01",
    "conversion_ts_bucket": "2026-04-16T10:25:00Z/5m",
    "device_scoped_query_key": "qk_9f2e1d5174"
  },
  {
    "conversion_id": "conv_probe_01",
    "conversion_ts_bucket": "2026-04-16T10:30:00Z/5m",
    "device_scoped_query_key": "qk_9f2e1d5174"
  }
]
```

如果 network 每次都老实回答，那么 MMP 可能逐步推断出：

- click 离 conversion 有多远时还会 claim
- 某个 network 的 attribution window 或内部 gate 边界

推荐防护：

1. `query_hash` 绑定标准化后的 conversion query
2. 同一个 `conversion_id` 只能接受一次或有限次 claim 查询
3. 时间戳必须桶化，不能接受任意精细度探测
4. 命中 replay cache 时直接拒绝或打低信任分

推荐的拒绝响应示例：

```json
{
  "request_id": "req_probe_002",
  "network_id": "netA",
  "claim": "no",
  "claim_token": null,
  "policy_version": "pv_20260416_01",
  "response_expiry_ts": "2026-04-16T10:31:00Z",
  "response_signature": "sig_netA_probe_blocked"
}
```

说明：

- 对外仍然维持简单响应结构
- 但内部会把这类行为记录到 probing audit log

### 16.5 后台 PJC 对账样例

前台 yes/no claim 只能解决“谁有资格 claim”，并不适合解决 campaign-level 的对账与结算。

假设某个 campaign 在一天内的数据如下。

MMP 持有的 conversions：

```text
u1 -> value 10
u2 -> value 20
u3 -> value 30
u4 -> value 40
```

Network B 持有的已归因 touch 用户集合：

```text
u2
u3
u5
```

如果双方直接交换明文集合：

- MMP 会知道 network 的覆盖集合
- network 会知道 MMP 的全部转化用户

使用后台 PJC / PI-Sum 时，目标只输出：

```text
intersection cardinality = 2
intersection value sum = 50
```

因为交集是：

```text
u2 -> 20
u3 -> 30
```

这个例子说明：

- 前台 claim API 适合逐条资格判断
- 后台 PJC 更适合做聚合验证与 settlement
- 两者并不冲突，而是互补

### 16.6 claim token 验证样例

假设 Network B 收到一个 finalize 请求，其中 `claim_token` 解码后的载荷为：

```json
{
  "network_id": "netB",
  "request_id": "req_20260416_1001_00017_netB",
  "conversion_id": "conv_20260416_00017",
  "query_hash": "qh_26f4ad7d",
  "policy_version": "pv_20260416_01",
  "issued_at": "2026-04-16T10:20:12Z",
  "expiry_ts": "2026-04-16T10:25:00Z",
  "token_nonce": "tn_b1"
}
```

Network B 的 finalize service 会检查：

1. 签名是否正确
2. `network_id` 是否是自己
3. `conversion_id` 是否与请求一致
4. token 是否过期
5. `token_nonce` 是否已被消费
6. `policy_version` 是否仍被允许 finalize

全部通过后：

- 写入 finalize cache
- 将 `token_nonce` 标记为已使用
- 返回 `accepted = true`

如果 token 被重放，则返回：

```json
{
  "request_id": "fin_20260416_00017_netB_retry",
  "accepted": false,
  "settlement_ref": null,
  "response_signature": "sig_netB_fin_reject_replay"
}
```

### 16.7 最小伪代码样例

下面是一段足够接近真实实现、但又不依赖具体语言框架的伪代码。

```text
function eligible_to_claim(claim_request):
    assert verify_signature(claim_request.request_signature)
    normalized_query = normalize(claim_request)
    query_hash = hash(normalized_query)

    if replay_cache.contains(query_hash):
        return no_response()

    opaque_match_key = map_query_key_to_match_key(
        claim_request.device_scoped_query_key
    )

    candidates = hot_claim_index.lookup(opaque_match_key)
    candidates = filter_by_window(candidates, claim_request.conversion_ts_bucket)
    candidates = filter_by_fraud_state(candidates, "clear")
    candidates = filter_by_dedupe_state(candidates, "unused")
    candidates = apply_touch_precedence(candidates)

    replay_cache.put(query_hash)

    if candidates.is_empty():
        return no_response()

    token = mint_claim_token(claim_request, candidates.best_policy_version)
    return yes_response(token)
```

这段伪代码想说明的不是实现细节，而是顺序：

- 先做请求校验和 replay 防护
- 再查最小化索引
- 再应用 eligibility 规则
- 最后才决定 yes/no 和是否铸造 token
