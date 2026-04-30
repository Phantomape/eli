# On-Device Measurement RFC

状态: Draft<br>
最后更新: 2026-04-30<br>
适用对象: Ad Network, Advertiser App, MMP/AAP, Privacy Infra, SDK, Data Infra, ML Platform

## 1. 摘要

本文把 `on-device measurement` 整理成一份面向广告场景的工程 RFC。目标不是解释几个公式，而是定义一套从端上采集、MMP/SRN 协同、服务端 confidential join、request-level optimization、aggregate reporting 到后续 DP 加固的完整规范。

核心结论只有三条：

1. `on-device measurement` 不等于“设备上算个 token 再上传”。
2. 如果要支撑 personalized optimization，就必须保留服务端生成的 `server_request_id` 这类 request-scoped join key，但它只能存在于严格受控的数据面。
3. MMP 的 SRN 流程仍然是现实世界的主协议形态，因此系统必须围绕 `MMP Ask -> Ad Network Claim -> MMP Confirm` 设计，而不是试图绕过它。

2026-04-30 追加的 ODM / ODC HAR 逆向把第 1 点进一步具体化：Google-compatible 路径很可能包含 `config -> OPRF/PSM candidate retrieval -> local filtering -> validate` 子流程，最终 `odm_info` 是该子流程之后的 bridge object，而不是单个本地 token。

本文刻意兼顾生产实用性：

- 不使用 toy 算法替代生产组件；
- 优先复用公开可用的 SDK、TEE/CVM、DP、审计和训练库；
- 在能放松的地方明确放松，例如 Phase 1 不强制 optimization plane 上 DP；
- 在不能放松的地方明确收紧，例如不允许把 `odm_info` 演化为长期标识符。

## 2. 背景与问题定义

在现代移动广告里，存在四个同时成立的现实：

1. 广告主 App 内嵌 ad network SDK，SDK 在设备侧能观察到 impression、click、install、purchase，以及 `boot_time`、原始 `ip`、网络类型、时区、设备 uptime、重装痕迹等敏感或半敏感信号。
2. MMP / AAP 与 Self-Reporting Network（SRN）的主协议仍然是“先检测 install，再向广告网络查询，再由网络 claim，再由 MMP confirm”。
3. 广告网络为了持续优化出价、排序、反作弊和预算分配，仍然需要 request-level 的监督信号，而不仅仅是 aggregate count。
4. 隐私边界必须比传统 click-ID 或 device-ID 时代更强，尤其不能把原始高敏感信号直接沉入普通数仓。

因此，本文讨论的 `on-device measurement` 不是“纯端上闭环”。更准确地说，它是一个三层系统：

- 设备侧保留原始敏感观察；
- 设备侧只上送 task-bound、TTL-bound、contribution-bound 的 artifact；
- 服务端只在 confidential boundary 内完成验证、join、label 物化，再分层释放到 optimization plane 和 aggregate reporting plane。

## 3. 设计目标与非目标

### 3.1 目标

- 定义广告场景下可落地的 on-device measurement 端到端协议。
- 支撑 MMP SRN 协议协同，而非脱离 MMP 单独设计。
- 支撑 request-level personalized optimization，而不只是 aggregate measurement。
- 定义字段级 schema、mock payload、生命周期、TTL、anti-replay 和治理边界。
- 为后续 DAP/VDAF、DP、PJC/PSI、verifiable workflow 留出升级路径。

### 3.2 非目标

- 第一天就把所有服务端信任替换成 MPC。
- 第一天就让 optimization plane 满足严格 user-level DP。
- 把所有模型训练改造成 federated learning。
- 试图定义适配所有 ad network、所有 MMP、所有司法辖区的唯一通用标准。

## 4. 最小心智模型

可以用八步理解整个系统：

1. 广告请求发生时，ad network backend 生成一次性的 `server_request_id:int64`。
2. ad network SDK 在设备侧观察 impression、click、install、purchase，以及本地敏感信号。
3. 设备侧把原始观察压缩成两个对象：
   - 发给 ad network confidential backend 的 `OnDeviceMeasurementArtifact`
   - 透传给 MMP/AAP 的 `ODMInfoEnvelope`
4. MMP 观察到 install 或 event 后，发起 `MmpAskRequest`。
5. ad network 在 confidential plane 内验证 artifact、task binding、TTL、replay，再返回 `ClaimResponse`。
6. MMP 完成 winner 选择后，再回传 `MmpConfirmRequest`。
7. ad network 在 confidential plane 中把 `AdRequestContext + Artifact + Confirm` join 成：
   - `RequestScopedOptimizationLabel`
   - `AggregateMeasurementContribution`
8. downstream 分层消费：
   - optimization plane 消费 request-level label
   - aggregate reporting plane 消费 thresholded / bounded / optional-DP 的聚合输出

## 5. 截至 2026-04-29 的研究与标准更新

这一节只保留会影响系统设计的结论。

### 5.1 Ephemeral on-device analytics 已经工程化

Google Research 2024 的 [Mayfly](https://research.google/pubs/mayfly-private-aggregate-insights-from-ephemeral-streams-of-on-device-user-data/) 证明了三件事：

- 敏感原始流可以保留在设备侧的短期窗口内，而不是永久中心化存储；
- query template、windowing、contribution bounding 应当是协议主体，不是实现细节；
- 上行对象可以是受限 artifact，而不是完整明细。

对本 RFC 的直接影响是：

- `measurement_task_id`
- `query_template_id`
- `observation_window_sec`
- `contribution_policy_id`

这些都必须进入协议对象，而不是只写在内部 wiki。

### 5.2 Confidential server-side processing 已经不是“概念”

[Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)（2024）和 [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute) 说明：

- 服务端可以在 TEE/CVM 中完成隐私敏感的 processing graph；
- 上传对象可以绑定允许的 workflow；
- verifiable processing 需要 manifest、signature、attestation，而不是只说“我们会小心处理”。

因此，本 RFC 采用 `confidential plane` 作为 request-level join 的默认部署边界。

### 5.3 DAP / VDAF / Taskprov 已经足够成熟到值得对齐对象模型

截至 2026-04-29：

- [DAP draft-ietf-ppm-dap-17](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/) 最近一次更新时间是 2026-01-30；
- [DAP Taskprov draft-ietf-ppm-dap-taskprov-03](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap-taskprov/) 最近一次修订发布于 2025-09-05，且 datatracker 在 2026-03-16 将其标记为 expired & archived，但其中的 task binding 语义仍然直接可用；
- [VDAF draft-irtf-cfrg-vdaf-19](https://datatracker.ietf.org/doc/draft-irtf-cfrg-vdaf/) 最近一次更新时间是 2026-04-14；
- [DAP Extensions for the Attribution API draft-thomson-ppm-dap-attribution-01](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/) 最近一次更新时间是 2026-02-17，让 attribution 类 measurement 与 PPM/DAP 更接近。

这意味着即使 Phase 1 不直接部署完整 DAP，aggregate object model 也应该主动对齐：

- `task`
- `report_id`
- `batch_id`
- `task_expiration`
- `extension_fields`

更进一步，aggregate plane 不应再停留在“以后再看怎么聚合”的抽象层。既然 VDAF 对象模型已经稳定，生产 RFC 应直接偏向已有 primitive：

- `Prio3Count`
  - 适合 install / purchase user count
- `Prio3Sum`
  - 适合 revenue、cost、value sum
- `Prio3Histogram`
  - 适合 retention day bucket、latency bucket、value bucket
- `Prio3SumVec`
  - 适合多维 campaign bucket 的固定长度向量聚合

这样做的意义不是“马上部署完整 DAP/VDAF”，而是避免 aggregate schema 将来卡死在自定义半协议上。

### 5.4 Contribution bounding 现在是生产问题，不是论文角落

[Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)（2025）以及 [It's My Data Too](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)（ICML 2025）都指向同一件事：

- 一个训练样本可能对应多个“拥有者”或多个 touch；
- multi-touch / multi-user 数据里，contribution bounding 是一等公民；
- 如果 bounding 只藏在离线 SQL 里，后续隐私和训练质量都不可控。

因此，本 RFC 要求：

- `conversion_group_id`
- `credit_fraction_micros`
- `contribution_policy_id`

必须进入 label contract。

### 5.5 交互式 release 的隐私分析已经不能忽略

[On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)（PETS 2025）强调：

- 查询会依赖之前的输出；
- 数据库本身也会因为系统状态变化而变化；
- release 不能被当成“静态 SQL 导出”。

对本 RFC 的含义是：

- aggregate reporting 必须有显式 budget ledger；
- provisional / final / correction 必须有规则；
- 任何重复 collect 都必须视为额外 privacy cost 或额外治理风险。

### 5.6 “DP 可审计”已经从研究走向工程

[DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)（2024）和 [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)（NeurIPS 2025）说明：

- DP 不能只信数学证明和实现自信；
- 黑盒审计、持续审计、序列式审计都已经可做；
- 如果后续引入 DP release，审计栈应该提前预留。

### 5.7 TEE 不是 magic box

2026 年的 [SNPeek](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/) 和 [TDXRay](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/) 说明：

- Confidential VM 仍然存在 side-channel 风险；
- 工作负载本身必须考虑 access pattern、timing、batching、debug 策略；
- “放进 TEE 就安全”是错误的。

因此，本 RFC 对 confidential workflows 要求分级、限 debug、加回归测试。

### 5.8 公开产品形态已经验证 ODM / ICM 是现实路径

截至 2026-04-29：

- Google Ads 帮助文档显示 [Integrated Conversion Measurement](https://support.google.com/google-ads/answer/16203286?hl=en-EN) 自 2025 年 5 月起逐步 rollout；
- [on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en) 文档指出 event-data 方案使用临时、去标识化事件数据，且 Firebase iOS SDK `11.14.0` 于 2025 年 6 月提供相关版本；
- [request/response spec](https://developers.google.com/app-conversion-tracking/api/request-response-specs) 已明确 `odm_info` 是 ICM 所需字段；
- [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk) 说明 standalone SDK 路线可行。

同时，Google 2026 年的产品文档还把两个生产边界写得更清楚了：

- [Understanding iOS App campaign measurement and reporting](https://support.google.com/google-ads/answer/16771743) 明确 ICM 是 AAP UI 中的 granular, event-level, cross-network view，而不是 Google Ads UI 中的同一条 reporting surface；
- [on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en) 明确该功能对位于 `EEA`、`UK`、`Switzerland` 的用户 inactive。

这直接支持本文把 `ODMInfoEnvelope` 视为正式协议对象，而不是 SDK 内部细节；也支持把 `reporting_surface_id`、`region_eligibility_code` 和 `feature_active=false` 视为正式状态，而不是埋在 FAQ 里的例外逻辑。

### 5.9 MMP 的 SRN 工作流没有消失

[AppsFlyer SRN 文档](https://support.appsflyer.com/hc/en-us/articles/360001546905-Self-Reporting-Networks) 和 [Adjust SAN 文档](https://help.adjust.com/en/marketer/self-attributing-networks) 仍表明：

- MMP / attribution provider 先检测 install / event；
- 再向 self-reporting network 查询或通知；
- network 基于自身 engagement data 做 claim；
- 某些回调和 postback 仍依赖 device ID 或 network-specific transaction object。

所以，on-device measurement 必须服务于 SRN，而不是与 SRN 平行、互不相干。

进一步地，截至 2026-04-29，产品文档还显示两个值得写进 RFC 的现实：

- [AppsFlyer attribution model](https://support.appsflyer.com/hc/en-us/articles/207447053-AppsFlyer-attribution-model) 页面在 2026-04-19 更新，仍明确区分 deterministic、probabilistic、SRN query、assist 等多条归因路径；
- [AppsFlyer Enhanced attribution model](https://support.appsflyer.com/hc/en-us/articles/41442782045073-About-the-Enhanced-attribution-model) 在 2026-03-19 公开说明了设备侧 flooding 检测后仅保留 eligible click / impression 的做法。

这对本文的直接影响是：

- RFC 不能只建模“最后一次 click 是否胜出”，还要建模 `eligible_candidate_count`、`prefilter_candidate_count`、`assist_count` 这类质量上下文；
- request-level optimization 不能只消费二元 `is_attributed`，还应消费 winner 选择过程中的质量切片与延迟反馈。

### 5.10 Privacy Sandbox 的 aggregate 优化研究说明 bucket 设计本身也是协议

[Summary Reports Optimization in the Privacy Sandbox Attribution Reporting API](https://research.google/pubs/summary-reports-optimization-in-the-privacy-sandbox-attribution-reporting-api/)（PETS 2024）虽然主要针对 Attribution Reporting API，但对本 RFC 有一个很现实的启发：

- 同样的 privacy guardrail 下，bucket 设计和 contribution budget 分配会显著影响可用性；
- “先把数据聚出来，之后分析时再想怎么切桶” 往往太晚；
- measurement task、aggregation key、value bucket、reporting window 应一起设计。

因此，本 RFC 把 `aggregation_key_schema_id`、`value_bucket_schema_id`、`reporting_window_id` 视为 production contract，而不是 BI 侧随手改的维表配置。

### 5.11 W3C Attribution Level 1 让 aggregate plane 的边界更清晰

[W3C Attribution Level 1](https://www.w3.org/TR/privacy-preserving-attribution/) 在 2026-04-28 发布了新的 Working Draft。它最重要的启发不是“移动 App 要照搬浏览器 API”，而是进一步确认了四件事：

- on-device attribution 与 off-device aggregation 可以明确分层；
- aggregate service `MUST` 处理 anti-replay，而不是只做求和；
- privacy budget、epoch 和 per-site / per-surface 限额应该是正式协议状态，而不是分析平台外部约定。
- multi-party aggregation、DAP/VDAF 和 collector state 应作为一等设计对象进入协议，而不是留给后续实现随意发挥。

对本 RFC 的意义是：广告 App 场景里的 aggregate reporting plane 也应该显式拥有 `budget ledger + replay rejection + report lifecycle + collector identity`，而不是只导出一个聚合表。

### 5.12 Verifiable local reporting 说明“端上上报正确性”也要入 RFC

[Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)（2025）指出一个很现实的问题：

- 只要 measurement 的部分逻辑发生在设备侧，系统就不只是担心“服务端看太多”，还要担心“端上报了假的东西”；
- 本地私有化或本地裁剪后的上报，如果没有 provenance 约束，容易被 poisoning、flooding、伪造 engagement 或脚本化设备利用；
- 可验证随机性、第三方 ground truth、或至少更强的 event provenance，会明显改变系统可用性上限。

对广告场景的直接含义是：

- RFC 不能只定义 `artifact` 长什么样，还要定义 `artifact` 证明了什么；
- 端上 `impression` / `click` / `first_open` / `purchase` 的来源级别，应该进入 policy；
- `artifact_auth_level`、`event_provenance`、`sdk_build_fingerprint` 这类字段值得成为正式 contract，而不是埋在风控旁路里。

### 5.13 ODC / ODM 逆向证据把 OPRF / PSM 放回主链路

2026-04-14 的 Google ODC / ODM HAR 样本，以及 2026-04-30 的 wire-format 逆向整理，给了一个比公开产品文档更具体的实现信号。样本来自 `com.underdogsports.fantasy`，SDK 为 `odm-sdk-i-v3.2.0`，`source=aaps`。它不是官方 SDK 文档，但足以改变本 RFC 对 Google ODM 兼容层的默认模型。

可直接从 HAR 确认的链路是：

```text
GET  /odm/config
POST /odm/psm
POST /odm/validate
```

关键观察：

- `/odm/config` 返回 `matching_id`、`bucketed_date`、`prefix_length=22`、`extension_data`；其中 `extension_data` 在后续请求里以 `odmed` 原样复用。
- `/odm/psm` request 中的 `psm_request` 解码后为 50 bytes，包含 3-byte prefix-like blob、33-byte compressed EC point、`prefix_length=22` 参数和 `mode=35`。
- `/odm/psm` response 解码后约 123KB，核心 payload 是 `1009` 条 candidate rows，而不是一个单值 membership result。
- response header 中有两个 33-byte compressed EC points，第一个与 request 里的 blinded point 一致，第二个很像服务端 OPRF evaluation 或 VOPRF proof element。
- `/odm/validate` body 是 `mvs + odmed`，response 返回渠道化 measurement values：`mv_ga4f` 与 `mv_aaps`。

因此，Google ODM 的现实路径不应再被描述成“端上算一个 opaque token 后直接上传”。更贴近 HAR 的模型是：

```text
Config 下发上下文
  -> Client 生成 prefix bucket + EC blinded query
  -> Server 对 blinded point 做 OPRF/PSM 评估，并返回该 prefix bucket 下的候选记录集合
  -> Client 本地 unblind / derive key / filter or decrypt candidate rows
  -> Client 生成 mvs
  -> Validate 派生 mv_ga4f / mv_aaps
  -> SDK 暴露 aggregateConversionInfo / odm_info 给后续归因或上报链路
```

这也修正了几条旧判断：

- `matching_id` 不是 `/psm` 成功后签发；它在 `/config` 阶段已返回，更像 opaque context / cache key / correlation key。
- `tfo=1776212580` 按 Unix epoch 秒解释接近抓包本地时间，不像 “time from first open” duration。
- Paillier / PIR 仍可作为更强隐私设计方案，但当前 HAR 没有 Paillier selection vector 或 2048-bit ciphertext 的形态；主链路更像 `OPRF + prefix bucket candidate retrieval + client-side local filtering`。
- `boot_time` 仍然可能参与本地 material 或 `mvs` 构造，但当前 HAR 中没有明文字段证明它进入 ODM PSM 主链路。

## 6. 总体架构

### 6.1 逻辑平面

系统划分为四个数据面：

1. `Device Raw Plane`
   - 位置: advertiser app + ad network SDK
   - 内容: 原始 install / event、本地敏感信号、原始 `boot_time`、原始 `ip`
   - 生命周期: 极短
2. `Confidential Plane`
   - 位置: TEE/CVM 或严格隔离的 confidential service
   - 内容: artifact 验证、SRN claim/confirm join、敏感特征派生
   - 生命周期: 中短期，受 retention policy 控制
3. `Optimization Plane`
   - 位置: 训练样本与线上优化系统
   - 内容: request-scoped label、低敏派生特征、campaign context
   - 禁止内容: 原始 `ip`、原始 `boot_time`、`odm_info`
4. `Aggregate Reporting Plane`
   - 位置: partner-facing / BI-facing aggregate service
   - 内容: bounded, thresholded, optional-DP aggregate outputs

### 6.2 三类关键键

- `server_request_id:int64`
  - 服务端生成
  - 一次 ad request 唯一
  - 是 optimization join key
  - 不是 user ID
- `artifact_id:bytes`
  - 设备侧生成或设备侧签名对象中的唯一标识
  - 只代表一次 measurement artifact
  - 不是长期标识符
- `odm_info:string`
  - 端上生成并透传给 MMP/AAP 的 opaque envelope
  - 是 bridge object
  - 不能被二次用途化为 durable identifier

## 7. 端到端数据流

### 7.1 Step A: Ad Request

ad network backend 生成广告请求上下文：

- `server_request_id:int64`
- `auction_id:int64`
- `campaign_id:int64`
- `creative_id:int64`
- `placement_id:int64`
- `request_ts_ms:int64`
- `publisher_app_id:string`
- `country_code:string`
- `consent_scope:uint32`
- `measurement_task_id:string`

### 7.2 Step B: Ad Response / Exposure

SDK 在设备侧拿到最小必要元数据：

- `server_request_id`
- `auction_id`
- `ad_network_id:int32`
- `campaign_id`
- `creative_id`
- `measurement_task_id`

随后记录：

- `impression_ts_ms:int64`
- `click_ts_ms:int64?`
- `local_event_seq:int32`

### 7.3 Step C: Device Observation

SDK 观察到以下本地信号，但默认不直接外发原值：

- `boot_time_ms:int64`
- `device_uptime_ms:int64`
- `raw_ip:bytes`
- `network_type:enum`
- `timezone_offset_min:int32`
- `locale:string`
- `disk_reinstall_hint:bool`
- `bundle_first_install_ts_ms:int64`

这些信号仅用于：

- 端上匹配
- 端上去重
- 端上 risk scoring
- confidential plane 派生特征

### 7.4 Step D: On-Device Artifact Construction

SDK 生成两类对象：

- `OnDeviceMeasurementArtifact`
  - 发往 ad network confidential endpoint
- `ODMInfoEnvelope`
  - 缓存在 app 或 advertiser server，并透传给 MMP / AAP downstream event

### 7.4B Observed Google ODM / ODC Construction Flow

Google ODM / ODC 的逆向样本显示，真实 SDK 可以把 Step D 拆成一个带服务端辅助的本地匹配流程，而不是纯本地 artifact 构造：

1. `GET /odm/config`
   - SDK 拉取 `prefix_length`、`bucketed_date`、`extension_data/odmed` 和 `matching_id`。
2. `POST /odm/psm`
   - SDK 发送 `odmed` 与 `psm_request`。
   - `psm_request` 包含 prefix bucket、compressed EC blinded point、协议参数和 mode id。
   - 服务端返回 OPRF-like header 与该 prefix bucket 下的 candidate set。
3. Local candidate processing
   - SDK 验证 echoed blinded point。
   - SDK unblind server evaluation，派生 row key。
   - SDK 扫描候选行，使用 tag / encrypted package / row meta 完成本地过滤或解密。
4. `POST /odm/validate`
   - SDK 提交 opaque `mvs` 与 `odmed`。
   - 服务端返回 `mv_ga4f`、`mv_aaps` 等渠道化 measurement values。

这意味着本 RFC 的 `OnDeviceMeasurementArtifact` 与 `ODMInfoEnvelope` 应被理解为逻辑对象：具体产品实现可以在生成 envelope 之前先完成一次 `config -> psm -> validate` 子状态机。协议治理上仍然要约束最终外发对象的 TTL、task binding、replay 与用途绑定，但实现层需要给 OPRF/PSM 中间态留出清晰边界。

### 7.5 Step E: MMP Ask

MMP 检测到 install / first_open / purchase 后，向 ad network 发起查询：

- 包含 MMP 常规 query fields
- 包含 `odm_info`
- 包含 MMP 事件上下文

### 7.6 Step F: Ad Network Claim

ad network 在 confidential plane 内：

- 校验 `odm_info` 与 `artifact_id`
- 校验 task binding
- 校验 TTL
- 校验 anti-replay
- 可选结合 network engagement log、fraud policy、MMP query template 进行 claim

返回：

- `claim_status`
- `claim_token`
- `claim_confidence`
- `measurement_task_id`

### 7.7 Step G: MMP Confirm

MMP 根据全局 winner selection 结果回传：

- `mmp_decision`
- `winning_touch_ts_ms`
- `confirm_ts_ms`
- `claim_token`

### 7.8 Step H: Confidential Join and Release

ad network 在 confidential plane 中 join：

- `AdRequestContext`
- `OnDeviceMeasurementArtifact`
- `MmpAskRequest`
- `ClaimResponse`
- `MmpConfirmRequest`

输出两个主对象：

- `RequestScopedOptimizationLabel`
- `AggregateMeasurementContribution`

## 8. 协议对象与 schema

以下 schema 是 RFC 的逻辑规范，生产实现建议使用 `Protobuf + buf` 管理。

### 8.1 AdRequestContext

```proto
message AdRequestContext {
  int64 server_request_id = 1;
  int64 auction_id = 2;
  int64 campaign_id = 3;
  int64 creative_id = 4;
  int64 placement_id = 5;
  int64 advertiser_id = 6;
  int64 publisher_app_numeric_id = 7;
  string publisher_app_bundle = 8;
  int64 request_ts_ms = 9;
  string country_code = 10;
  string region_code = 11;
  uint32 consent_scope = 12;
  string measurement_task_id = 13;
  string contribution_policy_id = 14;
  string feature_policy_id = 15;
  string retention_policy_id = 16;
}
```

### 8.2 DeviceLocalObservation

此对象默认不出设备，不进入普通日志，仅作为本地或 confidential 输入：

```proto
message DeviceLocalObservation {
  int64 boot_time_ms = 1;
  int64 device_uptime_ms = 2;
  bytes raw_ip = 3;
  string ip_version = 4;
  string timezone_name = 5;
  int32 timezone_offset_min = 6;
  string locale = 7;
  string network_type = 8;
  bool reinstall_hint = 9;
  int64 bundle_first_install_ts_ms = 10;
}
```

### 8.3 OnDeviceMeasurementArtifact

```proto
message OnDeviceMeasurementArtifact {
  bytes artifact_id = 1;
  string artifact_version = 2;
  string measurement_task_id = 3;
  int64 server_request_id = 4;
  int64 impression_ts_ms = 5;
  int64 click_ts_ms = 6;
  int64 conversion_candidate_ts_ms = 7;
  uint32 observation_window_sec = 8;
  bytes derived_match_key = 9;
  bytes derived_risk_key = 10;
  bytes encrypted_feature_blob = 11;
  bytes query_template_commitment = 12;
  int64 artifact_expiry_ts_ms = 13;
  bytes replay_nonce = 14;
  string workflow_manifest_digest = 15;
  bytes sdk_attestation = 16;
}
```

字段解释：

- `derived_match_key`
  - 端上从敏感信号导出的 task-bound、短生命周期匹配键
- `derived_risk_key`
  - 端上为 fraud / replay / reinstall 辅助生成的键
- `encrypted_feature_blob`
  - 只允许 confidential plane 解密

### 8.4 ODMInfoEnvelope

```proto
message ODMInfoEnvelope {
  string odm_info = 1;
  string odm_version = 2;
  string measurement_task_id = 3;
  int64 info_generated_ts_ms = 4;
  int64 info_expiry_ts_ms = 5;
  bytes artifact_id_hash = 6;
  bytes query_hash = 7;
}
```

约束：

- `odm_info` `MUST` 是 opaque string。
- `odm_info` `MUST NOT` 作为 durable user ID 使用。
- `odm_info` `MUST` 绑定 `measurement_task_id` 和 expiry。

### 8.4B Observed Google ODM Wire Objects

以下对象不是本 RFC 要求外部 partner 直接实现的公开 schema，而是 2026-04-14 HAR 样本中可解析出的 Google ODM / ODC 内部 wire shape。它们用于校准兼容层和威胁模型。

```proto
message ObservedOdmConfig {
  bytes matching_id = 1;      // decoded len=32; returned by /odm/config
  string bucketed_date = 2;   // observed: 2026-04-13
  uint32 prefix_length = 3;   // observed: 22
  bytes extension_data = 4;   // decoded len=16; reused as odmed
}

message ObservedPsmRequest {
  bytes query_material = 1;   // nested prefix + compressed EC point
  bytes params = 2;           // includes prefix_length=22
  uint32 mode = 3;            // observed: 35
}

message ObservedPsmQueryMaterial {
  bytes prefix_bucket = 1;    // observed len=3; fits 22-bit prefix
  bytes blinded_point = 2;    // observed len=33; compressed EC point
}

message ObservedPsmResponseCore {
  bytes ec_header = 1;        // two 33-byte compressed EC points
  uint32 mode = 4;            // observed: 35
  bytes candidate_payload = 5;// observed len=123098
  bytes crypto_params = 7;    // mode=35, key_or_curve_size=256, scheme=2
}

message ObservedCandidatePayload {
  repeated bytes quick_tag = 1;       // 1009 items x 1 byte
  repeated bytes crypto_package = 2;  // 1009 items x 77 bytes
  repeated bytes row_meta = 3;        // 1009 items x 38 bytes
}

message ObservedValidateRequest {
  bytes mvs = 1;              // opaque MVS material, decoded envelope len=63
  bytes odmed = 2;            // same as /odm/config extension_data
}
```

Compatibility guidance:

- Treat `matching_id`, `odmed`, `mvs`, `mv_ga4f`, `mv_aaps`, and final `odm_info` as opaque protocol artifacts unless the SDK owner publishes a stable schema.
- Do not persist `matching_id` or `odmed` as durable user identity. Even if they are stable within a context, their safe interpretation is task-bound control material.
- Model the PSM stage as candidate retrieval plus local filtering, not as server-returned ground truth. Attribution truth should still be represented by explicit claim / confirm state.

### 8.5 MmpAskRequest

```proto
message MmpAskRequest {
  string mmp_name = 1;
  string mmp_event_id = 2;
  string mmp_install_id = 3;
  string app_bundle = 4;
  string platform = 5;
  int64 install_ts_ms = 6;
  int64 event_ts_ms = 7;
  string event_name = 8;
  string id_type = 9;
  string device_id = 10;
  string odm_info = 11;
  string query_template_id = 12;
  bytes query_hash = 13;
  string country_code = 14;
  map<string, string> additional_fields = 15;
  string ask_idempotency_key = 16;
  int64 ask_attempt_ts_ms = 17;
  string query_contract_id = 18;
}
```

说明：

- `device_id` 可是 `idfa`、`idfv`、`gaid`、`appsetid`，也可能为空或全零。
- `odm_info` 用于让 network 在缺少稳定 device ID 时仍可进行 privacy-preserving claim。

### 8.6 ClaimResponse

```proto
message ClaimResponse {
  string mmp_event_id = 1;
  string claim_status = 2; // CLAIMED, DECLINED, SOFT_DECLINED
  bytes claim_token = 3;
  float claim_confidence = 4;
  string measurement_task_id = 5;
  int64 claim_ts_ms = 6;
  int64 claim_expiry_ts_ms = 7;
  bytes replay_cache_key = 8;
  string policy_version = 9;
  string claim_reason_code = 10;
  bool request_accepted = 11;
}
```

### 8.7 MmpConfirmRequest

```proto
message MmpConfirmRequest {
  string mmp_event_id = 1;
  bytes claim_token = 2;
  string final_decision = 3; // WIN, LOSE, IGNORE
  int64 confirm_ts_ms = 4;
  int64 winning_touch_ts_ms = 5;
  string winning_network = 6;
  map<string, string> attribution_metadata = 7;
  string confirm_idempotency_key = 8;
  int64 confirm_attempt_ts_ms = 9;
}
```

### 8.8 RequestScopedOptimizationLabel

```proto
message RequestScopedOptimizationLabel {
  int64 server_request_id = 1;
  int64 advertiser_id = 2;
  int64 campaign_id = 3;
  int64 creative_id = 4;
  int64 placement_id = 5;
  int64 label_ts_ms = 6;
  string label_type = 7; // install, first_open, purchase, roas_7d
  double label_value = 8;
  bool is_attributed = 9;
  float claim_confidence = 10;
  int64 conversion_group_id = 11;
  int32 credit_fraction_micros = 12;
  uint32 observation_window_sec = 13;
  bool right_censored = 14;
  string trainer_policy_id = 15;
  string feature_policy_id = 16;
  string contribution_policy_id = 17;
  string region_profile = 18;
  string network_stability_bucket = 19;
  string reinstall_hint_bucket = 20;
}
```

约束：

- `server_request_id` `MUST` 存在，否则 personalized optimization 会退化。
- 原始 `ip`、原始 `boot_time` `MUST NOT` 出现在该对象中。
- `credit_fraction_micros` 用于 multi-touch / fractional credit。

### 8.9 AggregateMeasurementContribution

```proto
message AggregateMeasurementContribution {
  string measurement_task_id = 1;
  string batch_id = 2;
  bytes report_id = 3;
  int64 contribution_ts_ms = 4;
  string metric_name = 5;
  double metric_value = 6;
  int64 conversion_group_id = 7;
  string aggregation_key = 8;
  string contribution_policy_id = 9;
  int64 task_expiry_ts_ms = 10;
}
```

### 8.10 PostInstallConversionEvent

这个对象代表 advertiser app 在 install 之后继续上报给 ad network / MMP 的 conversion 事件。它不是原始设备信号，也不是最终训练标签，而是进入 ask/claim/confirm 与 confidential join 之前的业务事件。

```proto
message PostInstallConversionEvent {
  int64 advertiser_event_id = 1;
  int64 advertiser_id = 2;
  string app_bundle = 3;
  string platform = 4;
  string event_name = 5; // first_open, purchase, subscribe, level_achieved
  int64 event_ts_ms = 6;
  int64 event_value_micros = 7;
  string currency_code = 8;
  string event_dedupe_key = 9;
  string odm_info = 10;
  int64 advertiser_user_id = 11;
  string event_schema_id = 12;
  map<string, string> event_dimensions = 13;
}
```

### 8.11 AttributionHandshakeState

这个对象把 `MMP Ask -> Ad Network Claim -> MMP Confirm` 从“几条日志”提升为正式状态机，方便生产排障、TTL、retry 和 winner/loser 归因裁决。

```proto
message AttributionHandshakeState {
  string handshake_id = 1;
  string mmp_event_id = 2;
  int64 server_request_id = 3;
  string measurement_task_id = 4;
  string ask_status = 5;     // RECEIVED, REJECTED, EXPIRED
  string claim_status = 6;   // CLAIMED, DECLINED, SOFT_DECLINED
  string confirm_status = 7; // PENDING, WIN, LOSE, IGNORED, EXPIRED
  int64 ask_ts_ms = 8;
  int64 claim_ts_ms = 9;
  int64 confirm_ts_ms = 10;
  int64 expiry_ts_ms = 11;
  string policy_version = 12;
  bytes replay_cache_key = 13;
  string failure_reason_code = 14;
}
```

### 8.12 ExternalAttributionCompatRecord

这个对象只服务于 partner API 兼容与 follow-up 请求，不属于 optimization plane 的训练明细。

```proto
message ExternalAttributionCompatRecord {
  string partner_name = 1; // google_app_conversion_api, appsflyer, adjust
  string api_contract_version = 2;
  string request_contract_id = 3;
  string app_bundle = 4;
  string platform = 5;
  string app_event_type = 6;
  int64 event_timestamp_sec_micros = 7;
  string odm_info = 8;
  string id_type = 9;
  string rdid = 10;
  string user_agent = 11;
  string x_forwarded_for = 12;
  string ad_event_id = 13;
  bool attributed = 14;
  int64 compat_expiry_ts_ms = 15;
  string response_tracking = 16; // ACCEPTED, EMPTY_200, RETRYABLE_5XX, REJECTED_4XX
}
```

### 8.13 ExternalAdEventMappingRecord

partner-facing `ad_event_id` 之类的字段进入系统后，必须先映射为受 policy 约束的内部事实，而不是直接拿来做通用 join。

```proto
message ExternalAdEventMappingRecord {
  string partner_name = 1;
  string ad_event_id = 2;
  int64 server_request_id = 3;
  int64 campaign_id = 4;
  int64 creative_id = 5;
  int64 click_ts_ms = 6;
  int64 mapping_expiry_ts_ms = 7;
  string source_contract_id = 8;
  string mapping_confidence = 9; // EXACT, POLICY_FILTERED, MISSING
}
```

### 8.14 ServerFeatureDerivationRecord

这个对象定义 confidential plane 向 optimization plane 释放什么，而不是释放什么原始信号。

```proto
message ServerFeatureDerivationRecord {
  int64 server_request_id = 1;
  string measurement_task_id = 2;
  string feature_policy_id = 3;
  string derivation_workflow_id = 4;
  int64 derivation_ts_ms = 5;
  string network_stability_bucket = 6;
  string timezone_consistency_bucket = 7;
  string reinstall_hint_bucket = 8;
  string ip_churn_bucket = 9;
  string boot_time_freshness_bucket = 10;
  bool suspicious_replay_pattern = 11;
  string release_scope = 12; // optimization_only, fraud_only
}
```

### 8.15 AttributionDecisionRecord

这个对象记录 winner 选择前后的候选集质量，用于解释为什么某个 request 拿到了最终 credit，以及为什么某些流量虽然被 claim 但不值得被高权重训练。

```proto
message AttributionDecisionRecord {
  string decision_id = 1;
  string mmp_event_id = 2;
  int64 server_request_id = 3;
  string measurement_task_id = 4;
  string final_decision = 5; // WIN, LOSE, ORGANIC, PROVISIONAL
  string winner_reason = 6; // LAST_CLICK, ELIGIBLE_CLICK, SRN_CONFIRM, POLICY_FILTER
  int32 prefilter_candidate_count = 7;
  int32 eligible_candidate_count = 8;
  int32 assist_count = 9;
  bool flooding_suspected = 10;
  float winner_confidence = 11;
  int64 decision_ts_ms = 12;
  string decision_policy_id = 13;
}
```

### 8.16 OptimizationFeedbackRecord

这个对象定义 label 发布后的持续反馈。它不是新的归因对象，而是给 bidding / ranking / pacing 系统提供“某次请求后续到底发生了什么”的稳定闭环。

```proto
message OptimizationFeedbackRecord {
  int64 server_request_id = 1;
  int64 advertiser_id = 2;
  int64 campaign_id = 3;
  int64 creative_id = 4;
  string feedback_type = 5; // install, purchase, revenue_7d, retention_d1
  double feedback_value = 6;
  int64 event_ts_ms = 7;
  int64 publish_ts_ms = 8;
  bool is_final = 9;
  bool is_revision = 10;
  string source_object = 11; // RequestScopedOptimizationLabel, PostInstallConversionEvent
  string trainer_policy_id = 12;
  string feedback_policy_id = 13;
}
```

### 8.17 OptimizationTrainingRow

这个对象不是对外协议对象，而是 ad network 在内部训练面物化后的最小训练行。它的作用是把“归因标签”和“可释放特征”在最后一跳 join 成一个 trainer-safe row。

```proto
message OptimizationTrainingRow {
  string schema_version = 1;
  string trainer_policy_id = 2;
  string feature_policy_id = 3;
  string label_policy_id = 4;
  int64 server_request_id = 5;
  int64 campaign_id = 6;
  int64 creative_id = 7;
  int64 placement_id = 8;
  int64 auction_id = 9;
  bool is_attributed = 10;
  int32 claim_confidence_micros = 11;
  int64 conversion_group_id = 12;
  int32 credit_fraction_micros = 13;
  bool right_censored = 14;
  int64 label_ts_ms = 15;
  repeated string released_feature_names = 16;
  string feature_vector_ref = 17;
  string sample_weight_policy_id = 18;
  int32 sample_weight_micros = 19;
}
```

### 8.18 AggregateCollectorBudgetState

这个对象不是给设备侧看的，而是给 aggregate collector 和 budget scheduler 明确“这次 collect 到底花了什么预算、属于哪个 collector、处于哪个生命周期状态”。它把 W3C Attribution Level 1 和 DAP attribution draft 里的 budget / collector thinking 变成可落地的生产 contract。

```proto
message AggregateCollectorBudgetState {
  string measurement_task_id = 1;
  string report_id = 2;
  string batch_id = 3;
  string collector_domain = 4; // mmp.example, analytics.partner.example
  string collector_surface_id = 5; // aap_ui, bi_export, partner_report_api
  string budget_scope_id = 6; // campaign_day_us, advertiser_week_global
  int32 privacy_budget_epoch_id = 7;
  int64 requested_budget_micros = 8;
  int64 reserved_budget_micros = 9;
  int64 finalized_budget_micros = 10;
  int64 report_create_ts_ms = 11;
  int64 report_expiry_ts_ms = 12;
  string lifecycle_state = 13; // pending, collected, finalized, expired, replay_rejected
  bool replay_rejected = 14;
  string budget_allocation_policy_id = 15;
}
```

## 9. Mock payload

### 9.1 广告请求

```json
{
  "server_request_id": 91833720368540001,
  "auction_id": 91833720368549991,
  "campaign_id": 74012091,
  "creative_id": 74019912,
  "placement_id": 30101,
  "advertiser_id": 120045,
  "publisher_app_numeric_id": 88990011,
  "publisher_app_bundle": "com.example.game",
  "request_ts_ms": 1777500005123,
  "country_code": "US",
  "region_code": "US-CA",
  "consent_scope": 5,
  "measurement_task_id": "icm_install_v3",
  "contribution_policy_id": "contrib_install_v2",
  "feature_policy_id": "feature_low_sensitive_v4",
  "retention_policy_id": "retain_30d_confidential_180d_label"
}
```

### 9.2 端上 artifact

```json
{
  "artifact_id": "d91f8c0a82d311eebf3d0242ac120002",
  "artifact_version": "odm-artifact-v3",
  "measurement_task_id": "icm_install_v3",
  "server_request_id": 91833720368540001,
  "impression_ts_ms": 1777500006123,
  "click_ts_ms": 1777500009231,
  "conversion_candidate_ts_ms": 1777500900000,
  "observation_window_sec": 604800,
  "artifact_expiry_ts_ms": 1778105700000,
  "workflow_manifest_digest": "sha256:9c9c0d...f2a1",
  "sdk_attestation": "base64:MEQCIA..."
}
```

### 9.2B aggregate collector budget state

```json
{
  "measurement_task_id": "agg_install_geo_day_v4",
  "report_id": "rpt_01JVATJQ6D3SK9D6V7Y4M3Q2P1",
  "batch_id": "2026-04-29/us-ca/install/000041",
  "collector_domain": "mmp.example",
  "collector_surface_id": "aap_ui",
  "budget_scope_id": "advertiser_120045_us_daily",
  "privacy_budget_epoch_id": 20260429,
  "requested_budget_micros": 50000,
  "reserved_budget_micros": 50000,
  "finalized_budget_micros": 50000,
  "report_create_ts_ms": 1777503600123,
  "report_expiry_ts_ms": 1778112000000,
  "lifecycle_state": "finalized",
  "replay_rejected": false,
  "budget_allocation_policy_id": "budget_install_geo_day_v2"
}
```

### 9.3 advertiser app / server 缓存的 `odm_info`

```json
{
  "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f-28sN5qN9GTZ_FztjL0OLFzgxUJD...",
  "odm_version": "icm-info-v2",
  "measurement_task_id": "icm_install_v3",
  "info_generated_ts_ms": 1777500900100,
  "info_expiry_ts_ms": 1778105700000
}
```

### 9.4 MMP Ask

```json
{
  "mmp_name": "ExampleMMP",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "mmp_install_id": "mmp_install_120045_9981",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "install_ts_ms": 1777500905123,
  "event_ts_ms": 1777500905123,
  "event_name": "first_open",
  "id_type": "idfv",
  "device_id": "CCB300A0-DE1B-4D48-BC7E-599E453B8DD4",
  "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
  "query_template_id": "mmp_install_query_v2",
  "country_code": "US",
  "ask_idempotency_key": "ask_01JTRP7V8W5T7A8Y4A8V2P",
  "ask_attempt_ts_ms": 1777500905123,
  "query_contract_id": "google_icm_install_query_v3"
}
```

### 9.5 Claim Response

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "claim_status": "CLAIMED",
  "claim_token": "base64:Wk1Qd1p4Y2xhaW0...",
  "claim_confidence": 0.94,
  "measurement_task_id": "icm_install_v3",
  "claim_ts_ms": 1777500906201,
  "claim_expiry_ts_ms": 1777502706201,
  "policy_version": "claim_policy_v5",
  "claim_reason_code": "MATCHED_ODM_AND_ELIGIBLE_TOUCH",
  "request_accepted": true
}
```

### 9.6 MMP Confirm

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "claim_token": "base64:Wk1Qd1p4Y2xhaW0...",
  "final_decision": "WIN",
  "confirm_ts_ms": 1777500907120,
  "winning_touch_ts_ms": 1777500009231,
  "winning_network": "example_ad_network",
  "confirm_idempotency_key": "confirm_01JTRP7V8W5T7A8Y4A8V2P",
  "confirm_attempt_ts_ms": 1777500907120
}
```

### 9.7 优化标签

```json
{
  "server_request_id": 91833720368540001,
  "advertiser_id": 120045,
  "campaign_id": 74012091,
  "creative_id": 74019912,
  "placement_id": 30101,
  "label_ts_ms": 1777500907120,
  "label_type": "install",
  "label_value": 1.0,
  "is_attributed": true,
  "claim_confidence": 0.94,
  "conversion_group_id": 502233001,
  "credit_fraction_micros": 1000000,
  "observation_window_sec": 604800,
  "right_censored": false,
  "trainer_policy_id": "trainer_gbdt_install_v7",
  "feature_policy_id": "feature_low_sensitive_v4",
  "contribution_policy_id": "contrib_install_v2",
  "region_profile": "R1",
  "network_stability_bucket": "wifi_stable",
  "reinstall_hint_bucket": "weak"
}
```

### 9.8 post-install purchase event

```json
{
  "advertiser_event_id": 20078199001,
  "advertiser_id": 120045,
  "app_bundle": "com.example.game",
  "platform": "ios",
  "event_name": "purchase",
  "event_ts_ms": 1777504507123,
  "event_value_micros": 4990000,
  "currency_code": "USD",
  "event_dedupe_key": "purchase_120045_user_9981_order_771",
  "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
  "advertiser_user_id": 998100771,
  "event_schema_id": "purchase_event_v2",
  "event_dimensions": {
    "sku": "gem_pack_1",
    "store": "app_store",
    "is_intro_offer": "false"
  }
}
```

### 9.9 SRN handshake state

```json
{
  "handshake_id": "hs_01JTRPD6K3K53M2EVR8C3R6B6Z",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "server_request_id": 91833720368540001,
  "measurement_task_id": "icm_install_v3",
  "ask_status": "RECEIVED",
  "claim_status": "CLAIMED",
  "confirm_status": "WIN",
  "ask_ts_ms": 1777500905123,
  "claim_ts_ms": 1777500906201,
  "confirm_ts_ms": 1777500907120,
  "expiry_ts_ms": 1777502706201,
  "policy_version": "claim_policy_v5",
  "failure_reason_code": ""
}
```

### 9.10 external compat record

```json
{
  "partner_name": "google_app_conversion_api",
  "api_contract_version": "v1.1_2026-03-10",
  "request_contract_id": "google_app_conversion_first_open_v4",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "app_event_type": "first_open",
  "event_timestamp_sec_micros": 1777500905123000,
  "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
  "id_type": "idfv",
  "rdid": "CCB300A0-DE1B-4D48-BC7E-599E453B8DD4",
  "user_agent": "ExampleMMP/8.1.0 (iOS 18.1; en_US; iPhone16,2; Build/22B82; Proxy)",
  "x_forwarded_for": "203.0.113.24",
  "ad_event_id": "CAESEJr7v2cTn6M8W2Gv6V9qKQ",
  "attributed": true,
  "compat_expiry_ts_ms": 1777587307120,
  "response_tracking": "ACCEPTED"
}
```

### 9.11 server feature derivation record

```json
{
  "server_request_id": 91833720368540001,
  "measurement_task_id": "icm_install_v3",
  "feature_policy_id": "feature_low_sensitive_v4",
  "derivation_workflow_id": "feature_release_workflow_2026_04",
  "derivation_ts_ms": 1777500908200,
  "network_stability_bucket": "wifi_stable",
  "timezone_consistency_bucket": "stable",
  "reinstall_hint_bucket": "weak",
  "ip_churn_bucket": "same_prefix_24h",
  "boot_time_freshness_bucket": "2_to_7_days",
  "suspicious_replay_pattern": false,
  "release_scope": "optimization_only"
}
```

### 9.12 attribution decision record

```json
{
  "decision_id": "dec_01JTRPF2VY9T21Q2FJAA1K8M7X",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "server_request_id": 91833720368540001,
  "measurement_task_id": "icm_install_v3",
  "final_decision": "WIN",
  "winner_reason": "ELIGIBLE_CLICK",
  "prefilter_candidate_count": 6,
  "eligible_candidate_count": 2,
  "assist_count": 3,
  "flooding_suspected": true,
  "winner_confidence": 0.94,
  "decision_ts_ms": 1777500907199,
  "decision_policy_id": "decision_policy_v3"
}
```

### 9.13 optimization feedback record

```json
{
  "server_request_id": 91833720368540001,
  "advertiser_id": 120045,
  "campaign_id": 74012091,
  "creative_id": 74019912,
  "feedback_type": "purchase",
  "feedback_value": 4.99,
  "event_ts_ms": 1777504507123,
  "publish_ts_ms": 1777504511000,
  "is_final": false,
  "is_revision": false,
  "source_object": "PostInstallConversionEvent",
  "trainer_policy_id": "trainer_gbdt_purchase_v4",
  "feedback_policy_id": "feedback_publish_v2"
}
```

### 9.14 final optimization training row

```json
{
  "schema_version": "optimization_training_row.v1",
  "trainer_policy_id": "trainer_policy.purchase_value_v3",
  "feature_policy_id": "feature_policy.low_sensitive_release_v4",
  "label_policy_id": "label_policy.purchase_7d_v2",
  "server_request_id": "922337203600012345",
  "campaign_id": "20014501",
  "creative_id": "30077882",
  "placement_id": "40102",
  "auction_id": "800990011",
  "is_attributed": true,
  "claim_confidence_micros": 910000,
  "conversion_group_id": "7001000001",
  "credit_fraction_micros": 1000000,
  "right_censored": false,
  "label_ts_ms": "1761795105123",
  "released_feature_names": [
    "network_stability_bucket",
    "timezone_consistency_bucket",
    "reinstall_hint_bucket",
    "request_hour_bucket",
    "geo_cluster_id"
  ],
  "feature_vector_ref": "fv://trainer-ready/2026-04-29/922337203600012345",
  "sample_weight_policy_id": "sample_weight.purchase_quality_v2",
  "sample_weight_micros": 1000000
}
```

## 10. 敏感 PII 如何流动

### 10.1 原则

- 原始 `boot_time`、原始 `ip`、完整 `User-Agent`、长期稳定设备标识 `MUST NOT` 进入普通 BI、通用日志或通用湖仓。
- 如果协议兼容需要把某些字段传给外部 API，这些字段也 `MUST NOT` 自动下沉到 optimization plane。
- “为了兼容 partner API 先缓存一下” 不等于 “这个字段可以成为训练特征”。

### 10.2 推荐的数据流

1. ad network SDK 在 advertiser app 内观察到敏感信号。
2. 设备侧只输出两类结果：
   - `task-bound opaque envelope`
   - `encrypted confidential feature blob`
3. confidential plane 内部做低敏特征派生，例如：
   - `network_stability_bucket`
   - `timezone_consistency_bucket`
   - `reinstall_hint_bucket`
   - `ip_churn_bucket`
4. optimization plane 只看到派生后的低敏特征。
5. aggregate plane 只看到 bounded metric contribution。

### 10.3 关于 `user_id:int64`

本文允许存在内部账户体系下的 `advertiser_user_id:int64`，但有强约束：

- 只可用于 advertiser 自有 first-party 路径；
- 必须与 `server_request_id`、`measurement_task_id` 分离；
- 不得通过 `odm_info` 暗度陈仓传给 MMP；
- 不得成为跨 app、跨 network 的通用 join key。

也就是说：

- `server_request_id` 是 request key
- `advertiser_user_id` 是 advertiser first-party account key
- `odm_info` 是 opaque bridge object

三者语义必须严格分开。

### 10.4 建议按四层处理“既敏感又可能有业务价值”的字段

这类字段最容易在生产中边界失守。建议直接按 release surface 分类：

- `raw-sensitive only`
  - `boot_time_ms`
  - `raw_ip`
  - 完整 `User-Agent`
  - 只允许留在设备侧或 confidential plane
- `egress-only compatibility`
  - `rdid`
  - `X-Forwarded-For`
  - `ad_event_id`
  - 允许短期缓存用于 partner API，但 `MUST NOT` 进入训练特征表
- `optimization-safe derived`
  - `network_stability_bucket`
  - `ip_churn_bucket`
  - `reinstall_hint_bucket`
  - 允许进入 optimization plane，但必须有 `feature_policy_id`
- `aggregate-only`
  - `metric_name`
  - `metric_value`
  - `aggregation_key`
  - 只允许以 bounded contribution 形态出现

如果团队发现某个字段同时出现在这四层中的两层以上，默认说明边界设计有问题，需要拆对象，而不是继续打补丁。

### 10.5 字段级 handling matrix

为了避免“实现时顺手透传”，建议把常见字段在 RFC 里直接定死到 release surface：

- `boot_time_ms`
  - 允许出现于 `Device Raw Plane`
  - 允许以派生桶特征出现于 `Confidential Plane`
  - 默认不允许进入 `MMP/SRN payload`
  - 默认不允许原值进入 `Optimization Plane`
- `raw_ip`
  - 允许短期出现于 `Device Raw Plane`
  - 允许短期出现于 partner compat egress
  - 默认不允许进入训练明细或普通数仓
- `rdid`
  - 只在 partner compat contract 需要时短期存在
  - 不得作为内部通用 join key
- `odm_info`
  - 只用于 bridge / ask 流程
  - 不得进入 trainer row
  - 不得进入长期画像表
- `ad_event_id`
  - 允许存在于 external response mapping
  - 不得直接进入 bid / ranking / pacing 训练
- `server_request_id`
  - 允许出现在 confidential join 和 optimization label
  - 不得进入 partner-facing payload
  - 不得沉入普通 BI 明细
- `user_id:int64`
  - 若广告主业务必须使用，应该只存在于 advertiser-controlled first-party plane
  - 不得成为 ODM core protocol 的必填字段
  - 不得替代 `server_request_id`

## 11. 与 MMP / SRN 的协同规范

### 11.1 标准流程

本文默认 SRN 协议抽象为：

1. `MMP Ask`
2. `Ad Network Claim`
3. `MMP Confirm`

### 11.2 Ask 阶段要求

- `odm_info` `SHOULD` 作为 ask 的可选增强字段。
- `query_template_id` `MUST` 明确，防止 partner 任意探测。
- `query_hash` `SHOULD` 绑定进 `claim_token`。

### 11.3 Claim 阶段要求

- ad network `MUST` 校验 task binding。
- ad network `MUST` 校验 expiry。
- ad network `MUST` 做 anti-replay。
- ad network `SHOULD` 默认不返回内部 loser diagnostics。

### 11.4 Confirm 阶段要求

- `claim_token` `MUST` 只在短窗口内有效。
- `final_decision` `MUST` 决定后续 label 是否物化。
- confirm 缺失时，系统 `MAY` 产生 provisional label，但不得混入 final training set。

### 11.5 与 Google App Conversion / ICM 的兼容

Google 的 [request/response spec](https://developers.google.com/app-conversion-tracking/api/request-response-specs) 已明确：

- `odm_info` 是 ICM 必需字段之一；
- 响应里存在 `ad_event_id` 这类 partner-facing 标识；
- 某些外部 API 仍要求 `rdid`、`User-Agent`、`X-Forwarded-For` 等字段。
- cross-network attribution request 需要带回 `ad_event_id` 与 `attributed`；
- 有效的 cross-network attribution request 会收到 `HTTP 200` 且空响应体，这只能说明 partner accepted the follow-up request，不说明 attribution truth 已被全链路确认。

同时，Google 2026 年的 measurement reporting 文档还明确：

- ICM 的 granular event-level view 位于 AAP UI，而不是 Google Ads reporting UI；
- ODM 对位于 `EEA`、`UK`、`Switzerland` 的用户 inactive，因此协议必须区分 `feature_not_active_by_region`、`feature_not_integrated`、`claim_not_found` 这三类完全不同的状态。

2026-04-14 ODM HAR 逆向进一步说明，Google SDK 的 `odm_info` 兼容路径背后很可能先经历了 `config -> psm -> validate` 子流程。对本 RFC 最重要的兼容含义是：

- 外部 API 里的 `odm_info` 是最终 bridge object，不等同于 `/odm/config.extension_data`、`/odm/psm.psm_request`、`/odm/validate.mvs` 中任何单个内部字段。
- `matching_id` 在 `/config` 阶段返回，不能被建模为 PSM 命中后才产生的 attribution result。
- `/validate` 返回的 `mv_ga4f` 与 `mv_aaps` 更像渠道化 measurement values，应进入 compatibility egress cache，而不是直接进入 optimization plane。
- 如果 partner 只看到 accepted / empty response，仍然不能据此推出 PSM 是否命中、MVS 是否通过、或 MMP winner 是否确认。

因此推荐四层拆分：

1. `compatibility egress cache`
2. `confidential join cache`
3. `optimization labels`
4. `aggregate outputs`

不要把第 1 层直接合并进第 3 层。

### 11.6 “partner 接受了请求” 不等于 “归因已成立”

以 Google App Conversion API 为代表的外部协议里，`HTTP 200` 常常只表示 request 被接受或可继续处理，不表示 attribution truth 已经成立。

因此生产系统 `MUST` 明确区分至少三层状态：

- `request_accepted`
  - 外部 API 接收了这条请求
- `claim_established`
  - ad network 在自己的 confidential plane 内完成了有效 claim
- `attribution_confirmed`
  - MMP confirm 或内部 winner selection 最终闭环完成

如果把这三层混成一个布尔值，就会同时伤害：

- 训练标签质量
- partner 对账
- 重试与补发逻辑
- 事故排障

推荐做法是把外部响应状态写入 `ExternalAttributionCompatRecord.response_tracking`，把闭环状态写入 `AttributionHandshakeState.confirm_status`。

### 11.7 Ask / Claim / Confirm 必须可重放排查，但不可重放执行

这类系统线上一定会遇到：

- ask 超时重试
- claim 成功但 confirm 丢失
- confirm 迟到
- partner follow-up accepted 但未回传可用 mapping

因此 RFC 应要求：

- 每次 ask/claim/confirm 都有独立 `attempt_ts_ms`
- `ask_idempotency_key` 与 `confirm_idempotency_key` `MUST` 进入协议对象，而不是只留在 API gateway 日志
- 同一 `mmp_event_id + measurement_task_id + query_hash` 有 bounded retry budget
- 线上排查依赖 `AttributionHandshakeState` 和 `ExternalAttributionCompatRecord`
- 真正执行路径依赖 `replay_cache_key`、expiry、policy version，防止“排查日志可见”演变成“协议可重放”

### 11.8 ownership 与责任矩阵

要让 ask / claim / confirm 真能线上落地，RFC 需要把“谁生成、谁缓存、谁负责过期”写清楚：

- `server_request_id`
  - 生成方: ad network backend
  - 写入方: ad response / SDK exposure metadata
  - 生命周期负责人: ad network
- `odm_info`
  - 生成方: advertiser app 中的 ODM SDK
  - 缓存方: advertiser app 或 advertiser server
  - 透传方: MMP / AAP
  - 过期负责人: advertiser app 与 ad network 共同约束
- `ask_idempotency_key`
  - 生成方: MMP
  - 生命周期负责人: MMP
- `claim_token`
  - 生成方: ad network confidential service
  - 使用方: MMP confirm
  - 过期负责人: ad network
- `confirm_idempotency_key`
  - 生成方: MMP
  - 生命周期负责人: MMP

如果责任不清晰，线上最容易出现两种事故：一是同一 install 被多次问询，二是 `odm_info` 被错误地缓存成长期用户标识。

## 12. Optimization 规范

### 12.1 为什么必须保留 request-level 粒度

如果服务端只拿到 aggregate conversion count，则无法稳定支撑：

- 出价优化
- creative ranking
- budget pacing
- cold-start exploration
- fraud / anomaly modeling

因此 `RequestScopedOptimizationLabel` 至少要保留：

- `server_request_id`
- `campaign_id`
- `creative_id`
- `placement_id`
- `label_type`
- `label_value`
- `credit_fraction_micros`
- `claim_confidence`

### 12.2 多触点与多拥有者

现实世界里，一个 conversion 可能对应多个 touch、多个 network、多个 owner。受 [It's My Data Too](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/) 启发，label contract 必须处理：

- winner-only attribution
- fractional credit attribution
- assist logging
- multi-user ownership

推荐规范：

- `conversion_group_id:int64`
  - 同一 conversion 组内的多条样本共享该 ID
- `credit_fraction_micros:int32`
  - 1000000 表示 100%
- `contribution_policy_id:string`
  - 明确该 conversion 组如何裁剪

### 12.3 推荐 baseline

Phase 1 推荐：

- `LightGBM`
- `XGBoost`
- delayed-feedback aware label materialization
- right-censoring aware training data build

暂不建议一上来就把训练升级成：

- 全量 DP-SGD 深度模型
- 联邦端上训练主路径

这不是因为这些方向不重要，而是因为在广告测量落地里，先把 `label contract + policy versioning + sample lifecycle` 做对，收益更大。

### 12.4 optimization plane 最低要看到什么

如果目标是 personalized optimization，而不是只做 aggregate reporting，那么服务端至少要稳定保留以下粒度：

- request identity
  - `server_request_id`
  - `campaign_id`
  - `creative_id`
  - `placement_id`
- attribution state
  - `claim_confidence`
  - `is_attributed`
  - `conversion_group_id`
  - `credit_fraction_micros`
- lifecycle state
  - `observation_window_sec`
  - `right_censored`
  - `label_ts_ms`
- policy state
  - `trainer_policy_id`
  - `feature_policy_id`
  - `contribution_policy_id`
- released low-sensitive features
  - `network_stability_bucket`
  - `timezone_consistency_bucket`
  - `reinstall_hint_bucket`

反过来说，下列字段通常不该进入 optimization plane：

- `odm_info`
- `claim_token`
- `rdid`
- `X-Forwarded-For`
- 完整 `User-Agent`
- partner 返回的原始 `ad_event_id`

### 12.5 推荐把训练样本拆成“标签行”和“特征释放行”

不要把所有字段做成一张肥表。更稳的设计是：

- `RequestScopedOptimizationLabel`
  - 定义监督信号和 credit
- `ServerFeatureDerivationRecord`
  - 定义 confidential plane 释放的低敏特征

训练时再按 `server_request_id` 做内部 join。这样有三个好处：

- feature policy 漂移更容易灰度
- compat 字段更难误入训练
- 后续要给 fraud model 和 bid model 不同 release scope 时，不必拆历史大表

### 12.6 optimization feedback 不应隐式依赖离线回填

如果希望 on-device measurement 真正服务于 personalized optimization，而不仅仅是离线归因报表，则系统还应显式发布 `OptimizationFeedbackRecord`：

- 安装类标签可以低延迟发布 first label，再在 `purchase`、`retention_d1`、`roas_7d` 到达时持续补充反馈；
- `is_final` 与 `is_revision` 用来区分“首次反馈”“更正反馈”“最终冻结反馈”；
- bidding / pacing / exploration 系统消费 feedback ledger，而不是直接监听杂乱的 post-install 业务事件流。

推荐把 `RequestScopedOptimizationLabel` 视为“首次监督信号”，把 `OptimizationFeedbackRecord` 视为“持续监督流”。两者共同构成线上优化闭环。

### 12.7 purchase optimization walkthrough

把一次真实 purchase 优化闭环按时间顺序写开，会更容易看懂为什么要保留这些字段：

1. ad network 在广告请求时生成 `server_request_id=922337203600012345`，并把 campaign、creative、placement、geo、consent 写入 `AdRequestContext`。
2. SDK 在端上看到 impression / click，同时观察到 `boot_time_ms`、`raw_ip`、`timezone_offset_min`、`bundle_first_install_ts_ms` 等本地信号。
3. 端上不直接上送这些原值，而是生成：
   - `OnDeviceMeasurementArtifact`
   - `odm_info`
4. 用户完成安装，MMP 发起 `MmpAskRequest`，其中包含自己的 `mmp_event_id`、query contract，以及透传的 `odm_info`。
5. ad network 在 confidential plane 内把 ask 与 artifact 绑定，判断这次 install 是否 eligible to claim，并返回短期 `claim_token`。
6. MMP 在多家 SRN 返回结果之间做 winner selection，然后只对 winner 发 `MmpConfirmRequest`。
7. ad network 在 confidential plane 内做最终 join，输出：
   - `RequestScopedOptimizationLabel`
   - `ServerFeatureDerivationRecord`
   - `OptimizationFeedbackRecord`
8. trainer materialization 作业按 `server_request_id` 内联 join label 与 feature release，生成 `OptimizationTrainingRow`。
9. 线上 bidding / ranking 系统拿到的是训练安全的 request row，而不是 `odm_info`、`raw_ip`、完整 `User-Agent` 或 partner `ad_event_id`。

这个 walkthrough 的关键点是：个性化优化依赖的是 request-level 对齐能力，不依赖把原始 PII 长期放进训练面。

## 13. Aggregate reporting 规范

### 13.1 最低治理要求

任何 aggregate release `MUST` 至少有：

- dedupe
- contribution bounding
- minimum crowd threshold
- audit log
- replay rejection

### 13.2 DP 策略

本文明确允许 trade-off：

- `optimization plane` 初期 `MAY` 为 confidential-but-not-DP
- `aggregate reporting plane` `SHOULD` 更早进入 DP 治理

推荐库：

- [OpenDP](https://github.com/opendp/opendp)
- [google/differential-privacy](https://github.com/google/differential-privacy)

### 13.3 与 DAP/VDAF 对齐

即使 Phase 1 不部署完整 DAP，也建议 aggregate object model 对齐：

- `measurement_task_id`
- `report_id`
- `batch_id`
- `task_expiry_ts_ms`
- `extension_fields`
- `collector_domain`
- `collector_surface_id`
- `privacy_budget_epoch_id`
- `requested_budget_micros`
- `lifecycle_state`

这样 Phase 2 升级到 DAP/VDAF 或 partner-managed aggregate collector 时，迁移成本更低。

同时应吸收 [W3C Attribution Level 1](https://www.w3.org/TR/privacy-preserving-attribution/) 的两个硬约束：

- aggregate collector `MUST NOT` 接收同一 report 多次；
- privacy budget 的扣减和 report 生命周期必须是 collector 可见状态，而不是依赖外部分析作业补记。

再进一步，受 [DAP Extensions for the Attribution API](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/) 影响，aggregate plane `SHOULD` 从第一天起显式建模：

- collector 是谁
- budget 属于哪个 scope
- 这是 requested / reserved / finalized 的哪一种预算状态
- batch 是 leader/collector 视角下的哪一个稳定 collect 单位

否则后面一旦要支持 shared budget、multi-surface reporting 或多个 collector，系统就会被迫把“预算语义”硬塞进离线任务名字和脚本参数里。

### 13.4 推荐的 VDAF primitive 映射

为了避免 aggregate plane 落回自定义协议，建议优先按指标类型选择已有 VDAF primitive：

- install / purchase count
  - `Prio3Count`
- revenue / ROAS numerator
  - `Prio3Sum`
- retention day、latency、value range
  - `Prio3Histogram`
- 固定长度 campaign x geo x day 向量
  - `Prio3SumVec`

RFC 不需要强制“今天就部署哪一个 collector”，但应先把 metric type 和 primitive 对齐，否则未来很容易出现一套只服务本团队脚本的半成品 aggregation protocol。

### 13.5 bucket 与 reporting window 也是优化对象

受 [Summary Reports Optimization in the Privacy Sandbox Attribution Reporting API](https://research.google/pubs/summary-reports-optimization-in-the-privacy-sandbox-attribution-reporting-api/) 启发，aggregate plane 应把下面这些东西也版本化：

- `aggregation_key_schema_id`
- `value_bucket_schema_id`
- `reporting_window_id`
- `budget_allocation_policy_id`

原因很简单：同样的 privacy budget 下，维度切分和 value bucket 设计直接决定报表可用性。把这些参数留给下游分析师临时拼接，往往会让系统既不稳，也不容易审计。

## 14. 安全、隐私与治理要求

### 14.1 TTL

以下对象都 `MUST` 有 expiry：

- `OnDeviceMeasurementArtifact`
- `odm_info`
- `claim_token`
- `compatibility egress cache`

### 14.2 Anti-replay

至少要求：

- `artifact_id`
- `replay_nonce`
- `query_hash`
- `replay_cache_key`
- bounded-shot query count

### 14.3 Purpose binding

每次 confidential upload `SHOULD` 绑定：

- `measurement_task_id`
- `workflow_manifest_digest`
- `allowed_release_surface`
- `retention_policy_id`

### 14.4 Verifiability

confidential plane `SHOULD` 保留：

- `processing_manifest_digest`
- `workflow_signature_ref`
- `tee_attestation_ref`
- `privacy_budget_ledger_ref`

推荐组件：

- [sigstore/cosign](https://github.com/sigstore/cosign)
- [sigstore/rekor](https://github.com/sigstore/rekor)

### 14.5 TEE/CVM side-channel 加固

结合 [SNPeek](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/) 与 [TDXRay](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/)，高敏 workflow 至少要求：

- 按 `artifact_validation`、`claim_join`、`feature_derivation`、`egress_adapter` 拆 workflow
- debug 日志默认关闭 request-level 敏感字段
- 对高敏路径优先使用批处理、固定模板、减少 data-dependent branching
- 做 side-channel regression test

## 15. Trade-off 设计

### 15.1 可以放松的地方

- Phase 1 的 optimization plane 不强制 DP。
- confidential plane 初期可以先用单方 TEE/CVM，而不是直接上 MPC。
- MMP bridge 初期可以先做 opaque pass-through，而不是完整通用标准。
- baseline model 先用 GBDT，而不是直接上大型 DP 深度模型。

### 15.2 不能放松的地方

- 不能把 `server_request_id` 下沉到普通 BI。
- 不能把原始 `boot_time`、原始 `ip` 透传给 MMP 作为通用字段。
- 不能把 `odm_info` 变成 durable identifier。
- 不能取消 anti-replay。
- 不能把 contribution bounding 视为可选项。

### 15.3 为什么本文允许“不先上 DP”

因为 optimization plane 的风险特征与 aggregate release 不同：

- 消费者更少
- ACL 更强
- TTL 更短
- purpose binding 更强
- 不直接对外发布

但这不等于可以“少做治理”。恰恰相反，Phase 1 就必须做版本化：

- `measurement_task_id`
- `feature_policy_id`
- `contribution_policy_id`
- `trainer_policy_id`
- `retention_policy_id`

## 16. 生产实现建议

### 16.1 端上 / SDK

- iOS 侧优先复用 [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk) 或 Firebase ODM 路线。
- 用 `Protobuf + buf` 定义 wire schema。
- 本地仅保留短期加密缓存，不保留长期稳定 token。
- 如果自研 Google-compatible ODM 子流程，默认按 `OPRF/VOPRF-style PSM + prefix bucket candidate retrieval + local filtering` 建模；不要把 Paillier/PIR 当成当前 HAR 已证实的主路径。
- SDK 状态机需要显式记录 `config_loaded`、`psm_candidate_set_received`、`local_match_evaluated`、`mvs_validated`，而不是只记录一个布尔 `odm_info_generated`。

### 16.2 confidential processing

- 优先评估 [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute) 作为 workflow 编排和 confidential processing 基座。
- ingress 处立刻做 TTL 和 replay gate。
- 不要做一个“万能 confidential service”；按 workflow 分类部署。

### 16.3 optimization training

- baseline: [LightGBM](https://github.com/microsoft/LightGBM) / [XGBoost](https://github.com/dmlc/xgboost)
- 深度模型或更强隐私训练再考虑：
  - [JAX Privacy](https://github.com/google-deepmind/jax_privacy)
  - [TensorFlow Privacy](https://github.com/tensorflow/privacy)

### 16.4 aggregate reporting

- 先完成 bounded release pipeline，再补 DP。
- privacy budget ledger 要单独版本化和审计。

### 16.5 审计

- DP 机制审计可接入 [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)。
- 若 release surface 升级成持续 DP 机制，可进一步参考 [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)。

### 16.6 跨方 reconciliation

如果未来要做 advertiser / publisher / network 的隐私保护对账，优先考虑 [Private Join and Compute](https://github.com/google/private-join-and-compute)，而不是回退到交换原始 user-level 明细。

## 17. Deployment Profiles

### 17.1 Profile A: Minimum Production

包含：

- `server_request_id`
- device artifact
- opaque `odm_info`
- `MMP Ask -> Claim -> Confirm`
- confidential join
- request-level labels
- thresholded aggregate reporting

### 17.2 Profile B: Recommended Default

在 Profile A 基础上增加：

- TEE-backed confidential processing
- versioned contribution policy
- DP-backed aggregate reporting
- policy-aware audit trail

### 17.3 Profile C: Cross-Party Hardened

在 Profile B 基础上增加：

- PJC/PSI reconciliation
- stronger verifiable workflow
- DAP/VDAF-aligned aggregate service

## 17A. ODM / ODC HAR 逆向附录

本附录保留 2026-04-14 HAR 样本中能落到 byte-level 的证据。它的定位不是替代主 RFC，而是给 `OPRF/VOPRF-style PSM + prefix bucket candidate retrieval + local filtering` 这条推断链提供可复核材料。

样本上下文：

- App: `com.underdogsports.fantasy`
- SDK: `odm-sdk-i-v3.2.0`
- source: `aaps`
- 输入材料: 2026-04-14 HAR 样本与 2026-04-30 逆向整理
- 证据边界: HAR 可证明字段、长度、顺序和部分 protobuf-like wire shape；算法名称、曲线、KDF、row 加密格式仍是强推断。

### 17A.1 证据等级

| 等级 | 含义 | 本样本例子 |
|---|---|---|
| Confirmed by HAR | 抓包可直接验证，字段、长度、顺序确定 | `/config -> /psm -> /validate`；`odmed == extension_data`；`psm_response` decoded len 为 123,189 bytes |
| Strong inference | 字节形态与算法模型强匹配，但还需要 hook 或多样本确认 | 33-byte point 指向 EC-OPRF/VOPRF；3-byte blob 与 22-bit prefix bucket 匹配 |
| Plausible model | 能解释端到端流程，但 HAR 不能唯一证明 | 77-byte candidate field 是 encrypted payload 或 proof package |
| Not proven / open | 当前不应写成结论 | Paillier 是否参与该 HAR；boot time 是否进入 `mvs`；`matching_id` 的真实消费点 |

### 17A.2 请求链路顺序

HAR entries 数组本身不保证时间排序；按 `startedDateTime`，真实顺序是：

| 顺序 | 时间 | 方法 | Endpoint | 主要职责 |
|---:|---|---|---|---|
| 1 | `2026-04-14T17:22:09.783Z` | GET | `/odm/config` | 下发 ODM context：`matching_id`、`bucketed_date`、`prefix_length`、`extension_data` |
| 2 | `2026-04-14T17:22:10.268Z` | POST | `/odm/psm` | 发送 prefix bucket 与 EC blinded query；返回 OPRF header 与 candidate set |
| 3 | `2026-04-14T17:22:10.658Z` | POST | `/odm/validate` | 提交 `mvs + odmed`；返回 `mv_ga4f` 与 `mv_aaps` |

端到端抽象：

```text
Client local identity / install material
  | normalize + hash + prefix selection
  v
GET /odm/config
  returns: matching_id, bucketed_date, prefix_length=22, extension_data(odmed)
  |
  | build PSM request: prefix(3 bytes) + A = r * H(x)
  v
POST /odm/psm
  returns: OPRF response header + 1009 candidate rows
  |
  | client unblind: Y = r^-1 * B = k * H(x)
  | derive tail / row key; locally filter/decrypt candidate rows
  v
POST /odm/validate { mvs, odmed }
  returns: mv_ga4f, mv_aaps
  |
  v
SDK exposes aggregateConversionInfo / odm_info for reporting pipeline
```

### 17A.3 `/odm/config`

Observed request parameters:

```text
version=1.2
bundle_id=com.underdogsports.fantasy
app_version=26.25.0
sdk_version=odm-sdk-i-v3.2.0
retry_count=0
odm2_count=0
source=aaps
device_model=iPhone18,1
os_version=26.3.1
user_default_language=en-cn
time_zone_offset_minutes=-420
```

Observed response:

```json
{
  "matching_id": "h-hf03rtPMDBUSedI71d9U8WcMvUzjXslIKBaa8RNAw",
  "bucketed_date": "2026-04-13",
  "prefix_length": 22,
  "extension_data": "CBYaAggEKghiMTkyNDY1Ng"
}
```

`matching_id` base64url decoded len = 32:

```text
87 e8 5f d3 7a ed 3c c0 c1 51 27 9d 23 bd 5d f5
4f 16 70 cb d4 ce 35 ec 94 82 81 69 af 11 34 0c
```

`extension_data` decoded len = 16, and is reused as `odmed` in `/psm` and `/validate`:

```text
08 16 1a 02 08 04 2a 08 62 31 39 32 34 36 35 36
```

Inferred schema:

```proto
message OdmExtensionData {
  uint64 field1 = 1; // 22; equals prefix_length
  bytes  field3 = 3; // len=2; nested: field1=4
  bytes  field5 = 5; // ASCII "b1924656"
}
```

Important correction: `matching_id` is returned by `/config`, not minted by `/psm`. In this HAR it is better treated as opaque context, cache key, or correlation key.

### 17A.4 `/odm/psm` request

Observed request body is JSON over `application/x-www-form-urlencoded`:

```json
{
  "odmed": "CBYaAggEKghiMTkyNDY1Ng",
  "psm_request": "CigKA7Tu2BIhAxP3dhiA3fXD_ZjKy63l939rAXXzgG9H4NCafWVrDXC_EgQQAhgWGCM"
}
```

`odmed` equals `/config.extension_data`.

`psm_request` base64url decoded len = 50:

```proto
message PsmRequest {
  bytes  field1 = 1; // len=40; query material
  bytes  field2 = 2; // len=4; params
  uint32 field3 = 3; // 35; protocol/mode id
}

message QueryMaterial {
  bytes field1 = 1; // len=3: b4 ee d8
  bytes field2 = 2; // len=33 compressed EC point, prefix 0x03
}

message PsmParams {
  uint32 field2 = 2; // 2
  uint32 field3 = 3; // 22; equals prefix_length
}
```

Raw bytes:

```text
psm_request len = 50
0a 28
  0a 03 b4 ee d8
  12 21 03 13 f7 76 18 80 dd f5 c3 fd 98 ca cb ad e5 f7
        7f 6b 01 75 f3 80 6f 47 e0 d0 9a 7d 65 6b 0d 70 bf
12 04
  10 02 18 16
18 23
```

Algorithmic interpretation:

```text
x       = normalized local measurement input
h       = SHA256(x || app/source/date/context)       // exact concatenation unknown
prefix  = high_22(h)                                 // 22-bit bucket key
P       = HashToCurve(h or tail-material)
r       = client random scalar
A       = r * P                                      // blinded point
send    = { prefix, A, params(prefix_length=22), mode=35 }
```

Why this matters: a 3-byte prefix-like field matches `ceil(22/8)`, while the 33-byte compressed EC point makes OPRF/VOPRF-style PSM a much stronger fit than a generic opaque token model.

### 17A.5 `/odm/psm` response

`psm_response` base64url decoded len = 123,189 bytes:

```proto
message PsmResponseEnvelope {
  bytes field1 = 1; // len=123185
}

message PsmResponseCore {
  bytes  field1 = 1; // len=70; EC header
  uint32 field4 = 4; // 35
  bytes  field5 = 5; // len=123098; candidate payload
  bytes  field7 = 7; // len=7; crypto params
}

message CryptoParams {
  uint32 field1 = 1; // 35
  uint32 field2 = 2; // 256
  uint32 field3 = 3; // 2
}
```

The 70-byte EC header can be parsed as two 33-byte compressed EC points:

```proto
message PsmEcHeader {
  bytes field1 = 1; // len=33; equals request point A
  bytes field2 = 2; // len=33; likely server evaluated point B or proof element
}
```

First EC point, equal to the request blinded point:

```text
03 13 f7 76 18 80 dd f5 c3 fd 98 ca cb ad e5 f7
7f 6b 01 75 f3 80 6f 47 e0 d0 9a 7d 65 6b 0d 70 bf
```

Second EC point:

```text
02 76 ca 3a b0 e7 46 af e9 9a be 0d ff 43 a3 ea
44 29 3e f7 49 b0 6f b2 fd c9 36 30 92 81 fb 05 ff
```

OPRF interpretation:

```text
A = r * H(x)               // client blinded point, echoed back
B = k * A                  // server evaluated point, or part of VOPRF proof/evaluation
client computes r^-1 * B = k * H(x)
```

### 17A.6 Candidate payload segmentation

`PsmResponseCore.field5` len = 123,098 bytes. It is not a vector of scalar membership answers; it is a repeated-field candidate payload:

```proto
message CandidatePayload {
  repeated bytes field1 = 1; // 1009 items, each len=1
  repeated bytes field2 = 2; // 1009 items, each len=77
  repeated bytes field3 = 3; // 1009 items, each len=38
}
```

| Segment | Offset | Wire shape | Count | Interpretation |
|---|---:|---|---:|---|
| A | `0 -> 3027` | `0a 01 xx` | 1009 | row-level 1-byte tag / mask / quick check |
| B | `3027 -> 82738` | `12 4d <77 bytes>` | 1009 | opaque crypto package / encrypted candidate payload |
| C | `82738 -> 123098` | `1a 26 <38 bytes>` | 1009 | structured metadata + row token/id |

Segment A statistics:

```text
count = 1009
unique values = 256
min = 0
max = 255
mean = 127.27
first 32 values = 22 c7 94 99 55 25 4b 3a b2 df a2 f7 7b a1 01 ca ...
```

Segment B first 77-byte blob:

```text
7b 8b b9 48 02 f3 c2 0f 0b 73 8b 7b 27 01 fb ac
02 5f e7 e3 59 c8 03 00 fb d2 88 ce a0 8b c0 d3
be 7c 16 e8 18 3e 26 47 c0 c5 d0 44 be ec 44 7f
70 48 7c 37 1e 59 65 44 92 56 09 e8 b9 50 d5 ae
82 73 bb a2 45 9d 97 89 d2 6d c3 e0 8f
```

Segment C inferred schema:

```proto
message CandidateMetaRow {
  bytes field1 = 1; // len=13; nested meta
  bytes field3 = 3; // len=21; row token/id
}

message CandidateMeta {
  uint64 field1 = 1; // timestamp-like microsecond epoch
  uint32 field2 = 2; // 1 or 2
  uint32 field3 = 3; // 0 or 1
}
```

Segment C statistics:

```text
rows = 1009
meta.field1 min = 1775253031479509  // 2026-04-03 21:50:31.479509 UTC
meta.field1 max = 1776212457023095  // 2026-04-15 00:20:57.023095 UTC
meta.field1 unique = 532 / 1009
meta.field2 distribution = {2: 801, 1: 208}
meta.field3 distribution = {1: 827, 0: 182}
row token length = 21 bytes for all rows
row token prefix = 00 94 87 9f 8c for all rows; last 16 bytes vary
```

This supports the older “one bucket contains about 1000 candidate touchpoints” model, but corrects the size estimate: this HAR is about 123KB decoded, not a 5-15KB compressed response.

### 17A.7 `/odm/validate`

Observed request:

```json
{
  "mvs": "Cj0g2dhkPT1JgtV6cBSKVzO9pIX8UZ1im8lGlZFdE7SQ5pW_FZ4hbosVhsHrIxy3QGtprZHMCclRr5Hf_XiK",
  "odmed": "CBYaAggEKghiMTkyNDY1Ng"
}
```

`mvs` decoded len = 63 and wraps a 61-byte opaque blob:

```proto
message MvsEnvelope {
  bytes field1 = 1; // len=61; opaque MVS material
}
```

Observed response:

```json
{
  "mv_ga4f": "...",
  "mv_aaps": "..."
}
```

Decoded output lengths:

```text
mv_ga4f decoded len = 96
mv_aaps decoded len = 62
both outputs share a similar binary prefix: 00 3f 03 af f1 ...
```

Interpretation: `/validate` is better modeled as server validation, normalization, or channel derivation over `mvs + odmed`, not as “send `matching_id` and receive attribution truth.”

### 17A.8 Revised implementation model

Server-side preprocessing model:

```text
input touchpoint:
  req_id, campaign_id, ad_group_id, creative_id, click_ts,
  source identity material: GA4F / AAPS / email / phone / install id / other device material

normalize:
  z = Normalize(identity material)
  d = SHA256(z || app_id || source || bucketed_date || salt/context)

bucket:
  prefix = high_N(d)             // N = prefix_length, here 22

OPRF-side material:
  P = HashToCurve(d or tail-material)
  y = k * P                      // server OPRF secret k
  row_key = KDF(y || odmed || bucketed_date)

candidate row:
  tag_1b         = Truncate8(H(row_key || "tag"))
  crypto_package = EncryptOrWrap(touchpoint payload, row_key, context)
  meta           = {click_ts_us, source/type flags, row_token}

store:
  CandidateStore[prefix].append({tag_1b, crypto_package, meta})
```

Client-side query and local filtering:

```text
z = Normalize(local measurement material)
d = SHA256(z || app_id || source || bucketed_date || context)

prefix = high_22(d)
P = HashToCurve(d or tail-material)
r = RandomScalar()
A = r * P

POST /odm/psm {
  odmed,
  psm_request: {
    prefix_bytes = Encode(prefix),    // observed len=3
    blinded_point = Compress(A),      // observed len=33
    params = {scheme=2, prefix_length=22},
    mode = 35
  }
}

parse response:
  A_echo = response.ec_header.field1
  B      = response.ec_header.field2
  assert A_echo == A

Y = r^-1 * B
row_key = KDF(Y || odmed || bucketed_date || app/source context)

for each candidate row:
  if quick_tag does not match:
      continue
  payload = try_open_package(crypto_package, row_key, row_meta)
  if payload opens:
      mvs = build_mvs(payload, config, row_meta)
      validate(mvs, odmed)
```

### 17A.9 Old-model corrections

| 旧判断 / 模型 | 新处理 | 原因 |
|---|---|---|
| OPRF / PSM 是核心 | 保留并上升为主推断实现 | EC point、双 EC response header、prefix_length、1009-row payload 均支持 |
| hash 后截前 N bit 作为 prefix bucket | 保留 | `prefix_length=22`，request 中出现 3-byte prefix-like blob |
| 一个 bucket 返回约 1000 条候选触点 | 基本被 HAR 支持 | payload 精确拆出 1009 rows |
| 一次 response 约 5-15KB | 修正为 123KB 级 | 当前 decoded response 为 123,189 bytes，crypto payload 高熵 |
| PSM 成功后返回 `matching_id` | 修正 | `matching_id` 由 `/config` 返回，不是 `/psm` response |
| `/validate` 携 `matching_id` 查询 aggregate result | 修正 | body 是 `mvs + odmed`，response 是 `mv_ga4f/mv_aaps` |
| `extension_data` 是 JSON string | 修正 | 实际更像 16-byte protobuf-like context，并作为 `odmed` 复用 |
| Paillier / PIR 是实际实现 | 降为 alternative model | HAR 没有 Paillier selection vector 或明显 HE ciphertext |
| BootTime 进入 ODC 主链路 | 未证实 | HAR 无明文 boot_time；若存在，只可能封装进 local material / `mvs` |
| `tfo = now - first open` | 修正 | `1776212580` 按 epoch 秒解释接近抓包时间，不像 duration |

### 17A.10 Recommended hooks

| 问题 | 推荐实验 | 预期信号 |
|---|---|---|
| 使用哪条曲线？ | hook BoringSSL / Security.framework EC scalar multiply / point compress | 确认 P-256、secp256k1 或其他 curve |
| 3-byte blob 是否就是 prefix？ | 多设备、多 source、多 date/context 抓包 | blob 应随 hash prefix 变化；长度应等于 `ceil(prefix_length/8)` |
| EC point 是否每次随机 blind？ | 同一设备同一 context 连续请求 | prefix 稳定，EC point 随机变化 |
| response 第二个 EC point 是否为 `kA`？ | hook unblind 前后或定位 VOPRF verify 函数 | 看到 `r^-1` scalar multiply 或 proof verification |
| Segment B 77 bytes 结构 | hook AEAD open / decrypt / protobuf parse after local processing | 出现 campaign、adgroup、creative、req_id 或 aggregate payload |
| `mvs` 构造来源 | hook validate 前对象序列化 | 确认是否由命中 candidate row 派生 |
| `matching_id` 消费点 | 搜索 local plist / keychain / request queue | 确认是否用于 cache、report、dedupe 或 ack |
| BootTime 是否进入 material | hook `sysctl`、`mach_absolute_time`、`systemUptime`、hash input buffer | 若进入，应在 hash/normalization 前看到 boot-related value |

## 18. Open Questions

以下问题应由具体产品 RFC 继续收敛：

- install / purchase / ROAS 的 observation window 分别取多少？
- `boot_time`、`ip`、reinstall hint 的派生策略具体怎么版本化？
- Google ODM 的 3-byte `psm_request` blob 是否严格等于 `high_22(hash(local_material))`，以及 prefix 拼接里是否包含 `bucketed_date`、`odmed`、app/source context？
- `/odm/psm` 使用的具体曲线是 P-256、secp256k1 还是其他 curve，response 第二个 EC point 是否就是 `kA` 或 VOPRF proof element？
- `mvs` 是否由命中 candidate row 派生，`mv_ga4f` / `mv_aaps` 与最终 `aggregateConversionInfo` / `odm_info` 的包装边界在哪里？
- `matching_id` 的实际消费点是本地缓存、dedupe、report correlation，还是未捕获的后续链路？
- confirm 缺失时是否允许 provisional label 进入某些在线系统？
- 多归因场景里 winner-only 与 fractional-credit 的默认策略是什么？
- 各 region 是否允许 event-level partner-facing reporting？
- aggregate reporting 的 DP budget 如何按 metric 和时间窗分配？

## 19. 最终建议

建议的工程优先级是：

1. 先把边界做对：原始敏感字段不外泄，`server_request_id` 不下沉，`odm_info` 不复用。
2. 再把可用性做稳：`MMP Ask -> Claim -> Confirm` 打通，并能稳定回流 request-level label。
3. 最后持续加固：aggregate DP、verifiable workflow、PJC/PSI、DAP/VDAF 对齐。

一句话总结：真正有生产价值的 on-device measurement，不是把服务器删掉，而是把“哪些数据能离开设备、去哪一层、以什么粒度、为了什么目的离开”定义成严格协议。

## 20. 参考资料

### 20.1 Research

1. [Mayfly: Private Aggregate Insights from Ephemeral Streams of On-Device User Data](https://research.google/pubs/mayfly-private-aggregate-insights-from-ephemeral-streams-of-on-device-user-data/)
2. [Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)
3. [Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)
4. [It's My Data Too: Private ML for Datasets with Multi-User Training Examples](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)
5. [On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)
6. [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)
7. [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)
8. [SNPeek](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/)
9. [TDXRay](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/)
10. [Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)
11. [About the Enhanced attribution model](https://support.appsflyer.com/hc/en-us/articles/41442782045073-About-the-Enhanced-attribution-model)

### 20.2 Standards

1. [DAP](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/)
2. [DAP Taskprov](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap-taskprov/)
3. [VDAF](https://datatracker.ietf.org/doc/draft-irtf-cfrg-vdaf/)
4. [DAP Extensions for the Attribution API](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/)
5. [W3C Attribution Level 1](https://www.w3.org/TR/privacy-preserving-attribution/)

### 20.3 Product / Integration

1. [Integrated Conversion Measurement](https://support.google.com/google-ads/answer/16203286?hl=en-EN)
2. [About on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en)
3. [App Conversion Tracking and Remarketing - Request/Response Specifications](https://developers.google.com/app-conversion-tracking/api/request-response-specs)
4. [Implement on-device conversion measurement with a standalone SDK](https://support.google.com/google-ads/answer/16384720?hl=en)
5. [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk)
6. [AppsFlyer SRN](https://support.appsflyer.com/hc/en-us/articles/360001546905-Self-Reporting-Networks)
7. [Adjust SAN](https://help.adjust.com/en/marketer/self-attributing-networks)
8. [AppsFlyer attribution model](https://support.appsflyer.com/hc/en-us/articles/207447053-AppsFlyer-attribution-model)
9. [Adjust self-attributing callbacks](https://help.adjust.com/en/article/self-attributing-network-callbacks)
10. [Understanding iOS App campaign measurement and reporting](https://support.google.com/google-ads/answer/16771743)
11. Google ODC / ODM On-Device Measurement 技术逆向与实现模型，2026-04-30，基于 2026-04-14 HAR 样本。

### 20.4 Engineering Components

1. [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute)
2. [OpenDP](https://github.com/opendp/opendp)
3. [google/differential-privacy](https://github.com/google/differential-privacy)
4. [JAX Privacy](https://github.com/google-deepmind/jax_privacy)
5. [TensorFlow Privacy](https://github.com/tensorflow/privacy)
6. [XGBoost](https://github.com/dmlc/xgboost)
7. [LightGBM](https://github.com/microsoft/LightGBM)
8. [Private Join and Compute](https://github.com/google/private-join-and-compute)
9. [sigstore/cosign](https://github.com/sigstore/cosign)
10. [sigstore/rekor](https://github.com/sigstore/rekor)
