# On-Device Measurement RFC

状态: Draft  
最后更新: 2026-04-29  
适用对象: Ad Network, Advertiser App, MMP/AAP, Privacy Infra, ML Platform, SDK, Data Infra

## 1. 目的

本文把 `on-device measurement` 从概念整理成一份可评审、可实现、可演进的 RFC，面向广告场景，覆盖：

- 端上采集与本地最小化处理
- MMP/SRN 协议协同
- 服务端 confidential join
- request-level optimization label 回流
- aggregate reporting 发布
- 后续 DP、DAP/VDAF、PJC 等升级路径

这不是一个 toy 方案。目标是既要保护隐私，也要保住生产可用性，尤其是：

- 广告主 App 内嵌 ad network SDK；
- ad network SDK 在设备侧能看到一部分敏感或半敏感信号，例如 `boot_time`、`ip`、`device_uptime_ms`、网络状态、时区、重装痕迹等；
- MMP 仍然走 SRN 形态的协议，即 `MMP Ask -> Ad Network Claim -> MMP Confirm`；
- ad network 服务端仍然需要足够细粒度的信息做个性化优化、训练样本构造、反作弊、reconciliation 和报表。

## 2. 非目标

本文不试图：

- 第一天就消灭所有服务端信任；
- 要求所有输出面都立刻上严格 DP；
- 替代 MMP 的产品能力；
- 把所有优化问题都改造成 federated learning；
- 定义一个适配所有 ad network 的世界标准。

本文的目标是先定义一个现实可落地、边界清晰、能继续加固的系统。

## 3. 一句话定义

`on-device measurement` 不是“本地 hash 一下再上传”。  
它是一种三层架构：

1. 原始用户事件和敏感设备信号优先留在设备侧；
2. 设备只上传任务受限、生命周期受限、贡献受限的 artifact；
3. 服务端只在受控边界内完成 join、label 构造、聚合和对账，再向不同下游释放不同粒度的数据。

### 3.1 工作原理的最小心智模型

可以把整个系统理解成四句话：

1. 广告请求发生时，ad network 服务端先生成一次性的 `server_request_id`。
2. 广告主 App 内的 ad network SDK 在设备侧观察 impression、click、install、purchase，以及 `boot_time`、`ip` 这类敏感信号，但原始值尽量不出端。
3. 设备侧把这些原始观察压缩成两个对象：一个给 ad network confidential backend 的 `OnDeviceMeasurementArtifact`，一个给 MMP/SRN 流程透传的 `ODMInfoEnvelope`。
4. 服务端收到 MMP 的 `Ask -> Claim -> Confirm` 结果后，只在 confidential plane 里把 `AdRequestContext`、artifact、confirm 结果 join 成 request-level label，再分别喂给 optimization plane 和 aggregate reporting plane。

### 3.2 为什么它比“本地算个 token 再上传”更复杂

真正的 on-device measurement 至少同时解决四个问题：

- 设备侧最小化：原始敏感信号不应该直接上送。
- 协议桥接：MMP/SRN 仍然要求 `Ask -> Claim -> Confirm` 这样的跨方流程。
- 优化可用性：服务端仍然必须拿到 request-level label，才能训练出能用的投放模型。
- 发布治理：最终对外报表又必须和 request-level 明细彻底分层。

如果只做“本地 token”，通常会在三个地方失败：

- token 没有 task binding，最终演化成跨请求可复用 ID；
- token 无法支撑 MMP/SRN claim/replay/confirm；
- token 只能做 measurement，做不了 request-level optimization。

### 3.3 端到端数据流的文字图

按一次 install 的真实生产路径，数据流可以写成：

1. `Ad Request`
   ad network backend 生成 `server_request_id=int64`，并把 campaign、creative、region、consent 等上下文写入 `AdRequestContext`。
2. `Ad Response / Exposure`
   SDK 在端上记录 impression/click，并拿到最小必要 request metadata，例如 `server_request_id`、`auction_id`、`ad_network_id`。
3. `On-Device Measurement`
   SDK 结合本地 install/first_open 事件，以及本地敏感信号，生成：
   - `OnDeviceMeasurementArtifact`
   - `ODMInfoEnvelope`
4. `MMP Ask`
   MMP 观察到 install 后，携带常规 device query 和 `odm_info` 向 ad network 发起 ask。
5. `Ad Network Claim`
   ad network 在 confidential plane 内验证 `odm_info`、task binding、TTL、anti-replay、policy gate，返回 `claim_yes/no` 和短期 `claim_token`。
6. `MMP Confirm`
   MMP 完成 winner selection 后回传 confirm。到这里，SRN 协议才算闭环。
7. `Confidential Join`
   ad network 把 `AdRequestContext + Artifact + Confirm` join 成：
   - `RequestScopedOptimizationLabel`
   - `AggregateMeasurementContribution`
8. `Downstream Release`
   optimization plane 拿 request-level label 训练模型；aggregate plane 做 thresholding、contribution bounding、可选 DP 后再发布报表。

### 3.4 三种“键”的边界

这份 RFC 里最容易混淆的是三个键：

- `server_request_id`
  服务端生成，只代表一次 ad request。它是 optimization 的主键，不是用户 ID。
- `artifact_id`
  设备侧生成，只代表一次 measurement artifact。它是协议对象 ID，不是广告训练主键。
- `odm_info`
  端上生成并透传给 MMP 的 opaque envelope。它是 bridge object，不是 durable identifier。

一个简单判断标准是：

- 如果某个字段会跨请求、跨 app、跨任务复用，那它就不应该是 `server_request_id`、`artifact_id` 或 `odm_info` 中的任何一个。

## 4. 核心结论

如果只记住几件事，应该是这几条：

1. `server_request_id` 必须保留，否则 personalized optimization 很快失真。
2. `server_request_id` 只能存在于 confidential plane 和 optimization plane，不能下沉到普通 BI。
3. `odm_info` 这类 bridge object 必须被视为短生命周期 opaque envelope，而不是新的用户标识。
4. `boot_time`、原始 `ip` 等高敏感信号不是绝对不能用，但只能留在设备侧或 confidential plane。
5. request-level optimization label 和 aggregate reporting 必须分层治理。
6. Phase 1 可以先不上 DP 到 optimization plane，但 aggregate reporting plane 应尽早进入 contribution bounding + thresholding + DP 的治理模式。
7. 生产落地优先复用成熟组件，而不是自造协议栈。

## 5. 设计原则

### 5.1 最小化优先

原始敏感值，例如：

- `boot_time`
- 原始 `ip`
- `ssid` / `bssid`
- 长期稳定跨请求标识

`MUST NOT` 进入普通 BI、通用 data lake、普通 Kafka topic 或开放分析链路。

### 5.2 optimization 是一等公民

如果系统只能做 aggregate measurement，不能做 request-level label 回流，那么它对广告优化的价值会很有限。  
因此本文明确要求保留服务端生成的请求级键：

- `server_request_id`

该字段：

- `MUST` 由服务端为每次 ad request 生成；
- `MUST` 每次请求唯一；
- `MUST NOT` 被当作跨 request 的长期用户键；
- `MUST` 只存在于 confidential plane 或衍生 optimization plane；
- `MUST NOT` 流入普通报表。

### 5.3 MMP/SRN 协同不是可选项

移动广告的现实不是“网络自己测完就结束”，而是还要和 MMP/SRN 协议协同。  
因此本文显式定义：

- `MmpAskRequest`
- `AdNetworkClaimResponse`
- `MmpConfirmRequest`
- `ODMInfoEnvelope`

### 5.4 优先使用成熟组件

优先使用：

- 端上 ODM SDK: `GoogleAdsOnDeviceConversion` / Firebase ODM 路径
- confidential compute / federated analytics: `google-parfait/confidential-federated-compute`
- DP 库: `OpenDP`, `google/differential-privacy`, `JAX Privacy`, `TensorFlow Privacy`
- 私有 join / reconciliation: `google/private-join-and-compute`
- 模型训练: `XGBoost`, `LightGBM`, `TensorFlow`, `PyTorch`
- 透明度与签名: `sigstore/cosign`, `sigstore/rekor`

不建议手写：

- DP accountant
- PSI/PJC 协议
- TEE attestation 流程
- “本地算个 token 再上报”的简化伪方案

## 6. 2026-04-29 之前最新研究与标准化进展

本节只保留对系统设计真正有影响的结论。

### 6.1 Mayfly 证明了“短生命周期设备流 + 受限查询模板”是可工程化的

Google Research 2024 年的 *Mayfly* 表明：

- 设备侧可以保留短期原始流；
- 设备侧可以执行预定义模板查询；
- 上行对象不必是完整明细，也可以是最小化 artifact 或私有聚合结果；
- windowing 和 contribution bounding 不是附属细节，而是协议主体。

对本 RFC 的含义：

- measurement task 必须显式建模；
- observation window、contribution policy、task TTL 都要进协议。

来源：
- [Mayfly](https://research.google/pubs/mayfly-private-aggregate-insights-from-ephemeral-streams-of-on-device-user-data/)

### 6.2 Confidential Federated Computations 把“少信服务端”变成了工程能力

Google Research 2024 年的 *Confidential Federated Computations* 和后续 Parfait 开源组件说明：

- 服务端聚合和处理可以运行在 TEE 内；
- 客户端上传的数据可以绑定到允许的 processing graph；
- 密钥释放、budget 跟踪、processing policy 能成为系统本身的一部分。

对本 RFC 的含义：

- request-scoped join 和敏感特征衍生可以在服务端做，但必须在 confidential boundary 内做；
- `processing_manifest_digest`、`workflow_signature_ref`、`tee_attestation_ref` 应当是协议字段，而不是文档备注。

来源：
- [Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)
- [Parfait confidential federated compute](https://github.com/google-parfait/confidential-federated-compute)

### 6.3 DAP 与 attribution 扩展已经足够成熟，值得对齐对象模型

截至 2026-04-29：

- `draft-ietf-ppm-dap-17` 发布于 2026-01-30；
- PPM 工作组状态页显示 DAP 仍处于活跃推进状态；
- `draft-thomson-ppm-dap-attribution-01` 在 2026-02-17 更新，明确把 Attribution API 的需求往 DAP 上对齐。

对本 RFC 的含义：

- 即便第一阶段不直接部署完整 DAP，也应让 aggregate object model 对齐其概念：
  `task`, `report`, `report_id`, `batch`, `task expiration`, `replay protection`, `extensions`
- attribution-specific privacy budget binding 和 collector-selected batching 已经不是“脑洞”，而是公开标准化方向。

来源：
- [DAP draft-17](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/)
- [PPM working group status](https://datatracker.ietf.org/wg/ppm/)
- [DAP Extensions for the Attribution API](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/)

### 6.4 contribution bounding 已经是可扩展性问题，不只是论文里的小节

Google Research 2025 年 *Scalable contribution bounding to achieve privacy* 的启发很直接：

- 真实广告数据里，一个用户会有多次事件；
- 一个 artifact 可能影响多个 release surface；
- 如果 contribution bounding 只藏在 SQL 里，迟早不可控。

对本 RFC 的含义：

- `contribution_policy_id` 必须显式版本化；
- bounding 必须是正式 processing stage；
- 任何新 release surface 复用旧 artifact，都要重新评估 bounding 影响。

来源：
- [Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)

### 6.5 广告模型的 DP 路线已经可行，但不该一上来就全量启用

Google Research 关于 `Private Ad Modeling with DP-SGD`、semi-sensitive features、user-level DP optimization 的工作说明：

- 广告模型并非不能做 DP；
- 但比“立即全量 DP-SGD”更重要的是先把 label contract、sample lifecycle、特征边界定义清楚；
- 不同 feature 的保护强度未必相同。

对本 RFC 的含义：

- Phase 1 可以让 optimization label plane 先走 confidential-but-not-DP；
- Phase 2 再逐步引入 semi-sensitive 或 selective DP；
- 真正做训练时要优先使用 `JAX Privacy` 或 `TensorFlow Privacy` 这类成熟库。

来源：
- [Private Ad Modeling with DP-SGD](https://research.google/pubs/private-ad-modeling-with-dp-sgd/)
- [Training Differentially Private Ad Prediction Models with Semi-Sensitive Features](https://research.google/pubs/training-differentially-private-ad-prediction-models-with-semi-sensitive-features/)
- [On Convex Optimization with Semi-Sensitive Features](https://research.google/pubs/on-convex-optimization-with-semi-sensitive-features/)
- [Linear-Time User-Level DP SCO via Robust Statistics](https://research.google/pubs/linear-time-user-level-dp-sco-via-robust-statistics/)

### 6.6 可验证 privacy workflow 正在从研究走向生产

2025 年后的 “provably private insights” 路线给出了一个非常关键的工程模式：

- 开源处理代码
- TEE attestation
- workflow signature
- transparency log
- DP release discipline

对本 RFC 的含义：

- “我们承诺只会这样处理数据” 不够；
- 更强的做法是让客户端、审计系统和外部评审者都能验证：真的只有这一组公开 workflow 有资格解密并处理这批上传数据。

来源：
- [Toward provably private insights into AI use](https://research.google/blog/toward-provably-private-insights-into-ai-use/)
- [Differentially Private Insights into AI Use](https://research.google/pubs/differentially-private-insights-into-ai-use/)
- [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)

### 6.7 ODM / ICM 已经是公开产品现实

截至 2026-04-29，Google 官方文档公开说明：

- ICM 自 2025-05 起逐步 rollout；
- iOS 可通过 Firebase iOS SDK `11.14.0+` 或 standalone `GoogleAdsOnDeviceConversion` SDK 接入；
- 对某些 server-to-server MMP 集成，advertiser 需要把 on-device measurement 的 `info string` 透传给 MMP/AAP。

对本 RFC 的含义：

- `odm_info` 不能只是“实现细节”；
- 它必须成为规范对象；
- 它必须被定义为短生命周期、task-bound、opaque transport envelope。

来源：
- [Integrated Conversion Measurement](https://developers.google.com/app-conversion-tracking/api/integrated-conversion-measurement)
- [About Integrated Conversion Measurement for App Campaigns](https://support.google.com/google-ads/answer/16203286?hl=en-EN)
- [About on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en)
- [GoogleAdsOnDeviceConversion SDK repo](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk)

### 6.8 MMP 的 SRN 工作方式仍然是“先检测 install，再向网络查询”

AppsFlyer、Adjust 等官方文档仍然描述了 SRN 的本质流程：

- MMP 先检测 install 或 event；
- 再去 self-reporting network 问；
- network 根据自己的 engagement data 进行 claim 或 decline。

对本 RFC 的含义：

- `MMP Ask -> Ad Network Claim -> MMP Confirm` 是正确抽象；
- on-device measurement 不能绕开这个流程，而要给这个流程喂一个 privacy-preserving bridge object。

来源：
- [AppsFlyer SRN overview](https://support.appsflyer.com/hc/en-us/articles/360001546905-Self-Reporting-Networks)
- [Adjust SAN setup](https://help.adjust.com/en/article/self-attributing-network-san-setup)
- [Adjust self-attributing callbacks](https://help.adjust.com/en/article/self-attributing-network-callbacks)

### 6.9 Privacy Sandbox 的交互式 DP 分析说明“查询会互相影响”，不能把 release 当静态 SQL

Google Research 2025 年 *On the Differential Privacy and Interactivity of Privacy Sandbox Reports* 的关键点不是“ARA/PAA 可以做 DP”，而是：

- 查询和数据库都可能随着之前的输出而变化；
- measurement 系统的隐私分析必须考虑交互式 release，而不是单次离线统计；
- attribution/reporting API 的 guardrail 不能只写在分析文档里，必须进入协议和 budget ledger。

对本 RFC 的含义：

- aggregate reporting `MUST` 显式记录 `measurement_task_id`、`release_cadence`、`query_template_id`、`privacy_budget_ledger_ref`；
- provisional report、late correction、re-release 都要计入同一条审计链，而不是被当作“补数据”绕过预算；
- optimization plane 和 aggregate plane 的 query/release 路径必须分离，否则交互式反馈会污染 aggregate privacy accounting。

来源：
- [On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)

### 6.10 Verifiable LDP 说明“本地 DP”本身也会被投毒，端上随机化不是免死金牌

Google Research 2025 年 *Vεrity: Verifiable Local Differential Privacy* 指出：

- 本地 DP / LDP 的常见弱点不是只有精度下降，还有 poisoning；
- 如果攻击者控制一批设备，完全可以伪造本地随机化输出，显著扭曲 aggregate；
- 因此“设备侧先随机化再上传”并不自动等于“系统安全”。

对本 RFC 的含义：

- 如果后续某些 aggregate surface 采用 local DP，`MUST` 额外定义设备证明、随机性来源、签名或第三方 ground truth 绑定策略；
- 在广告场景下，任何 device-reported local-DP aggregate `SHOULD` 带 `attestation_ref`、`client_build_id` 或等价 provenance；
- 对 request-level optimization，本 RFC 仍然更推荐 confidential plane + purpose binding，而不是过早把全部训练信号改成本地 DP 上报。

来源：
- [Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)

### 6.11 顺序式 DP 审计意味着发布和训练都应该具备“持续验错”能力

Google Research 2025 年 *Sequentially Auditing Differential Privacy* 的价值在于：

- 它把 DP audit 从一次性的“离线测一把”变成了持续进行的顺序检验；
- 对复杂训练流程或重复 release 来说，更符合生产系统现实；
- 它能够更早发现实现错误、错误裁剪或预算失控。

对本 RFC 的含义：

- aggregate reporting plane `SHOULD` 配置持续运行的 audit canary，而不只是上线前跑一次测试；
- 训练侧若引入 `TensorFlow Privacy` / `JAX Privacy`，`SHOULD` 对关键 label/feature pipeline 维护固定 replay sample 和黑盒审计任务；
- `dp_audit_policy_id` 应成为治理字段，而不是 wiki 里的人工流程。

来源：
- [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)

### 6.12 多归因训练样本研究说明“一个 conversion 不一定只属于一个 user/request”

Google Research 2025 年 *It's My Data Too: Private ML for Datasets with Multi-User Training Examples* 的启发对广告特别直接：

- 一个训练样本可能同时关联多个 user、多个 request，不能默认“1 conversion = 1 user = 1 request”；
- 真正困难的不只是 DP 噪声，而是先把多归因样本裁剪成可治理的数据集；
- contribution bounding 在训练集构造阶段就要发生，而不是等到报表发布阶段才补救。

对本 RFC 的含义：

- `RequestScopedOptimizationLabel` `SHOULD` 显式携带 credit 分配语义，例如 winner-only 还是 fractional credit；
- 同一个 conversion 如果在 MMP/SRN 流程里存在多个候选 request，训练侧 `MUST` 保留 `conversion_group_id`、`credit_fraction_micros` 或等价字段，而不是静默覆盖；
- 如果后续把 optimization plane 升级为 user-level DP，训练样本构造 `MUST` 先做 per-user / per-conversion contribution bounding，再接入 `JAX Privacy`、`TensorFlow Privacy` 等训练栈。

来源：
- [It's My Data Too: Private ML for Datasets with Multi-User Training Examples](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)

### 6.13 2026 年 TEE 侧信道研究说明 confidential compute 不是“开了 TEE 就万事大吉”

2026 年 Google Research 公开的 *SNPeek* 和 *TDXRay* 给了一个对生产非常重要的提醒：

- confidential VM / TEE 可以保护内存内容不被宿主机直接读取，但不自动消除 page-fault、cache contention、timing 这类侧信道；
- 侧信道风险和 workload 形态直接相关，同样的 TEE 平台，join、feature engineering、训练前裁剪三个 workflow 的泄露面可能完全不同；
- “我们用了 TEE” 不能替代 workload 级别的评估、分层和缓解。

对本 RFC 的含义：

- confidential plane `MUST` 再细分成 workflow，而不是把所有敏感 join、特征衍生、debug 查询都塞进同一个大 enclave / CVM；
- 处理 `boot_time`、raw `ip`、reinstall hint、`server_request_id` join 的 workflow `SHOULD` 显式标注 side-channel risk profile，并优先采用顺序扫描、固定模板、受限索引访问或 oblivious-memory 友好的实现；
- TEE attestation `SHOULD` 只证明“代码是这份代码”，不能被当作“泄露风险已经消失”的替代品；上线 gate 仍需 workload-specific 评估、回放测试和 kill switch。

来源：
- [SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/)
- [TDXRay: Microarchitectural Side-Channel Analysis of Intel TDX for Real-World Workloads](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/)

## 7. 角色与信任边界

### 7.1 角色

- `Advertiser App`: 广告主 App
- `Ad Network SDK`: 广告网络 SDK
- `MMP SDK`: MMP/AAP SDK
- `Ad Network Backend`: 广告网络服务端
- `Confidential Compute Cluster`: TEE 或同等级隔离边界

### 7.2 三层输出面

#### 7.2.1 `Confidential Raw Plane`

包含：

- 加密 device artifact
- opaque `odm_info`
- 带 `server_request_id` 的 request join 表
- 敏感特征衍生处理
- claim replay cache
- label 构造中间态

要求：

- `MUST` 运行在受控 confidential boundary 内
- `MUST` 有 TTL
- `MUST` 默认不能被人工直接按行查询
- `SHOULD` 记录 attestation 与 workflow provenance

#### 7.2.2 `Optimization Label Plane`

包含：

- request-scoped label
- 可训练的衍生特征
- delayed feedback 信息
- sample weighting / censoring 信息

要求：

- 初期 `MAY` 不做 DP
- `MUST` 做 purpose binding
- `MUST` 与普通 BI 隔离
- `MUST NOT` 暴露 raw `boot_time`、raw `ip`、raw `odm_info`

#### 7.2.3 `Aggregate Reporting Plane`

包含：

- campaign / adgroup / creative 级指标
- 时间桶聚合
- reconciliation summary
- 与 DAP/VDAF 对齐的 aggregate output

要求：

- `MUST` 有 minimum crowd threshold
- `MUST` 有 contribution bounding
- `SHOULD` 对较广 release surface 加入 DP
- `MUST NOT` 包含 `server_request_id`

## 8. 数据保留模型

### 8.1 设备侧

- impression buffer TTL: 推荐 `24h`
- click buffer TTL: 推荐 `7d`
- conversion observation window: 业务定义，常见为 `1d` / `7d` / `30d`
- 原始敏感信号缓存 TTL: 推荐 `分钟级到小时级`

### 8.2 confidential 服务端

- raw artifact TTL: 推荐 `<= 30d`
- claim replay cache TTL: 与 claim window 对齐，常见 `7d` 到 `30d`
- request join TTL: 与训练和归因窗口对齐，常见 `30d` 到 `90d`

### 8.3 optimization plane

- 训练样本 TTL 取决于模型刷新节奏和合法性要求；
- `SHOULD` 与原始 artifact 保留时间解耦。

## 9. 规范对象模型

下面用 JSON 展示对象形状。  
生产传输建议使用 Protobuf 或 CBOR。若使用 JSON，所有 `int64` 建议序列化为十进制字符串，避免 JavaScript 精度问题。

### 9.1 `AdRequestContext`

```json
{
  "schema_version": 1,
  "server_request_id": "9183372036854775801",
  "auction_id": "331245778901",
  "ad_network_id": 1024,
  "advertiser_id": 200045,
  "campaign_id": 9830012,
  "adgroup_id": 9830099,
  "creative_id": 712334455,
  "placement_id": 40012,
  "exchange_id": 18,
  "request_ts_ms": "1777465200123",
  "device_platform": "ios",
  "app_bundle": "com.example.game",
  "country_code": "US",
  "region_code": "CA",
  "consent_state": {
    "att_authorized": false,
    "gdpr_applies": false,
    "dma_ad_user_data": "granted",
    "dma_ad_personalization": "granted"
  },
  "model_feature_scope_id": "scope_req_v4",
  "optimization_goal": "purchase_value"
}
```

### 9.1A `MeasurementTaskDescriptor`

这是整套系统里最值得单独建模的对象。没有 task descriptor，很多边界会退化成代码里的隐含约定。

```json
{
  "schema_version": 1,
  "measurement_task_id": "install_icm_ios_v3",
  "task_type": "install_measurement",
  "task_scope": "srn_claim_and_opt",
  "task_created_ts_ms": "1777465100000",
  "task_expiry_ts_ms": "1778070000000",
  "query_template_id": "tmpl_install_claim_v2",
  "release_cadence": "daily_final_plus_intraday_provisional",
  "contribution_policy_id": "contrib_install_v2",
  "privacy_budget_ledger_ref": "pb_install_ios_2026q2",
  "allowed_partners": [
    "adjust",
    "appsflyer"
  ],
  "allowed_release_surfaces": [
    "optimization_plane",
    "aggregate_reporting_plane"
  ],
  "late_event_cutoff_ts_ms": "1778070000000"
}
```

### 9.2 `SensitiveSignalSnapshot`

这个对象 `MUST` 只存在于设备侧或 confidential raw plane。

```json
{
  "capture_ts_ms": "1777465210456",
  "boot_time_ms": "1777120000000",
  "device_uptime_ms": "345210456",
  "ip_v4": "203.0.113.14",
  "network_type": "wifi",
  "carrier_mccmnc": "310260",
  "locale": "en_US",
  "timezone_offset_min": -420,
  "battery_bucket": "30_50",
  "disk_state_bucket": "10_20_free",
  "is_vpn": false
}
```

### 9.3 `DerivedSensitiveFeatures`

这个对象在满足 policy 的前提下 `MAY` 进入 optimization plane，但必须是衍生值而不是原始值。

```json
{
  "feature_version": "derived_sensitive_v3",
  "boot_time_bucket_hours": 96,
  "uptime_bucket_min": 5760,
  "coarse_ip_prefix": "203.0.113.0/24",
  "network_quality_bucket": "wifi_stable",
  "local_hour_bucket": 19,
  "timezone_bucket": "utc_minus_8",
  "fraud_risk_seed_features": {
    "is_vpn": false,
    "clock_skew_bucket": "lt_5s",
    "recent_reinstall_bucket": "unknown"
  }
}
```

### 9.4 `OnDeviceMeasurementArtifact`

```json
{
  "schema_version": 1,
  "artifact_id": "c77a8a3f-7a9a-4aa7-8b8d-9bff0f2cbe9d",
  "artifact_type": "install_candidate",
  "artifact_created_ts_ms": "1777468805123",
  "artifact_expiry_ts_ms": "1777555205123",
  "ad_network_id": 1024,
  "app_bundle": "com.example.game",
  "server_request_ref": {
    "server_request_id": "9183372036854775801",
    "auction_id": "331245778901"
  },
  "event_ref": {
    "conversion_event_id": "8ed4a45a-3699-4927-b7d0-c80ac2d0f417",
    "event_name": "first_open",
    "event_ts_ms": "1777468805000"
  },
  "derived_sensitive_features": {
    "feature_version": "derived_sensitive_v3",
    "boot_time_bucket_hours": 96,
    "uptime_bucket_min": 5760,
    "coarse_ip_prefix": "203.0.113.0/24",
    "network_quality_bucket": "wifi_stable"
  },
  "contribution_policy_id": "contrib_install_v2",
  "device_local_nonce": "8c19eafc0b0d4d8fb4ef0ef77c191f7d",
  "payload_mac": "base64:8gM1...=="
}
```

### 9.5 `ODMInfoEnvelope`

这就是端上到 MMP/SRN 的桥接对象。

```json
{
  "schema_version": 1,
  "envelope_type": "odm_info",
  "artifact_id": "c77a8a3f-7a9a-4aa7-8b8d-9bff0f2cbe9d",
  "ad_network_id": 1024,
  "app_bundle": "com.example.game",
  "issued_ts_ms": "1777468805123",
  "expiry_ts_ms": "1777555205123",
  "opaque_payload": "base64url:eyJraWQiOiJrMSIsImNpcGhlcnRleHQiOiIuLi4ifQ",
  "transport_hints": {
    "channel": "mmp_sdk",
    "partner_name": "adjust"
  }
}
```

规则：

- MMP `MUST` 把 `opaque_payload` 视为 opaque
- MMP `MUST NOT` 解码后落普通分析字段
- envelope `MUST` 是 task-bound 的
- envelope `MUST` 有明确过期时间
- envelope `MUST NOT` 跨 app、跨 network、跨任务复用

### 9.6 `MmpAskRequest`

```json
{
  "schema_version": 1,
  "ask_request_id": "01JTG7X7NQ0Z4W9Y9G1M13FQ7Q",
  "mmp_id": 501,
  "partner_app_id": "app_200045_ios",
  "ad_network_id": 1024,
  "install_ts_ms": "1777468810021",
  "event_type": "install",
  "device_query": {
    "idfa": "00000000-0000-0000-0000-000000000000",
    "idfv": "A0C33210-17D4-4A7A-97D8-BC0244B1E6A1",
    "ip_hint": "203.0.113.14",
    "user_agent_hash": "sha256:1ad0...",
    "country_code": "US"
  },
  "odm_info": "base64url:eyJzY2hlbWFfdmVyc2lvbiI6MX0",
  "mmp_event_id": "2737f9ce-ef8d-458b-9c29-29e9f9ffde4e"
}
```

### 9.7 `AdNetworkClaimResponse`

```json
{
  "schema_version": 1,
  "ask_request_id": "01JTG7X7NQ0Z4W9Y9G1M13FQ7Q",
  "claim_decision": "claim_yes",
  "claim_token": "base64url:Q0xBSU0tVE9LRU4uLi4",
  "claim_reason_code": "matched_odm_request_context",
  "claim_confidence": 0.93,
  "attribution_scope": {
    "campaign_id": 9830012,
    "adgroup_id": 9830099,
    "creative_id": 712334455,
    "network_type": "google_app_campaign"
  },
  "claim_expiry_ts_ms": "1777555211000",
  "replay_cache_key": "sha256:e302..."
}
```

建议：

- 前台 claim 接口只返回协议推进所需最小字段；
- 不返回 raw sensitive signal；
- 不返回 request log 明细。

### 9.7A `ClaimTokenBinding`

`claim_token` 不应该只是一个“能过校验的字符串”，而应该绑定 ask 的上下文，否则很容易被跨请求复用或被 MMP 探测边界。

```json
{
  "schema_version": 1,
  "claim_token_id": "ctok_01JTG7Y5PJWQY2P0R3K6H42S7D",
  "ask_request_id": "01JTG7X7NQ0Z4W9Y9G1M13FQ7Q",
  "measurement_task_id": "install_icm_ios_v3",
  "query_template_id": "tmpl_install_claim_v2",
  "query_hash": "sha256:abdd91...",
  "ad_network_id": 1024,
  "policy_version": "claim_policy_v5",
  "issued_ts_ms": "1777468811050",
  "expiry_ts_ms": "1777555211000",
  "signed_by": "hsm:key-2026-04",
  "signature": "base64url:MEQCIF..."
}
```

### 9.8 `MmpConfirmRequest`

```json
{
  "schema_version": 1,
  "confirm_request_id": "01JTG7Y3B4YPYXCY7AD8KSN9XK",
  "ask_request_id": "01JTG7X7NQ0Z4W9Y9G1M13FQ7Q",
  "claim_token": "base64url:Q0xBSU0tVE9LRU4uLi4",
  "final_outcome": "confirmed_install",
  "mmp_attribution_ts_ms": "1777468811098",
  "mmp_result_id": "mmpres_79120381",
  "dedupe_key": "sha256:54da...",
  "post_install_metadata": {
    "store": "app_store",
    "is_redownload": false
  }
}
```

### 9.9 `RequestScopedOptimizationLabel`

```json
{
  "schema_version": 1,
  "label_id": "lbl_01JTG82T1H2V0HDM0Y1D0T1RRT",
  "server_request_id": "9183372036854775801",
  "conversion_group_id": "cg_20260429_88710023",
  "auction_id": "331245778901",
  "ad_network_id": 1024,
  "label_type": "purchase_value_7d",
  "label_value": 19.99,
  "label_currency": "USD",
  "label_event_count": 1,
  "credit_allocation_policy_id": "winner_only_v1",
  "credit_fraction_micros": 1000000,
  "attribution_rank": 1,
  "first_label_ts_ms": "1777480000000",
  "observation_window_sec": 604800,
  "right_censored": false,
  "sample_weight": 1.0,
  "feature_scope_id": "scope_req_v4",
  "trust_scope_id": "opt_plane_internal_v1",
  "trainer_policy_id": "trainer_purchase_v3"
}
```

### 9.10 `AggregateMeasurementReport`

```json
{
  "schema_version": 1,
  "measurement_task_id": "agg_purchase_value_daily_v1",
  "task_window_start_ts_ms": "1777420800000",
  "task_window_end_ts_ms": "1777507200000",
  "group_keys": {
    "advertiser_id": 200045,
    "campaign_id": 9830012,
    "country_code": "US"
  },
  "metrics": {
    "installs": 1245,
    "purchasers": 281,
    "purchase_value_usd": 6441.32
  },
  "privacy": {
    "contribution_policy_id": "contrib_daily_adv_v3",
    "minimum_crowd_size": 50,
    "dp_enabled": true,
    "epsilon": 0.35,
    "delta": 1e-9
  },
  "release_status": "final"
}
```

### 9.11 `OptimizationTrainingExample`

optimization plane 真正消费的通常不是原始 request 表，而是 feature row + label row 的绑定结果。这里单独建模是为了避免后续把 raw artifact 直接开放给训练。

```json
{
  "schema_version": 1,
  "training_example_id": "trn_01JTG84E6SEVY5N12TRH5K6Q3P",
  "server_request_id": "9183372036854775801",
  "conversion_group_id": "cg_20260429_88710023",
  "feature_scope_id": "scope_req_v4",
  "label_id": "lbl_01JTG82T1H2V0HDM0Y1D0T1RRT",
  "label_status": "observed_final",
  "observation_window_id": "purchase_7d_v3",
  "window_close_ts_ms": "1778070000000",
  "loss_weight": 1.0,
  "credit_fraction_micros": 1000000,
  "multi_touch_group_size": 1,
  "match_strength": "strong_request_join",
  "claim_confidence": 0.93,
  "trainer_policy_id": "trainer_purchase_v3",
  "features": {
    "campaign_id": 9830012,
    "creative_id": 712334455,
    "country_code": "US",
    "local_hour_bucket": 19,
    "network_quality_bucket": "wifi_stable",
    "recent_reinstall_bucket": "unknown"
  }
}
```

### 9.12 `DPReleaseAuditRecord`

```json
{
  "schema_version": 1,
  "audit_record_id": "aud_01JTG86M6V0QK0TVWDK0P4M2RP",
  "measurement_task_id": "agg_purchase_value_daily_v1",
  "query_template_id": "tmpl_campaign_country_daily_v1",
  "release_id": "rel_2026_04_29_0001",
  "dp_audit_policy_id": "seq_audit_v2",
  "privacy_budget_ledger_ref": "pb_agg_2026q2",
  "auditor_impl": "dp_auditorium+sequential_audit",
  "audit_status": "pass",
  "audit_ts_ms": "1777470100000",
  "canary_sample_ref": "canary_purchase_daily_v4"
}
```

### 9.12A `ExternalAttributionCompatRecord`

有些对外归因 API 明确要求 request 级透传字段，例如 Google App Conversion API 的 `odm_info`、`rdid`、`User-Agent`、`X-Forwarded-For`、`ad_event_id` 和 cross-network attribution 请求。这些字段在工程上经常“顺手”混进训练或通用埋点，这是本 RFC 明确禁止的。

正确做法是单独建一个 egress-only 兼容对象，让“为了对外协议兼容而保留”的字段和“为了内部 optimization / reporting 而保留”的字段分层治理。

```json
{
  "schema_version": 1,
  "compat_record_id": "ext_01JTG8C2H8NMQ2V0MHKQW0P6N7",
  "provider": "google_ads_app_conversion_api",
  "server_request_id": "9183372036854775801",
  "conversion_group_id": "cg_20260429_88710023",
  "mmp_event_id": "2737f9ce-ef8d-458b-9c29-29e9f9ffde4e",
  "odm_info_cache_key": "odmcache_4b6c1f2a",
  "retention_ttl_sec": 2592000,
  "google_ads": {
    "odm_info": "abcdEfadGdaf",
    "rdid": "0F7AB11F-DA50-498E-B225-21AC1977A85D",
    "id_type": "idfv",
    "lat": 0,
    "ctry_c": "US",
    "eea": 0,
    "ad_personalization": 1,
    "ad_user_data": 1,
    "x_forwarded_for": "203.0.113.14",
    "app_user_agent": "ExampleMMP/5.4.1 (iOS 18.1; en_US; iPhone16,2; Build/22B92; Proxy)",
    "ad_event_id": "Q2owS0VRancwZHk0QlJDdXVMX2U1TQ",
    "cross_network_attributed": 1
  }
}
```

约束：

- `ExternalAttributionCompatRecord` `MUST NOT` 直接喂给 optimization feature pipeline；
- raw `rdid`、raw `x_forwarded_for`、完整 `app_user_agent` `MUST` 视为 egress plane 专属字段，而不是通用 join key；
- `ad_event_id` 这类第三方返回的 request 级 id `SHOULD` 仅用于对外 confirm / cross-network follow-up，不应反向污染内部 `server_request_id` 主键体系。

## 10. 端到端协议流程

### 10.1 Ad Request

1. Ad network backend 收到 ad request。
2. 服务端生成 `server_request_id`，必要时同时生成 `auction_id`。
3. request context 写入 confidential raw plane。
4. ad response 返回给 App，同时下发设备侧所需最小 request metadata。

硬要求：

- `server_request_id` `MUST` 每请求唯一；
- `server_request_id` `MUST NOT` 出现在普通客户端日志；
- request context `MUST` 保留到足以支撑归因和优化窗口结束。

### 10.2 端上采集

ad network SDK 在广告主 App 内采集：

- impression / click
- install / first_open / in-app event
- 本地敏感信号

原始采集规则：

- 原始值 `SHOULD` 尽量只保留在内存或短期本地缓存；
- 能先转 bucket 或衍生特征的，`SHOULD` 先转再上传；
- 同一用户对同一 measurement task 的贡献 `MUST` 受上限约束。

### 10.3 端上 artifact 生成

当出现候选 conversion 时，SDK 生成：

- `OnDeviceMeasurementArtifact`
- `ODMInfoEnvelope`

前者给 ad network confidential processing；  
后者给 MMP/SRN 协议桥接。

### 10.3A 对外归因 API 兼容缓存

如果系统需要同时对接 MMP SRN 和 Google App Conversion API 一类外部归因 API，端上或 MMP server 通常还要维护一层短期兼容缓存：

- `odm_info` `MUST` 缓存到足以覆盖 post-install conversion 的窗口，因为官方文档明确要求后续 app 内 conversion 继续带上它；
- `rdid`、`id_type`、`lat`、`app_version`、`os_version`、`sdk_version`、`timestamp`、`User-Agent`、`X-Forwarded-For`、consent flags 等字段 `MAY` 为对外 API 暂存；
- 这些字段 `MUST` 进入独立 egress adapter 或 `ExternalAttributionCompatRecord`，而不是并入 `OnDeviceMeasurementArtifact` 或优化训练样本。

一句话说：`odm_info` 负责桥接 on-device measurement，兼容缓存负责满足外部 API 契约，两者相关，但不是同一个数据面。

### 10.4 MMP Ask

MMP 观察到 install 或 event 后，向 ad network 发起：

- `MmpAskRequest`

这个 ask 可以同时带：

- 常规 device query 字段；
- 短生命周期 opaque `odm_info`。

### 10.5 Ad Network Claim

ad network 校验：

- envelope 是否过期
- anti-replay 状态
- partner 是否有权限
- policy / consent gate
- 匹配条件是否满足

然后返回：

- `claim_yes` / `claim_no`
- 如果是 `yes`，则返回 `claim_token`

### 10.6 MMP Confirm

MMP 完成自己的归因判断后，向 ad network 发送：

- `MmpConfirmRequest`

这一步把一个“可 claim 候选”变成“可用于 optimization / reporting 的最终结果”。

如果下游还要向 Google Ads 发起 cross-network attribution follow-up，则还会多一条并行但独立的 egress 支路：

1. 外部 API 返回 `ad_event_id`；
2. MMP / attribution partner 完成自己的 winner decision；
3. egress adapter 使用 `ad_event_id` + `attributed` 发送 follow-up；
4. 这条支路 `MUST NOT` 反向定义内部 optimization label 主键，内部主键仍然是 `server_request_id`。

### 10.7 confidential join 与 label 构造

在 confidential plane 内执行：

1. join `AdRequestContext`
2. join `OnDeviceMeasurementArtifact`
3. join `MmpConfirmRequest`
4. 构造 request-scoped label
5. 构造 bounded aggregate contribution

### 10.8 aggregate reporting

aggregate output 只有在经过下列处理后才能释放：

- dedupe
- contribution bounding
- minimum crowd threshold
- 可选的 DP noise
- audit log

### 10.9 一个完整 install 例子

下面给一个带 mock 数据的完整例子，帮助把对象和流程串起来：

1. `2026-04-29 10:00:00.123 UTC`
   ad network backend 收到一次广告请求，生成：
   - `server_request_id="9183372036854775801"`
   - `auction_id="331245778901"`
   - `campaign_id=9830012`
2. `2026-04-29 10:00:01.800 UTC`
   端上发生 click，SDK 在本地记录：
   - `boot_time_ms="1777120000000"`
   - `ip_v4="203.0.113.14"`
   - `device_uptime_ms="345210456"`
   这些原始值仍留在端上内存或短期加密缓存。
3. `2026-04-29 13:40:05.123 UTC`
   用户首次打开 App，SDK 生成：
   - `artifact_id="c77a8a3f-7a9a-4aa7-8b8d-9bff0f2cbe9d"`
   - `odm_info="base64url:eyJzY2hlbWFfdmVyc2lvbiI6MX0"`
4. `2026-04-29 13:40:10.021 UTC`
   MMP 发起 ask：
   - `ask_request_id="01JTG7X7NQ0Z4W9Y9G1M13FQ7Q"`
   - `mmp_event_id="2737f9ce-ef8d-458b-9c29-29e9f9ffde4e"`
   - `odm_info=<opaque string>`
5. `2026-04-29 13:40:11.050 UTC`
   ad network 返回：
   - `claim_decision="claim_yes"`
   - `claim_token=<signed short-lived token>`
   - `claim_confidence=0.93`
6. `2026-04-29 13:40:11.098 UTC`
   MMP 发送 confirm，声明 winner 是这家 ad network。
7. confidential plane 内部 join 后产出：
   - `label_id="lbl_01JTG82T1H2V0HDM0Y1D0T1RRT"`
   - `label_type="purchase_value_7d"`
   - `server_request_id="9183372036854775801"`
8. 7 天窗口关闭后：
   - optimization plane 得到一条 request-level training example；
   - aggregate plane 把该用户对 `campaign_id=9830012,country_code=US` 的贡献裁剪到 `contribution_policy_id="contrib_daily_adv_v3"` 允许的上限，再参与每日报表发布。

## 11. 敏感信号流转规范

这部分是整个 RFC 最容易被做坏的地方，因此单独写清楚。

### 11.1 App 可以采哪些

`MAY` 采：

- `boot_time_ms`
- `device_uptime_ms`
- 原始 `ip`
- user agent
- coarse network class
- locale / timezone
- reinstall hints
- app / os / model family

### 11.2 应该怎么走

推荐路径：

1. raw signal 在设备侧采集
2. 尽早转换为 bucket、truncated value 或 derived feature
3. 只通过 artifact 或 confidential upload 进入服务端
4. 只在 confidential join / fraud / label workflow 中消费
5. 不进入普通报表和普通训练表

### 11.3 绝对不应该怎么走

- raw `boot_time` 透传给 MMP
- raw `ip` 进入通用 Kafka topic
- 原始敏感字段作为长期 identity key
- `odm_info` 被设计成可复用 pseudo-user-id

### 11.4 为外部归因 API 兼容而暂存的字段应该怎么走

有些字段不是 ODM 本身需要，而是 Google App Conversion API 这类外部协议需要，例如 `rdid`、`id_type`、`User-Agent`、`X-Forwarded-For`、`ad_event_id`、`attributed`。这些字段的推荐流向是：

1. 只在端上 / MMP / egress adapter 的专用链路出现；
2. 只保留到完成外部 API 请求和排障 TTL 为止；
3. 默认不进入 optimization feature 表，不进入 aggregate reporting 表；
4. 若确实需要用于 fraud 或 reconciliation，`MUST` 在 confidential workflow 内再次降维成派生特征，再决定是否可以下游消费。

不要因为外部 API 要 raw 字段，就把内部所有数据面一起放松。

## 12. 匹配策略

本文假设存在多档匹配强度。

### 12.1 最强

- 通过 confidential plane 内的 `server_request_id` 进行 request 级精确关联

### 12.2 中等

- 通过短生命周期 `odm_info` / artifact 做 task-bound 匹配

### 12.3 更弱

- 通过临时衍生特征做 bounded probabilistic matching

规则：

- optimization `SHOULD` 优先消费强匹配结果；
- 弱匹配 `MUST` 带上 confidence；
- settlement 或敏感对账场景 `SHOULD` 使用更严格门槛。

## 13. optimization 需求

### 13.1 为什么必须有 `server_request_id`

广告优化经常需要回答：

- 哪次 ad request 触发了 install？
- 哪次 request 对应了 purchase value？
- 哪些请求在 observation window 结束后仍然是 hard negative？

没有 request 级键，系统会退化成：

- aggregate-only measurement
- 弱监督训练
- delayed feedback 处理能力不足

### 13.2 label contract

每一种 optimization label `MUST` 定义：

- `label_type`
- `observation_window`
- `right_censoring` 规则
- `late_event_cutoff`
- `dedupe` 规则
- `credit_allocation` 规则
- `sample_weight` 规则
- `trust_scope_id`
- `trainer_policy_id`

如果一个 conversion 可能对应多个候选 touch / request，label contract 还 `MUST` 明确：

- winner-only 还是 fractional credit
- `conversion_group_id` 的构造规则
- `credit_fraction_micros` 与 `sample_weight` 如何共同生效
- 多归因样本在训练集进入前如何做 contribution bounding

### 13.3 推荐 baseline

第一阶段训练推荐：

- `LightGBM`
- `XGBoost`
- delayed-feedback aware pipeline
- right-censoring aware label materialization

确实需要时再升级：

- `TensorFlow` / `PyTorch`
- `JAX Privacy` / `TensorFlow Privacy`

## 14. aggregate reporting 需求

### 14.1 最低控制集合

任何 aggregate release `MUST` 实现：

- dedupe
- contribution bounding
- minimum crowd threshold
- audit log

### 14.2 DP 策略

本文明确允许阶段性 trade-off：

- optimization label plane 初期 `MAY` 只做 confidential + TTL + ACL + audit
- aggregate reporting plane `SHOULD` 更早进入 DP 治理

### 14.3 DAP/VDAF 对齐

即使第一阶段不直接部署完整 DAP，也建议 aggregate object model 对齐：

- `task`
- `task_expiration`
- `report`
- `report_id`
- `batch`
- `collect_request`
- `aggregate_result`
- `extension_fields`

## 15. 跨方 reconciliation 与 settlement

如果后续要做 advertiser / publisher / ad network 的跨方对账：

- 优先考虑 `Private Join and Compute`
- 不要回退到跨方交换 raw user-level 明细

适合的场景：

- advertiser vs ad network reconciliation
- publisher vs ad network settlement
- MMP 协助下的 aggregate sanity check

来源：
- [Private Join and Compute](https://github.com/google/private-join-and-compute)

## 16. 安全与治理要求

### 16.1 Anti-replay

每个 artifact / claim flow `MUST` 至少带：

- 唯一 nonce 或 report ID
- expiry
- task binding
- replay cache key

### 16.2 Purpose binding

每次 confidential upload `SHOULD` 绑定：

- allowed processing workflow
- allowed release surface
- retention policy

### 16.3 Verifiability

confidential plane `SHOULD` 存：

- `processing_manifest_digest`
- `workflow_signature_ref`
- `tee_attestation_ref`
- `privacy_budget_ledger_ref`

### 16.4 Access control

- optimization plane `MUST` 与 BI 隔离
- confidential raw plane `MUST` 默认不可人工查明细
- partner-facing API `MUST` 只暴露契约最小集

### 16.5 Anti-probing

SRN claim 的主要风险之一不是“被偷走一条明文数据”，而是被 MMP 或其他集成方长期探测出 network coverage 边界。因此：

- `MmpAskRequest` `MUST` 受 query template 限制；
- 同一 `mmp_event_id`、`dedupe_key`、`odm_info` 组合 `MUST` 有 bounded-shot 查询次数；
- `claim_token` `MUST` 绑定 `query_hash`、`measurement_task_id` 和 `policy_version`；
- partner-facing claim API `SHOULD` 默认不返回 loser diagnostics、原始 touch 时间戳或内部匹配 reason 明细。

### 16.6 TEE 侧信道与执行形态加固

TEE/CVM 不是 magic box。对包含 `server_request_id` join、raw `ip`、`boot_time`、reinstall hints 的 workflow，至少应有：

- `workflow_classification`: `artifact_validation`、`claim_join`、`feature_derivation`、`egress_adapter` 分开部署，避免 debug / compat / join 混跑；
- `side_channel_risk_profile`: 高风险 workflow `SHOULD` 优先采用批处理、固定模板、顺序访问、预先 padding 或 oblivious memory 友好的实现；
- `debug_policy`: 线上 confidential workflow `MUST NOT` 打印 request 级敏感字段，不允许 ad hoc SQL 直查原始输入；
- `kill_switch`: 发现 attestation 漂移、侧信道评估失败或异常 replay pattern 时，`MUST` 能快速关闭相关 workflow，而不是只能整套系统停机。

## 17. Trade-off 设计

本文刻意允许某些地方放松，但不是所有地方都能放松。

### 17.1 可以先放松的地方

- optimization label plane 初期可以先不上 DP
- confidential plane 初期可以先用单方 confidential compute，而不是 MPC
- MMP bridge 可以先只做 opaque pass-through
- baseline model 可以先做 GBDT，不必直接上 DP deep learning 或 federated fine-tuning

### 17.2 不建议放松的地方

- 不要把 `server_request_id` 下沉到 BI
- 不要把 raw `boot_time` 或 raw `ip` 透传给 MMP
- 不要把 `odm_info` 做成 durable token
- 不要取消 anti-replay
- 不要把 contribution bounding 当成可选项

### 17.3 为什么 optimization plane 可以先不上 DP

因为 optimization plane 是：

- 内部面
- 消费方少
- 可以有强 ACL
- 可以有 TTL
- 可以做 purpose binding

而 aggregate reporting plane 天生就是 release surface，所以更应该优先上 DP discipline。

### 17.4 为什么外部兼容字段不能顺手并入 optimization

生产里最容易犯的错，是因为 Google App Conversion API 或别的 partner API 需要 `rdid`、`X-Forwarded-For`、`User-Agent`、`ad_event_id`，于是把这套字段顺手塞进训练明细表。这样会同时制造三个问题：

- 把“对外协议兼容字段”偷偷升级成“内部通用 join key”；
- 让 optimization plane 获得本来只该在 egress plane 短期存在的高敏感字段；
- 让后续 DP、ACL、TTL 和审计边界都变得含糊。

因此本文建议的放松是“兼容缓存可以存在”，不是“兼容缓存可以下沉到所有数据面”。

## 18. Deployment Profiles

### 18.1 Profile A: Minimum Production

包含：

- `server_request_id`
- device artifact
- opaque `odm_info`
- `MMP Ask -> Claim -> Confirm`
- confidential join
- request-scoped labels
- thresholded aggregate reporting

适用：

- 第一版生产系统
- iOS ODM / ICM 打通
- 快速拿到 optimization lift

### 18.2 Profile B: Recommended Default

在 Profile A 基础上增加：

- TEE-backed confidential processing
- versioned contribution policy
- DP-backed aggregate reporting
- trainer contract 与审计

适用：

- 大型 ad network
- 多团队消费场景
- 较严治理要求

### 18.3 Profile C: Cross-Party Hardened

在 Profile B 基础上增加：

- `PJC` / `PSI`
- 更强的 reconciliation
- DAP/VDAF aligned aggregate service
- 更强外部可验证性

适用：

- settlement-sensitive 场景
- 多方互不完全信任的 measurement 生态

## 19. 实现建议

### 19.1 App / SDK 侧

- 优先使用 `GoogleAdsOnDeviceConversion` 或 Firebase ODM 路径
- 定义 `OnDeviceMeasurementArtifact` 的 Protobuf schema
- 定义简洁、短生命周期、opaque 的 `odm_info` wrapper
- 为 `odm_info` 和 post-install event 建立短期缓存，而不是每次 event 重新发明 bridge token
- 本地只保留短期加密缓存

### 19.2 confidential processing

- 优先复用 Parfait confidential federated compute 组件
- 上传时绑定 workflow policy digest
- ingress 处即做 TTL 与 replay cache 控制
- 按 `artifact_validation` / `claim_join` / `feature_derivation` / `external_egress` 拆 workflow，而不是做一个万能 confidential service
- 对高敏感 workflow 预留 side-channel regression 测试和回放基准，避免“attestation 通过但 workload 泄露更严重”

### 19.3 model training

- baseline 优先 `LightGBM` / `XGBoost`
- label materialization 显式定义 observation window
- 若存在 multi-touch / multi-user attribution，先做 `conversion_group_id` 裁剪与 contribution bounding
- 业务上确实有收益时再引入 `JAX Privacy` / `TensorFlow Privacy`

### 19.4 aggregate reporting

- release logic 优先用 `OpenDP` 或成熟 DP 库
- privacy budget ledger 显式化
- 提前设计 provisional / final、late correction、bucket 重发上限

### 19.5 审计与验证栈

- DP 审计优先使用 `google/dp-auditorium`
- 顺序式在线审计可参考 `Sequentially Auditing Differential Privacy`
- 若未来引入 local DP surface，优先按 `Vεrity` 的思路把 provenance / anti-poisoning 一并设计进去
- TEE / workflow provenance 继续使用 `sigstore/cosign`、`sigstore/rekor` 和 attestation 引用字段，而不是散落在人工发布流程里

## 20. 后续产品化 RFC 仍需决策的点

本文已经能支撑大方向实现，但具体产品 RFC 仍需明确：

- request / conversion window 到底取几天
- 各 market / legal basis 下的 TTL
- claim confidence threshold
- `boot_time` / `ip` / reinstall hint 的具体特征化规则
- 优化目标是 install、purchase、ROAS、retention 还是 fraud
- 各 aggregate surface 的 DP budget allocation

## 21. 最终建议

建议的工程优先级是：

1. 先保住边界：raw sensitive signal 不外泄，`server_request_id` 不下沉，`odm_info` 不复用。
2. 再保住可用性：打通 request-level label 回流，保证 optimization 能吃到足够细粒度监督。
3. 最后持续加固：aggregate reporting 上 DP、标准化 DAP/VDAF、跨方 reconciliation 上 PJC/PSI。

## 22. 参考资料

### 22.1 Research and standards

1. [Mayfly: Private Aggregate Insights from Ephemeral Streams of On-Device User Data](https://research.google/pubs/mayfly-private-aggregate-insights-from-ephemeral-streams-of-on-device-user-data/)
2. [Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)
3. [DAP draft-17](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/)
4. [PPM working group status](https://datatracker.ietf.org/wg/ppm/)
5. [DAP Extensions for the Attribution API](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/)
6. [Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)
7. [Private Ad Modeling with DP-SGD](https://research.google/pubs/private-ad-modeling-with-dp-sgd/)
8. [Training Differentially Private Ad Prediction Models with Semi-Sensitive Features](https://research.google/pubs/training-differentially-private-ad-prediction-models-with-semi-sensitive-features/)
9. [On Convex Optimization with Semi-Sensitive Features](https://research.google/pubs/on-convex-optimization-with-semi-sensitive-features/)
10. [Linear-Time User-Level DP SCO via Robust Statistics](https://research.google/pubs/linear-time-user-level-dp-sco-via-robust-statistics/)
11. [Toward provably private insights into AI use](https://research.google/blog/toward-provably-private-insights-into-ai-use/)
12. [Differentially Private Insights into AI Use](https://research.google/pubs/differentially-private-insights-into-ai-use/)
13. [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)
14. [On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)
15. [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)
16. [Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)
17. [It's My Data Too: Private ML for Datasets with Multi-User Training Examples](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)
18. [SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/)
19. [TDXRay: Microarchitectural Side-Channel Analysis of Intel TDX for Real-World Workloads](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/)

### 22.2 Product and integration docs

1. [Integrated Conversion Measurement](https://developers.google.com/app-conversion-tracking/api/integrated-conversion-measurement)
2. [App Conversion Tracking and Remarketing - Request/Response Specifications](https://developers.google.com/app-conversion-tracking/api/request-response-specs)
3. [About Integrated Conversion Measurement for App Campaigns](https://support.google.com/google-ads/answer/16203286?hl=en-EN)
4. [About on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en)
5. [GoogleAdsOnDeviceConversion SDK repo](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk)
6. [AppsFlyer SRN overview](https://support.appsflyer.com/hc/en-us/articles/360001546905-Self-Reporting-Networks)
7. [Adjust SAN setup](https://help.adjust.com/en/article/self-attributing-network-san-setup)
8. [Adjust self-attributing callbacks](https://help.adjust.com/en/article/self-attributing-network-callbacks)

### 22.3 Engineering components

1. [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute)
2. [OpenDP](https://github.com/opendp/opendp)
3. [google/differential-privacy](https://github.com/google/differential-privacy)
4. [JAX Privacy](https://github.com/google-deepmind/jax_privacy)
5. [TensorFlow Privacy](https://github.com/tensorflow/privacy)
6. [XGBoost](https://github.com/dmlc/xgboost)
7. [LightGBM](https://github.com/microsoft/LightGBM)
8. [Private Join and Compute](https://github.com/google/private-join-and-compute)
9. [Sigstore Cosign](https://github.com/sigstore/cosign)
10. [Sigstore Rekor](https://github.com/sigstore/rekor)
