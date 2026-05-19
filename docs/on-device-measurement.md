# On-Device Measurement RFC：端侧广告归因与优化闭环

状态: Draft<br>
最后更新: 2026-05-19 UTC<br>
适用对象: Ad Network, Advertiser App, MMP/AAP, Privacy Infra, SDK, Data Infra, ML Platform

## 1. 摘要

本文讨论一个很具体的问题：

> 用户点击广告后，广告主 App 里发生了安装、打开、购买等转化。我们希望广告网络能知道这次转化是否来自自己，从而做归因和模型优化；但又不希望把设备指纹、原始设备信号、请求级内部 ID 直接交给 MMP 或沉进普通数仓。

`on-device measurement` 不是“所有东西都在设备上完成”，也不是“设备上算个 token 然后上传”。更准确地说，它是一套分层协议：

- 设备侧保留最敏感的原始观察；
- SDK 用 OPRF/PSM 这类协议做私密匹配；
- MMP 仍然走现实世界里的 Ask / Claim / Confirm 流程；
- Ad Network 只在受控服务端边界内把归因结果恢复成 request-level 优化信号；
- 对外报告只释放受限、聚合、可审计的结果。

如果只记一版结论，可以记这五条：

1. `on-device measurement` 不等于“设备上算个 token 再上传”。
2. 如果要支撑个性化优化，就必须保留 `server_request_id` / `req_id` 这类 request-scoped join key；但它们只能留在 Ad Network 受控边界内。
3. MMP 的 SRN 流程没有消失，所以主链路应该围绕 `MMP Ask -> Ad Network Claim -> MMP Confirm` 设计。
4. 生产 ODM / ODC 类协议不应理解成裸 PSM 的 `matched bit`。更准确的模型是 `OPRF/PSM layer + associated payload layer`：前者负责私密匹配，后者承载可披露的归因上下文。
5. 推荐折中是 `mmp_touch_token + opaque claim_token`：MMP 可以做 click-conversion join 和 creative-level reporting；Ad Network 在 Confirm 后通过 token 找回内部 `req_id`；MMP 不接触 `device_fp_hash`、OPRF 输入输出、bucket tail/tag 或 `req_id`。

2026-04-30 追加的 ODM / ODC HAR 逆向把第 4 点具体化：Google-compatible 路径很可能包含 `config -> OPRF/PSM candidate retrieval -> local filtering -> validate` 子流程，最终 `odm_info` 是该子流程之后的 bridge object，而不是单个本地 token。2026-05-01 的 legal review 进一步修正了披露边界：文档不应写成 “no PII leaves device”，而应写成 “raw device identifiers and raw fingerprinting material do not leave the AdNetwork SDK process; MMP may receive scoped pseudonymous attribution material depending on the selected option”。
2026-05-08 的补充调研再加了一条生产现实：touchpoint 质量本身也需要可验证。IAB Tech Lab 已把基于 Privacy Pass 语义的 device attestation 放进 OM SDK，说明广告 measurement 不只要保护 conversion 侧 PII，也要防止伪造设备、伪造 supply path 把低质量触点灌进归因与优化闭环。本文因此把 device / supply-path attestation 建模为 request-scoped quality receipt，而不是 user identifier 或新的归因 token。
2026-05-09 的补充调研把“优化”从 attribution label 又向前推进了一步：最新 W3C Attribution Level 1 工作草案继续确认 aggregate + DP + anti-replay 是公开 reporting 的主边界；IAB ADMaP / GPP / DDRF 则说明 clean-room matching、consent/deletion signal 传播已经进入行业标准化；2026-04 修订的 PIE incrementality 研究进一步提醒：last-click 或 on-device claim 只回答“谁应拿到 credit”，不等于回答“这次广告带来多少因果增量”。因此本 RFC 新增 `IncrementalityCalibrationRecord` 与 `PrivacyControlPropagationRecord`，把 request-level optimization label、因果校准、隐私控制传播拆成三个对象，避免把归因事实、增量价值和合规状态混成一张黑盒训练表。
2026-05-10 的复查补上了三个更贴近生产实现的约束：第一，PrivacyGo 和 DP ad conversion measurement 方向提醒我们，multi-ID private matching 不能把 email、phone、rdid、appsetid、gclid 等标识符先合成一个“万能用户 ID”，而要用 task-scoped identifier bundle、key epoch 和 blind rotation 管住 linkage；第二，AdsBPC 说明广告测量里的实时流式报表可以做 per-user DP，但 privacy unit、release slot、noise plan 和 budget ledger 必须先进入协议对象；第三，Singular 在 2026-05-08 更新的 Google ICM 文档把 Android / iOS open beta、Kids apps、click-through-only、5 秒 ODM timeout、`odm_error`、6 个月 retention 和 LDS->Google consent mapping 都写成生产约束，说明 MMP/AAP 集成状态本身也必须进入 RFC，而不是靠运营手册补充。
2026-05-11 的复查没有推翻 `Ask -> Claim -> Confirm` 主链路，但补上了 optimization training 的隐私契约：Google Research 的 Private Ad Modeling with DP-SGD 说明 DP-SGD 已经能用于 CTR、CVR 和 conversion count 这类广告任务，但广告数据的高稀疏、高类别不平衡会让“全量 DP-SGD”成为成本很高的 profile；Training Differentially Private Ad Prediction Models with Semi-Sensitive Features 进一步说明，生产上更合理的中间态是把特征拆成 known features、semi-sensitive derived features 和 protected labels。本文因此新增 `TrainingPrivacyPolicy`，要求 trainer 明确 `privacy_profile`、`privacy_unit`、`adjacency_relation`、feature sensitivity manifest、DP accountant 和 audit profile。Phase 1 仍可不上 DP，但不能把“未上 DP 的内部优化样本”包装成隐私保护训练。
2026-05-12 的复查把平台依赖边界再收紧一层：W3C Attribution Level 1 最新索引已推进到 `2026-05-14` Working Draft，继续把广告测量抽象成设备/用户代理侧选择 attribution、再经 aggregation service 做 anti-replay、budget 和 DP release；同时 Google Privacy Sandbox 官方在 `2025-10-17` 宣布退役 Attribution Reporting API（Chrome 和 Android）等技术，Android `MeasurementManager` 文档也把 measurement APIs 标为 API 37 deprecated 且没有直接替代 API。因此，本 RFC 不应把 Android Privacy Sandbox MeasurementManager 当作生产主线依赖，而应把它降级为历史/兼容参考；Android 生产路径更现实的是 Google ICM / App Conversion API / install referrer / consent flags / MMP partner contract。另一方面，Apple AdAttributionKit 在 iOS 18.4+ 的 conversion tag、WWDC25 的 configurable attribution rules / geography postback，以及 winning postback copy 能力，说明平台 postback plane 正在变细，但它仍不能替代 MMP SRN 的 `Ask -> Claim -> Confirm` 主链路，也不能直接提供 request-level `req_id` 优化标签。

2026-05-13 的增量复查补上了一个之前写得不够硬的生产约束：**privacy budget 本身必须成为协议对象**。W3C 最新草案的 `2026-05-14` 版本继续把 report、batch、aggregation service、anti-replay 和 privacy budget 放在同一条 aggregate path 里；`Beyond Per-Querier Budgets / Big Bird` 进一步说明，只有 per-querier / per-collector 预算在自适应查询下并不足以形成强隐私保证，真实系统还要有 global device-epoch budget、resource isolation、batch scheduling 和 DoS resilience。本文因此新增 `AggregateBudgetSchedulerPolicy` 与 mock payload：Phase 1 可以仍然只做 per-collector quota 和 thresholded reporting，但只要对外宣称 DP aggregate release，就必须记录 global budget 口径、reservation/finalization 生命周期和 scheduler policy。

2026-05-14 的增量复查把“可用性 trade-off”写进协议对象，而不是停留在架构口号。PNAS 2026-05-12 发表的 Privacy Sandbox / cookies field experiment 显示，隐私保护广告技术的经济效果受 adoption、latency 和供应侧覆盖强烈影响；2026-03 的位置数据价值研究说明，地理/位置类信号在 cold-start 阶段价值最高，但当行为历史足够丰富后会变得更可替代；PETS 2026 的 Android TCF 研究则提醒，仅有 consent framework 不等于 consent enforcement，移动 App 里仍可能在无合法依据或用户交互前泄露 AAID。本文因此新增 `DeviceSensitiveSignalPolicy` 与 `MeasurementUtilityExperimentRecord`：前者把 `boot_time`、`ip`、location-like signal 的采集点、分桶、TTL 和 release surface 写死；后者把 revenue / ROAS / CPA / latency / adoption / observability 的实验结果作为上线门槛，避免把“隐私更强”误包装成“业务无损”。

2026-05-15 的复查没有改变主链路，但把“端侧敏感信号如何进入优化闭环”补成逐事件对象：W3C TR 索引显示 `Attribution Level 1` 最新公开草案已推进到 `2026-05-14`，仍以 aggregation service、DAP/VDAF-style histogram、anti-replay、privacy budget 和 DP noise 作为公开 reporting 边界；Google Privacy Sandbox 官方退役 ARA / Private Aggregation / On-Device Personalization 等 API 的结论仍然成立；Android `MeasurementManager` 仍是 API 37 deprecated；Google Ads ODM / AAP 文档则再次说明，iOS event-data 路径会从 IP、timestamp 等设备信号派生临时数据，且 EEA/UK/CH 不激活，AAP 集成必须先采集 consent，再传 app conversion / referrer / consent 状态。本文因此新增 `DeviceSensitiveSignalDerivationRecord`：policy 说明“允许怎么做”，record 说明“这一次事件实际做了什么”。这样既能把 `server_request_id:int64` 透传回 Ad Network 内部训练面，又不把 raw `ip`、`boot_time_ms`、`device_fp_hash`、OPRF output 或 `req_id` 暴露给 MMP。

2026-05-17 的复查没有发现需要推翻主链路的新证据。新增的 RFC 化要求是：不能只定义 message schema，还要定义 implementation conformance。W3C TR 索引仍显示 `Attribution Level 1` 最新公开草案日期为 `2026-05-14`；Google ICM 官方文档继续强调它经由第三方 AAP interface 提供更实时、事件级的 reporting，并且 S2S 集成要把 on-device measurement `info` string 传给 AAP；AppsFlyer / Adjust 等 AAP 文档也继续把 ICM 写成 partner integration，而不是通用平台 API。研究侧，CHI 2026 的 Android fingerprinting developer study 说明平台限制并不会自动消灭 SDK 指纹风险，开发者更关心合规与 enforcement。因此本文新增 `MeasurementConformanceProfile`：把 Profile A/B/C/D、第三方库选择、MMP/SRN 合同、敏感信号 policy、request-level optimization、aggregate DP、fallback 与上线门禁写成一个可审计对象，避免每个团队口头声明“我们实现了 RFC”，但实际只实现了其中一小段。

2026-05-19 的复查把隐私边界从“单个子协议安全”推进到“端到端 composition 可解释”。PoPETs 2026 的 private advertising 系统化研究提醒：targeting、engagement、attribution、reporting 各自合理的 privacy notion 并不会自动组合成一个自然的端到端隐私保证，而且有用的广告系统本身会通过 market research 泄露一些信息。W3C Attribution Level 1 `2026-05-14` Working Draft 也明确把 side-channel 风险、privacy budget store、aggregation service 和 DP release 写进核心流程。产品侧，Google ICM 继续要求 S2S 集成把 on-device measurement `info` string 传给 AAP；Adjust ODM 文档进一步把“尽早捕获 app launch time”写成 attribution 准确性的关键要求。本文因此新增 `LaunchClockEvidenceRecord` 与 `EcosystemPrivacyCompositionRecord`：前者把 boot time / launch time 从“可疑指纹材料”约束成短期、可派生、可审计的 clock evidence；后者把 MMP Ask/Claim/Confirm、AAP event-level reporting、Ad Network request-level optimization 和 aggregate release 放在同一张 composition 风险表里，避免把局部隐私声明误读为端到端 DP。

本文刻意兼顾生产实用性：

- 不使用 toy 算法替代生产组件；
- 优先复用公开可用的 SDK、TEE/CVM、DP、审计和训练库；
- 在能放松的地方明确放松，例如 Phase 1 不强制 optimization plane 上 DP；
- 在不能放松的地方明确收紧，例如不允许把 `odm_info` 演化为长期标识符。

### 1.1 怎么读这份文档

这份文档比较长，不同读者可以按不同路径读：

- 如果你只想理解方案，先读 `1-4`、`7`、`9.4-9.6`、`17C-17D`。
- 如果你要评审架构，重点读 `6-8`、`10-14`、`17B`。
- 如果你关心 legal / privacy risk，重点读 `10`、`11`、`17C-17D`、`19`。
- 如果你要实现或调 SDK，重点读 `7.4`、`8`、`9`、`17A`、`17B`。
- 如果你要做优化训练，重点读 `8.8`、`8.14-8.17A`、`9.14`、`9.17`、`12`。
- 如果你要追端侧敏感 PII 如何变成可用优化信号，重点读 `8.2A-8.2B`、`9.1B-9.1C`、`10`。
- 如果你要评估上线 trade-off，重点读 `8.2A`、`8.26-8.29`、`9.18-9.21`、`15.4-15.6`。

第一次阅读时可以先跳过大段 schema。schema 的作用是把边界写死，不是让人从字段定义开始理解系统。

## 2. 背景与问题定义

在现代移动广告里，存在四个同时成立的现实：

1. 广告主 App 内嵌 ad network SDK，SDK 在设备侧能观察到 impression、click、install、purchase，以及 `boot_time`、原始 `ip`、网络类型、时区、设备 uptime、重装痕迹等敏感或半敏感信号。
2. MMP / AAP 与 Self-Reporting Network（SRN）的主协议仍然是“先检测 install，再向广告网络查询，再由网络 claim，再由 MMP confirm”。
3. 广告网络为了持续优化出价、排序、反作弊和预算分配，仍然需要 request-level 的监督信号，而不仅仅是 aggregate count。
4. 隐私边界必须比传统 click-ID 或 device-ID 时代更强，尤其不能把原始高敏感信号直接沉入普通数仓。

因此，本文讨论的 `on-device measurement` 不是“纯端上闭环”。更准确地说，它是一个三层系统：

- AdNetwork SDK 在设备侧保留原始敏感观察，并在本地生成 private matching material；
- AdNetwork SDK 与 AdNetwork Server 通过 OPRF/PSM-with-payload 完成私密匹配，向 MMP 释放 scoped Claim；
- AdNetwork Server 只在 Confirm 后用 `mmp_touch_token -> req_id` 恢复内部请求上下文，再分层释放到 optimization plane 和 aggregate reporting plane。

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

先把它想成两条线：

- `转化归因线`：MMP 想知道这次 install / purchase 最终应不应该归因给某个 ad network。
- `模型优化线`：Ad Network 想把这次转化回灌到当时那一次广告请求，用来训练出价、排序、创意和反作弊模型。

隐私技术的作用，是让这两条线能闭环，但不要把原始设备信号或内部 `req_id` 直接交给第三方。

完整流程可以拆成十步：

1. 广告请求发生时，ad network backend 生成一次性的 `server_request_id:int64`。
2. ad network backend 同时写入 touchpoint row，并生成 MMP-facing 的 `mmp_touch_token` 或等价 touch-scoped token；内部 `req_id` 不给 MMP。
3. ad network SDK 在设备侧观察 impression、click、install、purchase，以及本地敏感信号。
4. 广告主 App 发生 install / first_open / purchase 后，MMP SDK 捕获事件，并调用 AdNetwork SDK 发起 Ask。
5. AdNetwork SDK 在本地生成 device material / `device_fp_hash`，MMP SDK 不生成、不传递、不保存这些材料。
6. AdNetwork SDK 与 AdNetwork Server 运行 `GET /config -> POST /psm -> local candidate processing -> optional POST /validate` 子状态机。
7. AdNetwork SDK / Server 根据命中 payload 签发或构造 `ClaimResponse`；推荐返回 `mmp_touch_token + claim_token + creative metadata`，不返回 `req_id`。
8. MMP 完成 winner 选择后，再回传 `MmpConfirmRequest`；Confirm 必须带 `claim_token`，token alone 不能完成确认。
9. AdNetwork Server 在 Confirm 后用 `mmp_touch_token -> req_id` 找回内部请求上下文，并物化：
   - `RequestScopedOptimizationLabel`
   - `AggregateMeasurementContribution`
10. downstream 分层消费：
   - optimization plane 消费 request-level label
   - aggregate reporting plane 消费 thresholded / bounded / optional-DP 的聚合输出

一个更贴近 v3.1 legal review 的主链路可以写成：

```text
MMP SDK Ask
  -> AdNetwork SDK 在本地生成 device material / device_fp_hash
  -> AdNetwork SDK 与 AdNetwork Server 运行 EC-OPRF / PSM-with-payload
  -> AdNetwork SDK 返回 Claim 给 MMP SDK
  -> MMP SDK 上报 MMP Server
  -> MMP Server Confirm 给 AdNetwork Server
  -> AdNetwork Server 通过 mmp_touch_token 找回 req_id
  -> attribution / optimization
```

最重要的不变式：

- raw device material、`device_fp_hash`、OPRF input、unblinded OPRF output 不出 AdNetwork SDK crypto boundary。
- MMP 不生成、不传递、不保存 `device_fp_hash`。
- MMP 可以按 legal 选择看到 advertiser-scoped / touch-scoped attribution material，例如 `mmp_touch_token`、`creative_id`、`campaign_id`、`ad_group_id`、`touch_time_bucket`。
- MMP 不应看到 `req_id`、raw device signal、OPRF tail/tag、raw matching key、row decryption key。
- AdNetwork Server 通过 `mmp_touch_token -> req_id` 找回 request-level optimization context，而不是让 MMP 明文回传 `req_id`。

### 4.1 名词小抄

| 名词 | 可以怎么理解 | 不要误解成 |
|---|---|---|
| `device material` | SDK 在本地看到的设备侧信号，例如安装、时间、网络、重装 hint 等 | 可以随便外发的设备 ID |
| `device_fp_hash` | 从设备信号派生出的匹配材料 | 不应让 MMP 可见，也不应由 MMP 传给 Ad Network |
| `OPRF/PSM` | 让 SDK 和服务器协同判断“是否命中某条触点”的私密匹配层 | 只能输出 yes/no 的完整产品协议 |
| `associated payload` | 命中触点后可释放的上下文字节，例如 token、creative、campaign | 原始设备信号 |
| `mmp_touch_token` | 给 MMP 用的 touch-scoped join handle | 跨 app / 跨广告主的 User ID |
| `claim_token` | 一次性的、不可伪造的 on-device match receipt | MMP 能解开的明文字段包 |
| `req_id` | Ad Network 内部请求级优化 key | MMP 或 partner-facing payload |
| `odm_info` | 外部兼容协议里的 opaque bridge object | 长期用户标识符 |

这张表的核心判断是：`mmp_touch_token` 可以让 MMP 做归因协同，`claim_token` 证明端侧匹配发生过，`req_id` 则留在 Ad Network 内部做优化。三者不能混用。

## 5. 设计依据索引

这一节只保留“为什么正文要这么设计”的索引，不展开论文和标准细节。完整依据放在文末附录。

| 正文设计决策 | 为什么需要它 | 详细依据 |
|---|---|---|
| 设备侧保留原始敏感信号，只输出 task-bound claim / compatibility artifact | 原始设备流适合短期、端侧处理，不应永久中心化 | 附录 20.1 |
| request-level join 放在 confidential plane | personalized optimization 需要 request-level label，但 join 过程不能进入普通数仓 | 附录 20.2、20.7 |
| aggregate reporting 对齐 DAP / VDAF / budget ledger | 聚合报告不是普通 SQL 导出，需要 task、batch、collector、anti-replay、budget 状态 | 附录 20.3、20.5、20.10、20.11 |
| label contract 显式包含 contribution / credit / owner 信息 | multi-touch 和多 owner 数据里，贡献上界会影响隐私与训练质量 | 附录 20.4 |
| DP 作为后续 release 加固，而不是 Phase 1 强制前置 | DP 需要预算、审计和交互式 release 分析，不能只在 SQL 末尾加噪声 | 附录 20.5、20.6 |
| TEE/CVM 只是执行边界，不是万能隐私证明 | confidential processing 仍要考虑 side-channel、debug、access pattern 与 workload 测试 | 附录 20.7 |
| 主链路必须兼容 MMP / SRN Ask-Claim-Confirm | 真实商业归因仍然围绕 MMP/SRN 工作流，不应绕开它另造孤岛 | 附录 20.8、20.9 |
| ODM / ODC 建模为 OPRF/PSM candidate retrieval + local filtering | HAR 证据显示真实实现不是单个本地 token，也不是裸 matched bit | 附录 20.13、17A |
| MMP SDK / AdNetwork SDK 集成状态需要本地、可审计的 runtime trace | 2026 年 MMP ICM 文档已经把 ODM SDK、MMP SDK 版本、初始化 timeout、deep link callback delay 写成生产接入条件 | 附录 20.15、11.5A |
| device / SDK debug log 必须在产生点做 PII 最小化，而不是事后清洗 | 2026 年 Proteus 说明移动端日志可以用 keyed pseudonymization + rotating encryption 保留排障关联性，同时避免明文 PII 外流 | 附录 20.15、10.6 |
| touchpoint 质量需要 request-scoped device / supply-path attestation，但不能变成 user join key | OM SDK device attestation 把 Privacy Pass 风格证明带入广告 measurement；它适合反伪造和样本质量治理，不适合替代 attribution token | 附录 20.17、14.6 |
| FHE 作为 hardened profile，而不是默认主链路 | FHE 能隐藏被计算的输入，但不能自动解决输出泄露、重放、MMP confirm 和 request-level optimization join；适合私密候选评分、aggregate 加固和小模型加密推理 | 17E、20.16 |
| attribution label 必须与 incrementality calibration 分开 | 2026-04 修订的 PIE 研究说明 attribution / last-click / exposure rate 等 post-determined aggregate features 可以预测因果增量，但它们本身不是因果真值；优化面应把 claim label、calibration weight、experiment provenance 拆开 | 9.15、12.8、20.18 |
| clean-room / PET matching 可以做后端对账和跨方测量，但不替代 SRN Ask-Claim-Confirm | ADMaP v1.0 已把 DCR 内两方 matching、attribution computation、report generation 标准化；本 RFC 用它加固 settlement / aggregate verification，而不是让 MMP 前台 claim API 暴露更多字段 | 13、17B、20.18 |
| consent / deletion / jurisdiction signal 是协议状态，不是 legal 备注 | GPP 与 DDRF V2 说明隐私选择、删除请求、传播状态、签名和错误码需要机器可读；on-device measurement 必须能把这些信号映射到 artifact、token、feature release 和 retention policy | 8.23、9.15、10、20.18 |
| 多标识符私密匹配必须有 task-scoped policy，而不是先合成一个万能 ID | PrivacyGo 把 multi-identifier ad measurement 建模为 reversed OPRF + blind key rotation + DP-obfuscated intersection size；这支持本 RFC 把 identifier bundle、key epoch、linkage guardrail 写成正式对象 | 8.24、9.16、20.19 |
| 实时报表 DP 不能只写一个 epsilon | Differentially Private Ad Conversion Measurement 要求归因规则、DP 邻接、贡献裁剪 scope 和 enforcement point 一起 operationally valid；AdsBPC 则说明流式广告报表需要 per-user DP、release slot 和非同分布噪声计划 | 8.25、13.2A、20.19 |
| privacy budget 需要 scheduler policy，而不是报表作业参数 | W3C Attribution Level 1 `2026-05-14` 草案继续把 aggregation service、anti-replay 和 privacy budget 放进核心对象；Big Bird 说明 per-querier budget 在自适应查询下不够，生产上要记录 global budget、quota、batch scheduling 和 DoS resilience | 8.18A、9.2C、13.2B、20.26 |
| 端侧敏感信号要有 release policy，而不是靠字段名约定 | 2026 的移动位置 / 传感器 / TCF 研究共同说明，`ip`、boot time、location-like signal、AAID 这类字段的业务价值与隐私风险都强依赖采集点、consent、cold-start 阶段和 release surface；因此需要把 raw TTL、bucketization、MMP 可见性和 trainer 可见性写成协议对象 | 8.2A、9.1B、10、20.27 |
| 敏感信号还需要逐事件 derivation record，而不只是全局 policy | Google Ads ODM 文档明确 event-data 路径会使用从 IP / timestamp 等设备信号派生的临时数据；AAP 文档又要求 consent 先于 conversion/referrer 发送。生产上必须记录每次事件实际用了哪些 policy、输出了哪些派生桶、是否允许 MMP / trainer 可见 | 8.2B、9.1C、10、20.28 |
| 隐私增强方案必须量化 utility / latency / adoption trade-off | 2026-05 PNAS field experiment 和 Privacy-Enhanced Retargeting 实验说明，Privacy Sandbox 类方案的广告效果不是常数，受 adoption、latency、供应侧覆盖和成本分母影响；RFC 需要记录实验设计和业务指标，而不是只记录 privacy profile | 8.26、9.18、15.4、20.27 |
| RFC 合规性需要一个可审计对象，而不是口头声明 | W3C / ICM / AAP 资料共同说明 measurement 已经是多 surface、多 partner、多 policy 的系统；CHI 2026 Android fingerprinting developer study 又说明平台限制需要 enforcement。实现方应声明具体 profile、必选对象、库栈、fallback、禁止字段和上线门禁 | 8.27、9.19、15.5、20.29 |
| launch time / clock evidence 要单独建模，不能把 boot time 当普通特征 | Adjust ODM 文档把 app launch time 的早期捕获写成 attribution 准确性的关键因素；W3C Attribution Level 1 又提醒 timing / shared resource side-channel 会泄露 budget、match 或 conversion value 状态。RFC 需要同时记录准确性证据和 side-channel 缓解 | 8.28、9.20、15.6、20.30 |
| 端到端隐私需要 composition record，而不是拼接局部隐私声明 | PoPETs 2026 private advertising 研究说明广告生态里 targeting、engagement、attribution、reporting 的局部隐私保证不自动组合，且有用广告系统存在不可避免的信息泄露；因此必须把 MMP、AAP、optimization、aggregate release 的残余泄露和上线 gate 写成同一对象 | 8.29、9.21、15.6、20.30 |
| optimization training 的隐私 profile 必须显式区分 known / semi-sensitive / protected label | DP-SGD 在广告 CTR/CVR/conversion count 任务上可行，但广告数据稀疏且类别不平衡；semi-sensitive feature DP 给了比“全量 DP”或“只做 label DP”更贴近生产的折中 | 8.17A、9.17、12.3、20.21 |
| MMP/AAP ICM 集成状态是协议输入，不是客服排障备注 | 2026-05-08 Singular 文档把 Google ICM 的 Android/iOS open beta、click-through-only、Kids apps、ODM timeout、`odm_error`、retention 和 consent mapping 写成正式接入规则 | 8.19、9.4C、11.5A、20.19 |
| Cross-MMP ICM 不能被压成一个 `icm_enabled` 布尔值 | AppsFlyer / Singular / Branch / Airbridge / Kochava / Tenjin / Adjust 对 ICM 的描述共同显示：iOS 是 ODM / `odm_info` path，Android 多为 partner-config / API path；claim 语义是 non-deterministic / probabilistic / modeled，需要独立 waterfall tier | 8.19、11.5B、20.20 |
| Android Privacy Sandbox MeasurementManager 不应成为生产主线依赖 | Google 已宣布退役 Attribution Reporting API（Chrome / Android），Android `MeasurementManager` API 37 deprecated 且无直接替代 API；Android 侧应优先建模为 ICM / App Conversion API / referrer / consent / partner contract | 8.19、9.4C、11.5B、15、20.22 |
| Apple AdAttributionKit 是平台 postback plane，不是 SRN Confirm 替代品 | conversion tag、configurable attribution rules、geography postback 和 winning postback copy 提高了平台报表粒度，但仍不暴露 Ad Network 内部 `req_id`，也不能替代 MMP winner adjudication | 8.19、9.4E、11.9、20.22 |
| 2022 公开的 Google aggregated conversion measurement 专利更接近浏览器 aggregate postback，不是本 RFC 的 SRN 主链路 | US20220086240A1 / US11711436B2 使用 browser conversion engine、URL registration table、batch/proxy/reporting policy；本 RFC 使用 SDK + MMP Ask/Claim/Confirm + OPRF/PSM + request-level optimization label | 11.9、13、20.23 |
| 标题更像 on-device privatization 的 2022 专利并非 Google LLC | US20240143416A1 / US12327150B2 的优先日是 2022-11-01，但 assignee 是 Microsoft Technology Licensing；它使用 on-device DP noisy labels + debiasing + ML training，适合对照 `TrainingPrivacyPolicy`，不能当作 Google ODM 主链路证据 | 8.17A、12.3、20.23 |
| Google 2022 filed 的 privacy + SDK install attribution 专利与本 RFC 最接近，但仍不是 MMP/SRN 完整协议 | US20240095364A1 / WO2023214975A1 使用 attribution SDK / DC SDK、trusted program、sharded secure token、install integrity token 和 attribution credit；它更像 secure install attribution + anti-fraud token chain，不包含 `MMP Ask -> Claim -> Confirm` 与 `server_request_id` 优化标签闭环 | 7.2A、8.19A、11.9、20.24 |
| Google 2022 filed 的 attestation-token 专利支持 touchpoint 真实性建模 | WO2023028293A1 / US20240220654A1 使用 anonymous / attestation tokens 证明 request、display、interaction、install 链路，支持本文把 device / supply-path attestation 作为 request-scoped quality receipt，而不是用户标识 | 7.2A、8.19A、14.6、20.24 |
| 旧版 EC-OPRF candidate rows 提案应融合为实现 profile，而不是替代主 RFC | 旧文档的默认路径与本文一致：EC-OPRF + encrypted candidate rows、Paillier/PIR privacy escalation、FHE research-only；差异是旧文档把 `AdPlatformUserID/click_id` 当默认 MMP-visible handle，本文将其收敛为兼容披露 profile，默认仍是 `mmp_touch_token + claim_token` | 8.6、8.7、17B、17C.8、17D.7、20.25 |

这张表的作用是把“研究/标准/产品资料”转成正文里的实现约束。第一次阅读时可以继续往下读第 6 节；只有在需要追溯依据时再看附录。

## 6. 总体架构

### 6.1 逻辑平面

系统划分为四个数据面。不要把它理解成四套独立系统；更像同一条数据在不同风险级别下的四个停靠站：

- 设备侧负责“看到但不乱发”；
- confidential plane 负责“能验证、能 join、但不外泄明细”；
- optimization plane 负责“把归因变成训练样本”；
- aggregate reporting plane 负责“对外只给聚合结果”。

1. `Device Raw Plane`
   - 位置: advertiser app + ad network SDK
   - 内容: 原始 install / event、本地敏感信号、原始 `boot_time`、原始 `ip`
   - 生命周期: 极短
2. `Confidential Plane`
   - 位置: TEE/CVM 或严格隔离的 confidential service
   - 内容: claim verification、token-to-`req_id` join、敏感特征派生；兼容路径下也可包含 artifact validation
   - 生命周期: 中短期，受 retention policy 控制
3. `Optimization Plane`
   - 位置: 训练样本与线上优化系统
   - 内容: request-scoped label、低敏派生特征、campaign context
   - 禁止内容: 原始 `ip`、原始 `boot_time`、`odm_info`
4. `Aggregate Reporting Plane`
   - 位置: partner-facing / BI-facing aggregate service
   - 内容: bounded, thresholded, optional-DP aggregate outputs

### 6.1A 这不是“local vs central”的二元对立，而是 trust graph 分层

2025 的 [Differential Privacy on Trust Graphs](https://research.google/pubs/differential-privacy-on-trust-graphs/) 给了一个很有用的心智模型：真实系统里，各方通常不是“完全互信”或“完全不信任”，而是只信任一部分邻居。广告主 App、Ad Network SDK、MMP、Ad Network confidential service、aggregate collector 就属于这种结构。

这对本 RFC 的直接意义是：

- `Device Raw Plane` 不是为了把所有价值都困在端上，而是为了把最敏感原料只暴露给最小信任域；
- `Confidential Plane` 不是普通数据仓库前面再加一层 ACL，而是承接“只有少数邻居可见”的 join 和派生；
- `Optimization Plane` 看到的是为训练释放过的低敏派生特征，而不是原始跨方识别材料；
- `Aggregate Reporting Plane` 则进一步收缩成 collector / task / budget 约束下的聚合输出。

换句话说，本文的四平面设计，本质上是在把“谁可以看到什么、看到后可以做什么”写成显式 trust graph，而不是把 `on-device measurement` 误解成“除了端上，谁都不该再看任何东西”。

### 6.2 关键键

- `server_request_id:int64`
  - 服务端生成
  - 一次 ad request 唯一
  - 是 optimization join key
  - 不是 user ID
- `mmp_touch_token:string`
  - 服务端生成
  - MMP-facing、advertiser-scoped、touch-scoped attribution token
  - 用于 MMP click-conversion join 和 Confirm 回传
  - 不是 network-level user ID，不得跨 advertiser / app / MMP / purpose 复用
- `claim_token:bytes`
  - AdNetwork SDK / confidential service 生成或签发
  - opaque、single-use、short-TTL、partner/app/event scoped
  - 用来证明一次 on-device match 已发生
  - token alone 不应允许 MMP 伪造归因
- `artifact_id:bytes`
  - 兼容路径对象
  - 设备侧生成或设备侧签名对象中的唯一标识
  - 只代表一次 measurement artifact
  - 不是长期标识符
- `odm_info:string`
  - 兼容路径对象
  - 端上生成并透传给 MMP/AAP 的 opaque envelope
  - 是 bridge object
  - 不能被二次用途化为 durable identifier

### 6.3 一个可上线的最小 RFC 蓝图

如果 reviewer 只想先抓住“这套协议里到底有哪些对象、谁持有它们、它们如何串起来”，可以先记下面这 7 个对象：

- `AdRequestContext`
  - 由 ad network backend 在广告请求时生成
  - 核心字段建议至少包含 `server_request_id:int64`、`advertiser_id:int64`、`campaign_id:int64`、`ad_group_id:int64`、`creative_id:int64`、`touch_ts_ms:int64`
  - 作用是把一次广告请求固定成后续 optimization 的 request-scoped anchor
- `TouchpointRecord`
  - 由 ad network server 持久化
  - 核心字段建议至少包含 `server_request_id:int64`、`mmp_touch_token:string`、`touch_time_bucket:int32`、`feature_ptr:string`
  - 作用是把对外可见 token 和对内 `req_id`/request context 分开
- `LocalMeasurementObservation`
  - 只存在于 advertiser app 内的 AdNetwork SDK process
  - 可包含 `boot_time_ms:int64`、`raw_ip:string`、`network_type:string`、`install_ts_ms:int64`、`local_sequence_no:int32`
  - 它是原料，不是对外协议对象
- `MmpAskRequest`
  - 由 MMP SDK 触发，但不携带 raw device material
  - 建议最小字段为 `mmp_event_id:string`、`measurement_task_id:string`、`event_type:enum`、`ask_idempotency_key:string`
  - 若走兼容路径，可额外带 `odm_info:string`
- `ClaimResponse`
  - 由 AdNetwork SDK / confidential service 返回
  - 建议最小字段为 `mmp_touch_token:string`、`claim_token:bytes`、`campaign_id:int64`、`ad_group_id:int64`、`creative_id:int64`
  - 不得携带 `req_id`、`device_fp_hash`、OPRF 输入输出、row key
- `MmpConfirmRequest`
  - 由 MMP 对 winner network 回传
  - 建议最小字段为 `mmp_touch_token:string`、`claim_token:bytes`、`final_decision:enum`、`confirm_idempotency_key:string`
  - 作用是把 “candidate claim” 变成 “可物化 label 的最终归因结论”
- `RequestScopedOptimizationLabel` 与 `AggregateMeasurementContribution`
  - 两者都由 AdNetwork server 在 Confirm 后物化
  - 前者面向 request-level 训练与在线优化，后者面向 bounded aggregate release
  - 两者必须是两个对象，不能让 optimization 和 aggregate 共用同一份原始事件明细

把这 7 个对象串起来，最小可上线链路就是：

```text
一次 ad request
  -> 生成一个 server_request_id:int64
  -> 写入一个 TouchpointRecord
一次 install / first_open
  -> 生成一个 mmp_event_id:string
  -> 对多家 network 发 Ask
每家 network
  -> 本地完成 OPRF/PSM 子流程
  -> 返回一个 ClaimResponse
MMP 选 winner
  -> 只对 winner 发 Confirm
winner network
  -> 用 mmp_touch_token / claim_token 找回 server_request_id
  -> 物化 OptimizationLabel 与 AggregateContribution
```

理解这个蓝图时要刻意区分三种“像 ID 但不是一回事”的字段：

- `server_request_id:int64` 是 ad request 级别的内部优化锚点
- `mmp_event_id:string` 是 MMP 视角的一次 install / event 闭环对象
- `odm_info:string` 是兼容路径里的 opaque bridge object

这三者如果被实现混成一个“万能 token”，整个 RFC 的隐私边界和调试边界都会一起失效。

## 7. 端到端数据流

本节以 v3.1 legal review 的主链路为准。核心变化是：MMP 不再被建模为“带着 device_fp_hash / odm_info 去问 Ad Network 的一方”；MMP SDK 只是触发 Ask，真正的 device material 采集、hash、blind、OPRF/PSM 查询都发生在 AdNetwork SDK 内。

主链路：

```text
MMP SDK Ask
  -> AdNetwork SDK 本地生成 device material / device_fp_hash
  -> AdNetwork SDK 与 AdNetwork Server 运行 EC-OPRF / PSM-with-payload
  -> AdNetwork SDK 返回 Claim 给 MMP SDK
  -> MMP SDK 上报 MMP Server
  -> MMP Server Confirm 给 AdNetwork Server
  -> AdNetwork Server 通过 mmp_touch_token 找回 req_id
  -> attribution / optimization
```

`OnDeviceMeasurementArtifact`、`ODMInfoEnvelope`、`odm_info` 仍可作为兼容对象存在，尤其用于 Google ICM / AAP 类外部接口；但它们不是本文推荐主链路的起点。推荐主链路的起点是 `MMP SDK -> AdNetwork SDK Ask`。

### 7.1 Step A: Touchpoint Ingestion

用户在 AdNetwork App / publisher surface 中发生 impression 或 click。AdNetwork Server 写入 touchpoint row：

- `req_id` / `server_request_id`
- `user_id`，仅 AdNetwork 内部使用
- `adv_app_id`
- `advertiser_id`
- `campaign_id`
- `ad_group_id`
- `creative_id`
- `touch_ts_ms`
- `touch_time_bucket`
- `feature_ptr`

同时生成 MMP-facing touch token：

```text
mmp_touch_token = HMAC_Kmmp(
  mmp_partner_id
  || advertiser_id
  || adv_app_id
  || req_id
  || creative_id
  || touch_time_bucket
)
```

这个 token 可以通过 tracking link / click log 给到 MMP，用于后续 click-conversion join。`req_id` 不给 MMP；AdNetwork Server 维护内部索引：

```text
mmp_touch_token -> req_id, creative_id, campaign_id, ad_group_id, feature_ptr, expiry_ts
```

### 7.2 Step B: Candidate Store Build

AdNetwork Server 离线或准实时构建 OPRF/PSM candidate store。

对每条 touchpoint：

1. 从 AdNetwork 可用的 identity material 派生 normalized input。
2. 计算 digest 和 prefix bucket。
3. 用 OPRF server key 生成 row key material。
4. 把可披露的 reporting payload 加密进 candidate row。

Reporting payload 可以包含：

- `mmp_touch_token`
- `creative_id`
- `campaign_id`
- `ad_group_id`
- `touch_time_bucket`

不应包含：

- `req_id` 明文
- raw device signal
- row key
- OPRF input / output

### 7.2A Optional Touchpoint Device / Supply-Path Attestation

如果 touchpoint 来自移动媒体 App、CTV App 或可集成 OM SDK 的广告渲染环境，AdNetwork 可以在 touchpoint ingestion 附近额外记录一次 request-scoped attestation receipt：

```text
ad render / OM SDK session
  -> Privacy Pass-style token challenge / redemption
  -> verifier returns attestation result
  -> AdNetwork stores receipt against server_request_id
```

这条支路解决的是“这个 impression / click 是否来自可信设备和 supply path”，不是“这个用户是谁”。因此它有三条硬边界：

- `DeviceSupplyPathAttestationReceipt` 可以绑定 `server_request_id`，用于反作弊、样本质量、pacing 风控和训练样本降权。
- 原始 Privacy Pass token、platform attestation blob、device ID、seller SDK 私有字段不进入 MMP / SRN payload，也不进入 trainer row。
- MMP 最多看到 coarse claim path / quality reason，例如 `LOW_CONFIDENCE_TOUCHPOINT`，不应看到可链接的 attestation token 或 verifier challenge。

这条支路对 optimization 很重要：没有它，伪造设备产生的大量低质量触点会和真实“未转化触点”混在一起，模型会把 fraud / inventory quality 问题错学成用户兴趣问题。

### 7.3 Step C: Conversion Event and MMP SDK Ask

广告主 App 内发生 install / first_open / purchase。MMP SDK 捕获事件，然后调用 AdNetwork SDK：

```text
Ask(event_name, event_ts_ms, adv_app_id, mmp_context)
```

Ask 阶段的关键边界：

- MMP SDK 不传 `device_fp_hash`。
- MMP SDK 不传 raw device material。
- MMP SDK 可以传事件上下文，例如 event name、event time、app id、MMP event id。
- AdNetwork SDK 负责在本地采集 / normalize / hash device material。

### 7.3A iOS optional AdNetwork SDK and Ask eligibility

iOS 上要额外处理一个现实：MMP SDK 通常是广告主 App 必装，但每个 ad network SDK 是选装。协议不能假设所有 ad network SDK 都存在，也不应该为了 ODM 迫使开发者集成所有 network SDK。

推荐模型是 `MMP SDK -> local capability registry -> optional network adapter -> AdNetwork SDK`：

```text
App starts
  -> MMP SDK initializes AdapterRegistry
  -> linked AdNetwork adapter registers capability if present
  -> MMP SDK caches per-network AskEligibility
  -> conversion event arrives
  -> MMP SDK calls Ask only for eligible local adapters
```

iOS 侧落地建议：

- MMP SDK 暴露稳定的 `MmpMeasurementAdapter` protocol 和 `AdapterRegistry`。
- ad network 提供一个很薄的 optional adapter package，内部再调用自己的完整 SDK。
- 如果 app 没有链接该 adapter / SDK，registry 里没有该 network，MMP SDK 直接记录 `ASK_SKIPPED_SDK_NOT_PRESENT`。
- 如果 adapter 存在但版本、地区、consent、功能开关不满足，则记录明确 skip reason，不发 Ask。
- remote config 只能决定“是否允许某 network 参与”，不能替代本地 `sdk_present=true` 判断。

这样开发者体验是可控的：装了哪个 network SDK，就自动获得哪个 network 的 ODM Ask 能力；没装的 network 不报错、不超时、不要求开发者写额外 glue code。

### 7.4 Step D: AdNetwork SDK Local Material and Config

AdNetwork SDK 在本地生成 measurement material：

- device / install / app context
- time bucket context
- source / app / measurement task context
- policy-controlled local signals

然后向 AdNetwork Server 拉取 config：

```text
GET /odm/config
```

config 可以包含：

- `prefix_length`
- `bucketed_date`
- `extension_data / odmed`
- `matching_id` 或 opaque context
- crypto / protocol mode

`matching_id`、`odmed` 这类字段是协议上下文，不是 attribution result，也不应被当成 durable user identifier。

### 7.5 Step E: OPRF / PSM-with-payload

AdNetwork SDK 本地计算 prefix bucket 和 blinded EC point，然后请求 candidate rows：

```text
POST /odm/psm { odmed, psm_request }
```

Server 返回：

- OPRF / VOPRF-style response header
- prefix bucket 下的 candidate rows
- 每行的 quick tag / encrypted package / row meta

SDK 本地完成：

1. unblind server evaluation；
2. derive row key；
3. scan candidate rows；
4. 用 quick tag 做快速过滤；
5. 对可能命中的 row 做 decrypt / verify；
6. 恢复命中 row 的 associated payload。

这一步的输出不是裸 `matched bit`，而是：

```text
matched + associated payload + proof context
```

### 7.6 Step F: Optional Validate / Claim Issuance

如果协议需要 validate，AdNetwork SDK 提交 opaque validation material：

```text
POST /odm/validate { mvs, odmed }
```

Validate 可以返回 channel-specific measurement values，或参与 claim issuance。最终 AdNetwork SDK 返回给 MMP SDK 的 Claim 推荐为：

```json
{
  "matched": true,
  "mmp_touch_token": "AMT_v1_7ec3...",
  "creative_id": 74019912,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "touch_time_bucket": 4933923,
  "match_type": "on_device_psm",
  "claim_token": "opaque_claim_token_v1",
  "expires_at_ms": 1777518000000
}
```

Claim 不应包含：

- `req_id`
- `device_fp_hash`
- raw matching id
- OPRF tail / output
- row key
- bucket tail / tag

### 7.7 Step G: MMP Server Attribution and Confirm

MMP SDK 把 conversion + Claim 上报给 MMP Server。MMP Server 执行自己的多渠道 winner selection。

如果 MMP 最终决定归因给该 AdNetwork，则 Confirm：

```json
{
  "partner": "ExampleMMP",
  "adv_app_id": "com.example.game",
  "event_name": "first_open",
  "event_ts_ms": 1777500905123,
  "final_decision": "WIN",
  "mmp_touch_token": "AMT_v1_7ec3...",
  "claim_token": "opaque_claim_token_v1",
  "confirm_idempotency_key": "confirm_01JTRP7V8W5T7A8Y4A8V2P"
}
```

Confirm 阶段必须校验：

- `claim_token` valid / not expired / not replayed
- `claim_token` 与 `mmp_touch_token` 绑定一致
- partner / app / event / policy context 一致
- token 仍在 attribution window 内

### 7.8 Step H: Token to req_id and Optimization Release

AdNetwork Server 在 Confirm 后做内部 join：

```text
mmp_touch_token -> req_id -> feature_ptr -> attribution / optimization label
```

输出两个方向：

- request-level optimization label，用于训练和模型反馈；
- aggregate reporting contribution，用于 partner-facing / BI-facing 聚合报告。

这里的关键边界是：

- MMP 只看到 scoped attribution material 和 claim receipt。
- `req_id` 只在 AdNetwork Server 内部恢复。
- optimization plane 消费 request-level label，但不消费 raw device material、`device_fp_hash` 或 `odm_info`。
- aggregate reporting plane 继续执行 threshold、budget、DP 或 DAP/VDAF 对齐策略。

### 7.9 兼容对象的位置

`OnDeviceMeasurementArtifact`、`ODMInfoEnvelope`、`odm_info` 的合理位置是兼容层和桥接层：

- 用于 Google ICM / AAP 类外部 API；
- 用于 advertiser app / advertiser server 缓存 opaque bridge object；
- 用于排查和跨系统 correlation，但必须 TTL-bound、purpose-bound；
- 不作为主链路里 MMP 提供 device matching material 的方式。

因此，后文 schema 仍保留这些对象，但语义应理解为 compatibility / bridge object，而不是 v3.1 主流程的核心输入。

## 8. 协议对象与 schema

以下 schema 是 RFC 的逻辑规范，生产实现建议使用 `Protobuf + buf` 管理。

读这一节时不用从字段细节开始。它的作用有三个：

1. 把“谁能看到什么”写成字段边界；
2. 把 TTL、replay、policy version 这类治理要求变成正式 contract；
3. 让 SDK、MMP、confidential service、训练系统对同一批对象有共同语言。

如果只是理解架构，可以先跳到第 9 节看 mock payload，再回来查 schema。

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

### 8.2A DeviceSensitiveSignalPolicy

这个对象定义“端上看到了敏感信号之后，允许怎么派生、保存和释放”。它不描述单个用户事件，而是描述 policy。没有这个对象，`boot_time`、`ip`、近似地理位置、install referrer、AAID/IDFA 兼容字段很容易在 SDK、MMP、debug log、trainer 之间被顺手透传。

```proto
message DeviceSensitiveSignalPolicy {
  string policy_id = 1;
  string measurement_task_id = 2;
  repeated string raw_signal_names = 3; // boot_time_ms, raw_ip, ip_prefix, aa_id, location_like_signal
  string collection_point = 4; // adnetwork_sdk, mmp_sdk, advertiser_app, platform_postback
  string allowed_raw_surface = 5; // device_process_only, confidential_plane_short_ttl, partner_egress_only
  int64 raw_ttl_seconds = 6;
  string derivation_mode = 7; // bucketize_clip_hmac, coarse_geo_only, risk_bucket_only, none
  repeated string released_feature_names = 8;
  string release_scope = 9; // fraud_quality_only, optimization_only, aggregate_only, partner_compat_only
  string cold_start_gate = 10; // first_n_events, no_behavior_history, disabled
  int32 max_precision_level = 11; // e.g. max geo cell precision or custom enum value
  bool allow_mmp_visibility = 12;
  bool allow_trainer_raw_visibility = 13;
  string consent_dependency_id = 14;
  string retention_policy_id = 15;
  string legal_basis_policy_id = 16;
}
```

关键约束：

- `allow_trainer_raw_visibility` 默认必须是 `false`；若设为 `true`，需要单独的 legal / privacy exception review，不能在普通 RFC profile 中启用。
- `raw_ip` 这类字段如果进入 `partner_egress_only`，必须绑定具体 API contract、TTL 和 consent state；它不因此自动成为 Ad Network trainer 可用特征。
- `cold_start_gate` 用来表达“只在冷启动阶段释放粗粒度派生特征”的 trade-off。行为历史足够丰富后，location-like signal 应降级或关闭，而不是永久保留。
- `max_precision_level` 必须和 `released_feature_names` 一起审计；例如只释放 `country_code` / `region_bucket` 与释放精细 geo cell 是两个完全不同的隐私口径。

### 8.2B DeviceSensitiveSignalDerivationRecord

`DeviceSensitiveSignalPolicy` 是“允许怎么做”；`DeviceSensitiveSignalDerivationRecord` 是“这一次事件实际做了什么”。广告媒体 SDK 在广告主 App 上看到 `boot_time_ms`、`raw_ip`、network churn 或 install referrer hint 时，不能只靠代码路径自证合规。它需要产出一条逐事件 record，把 raw signal 留在哪里、派生出了哪些桶、这些桶能否进入优化训练、MMP 能看到什么，都写成可审计数据。

```proto
message DeviceSensitiveSignalDerivationRecord {
  string derivation_record_id = 1;
  string measurement_task_id = 2;
  int64 server_request_id = 3; // internal only; never MMP-visible
  string mmp_event_id = 4;
  string app_bundle = 5;
  string platform = 6; // ios, android
  string sensitive_signal_policy_id = 7;
  int64 collection_ts_ms = 8;
  int64 derivation_ts_ms = 9;
  repeated string observed_raw_signal_names = 10; // names only, not values
  string raw_surface = 11; // device_process_only, confidential_plane_short_ttl
  int64 raw_delete_after_ts_ms = 12;
  map<string, string> derived_feature_buckets = 13;
  string derived_release_surface = 14; // optimization_feature_store, fraud_quality_store, aggregate_only
  string consent_snapshot_id = 15;
  string legal_basis_state = 16; // consented, limited_ads, legitimate_interest, unavailable
  string jurisdiction_scope = 17; // US-CA, EEA, UK, CH, ROW
  string cold_start_state = 18; // first_open, first_n_events, warmed, disabled
  bool mmp_visible = 19;
  bool trainer_raw_visible = 20;
  string feature_policy_id = 21;
  string retention_policy_id = 22;
  string debug_log_policy_id = 23;
  string optimization_join_key_mode = 24; // server_request_id_internal, mmp_touch_token_confirmed, aggregate_only
  string derivation_code_version = 25;
  bytes replay_nonce_digest = 26;
  bytes sdk_signature = 27;
}
```

关键约束：

- `observed_raw_signal_names` 只记录字段名，不记录 raw value；`raw_ip=203.0.113.42`、`boot_time_ms=...` 这类值不得进入 record。
- `server_request_id` 只允许留在 Ad Network 内部或 confidential plane。MMP 侧最多看到 `mmp_event_id`、`mmp_touch_token`、creative / campaign 元数据和 opaque `claim_token`。
- `derived_feature_buckets` 可以进入 request-level optimization，但必须是短期、任务绑定、可解释的桶，例如 `boot_time_freshness_bucket=lt_2h`、`ip_churn_bucket=stable_24h`。
- `mmp_visible=false` 与 `trainer_raw_visible=false` 是默认值；如果某个 partner compatibility path 放松，必须同时引用 `consent_snapshot_id`、`legal_basis_state`、`retention_policy_id` 和 exception review。
- 当 `legal_basis_state=unavailable` 或 region policy 不允许时，`optimization_join_key_mode` 应降级为 `aggregate_only` 或跳过派生，不应用服务端 fallback 去重建 raw fingerprint。

### 8.3 Compatibility OnDeviceMeasurementArtifact

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

### 8.4 Compatibility ODMInfoEnvelope

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

这个对象用于描述 MMP / AAP 兼容 API 中的 server-side Ask 记录，不是 v3.1 主链路中 `MMP SDK -> AdNetwork SDK` 的原始调用参数。

v3.1 主链路里，MMP SDK 对 AdNetwork SDK 的 Ask 应尽量薄：

```text
Ask(event_name, event_ts_ms, adv_app_id, mmp_event_id, partner_context)
```

它不应携带 `device_fp_hash`、raw device material、OPRF input/output 或 row key。下面的 `device_id` / `odm_info` 字段只用于兼容已有 MMP / AAP / ICM 接口，不能被理解成推荐主流程的匹配输入。

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

- `device_id` 可是 `idfa`、`idfv`、`gaid`、`appsetid`，也可能为空或全零；它只属于 partner compatibility surface。
- `odm_info` 用于兼容 Google ICM / AAP 类 bridge object，不是 v3.1 主链路中由 MMP 提供的 matching material。
- v3.1 主链路的 private matching material 由 AdNetwork SDK 在本地生成，并通过 OPRF/PSM 子流程处理。

### 8.5A LocalAskEligibilityRecord

这个对象描述 MMP SDK 在本地决定“是否应该调用某个 ad network Ask”的结果。它主要是 iOS 端上对象，也可以作为低敏集成健康诊断批量上报给 MMP server。它不是归因结果，也不能被训练面消费。

```proto
message LocalAskEligibilityRecord {
  string mmp_name = 1;
  string mmp_event_id = 2;
  string network_id = 3;
  string app_bundle = 4;
  string platform = 5; // ios
  bool sdk_present = 6;
  string sdk_version = 7;
  bool adapter_present = 8;
  string adapter_version = 9;
  bool supports_odm_ask = 10;
  string ask_eligibility_status = 11; // ELIGIBLE, SDK_NOT_PRESENT, ADAPTER_NOT_PRESENT, VERSION_UNSUPPORTED, REGION_INELIGIBLE, CONSENT_DISABLED, REMOTE_CONFIG_DISABLED
  string skip_reason_code = 12;
  int64 evaluated_ts_ms = 13;
  int64 capability_cache_expiry_ts_ms = 14;
  string discovery_method = 15; // REGISTRY, INFO_PLIST_MANIFEST, NSCLASS_FROM_STRING, REMOTE_CONFIG_ONLY
  string registry_policy_id = 16;
}
```

关键约束：

- `REMOTE_CONFIG_ONLY` 不得产生 `ELIGIBLE`，最多只能产生 `REMOTE_CONFIG_DISABLED` 或等待本地 adapter discovery。
- `NSCLASS_FROM_STRING` 只能作为兼容兜底，优先级低于显式 adapter registry。
- `sdk_present=false` 时不得向 ad network server 发起 Ask，也不得把缺失解释成 attribution negative。
- `LocalAskEligibilityRecord` 可用于集成排障，但不得进入 `OptimizationTrainingRow`。

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
  string mmp_touch_token = 12;
  int64 creative_id = 13;
  int64 campaign_id = 14;
  int64 ad_group_id = 15;
  int64 touch_time_bucket = 16;
  string match_type = 17; // on_device_psm, opaque_claim_only, aggregate_only
  string ad_platform_user_id = 18; // optional compatibility profile; MMP-visible only if contractually pre-existing and scoped
  string opaque_click_id = 19; // optional gbraid-like encrypted/pointer handle; MMP opaque, AdNetwork decrypts/verifies
  string mmp_visible_handle_mode = 20; // tracking_link_touch_token, apuid_click_id, claim_token_only
}
```

字段边界：

- `mmp_touch_token` `MUST` 是 advertiser-scoped / touch-scoped，不得从 raw `user_id` 单独派生。
- `claim_token` `MUST` 是 opaque、short-TTL、anti-replay、partner/app/event scoped。
- `creative_id` / `campaign_id` / `ad_group_id` 是 reporting metadata；是否返回由 partner contract 和 legal option 决定。
- `ad_platform_user_id` 和 `opaque_click_id` 只适用于兼容 profile：MMP 已通过 tracking link 或既有 partner contract 合法接收同类 handle 时才可启用。
- `opaque_click_id` 可以承载或指向 `req_id`，但必须对 MMP 不可解密、不可解释、不可跨 advertiser / app / MMP 复用。
- `req_id`、`device_fp_hash`、OPRF output、bucket tail/tag、row key `MUST NOT` 出现在 `ClaimResponse`。

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
  string mmp_touch_token = 10;
  string partner = 11;
  string adv_app_id = 12;
  string event_name = 13;
  int64 event_ts_ms = 14;
  string ad_platform_user_id = 15; // optional compatibility profile, if present in ClaimResponse
  string opaque_click_id = 16; // optional compatibility profile, if present in ClaimResponse
  string mmp_visible_handle_mode = 17;
}
```

Confirm 处理约束：

- `claim_token` `MUST` 校验签名/解密、expiry、nonce、partner、app、event 和 replay state。
- 如果携带 `mmp_touch_token`，服务端 `MUST` 校验它与 `claim_token` 中绑定的 touch context 一致。
- 如果携带 `ad_platform_user_id` / `opaque_click_id`，服务端 `MUST` 校验它们与 `claim_token` 中的 partner、app、event、touch context 和 key epoch 一致。
- `mmp_touch_token` 只能解析到 AdNetwork 内部的 `req_id` / feature pointer，不得向 MMP 返回 `req_id`。
- token alone 不能完成 Confirm；必须有 valid `claim_token`。

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

这个对象代表 advertiser app 在 install 之后继续上报给 ad network / MMP 的 conversion 事件。它不是原始设备信号，也不是最终训练标签。v3.1 主链路中，Ask 由 MMP SDK 调 AdNetwork SDK 触发；这里的 compatibility fields 只服务已有 partner API。

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
  string compatibility_odm_info = 10;
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
  int64 server_request_id = 3; // populated after Confirm/token-to-req_id join
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
  string mmp_touch_token = 15;
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
  string device_authenticity_bucket = 13; // attested, weak_attestation, missing, failed
  string supply_path_quality_bucket = 14; // verified_seller, known_app, unknown_app, spoof_risk
  string device_attestation_policy_id = 15;
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
  int32 eligible_click_count = 14;
  int32 eligible_impression_count = 15;
  string srn_partner_id = 16;
  string claim_path = 17; // ODM_EVENT_DATA, FIRST_PARTY_DATA, DEVICE_ID, PROBABILISTIC
  int32 total_candidate_count = 18;
  string winner_engagement_type = 19; // CLICK, IMPRESSION, ENGAGED_CLICK, ENGAGED_VIEW
  string raw_candidate_metric_source = 20; // MMP_TOTAL_CANDIDATES, NETWORK_INTERNAL, MIXED
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
  string currency_code = 14;
  string srn_partner_id = 15;
  string feedback_revision_id = 16;
  int64 observation_window_sec = 17;
  string value_source = 18; // EVENT_VALUE, MODELED_VALUE, CURRENCY_BUCKET
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
  string decision_id = 20;
  string srn_partner_id = 21;
  int64 feedback_snapshot_ts_ms = 22;
  string training_privacy_policy_id = 23;
  string feature_sensitivity_manifest_id = 24;
}
```

### 8.17A TrainingPrivacyPolicy

这个对象定义“训练系统到底在保护什么”。它不是给 MMP 的字段，也不是用来阻止 request-level optimization 的；它的作用是避免训练面把 `raw_ip`、`boot_time` 派生物、归因 label、广告上下文全部混成一类数据，然后只用一句“我们会做 DP”带过。

```proto
message TrainingPrivacyPolicy {
  string training_privacy_policy_id = 1;
  string training_task_id = 2;
  string trainer_policy_id = 3;
  string model_family = 4; // LIGHTGBM, XGBOOST, WIDE_AND_DEEP, DLRM
  string privacy_profile = 5; // NO_DP_BASELINE, LABEL_DP, SEMI_SENSITIVE_DP, FULL_USER_LEVEL_DP
  string privacy_unit = 6; // request, app_instance, advertiser_user, account
  string adjacency_relation = 7; // add_remove_user, replace_label, replace_sensitive_feature_bundle
  repeated string known_feature_names = 8;
  repeated string semi_sensitive_feature_names = 9;
  repeated string protected_label_names = 10;
  repeated string prohibited_raw_feature_names = 11;
  string feature_sensitivity_manifest_id = 12;
  string dp_accountant_id = 13;
  double epsilon = 14;
  double delta = 15;
  double noise_multiplier = 16;
  double clipping_norm = 17;
  string clipping_policy_id = 18;
  string sampling_policy_id = 19;
  string privacy_audit_profile_id = 20;
  string empirical_privacy_eval_id = 21;
  string library_profile = 22; // lightgbm_xgboost_baseline, tensorflow_privacy, jax_privacy, opendp
  string release_gate = 23; // offline_only, shadow, online_eligible
  string dp_sampling_method = 24; // poisson, shuffle, balls_and_bins, full_batch, not_applicable
  string dp_accounting_method = 25; // rdp_poisson, shuffle_accounting, custom_audited, not_applicable
  string empirical_privacy_audit_schedule = 26; // none, per_release, quarterly, model_family_gate
  string empirical_privacy_risk_profile = 27; // unknown, low, medium, high
}
```

约束：

- `privacy_profile=NO_DP_BASELINE` 允许存在，但只能表示内部受控优化 baseline，不能对外宣称 DP。
- `LABEL_DP` 只保护 label 时，`known_feature_names` 必须穷尽所有进入训练的特征；否则就是把未知敏感特征误当公开特征。
- `SEMI_SENSITIVE_DP` 是推荐的 Phase 2 profile：campaign、creative、placement 这类上下文通常可视为 known；`ip_churn_bucket`、`boot_time_freshness_bucket`、`reinstall_hint_bucket` 和 label 则进入 protected side。
- `FULL_USER_LEVEL_DP` 必须显式声明 `privacy_unit` 和 `adjacency_relation`，不能只记录 `epsilon/delta`。
- `prohibited_raw_feature_names` 至少应包含 `raw_ip`、`boot_time_ms`、完整 `user_agent`、`device_fp_hash`、`odm_info`、`claim_token`。
- 如果 `privacy_profile` 不是 `NO_DP_BASELINE`，`dp_sampling_method` 与 `dp_accounting_method` 必须同时记录；不能用 Poisson accountant 去包装实际 shuffle sampler。
- `empirical_privacy_audit_schedule` 用于记录黑盒或白盒 privacy audit 的节奏；DP 训练发布不应只依赖一次性 notebook 证明。

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

### 8.18A AggregateBudgetSchedulerPolicy

`AggregateCollectorBudgetState` 描述一次 collect 花了多少预算；`AggregateBudgetSchedulerPolicy` 描述预算系统为什么允许它花。这个对象吸收 W3C Attribution Level 1 与 Big Bird 的共同启发：per-collector quota 适合产品隔离，但如果对外声称 formal DP guarantee，就还要说明 global budget、device/user epoch、batch scheduling 和 DoS resilience。

```proto
message AggregateBudgetSchedulerPolicy {
  string policy_id = 1;
  string measurement_task_id = 2;
  string privacy_unit = 3; // browser_instance_epoch, advertiser_user_epoch, app_instance_epoch, device_scoped_epoch
  string formal_budget_model = 4; // per_collector_quota_only, global_device_epoch_idp, hybrid_per_collector_plus_global
  string per_collector_scope_id = 5;
  int64 per_collector_quota_micros = 6;
  string global_budget_scope_id = 7;
  int64 global_budget_micros = 8;
  int64 global_budget_slack_micros = 9;
  string scheduler_type = 10; // fifo, weighted_fair_queue, batched_quota_scheduler
  int32 batch_window_seconds = 11;
  int32 min_batch_size = 12;
  int32 max_batch_delay_seconds = 13;
  string dos_resilience_policy_id = 14;
  bool adaptive_querier_throttling = 15;
  string correction_release_policy_id = 16;
  string audit_log_sink = 17;
  string formal_guarantee_note = 18;
}
```

关键约束：

- `formal_budget_model=per_collector_quota_only` 可以作为 Phase 1 工程限额，但不能宣传成 global user-level / device-epoch DP。
- `global_budget_micros` 与 `global_budget_slack_micros` 要分开记录；slack 是为了正常负载和 DoS resilience，不应被报表团队当成额外可卖库存。
- `scheduler_type` 与 `batch_window_seconds` 会改变报表时效和隐私语义；它们必须进入审计日志，不能只保存在 Airflow / Spark 参数里。
- `correction_release_policy_id` 必须声明 correction release 是否重复扣预算；不能把修正报表包装成“同一次 release 的补发”来绕过 ledger。

### 8.19 SdkMeasurementRuntimeTrace

这个对象描述 MMP SDK、AdNetwork adapter、ODM SDK 在广告主 App 内的运行态。它不是归因结果，也不是训练特征；它的作用是让 `Ask` 为什么发出、为什么跳过、为什么超时可以被复盘。

```proto
message SdkMeasurementRuntimeTrace {
  string trace_id = 1;
  string mmp_name = 2;
  string mmp_event_id = 3;
  string platform = 4; // ios, android
  string app_bundle = 5;
  string network_id = 6;
  string sdk_family = 7; // singular, appsflyer, adjust, custom_mmp
  string mmp_sdk_version = 8;
  bool adnetwork_adapter_present = 9;
  string adnetwork_adapter_version = 10;
  string adapter_manifest_hash = 11;
  bool odm_sdk_present = 12;
  string odm_sdk_version = 13;
  bool odm_info_present = 14;
  int32 odm_fetch_timeout_ms = 15;
  int32 sdk_init_delay_ms = 16;
  bool deep_link_callback_deferred = 17;
  string event_source_system = 18; // firebase_sdk, mmp_sdk, s2s_api, measurement_protocol, unknown
  bool is_firebase_native_event = 19;
  string region_eligibility_code = 20; // ELIGIBLE, EEA_INACTIVE, UK_INACTIVE, CH_INACTIVE, UNKNOWN
  string att_authorization_status = 21;
  string ads_personalization_status = 22;
  string local_runtime_policy_id = 23;
  string trace_release_scope = 24; // integration_health_only, confidential_debug_only
  string icm_platform_rollout_state = 25; // open_beta_all_advertisers, allowlisted, unsupported, unknown
  string icm_reporting_scope = 26; // click_through_install_only, install_and_reengagement, unknown
  string odm_error_code = 27;
  string kids_app_policy_state = 28; // supported, unsupported, not_applicable, unknown
  string user_level_retention_policy_id = 29;
  string partner_consent_mapping_policy_id = 30;
  bool advanced_data_sharing_enabled = 31;
  bool android_sdk_update_required = 32;
  bool ios_odm_sdk_required = 33;
  repeated string icm_supported_engagement_types = 34; // click, engaged_view, reattribution, reengagement
  string icm_claim_semantics = 35; // google_non_deterministic_claim, modeled_tier, probabilistic_tier
  bool gclid_capture_enabled = 36;
  bool install_referrer_gclid_capture_enabled = 37;
  bool gbraid_capture_enabled = 38;
  string platform_measurement_api_family = 39; // google_icm_ios_odm, google_icm_android_partner_api, apple_adattributionkit, w3c_attribution_level1, android_privacy_sandbox_measurement_deprecated
  string android_privacy_sandbox_measurement_state = 40; // not_used, deprecated_api37, soft_removal_expected, unsupported
  bool apple_adattributionkit_postback_copy_enabled = 41;
  bool apple_adattributionkit_conversion_tag_present = 42;
  string apple_adattributionkit_attribution_rule_profile_id = 43;
  string apple_adattributionkit_geo_scope = 44; // country_region_postback, unavailable, unknown
  string w3c_attribution_draft_date = 45; // latest checked: 2026-05-14
  string aggregate_api_dependency_state = 46; // active_standard_track, platform_deprecated, partner_managed
}
```

关键约束：

- `SdkMeasurementRuntimeTrace` `MUST NOT` 携带 raw `ip`、raw `boot_time_ms`、`device_fp_hash`、OPRF input / output、row key、`claim_token` 或 `server_request_id`。
- `event_source_system=s2s_api` 或 `measurement_protocol` 时，Google-compatible ODM event-data path 默认 `MUST` 标记为 ineligible，除非特定 partner contract 明确允许。
- `sdk_init_delay_ms` 与 `deep_link_callback_deferred` 只用于集成健康和用户体验评估，不得进入 bidder / ranking / pacing 训练。
- `adapter_manifest_hash` 是本地集成证据，不等于 remote config。remote config 不能单独证明某个 network SDK 在设备上可调用。
- `advanced_data_sharing_enabled`、`gclid_capture_enabled`、`install_referrer_gclid_capture_enabled` 和 `gbraid_capture_enabled` 是 ICM 可用性输入，不是归因真值；它们只能解释为什么 Google non-deterministic claim 可能出现或缺失。
- `platform_measurement_api_family` 和 `aggregate_api_dependency_state` 只描述平台兼容面，不改变 SRN `ClaimResponse` / `MmpConfirmRequest` 的主链路。
- `android_privacy_sandbox_measurement_state=deprecated_api37` 或 `soft_removal_expected` 时，系统 `MUST NOT` 把 Android Privacy Sandbox MeasurementManager 作为生产 attribution dependency；只能作为历史兼容或测试维度保留。
- Apple AdAttributionKit 字段只用于 platform postback reconciliation、integration health 和 aggregate reporting explanation，不得直接进入 request-level bidder / ranking / pacing 训练。

### 8.19A DeviceSupplyPathAttestationReceipt

这个对象描述广告渲染侧或媒体 SDK 侧对 touchpoint 的设备真实性 / supply-path 证明。它是 request-scoped quality evidence，不是 attribution token，也不是用户标识。

```proto
message DeviceSupplyPathAttestationReceipt {
  string attestation_receipt_id = 1;
  int64 server_request_id = 2;
  int64 publisher_app_numeric_id = 3;
  string publisher_app_bundle = 4;
  string om_sdk_version = 5;
  string attestation_protocol = 6; // privacy_pass_private_token, platform_attestation, vendor_receipt
  string attester_id = 7; // apple, amazon_fire_tv, platform_vendor, unknown
  string issuer_id = 8;
  string verifier_id = 9;
  string token_challenge_digest = 10;
  string token_redemption_digest = 11;
  string attestation_result = 12; // VERIFIED, MISSING, EXPIRED, FAILED, UNSUPPORTED
  int64 challenge_ts_ms = 13;
  int64 redemption_ts_ms = 14;
  int64 receipt_expiry_ts_ms = 15;
  int32 max_age_sec = 16;
  string supply_path_id = 17;
  string seller_id = 18;
  string fraud_policy_id = 19;
  string release_scope = 20; // fraud_quality_only, optimization_quality_only, aggregate_only
}
```

关键约束：

- `token_challenge_digest` 和 `token_redemption_digest` 只用于 replay / audit / debugging；原始 token 默认不落普通日志。
- `server_request_id` 只留在 AdNetwork 内部或 confidential plane，不能随 attestation receipt 给 MMP。
- `attestation_result=VERIFIED` 只能说明 touchpoint 环境质量更可信，不能单独证明 conversion 应归因给该 network。
- optimization plane 只能消费 `device_authenticity_bucket`、`supply_path_quality_bucket` 这类派生桶，不能消费 token digest 或 platform attestation blob。

### 8.20 FheMeasurementTaskConfig

这个对象只在 hardened profile 下启用。它定义某个 measurement task 是否允许 FHE，以及允许哪一种电路、密钥、参数和解密边界。不要把 FHE 参数藏在 SDK remote config 里；FHE 的安全性和性能都高度依赖这些参数。

```proto
message FheMeasurementTaskConfig {
  string measurement_task_id = 1;
  string fhe_profile_id = 2; // disabled, fhe_private_candidate_scoring_v1, fhe_aggregate_sum_v1, fhe_encrypted_inference_v1
  string scheme = 3; // BFV, BGV, CKKS, TFHE, FHEW
  int32 security_level_bits = 4; // 128 or higher
  int32 poly_modulus_degree = 5;
  repeated int32 coeff_modulus_bits = 6;
  int64 plaintext_modulus = 7; // BFV/BGV only
  double ckks_scale = 8; // CKKS only
  int32 slot_count = 9;
  string public_key_id = 10;
  string relin_keys_ref = 11;
  string galois_keys_ref = 12;
  string key_epoch_id = 13;
  string circuit_id = 14;
  int32 multiplicative_depth = 15;
  int32 max_ciphertext_bytes = 16;
  int32 max_response_ciphertext_bytes = 17;
  string decryptor_role = 18; // device_sdk, threshold_collectors, confidential_service
  string output_release_policy_id = 19;
  string fhe_library_hint = 20; // openfhe, seal, lattigo, concrete
}
```

关键约束：

- `decryptor_role=device_sdk` 时，server `MUST NOT` 获得 secret key；但 SDK 也不应获得未限界的 candidate database 明细。
- `decryptor_role=threshold_collectors` 时，至少需要 `threshold_policy_id`、collector identity、share refresh 和 audit log；不要把它伪装成普通 server decrypt。
- FHE 结果解密后仍然受 `output_release_policy_id` 约束。FHE 保护的是计算过程，不是输出本身。
- `scheme=CKKS` 的输出是近似值，不得用于需要 exact equality / exact count 的归因判定。

### 8.21 FhePrivateMeasurementQuery

这个对象描述一次 FHE 子流程请求。它不替代 `MmpAskRequest`、`ClaimResponse` 或 `MmpConfirmRequest`；它只是 Ask 内部的一个可选 hardened 子状态。

```proto
message FhePrivateMeasurementQuery {
  string fhe_query_id = 1;
  string mmp_event_id = 2;
  string measurement_task_id = 3;
  string fhe_profile_id = 4;
  string public_key_id = 5;
  string key_epoch_id = 6;
  string circuit_id = 7;
  bytes encrypted_feature_vector = 8;
  bytes encrypted_selector_or_mask = 9;
  string encrypted_input_encoding = 10; // packed_bfv_bits, ckks_real_slots, tfhe_bits
  string prefix_bucket_hint = 11;
  int32 padded_candidate_count = 12;
  int64 query_ts_ms = 13;
  int64 query_expiry_ts_ms = 14;
  bytes replay_cache_key = 15;
  string output_release_policy_id = 16;
}

message FhePrivateMeasurementResponse {
  string fhe_query_id = 1;
  string evaluation_status = 2; // EVALUATED, REJECTED, UNSUPPORTED_PROFILE, TOO_EXPENSIVE
  bytes encrypted_match_scores = 3;
  bytes encrypted_aggregate_result = 4;
  bytes encrypted_auxiliary_proof = 5;
  int32 padded_candidate_count = 6;
  int32 circuit_eval_ms = 7;
  string evaluator_build_id = 8;
  string evaluation_manifest_digest = 9;
}
```

关键约束：

- request 里不能带 raw `ip`、raw `boot_time_ms`、`device_fp_hash` 明文；只能带 policy-bound encoded/encrypted feature。
- `prefix_bucket_hint` 如果会泄露太多，应做粗分桶、padding 或固定批次；FHE 不会自动隐藏 access pattern。
- response 里只返回 encrypted scores / encrypted aggregate；明文 `req_id`、row key、candidate payload 仍然不得出现。
- FHE response 解密后的结果必须继续走 `ClaimResponse -> MmpConfirmRequest -> token_to_req_id_join`，不能绕过 MMP SRN 闭环。

### 8.22 IncrementalityCalibrationRecord

这个对象回答 optimization plane 的另一个问题：这条 request-level label 对 bidder / pacing 到底应当产生多大权重。`RequestScopedOptimizationLabel` 是归因事实，`IncrementalityCalibrationRecord` 是增量价值校准；两者不能合并。

```proto
message IncrementalityCalibrationRecord {
  string calibration_id = 1;
  string measurement_task_id = 2;
  int64 advertiser_id = 3;
  int64 campaign_id = 4;
  int64 creative_family_id = 5;
  string calibration_level = 6; // campaign_day, campaign_week, creative_family_week
  string experiment_provenance = 7; // RCT, GEO_HOLDOUT, SYNTHETIC_CONTROL, PIE_MODEL
  string experiment_id = 8;
  string holdout_policy_id = 9;
  string post_determined_feature_snapshot_id = 10;
  int64 attributed_conversion_count = 11;
  int64 test_group_outcome_count = 12;
  int64 exposure_count = 13;
  int32 exposure_rate_micros = 14;
  int32 last_click_share_micros = 15;
  int32 predicted_incrementality_micros = 16;
  int32 incrementality_weight_micros = 17;
  string calibration_model_id = 18;
  string calibration_library_hint = 19; // lightgbm, xgboost, econml, dowhy
  int64 valid_from_ts_ms = 20;
  int64 expires_ts_ms = 21;
  string release_scope = 22; // optimization_calibration_only, aggregate_reporting_only
}
```

关键约束：

- `calibration_id` 可以进入 `OptimizationTrainingRow`，但 RCT raw exposure / control-group user rows 不进入普通训练面。
- `post_determined_feature_snapshot_id` 只能指向 aggregate feature snapshot，不能指向 user-level 明细。
- `incrementality_weight_micros` 是 sample weighting / budget prior，不得反向改写 `is_attributed`。
- 如果 `experiment_provenance=PIE_MODEL`，必须保留训练该 calibration model 的 RCT / holdout provenance；否则它会退化成“看起来像因果”的普通预测模型。

### 8.23 PrivacyControlPropagationRecord

这个对象把 consent、jurisdiction、deletion 和 partner privacy signal 变成正式协议状态。它不判断归因是否成立，只约束哪些 artifact、token、feature release、debug trace 可以继续存在或继续被消费。

```proto
message PrivacyControlPropagationRecord {
  string control_signal_id = 1;
  string source_system = 2; // mmp, cmp, advertiser_server, gpp, ddrf
  string request_type = 3; // CONSENT_UPDATE, CONSENT_WITHDRAWAL, DELETE, SUPPRESS_PROCESSING
  string jurisdiction_scope = 4; // US-CA, US-MD, EEA, UK, CH
  bytes gpp_string_digest = 5;
  repeated string gpp_section_ids = 6;
  string ddrf_request_id = 7;
  int64 subject_user_id_int64 = 8; // optional advertiser first-party user id when lawfully available
  bytes subject_match_key_digest = 9;
  repeated string affected_token_types = 10; // mmp_touch_token, claim_token, odm_info, debug_trace_window
  repeated string affected_plane_ids = 11; // device_raw, confidential, optimization, aggregate
  string action = 12; // DELETE, FREEZE, SUPPRESS_RELEASE, ROTATE_KEYS, RETAIN_AGGREGATE_ONLY
  int64 effective_ts_ms = 13;
  int64 received_ts_ms = 14;
  int64 propagation_deadline_ts_ms = 15;
  string propagation_status = 16; // RECEIVED, IN_PROGRESS, APPLIED, PARTIAL, FAILED
  bytes request_signature = 17;
  string audit_log_ref = 18;
}
```

关键约束：

- `subject_user_id_int64` 只在 advertiser first-party 合法可用时出现；它不是 ad network 的跨 app 用户 ID。
- deletion / suppression 不应简单删除 aggregate history；更常见的动作是停止未来 release、冻结 request-level feature consumption、轮转 debug key，并记录 audit trail。
- `PrivacyControlPropagationRecord` 必须能追到 `retention_policy_id`、`feature_policy_id`、`debug_trace_window_id`，否则无法证明 PII 派生物被按范围处理。

### 8.24 MultiIdentifierPrivateMatchPolicy

这个对象描述 advertiser / MMP / ad network 在需要多标识符私密匹配时的任务级策略。它的目标不是增加可见字段，而是防止实现方先把 email、phone、rdid、idfv、appsetid、gclid、gbraid 等材料合成一个长期 universal user id，再把“私密匹配”放到后面补救。

```proto
message MatchIdentifierSource {
  string identifier_type = 1; // email_sha256, phone_sha256, idfv, idfa, rdid_zeroed, appsetid, gclid, gbraid, odm_info
  string source_plane = 2; // device_raw, advertiser_first_party, mmp_compat, adnetwork_touch
  string normalization_policy_id = 3;
  string availability_policy_id = 4;
  bool may_leave_device_raw = 5;
  bool may_enter_mmp = 6;
  bool may_enter_optimization = 7;
}

message MultiIdentifierPrivateMatchPolicy {
  string private_match_policy_id = 1;
  string measurement_task_id = 2;
  string advertiser_id = 3;
  string app_bundle = 4;
  repeated MatchIdentifierSource identifier_sources = 5;
  string matching_protocol = 6; // reversed_oprf, voprf_psm, psi, pjc, encrypted_relay_fallback
  string oprf_suite_id = 7; // ristretto255, p256, voprf_rfc9497_suite
  string blind_key_epoch_id = 8;
  int64 key_epoch_start_ts_ms = 9;
  int64 key_epoch_expiry_ts_ms = 10;
  string key_rotation_policy_id = 11;
  string linkage_guardrail_id = 12; // no_cross_identifier_join, task_scoped_join_only
  string intersection_release_policy_id = 13;
  string dp_intersection_size_policy_id = 14;
  int32 max_identifier_types_per_event = 15;
  int32 max_candidate_rows_per_bucket = 16;
  string fallback_policy_id = 17;
  string audit_manifest_digest = 18;
}
```

关键约束：

- `identifier_sources` 是 allowlist，不是 SDK 可以随意添加字段的 schema。
- `may_leave_device_raw=false` 的标识符只能在端上或 confidential plane 内派生 task-bound material，不能通过 MMP 透传。
- `blind_key_epoch_id` 必须和 `measurement_task_id`、app、partner 绑定；禁止跨 advertiser / app / purpose 复用同一 blind output。
- `intersection_release_policy_id` 只能释放 scoped claim、DP-obfuscated count 或 aggregate outcome；不能释放“哪些 identifier pair 命中”的明细。
- 如果启用 fallback encrypted relay，必须把它标成 lower-privacy profile，不能继续宣称 raw material stayed local。

### 8.25 StreamingDpReleasePlan

这个对象描述实时广告测量报表如何做 per-user DP。它服务 aggregate reporting plane，不改变主链路的 `MMP Ask -> Claim -> Confirm`，也不要求 Phase 1 optimization plane 必须先上 DP。

```proto
message StreamingDpReleasePlan {
  string streaming_dp_plan_id = 1;
  string measurement_task_id = 2;
  string metric_name = 3; // install_count, purchase_count, revenue_sum, roas_num
  string attribution_rule_id = 4; // last_click, engaged_click_only, winner_only, fractional_credit
  string dp_subject_unit = 5; // advertiser_user, app_instance, device_scoped, household, unknown
  string dp_adjacency_relation = 6; // add_remove_user, replace_user, bounded_events_per_user
  string contribution_bounding_scope = 7; // per_user_per_campaign_day, per_user_per_task_epoch
  string contribution_enforcement_point = 8; // device_sdk, confidential_plane, aggregate_collector
  string release_slot_granularity = 9; // hourly, daily, campaign_day
  int64 release_slot_start_ts_ms = 10;
  int64 release_slot_end_ts_ms = 11;
  string budget_scope_id = 12;
  int32 epsilon_micros = 13;
  int64 delta_nanos = 14;
  string noise_family = 15; // discrete_laplace, gaussian, non_iid_streaming
  string noise_power_allocation_id = 16;
  string streaming_state_ref = 17;
  string dp_audit_profile_id = 18;
  string release_lifecycle_state = 19; // planned, reserved, released, corrected, frozen
}
```

关键约束：

- `attribution_rule_id`、`dp_adjacency_relation`、`contribution_bounding_scope`、`contribution_enforcement_point` 必须同时出现；只写 `epsilon` 不是一个可执行 DP 配置。
- `dp_subject_unit=unknown` 时，系统只能发布 thresholded / non-DP operational dashboard，不应宣称 user-level DP。
- `release_slot_granularity` 必须和 budget ledger 对齐；同一 slot 的 correction release 也要扣预算或进入明确的 correction policy。
- `noise_power_allocation_id` 应记录到训练和报表治理栈，方便解释为什么某些 campaign / slot 的误差不同。

### 8.26 MeasurementUtilityExperimentRecord

这个对象记录隐私增强 measurement profile 的业务可用性，而不是记录用户级明细。最新 field experiment 的共同教训是：隐私技术的效果会受 adoption、latency、供应侧覆盖、成本口径和冷启动状态影响。RFC 因此需要一个正式对象来回答“这个 profile 是否值得上线、在哪里上线、用什么 fallback”，而不是只写“privacy-preserving”。

```proto
message MeasurementUtilityExperimentRecord {
  string experiment_id = 1;
  string measurement_task_id = 2;
  string platform_surface = 3; // google_icm_ios_odm, google_icm_android_partner_api, apple_aak, w3c_attribution, internal_odm
  string privacy_profile = 4; // no_dp_baseline, thresholded, aggregate_dp, semi_sensitive_dp, strict_aggregate_only
  string treatment_profile_id = 5;
  string baseline_profile_id = 6;
  string causal_design = 7; // geo_experiment, randomized_holdout, switchback, synthetic_control, observational_with_calibration
  string traffic_scope = 8;
  int64 start_ts_ms = 9;
  int64 end_ts_ms = 10;
  int64 impression_count = 11;
  int64 click_count = 12;
  int64 conversion_count = 13;
  double attribution_observability_delta_ratio = 14;
  double revenue_delta_ratio = 15;
  double cpa_delta_ratio = 16;
  double roas_delta_ratio = 17;
  double latency_p95_delta_ms = 18;
  double impression_delivery_delta_ratio = 19;
  string adoption_state = 20; // sdk_ready, partner_beta, partial_supply, broad_rollout, fallback_only
  string query_budget_policy_id = 21;
  string sensitive_signal_policy_id = 22;
  string decision = 23; // ship, ship_with_gate, hold, rollback
  string decision_note = 24;
}
```

关键约束：

- 这个对象只允许 aggregate experiment metrics，不允许包含 `server_request_id`、`user_id`、`claim_token`、`odm_info` 或 raw device signal。
- `latency_p95_delta_ms` 与 `impression_delivery_delta_ratio` 必须和业务指标一起看；隐私保护路径如果显著增加延迟，measurement / auction / SDK 初始化都需要独立排障。
- `adoption_state` 是上线门槛之一。一个在 partial-supply beta 下有效或无效的结果，不能直接外推为全量生产判断。
- `decision=ship_with_gate` 必须说明 gate，例如 region、MMP partner、SDK version、cold-start cohort 或 aggregate-only reporting。

### 8.27 MeasurementConformanceProfile

这个对象回答一个 RFC 实施中经常被忽略的问题：某个 app / advertiser / MMP / ad network 组合到底实现了哪一级能力。没有 conformance profile，团队很容易说“我们支持 on-device measurement”，但实际只支持 `odm_info` pass-through、没有 Confirm 后的 request-level label、没有 sensitive-signal derivation record，也没有 aggregate budget ledger。

```proto
message MeasurementConformanceProfile {
  string conformance_profile_id = 1;
  string measurement_task_id = 2;
  string advertiser_id = 3;
  string app_bundle = 4;
  string platform = 5; // ios, android, cross_platform
  string profile_level = 6; // PROFILE_A_MINIMUM, PROFILE_B_DEFAULT, PROFILE_C_CROSS_PARTY, PROFILE_D_FHE_HARDENED
  string mmp_partner_id = 7;
  string srn_contract_id = 8;
  string sdk_compat_profile_id = 9;
  string request_level_join_mode = 10; // server_request_id_internal_only, aggregate_only, disabled
  bool request_level_optimization_enabled = 11;
  string optimization_privacy_mode = 12; // no_dp_confidential, label_dp, semi_sensitive_dp, full_user_level_dp
  string public_reporting_privacy_mode = 13; // thresholded_only, aggregate_dp, dap_vdaf_aligned
  repeated string required_protocol_objects = 14;
  repeated string required_policy_objects = 15;
  repeated string prohibited_field_names = 16;
  repeated string sensitive_signal_policy_ids = 17;
  string training_privacy_policy_id = 18;
  string aggregate_budget_scheduler_policy_id = 19;
  string streaming_dp_plan_id = 20;
  string utility_experiment_id = 21;
  repeated string approved_library_profiles = 22; // protobuf_buf, circl_voprf, lightgbm, opendp, jax_privacy, openfhe
  string crypto_suite_policy_id = 23;
  string runtime_trace_requirement = 24; // required, sampled, disabled
  string derivation_record_requirement = 25; // required, sampled, disabled
  string fallback_policy_id = 26;
  string rollout_gate = 27; // partner_beta, region_allowlist, sdk_version_gate, broad_rollout
  string break_glass_policy_id = 28;
  string conformance_test_suite_id = 29;
  string audit_manifest_digest = 30;
  int64 effective_from_ts_ms = 31;
  int64 expires_ts_ms = 32;
}
```

关键约束：

- `profile_level=PROFILE_A_MINIMUM` 也必须包含 `claim_token` replay gate、`mmp_touch_token -> server_request_id` 内部 join、`TrainingPrivacyPolicy`、thresholded aggregate reporting 和 prohibited field manifest。否则它不是 minimum production。
- `request_level_optimization_enabled=true` 时，`request_level_join_mode` 必须是 `server_request_id_internal_only`，且 `prohibited_field_names` 至少包含 `raw_ip`、`boot_time_ms`、`device_fp_hash`、`odm_info`、`claim_token`。
- `public_reporting_privacy_mode=aggregate_dp` 或 `dap_vdaf_aligned` 时，必须引用 `aggregate_budget_scheduler_policy_id` 或 `streaming_dp_plan_id`；不能只写 `dp=true`。
- `optimization_privacy_mode=no_dp_confidential` 可以用于 Phase 1，但 conformance profile 必须显式声明，不得把它包装成 full DP。
- `runtime_trace_requirement=disabled` 只适用于离线研究或不可上线 profile；生产 ICM / ODM / AAP integration 至少应为 `sampled`，推荐 `required`。
- `approved_library_profiles` 是工程约束，不是宣传材料。OPRF / VOPRF、DP、FHE、GBDT、causal calibration 都应优先使用成熟库或 audited implementation，不应自研 toy primitive。

### 8.28 LaunchClockEvidenceRecord

`boot_time`、app launch time、SDK init delay 都是双刃剑：它们能显著改善 install / first_open attribution 的时间对齐，也可能变成设备指纹或 timing side-channel。因此本文不建议把它们当普通特征写进训练表，而是单独建模为 launch / clock evidence。

```proto
message LaunchClockEvidenceRecord {
  string launch_clock_evidence_id = 1;
  string measurement_task_id = 2;
  string platform = 3; // ios, android
  string app_bundle = 4;
  string sdk_instance_id = 5;
  int64 server_request_id = 6; // Ad Network internal only
  int64 app_process_start_wall_ts_ms = 7;
  int64 sdk_init_wall_ts_ms = 8;
  int64 first_open_event_wall_ts_ms = 9;
  int64 monotonic_elapsed_ms_at_sdk_init = 10;
  int64 monotonic_elapsed_ms_at_first_open = 11;
  int64 sdk_init_delay_ms = 12;
  string capture_point = 13; // didFinishLaunchingWithOptions, ContentProvider.onCreate, Activity.onCreate
  string first_session_delay_state = 14; // inactive, active_waiting, active_released
  string clock_quality_bucket = 15; // launch_0_250ms, launch_250_1000ms, delayed_gt_1000ms
  string raw_boot_time_policy_id = 16;
  bool raw_boot_time_collected = 17;
  bool raw_boot_time_released = 18;
  repeated string derived_clock_buckets = 19;
  repeated string allowed_release_surfaces = 20; // device_derivation_only, runtime_trace, trainer_bucket
  repeated string prohibited_release_surfaces = 21; // mmp_payload, claim_response, bi_raw_logs
  string side_channel_mitigation = 22; // constant_path, sampled_trace, disabled
  string consent_snapshot_id = 23;
  string derivation_record_id = 24;
  string trace_id = 25;
  int64 record_created_ts_ms = 26;
}
```

关键约束：

- `raw_boot_time_released` 在生产 profile 中默认必须是 `false`。如果为了 OS / SDK 兼容需要临时采集 raw boot time，也只能在 SDK process 或 confidential derivation plane 内短 TTL 使用。
- `clock_quality_bucket` 可以进入 optimization plane，但必须是粗粒度桶；不能把 `boot_time_ms`、`monotonic_elapsed_ms_at_*` 原值写入 `OptimizationTrainingRow`。
- `capture_point` 和 `first_session_delay_state` 属于 integration health，不是用户特征。它们可用于解释 ODM / ICM 命中率下降，但不得直接成为 bidder 的用户级 targeting feature。
- `side_channel_mitigation=disabled` 只适合离线诊断。生产路径至少要做到固定错误语义、稳定返回形态、采样 trace 和 forbidden-field scan。

### 8.29 EcosystemPrivacyCompositionRecord

这个对象回答 PoPETs 2026 private advertising 研究提出的核心问题：一个广告 measurement 系统不能只证明每个组件“看起来隐私”，还要说明这些组件组合后泄露了什么、哪些泄露是业务上不可避免的、哪些泄露被 gate 住了。

```proto
message EcosystemPrivacyCompositionRecord {
  string composition_record_id = 1;
  string measurement_task_id = 2;
  string conformance_profile_id = 3;
  string advertiser_id = 4;
  string app_bundle = 5;
  string mmp_partner_id = 6;
  int64 advertiser_user_id = 7; // advertiser scoped; Protobuf JSON should encode int64 as string
  int64 server_request_id = 8; // Ad Network internal only
  string mmp_conversion_id = 9;
  repeated string composed_surfaces = 10;
  repeated string raw_sensitive_inputs = 11;
  repeated string derived_sensitive_outputs = 12;
  repeated string external_release_surfaces = 13;
  repeated string internal_release_surfaces = 14;
  repeated string residual_leakage_channels = 15;
  repeated string non_composing_privacy_claims = 16;
  repeated string required_gates = 17;
  string composition_privacy_statement = 18; // contextual_scope_enforced, no_end_to_end_dp_claim
  string optimization_release_mode = 19; // request_level_internal, aggregate_only, disabled
  string public_reporting_mode = 20; // thresholded, aggregate_dp, dap_vdaf_aligned
  string decision = 21; // ship_with_gates, aggregate_only, block
  string reviewer = 22;
  int64 created_ts_ms = 23;
}
```

关键约束：

- 只要同时启用 MMP/AAP reporting、SRN Confirm 和 Ad Network request-level optimization，就必须生成 `EcosystemPrivacyCompositionRecord`。
- `non_composing_privacy_claims` 的作用是阻止误读。例如 “ODM keeps identifiable info on device”、“SRN yes/no is minimal”、“aggregate report has DP” 三句话都可能为真，但三者相加仍不等于 end-to-end DP。
- `advertiser_user_id:int64` 如果存在，只能作为 advertiser-scoped 输入事实或 MMP 合同内字段；进入 Ad Network / SRN / trainer 前必须转成 task-scoped token、coarse bucket 或受控 label。
- `decision=ship_with_gates` 必须指向具体 gate，例如 `clock_evidence_required`、`forbidden_field_scan`、`claim_token_replay_cache`、`aggregate_budget_scheduler` 或 `composition_review_required`。

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

### 9.1A touchpoint device / supply-path attestation receipt

```json
{
  "attestation_receipt_id": "att_01JTXD1P7ZK69KJZB8A7K9P0M3",
  "server_request_id": 91833720368540001,
  "publisher_app_numeric_id": 88990011,
  "publisher_app_bundle": "com.example.game",
  "om_sdk_version": "1.6.0",
  "attestation_protocol": "privacy_pass_private_token",
  "attester_id": "apple",
  "issuer_id": "iab_om_device_attestation_issuer_us",
  "verifier_id": "adnetwork_quality_verifier_v2",
  "token_challenge_digest": "sha256:7fbe0a9e4b1d...",
  "token_redemption_digest": "sha256:ac451b71d2b4...",
  "attestation_result": "VERIFIED",
  "challenge_ts_ms": 1777500005180,
  "redemption_ts_ms": 1777500005411,
  "receipt_expiry_ts_ms": 1777500305411,
  "max_age_sec": 300,
  "supply_path_id": "seller:pub-7788/app:com.example.game/exchange:adx",
  "seller_id": "pub-7788",
  "fraud_policy_id": "touch_quality_attestation_v1",
  "release_scope": "fraud_quality_only"
}
```

这个 receipt 可以让内部训练面知道 `server_request_id=91833720368540001` 的 touchpoint 质量更可信，但 trainer 只应看到派生后的 `device_authenticity_bucket=attested` / `supply_path_quality_bucket=verified_seller`，不应看到 token digest。

### 9.1B device sensitive signal policy

这条 policy 表达的是：SDK 可以观察 raw `ip` / `boot_time`，但只能把它们变成短期、粗粒度、任务绑定的派生桶。它同时把 cold-start 场景写进 gating，避免 location-like signal 在行为历史已经充足后继续成为默认优化特征。

```json
{
  "policy_id": "sens_sig_install_coldstart_v1",
  "measurement_task_id": "icm_install_v3",
  "raw_signal_names": [
    "boot_time_ms",
    "raw_ip",
    "ip_prefix",
    "network_churn",
    "install_referrer_hint"
  ],
  "collection_point": "adnetwork_sdk",
  "allowed_raw_surface": "confidential_plane_short_ttl",
  "raw_ttl_seconds": 3600,
  "derivation_mode": "bucketize_clip_hmac",
  "released_feature_names": [
    "boot_time_freshness_bucket",
    "ip_churn_bucket",
    "network_stability_bucket",
    "same_country_as_touch"
  ],
  "release_scope": "optimization_only",
  "cold_start_gate": "first_n_events",
  "max_precision_level": 2,
  "allow_mmp_visibility": false,
  "allow_trainer_raw_visibility": false,
  "consent_dependency_id": "gpp_tcf_limited_ads_v3",
  "retention_policy_id": "retain_raw_1h_confidential_derived_30d",
  "legal_basis_policy_id": "ads_measurement_legitimate_interest_or_consent_v2"
}
```

落地含义：

- MMP 看不到 `raw_ip`、`boot_time_ms` 或 `ip_prefix`。
- trainer 只看派生桶，而且这些桶由 `feature_policy_id` / `policy_id` 约束。
- 如果 consent 状态缺失、用户处于 EEA/UK/CH 且当前 contract 不允许，SDK 应跳过派生或只输出 aggregate-only contribution。

### 9.1C device sensitive signal derivation record

这条 record 是 9.1B policy 的一次执行结果。它解释“广告媒体 SDK 看到了敏感信号后，最终哪些信息能被回传到服务端做 personalized optimization”。注意：这里保留 `server_request_id:int64`，但它是 Ad Network 内部 join key，不会出现在 MMP Ask / Claim / Confirm payload 里。

```json
{
  "derivation_record_id": "dsdr_01JVCKY8X7F8BR0N9Y6C2H7P11",
  "measurement_task_id": "icm_install_v3",
  "server_request_id": 91833720368540001,
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "sensitive_signal_policy_id": "sens_sig_install_coldstart_v1",
  "collection_ts_ms": 1777500905019,
  "derivation_ts_ms": 1777500905061,
  "observed_raw_signal_names": [
    "boot_time_ms",
    "raw_ip",
    "network_churn",
    "install_referrer_hint"
  ],
  "raw_surface": "confidential_plane_short_ttl",
  "raw_delete_after_ts_ms": 1777504505061,
  "derived_feature_buckets": {
    "boot_time_freshness_bucket": "lt_2h",
    "ip_churn_bucket": "stable_24h",
    "network_stability_bucket": "wifi_stable",
    "same_country_as_touch": "true"
  },
  "derived_release_surface": "optimization_feature_store",
  "consent_snapshot_id": "consent_01JVCKY6J8A9T4K2M1Q3F5",
  "legal_basis_state": "limited_ads",
  "jurisdiction_scope": "US-CA",
  "cold_start_state": "first_open",
  "mmp_visible": false,
  "trainer_raw_visible": false,
  "feature_policy_id": "feature_low_sensitive_v4",
  "retention_policy_id": "retain_raw_1h_confidential_derived_30d",
  "debug_log_policy_id": "debug_no_raw_sensitive_v2",
  "optimization_join_key_mode": "server_request_id_internal",
  "derivation_code_version": "sdk-ios-odm-bridge-4.18.2",
  "replay_nonce_digest": "sha256:2a9d77ef5bc1...",
  "sdk_signature": "base64:MEUCIQCp..."
}
```

服务端消费规则：

- `optimization_feature_store` 可以按 `server_request_id` join 到 bidder / ranking / pacing 样本，但只能消费 `derived_feature_buckets`。
- MMP 的 Ask / Claim / Confirm 仍只走 `mmp_event_id`、`mmp_touch_token`、`claim_token` 和 reporting metadata，不接触 raw signal，也不接触 `server_request_id`。
- 如果之后 MMP Confirm 没有发生，`server_request_id_internal` 只能用于 fraud / integration debug，不得物化为正样本 conversion label。
- 如果 consent 变更或 deletion request 到达，`consent_snapshot_id` 与 `retention_policy_id` 必须能追到这条 record，并冻结后续 feature consumption。

### 9.2 compatibility 端上 artifact

这是兼容 / bridge path 的对象，不是 v3.1 主链路的必需输入。

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

### 9.2C aggregate budget scheduler policy

下面这条 mock 表达的是“为什么 9.2B 那次 collect 可以被执行”。它不是用户级明细，也不是训练特征，而是 aggregate collector 的控制面配置。`formal_budget_model` 决定这套报表能宣称什么隐私口径。

```json
{
  "policy_id": "budget_sched_w3c_attr_v1",
  "measurement_task_id": "agg_install_geo_day_v4",
  "privacy_unit": "device_scoped_epoch",
  "formal_budget_model": "hybrid_per_collector_plus_global",
  "per_collector_scope_id": "mmp_example_us_daily",
  "per_collector_quota_micros": 250000,
  "global_budget_scope_id": "advertiser_120045_global_device_epoch_202604",
  "global_budget_micros": 3000000,
  "global_budget_slack_micros": 450000,
  "scheduler_type": "batched_quota_scheduler",
  "batch_window_seconds": 3600,
  "min_batch_size": 1000,
  "max_batch_delay_seconds": 14400,
  "dos_resilience_policy_id": "resource_isolation_v1",
  "adaptive_querier_throttling": true,
  "correction_release_policy_id": "corrections_reconsume_budget_v1",
  "audit_log_sink": "privacy_ledger_prod.aggregate_budget_events",
  "formal_guarantee_note": "per-collector quota plus global device-epoch IDP budget; Phase 1 internal dashboards may use quota-only mode but must not claim global DP"
}
```

### 9.3 advertiser app / server 缓存的 `odm_info`

这是 Google ICM / AAP 类接口的兼容对象。v3.1 主链路不要求 MMP 用 `odm_info` 作为 matching material。

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

v3.1 主链路中，MMP SDK 对 AdNetwork SDK 的 Ask 应该是薄触发，不携带 device matching material：

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "mmp_name": "ExampleMMP",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "event_name": "first_open",
  "event_ts_ms": 1777500905123,
  "adv_app_id": "com.example.game",
  "ask_idempotency_key": "ask_01JTRP7V8W5T7A8Y4A8V2P",
  "partner_context": {
    "mmp_install_id": "mmp_install_120045_9981",
    "country_code": "US",
    "query_template_id": "mmp_install_query_v2"
  }
}
```

不应包含：

- `device_fp_hash`
- raw device material
- OPRF input / output
- row key

### 9.4A iOS local Ask eligibility

MMP SDK 在调用某个 ad network Ask 前，应先在本地得到类似下面的 capability 结果：

```json
{
  "mmp_name": "ExampleMMP",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "network_id": "adn_123",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "sdk_present": false,
  "sdk_version": "",
  "adapter_present": false,
  "adapter_version": "",
  "supports_odm_ask": false,
  "ask_eligibility_status": "SDK_NOT_PRESENT",
  "skip_reason_code": "IOS_ADNETWORK_SDK_NOT_LINKED",
  "evaluated_ts_ms": 1777500905000,
  "capability_cache_expiry_ts_ms": 1777504505000,
  "discovery_method": "REGISTRY",
  "registry_policy_id": "ios_adapter_registry_policy_v1"
}
```

如果 SDK / adapter 存在，则 eligibility 可以变成：

```json
{
  "mmp_name": "ExampleMMP",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "network_id": "adn_456",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "sdk_present": true,
  "sdk_version": "3.2.0",
  "adapter_present": true,
  "adapter_version": "1.4.1",
  "supports_odm_ask": true,
  "ask_eligibility_status": "ELIGIBLE",
  "skip_reason_code": "",
  "evaluated_ts_ms": 1777500905000,
  "capability_cache_expiry_ts_ms": 1777504505000,
  "discovery_method": "REGISTRY",
  "registry_policy_id": "ios_adapter_registry_policy_v1"
}
```

只有第二种状态才允许进入 `MMP SDK -> AdNetwork SDK Ask`。第一种状态应被视为 integration state，而不是 ad network declined attribution。

### 9.4B Compatibility MMP Ask with `odm_info`

如果对接已有 MMP / AAP / ICM server-side API，可以存在兼容形态：

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
  "compatibility_odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
  "query_template_id": "mmp_install_query_v2",
  "country_code": "US",
  "ask_idempotency_key": "ask_01JTRP7V8W5T7A8Y4A8V2P",
  "ask_attempt_ts_ms": 1777500905123,
  "query_contract_id": "google_icm_install_query_v3"
}
```

这类对象属于 compatibility surface，不改变 v3.1 主链路的边界：MMP 仍不提供 `device_fp_hash`，AdNetwork SDK 仍负责本地 material 和 OPRF/PSM。

### 9.4C MMP / ODM runtime trace

下面是一次 MMP SDK 集成 Google-compatible ODM / ICM 时应保存的低敏运行态 trace。它解释“为什么 Ask 可以发出、为什么 `odm_info` 可能缺失、SDK 初始化是否被 ODM fetch timeout 拖慢”，但不参与归因 winner selection。

```json
{
  "trace_id": "sdk_trace_01JW0W1T9P82VDV0DR7HG2P6K2",
  "mmp_name": "Singular",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "platform": "ios",
  "app_bundle": "com.example.game",
  "network_id": "google_ads",
  "sdk_family": "singular",
  "mmp_sdk_version": "12.8.1",
  "adnetwork_adapter_present": true,
  "adnetwork_adapter_version": "google-icm-adapter-1.0.0",
  "adapter_manifest_hash": "sha256:6f1d9d3c2b7a...",
  "odm_sdk_present": true,
  "odm_sdk_version": "GoogleAdsOnDeviceConversion-3.5.0",
  "odm_info_present": true,
  "odm_fetch_timeout_ms": 5000,
  "sdk_init_delay_ms": 814,
  "deep_link_callback_deferred": true,
  "event_source_system": "firebase_sdk",
  "is_firebase_native_event": true,
  "region_eligibility_code": "ELIGIBLE",
  "att_authorization_status": "DENIED",
  "ads_personalization_status": "UNKNOWN",
  "local_runtime_policy_id": "mmp_odm_runtime_trace_v2",
  "trace_release_scope": "integration_health_only",
  "icm_platform_rollout_state": "open_beta_all_advertisers",
  "icm_reporting_scope": "click_through_install_only",
  "odm_error_code": "",
  "kids_app_policy_state": "not_applicable",
  "user_level_retention_policy_id": "google_ads_user_level_6m_v1",
  "partner_consent_mapping_policy_id": "singular_lds_to_google_ads_consent_v1",
  "advanced_data_sharing_enabled": true,
  "android_sdk_update_required": false,
  "ios_odm_sdk_required": true,
  "icm_supported_engagement_types": ["click"],
  "icm_claim_semantics": "google_non_deterministic_claim",
  "gclid_capture_enabled": true,
  "install_referrer_gclid_capture_enabled": true,
  "gbraid_capture_enabled": true,
  "platform_measurement_api_family": "google_icm_ios_odm",
  "android_privacy_sandbox_measurement_state": "not_used",
  "apple_adattributionkit_postback_copy_enabled": false,
  "apple_adattributionkit_conversion_tag_present": false,
  "apple_adattributionkit_attribution_rule_profile_id": "",
  "apple_adattributionkit_geo_scope": "unavailable",
  "w3c_attribution_draft_date": "2026-05-14",
  "aggregate_api_dependency_state": "partner_managed"
}
```

如果事件来自 S2S 或 Measurement Protocol，应显式记录为不满足 event-data ODM path：

```json
{
  "trace_id": "sdk_trace_01JW0W2J0DJ4KW3EVVQEV6A1B3",
  "mmp_name": "ExampleMMP",
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "platform": "ios",
  "app_bundle": "com.example.game",
  "network_id": "google_ads",
  "sdk_family": "custom_mmp",
  "mmp_sdk_version": "8.1.0",
  "adnetwork_adapter_present": false,
  "adnetwork_adapter_version": "",
  "adapter_manifest_hash": "",
  "odm_sdk_present": false,
  "odm_sdk_version": "",
  "odm_info_present": false,
  "odm_fetch_timeout_ms": 0,
  "sdk_init_delay_ms": 0,
  "deep_link_callback_deferred": false,
  "event_source_system": "s2s_api",
  "is_firebase_native_event": false,
  "region_eligibility_code": "UNKNOWN",
  "att_authorization_status": "UNKNOWN",
  "ads_personalization_status": "UNKNOWN",
  "local_runtime_policy_id": "mmp_odm_runtime_trace_v2",
  "trace_release_scope": "integration_health_only",
  "icm_platform_rollout_state": "unsupported",
  "icm_reporting_scope": "unknown",
  "odm_error_code": "ODM_SDK_NOT_PRESENT",
  "kids_app_policy_state": "unknown",
  "user_level_retention_policy_id": "google_ads_user_level_6m_v1",
  "partner_consent_mapping_policy_id": "singular_lds_to_google_ads_consent_v1",
  "advanced_data_sharing_enabled": false,
  "android_sdk_update_required": false,
  "ios_odm_sdk_required": false,
  "icm_supported_engagement_types": [],
  "icm_claim_semantics": "unknown",
  "gclid_capture_enabled": false,
  "install_referrer_gclid_capture_enabled": false,
  "gbraid_capture_enabled": false,
  "platform_measurement_api_family": "google_icm_ios_odm",
  "android_privacy_sandbox_measurement_state": "not_used",
  "apple_adattributionkit_postback_copy_enabled": false,
  "apple_adattributionkit_conversion_tag_present": false,
  "apple_adattributionkit_attribution_rule_profile_id": "",
  "apple_adattributionkit_geo_scope": "unavailable",
  "w3c_attribution_draft_date": "2026-05-14",
  "aggregate_api_dependency_state": "partner_managed"
}
```

第二条 trace 的含义不是 “Google Ads declined”，而是 “本地没有可执行的 ODM event-data path”。这类状态应进入 integration health dashboard，不应进入 `AttributionDecisionRecord` 的 winner/loser 逻辑。

### 9.4D FHE private measurement query

下面是一条 hardened profile 下的 FHE 子流程示例。它发生在 `MMP SDK -> AdNetwork SDK Ask` 之后、`ClaimResponse` 之前；它不直接对 MMP 暴露，也不替代 Confirm。

```json
{
  "fhe_task_config": {
    "measurement_task_id": "icm_install_v3",
    "fhe_profile_id": "fhe_private_candidate_scoring_v1",
    "scheme": "BFV",
    "security_level_bits": 128,
    "poly_modulus_degree": 8192,
    "coeff_modulus_bits": [50, 30, 30, 50],
    "plaintext_modulus": 65537,
    "slot_count": 4096,
    "public_key_id": "fhe_pk_2026_05_ios_us_v1",
    "relin_keys_ref": "kms://fhe/eval/relin/2026_05_ios_us_v1",
    "galois_keys_ref": "kms://fhe/eval/galois/2026_05_ios_us_v1",
    "key_epoch_id": "fhe_epoch_2026_05_w01",
    "circuit_id": "candidate_score_exact_match_bfv_v1",
    "multiplicative_depth": 2,
    "max_ciphertext_bytes": 4194304,
    "max_response_ciphertext_bytes": 8388608,
    "decryptor_role": "device_sdk",
    "output_release_policy_id": "fhe_output_claim_candidate_v1",
    "fhe_library_hint": "openfhe"
  },
  "query": {
    "fhe_query_id": "fheq_01JW0X71N6K09HPACDJY5SBJGR",
    "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
    "measurement_task_id": "icm_install_v3",
    "fhe_profile_id": "fhe_private_candidate_scoring_v1",
    "public_key_id": "fhe_pk_2026_05_ios_us_v1",
    "key_epoch_id": "fhe_epoch_2026_05_w01",
    "circuit_id": "candidate_score_exact_match_bfv_v1",
    "encrypted_feature_vector": "base64:AgAAAAEAAABFHECIPHERTEXT...",
    "encrypted_selector_or_mask": "base64:AwAAABIAAADENSEMASK...",
    "encrypted_input_encoding": "packed_bfv_bits",
    "prefix_bucket_hint": "ios:us:2026-05-06:p22:8f4",
    "padded_candidate_count": 1024,
    "query_ts_ms": 1777587905123,
    "query_expiry_ts_ms": 1777588205123,
    "replay_cache_key": "base64:c2hhMjU2LWZoZS1yZXBsYXk...",
    "output_release_policy_id": "fhe_output_claim_candidate_v1"
  },
  "response": {
    "fhe_query_id": "fheq_01JW0X71N6K09HPACDJY5SBJGR",
    "evaluation_status": "EVALUATED",
    "encrypted_match_scores": "base64:BAAAABQAAABFVkFMUkVTVUxU...",
    "encrypted_aggregate_result": "",
    "encrypted_auxiliary_proof": "base64:ZXZhbF9tYW5pZmVzdF9wcm9vZg...",
    "padded_candidate_count": 1024,
    "circuit_eval_ms": 187,
    "evaluator_build_id": "fhe-evaluator-openfhe-1.5.1-20260507",
    "evaluation_manifest_digest": "sha256:3ce4a7f0c9d2..."
  }
}
```

SDK 解密 `encrypted_match_scores` 后只能得到 policy-bound candidate decision，例如：

```json
{
  "fhe_query_id": "fheq_01JW0X71N6K09HPACDJY5SBJGR",
  "decrypted_candidate_count": 1024,
  "matched_candidate_count": 1,
  "selected_candidate_slot": 317,
  "local_decision": "FHE_MATCHED_ONE_CANDIDATE",
  "release_to_mmp": {
    "claim_status": "CLAIMED",
    "mmp_touch_token": "AMT_v1_7ec3b6bd1c4a1f29999ae73f8c6c0d12",
    "claim_token": "base64:Wk1Qd1p4Y2xhaW0...",
    "campaign_id": 74012091,
    "creative_id": 74019912
  }
}
```

注意这里仍然没有把 `server_request_id`、row key、raw device signal 或完整 candidate payload 给 MMP。FHE 子流程只改变 “SDK 和 AdNetwork Server 怎么完成候选评分”，不改变 SRN 的 `Claim -> Confirm` 闭环。

### 9.4E Apple AdAttributionKit platform postback trace

Apple AdAttributionKit 的 postback copy / conversion tag / geography 字段应进入 platform postback reconciliation plane，而不是替代 MMP Ask / Claim / Confirm。下面是一条 advertised app server 或 MMP/AAP 侧可以保存的兼容 trace：

```json
{
  "platform_postback_trace_id": "aak_pb_01JW2K8Q7AB9W6M7P7Y9C9Z8H2",
  "platform_measurement_api_family": "apple_adattributionkit",
  "app_bundle": "com.example.game",
  "advertised_item_id": 6451234567,
  "publisher_item_id": 6440001112,
  "ad_network_id": "exampleadnetwork.skadnetwork",
  "conversion_type": "reengagement",
  "postback_sequence_index": 1,
  "source_identifier": "74012091",
  "campaign_id": 74012091,
  "creative_family_id": 74019,
  "country_or_region": "US",
  "conversion_tag_present": true,
  "conversion_tag_ref": "aak_tag_01JW2K8Q9V6K",
  "attribution_rule_profile_id": "aak_custom_window_click_10d_view_24h_v1",
  "postback_copy_enabled": true,
  "postback_received_ts_ms": 1778587300123,
  "signature_verified": true,
  "crowd_anonymity_tier": "tier_2",
  "mmp_reconciliation_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "server_request_id_available": false,
  "req_id_join_policy": "not_available_from_platform_postback",
  "release_scope": "platform_postback_reconciliation_only"
}
```

这里的 `conversion_tag_ref` 只是 advertised app 自己区分重叠 reengagement conversion 的书签；它 `MUST NOT` 被升级成跨 app / 跨 network 用户标识。`country_or_region` 可用于 campaign / geo 粒度报表和校准，但不应让 request-level optimizer 误以为它拿到了原始 IP 或设备位置。若 Ad Network 需要 request-level optimization，仍应等待 MMP Confirm 后通过自己的 `mmp_touch_token -> server_request_id` 路径恢复内部上下文。

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
  "request_accepted": true,
  "match_type": "on_device_psm",
  "mmp_touch_token": "AMT_v1_7ec3b6bd1c4a1f29999ae73f8c6c0d12",
  "mmp_visible_handle_mode": "tracking_link_touch_token",
  "creative_id": 74019912,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "touch_time_bucket": 4933923
}
```

这个版本对应 legal Option 4：MMP 在 tracking link 阶段已经拿过同一个 `mmp_touch_token`，Claim 只补充 on-device match proof / `claim_token`。Claim 不返回 `req_id`、`device_fp_hash`、OPRF output、bucket tag/tail 或 row key。

如果 partner 需要兼容旧提案里的 `AdPlatformUserID + click_id`，Claim 可以按 Option 2A 降落，但必须显式标注 handle mode：

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "claim_status": "CLAIMED",
  "claim_token": "base64:QVBVSURfY2xhaW1fdjE...",
  "claim_confidence": 0.93,
  "measurement_task_id": "icm_install_v3",
  "claim_ts_ms": 1777500906201,
  "claim_expiry_ts_ms": 1777502706201,
  "policy_version": "claim_policy_apuid_click_v2",
  "claim_reason_code": "MATCHED_ODM_AND_COMPAT_CLICK_ID_ALLOWED",
  "request_accepted": true,
  "match_type": "on_device_psm",
  "mmp_visible_handle_mode": "apuid_click_id",
  "ad_platform_user_id": "APUID_v1_adv120045_app9001002003_7d3a",
  "opaque_click_id": "clk_v1_Ea9b8QYy2r9oGx9B_compact_ptr",
  "creative_id": 74019912,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "touch_time_bucket": 4933923
}
```

这里的 `opaque_click_id` 可以是短密文或 server-side pointer；MMP 只能存储和回传，不能从中得到 `req_id`、device material、bucket tag/tail 或 row key。

Privacy-max 版本可以降级为 Option 3，只返回 opaque claim receipt：

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "claim_status": "CLAIMED",
  "claim_token": "opaque_claim_token_v1",
  "claim_confidence": 0.91,
  "measurement_task_id": "icm_install_v3",
  "creative_id": 74019912,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "touch_time_bucket": 4933923,
  "match_type": "opaque_claim_only"
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
  "confirm_attempt_ts_ms": 1777500907120,
  "mmp_touch_token": "AMT_v1_7ec3b6bd1c4a1f29999ae73f8c6c0d12",
  "mmp_visible_handle_mode": "tracking_link_touch_token",
  "partner": "ExampleMMP",
  "adv_app_id": "com.example.game",
  "event_name": "first_open",
  "event_ts_ms": 1777500905123
}
```

Option 2A 的 Confirm 形态：

```json
{
  "mmp_event_id": "mmp_evt_01JTRP7V8W5T7A8Y4A8V2P",
  "claim_token": "base64:QVBVSURfY2xhaW1fdjE...",
  "final_decision": "WIN",
  "confirm_ts_ms": 1777500907120,
  "winning_touch_ts_ms": 1777500009231,
  "winning_network": "example_ad_network",
  "confirm_idempotency_key": "confirm_01JTRP7V8W5T7A8Y4A8V2P",
  "confirm_attempt_ts_ms": 1777500907120,
  "mmp_visible_handle_mode": "apuid_click_id",
  "ad_platform_user_id": "APUID_v1_adv120045_app9001002003_7d3a",
  "opaque_click_id": "clk_v1_Ea9b8QYy2r9oGx9B_compact_ptr",
  "partner": "ExampleMMP",
  "adv_app_id": "com.example.game",
  "event_name": "first_open",
  "event_ts_ms": 1777500905123
}
```

AdNetwork Server 处理逻辑：

```python
def handle_confirm(req):
    claim = verify_claim_token(req.claim_token)
    assert claim.adv_app_id == req.adv_app_id
    assert claim.partner == req.partner
    assert claim.event_name == req.event_name
    assert not expired(claim)
    assert not replayed(claim.nonce)

    if req.mmp_visible_handle_mode == "apuid_click_id":
        assert claim.ad_platform_user_id == req.ad_platform_user_id
        assert claim.opaque_click_id == req.opaque_click_id
        row = ClickIdIndex.get(req.opaque_click_id)
    else:
        assert claim.mmp_touch_token == req.mmp_touch_token
        row = TouchTokenIndex.get(req.mmp_touch_token)

    assert row is not None

    emit_conversion({
        "server_request_id": row.server_request_id,
        "req_id": row.req_id,
        "creative_id": row.creative_id,
        "campaign_id": row.campaign_id,
        "ad_group_id": row.ad_group_id,
        "event": req.event_name,
        "event_ts_ms": req.event_ts_ms,
        "attributed_by": req.partner,
        "feature_ptr": row.feature_ptr
    })
```

关键点：`req_id` 只在 AdNetwork Server 内部恢复，用于 optimization feature join；MMP 不看到它。

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
  "compatibility_odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
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
  "failure_reason_code": "",
  "mmp_touch_token": "AMT_v1_7ec3b6bd1c4a1f29999ae73f8c6c0d12"
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

### 9.10A Google-compatible first_open / downstream conversion contract

下面这组字段不是 ODM core protocol 本身，而是为了兼容当前 Google App Conversion / ICM 接口必须落地的 partner contract。RFC 必须显式写出这些字段，因为它们决定了 app、MMP、Ad Network、compat gateway 到 confidential plane 之间究竟如何透传数据。

`first_open` 示例：

```json
{
  "request_contract_id": "google_app_conversion_first_open_v4",
  "http_method": "POST",
  "path": "/pagead/conversion/app/1.1",
  "query": {
    "dev_token": "Z_eErE4DkvcKjDM1OVE4c4",
    "link_id": "31FF8D67E5BB5DD5029DCC2734C2F884",
    "app_event_type": "first_open",
    "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
    "id_type": "idfv",
    "rdid": "CCB300A0-DE1B-4D48-BC7E-599E453B8DD4",
    "ctry_c": "US",
    "eea": 0,
    "ad_user_data": 1,
    "ad_personalization": 1,
    "lat": 0,
    "app_version": "8.3.1",
    "os_version": "18.1",
    "sdk_version": "mmp-ios-8.1.0",
    "timestamp": 1777500905.123456
  },
  "headers": {
    "User-Agent": "ExampleMMP/8.1.0 (iOS 18.1; en_US; iPhone16,2; Build/22B82; Proxy)",
    "X-Forwarded-For": "203.0.113.24",
    "Content-Type": "application/json; charset=utf-8"
  },
  "body": {
    "app_event_data": {
      "install_source": "app_store",
      "sdk_flow": "icm_first_open"
    }
  }
}
```

`purchase` 示例：

```json
{
  "request_contract_id": "google_app_conversion_purchase_v4",
  "http_method": "POST",
  "path": "/pagead/conversion/app/1.1",
  "query": {
    "dev_token": "Z_eErE4DkvcKjDM1OVE4c4",
    "link_id": "31FF8D67E5BB5DD5029DCC2734C2F884",
    "app_event_type": "ecommerce_purchase",
    "odm_info": "XYZr_AB8C-_zGtKjUhqtzPLeQ8lbJB5dADVR0tpZ9f...",
    "id_type": "idfv",
    "rdid": "CCB300A0-DE1B-4D48-BC7E-599E453B8DD4",
    "ctry_c": "US",
    "eea": 0,
    "ad_user_data": 1,
    "ad_personalization": 1,
    "lat": 0,
    "app_version": "8.3.1",
    "os_version": "18.1",
    "sdk_version": "mmp-ios-8.1.0",
    "timestamp": 1777504507.123456,
    "fot": 1777500905.123456,
    "value": 4.99,
    "currency_code": "USD"
  },
  "headers": {
    "User-Agent": "ExampleMMP/8.1.0 (iOS 18.1; en_US; iPhone16,2; Build/22B82; Proxy)",
    "X-Forwarded-For": "203.0.113.24",
    "Content-Type": "application/json; charset=utf-8"
  },
  "body": {
    "app_event_data": {
      "sku": "gem_pack_1",
      "store": "app_store",
      "order_bucket": "lt_10_usd"
    }
  }
}
```

字段级约束：

- `odm_info` 是 ICM / ODM 兼容层的 bridge object。它必须缓存并复用于 downstream conversions，但不能进入 optimization features，也不能二次演化为 durable user identifier。
- `id_type` 与 `rdid` 属于 partner-required compatibility fields。它们可以经过 compat gateway，但默认不得进入训练样本；若 ATT 未授权或 advertising id 不可用，应允许使用 partner contract 允许的 fallback，并保留全零 UUID 之类的 partner-specified sentinel value。
- `ctry_c`、`eea`、`ad_user_data`、`ad_personalization` 不只是“请求参数”，也是 release policy input。它们决定 compat 请求是否可发、可发到哪里，以及返回结果可否用于哪些 reporting surfaces。
- `fot` 只应在 `first_open` 之后的 session / post-install conversions 中携带，用来把下游事件绑定到同一安装上下文，而不是做通用跨事件追踪键。
- `User-Agent`、`X-Forwarded-For`、`rdid`、`ad_event_id` 都属于 compat plane 或 debugging plane 可见字段；它们进入内部系统后必须先映射成 policy-scoped facts，不得直接进入 optimization join。
- `app_event_data` 可以承载业务维度，但必须遵守 allowlist；禁止把原始 `ip`、`boot_time_ms`、`device_fp_hash`、`odm_info`、`claim_token` 重新塞回 JSON body。

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
  "device_authenticity_bucket": "attested",
  "supply_path_quality_bucket": "verified_seller",
  "device_attestation_policy_id": "touch_quality_attestation_v1",
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
  "decision_policy_id": "decision_policy_v3",
  "eligible_click_count": 1,
  "eligible_impression_count": 1,
  "srn_partner_id": "appsflyer",
  "claim_path": "ODM_EVENT_DATA",
  "total_candidate_count": 11,
  "winner_engagement_type": "ENGAGED_CLICK",
  "raw_candidate_metric_source": "MIXED"
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
  "feedback_policy_id": "feedback_publish_v2",
  "currency_code": "USD",
  "srn_partner_id": "appsflyer",
  "feedback_revision_id": "fb_rev_01JTRQH4D8F9AM4GQ3YB4A1M3S",
  "observation_window_sec": 604800,
  "value_source": "EVENT_VALUE"
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
    "device_authenticity_bucket",
    "supply_path_quality_bucket",
    "request_hour_bucket",
    "geo_cluster_id"
  ],
  "feature_vector_ref": "fv://trainer-ready/2026-04-29/922337203600012345",
  "sample_weight_policy_id": "sample_weight.purchase_quality_v2",
  "sample_weight_micros": 1000000,
  "decision_id": "dec_01JTRPF2VY9T21Q2FJAA1K8M7X",
  "srn_partner_id": "appsflyer",
  "feedback_snapshot_ts_ms": "1761795105123",
  "training_privacy_policy_id": "tpp_semi_sensitive_ads_v1",
  "feature_sensitivity_manifest_id": "fsm_20260511_request_opt_v1"
}
```

### 9.15 incrementality calibration 与 privacy-control propagation

归因 mock payload 只能说明“这次 request 被确认为 winner”。要让 bidder 真正做长期优化，还需要把这个 winner label 映射到“预期增量价值”。下面的对象是 campaign / creative-family 粒度的校准记录，不是 user-level 明细。

```json
{
  "schema_version": "incrementality_calibration_record.v1",
  "calibration_id": "cal_20260509_cmp_74012091_d7",
  "measurement_task_id": "icm_purchase_7d_v3",
  "advertiser_id": 120045,
  "campaign_id": 74012091,
  "creative_family_id": 920044,
  "calibration_level": "campaign_week",
  "experiment_provenance": "PIE_MODEL",
  "experiment_id": "rct_pool_meta_2026q1_2226",
  "holdout_policy_id": "geo_holdout_policy_v2",
  "post_determined_feature_snapshot_id": "pief://campaign-week/2026-05-03/74012091",
  "post_determined_features": {
    "attributed_conversion_count": 1280,
    "test_group_outcome_count": 1840,
    "exposure_count": 420000,
    "exposure_rate_micros": 420000,
    "last_click_share_micros": 681000,
    "aggregate_quality_bucket": "Q3"
  },
  "predicted_incrementality_micros": 730000,
  "incrementality_weight_micros": 760000,
  "calibration_model_id": "pie_lightgbm_v1_202604",
  "calibration_library_hint": "lightgbm",
  "valid_from_ts_ms": 1777824000000,
  "expires_ts_ms": 1778428800000,
  "release_scope": "optimization_calibration_only"
}
```

训练样本消费时推荐只取下面这种低敏引用：

```json
{
  "server_request_id": 91833720368540001,
  "label_policy_id": "label_policy.purchase_7d_v2",
  "is_attributed": true,
  "credit_fraction_micros": 1000000,
  "calibration_id": "cal_20260509_cmp_74012091_d7",
  "incrementality_weight_micros": 760000,
  "calibration_snapshot_ts_ms": 1777824000000
}
```

下面是隐私控制传播的 mock。它展示的是“用户或法规信号如何影响 artifact / token / feature release”，不是归因查询。

```json
{
  "schema_version": "privacy_control_propagation_record.v1",
  "control_signal_id": "pcs_01JTZ2K8CEW8AJ9P3N7RA0QZ6X",
  "source_system": "gpp_ddrf_gateway",
  "request_type": "DELETE",
  "jurisdiction_scope": "US-CA",
  "gpp_string_digest": "sha256:7fd8c4b1c2e7...",
  "gpp_section_ids": ["usca"],
  "ddrf_request_id": "ddrf_20260509_000145",
  "subject_user_id_int64": 922337203600012345,
  "subject_match_key_digest": "sha256:2c01b1e8f5aa...",
  "affected_token_types": [
    "mmp_touch_token",
    "claim_token",
    "odm_info",
    "debug_trace_window"
  ],
  "affected_plane_ids": [
    "confidential",
    "optimization"
  ],
  "action": "SUPPRESS_RELEASE",
  "effective_ts_ms": 1778342400000,
  "received_ts_ms": 1778342408123,
  "propagation_deadline_ts_ms": 1778428800000,
  "propagation_status": "IN_PROGRESS",
  "audit_log_ref": "audit://privacy-controls/2026-05-09/pcs_01JTZ2K8CEW8AJ9P3N7RA0QZ6X"
}
```

这个例子里 `subject_user_id_int64` 是广告主一方的 first-party user id，不是 ad network 用于跨 app 追踪的用户 ID。Ad network 侧应只通过 policy-bound digest / token map 找到受影响的 request、feature release 和 debug trace window。

### 9.16 multi-ID private match 与 streaming DP release

下面这个 mock 展示“广告主 App / MMP / Ad Network 都有一些可用标识符，但不把它们合成一个万能 ID”的生产形态。`advertiser_user_id:int64` 可以存在，但它只在 advertiser first-party 范围内使用；OPRF/PSM 看到的是 task-bound material。

```json
{
  "private_match_policy_id": "pmatch_20260510_icm_install_v1",
  "measurement_task_id": "icm_install_v3",
  "advertiser_id": "120045",
  "app_bundle": "com.example.game",
  "identifier_sources": [
    {
      "identifier_type": "email_sha256",
      "source_plane": "advertiser_first_party",
      "normalization_policy_id": "email_lower_trim_sha256_v2",
      "availability_policy_id": "signed_in_only",
      "may_leave_device_raw": false,
      "may_enter_mmp": false,
      "may_enter_optimization": false
    },
    {
      "identifier_type": "idfv",
      "source_plane": "mmp_compat",
      "normalization_policy_id": "uuid_lowercase_v1",
      "availability_policy_id": "ios_att_independent_idfv",
      "may_leave_device_raw": true,
      "may_enter_mmp": true,
      "may_enter_optimization": false
    },
    {
      "identifier_type": "odm_info",
      "source_plane": "device_raw",
      "normalization_policy_id": "opaque_passthrough_v1",
      "availability_policy_id": "google_icm_event_data_region_allowed",
      "may_leave_device_raw": true,
      "may_enter_mmp": true,
      "may_enter_optimization": false
    },
    {
      "identifier_type": "gclid",
      "source_plane": "adnetwork_touch",
      "normalization_policy_id": "case_sensitive_click_id_v1",
      "availability_policy_id": "deeplink_or_referrer_only",
      "may_leave_device_raw": true,
      "may_enter_mmp": true,
      "may_enter_optimization": false
    }
  ],
  "matching_protocol": "reversed_oprf",
  "oprf_suite_id": "voprf_rfc9497_p256_sha256",
  "blind_key_epoch_id": "oprf_epoch_2026_05_w02_us_ios",
  "key_rotation_policy_id": "blind_key_rotate_weekly_partner_app_v1",
  "linkage_guardrail_id": "task_scoped_no_cross_identifier_join_v1",
  "intersection_release_policy_id": "release_claim_token_or_dp_count_only_v1",
  "dp_intersection_size_policy_id": "dp_intersection_size_eps_0_25_v1",
  "max_identifier_types_per_event": 3,
  "max_candidate_rows_per_bucket": 1024,
  "fallback_policy_id": "encrypted_relay_requires_legal_exception_v1",
  "audit_manifest_digest": "sha256:138c2e3a6a91..."
}
```

一次 aggregate release 则应该像下面这样声明 DP 语义，而不是只在报表任务名字里写 `dp=true`：

```json
{
  "streaming_dp_plan_id": "sdp_20260510_install_daily_v1",
  "measurement_task_id": "agg_install_campaign_day_v4",
  "metric_name": "install_count",
  "attribution_rule_id": "winner_only_click_through_install_v2",
  "dp_subject_unit": "app_instance",
  "dp_adjacency_relation": "bounded_events_per_user",
  "contribution_bounding_scope": "per_user_per_campaign_day",
  "contribution_enforcement_point": "aggregate_collector",
  "release_slot_granularity": "daily",
  "release_slot_start_ts_ms": 1778371200000,
  "release_slot_end_ts_ms": 1778457600000,
  "budget_scope_id": "advertiser_120045_campaign_day_us",
  "epsilon_micros": 500000,
  "delta_nanos": 1,
  "noise_family": "non_iid_streaming",
  "noise_power_allocation_id": "adsbpc_global_noise_power_plan_v1",
  "streaming_state_ref": "sdp://state/2026-05-10/adv-120045/install",
  "dp_audit_profile_id": "dp_auditorium_streaming_ads_v1",
  "release_lifecycle_state": "reserved"
}
```

这两个对象解决的是两个不同问题：`MultiIdentifierPrivateMatchPolicy` 保护私密匹配不要变成跨标识符追踪；`StreamingDpReleasePlan` 保护公开 aggregate release 不要变成实时、重复、无预算的明细旁路。二者都不允许把 `server_request_id` 或 `claim_token` 暴露给 MMP 之外的新消费方。

### 9.17 optimization training privacy policy

下面这个 mock 展示 request-level optimization 如何保留足够细粒度，同时不把“所有训练字段都同等敏感”或“所有字段都公开”作为偷懒前提。这里的 `known_feature_names` 是 ad network 已经因广告请求持有的上下文；`semi_sensitive_feature_names` 是从 PII 或本地设备信号派生出来、但已被 bucket 化的字段；`protected_label_names` 是归因和后续 purchase feedback。

```json
{
  "training_privacy_policy_id": "tpp_semi_sensitive_ads_v1",
  "training_task_id": "bidder_purchase_value_d7_us_ios_v4",
  "trainer_policy_id": "trainer_policy.purchase_value_v3",
  "model_family": "LIGHTGBM",
  "privacy_profile": "SEMI_SENSITIVE_DP",
  "privacy_unit": "advertiser_user",
  "adjacency_relation": "replace_sensitive_feature_bundle",
  "known_feature_names": [
    "campaign_id",
    "creative_id",
    "placement_id",
    "request_hour_bucket",
    "auction_price_bucket",
    "mmp_partner_id",
    "claim_path"
  ],
  "semi_sensitive_feature_names": [
    "network_stability_bucket",
    "timezone_consistency_bucket",
    "reinstall_hint_bucket",
    "ip_churn_bucket",
    "boot_time_freshness_bucket",
    "device_authenticity_bucket",
    "supply_path_quality_bucket"
  ],
  "protected_label_names": [
    "is_attributed",
    "purchase_value_7d_bucket",
    "retention_d1"
  ],
  "prohibited_raw_feature_names": [
    "raw_ip",
    "boot_time_ms",
    "user_agent",
    "device_fp_hash",
    "odm_info",
    "claim_token"
  ],
  "feature_sensitivity_manifest_id": "fsm_20260511_request_opt_v1",
  "dp_accountant_id": "rdp_accountant_ads_train_v2",
  "epsilon": 4.0,
  "delta": 0.00000001,
  "noise_multiplier": 1.15,
  "clipping_norm": 1.0,
  "clipping_policy_id": "per_example_clip_1p0_sparse_dense_split_v1",
  "sampling_policy_id": "poisson_user_level_sampling_v2",
  "privacy_audit_profile_id": "dp_auditorium_ads_training_v1",
  "empirical_privacy_eval_id": "epv_eval_20260511_purchase_d7_shadow",
  "library_profile": "jax_privacy_shadow_eval",
  "release_gate": "shadow",
  "dp_sampling_method": "poisson",
  "dp_accounting_method": "rdp_poisson",
  "empirical_privacy_audit_schedule": "model_family_gate",
  "empirical_privacy_risk_profile": "medium"
}
```

这个对象有两个工程作用：

- 它允许 Phase 1 继续使用 `LightGBM` / `XGBoost` 做 request-level baseline，但明确标注 `NO_DP_BASELINE`，不伪装成 DP。
- 它为 Phase 2 的 DP 训练留出可执行升级路径：先把 feature sensitivity manifest 固定，再选择 `LABEL_DP`、`SEMI_SENSITIVE_DP` 或 `FULL_USER_LEVEL_DP`，最后用现成库和审计栈跑 shadow / online gate。

### 9.18 measurement utility experiment

下面这条 mock 不是 attribution row，而是隐私 profile 的上线评估记录。它用于回答一个生产问题：更隐私的路径是否在当前 partner / SDK / region / supply 覆盖下足够可用，以及是否需要 fallback。

```json
{
  "experiment_id": "mue_20260514_icm_odm_coldstart_us_ios_v1",
  "measurement_task_id": "icm_install_v3",
  "platform_surface": "google_icm_ios_odm",
  "privacy_profile": "semi_sensitive_dp",
  "treatment_profile_id": "odm_psm_payload_feature_policy_v4",
  "baseline_profile_id": "device_id_or_gclid_compat_v2",
  "causal_design": "geo_experiment",
  "traffic_scope": "us_ios_non_att_optin_coldstart_publishers_eligible",
  "start_ts_ms": 1778716800000,
  "end_ts_ms": 1779321600000,
  "impression_count": 240000000,
  "click_count": 3100000,
  "conversion_count": 185000,
  "attribution_observability_delta_ratio": 0.118,
  "revenue_delta_ratio": -0.012,
  "cpa_delta_ratio": -0.041,
  "roas_delta_ratio": 0.032,
  "latency_p95_delta_ms": 18.4,
  "impression_delivery_delta_ratio": -0.003,
  "adoption_state": "partner_beta",
  "query_budget_policy_id": "budget_sched_w3c_attr_v1",
  "sensitive_signal_policy_id": "sens_sig_install_coldstart_v1",
  "decision": "ship_with_gate",
  "decision_note": "Enable for eligible iOS ODM partners and cold-start cohort; keep device-id/gclid fallback where consent and contract permit."
}
```

这个对象的意义是把 trade-off 从争论变成数据：

- 如果 `latency_p95_delta_ms` 上升导致 `impression_delivery_delta_ratio` 明显变差，SDK / auction path 要先治理延迟，而不是把收入下降归因给 privacy 本身。
- 如果 `adoption_state=partner_beta`，结果只能支持 gated rollout，不能直接支持全量迁移。
- 如果 cold-start cohort 收益明显、老用户 cohort 无收益，`DeviceSensitiveSignalPolicy.cold_start_gate` 应该收紧，而不是继续长期采集 location-like signal。

### 9.19 conformance profile

下面这条 mock 把前面所有对象收敛成一份实施声明。它适合进入 rollout review、partner certification、internal privacy review 和 incident response runbook。

```json
{
  "conformance_profile_id": "conf_20260517_ios_icm_profile_b_v1",
  "measurement_task_id": "icm_install_v3",
  "advertiser_id": "120045",
  "app_bundle": "com.example.game",
  "platform": "ios",
  "profile_level": "PROFILE_B_DEFAULT",
  "mmp_partner_id": "appsflyer",
  "srn_contract_id": "srn_ask_claim_confirm_v3_appsflyer_googleicm",
  "sdk_compat_profile_id": "ios_odm_sdk_or_firebase_11_14_plus",
  "request_level_join_mode": "server_request_id_internal_only",
  "request_level_optimization_enabled": true,
  "optimization_privacy_mode": "no_dp_confidential",
  "public_reporting_privacy_mode": "aggregate_dp",
  "required_protocol_objects": [
    "AdRequestContext",
    "DeviceSensitiveSignalPolicy",
    "DeviceSensitiveSignalDerivationRecord",
    "MmpAskRequest",
    "ClaimResponse",
    "MmpConfirmRequest",
    "RequestScopedOptimizationLabel",
    "AttributionHandshakeState",
    "SdkMeasurementRuntimeTrace",
    "TrainingPrivacyPolicy",
    "AggregateBudgetSchedulerPolicy",
    "MeasurementUtilityExperimentRecord"
  ],
  "required_policy_objects": [
    "sens_sig_install_coldstart_v1",
    "claim_policy_v5",
    "retain_raw_1h_confidential_derived_30d",
    "debug_no_raw_sensitive_v2",
    "budget_sched_w3c_attr_v1"
  ],
  "prohibited_field_names": [
    "raw_ip",
    "boot_time_ms",
    "device_fp_hash",
    "oprf_input",
    "oprf_output",
    "odm_info",
    "claim_token",
    "raw_attestation_token"
  ],
  "sensitive_signal_policy_ids": [
    "sens_sig_install_coldstart_v1"
  ],
  "training_privacy_policy_id": "tpp_no_dp_baseline_block_raw_pii_v1",
  "aggregate_budget_scheduler_policy_id": "budget_sched_w3c_attr_v1",
  "streaming_dp_plan_id": "sdp_20260510_install_daily_v1",
  "utility_experiment_id": "mue_20260514_icm_odm_coldstart_us_ios_v1",
  "approved_library_profiles": [
    "protobuf_buf_schema_v2",
    "cloudflare_circl_voprf_or_equivalent_audited",
    "lightgbm_request_level_baseline",
    "opendp_or_google_dp_aggregate_release",
    "dp_auditorium_release_gate"
  ],
  "crypto_suite_policy_id": "voprf_rfc9497_p256_sha256_epoch_weekly_v1",
  "runtime_trace_requirement": "required",
  "derivation_record_requirement": "required",
  "fallback_policy_id": "fallback_partner_compat_no_training_raw_pii_v1",
  "rollout_gate": "partner_beta",
  "break_glass_policy_id": "support_grant_rotate_debug_keys_v2",
  "conformance_test_suite_id": "odm_rfc_conformance_ios_v20260517",
  "audit_manifest_digest": "sha256:8f9f84b8a1d7c3e0...",
  "effective_from_ts_ms": 1778976000000,
  "expires_ts_ms": 1781568000000
}
```

这条声明的重点不是“我们实现了所有最强隐私技术”，而是把生产事实说清楚：

- request-level optimization 已启用，但 join key 只在 Ad Network 内部。
- optimization plane 目前是 `no_dp_confidential`，不是严格 DP。
- 对外 aggregate reporting 已要求 budget scheduler / streaming DP plan。
- iOS ICM / ODM 的 SDK、runtime trace、`odm_info` 缺失原因和 fallback 都被纳入审计。
- 禁止字段列表可被 conformance test 自动扫描，避免 raw PII 通过日志、训练样本或 partner compat 表外流。

### 9.20 launch / clock evidence

下面这条 mock 展示如何把 `boot_time` 与 app launch time 纳入 attribution 准确性证据，同时不把它们变成 MMP 或 trainer 可见的 raw fingerprinting material。

```json
{
  "launch_clock_evidence_id": "lce_20260519_ios_install_000001",
  "measurement_task_id": "icm_install_v3",
  "platform": "ios",
  "app_bundle": "com.example.game",
  "sdk_instance_id": "sdk_inst_9f21a4",
  "server_request_id": "918273645546372819",
  "app_process_start_wall_ts_ms": "1779206400112",
  "sdk_init_wall_ts_ms": "1779206400264",
  "first_open_event_wall_ts_ms": "1779206401198",
  "monotonic_elapsed_ms_at_sdk_init": "184",
  "monotonic_elapsed_ms_at_first_open": "1118",
  "sdk_init_delay_ms": "152",
  "capture_point": "didFinishLaunchingWithOptions",
  "first_session_delay_state": "inactive",
  "clock_quality_bucket": "launch_0_250ms",
  "raw_boot_time_policy_id": "sens_sig_boot_time_no_release_v1",
  "raw_boot_time_collected": true,
  "raw_boot_time_released": false,
  "derived_clock_buckets": [
    "launch_0_250ms",
    "first_open_1s_bucket",
    "timezone_offset_-0700"
  ],
  "allowed_release_surfaces": [
    "device_derivation_only",
    "runtime_trace_sampled",
    "trainer_bucket_clock_quality"
  ],
  "prohibited_release_surfaces": [
    "mmp_payload",
    "claim_response",
    "bi_raw_logs"
  ],
  "side_channel_mitigation": "constant_path",
  "consent_snapshot_id": "consent_eea_not_applicable_us_ca_v3",
  "derivation_record_id": "dsdr_20260519_ios_install_000001",
  "trace_id": "trace_odm_20260519_001",
  "record_created_ts_ms": "1779206401308"
}
```

注意：Protobuf JSON 里 `int64` 建议编码成字符串，避免 JS / BigQuery JSON 解析时丢精度。类型契约仍然是 `int64`。

### 9.21 ecosystem privacy composition record

下面这条 mock 把 advertiser app、MMP/AAP、SRN、Ad Network optimization 和 aggregate reporting 放到同一张端到端风险表里。它不是一个新的归因 API，而是 rollout review / privacy review / incident response 都能消费的审计对象。

```json
{
  "composition_record_id": "ecr_20260519_ios_icm_profile_b_v1",
  "measurement_task_id": "icm_purchase_v4",
  "conformance_profile_id": "conf_20260517_ios_icm_profile_b_v1",
  "advertiser_id": "120045",
  "app_bundle": "com.example.game",
  "mmp_partner_id": "appsflyer",
  "advertiser_user_id": "48293102736498123",
  "server_request_id": "918273645546372819",
  "mmp_conversion_id": "conv_af_20260519_000019",
  "composed_surfaces": [
    "adnetwork_sdk_observation",
    "google_odm_info_string",
    "mmp_ask",
    "adnetwork_claim",
    "mmp_confirm",
    "request_scoped_optimization_label",
    "aggregate_dp_report"
  ],
  "raw_sensitive_inputs": [
    "advertiser_user_id_int64",
    "raw_ip",
    "boot_time_ms",
    "app_launch_wall_ts_ms",
    "install_referrer_hint"
  ],
  "derived_sensitive_outputs": [
    "task_scoped_user_token",
    "ip_geo_country_us",
    "launch_clock_quality_launch_0_250ms",
    "odm_event_data_ephemeral",
    "purchase_value_bucket_50_100"
  ],
  "external_release_surfaces": [
    "mmp_touch_token",
    "claim_token",
    "creative_ref",
    "odm_info_to_aap_s2s",
    "aggregate_report_campaign_day"
  ],
  "internal_release_surfaces": [
    "server_request_id",
    "RequestScopedOptimizationLabel",
    "OptimizationTrainingRow.feature_buckets",
    "fraud_quality_bucket"
  ],
  "residual_leakage_channels": [
    "mmp_observes_winner_network",
    "aap_event_level_icm_reporting",
    "creative_level_reporting",
    "launch_clock_quality_bucket",
    "aggregate_release_repetition"
  ],
  "non_composing_privacy_claims": [
    "odm_keeps_identifiable_info_on_device",
    "srn_claim_response_is_yes_no_or_scoped_token",
    "public_aggregate_report_uses_dp_budget"
  ],
  "required_gates": [
    "clock_evidence_required",
    "forbidden_field_scan",
    "claim_token_replay_cache",
    "aggregate_budget_scheduler",
    "composition_review_required"
  ],
  "composition_privacy_statement": "contextual_scope_enforced_no_end_to_end_dp_claim",
  "optimization_release_mode": "request_level_internal",
  "public_reporting_mode": "aggregate_dp",
  "decision": "ship_with_gates",
  "reviewer": "privacy-ads-measurement-review",
  "created_ts_ms": "1779206410000"
}
```

这条记录刻意把 `advertiser_user_id:int64`、`server_request_id:int64` 和 `raw_ip` 放在同一个 mock 里，是为了说明类型和边界，而不是建议把它们合并成一个万能 user row。实际生产中：

- `advertiser_user_id` 只能在 advertiser / MMP 合同允许的范围内使用；进入 Ad Network 前应变成 task-scoped token 或 aggregate feature。
- `server_request_id` 只能留在 Ad Network 内部，用于 Confirm 后恢复 request-level label。
- `raw_ip` 与 `boot_time_ms` 只能用于端侧或 confidential derivation，不能进入 MMP payload、普通日志或 trainer raw feature。
- `residual_leakage_channels` 必须被承认和 gate，而不是用 “privacy-preserving” 一句话盖掉。

## 10. 敏感 PII 如何流动

### 10.1 原则

- 原始 `boot_time`、原始 `ip`、完整 `User-Agent`、长期稳定设备标识 `MUST NOT` 进入普通 BI、通用日志或通用湖仓。
- 如果协议兼容需要把某些字段传给外部 API，这些字段也 `MUST NOT` 自动下沉到 optimization plane。
- “为了兼容 partner API 先缓存一下” 不等于 “这个字段可以成为训练特征”。
- 任何从 `boot_time`、`ip`、location-like signal、AAID/IDFA 或 install referrer 派生的字段，都必须能追到 `DeviceSensitiveSignalPolicy`；否则视为未授权派生物。
- 不要写 “no PII leaves device”。推荐写法是：raw device identifiers and raw fingerprinting material do not leave the AdNetwork SDK process；MMP 可能根据 legal option 收到 scoped pseudonymous attribution material。

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
  - precise location / high-precision IP geo
  - 完整 `User-Agent`
  - 只允许留在设备侧或 confidential plane
- `egress-only compatibility`
  - `rdid`
  - `X-Forwarded-For`
  - `ad_event_id`
  - `odm_info`
  - raw device attestation token / platform attestation blob
  - 允许短期缓存用于 partner API，但 `MUST NOT` 进入训练特征表
- `optimization-safe derived`
  - `network_stability_bucket`
  - `ip_churn_bucket`
  - `same_country_as_touch`
  - `coarse_region_bucket`
  - `reinstall_hint_bucket`
  - `boot_time_freshness_bucket`
  - `device_authenticity_bucket`
  - `supply_path_quality_bucket`
  - 允许进入 optimization plane，但必须有 `feature_policy_id`
- `aggregate-only`
  - `metric_name`
  - `metric_value`
  - `aggregation_key`
  - 只允许以 bounded contribution 形态出现

如果团队发现某个字段同时出现在这四层中的两层以上，默认说明边界设计有问题，需要拆对象，而不是继续打补丁。

位置 / IP 类信号还要额外加一个 cold-start 规则：它们只应在用户行为历史不足、广告请求上下文不足或反作弊需要时释放粗粒度派生桶。2026 的位置数据价值研究说明，地理信号在 cold-start 阶段最有价值；这支持本文把 `cold_start_gate` 写进 policy，而不是把位置/IP 派生物永久化。

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
  - 可以在 confidential plane 派生 `ip_churn_bucket`、`same_country_as_touch` 之类低敏特征
  - 默认不允许进入训练明细或普通数仓
- `rdid`
  - 只在 partner compat contract 需要时短期存在
  - 不得作为内部通用 join key
- `odm_info`
  - 只用于兼容 bridge / compatibility ask 流程
  - 不得进入 trainer row
  - 不得进入长期画像表
  - 若 advertiser app 缓存它用于后续 `purchase` / `session_start` 上报，缓存 TTL 应受 `compat_retention_policy_id` 约束
- `mmp_touch_token`
  - 允许存在于 tracking link、Claim、Confirm 和 MMP click-conversion join
  - 必须绑定 `mmp_partner_id / advertiser_id / adv_app_id / creative_id / touch_time_bucket`
  - TTL 不应超过 attribution window
  - 不得跨 advertiser、app、MMP 或 purpose 复用
  - 不应命名为 `UserID`，避免 reviewer 误解为 network-level user identifier
- `claim_token`
  - 允许 MMP 透传
  - 必须 opaque、single-use、short TTL、anti-replay
  - 不得让 MMP 解出 `req_id`、device material 或 row key
- `ad_event_id`
  - 允许存在于 external response mapping
  - 不得直接进入 bid / ranking / pacing 训练
- `DeviceSupplyPathAttestationReceipt`
  - 允许绑定 `server_request_id` 留在 AdNetwork 内部 quality / fraud plane
  - 原始 token、platform attestation blob、challenge nonce 不得进入 MMP / SRN payload
  - token digest 只用于 replay / audit，不得作为长期设备标识或跨 app join key
  - optimization plane 只可消费 `device_authenticity_bucket`、`supply_path_quality_bucket` 这类派生桶
- `server_request_id`
  - 允许出现在 confidential join 和 optimization label
  - 不得进入 partner-facing payload
  - 不得沉入普通 BI 明细
- `user_id:int64`
  - 若广告主业务必须使用，应该只存在于 advertiser-controlled first-party plane
  - 不得成为 ODM core protocol 的必填字段
  - 不得替代 `server_request_id`

### 10.6 SDK debug log 不能成为 PII 旁路

on-device measurement 的生产事故通常不是协议对象本身泄漏，而是 debug log、SDK trace、crash breadcrumb、MMP integration health 上报把原始字段又带了出去。尤其是 `boot_time_ms`、`raw_ip`、完整 `User-Agent`、install referrer、deep link URL、`odm_info` 和 adapter discovery 结果，很容易被“为了排障”写进通用日志。

推荐把端上日志分成三类：

- `public diagnostic`
  - 只包含状态码、耗时桶、SDK 版本、adapter 是否存在；
  - 可进入 MMP / ad network 的普通集成健康面板。
- `pseudonymized confidential diagnostic`
  - 包含可关联但不可还原的 token，例如 keyed-HMAC 后的 install referrer token、deep link token、IP prefix churn token；
  - 只能进入 confidential debug plane。
- `raw local only`
  - 原始 `ip`、原始 `boot_time_ms`、完整 deep link URL、完整 `User-Agent`、OPRF material；
  - 默认只在设备进程内短期存在，不能上报。

如果确实需要排障关联性，优先采用类似 Proteus 的“生成点保护”思路，而不是上报后再清洗：

1. 日志字段一产生就按 field policy 分类。
2. PII 字段先用设备本地 `K_hash` 做 keyed pseudonymization，`K_hash` 不出设备。
3. pseudonym token 再用时间轮转的 AEAD key 加密，防止跨多次日志快照长期关联。
4. 服务端只在 break-glass / support grant 下拿到某个时间窗的 ratchet state，窗口外不可解。
5. grant 后必须旋转 root / ratchet state，避免 support access 变成持续后门。

这不是要求 Phase 1 必须实现 Proteus 本身，而是要求 RFC 级别把以下字段预留出来：

- `pii_transform_policy_id`
- `log_key_epoch_id`
- `debug_trace_window_id`
- `support_grant_id`
- `post_grant_rotation_required`
- `device_attestation_ref`

落地判断很简单：如果某条 debug trace 离开设备后还能看见原始 IP、完整 deep link、完整 User-Agent、raw boot time 或 `odm_info`，它就不是 “on-device measurement debug”，而是另一个未治理的数据出口。

## 11. 与 MMP / SRN 的协同规范

### 11.1 标准流程

本文默认 SRN 协议抽象为：

1. `MMP Ask`
2. `Ad Network Claim`
3. `MMP Confirm`

### 11.2 Ask 阶段要求

- v3.1 主链路中，Ask 是 `MMP SDK -> AdNetwork SDK` 的薄触发，不应携带 `device_fp_hash` 或 raw device material。
- `odm_info` 只在兼容 MMP / AAP / ICM server-side API 时作为 optional bridge field，不是推荐主流程的 matching input。
- `query_template_id` `MUST` 明确，防止 partner 任意探测。
- `query_hash` `SHOULD` 绑定进 `claim_token`。

### 11.2A Optional SDK discovery and skip semantics

在 iOS 上，MMP SDK `MUST NOT` 对所有 SRN / ad network 盲目广播 Ask。Ask 前必须先完成本地 eligibility 判断：

1. MMP SDK 读取本地 `AdapterRegistry`。
2. registry 中存在该 network adapter，且 adapter 声明 `supports_odm_ask=true`。
3. adapter 版本、ad network SDK 版本、region、consent、remote config 都满足当前 measurement task。
4. MMP SDK 才调用该 adapter 的 `Ask`。

如果上述任一条件不满足，MMP SDK `MUST` 生成本地 `LocalAskEligibilityRecord`，但 `MUST NOT` 调用 ad network SDK / server。

推荐 skip code：

- `ASK_SKIPPED_SDK_NOT_PRESENT`
- `ASK_SKIPPED_ADAPTER_NOT_PRESENT`
- `ASK_SKIPPED_VERSION_UNSUPPORTED`
- `ASK_SKIPPED_REGION_INELIGIBLE`
- `ASK_SKIPPED_CONSENT_DISABLED`
- `ASK_SKIPPED_REMOTE_CONFIG_DISABLED`

这些状态的语义是“本地没有可执行 Ask 的能力”，不是“ad network claim declined”。MMP attribution graph 应把它们记为 integration / eligibility state，而不是 negative attribution evidence。

为了不破坏开发者体验，RFC 推荐 iOS 采用下面的优先级：

- 首选：ad network adapter 显式注册到 MMP SDK 的 `AdapterRegistry`
- 次选：广告主 App 在 `Info.plist` / MMP dashboard 中声明启用 network，MMP SDK 再要求本地 adapter 也存在
- 兜底：`NSClassFromString` 检查已知 adapter class，但只用于兼容旧集成
- 禁止：只因为 MMP server remote config 写了某 network enabled，就在本地无 SDK 的情况下发 Ask 或等待 timeout

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

### 11.5A MMP / AAP-style ICM 接入约束

2026 年的 MMP 产品文档已经说明，ICM / ODM 不是“Google SDK 自己跑完就结束”，而是需要 MMP SDK、Google ODM SDK、广告主 App 初始化顺序和 S2S fallback 一起满足条件。RFC 因此应把 MMP runtime 也建模成协议面的一部分。

以 Singular 当前公开文档为例，生产接入至少暴露出这些约束：

- ICM 在 MMP 侧已是开放 beta / 普遍可接入形态，而不是只存在于 Google Ads UI 内部；
- 当前公开资料显示 Android ICM open beta 自 `2026-03-30` 起面向所有广告主开放，iOS ICM open beta 自 `2025-11-12` 起面向所有广告主开放；这类 rollout 状态应建模为 `icm_platform_rollout_state`，不能藏在 release notes 里；
- iOS ICM 要求集成 Google ODM SDK，并升级 MMP SDK 或 S2S API；
- Singular iOS 原生 SDK 要求 `12.8.1+`，并需要启用 `enableOdmWithTimeoutInterval`；
- 推荐 timeout 示例是 `5s`，这会延迟 SDK initialization，并可能推迟 deep link callback；
- ICM 报告侧可能只覆盖 click-through installs，且某些维度如 sub network type 不可用；这必须进入 `icm_reporting_scope`，不能让下游误以为它覆盖 view-through、re-engagement 或完整 campaign hierarchy；
- Google ICM 在部分 MMP 文档中明确覆盖 iOS 14.5+ ATT declined、Android EEA / ads-personalization opt-out 以及 Kids apps，但不覆盖 iOS EEA/UK region；这些应分别进入 `region_eligibility_code`、`att_authorization_status`、`ads_personalization_status`、`kids_app_policy_state`；
- 如果 ODM SDK 没有产出 `odm_info`，S2S path 应记录并传递 `odm_error` / absence reason，而不是静默降级成 classic attribution；
- Google Ads user-level data retention 在 MMP 侧可能有 6 个月删除要求，retention policy 必须影响 compat record、debug trace 和 user-level reporting，而不只是 BI 展示；
- Singular LDS 会映射到 Google `ad_user_data` / `ad_personalization`，因此 consent mapping 应进入 `PrivacyControlPropagationRecord` 或等价 policy object；
- Android 与 iOS 的区域、allowlist / open-beta 状态、ads personalization 状态不同，不能共用一个 `icm_enabled=true` 布尔字段。

因此 MMP / AAP integration contract `MUST` 显式记录：

- `mmp_sdk_version`
- `odm_sdk_present`
- `odm_sdk_version`
- `odm_fetch_timeout_ms`
- `sdk_init_delay_ms`
- `deep_link_callback_deferred`
- `event_source_system`
- `is_firebase_native_event`
- `region_eligibility_code`
- `icm_reporting_scope`
- `icm_platform_rollout_state`
- `odm_error_code`
- `kids_app_policy_state`
- `user_level_retention_policy_id`
- `partner_consent_mapping_policy_id`

这些字段的消费边界也要写死：

- 可用于 integration health、support ticket、partner QA；
- 可用于解释为什么 `odm_info` 缺失、为什么 Ask skipped、为什么 downstream conversion 没有 ICM path；
- 不得直接进入 bidder / ranking / pacing / ROAS trainer；
- 不得被 MMP 当成 negative attribution evidence；
- 不得替代 `ClaimResponse` 或 `MmpConfirmRequest`。

换句话说，MMP SRN + ODM 的生产形态不是三行公式，而是一个有 timeout、有 SDK 版本、有地区 gating、有 callback 副作用的端到端系统。协议如果不把这些状态字段写出来，排障时就会被迫回到通用日志和人工截图，反而扩大 PII 暴露。

### 11.5B Cross-MMP ICM 集成洞察

把 Singular、AppsFlyer、Branch、Airbridge、Kochava、Tenjin、Adjust 的公开材料放在一起看，可以得到一个更清楚的产品事实：ICM 不是一个“所有 MMP 都照抄同一 SDK 步骤”的集成，而是一组由 Google non-deterministic / modeled claim 驱动、由 MMP 各自落到 attribution waterfall / reporting tier / dashboard 的 partner contract。

| MMP / AAP | iOS 要求 | Android 要求 | 报表语义 | 对 RFC 的含义 |
|---|---|---|---|---|
| Singular | Google ODM SDK + Singular SDK / S2S 更新，推荐 5s ODM timeout | Partner configuration + ICM toggle；Android open beta 后不应要求 App 侧 ODM SDK | click-through install only，probabilistic，sub network type 不可用 | `odm_error`、timeout、retention、consent mapping 必须是 runtime state |
| AppsFlyer | AppsFlyer iOS SDK `6.17.7+`，并集成 Firebase `11.14.0+` 或 standalone Google ODM SDK | Android no SDK update | Google 发送 non-deterministic install claims，AppsFlyer 用自身数据验证；Advanced Data Sharing 决定是否发送无 device ID install | ICM 是 claim + validation，不是 Google 单方最终真值 |
| Branch | Branch iOS SDK `3.13.3+` + Google ODM SDK / Firebase，或 S2S 传 `odm_info` | Android 暂无 immediate actions，measurement improvements 自动应用 | real-time event-level reporting；iOS / Android 都进入 Branch 报表 | Android 更像 backend / partner capability，不像端上 ODM SDK path |
| Airbridge | iOS Native SDK `4.4.1+` 并安装 Google On-Device Event Measurement SDK | Android 对 ACi winning touchpoints 提供 ICM，包含 clicks 和 engaged views | Google privacy-preserving conversion modeling / non-deterministic attribution data | engagement scope 不能硬编码为 click-only；要按 MMP / platform 记录 |
| Kochava | iOS 需要 Firebase / ODM 与 Kochava SDK 更新；S2S 要传 on-device measurement info string | no SDK update；Android modeled attribution 可用性取决于 rollout / allowlist | modeled tier / nondeterministic attribution | waterfall tier 必须进入 `claim_path`，不能混成 deterministic |
| Tenjin | iOS 需要 on-device conversion measurement 和 Tenjin SDK 版本更新 | no actions needed，automatic enablement | enhanced reporting / more real-time attribution | 小型 MMP 也会把 Android 作为自动 backend enablement，而不是 App SDK 工作 |
| Adjust | 公开材料强调 SDK-based 和 S2S 都支持，ICM 进入 probabilistic attribution tier / cross-network reporting | 同样覆盖 Android EEA / opt-out cohorts | event-level visibility, probabilistic tier | ICM 是 cross-network reporting 增强，不是替代 MMP SRN |

综合判断：

1. **iOS 是 ODM SDK / `odm_info` path，Android 是 API / referrer / partner-config path。** 多家 MMP 都写出 iOS 需要 ODM 或 Firebase SDK，Android 则常见为 no SDK update / automatic enablement / partner config。RFC 不能把 Android 建模成“也要装 ODM SDK”。
2. **ICM claim 不是 deterministic attribution。** AppsFlyer 写成 non-deterministic install claims，Singular / Adjust 写成 probabilistic tier，Kochava 写成 modeled tier，Airbridge 写成 non-deterministic attribution data。这些名称不同，但协议语义一致：`claim_path` 应单独标为 `GOOGLE_ICM_NON_DETERMINISTIC` 或等价枚举。
3. **MMP 仍然做 validation / waterfall / prioritization。** AppsFlyer 明确说 Google claim 需要被 AppsFlyer 数据验证；Kochava 说进入 modeled tier；Singular 说进入 probabilistic attribution。ICM 没有消灭 MMP 的 attribution graph，只是新增一类 Google claim。
4. **Android 成败关键是“事件与点击/referrer 上下文是否传够”。** Google request spec 支持 `appsetid`、zeroed `rdid`、`gclid`、`market_referrer_gclid`、`gclid_only_request`、`gbraid`、`ad_user_data`、`ad_personalization`。所以 Android ICM 的工程重点不是装 SDK，而是 deep link / install referrer / conversion API / consent flags 是否完整。
5. **ICM reporting scope 不能写死。** Singular 当前强调 click-through install only；Airbridge 对 Android 写了 clicks + engaged views winning touchpoints；AppsFlyer bulletin 提到 installs 和 re-attributions。RFC 应要求 `icm_supported_engagement_types`、`icm_reporting_scope`、`claim_path` 按 MMP / platform / campaign type 版本化。
6. **“发送所有 install / event” 是 ICM 的隐性前提。** Singular 的 Google SAN 集成要求发送 all installs、sessions 和 configured events；AppsFlyer 的 Advanced Data Sharing 开启后会发送无 device ID installs。RFC 应把 `advanced_data_sharing_enabled`、`receiving_all_installs`、`receiving_all_events` 视为 capability state，而不是 UI 设置。
7. **ICM 输出更适合 optimization explanation，不适合当作因果真值。** MMP 语言普遍是 visibility、modeled/probabilistic/non-deterministic reporting、performance insight；这支持本文前面的拆分：ICM attribution label 进入 request-level feedback，但 incrementality 仍要靠 holdout / PIE-style calibration。

推荐新增 contract 字段：

- `claim_path=GOOGLE_ICM_NON_DETERMINISTIC`
- `mmp_icm_waterfall_tier=probabilistic|modeled|non_deterministic`
- `advanced_data_sharing_enabled:bool`
- `receiving_all_installs:bool`
- `receiving_all_events:bool`
- `icm_supported_engagement_types:string[]`
- `android_sdk_update_required:bool`
- `ios_odm_sdk_required:bool`
- `gclid_capture_enabled:bool`
- `install_referrer_gclid_capture_enabled:bool`
- `gbraid_capture_enabled:bool`

一句话：跨 MMP 对比后，ICM 最值得写进 RFC 的不是“Google 又有一个归因产品”，而是它把 `non-deterministic Google claim -> MMP validation/waterfall -> event-level reporting -> optimization feedback` 变成了一个正式生产路径。

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
- `mmp_touch_token`
  - 生成方: ad network backend
  - 接收方: MMP click log / tracking-link path
  - 使用方: MMP Claim join 与 Confirm 回传
  - 过期负责人: ad network
- `ask_idempotency_key`
  - 生成方: MMP
  - 生命周期负责人: MMP
- `claim_token`
  - 生成方: AdNetwork SDK / ad network confidential service
  - 使用方: MMP confirm
  - 过期负责人: ad network
- `confirm_idempotency_key`
  - 生成方: MMP
  - 生命周期负责人: MMP
- `odm_info`
  - 仅兼容路径需要
  - 生成方: advertiser app 中的 ODM SDK
  - 缓存方: advertiser app 或 advertiser server
  - 透传方: MMP / AAP compatibility surface
  - 过期负责人: advertiser app 与 ad network 共同约束

如果责任不清晰，线上最容易出现三种事故：一是同一 install 被多次问询，二是 `claim_token` 被重放，三是 `odm_info` 或 `mmp_touch_token` 被错误地缓存成长期用户标识。

### 11.9 平台 attribution API 与 SRN 的边界

平台 attribution API 可以增强 reporting 和 reconciliation，但不能被误用为 MMP SRN 主链路的替代品。

**Android:**

- Android Privacy Sandbox Attribution Reporting / `MeasurementManager` `MUST NOT` 成为新的生产主依赖。官方路线已宣布退役 Attribution Reporting API（Chrome / Android），Android API reference 也把 measurement APIs 标为 API 37 deprecated 且无直接替代 API。
- Android 侧的生产 contract 应优先围绕 `Google ICM / App Conversion API / install referrer gclid / gbraid / appsetid / zeroed rdid / consent flags / MMP partner configuration` 建模。
- 如果历史实验或灰度仍产生 Android Privacy Sandbox trace，只能写入 `platform_measurement_api_family=android_privacy_sandbox_measurement_deprecated` 与 `android_privacy_sandbox_measurement_state`，不得让 downstream trainer 把它当稳定 feature source。

**Apple:**

- AdAttributionKit 的 postback copy、conversion tag、geography data 和 configurable attribution rules 应进入 platform postback reconciliation plane。
- `conversion_tag` 是 advertised app 区分重叠 reengagement conversion 的书签，不是跨 app / 跨 network user id。
- postback copy 可以帮助广告主或 MMP/AAP 做报表校验、SKAN/AAK reconciliation 和 geo/campaign calibration，但它不包含 Ad Network 内部 `server_request_id`。
- 如果 Ad Network 需要 personalized optimization，仍然必须等待 `MmpConfirmRequest`，再通过 `mmp_touch_token -> server_request_id` 在受控边界内恢复 request-level label。

因此，本 RFC 的平台兼容策略是：Google ICM、Apple AdAttributionKit、W3C Attribution Level 1 / DAP 都作为可对齐的 measurement surfaces；真正用于 SRN winner 与 request-level optimization 的主对象仍是 `MmpAskRequest`、`ClaimResponse`、`MmpConfirmRequest` 和 `RequestScopedOptimizationLabel`。

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

这里的判断不是“DP 对优化不重要”，而是广告训练数据有两个现实问题：一是正负样本极不平衡，二是稀疏 ID / embedding / bucket feature 很多。Private Ad Modeling with DP-SGD 已经证明 DP-SGD 可以用于 CTR、CVR 和 conversion count 这类广告任务；但它也意味着训练契约必须正视广告数据的 class imbalance 和 sparse gradients，而不是把图像/NLP 里的默认 DP-SGD recipe 直接搬过来。

更实用的分层是：

- Phase 1: `NO_DP_BASELINE`
  - 用 `LightGBM` / `XGBoost` 先把 label contract、right-censoring、delayed feedback 和 sample lifecycle 做稳。
  - 该 profile 只能用于内部优化，不能对外宣称 DP。
- Phase 2: `SEMI_SENSITIVE_DP`
  - 把 campaign、creative、placement、request hour 这类 ad request 上下文视为 known features。
  - 把 `ip_churn_bucket`、`boot_time_freshness_bucket`、`reinstall_hint_bucket`、`device_authenticity_bucket`、purchase label 等视为 protected side。
  - 用 `TrainingPrivacyPolicy` 固化 `known_feature_names`、`semi_sensitive_feature_names` 和 `protected_label_names`。
- Phase 3: `FULL_USER_LEVEL_DP`
  - 仅在确实需要跨广告主、跨 app 或更高保证的训练 release 时启用。
  - 必须先证明 privacy unit、adjacency relation、sampling policy 和 audit profile 都可执行。

如果后续真的把 DP 引入 optimization training，也不要只记录一个 `epsilon/delta` 就结束。2025 的 [Empirical Privacy Variance](https://research.google/pubs/empirical-privacy-variance/) 说明：名义上相同的 DP 保证，在不同超参数下可能表现出不同的经验隐私风险。因此训练契约至少还应固化：

- `dp_accountant_id`
- `noise_multiplier`
- `clipping_norm`
- `sampling_policy_id`
- `privacy_audit_profile_id`
- `empirical_privacy_eval_id`

也就是说，Phase 1 可以不先上 DP；但一旦上，就应把“会计、超参、审计、经验评估、feature sensitivity manifest”一起产品化，而不是只在汇报材料里写一个 epsilon。

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
  - `decision_id`
  - `srn_partner_id`
- lifecycle state
  - `observation_window_sec`
  - `right_censored`
  - `label_ts_ms`
  - `feedback_snapshot_ts_ms`
- policy state
  - `trainer_policy_id`
  - `feature_policy_id`
  - `contribution_policy_id`
- released low-sensitive features
  - `network_stability_bucket`
  - `timezone_consistency_bucket`
  - `reinstall_hint_bucket`
  - `coarse_ip_geo_bucket`
  - `ip_prefix_churn_bucket`
  - `device_authenticity_bucket`
  - `supply_path_quality_bucket`

反过来说，下列字段通常不该进入 optimization plane：

- `odm_info`
- `claim_token`
- `rdid`
- `X-Forwarded-For`
- 完整 `User-Agent`
- partner 返回的原始 `ad_event_id`
- raw device attestation token / token digest / platform attestation blob

### 12.4A 2026 产品现实要求保留“候选量”和“engagement 类型”上下文

2026-03-19 的 AppsFlyer Enhanced attribution 文档已经把一个非常实用的信号公开化了：`total candidates for attribution`。它表示“在 enhanced attribution 和 fraud filtering 生效前，本来会进入竞争的 engagement 数量”。这和只看最终 winner 不是一回事。

这意味着 production RFC 不应只保留 `is_attributed=true/false` 或单一 `winner_reason`，而应至少保留：

- `total_candidate_count`
- `prefilter_candidate_count`
- `eligible_candidate_count`
- `eligible_click_count`
- `eligible_impression_count`
- `winner_engagement_type`
- `flooding_suspected`

否则，优化面会丢失两个关键解释变量：

1. 这次请求为什么赢了；
2. 这次请求所处的竞争环境到底有多“脏”。

同样地，2026-04-19 的 AppsFlyer attribution model 已明确区分 `click-through`、`view-through`、`engaged click`、`engaged view` 等 engagement 形态。对 bidder / pacing / creative ranking 来说，`winner_engagement_type` 往往和后续价值质量直接相关；如果把它压扁成统一的 `click`，训练会把不同意图强度的流量混为一谈。

因此，推荐把 `AttributionDecisionRecord` 视为 optimization plane 的必要输入之一，而不是只把它当作 debug log。

### 12.4B touchpoint quality 不是用户特征

device / supply-path attestation 给 optimization 的价值，是把“伪造设备、伪造 seller、异常 supply path”从真实用户兴趣信号里剥离出来。推荐只以三种方式进入优化面：

- 样本过滤：`attestation_result=FAILED` 且 fraud policy 命中时，样本不进入 conversion quality trainer。
- 样本降权：`attestation_result=MISSING` 或 `UNSUPPORTED` 时，用 `sample_weight_policy_id` 降低权重，但不直接改写 `is_attributed`。
- 分层诊断：按 `device_authenticity_bucket`、`supply_path_quality_bucket` 查看 CPA / CVR / retention 差异，用于 supply 质量治理。

不推荐做法：

- 把 token digest 当作 device key；
- 把 attestation success rate 当作用户画像；
- 把 attestation failure 直接当作 negative conversion label；
- 把 MMP Confirm 之前的 attestation 状态暴露给 MMP 作为 attribution 决策输入。

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

进一步说，如果要支持 production pacing / bidder calibration，而不仅仅是离线 trainer，反馈 ledger 至少还要满足四个要求：

- 同一个 `server_request_id` 可以发布多次 feedback，但每次都必须带 `feedback_revision_id`
- revenue 类 feedback 必须显式带 `currency_code`，不能依赖外部 campaign 配置猜
- trainer / bidder 消费快照时应该固定 `feedback_snapshot_ts_ms`，避免同一批训练样本混入不同观测窗口
- `srn_partner_id` 与 `claim_path` 应能下钻到 request-level 反馈行，便于比较 ODM event-data、first-party data、classic device-id 等路径的真实增益

### 12.7 purchase optimization walkthrough

把一次真实 purchase 优化闭环按时间顺序写开，会更容易看懂为什么要保留这些字段：

1. ad network 在广告触点发生时生成 `server_request_id=922337203600012345` / `req_id`，并把 campaign、creative、placement、geo、consent 写入 touchpoint store。
2. ad network 同步生成 scoped `mmp_touch_token`，通过 tracking link / click log 给到 MMP；内部维护 `mmp_touch_token -> req_id` index。
3. 用户完成安装或 purchase，MMP SDK 捕获事件，并调用 AdNetwork SDK Ask；MMP SDK 不传 `device_fp_hash`。
4. AdNetwork SDK 在本地观察 `boot_time_ms`、`raw_ip`、`timezone_offset_min`、`bundle_first_install_ts_ms` 等本地信号，但不把原值交给 MMP。
5. AdNetwork SDK 与 AdNetwork Server 运行 `config -> psm -> local filtering -> optional validate`，从命中 candidate row 恢复 associated payload。
6. AdNetwork SDK 返回 Claim 给 MMP SDK，推荐包含 `mmp_touch_token + claim_token + creative metadata`，不包含 `req_id`。
7. MMP 在多家 SRN 返回结果之间做 winner selection，然后只对 winner 发 `MmpConfirmRequest`。
8. AdNetwork Server 校验 `claim_token`，再用 `mmp_touch_token -> req_id` 做最终 join，输出：
   - `RequestScopedOptimizationLabel`
   - `ServerFeatureDerivationRecord`
   - `OptimizationFeedbackRecord`
9. trainer materialization 作业按 `server_request_id` / `req_id` 内联 join label 与 feature release，生成 `OptimizationTrainingRow`。
10. 线上 bidding / ranking 系统拿到的是训练安全的 request row，而不是 `device_fp_hash`、`raw_ip`、完整 `User-Agent`、`odm_info` 或 partner `ad_event_id`。

这个 walkthrough 的关键点是：个性化优化依赖的是 request-level 对齐能力，不依赖把原始 PII 长期放进训练面。

### 12.8 attribution label 不是 incrementality truth

`MMP Confirm` 后拿到的 `RequestScopedOptimizationLabel` 适合做监督信号，但它不是因果增量真值。它回答的是：

- 这次 conversion 在 SRN / MMP 规则下归因给谁；
- 哪个 `server_request_id` 应该得到 credit；
- 这条样本是否可以进入 bidder / ranking / creative trainer。

它没有直接回答：

- 如果不展示这次广告，用户是否也会转化；
- campaign 的真实 incremental conversions per dollar 是多少；
- bidder 应该把 last-click label 放大还是降权。

2026-04 修订的 PIE（Predicted Incrementality by Experimentation）研究给了一个更适合生产的折中：用有限 RCT / holdout 的因果真值训练 campaign-level incrementality predictor，再用 non-RCT campaign 的 post-determined aggregate features 去预测增量。这里的关键点是“post-determined features 可以用于预测因果效果，但不能被伪装成因果控制变量”。

因此，optimization plane 推荐拆成三层：

1. `RequestScopedOptimizationLabel`
   - request-level attribution / credit / feedback lifecycle；
   - 用于告诉 trainer 哪次请求赢了、何时赢、赢的置信度和价值。
2. `IncrementalityCalibrationRecord`
   - campaign / creative-family / source-level 的 causal calibration；
   - 用于提供 `incrementality_weight_micros`、`calibration_id`、`experiment_provenance`。
3. `OptimizationTrainingRow`
   - 内部 join 后的训练行；
   - 消费 `is_attributed` 与 `incrementality_weight_micros`，但不消费 raw RCT user rows、raw IP、raw boot time、`odm_info`。

推荐落地方式：

- RCT / geo holdout / conversion lift 实验先进入 causal measurement store。
- 使用 `LightGBM` / `XGBoost` 做 PIE-style calibration baseline；如果需要显式估计异质处理效应或做敏感性分析，再用 `EconML` / `DoWhy` 做离线 causal review。
- calibration feature 只允许 aggregate 或低敏派生字段，例如 `exposure_rate_micros`、`last_click_share_micros`、`aggregate_quality_bucket`、`eligible_candidate_count_p50`。
- request-level trainer 只消费 `calibration_id` 和 `incrementality_weight_micros`，不要把 RCT/control user-level 明细接回 request table。
- bidder / pacing 初期把 calibration 当作 sample weight 或 campaign prior，而不是直接覆盖原始 attribution label。

不推荐做法：

- 把 `is_attributed=true` 当成 `incremental=true`；
- 用 on-device PSM 命中概率直接替代 incrementality；
- 把 holdout/control 组 user-level 明细接入普通 optimization feature store；
- 在没有实验 provenance 的情况下，把一个普通 CVR 模型命名为 causal lift model。

这条拆分会让系统复杂一点，但它避免了一个更大的生产问题：把“归因准确”误当成“预算最优”。on-device measurement 负责把 privacy-safe request label 拿回来；incrementality calibration 负责告诉优化系统这个 label 应该被多重地相信。

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

### 13.2A 实时 streaming DP 的落地条件

广告报表通常不是一次性 SQL 导出，而是按小时 / 天不断刷新。AdsBPC 这类研究的生产启发是：可以为了实时性采用 per-user streaming DP，但必须把以下四件事前置成协议，而不是让报表任务自己解释：

- `dp_subject_unit`：到底保护 advertiser user、app instance、device-scoped subject，还是只能说 event-level / thresholded。
- `contribution_enforcement_point`：贡献裁剪发生在 device SDK、confidential plane，还是 aggregate collector。
- `release_slot_granularity`：hourly / daily / campaign_day 的 slot 必须和 budget ledger 一一对应。
- `noise_power_allocation_id`：流式场景可以对不同 slot 分配不同噪声功率，但这个计划必须可审计、可复现、可解释。

这也是为什么本 RFC 新增 `StreamingDpReleasePlan`。它不要求 optimization plane 初期就上 DP；但任何 partner-facing “实时、连续、可下钻”的 aggregate release，都 `SHOULD` 至少拥有这类计划对象。否则系统很容易在 30 天内发布 30 次“看起来只是更新”的报表，实际却消耗了 30 次隐私预算。

### 13.2B privacy budget scheduler 必须产品化

DP aggregate reporting 不能只靠 `epsilon` 字段和离线任务命名来治理。W3C Attribution Level 1 的最新草案把 report lifecycle、anti-replay、aggregation service 和 privacy budget 放在同一条路径里；Big Bird 进一步指出，单纯给每个 querier / collector 独立预算，在自适应查询下不够稳。对本 RFC 来说，工程结论很直接：

- 如果只是 Phase 1 内部 operational dashboard，可以使用 `per_collector_quota_only`，但 UI、API 和文档都不能把它叫作 global DP。
- 如果对 partner 暴露 DP aggregate release，就必须记录 `privacy_unit`、`formal_budget_model`、`global_budget_scope_id`、`scheduler_type`、`min_batch_size` 和 correction release policy。
- 多个 MMP / AAP / BI surface 同时读取同一 measurement task 时，预算不能分散在各自的 Airflow 参数里；应由统一 `AggregateBudgetSchedulerPolicy` 做 reservation 和 finalization。
- DoS resilience 是隐私系统的一部分。global budget 如果太紧，会被恶意或异常 collector 抢光；如果太松，又会弱化保证。因此 slack、throttling、batch scheduling 和 audit log 必须是正式字段。

实际落地建议是：Phase 1 用 `AggregateCollectorBudgetState` 先把 report / batch / collector / replay / budget 状态打通；Phase 2 再启用 `AggregateBudgetSchedulerPolicy`，把 per-collector quota 和 global device/user epoch budget 合并到同一个 privacy ledger。

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

同时应吸收 [W3C Attribution Level 1](https://www.w3.org/TR/attribution/) 的两个硬约束：

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

- `claim_token`
- `mmp_touch_token -> req_id` index row
- OPRF/PSM session context，例如 `odmed`、`matching_id`、candidate cache handle
- validate / `mvs` context
- `OnDeviceMeasurementArtifact`，如果启用兼容 artifact 路径
- `odm_info`，如果启用 ICM / AAP bridge path
- `compatibility egress cache`

### 14.2 Anti-replay

至少要求：

- `claim_token` single-use
- `confirm_idempotency_key`
- `ask_idempotency_key`
- PSM / validate session nonce
- `replay_cache_key`
- bounded-shot query count
- `artifact_id` / `query_hash`，如果启用兼容 artifact path

### 14.3 Purpose binding

每次 Ask / Claim / Confirm / confidential processing `SHOULD` 绑定：

- `measurement_task_id`
- `adv_app_id`
- `mmp_partner_id`
- event name / event timestamp
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

- 按 `claim_verification`、`token_to_req_id_join`、`feature_derivation`、`egress_adapter` 拆 workflow；兼容 artifact path 再保留 `artifact_validation`
- debug 日志默认关闭 request-level 敏感字段
- 对高敏路径优先使用批处理、固定模板、减少 data-dependent branching
- 做 side-channel regression test
- 对外部可观察响应做固定尺寸或分桶填充，避免 `candidate_count`、`row_hit_count`、`validation_path` 直接暴露在响应大小和延迟上
- 禁止把 page-fault trace、HPC / PMC、fine-grained perf telemetry 默认开放给生产 operator；需要 break-glass 流程与审计
- 对 `token_to_req_id_join` 和 `feature_derivation` 优先做 constant-shape memory access review，而不是只做功能正确性 review
- 对 side-channel test 结果建立基线版本；workflow、编译器、内核、CVM 固件升级后必须回归

### 14.6 Device / supply-path attestation

device attestation 的目标是证明 touchpoint 环境更可信，而不是建立新的用户身份层。基于 Privacy Pass / PrivateToken 类协议时，推荐按四个角色建模：

- `Client`: 渲染广告的 App、video player、OM SDK 或媒体 SDK。
- `Verifier`: 需要验证 touchpoint 质量的 measurement / ad network 服务。
- `Attester`: 能观察平台真实性的设备或平台组件。
- `Issuer`: 签发不可链接 token 的角色。

生产约束：

- `MUST` 把 attestation token 的原始值和 `server_request_id` 分库存储；普通日志只保留 digest 和状态码。
- `MUST NOT` 把 device attestation receipt 暴露为 MMP 可见归因字段；MMP 只需要知道 claim 是否成立，不需要看到设备真实性证明细节。
- `SHOULD` 把 `attestation_result` 转成 coarse quality bucket，再进入 optimization plane；失败或缺失可以降权，但不能自动改写归因事实。
- `SHOULD` 对 `issuer_id`、`attester_id`、`max_age_sec`、`challenge_ts_ms` 和 `receipt_expiry_ts_ms` 做 replay / freshness audit。
- `MUST NOT` 把 attestation 的 success rate 当成用户画像特征；它是 supply quality / fraud quality 信号。

## 15. Trade-off 设计

### 15.1 可以放松的地方

- Phase 1 的 optimization plane 不强制 DP。
- confidential plane 初期可以先用单方 TEE/CVM，而不是直接上 MPC。
- MMP bridge 初期可以先做 opaque pass-through，而不是完整通用标准。
- baseline model 先用 GBDT，而不是直接上大型 DP 深度模型。
- device / supply-path attestation 初期可以作为 fraud-quality side signal，不强制所有 publisher surface 阻塞式接入。
- incrementality 初期可以先做 campaign / creative-family 粒度校准，不必把每条 request 都宣称为因果样本。
- ADMaP / PJC / PSI 初期可以用于后端对账和 aggregate verification，不必替代前台 SRN yes/no claim。
- GPP / DDRF 初期可以先覆盖 suppression / retention / debug-trace key rotation，不必一次性重算所有历史 aggregate release。
- Apple AdAttributionKit / W3C Attribution Level 1 这类平台 postback / aggregate surface 初期可以先作为 reconciliation 与 reporting 输入，不必让它们进入 request-level optimization。
- Android Privacy Sandbox Attribution Reporting 的历史实验 trace 可以保留为兼容分析样本，但生产主链路应转向 partner-managed ICM / App Conversion API path。

### 15.2 不能放松的地方

- 不能把 `server_request_id` 下沉到普通 BI。
- 不能把原始 `boot_time`、原始 `ip` 透传给 MMP 作为通用字段。
- 不能把 `odm_info` 变成 durable identifier。
- 不能取消 anti-replay。
- 不能把 contribution bounding 视为可选项。
- 不能把 device attestation token 或 token digest 当成 durable user identifier。
- 不能把 `is_attributed=true` 当成 `incremental=true`。
- 不能让 consent withdrawal / deletion signal 只停留在 legal ticket；它必须落到 token、artifact、feature release 和 retention state。
- 不能把已经 deprecated / soft-removal expected 的 Android MeasurementManager 当成未来生产 attribution abstraction。
- 不能把 Apple AdAttributionKit 的 `conversion_tag`、geo postback 或 winning postback copy 当成可恢复 `server_request_id` 的 request-level join key。

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
- `training_privacy_policy_id`
- `retention_policy_id`

### 15.4 utility trade-off 也要版本化

最新广告隐私 field experiment 给出的现实约束是：privacy-preserving profile 的业务效果不是一个固定常数。它会被以下因素放大或削弱：

- SDK / browser / platform adoption
- MMP partner 是否已经支持对应 Ask / Claim / Confirm path
- supply side 是否接入隐私增强 surface
- latency 是否进入广告请求关键路径
- cold-start 用户占比
- 是否把成本、点击、转化和收入放在同一个实验口径下评估

因此本文要求每个准备上线的 profile 至少产出一个 `MeasurementUtilityExperimentRecord`。推荐上线门槛：

- `causal_design` 不低于 geo experiment、randomized holdout、switchback 或有校准的 observational design。
- `latency_p95_delta_ms` 和 `impression_delivery_delta_ratio` 必须进入 release review。
- `adoption_state=partner_beta` 或 `partial_supply` 时，只允许 gated rollout。
- 对 location-like / IP-derived signal，若收益只集中在 cold-start cohort，应收紧 `DeviceSensitiveSignalPolicy.cold_start_gate`。
- 若为了业务可用性决定 Phase 1 不上 DP，必须在 `TrainingPrivacyPolicy.privacy_profile=NO_DP_BASELINE` 和 release note 中明确；不能对外声称 DP。

### 15.5 RFC conformance gates

为了让本文真正像 RFC，而不是架构白皮书，生产上线前建议按下面的 gate 判定实现是否合格。

`MUST` gate：

- 有 `MeasurementConformanceProfile`，且能指向具体 `measurement_task_id`、MMP partner、SDK compat profile、training privacy policy、aggregate budget policy。
- `ClaimResponse` 与 `MmpConfirmRequest` 有短 TTL、single-use `claim_token`、idempotency key 和 replay cache。
- `server_request_id` 只在 Ad Network 内部 / confidential plane / optimization label 中出现，不进入 MMP payload 或普通 BI 明细。
- `raw_ip`、`boot_time_ms`、`device_fp_hash`、OPRF input/output、`odm_info`、`claim_token` 不进入 `OptimizationTrainingRow`。
- 端侧敏感信号有 `DeviceSensitiveSignalPolicy` 与 `DeviceSensitiveSignalDerivationRecord`；没有 policy 的 raw signal 不采集、不派生、不上报。
- 如果对外宣称 DP aggregate release，必须有 `StreamingDpReleasePlan` 或 `AggregateBudgetSchedulerPolicy`；否则只能称为 thresholded / non-DP operational reporting。

`SHOULD` gate：

- OPRF / VOPRF、DP、FHE、PJC、GBDT / DP training 均使用成熟第三方库或 audited implementation，并记录在 `approved_library_profiles`。
- 每个新 privacy profile 上线前有 `MeasurementUtilityExperimentRecord`，至少记录 adoption、latency、observability、ROAS / CPA、fallback decision。
- MMP / AAP / ICM 集成保留 `SdkMeasurementRuntimeTrace`，把 SDK 缺失、region ineligible、consent disabled、S2S path ineligible、`odm_error` 与 attribution negative 区分开。
- 对广告媒体侧 touchpoint，若 surface 支持 OM SDK / Privacy Pass-style attestation，应把 attestation 作为 fraud quality bucket，而不是自研设备指纹。

`MAY` gate：

- Phase 1 可以不上 optimization DP，但必须标成 `optimization_privacy_mode=no_dp_confidential`。
- Phase 1 可以先不部署完整 DAP / VDAF collector，但 aggregate object model 应保留 report / batch / budget / replay lifecycle。
- Phase 1 可以用 LightGBM / XGBoost baseline，不必直接上 DP-SGD；但特征 sensitivity manifest 和 prohibited raw fields 必须先固定。

### 15.6 composition 与 clock evidence gates

`MeasurementConformanceProfile` 说明“实现到了哪一级”；`EcosystemPrivacyCompositionRecord` 说明“这些实现组合后还泄露什么”。两者都要有，否则上线 review 很容易把局部正确误读为整体正确。

`MUST` gate：

- Profile B 及以上只要启用 MMP/AAP reporting、SRN Confirm 和 request-level optimization，就必须生成 `EcosystemPrivacyCompositionRecord`。
- 任何 `boot_time`、launch time、SDK init delay 或 IP-derived feature 都必须能追到 `DeviceSensitiveSignalDerivationRecord`；涉及 launch / clock 的还必须能追到 `LaunchClockEvidenceRecord`。
- `raw_boot_time_released` 必须为 `false`，除非是明确标注为离线法务/安全调查的 break-glass profile。
- 对外声明必须按 surface 写清楚：MMP payload、AAP ICM reporting、Ad Network trainer、aggregate report 分别有什么保护；不得把局部 DP 或局部 on-device 处理宣传成端到端 DP。
- SDK / API 路径不得通过返回值、异常、耗时、日志量或重试语义泄露 “是否命中 attribution”、“budget 是否耗尽” 或 “conversion value 是否非零”。

`SHOULD` gate：

- Protobuf JSON 中的 `int64` 字段使用字符串编码，避免 `advertiser_user_id`、`server_request_id` 在 JS / warehouse JSON pipeline 里丢精度。
- `residual_leakage_channels` 应进入 privacy review 和 experiment readout；例如 MMP 观察 winner network、AAP event-level ICM、creative-level reporting 和 aggregate 重复 release。
- 对 launch / clock evidence，推荐只把粗桶进入 trainer，例如 `launch_0_250ms`，不要把毫秒级 monotonic clock 当作模型特征。

`MAY` gate：

- Phase 1 可以声明 `composition_privacy_statement=contextual_scope_enforced_no_end_to_end_dp_claim`，不必强行证明端到端 DP。
- 低量级 campaign 可以先只启用 aggregate / thresholded reporting，把 request-level optimization gate 在高量级、可审计 cohort 中。

## 16. 生产实现建议

### 16.1 端上 / SDK

- iOS 侧优先复用 [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk) 或 Firebase ODM 路线。
- 用 `Protobuf + buf` 定义 wire schema。
- 本地仅保留短期加密缓存，不保留长期稳定 token。
- 如果自研 Google-compatible ODM 子流程，默认按 `OPRF/VOPRF-style PSM + prefix bucket candidate retrieval + local filtering` 建模；不要把 Paillier/PIR 当成当前 HAR 已证实的主路径。
- SDK 状态机需要显式记录 `config_loaded`、`psm_candidate_set_received`、`local_match_evaluated`、`mvs_validated`，而不是只记录一个布尔 `odm_info_generated`。
- MMP SDK / ODM SDK 集成还应显式记录 `odm_fetch_timeout_ms`、`sdk_init_delay_ms`、`deep_link_callback_deferred`、`event_source_system` 和 `is_firebase_native_event`；这些字段只进入 integration health plane。
- SDK debug trace 的 PII 字段应在生成点做 field policy、keyed pseudonymization 和短窗口加密；不要依赖服务端事后清洗。
- SDK 采集 `boot_time`、`ip`、location-like signal 或 install referrer 前，应先解析 `DeviceSensitiveSignalPolicy`；没有 policy 的字段不采集、不派生、不上报。
- 对广告渲染侧 touchpoint，如果 surface 已接入 OM SDK / OMID，优先复用 OM SDK device attestation 能力作为 touchpoint quality evidence；不要用自研设备指纹去替代平台 attestation。
- device attestation 失败或缺失时，默认只影响 fraud quality / sample weighting，不应让 SDK 阻塞 `first_open`、deep link callback 或 MMP Ask 主链路。
- Android 侧不要新建对 `android.adservices.measurement.MeasurementManager` 的生产硬依赖；如果已有实验代码，必须通过 capability flag 与 fallback 隔离，并默认走 ICM / App Conversion API / install referrer / partner-config path。
- iOS 侧可把 AdAttributionKit postback copy / conversion tag / geo postback 作为 reconciliation surface 接入，但 SDK adapter 不应把这些平台字段直接转成 `server_request_id` 或训练特征。
- 新 profile 上线前必须先产出 `MeasurementUtilityExperimentRecord`；如果 adoption / latency / supply coverage 还在 beta，默认只做 gated rollout。

iOS optional SDK 的推荐实现：

- MMP SDK 定义一个小而稳定的 Objective-C-compatible protocol，例如 `MmpMeasurementAdapter`，避免 Swift ABI / module 名称变化影响 discovery。
- ad network 提供 `AdNetworkMmpAdapter` 这类轻量 package；广告主只有在已经接入该 ad network SDK 时才需要链接它。
- adapter 可以在初始化时显式调用 `MmpAdapterRegistry.register(networkId:adapter:)`；自动注册可用，但应允许开发者关闭。
- adapter package 应带本地可验证的 manifest / signature hash；remote config 只能启停 policy，不能伪造本地 SDK 存在性。
- MMP SDK 启动后缓存 capability，缓存 TTL 建议 30-60 分钟；app foreground、consent 改变、remote config 改变时重新评估。
- 没有 adapter 时，MMP SDK 只产生 `ASK_SKIPPED_SDK_NOT_PRESENT` 或 `ASK_SKIPPED_ADAPTER_NOT_PRESENT`，不抛异常、不弹日志噪音、不阻断 app 启动。
- 对开发者暴露一个集成诊断 API，例如 `getMeasurementIntegrations()`，返回哪些 network eligible、哪些被 skip，以及 skip reason。
- 诊断 API 不应返回 raw device material、`device_fp_hash`、`odm_info`、`claim_token` 或 `server_request_id`。

### 16.2 confidential processing

- 优先评估 [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute) 作为 workflow 编排和 confidential processing 基座。
- OPRF / VOPRF 层应对齐 [RFC 9497](https://www.rfc-editor.org/rfc/rfc9497) 的术语和 mode/ciphersuite 建模，至少把 `mode`、`suite_id`、`key_epoch_id`、`public_key_id` 写进配置和审计记录。
- 如果服务端主实现是 Go，优先评估 [cloudflare/circl](https://github.com/cloudflare/circl) 这类现成密码学库或同等级 audited 实现；不要自己手写 EC blind/unblind、DLEQ proof 或 group serialization。
- 如果客户端或工具链需要 TypeScript 参考实现，可参考 [cloudflare/voprf-ts](https://github.com/cloudflare/voprf-ts) 做测试向量和互操作验证，但不要把未经性能和内存审计的脚本实现直接放进热路径。
- ingress 处立刻做 TTL 和 replay gate。
- 不要做一个“万能 confidential service”；按 workflow 分类部署。
- OPRF key rotation 不应只靠人工换密钥；建议显式建模 `key_epoch_id`，并把它与 `measurement_task_id`、`query_template_id`、`prefix_length`、`candidate_store_version` 绑定。

### 16.3 optimization training

- baseline: [LightGBM](https://github.com/microsoft/LightGBM) / [XGBoost](https://github.com/dmlc/xgboost)
- 每个 trainer 都必须消费 `TrainingPrivacyPolicy`，即使 profile 是 `NO_DP_BASELINE`。
- feature store 应先按 `feature_sensitivity_manifest_id` 分桶，禁止 raw PII 字段绕过 manifest 进入训练。
- 深度模型或更强隐私训练再考虑：
  - [JAX Privacy](https://github.com/google-deepmind/jax_privacy)
  - [TensorFlow Privacy](https://github.com/tensorflow/privacy)
- 用 DP 训练时，先跑 shadow / offline gate，记录 `dp_accountant_id`、`privacy_audit_profile_id` 和 `empirical_privacy_eval_id`；不要把实验 notebook 里的 epsilon 当成生产证明。
- DP-SGD / DP-FTRL 的 accountant 必须和实际 sampler 对齐：如果训练实现使用 shuffle sampler，就不能只报告 Poisson subsampling accountant；建议把 `dp_sampling_method`、`dp_accounting_method` 和 empirical audit 结果写进 `TrainingPrivacyPolicy`。

### 16.4 aggregate reporting

- 先完成 bounded release pipeline，再补 DP。
- 具体聚合原语尽量对齐当前 [VDAF draft-19](https://datatracker.ietf.org/doc/draft-irtf-cfrg-vdaf/) 里的成熟 primitive：计数优先 `Prio3Count`，数值优先 `Prio3Sum`，分桶优先 `Prio3Histogram`；不要自造一套名字像 VDAF、语义却不可验证的半协议。
- privacy budget ledger 要单独版本化和审计。

### 16.5 审计

- DP 机制审计可接入 [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)。
- 若 release surface 升级成持续 DP 机制，可进一步参考 [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)。

### 16.6 跨方 reconciliation

如果未来要做 advertiser / publisher / network 的隐私保护对账，优先考虑 [Private Join and Compute](https://github.com/google/private-join-and-compute)，而不是回退到交换原始 user-level 明细。

### 16.7 conformance test suite

建议把 RFC 验收做成自动化测试，而不是靠人工 review 文档。最低测试集应包括：

- schema lint：`Protobuf + buf` 校验字段类型、保留字段、向后兼容。
- forbidden-field scan：扫描 MMP payload、debug trace、trainer row、BI 明细，确保没有 `raw_ip`、`boot_time_ms`、`device_fp_hash`、OPRF material、`odm_info`、`claim_token`。
- token replay test：同一 `claim_token` 重放 Confirm 必须失败；过期 token 必须失败。
- token-to-request join test：MMP 只能回传 `mmp_touch_token` 或 opaque handle，服务端只能在 Confirm 后恢复 `server_request_id`。
- policy coverage test：任何 `derived_feature_buckets` 都必须能追到 `DeviceSensitiveSignalPolicy`、`DeviceSensitiveSignalDerivationRecord` 和 `feature_policy_id`。
- launch-clock evidence test：任何 `boot_time`、app launch time 或 SDK init delay 派生桶都必须能追到 `LaunchClockEvidenceRecord`，且 raw clock 不进入 MMP payload / trainer raw feature。
- composition leak test：同一 `advertiser_user_id`、`server_request_id`、`claim_token` 或 `odm_info` 不得同时出现在 MMP payload、optimization raw feature 和 aggregate release 明细中。
- side-channel regression test：hit / miss / budget exhausted / consent disabled 路径的返回形态、错误码、日志量和粗粒度耗时必须保持稳定。
- aggregate budget test：DP / thresholded report 必须有 report、batch、collector、budget、replay lifecycle。
- partner ineligibility test：SDK missing、region ineligible、consent disabled、S2S ineligible 必须落到 runtime trace，不能写成 attribution negative。
- training manifest test：训练作业必须消费 `TrainingPrivacyPolicy`，并拒绝 prohibited raw feature。

这些测试不保证系统“绝对隐私”，但能保证实现没有偏离 RFC 的主要边界：MMP 看不到 `req_id`，trainer 看不到 raw PII，对外 release 有预算和 replay 语义。

## 17. Deployment Profiles

### 17.1 Profile A: Minimum Production

包含：

- `server_request_id`
- touchpoint store
- `mmp_touch_token -> req_id` index
- `MMP SDK Ask -> AdNetwork SDK OPRF/PSM -> Claim -> MMP Confirm`
- `claim_token` TTL / replay gate
- Confirm 后的 token-to-`req_id` join
- request-level labels
- `TrainingPrivacyPolicy`，至少标明 `NO_DP_BASELINE` 与 prohibited raw features
- thresholded aggregate reporting
- opaque `odm_info` / device artifact，仅在兼容 ICM / AAP path 时启用

### 17.2 Profile B: Recommended Default

在 Profile A 基础上增加：

- TEE-backed confidential processing
- versioned OPRF/PSM config and candidate store
- versioned contribution policy
- feature sensitivity manifest and semi-sensitive training shadow policy
- DP-backed aggregate reporting
- policy-aware audit trail

### 17.3 Profile C: Cross-Party Hardened

在 Profile B 基础上增加：

- PJC/PSI reconciliation
- stronger verifiable workflow
- DAP/VDAF-aligned aggregate service

### 17.4 Profile D: FHE-Hardened Optional

Profile D 不是比 Profile C “更高级所以默认更好”。它只适合少数高敏 task：你愿意付出明显的延迟、带宽、工程复杂度，用来让服务端在看不见某些输入明文的情况下完成固定计算。

Profile D 至少包含：

- `FheMeasurementTaskConfig`
- `FhePrivateMeasurementQuery`
- FHE evaluator service
- FHE parameter review
- ciphertext size / latency budget
- key epoch rotation
- decryptor role governance
- output release policy

Profile D 仍然必须保留 Profile A 的主闭环：

```text
MMP SDK Ask
  -> AdNetwork SDK optional FHE subflow
  -> ClaimResponse
  -> MMP Confirm
  -> token_to_req_id_join
  -> optimization / aggregate release
```

如果某个设计声称“用了 FHE，所以不需要 Claim/Confirm、anti-replay、purpose binding、DP 或 output policy”，它不是 hardened profile，而是把计算隐私误解成了系统隐私。

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

## 17B. AdNetwork OPRF/PSM-with-payload 推荐实现

这一节把 v3.1 legal review 里的实现判断合并进主 RFC。它不是替代 17A 的 HAR 证据，而是把证据转成推荐产品架构。

### 17B.1 Touchpoint row 与 MMP-facing token

AdNetwork 在点击或曝光发生时写入 touchpoint row：

```json
{
  "user_id": 7312459812234501123,
  "adv_app_id": "com.example.game",
  "advertiser_id": 120045,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "creative_id": 74019912,
  "req_id": "749b1ecf4d8f4b50a3cc1e2fb91b7ad2a7f",
  "server_request_id": 91833720368540001,
  "click_ts_ms": 1777500009231,
  "source": "ad_network",
  "feature_ptr": "creative_id x req_id",
  "ad_platform_user_id": "APUID_v1_scoped_optional",
  "opaque_click_id_ref": "clk_v1_optional_pointer"
}
```

然后生成 MMP-facing touch token：

```text
mmp_touch_token = HMAC_Kmmp(
  mmp_partner_id
  || advertiser_id
  || adv_app_id
  || req_id
  || creative_id
  || touch_time_bucket
)
```

设计重点：

- token 从 touch context 派生，而不是从 raw `user_id` 单独派生。
- token 名称避免 `UserID`，推荐 `mmp_touch_token` / `ad_touch_token`。
- 服务端维护 `mmp_touch_token -> req_id` index；MMP 不看到 `req_id`。
- `creative_id` 是 reporting metadata；`req_id` 是内部 optimization join key。
- 如果历史 partner contract 要求 `AdPlatformUserID` / opaque `click_id`，它们应被建模为 compatibility profile，而不是替换 `mmp_touch_token + claim_token` 的默认 profile。
- `opaque_click_id_ref` 应优先是 compact pointer 或短密文；不要把 500B 级 gbraid-like blob 复制到每条 candidate row，除非 bucket size 很小且有明确容量预算。

### 17B.2 Candidate row 与 associated payload

每条 touchpoint 可以进入 prefix bucket candidate store：

```proto
message CandidateRow {
  bytes quick_tag = 1;
  bytes opaque_payload = 2;
  bytes row_meta = 3;
}

message ReportingPayload {
  string mmp_touch_token = 1;
  int64 creative_id = 2;
  int64 campaign_id = 3;
  int64 ad_group_id = 4;
  int64 touch_time_bucket = 5;
  string ad_platform_user_id = 6; // optional compatibility profile
  string opaque_click_id = 7; // optional compatibility profile
  string visible_handle_mode = 8; // tracking_link_touch_token, apuid_click_id, claim_token_only
}
```

逻辑构建：

```python
def build_candidate_row(touchpoint, server_key, cfg):
    z = normalize_identity_material(touchpoint.identity_material)
    d = sha256(z, touchpoint.adv_app_id, cfg.source, cfg.bucketed_date)
    prefix = high_bits(d, cfg.prefix_length)
    P = hash_to_curve(d)
    Y = scalar_mul(server_key, P)

    row_key = hkdf(Y, cfg.odmed, cfg.bucketed_date, "row-key")
    quick_tag = trunc8(hmac(row_key, "quick-tag"))
    reporting_payload = encode({
        "mmp_touch_token": touchpoint.mmp_touch_token,
        "creative_id": touchpoint.creative_id,
        "campaign_id": touchpoint.campaign_id,
        "ad_group_id": touchpoint.ad_group_id,
        "touch_time_bucket": bucket(touchpoint.click_ts_ms),
        "ad_platform_user_id": optional_apuid(touchpoint),
        "opaque_click_id": optional_compact_click_id_pointer(touchpoint),
        "visible_handle_mode": cfg.visible_handle_mode,
    })
    opaque_payload = aead_encrypt(row_key, reporting_payload, aad=prefix)
    CandidateStore[prefix].append({
        "quick_tag": quick_tag,
        "opaque_payload": opaque_payload,
        "row_meta": encode_meta(touchpoint.click_ts_ms)
    })
```

### 17B.3 在线 Ask / Claim

```python
def ad_network_sdk_ask(event, adv_app_id):
    cfg = get_config(adv_app_id)
    z = derive_local_measurement_material()
    d = sha256(z, adv_app_id, cfg.source, cfg.bucketed_date)
    prefix = high_bits(d, cfg.prefix_length)

    P = hash_to_curve(d)
    r = random_scalar()
    A = scalar_mul(r, P)

    psm_resp = post_psm({
        "odmed": cfg.odmed,
        "prefix": prefix,
        "blinded_point": compress(A),
        "prefix_length": cfg.prefix_length
    })

    B = psm_resp.server_eval_point
    Y = scalar_mul(inv(r), decompress(B))
    row_key = hkdf(Y, cfg.odmed, cfg.bucketed_date, "row-key")

    for row in psm_resp.candidate_rows:
        if row.quick_tag != trunc8(hmac(row_key, "quick-tag")):
            continue
        payload = aead_decrypt(row_key, row.opaque_payload, aad=prefix)
        if payload is not None:
            return build_claim(payload, cfg, event)

    return {"matched": False, "match_type": "on_device_psm"}
```

`claim_token` 建议包含：

```text
claim_token = Sign_or_AEAD_Enc(
  K_claim,
  {
    claim_id,
    mmp_touch_token,
    adv_app_id,
    event_type,
    event_ts_ms,
    psm_context_hash,
    sdk_attestation_hash,
    expiry_ts,
    nonce,
    policy_version
  }
)
```

### 17B.4 性能直觉

2026-04-14 HAR 样本给出的量级是：

```text
/config response: ~192B JSON
/psm request: psm_request 50B decoded
/psm response: 123,189B decoded; JSON/base64 text roughly 164KB
candidate rows: 1009
average decoded row: ~122B
```

所以主瓶颈通常不是 OPRF 标量乘本身，而是移动网络下的 `/psm` response 和 SDK 冷启动。若 bucket 平均 1K rows，一次查询是百 KB 级，不能再按 5-15KB 小包估算。

如果 `quick_tag = 8 bit`，1009 rows 中进入 AEAD decrypt 尝试的误候选期望约为：

```text
1009 / 256 ~= 4
```

端侧 AEAD 成本可控；系统调优重点应放在 bucket sizing、cache、TLS/session reuse、retry budget 和后台调度。

## 17C. Bucket Return 方案分歧

`bucket return` 是 OPRF/PSM-with-payload 设计里最容易产生分歧的点。它讨论的不是 MMP 最后能看到什么，而是 AdNetwork Server 在 `/psm` 或等价接口里到底返回什么给 AdNetwork SDK。

换句话说，`17D` 讨论的是 `SDK -> MMP -> MMP Server -> AdNetwork Server` 的披露边界；本节讨论的是 `AdNetwork Server -> AdNetwork SDK` 的 bucket 返回边界。两者必须分开，否则容易把“不给 MMP 看 bucket tail/tag”误解成“server 也不能向 SDK 返回候选 bucket”。

### 17C.1 术语

- `prefix_bucket`: SDK 从本地 matching material 派生出的桶前缀，例如 HAR 中观察到的约 22-bit prefix。它不应被当成稳定用户 ID。
- `bucket candidate rows`: server 针对该 prefix 返回的一组候选行。每行通常是加密的 associated payload，而不是明文触点。
- `quick_tag` / `tail_tag`: 用于端侧快速过滤的短 tag。它只能留在 SDK crypto boundary 内，不应进入 MMP payload。
- `associated payload`: 命中后可恢复的 touch-scoped payload，例如 `mmp_touch_token`、`campaign_id`、`creative_id`、`touch_time_bucket`、`claim_policy_id`。
- `validate`: 可选的后续接口，用于把端侧 local filtering 的结果转成可发布的 measurement value、`odm_info` 或 claim receipt。

### 17C.2 选项总览

| 方案 | Server bucket return | Client 工作 | Server 是否知道精确命中 | 带宽 | request-level optimization | 推荐 |
|---|---|---|---:|---:|---:|---|
| BR-0: raw exact lookup | 不返回 bucket；server 直接用 raw / hash 查 | 很少 | 是 | 低 | 强 | Reject |
| BR-1: full candidate rows return | 返回 prefix bucket 下的加密 candidate rows | 本地 unblind、filter、decrypt | 默认不知道 | 中高 | 强 | 推荐默认 |
| BR-2: compact handles + validate | 返回 row handles / compact encrypted hints，payload 在 validate 后释放 | 本地过滤后请求 validate | 取决于 validate 设计 | 中 | 强 | 强化版 |
| BR-3: opaque claim only | 不返回 candidate rows，只返回 claim receipt | SDK 只转发 receipt | 取决于 server/TEE | 低 | 中强 | privacy-max 可选 |
| BR-4: metadata-only | 只返回 bucket policy / epoch / coarse count | SDK 不恢复 touch payload | 否或弱 | 低 | 弱 | fallback |
| BR-5: aggregation-only | 不做 request-level claim | 只产出 aggregate contribution | 否 | 低 | 弱或无 | fallback |

这里的关键判断是：`bucket return` 不只是性能细节，它决定了谁拥有精确匹配解释权。

- BR-1 把精确匹配放在 SDK 本地，所以 server 不需要知道 SDK 到底命中了 bucket 里的哪一行。
- BR-2 把 payload 释放推迟到 validate 阶段，适合更强治理，但 validate 必须做 padding、rate limit、anti-replay 和 purpose binding。
- BR-3 表面最省带宽，但如果没有 TEE / verifiable workflow / blinded validation，它很容易退化成 server-side exact matching。
- BR-4 / BR-5 隐私面更保守，但会明显削弱 MMP SRN reconciliation、creative-level reporting 和 request-level optimization。

### 17C.3 推荐默认：BR-1 candidate rows return

当前 RFC 的默认实现应写成 BR-1：

```text
SDK computes prefix_bucket + blinded OPRF query
  -> Server returns OPRF/VOPRF evaluation context
  -> Server returns encrypted candidate rows for prefix_bucket
  -> SDK locally unblinds / derives row key / filters quick_tag
  -> SDK decrypts matched associated payload
  -> SDK creates claim_token or validate material
```

推荐它作为默认，不是因为它最省资源，而是因为它同时满足四个生产目标：

1. 与 2026-04-14 HAR 观察到的 Google-compatible 形态一致；
2. 精确命中判断留在 SDK 本地；
3. associated payload 可以承载 `mmp_touch_token` 和 creative metadata；
4. Confirm 后仍能通过 `mmp_touch_token -> req_id` 物化 request-level optimization label。

BR-1 的最低返回对象可以建模为：

```json
{
  "schema_version": "bucket_return.v1",
  "measurement_task_id": "icm_install_v3",
  "bucket_epoch_id": "2026-05-06:ios:us:v3",
  "prefix_length": 22,
  "prefix_bucket_b64": "A7fQ",
  "oprf_suite_id": "ristretto255-sha512-rfc9497",
  "oprf_key_epoch_id": "oprf_key_2026_05_w1",
  "server_eval_b64": "AwEAAa...compressed-point",
  "server_proof_b64": "BHL0...proof",
  "candidate_row_count": 1009,
  "candidate_rows_ref": "inline",
  "candidate_rows_compression": "zstd",
  "candidate_rows_aead": "xchacha20poly1305",
  "quick_tag_bits": 8,
  "response_padding_class": "1000_to_1250_rows",
  "policy_version": "bucket_return_policy_v2",
  "expires_ts_ms": 1777590900000
}
```

其中 `prefix_bucket_b64`、`server_eval_b64`、`server_proof_b64`、`quick_tag_bits` 和 row key 派生材料都不得出 SDK crypto boundary，更不得进入 MMP Ask / Claim / Confirm payload。

### 17C.4 BR-2：compact handles + validate

BR-2 是 BR-1 的治理强化版。server 不直接返回完整 associated payload，而是返回 compact row handles 或更短的 encrypted hints。SDK 本地过滤后，把不可重放的 validate material 发回 AdNetwork controlled endpoint，由 server 在 policy 检查后签发 claim。

示意流程：

```text
/psm returns compact encrypted handles
  -> SDK local filtering finds one or more plausible handles
  -> SDK POST /validate { handle_commitment, match_proof, nonce, attestation }
  -> Server returns claim_token + allowed reporting metadata
```

它的好处是 payload 释放更可控，能在 validate 时检查：

- SDK build / attestation；
- event provenance；
- retry budget；
- consent / region eligibility；
- claim policy version；
- replay state。

它的风险也很明确：validate 如果设计得太“直”，server 就可能通过 validate request 学到精确匹配。因此 BR-2 必须要求：

- validate response 做固定大小或分档 padding；
- validate request 绑定 nonce、event_id、measurement_task_id 和 SDK attestation；
- validate endpoint 不返回 loser diagnostics；
- validate logs 不保留可反推 bucket row 的 raw handle；
- 高风险模式下把 validate 放进 confidential service。

### 17C.5 BR-3：opaque claim only

BR-3 的目标是让 SDK 和 MMP 都不接触 candidate bucket。它只返回一个 signed / opaque claim receipt：

```json
{
  "schema_version": "opaque_claim_return.v1",
  "measurement_task_id": "icm_install_v3",
  "matched": true,
  "claim_token": "opaque_claim_token_v1",
  "claim_policy_id": "claim_policy_privacy_max_v3",
  "expires_ts_ms": 1777590900000
}
```

这个方案看起来最干净，但有一个尖锐问题：如果 claim 是 server 直接根据 raw query 或 stable hash 生成的，它就不再是 on-device measurement，而是 server-side matching。要让 BR-3 成立，至少需要满足下列条件之一：

- claim 由 TEE / CVM 中的 audited workflow 生成；
- query 是 blinded / OPRF-style，server 不能看到 raw matching key；
- claim 只表达 policy-constrained membership，不携带可用于 MMP 长期 join 的 row identity；
- 所有 claim issuance 都有 anti-replay、rate limit、purpose binding 和 attestation 记录。

因此 BR-3 更适合作为 privacy-max mode，而不是默认生产路线。

### 17C.6 BR-4 / BR-5：metadata-only 与 aggregation-only

BR-4 只返回 bucket policy、epoch、粗粒度 count 或 compatibility hint，不返回 candidate rows，也不恢复 touch payload。它适合做健康检查、region eligibility、实验开关和 SDK 调度，但不适合承载完整 SRN claim。

BR-5 则更进一步：不做 request-level claim，只产出 aggregate measurement contribution。它的隐私面最保守，但会牺牲：

- MMP Ask -> Claim -> Confirm 的 winner 级协同；
- creative-level / campaign-level 细粒度诊断；
- Confirm 后 `req_id` 级 label materialization；
- personalized bidding / pacing / ranking 的监督信号。

所以 BR-4 / BR-5 应写成 fallback，而不是主路径。

### 17C.7 推荐排序

```text
Primary:
  BR-1 full candidate rows return

Hardened production:
  BR-2 compact handles + validate

Privacy-max:
  BR-3 opaque claim only, but only with TEE / blinded validation / verifiable workflow

Fallback:
  BR-4 metadata-only
  BR-5 aggregation-only

Reject:
  BR-0 raw exact lookup
```

一句话版本：如果目标是同时兼容 SRN、保留 request-level optimization、并控制 raw PII 出端风险，默认应选择 BR-1；如果 legal / security 对“SDK 获取 bucket candidate rows”仍然敏感，则升级到 BR-2，而不是直接退回 raw server-side matching。

### 17C.8 容量与 RD 估算：把旧 proposal 的 sizing 收进决策门槛

旧版 candidate rows proposal 里最有价值的工程补充是：`bucket return` 不能只按“隐私强弱”排序，还必须按 row size、bucket size、移动网络和团队工作量设上线门槛。本文把它收敛成下面的生产 guardrail。

Candidate row 分两类 profile：

```text
Light row:
  mmp_touch_token 或 scoped AdPlatformUserID
  creative_id / campaign_id / ad_group_id
  touch_ts_ms 或 touch_time_bucket
  compact opaque_click_id pointer
  decoded size ~= 150B

Heavy row:
  上述字段 + 500B 级 gbraid-like click_id blob
  decoded size ~= 650B
```

Bucket response 估算：

```text
S_decoded = N_bucket * S_row
S_wire ~= S_decoded * 4/3   // base64 / JSON overhead
T_transfer ~= S_wire / effective_mobile_bandwidth
```

以 `effective_mobile_bandwidth = 1.2MB/s` 粗估：

| Profile | Bucket rows | Decoded response | JSON/base64 wire | Transfer |
|---|---:|---:|---:|---:|
| Light 150B/row | 100 | 15KB | 20KB | ~17ms |
| Light 150B/row | 1,000 | 150KB | 200KB | ~167ms |
| Light 150B/row | 10,000 | 1.5MB | 2.0MB | ~1.7s |
| Heavy 650B/row | 100 | 65KB | 87KB | ~72ms |
| Heavy 650B/row | 1,000 | 650KB | 867KB | ~722ms |
| Heavy 650B/row | 10,000 | 6.5MB | 8.7MB | ~7.2s |

因此 BR-1 的上线门槛应写成：

- 默认 bucket target 应在 `~1K rows` 量级，并通过 `prefix_length / source / time partition / region partition` 控制尾部。
- Heavy `click_id` 不应 inline 到每条 row；应使用 compact pointer、BR-2 two-step validate，或让 `click_id` 在 Confirm 后由 server 端恢复。
- response 必须支持 compression、padding class、candidate row count cap、retry budget 和 stale snapshot 处理。
- `candidate_row_count` 可进入 internal observability；对外只释放粗粒度 bucket 或 policy class，避免把 response size 变成 membership side channel。

Paillier/PIR 的容量门槛也要写实。2048-bit Paillier 的 selector ciphertext 约 `512B`，因此 selector request 粗略为：

| Bucket rows | Selector request only | 判断 |
|---:|---:|---|
| 100 | ~50KB | 可实验 |
| 1,000 | ~512KB | 移动端偏重 |
| 10,000 | ~5.1MB | 不适合 MVP |

这还不包括 response ciphertext、proof、server homomorphic computation 和调试成本。所以 PIR 是 privacy escalation，不是默认替代 BR-1。

RD 估算应按实现 profile 拆：

| Workstream | 主要交付 | Complexity | Directional effort |
|---|---|---:|---:|
| SDK OPRF client | local material derivation、blind point、`/config`、`/psm`、unblind、row key | High | 4-6 person-weeks |
| SDK row matching + Claim | candidate scan/decrypt、multi-match/no-match、Claim API | Medium-high | 3-5 person-weeks |
| Server OPRF service | key management、OPRF eval、session binding、rate limit | High | 4-6 person-weeks |
| CandidateStore builder | touchpoint -> bucket row、AEAD、TTL、bucket-size control | High | 6-8 person-weeks |
| Payload / handle profile | `mmp_touch_token`、APUID/click_id compatibility、KMS、key rotation | Medium-high | 3-5 person-weeks |
| Confirm + verification | claim replay、partner/app/event binding、token -> req_id | Medium-high | 4-6 person-weeks |
| Observability + privacy controls | metrics、debug reason、log redaction、delete propagation、KMS audit | High | 4-6 person-weeks |
| MMP integration + testing | Ask/Claim/Confirm contract、partner sandbox、E2E validation | Medium | 3-5 person-weeks |

方向性总量：

```text
Core MVP implementation: ~31-47 person-weeks
Hardening / integration / rollout buffer: +12-18 person-weeks
Total: ~43-65 person-weeks
With a 5-6 person cross-functional RD group:
  internal prototype: 6-8 weeks
  limited MMP pilot: 10-14 weeks
  production-ready rollout: 4-6 months
```

最大 RD 风险按优先级排序：

1. bucket size > 1K 导致 payload / latency 线性上升；
2. heavy `click_id` blob 被复制到每条 row；
3. SDK-held long-term signing key 被提取；
4. duplicate Confirm / claim replay 导致 over-attribution；
5. CandidateStore snapshot stale，Confirm 时 token 无法恢复 `req_id`；
6. logs 泄漏 candidate row、click_id plaintext 或 claim internals；
7. show-level VTA 直接建全量 candidate rows，带来 10TB/day 级别存储压力。

## 17D. MMP Claim / Confirm 数据披露选项与 Legal Review

本节用于 legal / privacy / security review。它不是法律意见，也不是最终合规结论；目标是把不同技术折中、数据可见性、产品能力、剩余风险和必要控制项写清楚。

### 17D.1 评估前提

需要区分两类数据：

```text
Raw identity material:
  IDFV / IDFA / boot signal / device fingerprint / device_fp_hash /
  raw user_id / OPRF input / unblinded OPRF output

Pseudonymous attribution material:
  mmp_touch_token / claim_token /
  creative_id / campaign_id / ad_group_id / touch_time_bucket
```

当前主方案的目标不是宣称 “no personal data leaves the device”，而是更精确地控制：

```text
1. raw device identity / raw fingerprinting material stays inside AdNetwork SDK;
2. MMP does not receive device_fp_hash, OPRF inputs/outputs, bucket tags/tails, row keys, or req_id;
3. MMP may receive purpose-limited attribution material depending on selected integration option;
4. req_id remains server-side and is recovered by AdNetwork only after Confirm.
```

### 17D.2 选项总览

| 方案 | Claim 返回给 MMP | Confirm 回传给 AdNetwork | raw PII 是否出端 | MMP 是否拿稳定 join key | AdNetwork 是否能恢复 req_id | 推荐 |
|---|---|---|---:|---:|---:|---|
| Option 0: 明文 PII / device_fp | `device_fp_hash` / raw identity | raw identity / req_id | 是 | 是 | 是 | Reject |
| Option 1: Encrypted PII Relay | `Enc_AdNetwork(device_fp_hash)` | encrypted blob | 是，密文形式 | 取决于加密方式 | 是 | 仅 fallback |
| Option 2: OPRF/PSM + 明文 `mmp_touch_token` | `mmp_touch_token + creative metadata` | `mmp_touch_token + claim_token` | 否 | 是，touch-scoped | 是 | 可行 |
| Option 2A: OPRF/PSM + APUID/click_id compatibility | `ad_platform_user_id + opaque_click_id + creative metadata + claim_token` | `ad_platform_user_id + opaque_click_id + claim_token` | 否 | 是，取决于既有合同 scope | 是 | 兼容 profile |
| Option 3: OPRF/PSM + opaque `claim_token` only | `claim_token + creative metadata` | `claim_token` | 否 | 否 | 是 | Privacy-max |
| Option 4: Hybrid tracking-link token + opaque claim | `mmp_touch_token + claim_token + creative metadata` | 两者都回传 | 否 | 是，但 click 侧已存在 | 是 | 推荐折中 |
| Option 5: Aggregation-only | coarse matched / aggregate claim | aggregate confirm | 否 | 否 | 部分或不能 | fallback |

### 17D.3 推荐排序

```text
Primary recommendation:
  Option 4 — Hybrid: tracking-link mmp_touch_token + opaque claim_token

Privacy-max alternative:
  Option 3 — OPRF/PSM + opaque claim_token only

Compatibility profile:
  Option 2A — APUID/click_id, only when the MMP already receives equivalent scoped handles

Fast-launch fallback:
  Option 1 — Encrypted PII Relay

Not recommended:
  Option 0 — Plain device_fp_hash / raw identity

Aggregation fallback:
  Option 5 — Aggregation-only
```

Option 4 的关键叙事：

```text
Claim does not introduce a new user identifier.
It returns the same MMP-facing touch token that was already delivered on the tracking link.
The new information in Claim is the on-device match proof / claim_token.
```

必须控制：

- token name: `mmp_touch_token`, not `AdNetworkUserID` / `UserID`
- token generated from `req_id / touch context`, not raw `uid` alone
- scope: `mmp_partner_id / advertiser_id / adv_app_id / creative_id / touch_time_bucket`
- TTL <= attribution window
- no cross-advertiser reuse
- no cross-MMP reuse
- claim_token required for Confirm; token alone cannot confirm
- AdNetwork Server validates token + claim_token pair
- separate internal mapping: `mmp_touch_token -> req_id`

### 17D.4 Privacy-max 与 fallback

Option 3 只返回一次性的 `claim_token`：

```json
{
  "matched": true,
  "creative_id": 74019912,
  "campaign_id": 74012091,
  "ad_group_id": 7401209102,
  "touch_time_bucket": 4933923,
  "claim_token": "opaque_claim_token_v1"
}
```

它让 MMP 无法形成稳定 join key，但会削弱 MMP-side click/conversion join 和 reporting 灵活性。适合 privacy-max mode 或强监管场景。

Option 1 `Encrypted PII Relay` 只能作为 lower-privacy fallback。它只能说 `PII is encrypted in transit and opaque to MMP`，不能说 `raw PII stays on device`，因为 raw identity material 以可解密密文形式离开设备。

Option 0 明文 `device_fp_hash` / raw identity 直接违背 on-device measurement 主目标，应拒绝。Option 5 aggregation-only 最保守，但会削弱 creative-level reporting、request-level optimization 和 MMP SRN-style reconciliation。

### 17D.5 Legal / Privacy 需要重点判断的问题

建议直接给 legal / privacy review 以下问题：

1. `mmp_touch_token` 是否会被归类为 personal data / pseudonymous identifier？
2. 如果 `mmp_touch_token` 已经在 tracking link 阶段给到 MMP，Claim 阶段再次返回同一 token 是否属于新增披露？
3. token 是否必须避免包含 uid-derived semantics？
4. token 是否必须由 `req_id / touch context` 派生，而不是由 `user_id` 派生？
5. MMP 是否作为 processor / service provider / contractor 处理该 token？
6. MMP 是否被合同禁止用于 cross-advertiser join、profiling、retargeting 或二次用途？
7. token TTL 应该等于 attribution window，还是应更短？
8. 用户 opt-out / deletion 请求是否需要同步删除 `mmp_touch_token -> req_id` index？
9. Confirm 后 AdNetwork Server 用 token -> `req_id` 做 model optimization，是否需要单独披露和 consent / legitimate interest assessment？
10. `creative_id / campaign_id / ad_group_id` 返回给 MMP 是否属于 reporting metadata，还是与 token 组合后构成更高风险的 user-level measurement data？
11. 如果使用 `AdPlatformUserID`，它是否已经通过 tracking link 或既有 SRN contract 向该 MMP 披露？scope 是否限定到 advertiser/app/purpose？
12. 如果使用 opaque `click_id`，它是短 pointer 还是加密 payload？是否会因长度、稳定性或跨 app 复用而变成 durable identifier？
13. `touch_ts_ms` 是否允许 full precision，还是必须按 partner / region profile 做 rounding 或 bucketization？

### 17D.6 推荐措辞

不要写：

```text
No PII leaves device.
```

更稳妥的英文写法：

```text
Raw device identifiers and raw fingerprinting material do not leave the AdNetwork SDK process.
The MMP does not receive device_fp_hash, OPRF inputs/outputs, bucket tags, tails, row keys, or req_id.
Depending on the selected integration option, the MMP may receive either:
  (a) an opaque single-use claim_token only, or
  (b) a scoped mmp_touch_token that was already delivered through the tracking link, plus a claim_token.
In all cases, req_id remains server-side and is recovered by the AdNetwork only after Confirm.
```

中文写法：

```text
本方案控制的是 raw device PII / raw fingerprinting material 的出端风险，而不是宣称所有 measurement data 都不出端。MMP 不接触设备指纹、OPRF 输入输出、bucket/tag/tail、row key 或 req_id。根据 legal 选择的集成模式，MMP 可以只接收一次性的 opaque claim_token，或者接收一个已在 tracking link 阶段提供过的、广告主 scoped、touch-scoped 的 mmp_touch_token 加 claim_token。req_id 始终留在 AdNetwork Server 内部，并只在 MMP Confirm 后通过 token 映射找回。
```

### 17D.7 `AdPlatformUserID` / opaque `click_id` 兼容 profile

旧版技术文档把 `AdPlatformUserID + opaque click_id` 作为默认输出：MMP 拿到 APUID、campaign/adgroup/creative、touch time、opaque click_id 和 claim_token，Confirm 时原样回传，AdNetwork Server 再从 APUID/click_id 找回 `req_id`。这个模式和当前 RFC 的主链路并不矛盾，但它应该被收敛成 **compatibility disclosure profile**。

推荐映射如下：

| 旧文档字段 | 当前 RFC 默认字段 | 融合后的语义 |
|---|---|---|
| `AdPlatformUserID` | `mmp_touch_token` | 如果 APUID 已是 MMP-visible join handle，可作为 Option 2A；否则默认不要新增 network user handle |
| `click_id` | `opaque_click_id` / `mmp_touch_token` | gbraid-like opaque handle，MMP 只能存储和回传，不能解密、解释或跨目的复用 |
| `req_id` | `server_request_id` / internal `req_id` | 只在 AdNetwork Server 内部恢复，用于 optimization label，不给 MMP |
| `creative_id/campaign_id/ad_group_id` | 同名 reporting metadata | 可返回，但必须由 partner contract 和 region policy 控制 |
| `touch_ts_ms` | `touch_time_bucket` 或 bounded timestamp | full precision 不是默认；按 profile 决定是否 bucketize |

Option 2A 的启用条件：

1. APUID 或等价 join handle 已经在 tracking link / SRN contract 中存在；Claim 阶段不是新增一条跨 app 用户标识披露。
2. `opaque_click_id` 必须 AEAD-encrypted 或 server-side pointer 化，AAD 绑定 partner、advertiser、app、source、event、touch time bucket、key epoch 和 expiry。
3. `opaque_click_id` 不得包含 MMP 可解释的 raw `req_id`、device hash、OPRF output、row key、bucket tag/tail。
4. Confirm 必须同时校验 `claim_token`；APUID/click_id alone 不能完成 attribution finalization。
5. deletion / opt-out 必须同时作用到 APUID/click_id index、`mmp_touch_token -> req_id` index、claim replay cache 和未来 training release。
6. 如果 click_id payload 接近 500B，应使用 compact pointer 或 BR-2 validate 释放，不应 inline 到每条 candidate row。

因此，当前 RFC 的默认仍是 Option 4：`tracking-link mmp_touch_token + opaque claim_token`。Option 2A 是为了兼容某些 MMP/SRN 已经要求 APUID/click_id 的现实接入，不是为了引入一个新的 network-level user ID。

## 17E. FHE / 全同态加密落地方案

先把结论说死：FHE 不应该替代本文主链路里的 `OPRF/PSM + associated payload + Claim/Confirm`。更合适的位置是一个 optional hardened subflow，用来在少数高敏任务里减少服务端看到的明文输入。它解决的是“服务端能不能在不解密输入的情况下做固定计算”，不是“输出是否会泄露”“MMP 是否可信”“optimization label 是否合规”这些系统问题。

### 17E.1 FHE 到底保护什么

FHE 的心智模型很简单：

```text
SDK 持有 secret key
  -> SDK 把本地派生特征加密成 ciphertext
  -> Server 在 ciphertext 上跑固定 circuit
  -> Server 返回 ciphertext result
  -> SDK 或 threshold decryptor 解密 result
```

服务端看不到被加密的输入，也看不到中间结果。但这有三个容易误解的点：

- FHE 通常不隐藏 access pattern。比如请求了哪个 prefix bucket、返回多少 ciphertext、耗时多少，仍然可能泄露信息。
- FHE 不自动保护输出。输出解密后如果是 request-level match / score / label，仍然需要 release policy、TTL、anti-replay 和 purpose binding。
- FHE 不自动让复杂算法可行。比较、排序、top-k、字符串处理、正则、动态分支在 FHE 下都很贵，必须改写成固定电路或小模型。

因此，在本文里 FHE 是 `compute privacy` 组件，不是完整 measurement protocol。

### 17E.2 应该塞进哪三类位置

| 位置 | FHE 做什么 | 推荐 scheme | 适合度 | 备注 |
|---|---|---|---|---|
| 私密候选评分 | SDK 加密本地派生特征，server 对 prefix bucket 下的 candidate rows 计算 encrypted match score | BFV / BGV | 中 | 适合 exact integer / bit feature；要 padding，避免 candidate_count 泄露 |
| aggregate 加固 | SDK 或 confidential plane 加密 contribution，collector 只做 encrypted sum / histogram，threshold decrypt 后 release | BFV / BGV / CKKS | 中高 | 如果已有 DAP/VDAF，多数场景优先 DAP；FHE 更适合单 collector 不想看明细值 |
| 小模型加密推理 | SDK 加密低维特征，server 评估小型 logistic / linear / shallow tree / quantized model | CKKS / TFHE / Concrete-style integer FHE | 中 | 可用于 fraud/risk/eligibility bucket；不建议第一版用于主 bidder hot path |

不建议的落点：

- 不建议用 FHE 替代 `MMP Confirm`。FHE 不知道 MMP winner selection。
- 不建议用 FHE 直接返回 `server_request_id`。这样会破坏 partner-facing boundary。
- 不建议用 FHE 做完整 ad ranking / auction。排序、探索、频控、budget pacing 的电路和状态太复杂。
- 不建议把 raw `ip` / raw `boot_time` 明文编码后直接加密上发，然后宣称“PII 不出端”。严格说，raw PII 仍以可解密密文形式离开设备；这应被建模为 encrypted confidential processing，而不是 raw-local-only。

### 17E.3 推荐默认：FHE-assisted private candidate scoring

如果要把 FHE 塞进 ODM / SRN 主链路，最自然的落点是 Step E 的替代实现：

```text
MMP SDK Ask
  -> AdNetwork SDK 本地派生低维 feature
  -> AdNetwork SDK 用 FHE public key 加密 feature vector
  -> AdNetwork Server 对 prefix bucket candidate rows 评估固定 scoring circuit
  -> Server 返回 encrypted score vector
  -> SDK 解密并本地选择 bounded candidate
  -> SDK 返回 ClaimResponse 给 MMP
  -> MMP Confirm
  -> AdNetwork Server token_to_req_id_join
```

这个流程里，FHE 只替换 “server 如何参与候选评分”。它不改变以下不变量：

- MMP 仍然不看 `device_fp_hash`、OPRF output、row key、`req_id`。
- `ClaimResponse` 仍然只返回 `mmp_touch_token + claim_token + allowed metadata`。
- AdNetwork Server 仍然只在 Confirm 后恢复 `req_id`。
- optimization plane 仍然只消费 policy-bound label / feature release。

一版可上线的 circuit 不应贪心。建议从 exact bit / integer feature 开始：

```text
score(candidate, encrypted_features) =
  w1 * eq(country_bucket)
  + w2 * eq(install_day_bucket)
  + w3 * eq(app_bundle_bucket)
  + w4 * eq(touch_time_bucket)
  + w5 * eq(coarse_network_bucket)
```

然后 server 返回固定长度、padding 后的 encrypted score vector。SDK 解密后只允许释放：

- `matched_candidate_count`
- `selected_candidate_slot`
- `match_quality_bucket`
- `claim_token`
- `mmp_touch_token`

不允许释放完整 score vector、raw feature、row key、candidate payload 或 `server_request_id`。

### 17E.4 Aggregate FHE：什么时候比 DAP 更合适

对于 aggregate reporting，FHE 可以做：

```text
encrypted_count = Enc(1)
encrypted_value = Enc(revenue_bucket_value)
collector_sum = EvalAdd(encrypted_count/value over batch)
threshold decrypt only if crowd threshold and budget pass
```

它的优点是 collector 在聚合前看不到单条 contribution 明文。它的缺点是：

- 去重、contribution bounding、minimum crowd threshold 仍然要在密文外或 confidential sidecar 中治理；
- repeated collection 仍然有 privacy cost；
- threshold decrypt 和 key share governance 很重；
- 如果需要多 helper / anti-replay / standardized collection，DAP/VDAF 的协议面更完整。

所以本文推荐：

- partner-facing aggregate 默认优先 `DAP/VDAF + DP budget ledger`；
- 单方 collector 但不想看明细 value 时，可以用 FHE encrypted sum 作为加固；
- high-value revenue / ROAS aggregate 可以用 FHE 先做 encrypted bounded sum，再在 release 前走 threshold / DP / audit。

### 17E.5 小模型加密推理：适合做派生桶，不适合直接做大规模优化

FHE inference 在本文里最适合做 `ServerFeatureDerivationRecord` 的 hardened 版本。例如 SDK 把几个低维敏感派生特征加密，server 评估一个小模型，输出 encrypted risk score；SDK 或 threshold decryptor 解密后只释放 bucket：

```text
encrypted_features -> encrypted_model_score -> risk_bucket
```

推荐用途：

- fraud risk bucket
- reinstall likelihood bucket
- measurement eligibility bucket
- coarse conversion-quality bucket

不推荐用途：

- 直接训练 FHE GBDT / deep model 作为主 bidder；
- 在 FHE 中做完整 feature engineering；
- 在 FHE 中做 online auction ranking；
- 把 encrypted inference score 明文回传给 MMP。

工程上可以评估两类路线：

- CKKS / BFV / BGV 库路线：OpenFHE、Microsoft SEAL、Lattigo，适合团队有密码工程能力并能控制参数。
- 编译器 / ML 框架路线：Zama Concrete / Concrete ML，适合先验证小型量化模型的 encrypted inference。

无论哪条路线，生产 RFC 都必须记录：

- model / circuit version
- quantization policy
- precision / approximation error
- latency p50/p95/p99
- ciphertext size
- key epoch
- output bucket policy
- fallback path

### 17E.6 参数和库的生产建议

推荐按算法语义选 scheme，而不是先选库：

- BFV / BGV：exact integer arithmetic，适合 equality、计数、bitset、bucket score。
- CKKS：approximate real arithmetic，适合线性模型、近似分数、向量点积；不适合 exact attribution truth。
- TFHE / FHEW / CGGI：bit / lookup-table / comparison 类 circuit 更自然，但吞吐和工程复杂度要单独压测。
- Threshold FHE：当不希望单一服务或单一 SDK 拥有解密能力时使用；治理成本明显更高。

库选择建议：

- C++ server evaluator：优先评估 OpenFHE 或 Microsoft SEAL。
- Go microservice：可评估 Lattigo。
- encrypted ML prototype：可评估 Concrete / Concrete ML。
- 移动端 SDK：谨慎。不要默认把完整 FHE runtime 塞进主 app；优先让 SDK 只做 key management、encoding、encryption/decryption 和小规模测试，重计算放服务端。

生产上线前必须做四类 benchmark：

- ciphertext size：单次 Ask 上下行能否接受；
- latency：是否会影响 install / first_open / deep link callback；
- battery / CPU：移动端加解密是否可控；
- correctness drift：CKKS / quantized inference 是否改变 attribution 或 risk bucket。

### 17E.7 与 OPRF/PSM 的取舍

| 方案 | 服务端是否看明文 query material | 客户端是否可能看到 candidate 结构 | 性能 | 默认建议 |
|---|---:|---:|---:|---|
| OPRF/PSM + payload | 低，取决于协议实现和 bucket | 中，需要 payload/padding 控制 | 好 | 默认主链路 |
| FHE private scoring | 更低，输入可加密 | 中高，解密 score 后需限制输出 | 中到差 | hardened profile |
| PIR / HE retrieval | 更低，可隐藏查询 | 低到中，取决于返回设计 | 中到差 | 特殊高敏场景 |
| MPC / PJC | 多方信任更强 | 低 | 中到差 | 跨方 reconciliation |

换句话说，FHE 不是“比 OPRF/PSM 更现代，所以替换它”。它是另一个 trade-off：用更高计算和工程成本，换取服务端对某些输入的更低可见性。对大部分广告 attribution hot path，OPRF/PSM 更像产品默认；FHE 更像少数高敏 partner、强监管 region 或高价值 aggregate 的加固层。

### 17E.8 最小 POC 范围

如果要真实推进，建议不要从完整 ODM 开始。先做一个 4 周 POC：

1. 只选一个 task：`install_candidate_scoring_fhe_poc`。
2. 只选一个 region / app / campaign allowlist。
3. candidate bucket 固定 padding 到 `1024`。
4. feature 只用 5-8 个低维 bucket，不使用 raw IP / raw boot time。
5. 用 BFV/BGV 实现 exact score，先不做 CKKS。
6. server 只返回 encrypted score vector。
7. SDK 解密后只输出 `matched_candidate_count` 和 `selected_candidate_slot`。
8. 最终仍走 `ClaimResponse -> MmpConfirmRequest`。

POC 成功标准不应该是“FHE 能跑起来”，而是：

- p95 latency 在可接受范围；
- ciphertext size 不破坏移动网络体验；
- match rate 与 OPRF/PSM baseline 差异可解释；
- MMP 不新增任何 raw / internal field；
- optimization label 仍能在 Confirm 后找回 `req_id`；
- fallback path 明确，FHE 失败不等于 attribution negative。

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
- FHE hardened profile 的默认 POC 是否选择 BFV/BGV exact scoring，还是 CKKS / Concrete ML encrypted inference？
- 如果 FHE response 由 SDK 解密，如何限制 SDK 从 score vector 中学习过多 candidate store 结构？
- 如果 FHE response 改成 threshold decrypt，collector / helper 的 trust model 与 MMP legal role 如何定义？
- incrementality calibration 的最小实验池应按 campaign、advertiser vertical、geo，还是 creative family 建模？
- deletion / consent withdrawal 对历史 aggregate release 的处理是否采用 freeze、correction，还是只影响 future release？
- multi-ID private matching 中，哪些 identifier type 允许同一 task 内共同参与 OPRF/PSM，哪些必须拆成独立 task，避免 linkage amplification？
- 实时 streaming DP 的默认 privacy unit 应该选 `app_instance`、advertiser first-party user，还是 region / platform 分 profile 配置？
- ICM / ODM 的 `odm_error`、open-beta rollout、Kids app support 和 6 个月 retention 是否应进入所有 MMP 的统一 partner contract，还是先作为 Google-compatible extension？

## 19. 最终建议

建议的工程优先级是：

1. 先把边界做对：raw device material 不出 AdNetwork SDK crypto boundary，`req_id` 不给 MMP，`odm_info` 不复用。
2. 再把可用性做稳：采用 `MMP Ask -> AdNetwork SDK OPRF/PSM -> Claim -> MMP Confirm`，默认 Option 4：tracking-link `mmp_touch_token + opaque claim_token`。
3. 再把优化闭环做稳：Confirm 后用 `mmp_touch_token -> req_id` 恢复 request-level label，支撑 creative_id x req_id 级别训练。
4. 再把因果校准做稳：用 RCT / holdout / PIE-style calibration 给 attribution label 加 `incrementality_weight_micros`，不要把 `is_attributed=true` 当成 `incremental=true`。
5. 再把训练隐私做稳：每个 trainer 必须有 `TrainingPrivacyPolicy`，区分 `NO_DP_BASELINE`、`LABEL_DP`、`SEMI_SENSITIVE_DP` 和 `FULL_USER_LEVEL_DP`，不要把 raw PII 派生物和归因 label 混进一张无治理训练表。
6. 再把多标识符和实时报表边界做稳：multi-ID matching 必须有 `MultiIdentifierPrivateMatchPolicy`，streaming aggregate release 必须有 `StreamingDpReleasePlan`，不能用一个万能 user ID 或一个 `epsilon` 字段糊过去。
7. 最后持续加固：aggregate DP、verifiable workflow、PJC/PSI、DAP/VDAF 对齐；FHE 只作为高敏 task 的 optional hardened profile，而不是默认替代 OPRF/PSM。

一句话总结：真正有生产价值的 on-device measurement，不是把服务器删掉，也不是宣称所有 measurement data 都不出端，而是把“哪些数据能离开 SDK、去哪一层、以什么粒度、为了什么目的离开，谁能在 Confirm 后恢复 req_id，以及 trainer 对哪些字段承担什么隐私 profile”定义成严格协议。

## 20. 附录：研究、标准与产品依据

这一节是第 5 节索引背后的详细依据。它不属于主阅读路径；当你想追溯“为什么正文里要有某个字段、边界或治理要求”时，再回来看这一节。

### 20.1 Ephemeral on-device analytics 已经工程化

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

### 20.2 Confidential server-side processing 已经不是“概念”

[Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)（2024）和 [google-parfait/confidential-federated-compute](https://github.com/google-parfait/confidential-federated-compute) 说明：

- 服务端可以在 TEE/CVM 中完成隐私敏感的 processing graph；
- 上传对象可以绑定允许的 workflow；
- verifiable processing 需要 manifest、signature、attestation，而不是只说“我们会小心处理”。

因此，本 RFC 采用 `confidential plane` 作为 request-level join 的默认部署边界。

### 20.2A Trust graph 研究说明“分层信任”比“全本地化”更贴近现实

[Differential Privacy on Trust Graphs](https://research.google/pubs/differential-privacy-on-trust-graphs/)（ITCS 2025）研究的是一个更贴近现实协作系统的前提：每个参与方只信任一部分邻居，而不是所有人，也不是任何人都不信任。

这对广告场景里的 ODM + MMP + SRN 很有启发，因为这里天然就有：

- advertiser app 对 ad network SDK 的有限信任；
- MMP 对 ad network claim 的协议化信任，而不是原始数据级信任；
- ad network 对 confidential workflow 的高信任，但对 partner-facing output 的低披露要求。

因此，本文没有把架构写成“所有有价值的事都必须端上做完”，而是把不同操作放进不同 trust domain：端上保留高敏原料，confidential plane 承接跨事件验证与派生，optimization plane 只消费释放后的低敏信号，aggregate plane 只消费聚合贡献。

### 20.3 DAP / VDAF / Taskprov 已经足够成熟到值得对齐对象模型

截至 2026-04-30：

- [DAP draft-ietf-ppm-dap-17](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/) 最近一次更新时间是 2026-01-30，Datatracker 当前仍显示 `WG Consensus: Waiting for Write-Up`；
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

### 20.4 Contribution bounding 现在是生产问题，不是论文角落

[Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)（2025）以及 [It's My Data Too](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)（ICML 2025）都指向同一件事：

- 一个训练样本可能对应多个“拥有者”或多个 touch；
- multi-touch / multi-user 数据里，contribution bounding 是一等公民；
- 如果 bounding 只藏在离线 SQL 里，后续隐私和训练质量都不可控。

因此，本 RFC 要求：

- `conversion_group_id`
- `credit_fraction_micros`
- `contribution_policy_id`

必须进入 label contract。

### 20.5 交互式 release 的隐私分析已经不能忽略

[On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)（PETS 2025）强调：

- 查询会依赖之前的输出；
- 数据库本身也会因为系统状态变化而变化；
- release 不能被当成“静态 SQL 导出”。

对本 RFC 的含义是：

- aggregate reporting 必须有显式 budget ledger；
- provisional / final / correction 必须有规则；
- 任何重复 collect 都必须视为额外 privacy cost 或额外治理风险。

### 20.6 “DP 可审计”已经从研究走向工程

[DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)（2024）和 [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)（NeurIPS 2025）说明：

- DP 不能只信数学证明和实现自信；
- 黑盒审计、持续审计、序列式审计都已经可做；
- 如果后续引入 DP release，审计栈应该提前预留。

进一步地，[Empirical Privacy Variance](https://research.google/pubs/empirical-privacy-variance/)（ICML 2025）提醒了一个很实际的问题：即使名义 `epsilon/delta` 相同，不同训练超参数也可能表现出明显不同的经验隐私风险。对本 RFC 的含义是：如果 Phase 2/3 把 DP 带到 optimization training，就不能只把 privacy accounting 结果写进 PPT，而要把 `noise_multiplier`、`clipping_norm`、`sampling_policy_id`、`privacy_audit_profile_id` 和经验评估结果一起写入训练治理契约。

### 20.7 TEE 不是 magic box

2026 年的 [SNPeek](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/) 和 [TDXRay](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/) 说明：

- Confidential VM 仍然存在 side-channel 风险；
- 工作负载本身必须考虑 access pattern、timing、batching、debug 策略；
- “放进 TEE 就安全”是错误的。

[Hardening Confidential Federated Compute against Side-channel Attacks](https://arxiv.org/abs/2603.21469) 则进一步说明：即使系统已经围绕 DP / confidential compute 设计，side-channel 仍可能绕过原本假设的 release 边界，因此 side-channel hardening 必须和 privacy mechanism 一起设计，而不是在上线后补洞。

因此，本 RFC 对 confidential workflows 要求分级、限 debug、加回归测试。

### 20.8 公开产品形态已经验证 ODM / ICM 是现实路径

截至 2026-04-30：

- Google Ads 帮助文档显示 [Integrated Conversion Measurement](https://support.google.com/google-ads/answer/16203286?hl=en-EN) 自 2025 年 5 月起逐步 rollout；
- [on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en) 文档指出 event-data 方案使用临时、去标识化事件数据，且 Firebase iOS SDK `11.14.0` 于 2025 年 6 月提供相关版本；
- [Integrated Conversion Measurement developer guide](https://developers.google.com/app-conversion-tracking/api/integrated-conversion-measurement) 最近一次更新时间是 `2025-10-22 UTC`，仍要求 app 先设置 first launch time，再抓取 `aggregateConversionInfo` 并作为 `odm_info` 透传；
- [request/response spec](https://developers.google.com/app-conversion-tracking/api/request-response-specs) 最近一次更新时间是 `2026-03-10 UTC`，已明确 `odm_info` 是 ICM 所需字段，并把 `ad_event_id`、`attributed`、`fot`、`ctry_c`、`eea`、`ad_user_data`、`ad_personalization` 写成正式接口字段；
- [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk) 说明 standalone SDK 路线可行。

同时，Google 2026 年的产品文档还把两个生产边界写得更清楚了：

- [Understanding iOS App campaign measurement and reporting](https://support.google.com/google-ads/answer/16771743) 明确 ICM 是 AAP UI 中的 granular, event-level, cross-network view，而不是 Google Ads UI 中的同一条 reporting surface；
- [on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en) 明确该功能对位于 `EEA`、`UK`、`Switzerland` 的用户 inactive。

此外，Google 官方 [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk) 仓库当前显示最新 release 为 `3.5.0`（2026-04-16），README 还明确说它会引入 “additional de-identified, temporary signals, such as data derived from IP-address-based attributes” 来改进第三方 AAP 场景下的优化和 reporting。它直接支持了本文的一个核心边界判断：`raw_ip` 一类字段并不是“完全没有业务价值”，但它们进入优化面的方式应当是“短期、受控、去标识化派生”，而不是把原始值或稳定可重识别前缀直接送入训练。

这直接支持本文把 `ODMInfoEnvelope` 视为正式协议对象，而不是 SDK 内部细节；也支持把 `reporting_surface_id`、`region_eligibility_code` 和 `feature_active=false` 视为正式状态，而不是埋在 FAQ 里的例外逻辑。

### 20.9 MMP 的 SRN 工作流没有消失

[AppsFlyer attribution model](https://support.appsflyer.com/hc/en-us/articles/207447053-AppsFlyer-attribution-model) 页面在 `2026-04-19` 更新，[Adjust Self-attributing network setup](https://help.adjust.com/en/article/self-attributing-network-san-setup) 与 [Adjust Assists](https://help.adjust.com/en/article/assists) 在 2026 年当前版本里仍表明：

- MMP / attribution provider 先检测 install / event；
- 再向 self-reporting network 查询或通知；
- network 基于自身 engagement data 做 claim；
- 某些回调和 postback 仍依赖 device ID 或 network-specific transaction object。

所以，on-device measurement 必须服务于 SRN，而不是与 SRN 平行、互不相干。

进一步地，截至 2026-05-01，产品文档还显示三个值得写进 RFC 的现实：

- AppsFlyer 当前文档仍明确区分 deterministic、probabilistic、SRN query、assist 等多条归因路径；
- [AppsFlyer Enhanced attribution model](https://support.appsflyer.com/hc/en-us/articles/41442782045073-About-the-Enhanced-attribution-model) 在 2026-03-19 公开说明了设备侧 flooding 检测后仅保留 eligible click / impression 的做法。
- [Adjust Assists](https://help.adjust.com/en/article/assists) 进一步把 SAN 现实写得很直白：Adjust 会把 SDK 上报的每个 app session 发给 SAN，若 network 识别到活动则 claim attribution；这意味着 `session_start` / `first_open` 级别的 request trace 对排障和优化都是真需求，而不是“日志细节”。

这对本文的直接影响是：

- RFC 不能只建模“最后一次 click 是否胜出”，还要建模 `eligible_candidate_count`、`prefilter_candidate_count`、`assist_count` 这类质量上下文；
- request-level optimization 不能只消费二元 `is_attributed`，还应消费 winner 选择过程中的质量切片与延迟反馈。

### 20.10 Privacy Sandbox 的 aggregate 优化研究说明 bucket 设计本身也是协议

[Summary Reports Optimization in the Privacy Sandbox Attribution Reporting API](https://research.google/pubs/summary-reports-optimization-in-the-privacy-sandbox-attribution-reporting-api/)（PETS 2024）虽然主要针对 Attribution Reporting API，但对本 RFC 有一个很现实的启发：

- 同样的 privacy guardrail 下，bucket 设计和 contribution budget 分配会显著影响可用性；
- “先把数据聚出来，之后分析时再想怎么切桶” 往往太晚；
- measurement task、aggregation key、value bucket、reporting window 应一起设计。

因此，本 RFC 把 `aggregation_key_schema_id`、`value_bucket_schema_id`、`reporting_window_id` 视为 production contract，而不是 BI 侧随手改的维表配置。

### 20.11 W3C Attribution Level 1 让 aggregate plane 的边界更清晰

[W3C Attribution Level 1](https://www.w3.org/TR/attribution/) 当前索引显示的 Working Draft 日期是 `2026-05-14`。它最重要的启发不是“移动 App 要照搬浏览器 API”，而是进一步确认了四件事：

- on-device attribution 与 off-device aggregation 可以明确分层；
- aggregate service `MUST` 处理 anti-replay，而不是只做求和；
- privacy budget、epoch 和 per-site / per-surface 限额应该是正式协议状态，而不是分析平台外部约定。
- multi-party aggregation、DAP/VDAF 和 collector state 应作为一等设计对象进入协议，而不是留给后续实现随意发挥。

对本 RFC 的意义是：广告 App 场景里的 aggregate reporting plane 也应该显式拥有 `budget ledger + replay rejection + report lifecycle + collector identity`，而不是只导出一个聚合表。

### 20.12 Verifiable local reporting 说明“端上上报正确性”也要入 RFC

[Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)（2025）指出一个很现实的问题：

- 只要 measurement 的部分逻辑发生在设备侧，系统就不只是担心“服务端看太多”，还要担心“端上报了假的东西”；
- 本地私有化或本地裁剪后的上报，如果没有 provenance 约束，容易被 poisoning、flooding、伪造 engagement 或脚本化设备利用；
- 可验证随机性、第三方 ground truth、或至少更强的 event provenance，会明显改变系统可用性上限。

对广告场景的直接含义是：

- RFC 不能只定义 `artifact` 长什么样，还要定义 `artifact` 证明了什么；
- 端上 `impression` / `click` / `first_open` / `purchase` 的来源级别，应该进入 policy；
- `artifact_auth_level`、`event_provenance`、`sdk_build_fingerprint` 这类字段值得成为正式 contract，而不是埋在风控旁路里。

### 20.13 ODC / ODM 逆向证据把 OPRF / PSM 放回主链路

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

### 20.14 截至 2026-05-05 的官方产品资料进一步收紧了生产契约

这次复查里，最值得写进 RFC 的不是“又多了一篇公式论文”，而是几份官方文档已经把一些原本容易停留在推断层的生产约束写得更明确了。

先看 Google 官方产品文档：

- `About on-device conversion measurement for iOS App campaigns` 当前页面明确把 event-data 方案描述为“derived from device signals like IP addresses and timestamps”，并在 `Optional ad relevance improvements` 里进一步写明可使用额外信号 “like IP addresses”，但同时仍强调输出应是 de-identified 的、privacy-preserving 的。
- 同一页面现在还明确写出实施约束：ODM 目标事件必须来自 Firebase SDK events，而不是 generic S2S Measurement Protocol event。
- `Integrated Conversion Measurement` 开发文档当前仍要求在 first launch shortly after 获取 `aggregateConversionInfo`，并作为 `odm_info` 透传；页面底部标记的最后更新时间是 `2025-10-22 UTC`。
- `Request/Response Specifications` 当前摘要和正文继续强调两个生产细节：`ad_event_id` 要保留并在 cross-network follow-up 使用；cross-network request 即使成功也总是 generic `HTTP 200` 且没有 response body，因此“请求被接受”与“归因事实成立”必须分模。

这些资料对本 RFC 的直接含义是：

- 原始 `raw_ip`、`boot_time_ms`、`User-Agent` 可以存在于 device/confidential plane，但 optimization plane 只该看到 policy-bound derived release，而不是原值。
- 事件来源必须成为正式协议字段，而不是接入备注。推荐至少持久化 `event_source_system`、`sdk_family`、`source_sdk_version`、`is_firebase_native_event`，因为 ODM 是否生效已显式依赖这条边界。
- `request_accepted`、`response_empty_body`、`ad_event_id_retained` 这类 compat 状态必须与最终 `is_attributed` 分开建模。

再看 2026 年当前的 MMP / SRN 产品现实：

- AppsFlyer attribution model 页面当前更新时间是 `2026-04-19 13:14`。它已明确写出：iOS 上 SRN device-ID matching 依赖 ATT consent；probabilistic modeling 的输出是 aggregate campaign-level report，而不是 individual device identification；并且 engaged click / engaged view 已成为正式 engagement 类型。
- AppsFlyer Enhanced attribution 页面当前更新时间是 `2026-03-19 12:25`。该页不仅说明 flooding 场景下只保留 eligible clicks / impressions，还明确把 `total candidates for attribution` 暴露为可观测指标。
- Adjust Assists 当前页面继续明确：对 SAN，Adjust 会把 SDK 报告的每个 app session 发给 SAN；如果 network 识别该活动，则由 network claim。

这些资料把本 RFC 的另外三条设计要求坐实了：

1. `AttributionDecisionRecord` 里应保留候选量级、eligible 过滤和 engagement 类型，而不只是最终 winner。
2. SRN ask/claim/confirm 的观测粒度应至少覆盖 `session_start` / `first_open` 级 trace，否则生产排障会断链。
3. optimization plane 可以先不做 user-level DP，但不能把 compat-only 字段、ATT gating 状态和候选竞争质量信息混成一个黑盒标签。

### 20.15 截至 2026-05-07 的最新 delta：runtime trace 和 debug privacy 也要进 RFC

这次补充调研后的核心变化是：RFC 不能只写 measurement object 和归因公式，还要把 SDK 运行态、日志隐私、MMP 接入副作用一起写进生产契约。否则系统上线后会在“为什么没有归因”“为什么 deep link 延迟”“为什么 `odm_info` 缺失”这些问题上退回通用日志，而通用日志恰恰最容易泄漏 PII。

标准侧的最新状态没有推翻本文的 aggregate 设计，反而强化了它：

- [DAP draft-ietf-ppm-dap-17](https://www.ietf.org/archive/id/draft-ietf-ppm-dap-17.html) 发布于 2026-01-30，仍把多方 aggregate measurement、report lifecycle、batch、collection、anti-replay 和 VDAF 绑定放在协议核心。
- [DAP Extensions for the Attribution API -01](https://www.ietf.org/ietf-ftp/internet-drafts/draft-thomson-ppm-dap-attribution-01.html) 发布于 2026-02-18，目标就是把 Attribution API 依赖的 DP aggregation 和 operating modes 对齐到 DAP。

这说明本 RFC 里的 `AggregateCollectorBudgetState` 不应简化成 BI 表参数；它应该继续保留 `collector_surface_id`、`budget_scope_id`、`privacy_budget_epoch_id`、`lifecycle_state`、`replay_rejected` 这类协议状态。Phase 1 可以不部署完整 DAP，但对象模型不要背离 DAP。

产品侧的最新状态进一步说明 MMP / AAP integration 已经是正式工程面：

- Google Ads 的 [on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en) 明确 event-data 方案来自 device signals such as IP addresses and timestamps，并要求目标事件来自 Firebase SDK events，而不是 generic S2S Measurement Protocol events。
- Google 开发者 [request/response spec](https://developers.google.com/app-conversion-tracking/api/request-response-specs) 当前最后更新时间是 `2026-03-10 UTC`，继续把 `odm_info`、`ad_event_id`、`fot`、`ctry_c`、`eea`、`ad_user_data`、`ad_personalization` 写成正式接口字段，并说明有效 cross-network attribution request 是空 body 的 generic `HTTP 200`。
- Singular 的 [Google Ads attribution integration](https://support.singular.net/hc/en-us/articles/115003252786-Google-Ads-AdWords-Mobile-App-Campaigns-Attribution-Integration) 当前文档把 ICM 写成 open beta：Android 自 2026-03-30 起对所有广告主开放，iOS 自 2025-11-12 起对所有广告主开放；同时说明 ICM attribution 在 Singular 中可表现为 click-through install、probabilistic attribution，且 sub network type 不可用。
- Singular 的 [iOS SDK Advanced Options](https://support.singular.net/hc/en-us/articles/36198405689243-iOS-SDK-Advanced-Options?navigation_side_bar=true) 还把 Google ODM SDK、Singular iOS SDK `12.8.1+`、`enableOdmWithTimeoutInterval`、deep link callback delay 写成接入要求。

这些资料直接要求新增 `SdkMeasurementRuntimeTrace`：生产系统需要知道 `odm_sdk_present`、`mmp_sdk_version`、`odm_fetch_timeout_ms`、`sdk_init_delay_ms`、`deep_link_callback_deferred`、`event_source_system`、`is_firebase_native_event`，但这些状态只属于 integration health / confidential debug plane，不属于 attribution truth，也不属于 optimization trainer。

研究侧的最新补充则把 debug privacy 和 trust boundary 拉回主协议：

- [Proteus: A Practical Framework for Privacy-Preserving Device Logs](https://arxiv.org/abs/2603.06540)（2026-03-06）说明移动端日志可以在生成点先做 keyed pseudonymization，再用时间轮转密钥加密；服务端只获得特定时间窗的 controlled sharing，而不是长期明文 PII。它对本 RFC 的启发是：SDK debug trace 也要有 `pii_transform_policy_id`、`log_key_epoch_id`、`debug_trace_window_id` 和 `support_grant_id`。
- [Who am I Talking to?](https://research.google/pubs/who-am-i-talking-to-a-large-scale-measurement-of-surface-attribution-across-real-world-security-and-privacy-interfaces/)（CHI 2026）说明用户对 UI / permission / surface 来源的识别能力并不可靠。对 ODM / MMP 接入的含义是：不要把隐私边界建立在“用户能看懂哪个 SDK 在收集什么”的假设上，而要依赖协议级 purpose binding、本地 capability registry、字段级 release policy 和可审计 runtime trace。

因此，本文截至 2026-05-07 的推荐收紧如下：

1. `MMP Ask -> Ad Network Claim -> MMP Confirm` 仍是主链路，但 Ask 之前的本地 capability 和 runtime trace 必须被建模。
2. `odm_info` 仍是 compatibility bridge object，但它的生成条件、缺失原因、timeout 和 source event type 必须可审计。
3. SDK debug log 必须默认按 field policy 最小化，不能成为 raw IP / boot time / deep link / User-Agent 的旁路出口。
4. optimization plane 可以继续不先上 DP，但必须把 runtime trace、compat status、attribution truth、training label 分成不同对象。
5. aggregate plane 继续对齐 DAP / VDAF / Attribution extension，对外 release 不应退化为没有 lifecycle / budget / replay 语义的普通聚合表。

### 20.16 FHE 工程库已经可用，但仍要按“固定小电路”落地

截至 2026-05-07，FHE 的工程生态已经足够成熟到可以做 POC，但还没有成熟到应该无脑塞进广告 attribution hot path。

可用组件大致分四类：

- [OpenFHE](https://openfhe-development.readthedocs.io/en/latest/) 当前文档显示支持 BFV、BGV、CKKS、FHEW/TFHE/CGGI 等常见方案，并包含 threshold FHE、proxy re-encryption 等扩展。它适合作为 C++ server evaluator / research-to-production POC 基座。
- [Microsoft SEAL](https://github.com/microsoft/SEAL) 是成熟 C++ HE 库，支持 BFV / BGV / CKKS，并明确提醒 FHE 不是 generic technology：比较、排序、正则、动态分支等通常不适合直接搬进 HE。
- [Lattigo](https://github.com/tuneinsight/lattigo) 是 Go 生态里的 RLWE-based HE / multiparty HE 库，适合 Go microservice 和分布式系统原型。
- [Concrete / Concrete ML](https://docs.zama.org/concrete-ml/1.4/) 把 FHE 编译和 encrypted ML inference 做得更接近 ML 工程师工作流，适合验证量化小模型、logistic / tree / shallow neural inference 的 feasibility。

这些资料对本文的设计含义是：

- FHE 适合固定、低深度、可量化、可 padding 的小计算；不适合把整条 SRN attribution workflow 加密后“自动运行”。
- exact attribution / equality / count 应优先考虑 BFV / BGV；approximate score / vector dot product 可考虑 CKKS；bit / comparison / lookup-heavy circuit 才考虑 TFHE/FHEW/CGGI 类路线。
- FHE 参数必须是协议对象的一部分：`scheme`、`poly_modulus_degree`、`coeff_modulus_bits`、`plaintext_modulus`、`scale`、`multiplicative_depth`、`key_epoch_id`、`circuit_id` 都会影响安全性、正确性和性能。
- 对移动广告来说，真正的瓶颈通常不是“能不能算”，而是 ciphertext size、SDK CPU/battery、first_open latency、deep link callback 延迟和 fallback 语义。

因此本文把 FHE 放在 Profile D，而不是 Profile A/B/C。推荐先从 `FHE-assisted private candidate scoring` 或 `encrypted aggregate sum` 做 POC；不要从 “FHE 版完整归因系统” 开始。

### 20.17 截至 2026-05-08 的最新 delta：touchpoint 真实性也要进 RFC

这次复查新增的关键外部信号是 IAB Tech Lab 的 OM SDK device attestation。它不直接解决 conversion 侧归因，但会影响 on-device measurement 的输入质量：如果 impression / click 本身来自伪造设备或伪造 supply path，后面的 OPRF、Ask、Claim、Confirm 都可能“正确地处理了错误触点”。

公开资料给了三点可落地结论：

- [IAB Tech Lab device attestation release](https://iabtechlab.com/press-releases/device-attestation-support-in-open-measurement-sdk/) 把该能力定位为 OM SDK 中用于 CTV / mobile device spoofing 的质量信号，并说明它采用 IETF Privacy Pass Protocol 适配广告验证场景。
- [Open Measurement Device Attestation Implementation Guidance](https://iabtechlab.com/wp-content/uploads/2025/10/Open-Measurement-Device-Attestation-Implementation-Guidance.pdf) 明确采用 Privacy Pass 的 `Client / Verifier / Attester / Issuer` 角色模型，并提醒 attestation request 不应携带 device-level 或 user-level 信息。
- [RFC 9576](https://www.ietf.org/rfc/rfc9576.html) / [RFC 9577](https://www.ietf.org/rfc/rfc9577.html) 的核心语义是 unlinkable authorization token，而不是可追踪身份凭证；这与本文“不把 attestation token 变成 user join key”的边界一致。

对本 RFC 的直接改动是：

1. 新增 `DeviceSupplyPathAttestationReceipt`，把 attestation 作为 request-scoped quality evidence 记录。
2. `ServerFeatureDerivationRecord` 只释放 coarse quality bucket，例如 `device_authenticity_bucket`、`supply_path_quality_bucket`。
3. optimization plane 可以用这些桶做 fraud quality filtering / sample weighting，但不能把 token digest 当成设备标识。
4. MMP / SRN payload 不应接收原始 attestation token、challenge、platform blob 或 verifier 私有字段。

这条增量的本质是：on-device measurement 的隐私设计不能只看 conversion side。完整闭环还要保证 touchpoint side 没有被伪造流量污染，否则 request-level optimization 会把供应链真实性问题错学成用户偏好问题。

### 20.18 截至 2026-05-09 的最新 delta：把 attribution、incrementality、privacy controls 拆开

这次复查新增的关键信号不是单个更强的加密原语，而是三个系统边界变得更清楚：

1. 公开 attribution 标准继续向 aggregate / DP / anti-replay 收敛。
2. 行业 DCR / PET 标准开始把 matching、attribution computation、report generation 写成可互操作流程。
3. 广告优化研究重新强调 attribution 与 incrementality 不是同一个量。

具体依据如下。

- [W3C Attribution Level 1](https://www.w3.org/TR/attribution/) 在 `2026-05-14` 工作草案中继续把广告效果测量定义为 aggregate statistics，并把 aggregation service、strict limits、noise / DP、anti-replay、privacy budget 等作为核心设计对象。这支持本文继续把 partner-facing reporting 放在 aggregate plane，而不是让 request-level label 对外裸奔。
- [IAB Tech Lab ADMaP v1.0](https://iabtechlab.com/admap/) 已在 `2025-02-25` finalized。它把 DCR 中的两方 matching、attribution measurement、output use 和 collusion/threat vectors 写成互操作标准，并明确依赖 PETs。对本 RFC 的含义是：ADMaP / PJC / PSI 更适合做后端 settlement、aggregate verification 和跨方对账；前台 SRN claim 仍应保持 minimal yes/no + opaque token。
- [Global Privacy Protocol](https://iabtechlab.com/gpp/) 在 `2025-12-17` 页面显示 H2 2025 新州 section 已 finalized；[DDRF V2 public comment](https://iabtechlab.com/press-releases/iab-tech-lab-expands-global-privacy-frameworks-with-gpp-updates-and-ddrf-v2-release/) 说明删除请求框架正在增强 object formats、encoding 和 safeguards。对本 RFC 的含义是：consent、deletion、jurisdiction 不应只是 legal annex，而应进入 `PrivacyControlPropagationRecord`，并影响 artifact retention、debug trace key、feature release 和 future aggregate collection。
- [Predicted Incrementality by Experimentation](https://arxiv.org/abs/2304.06828) 在 `2026-04-01` 修订版中把 ad measurement 重新表述为 campaign-level prediction problem：用有限 RCT 学到 causal effect mapping，再把 post-determined aggregate features 用于非实验 campaign 的增量预测。它对本文的直接要求是：`RequestScopedOptimizationLabel` 不能独自承担“因果真值”职责，必须增加 `IncrementalityCalibrationRecord`。
- [IAB Project Eidos](https://www.iab.com/news/iab-announces-project-eidos/) 在 `2026-02-02` 把 attribution、incrementality、MMM 和 standardized privacy-ready inputs 放在同一 measurement modernization 议题里。这不是工程规范，但它说明客户和生态会同时要求 event-level 归因解释、incrementality、预算建议和跨渠道可比性。

因此，本 RFC 的 2026-05-09 收紧结论是：

1. `is_attributed` 是 attribution label，不是 incrementality label。
2. `incrementality_weight_micros` 应来自实验池或 PIE-style calibration，并带 `experiment_provenance`。
3. ADMaP / PJC / PSI 可以加固后端 aggregate verification，但不应让 MMP 前台 claim API 暴露更多 touch metadata。
4. GPP / DDRF / deletion signal 必须影响 token、artifact、feature release 和 debug trace lifecycle。
5. Optimization Phase 1 可以不上 DP，但不能没有 causal calibration provenance 和 privacy-control propagation record。

### 20.19 截至 2026-05-10 的最新 delta：multi-ID、streaming DP 与 ICM 生产约束

这次复查没有推翻主链路，反而补强了三个容易在实现中被低估的地方：多标识符匹配、实时报表 DP、MMP/AAP 集成状态。

第一，multi-ID private matching 不能被实现成“先把所有 ID 合并成一个大 user id，再跑隐私协议”。[PrivacyGo](https://arxiv.org/abs/2506.20981)（2025-06-26）把广告测量里的 multi-identifier profile matching 明确建模为 practical problem，并使用 reversed OPRF、blind key rotation 和 DP-obfuscated intersection size 来减少 cross-identifier linkage 和 membership inference 风险。这对本 RFC 的直接影响是新增 `MultiIdentifierPrivateMatchPolicy`：identifier source、normalization policy、key epoch、linkage guardrail 和 intersection release policy 都必须成为 task-scoped contract。

落地结论：

- email / phone / rdid / appsetid / idfv / gclid / gbraid / `odm_info` 不能因为“都能帮助匹配”就进入同一个长期 join key。
- 多标识符只能在 `measurement_task_id + app + advertiser + partner + key_epoch` 范围内产生 task-bound material。
- 对外释放只能是 scoped claim、aggregate value 或 DP-obfuscated intersection size；不要释放 identifier-pair hit 明细。
- 如果必须做 encrypted relay fallback，要承认它是 lower-privacy profile，而不是继续使用 raw-local-only 的宣传语。

第二，DP ad conversion measurement 的关键不只是噪声机制，而是“什么配置在操作上有效”。[Differentially Private Ad Conversion Measurement](https://arxiv.org/abs/2403.15224)（PoPETS 2024）强调 attribution rule、DP adjacency relation、contribution bounding scope 和 enforcement point 之间有细微耦合，必须一起定义才算 operationally valid。[AdsBPC / Click Without Compromise](https://arxiv.org/abs/2406.02463)（arXiv v4, 2025-09-08）则把实时流式广告报表作为正式问题，并用 per-user DP 和非同分布噪声分配改善准确率。

落地结论：

- `epsilon/delta` 不能单独出现在 RFC 里；它必须绑定 `dp_subject_unit`、`dp_adjacency_relation`、`contribution_bounding_scope`、`contribution_enforcement_point`。
- 对 hourly / daily campaign reporting，`release_slot_granularity` 和 `budget_scope_id` 必须进入 budget ledger。
- 流式 release 的 correction / refresh 不能被当成免费更新；要么消耗额外预算，要么进入明确的 correction policy。
- Phase 1 可以不把 DP 放进 optimization plane，但 partner-facing aggregate plane 应优先补齐 `StreamingDpReleasePlan`。

第三，ICM / ODM 的真实生产约束已经从“SDK 功能”变成“MMP/AAP 集成契约”。Singular 在 [Google Ads attribution integration](https://support.singular.net/hc/en-us/articles/115003252786-Google-Ads-AdWords-Mobile-App-Campaigns-Attribution-Integration)（页面更新 `2026-05-08`）里把 Google ICM 写成 open beta，并给出多条工程边界：Android 自 `2026-03-30` 起对所有广告主开放，iOS 自 `2025-11-12` 起对所有广告主开放；ICM 可覆盖 iOS ATT declined、Android EEA / ads personalization opt-out 和 Kids apps，但不支持 iOS EEA/UK region；报告形态是 click-through install、probabilistic attribution，sub network type 不可用；iOS 接入要求 Google ODM SDK、Singular SDK `12.8.1+`、`enableOdmWithTimeoutInterval`，推荐 5 秒 timeout，且可能延迟 deep link callback；没有产出 `odm_info` 时要传 `odm_error`；Google Ads user-level data 在 MMP 侧有 6 个月 retention 要求；LDS 会映射到 Google `ad_user_data` / `ad_personalization`。

落地结论：

- `SdkMeasurementRuntimeTrace` 需要新增 rollout、reporting scope、`odm_error_code`、Kids app policy、retention policy、consent mapping policy。
- `icm_enabled=true` 不够；需要区分 platform rollout、region inactive、consent denied、SDK missing、S2S fallback、event source ineligible。
- MMP/AAP 侧的 `odm_info` / `odm_error` 是 integration health 和 compat egress 状态，不是 attribution truth，也不是 optimization feature。
- 6 个月 retention 和 LDS->Google consent mapping 应进入 privacy-control propagation，而不是只写在 partner UI 操作文档里。

截至 2026-05-10，本文的新增判断是：on-device measurement RFC 如果只写 OPRF/PSM、Claim/Confirm 和 request-level label，还不够生产化。它还必须把“可用标识符如何组合”“实时 aggregate 如何重复发布”“MMP/AAP SDK 在什么 rollout / region / consent / timeout 状态下产出或缺失 `odm_info`”写进正式协议。

### 20.20 Cross-MMP ICM 资料的共同信号

2026-05-10 的额外复查把视角从 Singular 扩到多个 MMP / AAP。这里的关键不是哪家文档最完整，而是它们共同暴露了 ICM 的真实产品边界。

- AppsFlyer 的 [Google attribution solution bulletin](https://support.appsflyer.com/hc/en-us/articles/37857301293457-Bulletin-AppsFlyer-and-Google-attribution-solution-Open-BETA) 明确写出：Google 会向 AppsFlyer 发送 non-deterministic install claims；这些 claims 如果被 AppsFlyer 数据验证，就用于归因；iOS 需要 AppsFlyer iOS SDK `6.17.7+` 加 Firebase `11.14.0+` 或 standalone Google ODM SDK；Android no SDK update；Advanced Data Sharing 开启后 AppsFlyer 会发送没有 device ID 的 install，否则 ICM 效果受限。
- Singular 的 [Google Ads attribution integration](https://support.singular.net/hc/en-us/articles/115003252786-Google-Ads-AdWords-Mobile-App-Campaigns-Attribution-Integration) 把 Android / iOS open beta、click-through install only、probabilistic attribution、sub network type unavailable、iOS ODM SDK / timeout / `odm_error`、retention 和 consent mapping 写成具体接入约束。
- Branch 的 [Google ICM page](https://help.branch.io/account-hub/docs/branch-google-icm-for-enhanced-mobile-measurement) 把 iOS 路径写成 Branch iOS SDK `3.13.3+` + Google ODM SDK / Firebase，或 S2S 传 `odm_info`；Android 则写成 no immediate actions，measurement improvements 自动应用。
- Airbridge 的 [ICM announcement](https://www.airbridge.io/en/blog/airbridge-google-icm) 把 ICM 描述为 Google proprietary non-deterministic attribution data 进入 Airbridge dashboard；其 [touchpoint definitions](https://help.airbridge.io/en/guides/ad-channel-touchpoint-types) 进一步写出 Android ICM attribution data 可覆盖 ACi winning touchpoints，包括 clicks 和 engaged views；iOS 则需要安装 Google On-Device Event Measurement SDK 并升级 Airbridge iOS Native SDK `4.4.1+`。
- Kochava 的 [Google Ads ICM article](https://www.kochava.com/ru/blog/google-ads-integrated-conversion-measurement/) 写出 iOS 需要 Firebase / ODM 与 Kochava SDK 更新，S2S 要传 on-device measurement info string；Android no SDK update，modeled attribution 可用性取决于 rollout / allowlist；Google claims 进入 Kochava modeled tier。
- Tenjin 的 [ICM support article](https://tenjin.com/blog/tenjin-announces-early-support-for-google-ads-integrated-conversion-measurement/) 也呈现同样模式：iOS 需要 on-device conversion measurement 和 SDK 版本更新；Android no actions needed / automatic enablement。
- Adjust 的 [ICM overview](https://www.adjust.com/blog/integrated-conversion-measurement/) 没给出很细的 SDK 步骤，但明确 ICM 支持 SDK-based 和 S2S integrations，并会进入 Adjust 的 probabilistic attribution tier 和 cross-network reporting。

这些资料合在一起，给本 RFC 三个新约束：

1. `Android ICM` 和 `iOS ICM` 必须分 schema，不是同一套 SDK requirement。Android 更像 `Google App Conversion API + appsetid/zeroed rdid + gclid/referrer/gbraid + consent flags + partner toggle`；iOS 更像 `ODM SDK/Firebase -> odm_info -> MMP/AAP compat API`。
2. `claim_path` 必须显式表达 MMP waterfall tier。不同 MMP 叫法不一：non-deterministic claim、probabilistic attribution、modeled tier、privacy-preserving conversion modeling；训练面不能把它和 deterministic device-id claim 混成同一种 label。
3. `icm_supported_engagement_types` 必须平台 / MMP / campaign type 化。Singular 当前偏 click-through install only；Airbridge Android 明确包括 clicks 和 engaged views；AppsFlyer 提到 installs 和 re-attributions。这类差异会直接影响 bidder 如何解释 winner quality。

因此，本文在 `SdkMeasurementRuntimeTrace` 和 11.5B 中补充 `advanced_data_sharing_enabled`、`android_sdk_update_required`、`ios_odm_sdk_required`、`icm_supported_engagement_types`、`icm_claim_semantics`、`gclid_capture_enabled`、`install_referrer_gclid_capture_enabled` 和 `gbraid_capture_enabled`。这些字段的目的不是让 runtime trace 变成训练特征，而是让 ICM 的可用性、缺失原因和 claim 类型可审计。

### 20.21 截至 2026-05-11 的最新 delta：optimization training privacy 也要进 RFC

这次复查没有发现会改变主链路的最新产品资料。GoogleAdsOnDeviceConversion 官方 GitHub release 页面仍显示最新 release 为 `3.5.0`（2026-04-16）；DAP Attribution 扩展仍是 `-01`（2026-02-18）。真正需要补强的是 attribution label 进入训练面之后的隐私契约。

广告优化不是“拿回一个归因 bit 就结束”。一旦 `RequestScopedOptimizationLabel`、`ServerFeatureDerivationRecord` 和 `OptimizationFeedbackRecord` 进入 trainer，系统就必须回答四个问题：

1. 哪些字段本来就是广告请求上下文，攻击者或 ad network 已经可知？
2. 哪些字段来自 raw IP、boot time、timezone、reinstall hint、device attestation 等敏感观察的派生？
3. 哪些 label 或 value 是用户行为结果，需要和特征一起保护？
4. 当前 trainer 是内部 baseline、label DP、semi-sensitive DP，还是完整 user-level DP？

研究侧给出的信号很明确：

- [Private Ad Modeling with DP-SGD](https://research.google/pubs/private-ad-modeling-with-dp-sgd/) 把 DP-SGD 用到 CTR、CVR 和 conversion count 等广告任务上，说明广告优化模型可以走 DP 训练路线；但它同时提醒广告数据有高类别不平衡和稀疏梯度，不能直接套用通用深度学习 DP recipe。
- [Training Differentially Private Ad Prediction Models with Semi-Sensitive Features](https://research.google/pubs/training-differentially-private-ad-prediction-models-with-semi-sensitive-features/) 给了更贴近生产的分层：一部分 features 可被视为 attacker already knows；剩余 features 与 label 才是要保护的对象。该方向比“全部特征 full DP”或“只保护 label 且丢弃未知特征”更适合广告 request-level optimization。

落地结论：

- `TrainingPrivacyPolicy` 应成为正式对象，而不是 trainer README。
- `known_feature_names`、`semi_sensitive_feature_names`、`protected_label_names` 和 `prohibited_raw_feature_names` 必须由 feature sensitivity manifest 驱动。
- Phase 1 可以明确使用 `NO_DP_BASELINE`，但必须禁止 raw PII 和 compat-only artifact 进入训练面。
- Phase 2 推荐从 `SEMI_SENSITIVE_DP` shadow training 开始，而不是直接把主 bidder 切到 full user-level DP。
- 如果采用 DP-SGD、label DP 或 semi-sensitive DP，应优先使用 JAX Privacy、TensorFlow Privacy、OpenDP 或同等级库，并保留 accountant、clipping、sampling、audit 和 empirical privacy eval 记录。

这条 delta 把本文的 optimization 设计从“request-level label 必须回来”推进到“label 回来之后怎样进入 trainer”。否则，on-device measurement 只是把 PII 风险从 MMP payload 转移到了训练表。

### 20.22 平台 API 退场、W3C 收敛与 DP 训练审计

这次复查新增的不是一条新主链路，而是三个边界必须写得更硬。

第一，跨平台公开标准继续往 `aggregate + DP + anti-replay + budget state` 收敛。[W3C Attribution Level 1](https://www.w3.org/TR/attribution/) 的 `2026-05-14` Working Draft 把广告效果测量定义为：用户代理保存 impression，conversion 时生成加密 histogram contribution，站点把足够多的 reports 送到 aggregation service，aggregation service 做 replay check、加噪和 aggregate release。它直接支持本文的判断：partner-facing reporting plane 应对齐 `report_id`、`batch_id`、`collector_domain`、`privacy_budget_epoch_id` 和 replay state，而不是暴露 request-level label。

第二，不能再把 Android Privacy Sandbox Attribution Reporting 当成未来生产依赖。Google Privacy Sandbox 官方在 `2025-10-17` 宣布退役 Attribution Reporting API（Chrome / Android）、Private Aggregation、Protected Audience、Topics 等多项技术，并表示会继续把 Attribution 方向放到 W3C 标准化协作中。Android `MeasurementManager` API reference 又明确写出 measurement APIs 在 API 37 deprecated、没有直接替代 API、后续调用会在 soft removal 过程中被拒绝。对本文的落地要求是：

- `android.adservices.measurement.MeasurementManager` 只能作为历史实验 / 兼容 trace，不应成为 production SDK dependency。
- Android 生产协议应落到 `Google ICM / App Conversion API / install referrer gclid / gbraid / appsetid / consent flags / MMP partner config`。
- runtime trace 应新增 `platform_measurement_api_family`、`android_privacy_sandbox_measurement_state` 和 `aggregate_api_dependency_state`，否则后续排障会把“平台 API 不可用”误判成“用户没有转化”或“ad network declined”。

第三，Apple AdAttributionKit 变细了，但它仍是 platform postback plane。Apple 当前文档和 WWDC25 材料给出几个重要能力：view-through / click-through window、winning / nonwinning postback、advertised app postback copy、conversion tag 用于重叠 reengagement conversion、configurable attribution rules，以及 postback geography。它们对 RFC 的价值是增强 reconciliation、platform reporting、geo / campaign calibration；但它们不提供 Ad Network 内部 `server_request_id`，也不替代 MMP Confirm。因此本 RFC 新增 `9.4E` 的 platform postback trace，并明确 `conversion_tag` `MUST NOT` 被升级为跨 app / 跨 network 用户标识。

训练面也有一个细节需要补上。[How Private are DP-SGD Implementations?](https://research.google/pubs/how-private-are-dp-sgd-implementations/) 指出生产里常见的 shuffle-style DP-SGD 和 Poisson subsampling accountant 之间可能存在隐私分析 gap；[Balls-and-Bins Sampling for DP-SGD](https://research.google/pubs/balls-and-bins-sampling-for-dp-sgd/) 提供了一种更接近 shuffle 工程实现、同时更接近 Poisson 隐私放大的 sampler；[Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/) 和 [Empirical Privacy Variance](https://research.google/pubs/empirical-privacy-variance/) 则提醒：同样标称 `(epsilon, delta)` 的训练配置，经验隐私风险可能不同，且 audit 应进入持续发布门禁。

因此 `TrainingPrivacyPolicy` 新增：

- `dp_sampling_method`
- `dp_accounting_method`
- `empirical_privacy_audit_schedule`
- `empirical_privacy_risk_profile`

这不是要求 Phase 1 立刻上 DP；恰恰相反，它让 Phase 1 能诚实标注 `NO_DP_BASELINE`，让 Phase 2 的 DP shadow training 不再只靠“我们用了某个 DP 库”证明隐私。

本次 delta 的落地结论：

1. W3C / DAP 是 aggregate reporting 的平台无关方向；Android Privacy Sandbox MeasurementManager 不是。
2. Apple AdAttributionKit 可以进入 reconciliation 和 aggregate calibration；不能直接作为 request-level optimization label。
3. Android ICM 与 iOS ODM 应继续分 schema；Android 更偏 partner-managed backend / referrer / conversion API path，iOS 更偏 ODM SDK / `odm_info` path。
4. DP training profile 必须记录 sampler 和 accountant，否则 `(epsilon, delta)` 可能只是口径而不是证明。

### 20.23 2022 专利快速对照：Google aggregated conversion measurement 与 on-device privatization

这次专利检索里有两个容易混淆的对象：

1. **Google LLC: `Aggregated conversion measurement`**
   - 代表公开/授权：`US20220086240A1`（2022-03-17 公开），`US11711436B2`（2023-07-25 授权）。
   - 真实优先日更早：`2019-04-16`；后续 `US17/536,623` 在 `2021-11-29` filed，并在 2022 年公开。
   - 核心是浏览器侧 conversion engine：广告内容向 browser 注册 `landing page URL` 与 `conversion reporting URL`，browser 本地保存 registration table；当后续页面 URL 命中并满足 display-time / TTL / policy 条件时，browser 生成 reporting message，且可 batch、delay、proxy。
   - 它的隐私边界主要是：浏览器作为用户代理 gatekeeper，限制 payload，限制 campaign id 长度，delay / batch / proxy reporting，降低第三方 cookie 缺失后的跨站追踪风险。

   和本 RFC 的差异：

   - 它是 **browser/web attribution API**；本 RFC 是 **mobile app + MMP/SRN + ad network SDK**。
   - 它的主对象是 URL registration / reporting message；本 RFC 的主对象是 `MmpAskRequest`、`ClaimResponse`、`MmpConfirmRequest`、`RequestScopedOptimizationLabel`。
   - 它解决 partner-facing aggregate / conversion postback；本 RFC 还要求 Confirm 后恢复 `server_request_id`，支撑 request-level personalized optimization。
   - 它没有定义 OPRF/PSM-with-payload、`mmp_touch_token -> req_id`、MMP winner adjudication、Google ICM / ODM compatibility runtime trace。
   - 它对本 RFC 最有用的启发在 aggregate plane：reporting policy、batch requirement、TTL、payload limitation、proxy / delay 都应被建模成正式 contract。

2. **Microsoft Technology Licensing: `On-device privatization of multi-party attribution data`**
   - 代表公开/授权：`US20240143416A1`（2024-05-02 公开），`US12327150B2`（2025-06-10 授权）。
   - 优先日 / filing date 是 `2022-11-01`，标题和“on-device attribution + optimization model”很像我们的问题，但它不是 Google LLC 专利；只是页面在 Google Patents 上。
   - 核心是：设备侧接收 first-party login data、first-party click/link event、third-party conversion event，把第三方 event 转成 bit label，batch 后在设备侧加 DP noise，再把 noisy multi-party attribution data 发给第二计算设备；服务端或端上 debiasing system 去偏后训练 optimization / ranking model。

   和本 RFC 的差异：

   - 它默认允许 first-party identifier 与 noisy conversion label 形成 user-level training data；本 RFC 默认不把 MMP / partner 看到的 compat artifact 直接进 trainer，必须通过 `TrainingPrivacyPolicy` 和 feature sensitivity manifest。
   - 它的隐私技术重点是 local DP / noisy label / debiasing；本 RFC 的主链路重点是 `OPRF/PSM layer + associated payload layer + SRN Confirm`，DP 主要先落在 aggregate reporting 和 Phase 2 training profile。
   - 它把 optimization model training 放在专利核心；本 RFC 把 attribution fact、incrementality calibration、privacy-control propagation、optimization row 拆成多个对象，避免把 claim label 直接当 causal truth。
   - 它没有 MMP `Ask -> Claim -> Confirm`、winner-only finalize、claim token replay gate、`mmp_touch_token -> server_request_id` 的生产闭环。

专利检索带来的落地判断：

- 如果讨论 **Google 2022 公开专利**，更像 `W3C Attribution / Privacy Sandbox Attribution Reporting` 的前身或同类 browser aggregate postback，不是 Google iOS ODM / MMP ICM 的完整实现说明。
- 如果讨论 **2022 filed + on-device privatization + ML optimization**，标题相似度高，但 assignee 是 Microsoft；它更适合当作 `TrainingPrivacyPolicy` / DP noisy label 的 prior-art 对照。
- 本 RFC 的核心差异仍然是生产协议面：`MMP Ask -> AdNetwork SDK OPRF/PSM -> Claim -> MMP Confirm -> server_request_id label release`，以及围绕这个链路定义 schema、mock payload、runtime trace、privacy control 和 optimization contract。

### 20.24 Google 2022 privacy + SDK 专利对照

这次按 `Google LLC + privacy + SDK + 2022` 重新检索后，最接近本文主题的不是 `Aggregated conversion measurement`，而是 Google LLC 在 `2022-05-06` filed 的 **`Privacy-preserving and secure application install attribution`**（`US20240095364A1` / `WO2023214975A1`）。

它和本 RFC 的重叠点很明确：

- 场景是 app install attribution，而不是纯 web conversion。
- 角色里有 attribution SDK / digital component SDK、client device、content platform、application provider、attribution processing apparatus。
- 端侧有 trusted program / secure storage，SDK 可以向 trusted program 请求 sharded secure token。
- attribution token 可包含 installed app identity、attribution credit、integrity token、digital signature 等材料，用来证明 app install 和 touchpoint chain 更可信。
- 文档明确反对用 common identifier 把 request、impression、interaction、install 四段串起来，因为这会造成跨 app / 跨 publisher tracking 风险。

因此，这个专利更像本文的 **secure install attribution + anti-fraud token chain** prior art。它对本文最有用的启发是：`DeviceSupplyPathAttestationReceipt` 不应只证明“设备像真机”，还应证明 request / display / interaction / install 这些事件的 causality chain；同时，token sharding 应按 publisher / app boundary 做，避免把 attestation token 变成 durable cross-app identifier。

但它仍不是本文的 MMP/SRN 完整方案：

- 它的核心输出是 install attribution token / attribution credit；本文的核心协议是 `MMP Ask -> Ad Network Claim -> MMP Confirm`。
- 它没有定义 MMP winner adjudication，也没有 claim token replay gate、winner-only finalize、MMP confirm callback 这类 SRN 生产语义。
- 它不暴露 Ad Network 内部的 `server_request_id`，所以不能直接支撑 request-level personalized optimization。
- 它没有把 post-install purchase / value / retention label 通过 `RequestScopedOptimizationLabel` 回传到广告网络训练面。
- 它不包含本文的 `OPRF/PSM-with-payload` 层，也没有把 MMP-visible compat artifact 和 ad-network-only optimization context 明确分层。

第二个相关 Google 专利是 **`Secure attribution using attestation tokens`**（`WO2023028293A1` / `US20240220654A1`），PCT filing date 是 `2022-08-26`，priority 是 `2021-08-26`。它使用 anonymous / attestation tokens 证明 request、display、interaction、install 链路中的事件真实性，分类也覆盖广告防欺诈和 targeted advertisements。它适合放进本文的 request-scoped quality / anti-fraud plane：

- 可对齐到 `DeviceSupplyPathAttestationReceipt.device_attestation_family`、`attestation_token_digest`、`display_integrity_score`、`interaction_integrity_score`。
- `MUST NOT` 对齐到 user id、`server_request_id`、`mmp_touch_token` 或任何长期 join key。
- optimization 侧可以把它作为 sample weighting / fraud-quality feature，而不是 attribution label 本身。

第三个相邻但不是 SDK install attribution 主线的 Google 专利是 **`Privacy preserving cross-domain machine learning`**（`US20220405407A1`）。它在 `2022-12-22` 公开，主题是用 MPC 训练 / 使用 digital component selection model，避免第三方 cookie 和明文用户数据。它对本文的价值在 ML privacy plane：证明 Google prior art 里也把 secure MPC / privacy-preserving ad model training 作为无 cookie 广告选择方向；但它不是 `MMP Ask -> Claim -> Confirm`，也不是 advertiser app SDK install attribution。

本次检索结论：

1. 如果用户说的是“Google 2022 年提交过 privacy + SDK 相关专利”，最可能指 `US20240095364A1 / WO2023214975A1`，不是 2022 公开的 browser aggregate patent。
2. 本文方案的差异不在“有没有 token / SDK / trusted program”，而在把它们放进 MMP/SRN 生产协议：MMP 只看 yes/no claim 和 opaque token；Ad Network 只在 Confirm 后恢复 `server_request_id`；post-install value label 进入受控 optimization pipeline。
3. Google attestation-token 专利支持本文的 touchpoint quality receipt 设计，但不能被误用为 durable user identifier。
4. Google cross-domain ML 专利支持“隐私保护广告训练/推断”的方向，但不能替代本文的 attribution + optimization spec。

### 20.25 旧版 EC-OPRF candidate rows proposal 融合对照

这次融合的旧文档是一个更早的工程/法务评审包：`EC-OPRF + encrypted candidate rows with AdPlatformUserID / opaque click_id`。它不是要推翻当前 RFC，而是补齐当前 RFC 里几处需要更“落地”的实现 profile、容量估算和 legal review 语言。

相同点：

| 主题 | 旧文档 | 当前 RFC 融合结果 |
|---|---|---|
| 默认私密匹配 | EC-OPRF + encrypted candidate rows | 保留为 17B/17C 的 BR-1 默认实现 |
| 主链路 | MMP SDK Ask -> Ad Platform SDK PSM -> Claim -> MMP Confirm -> req_id optimization | 保留，但扩展成多 network SRN winner-only Confirm |
| MMP 不应看到 | raw device material、device_fp_hash、OPRF input/output、bucket tail、row key、raw req_id | 完全一致，并写进 Claim/Confirm schema boundary |
| 隐私措辞 | 不要说 “No PII leaves device” | 保留为 17D.6 推荐措辞 |
| 隐私升级路径 | Paillier/PIR selected-row retrieval；FHE research option | 保留为 BR-2/PIR escalation 与 17E FHE hardened profile |
| optimization 需求 | Confirm 后从 APUID/click_id 找回 req_id | 保留为 Confirm 后恢复 `server_request_id` 并物化 `RequestScopedOptimizationLabel` |

不同点：

| 主题 | 旧文档倾向 | 当前 RFC 的调整 |
|---|---|---|
| MMP-visible handle | `AdPlatformUserID + opaque click_id` 是默认输出 | 默认改为 `mmp_touch_token + claim_token`；APUID/click_id 收敛为 Option 2A compatibility profile |
| token 命名 | `AdPlatformUserID` 容易被理解成 network user ID | 推荐 `mmp_touch_token` / `ad_touch_token`，强调 advertiser-scoped、touch-scoped、purpose-bound |
| click_id payload | 可作为 gbraid-like encrypted req_id-bearing structure | 推荐 compact pointer；500B 级 blob 不应 inline 到 1K candidate rows |
| event scope | 主要围绕 install attribution | 当前 RFC 覆盖 install、first_open、purchase、ROAS、incrementality calibration、privacy control propagation |
| platform reality | 旧文档未覆盖 Google ICM/AAP、Apple AdAttributionKit、Android MeasurementManager 退役 | 当前 RFC 把这些作为 runtime trace / platform postback / compatibility plane |
| training privacy | 旧文档关注 Confirm 后 optimization | 当前 RFC 额外要求 `TrainingPrivacyPolicy`、feature sensitivity manifest、DP profile 和 empirical audit |
| candidate quality | 旧文档强调 bucket rows 形态 | 当前 RFC 还保留 `eligible_candidate_count`、`prefilter_candidate_count`、attestation receipt、fraud/sample weighting |

本次融合落到正文里的具体改动：

- `ClaimResponse` / `MmpConfirmRequest` 新增可选 `ad_platform_user_id`、`opaque_click_id`、`mmp_visible_handle_mode`，但默认不启用。
- `17B` 的 touchpoint row 和 `ReportingPayload` 增加 APUID/click_id compatibility 字段，并明确它们不能替代默认 `mmp_touch_token + claim_token`。
- `17C.8` 引入旧文档的 sizing：light row `~150B`、heavy row `~650B`、1K bucket 下约 `200KB` vs `867KB` wire、Paillier selector `~512KB/1K rows`、MVP `~43-65 person-weeks`。
- `17D` 的 legal matrix 增加 Option 2A，专门承接 APUID/click_id 方案。
- `17D.7` 把旧字段逐一映射到当前 RFC 字段，并列出启用条件。

合并后的设计判断：

1. 旧文档的 OPRF candidate rows 是当前 RFC 的默认实现 profile，不是另一套架构。
2. 旧文档的 APUID/click_id 是一个可兼容的 MMP/SRN partner profile，但不是所有 partner 的默认披露面。
3. 如果 Legal 接受 SDK 获取 encrypted bucket rows，BR-1 仍是 MVP 最现实选择。
4. 如果 Legal 对 bucket rows 敏感，优先升级到 BR-2 compact handles + validate 或 Paillier/PIR selected-row retrieval，而不是退回 raw server-side matching。
5. FHE 继续作为 high-sensitive task 的 hardened profile；不能替代 Claim/Confirm，也不能直接把 `server_request_id` 暴露给 MMP。

### 20.26 截至 2026-05-13 的最新 delta：预算调度与端侧敏感信号

本次增量复查没有改变主协议：`MMP Ask -> Ad Network Claim -> MMP Confirm -> request-level optimization` 仍是广告 App 场景下最现实的主链路。新增的是三条生产约束。

第一，W3C Attribution Level 1 最新公开 Working Draft 已是 `2026-05-14`。它继续把广告归因输出建模为 encrypted histogram contribution，经 aggregation service 做 replay check、加噪和 aggregate release。对本文的约束是：aggregate plane 不能只有 `report_id`，还要有 `batch_id`、`collector_domain`、`privacy_budget_epoch_id`、budget lifecycle 和 replay state。

第二，Big Bird / `Beyond Per-Querier Budgets` 把 privacy budget 从“配置项”提升成了“调度系统”。论文指出 per-querier budget 在自适应查询下存在 formal gap，并提出 global device-epoch budget、resource isolation 和 batch scheduling 来兼顾隐私保证与 DoS resilience。本文据此新增 `AggregateBudgetSchedulerPolicy`。这并不强迫 Phase 1 上完整 DP；但如果 Phase 1 只做 per-collector quota，就必须在 schema 里诚实标成 `per_collector_quota_only`，不能宣传成 global DP。

第三，官方 Google ICM / ODM 文档再次确认了 iOS 与 Android 的生产差异：ICM 面向第三方 AAP/MMP interface 提供更实时、更细粒度的归因；iOS 需要 ODM event-data path 或把 `info` string 传给 AAP，且 Firebase / SDK event 与 S2S / Measurement Protocol 的兼容边界不同；Android 侧则更偏 partner-managed rollout。本文保留 `SdkMeasurementRuntimeTrace` 的原因正是避免把“SDK 没初始化、ODM 不兼容、区域不 eligible、S2S 不支持”误判成用户没有转化。

第四，移动端敏感信号的处理要更靠近采集点。`Privacy on the Fly` 这类移动传感器隐私研究说明，连续、低层、看似非 ID 的端侧信号可以被用来推断身份或敏感属性。对广告 measurement 来说，`boot_time`、`ip`、network churn、uptime、sensor-like timing signal 不应原样进入 MMP、普通日志或训练表；可用折中是端上 bucketize / clip / derive，再只把 `boot_time_freshness_bucket`、`ip_churn_bucket`、`network_stability_bucket` 这类短期、任务绑定特征送入 confidential plane 或 feature derivation record。

落地结论：

1. `AggregateBudgetSchedulerPolicy` 是 aggregate release 的控制面对象；`AggregateCollectorBudgetState` 是单次 collect 的状态对象。
2. `privacy_unit`、`formal_budget_model`、`scheduler_type` 和 correction release policy 必须进入审计日志。
3. iOS ODM / Android ICM / Apple AdAttributionKit / W3C Attribution 继续作为不同 surface 建模，不应被压成一个 `measurement_enabled` 布尔值。
4. 端侧敏感信号可以服务反作弊和优化，但必须先在 SDK / confidential plane 内降维、分桶、裁剪，不能作为 raw feature 出现在 MMP 或 trainer。

### 20.27 截至 2026-05-14 的最新 delta：utility、consent enforcement 与冷启动信号

本次复查没有推翻主架构，但把 trade-off 从“原则描述”推进成了可审计对象。

第一，`Can privacy technologies replace cookies? Ad revenue in a field experiment`（PNAS，2026-05-12）给出了一个很硬的提醒：隐私增强广告技术的业务效果依赖生态 adoption、latency 和供应侧覆盖。该实验在 200M+ impressions 与 5K+ publishers 上比较 cookies disabled、Privacy Sandbox 与 baseline，结论不是“隐私技术无效”，而是“不能把隐私增强等同于业务无损”。对本文的约束是：RFC 不能只有 privacy profile，还要有 `MeasurementUtilityExperimentRecord`，记录 revenue / CPA / ROAS / latency / impression delivery / adoption state / experiment design。

第二，`Privacy-Enhanced versus Traditional Retargeting` 的行业实验显示，privacy-enhanced retargeting 在某些 click / conversion 指标上能恢复一部分 cookie loss，且按 spend 调整后差距会缩小。这支持本文不把 trade-off 写成二元选择：Phase 1 可以不先上 full DP，但必须保留 query budget、latency、adoption 与 causal design 记录，让产品能按场景 gated rollout。

第三，`The Privacy-Utility Trade-Off of Location Tracking in Ad Personalization`（2026-03）说明 location / geography signal 在 cold-start 阶段价值最高，用户行为历史丰富后更容易被替代。这直接支持 `DeviceSensitiveSignalPolicy.cold_start_gate`：`raw_ip`、coarse geo、network churn 这类信号可以有受控业务价值，但应该按冷启动、粗粒度、短 TTL 和派生桶释放，而不是变成永久训练特征。

第四，`The TCF doesn't really A(A)ID`（PETS 2026）对 Android App 中 TCF 实现的测量说明，存在 consent 拒绝未正确保存、AAID 在无合法依据或用户交互前被共享等问题。对本文的结论是：consent 不能只是 MMP / CMP 字段；`consent_dependency_id`、`PrivacyControlPropagationRecord`、SDK runtime trace 和 debug-log policy 必须一起记录。否则 on-device measurement 只是把隐私风险从协议字段挪到了移动端实际流量里。

第五，`Blind Targeting` 与 `Privacy Preserving Conversion Modeling in Data Clean Room` 说明，aggregate / DP / clean-room 限制下仍可做有效 targeting 或 CVR 训练，但前提是查询策略、batch-level gradients、label DP、de-biasing 和实验口径都被产品化。它们支持本文的折中：request-level optimization 可以先留在 Ad Network 受控边界内；公开 reporting 和跨方分析走 aggregate / clean-room / DP；训练隐私升级通过 `TrainingPrivacyPolicy` 和 `MeasurementUtilityExperimentRecord` 分阶段上线。

落地结论：

1. 新增 `DeviceSensitiveSignalPolicy`，把 raw signal、collection point、TTL、derivation mode、release scope、cold-start gate 和 consent dependency 写成正式对象。
2. 新增 `MeasurementUtilityExperimentRecord`，把 privacy profile 的上线效果写成实验记录，而不是靠一次离线汇报决策。
3. 对 IP / geo / location-like signal 的推荐默认是 `cold_start_gate=first_n_events`、`allow_mmp_visibility=false`、`allow_trainer_raw_visibility=false`。
4. 如果为了实用性放松 DP 或使用 partner compatibility path，必须在 profile 中显式承认 lower-privacy / non-DP / gated rollout 状态，不能对外宣传成严格 DP。

### 20.28 截至 2026-05-15 的最新 delta：敏感信号派生记录与 MMP/AAP consent gating

本次复查没有改变 `MMP Ask -> Ad Network Claim -> MMP Confirm -> request-level optimization` 主链路。新增的是一个更生产化的边界：端侧敏感信号不能只有全局 policy，还要有逐事件的 derivation record。

第一，W3C TR 索引显示 `Attribution Level 1` 最新公开草案已推进到 `2026-05-14`。正文仍把 attribution API 建模为用户代理侧保存 impression、conversion 时构造 report、通过 aggregation service 做 DAP/VDAF-style aggregation、anti-replay、budget control 和 DP noise。这继续支持本文的分层：公开 reporting plane 走 aggregate / DP / anti-replay；request-level optimization label 留在 Ad Network 内部。

第二，Google Privacy Sandbox 官方 `2025-10-17` 公告仍是关键生产事实：Attribution Reporting API、Private Aggregation、On-Device Personalization、SDK Runtime 等 Chrome / Android Privacy Sandbox 技术被退役，Google 表示会把 Attribution 的经验继续投入 W3C 标准协作。Android `MeasurementManager` API reference 也仍明确标记为 API 37 deprecated。因此 Android App 侧不应把 Privacy Sandbox measurement API 当未来主依赖；更现实的生产路径仍是 ICM / App Conversion API / install referrer / partner contract / consent flags。

第三，Google Ads ODM 与 AAP 文档把端侧敏感信号和 consent gating 讲得更具体：iOS ODM event-data variant 使用从设备信号（例如 IP address、timestamp）派生的临时、去标识 event data，且 EEA / UK / Switzerland 不激活；AAP 集成要求在发送 app conversions 给第三方 AAP 前先采集 EEA 用户 consent，且 SDK / S2S 路径会传递 app conversion event、referrer 和 consent status。这说明 `boot_time`、`ip`、referrer、timestamp 这类信号不能只在 privacy 文案里讨论，而必须进入 runtime trace、policy 和 per-event derivation record。

第四，Apple AdAttributionKit 文档继续给出一个强边界：postback 可以携带有限 campaign / conversion / publisher 信息，且通过 crowd anonymity threshold 控制；但 Apple 明确不允许从设备、位置或网络连接派生唯一识别。对本文的含义是：Apple platform postback 可以用于 reconciliation 和 aggregate reporting explanation，不能被用来绕开 SDK 内部的 sensitive-signal release policy。

第五，AppsFlyer 的 2026-04 隐私保护 campaign measurement 文档把 MMP 现实说清楚：当 advertiser ID 不可用时，MMP 仍会组合 install referrer、probabilistic modeling、deep linking、gbraid、SKAN / AEM / ASA 等方法；多数 SRN 仍要求 advertising ID，但少数支持 privacy-preserving alternatives。本文因此不能把 SRN claim 设计成“纯平台 postback”或“纯 MMP probabilistic”；更稳的 spec 是保留 MMP Ask / Claim / Confirm，同时把每种 platform / partner 方法写进 `SdkMeasurementRuntimeTrace` 和 compatibility profile。

落地结论：

1. 新增 `DeviceSensitiveSignalDerivationRecord`，把一次事件实际使用的 sensitive signal policy、派生桶、consent snapshot、release surface、retention 和 internal join key 记录下来。
2. `server_request_id:int64` 可以出现在 derivation record 和 Ad Network optimization plane，但必须标注 `internal only`；MMP payload 仍不得携带它。
3. `raw_ip`、`boot_time_ms`、`ip_prefix`、OPRF input/output、`device_fp_hash` 继续不得进入 MMP、普通日志或 trainer raw feature。
4. Phase 1 可以放松 DP：request-level optimization label 可先留在 Ad Network 受控边界，公开 reporting 和跨方分析走 aggregate / threshold / optional-DP。但如果没有 DP，就必须在 `privacy_profile`、`formal_budget_model` 和上线实验记录里诚实标注，不能宣传为严格 DP。

### 20.29 截至 2026-05-17 的最新 delta：从 schema RFC 推进到 conformance RFC

本次复查没有发现需要改变 `MMP Ask -> Ad Network Claim -> MMP Confirm -> server_request_id label release` 的新证据。新增判断是：这份文档已经不能只停在“定义了很多对象”，还要要求实现方声明自己到底实现了哪一级能力。

第一，[W3C Standards and Drafts Index](https://www.w3.org/TR/?status%5B0%5D=draftStandard) 仍显示 `Attribution Level 1` 最新公开草案日期为 `2026-05-14`，文档本身仍声明它是 Working Draft。对 RFC 的含义是：公开 reporting plane 可以继续跟 W3C / DAP / VDAF 的 aggregate、anti-replay、privacy budget 语义对齐，但不应把仍在变化的平台 draft 当作唯一生产依赖。

第二，[Google Ads ICM 官方说明](https://support.google.com/google-ads/answer/16203286?hl=en-EN) 继续把 ICM 定位为通过第三方 App Attribution Partner interface 提供更实时、事件级 reporting 的方案，并明确 S2S 集成需要把 on-device measurement `info` string 传给 AAP。这支持本文把 ICM / ODM 建模为 partner compatibility surface：它能提高 MMP/AAP 报告可见性，但仍不替代 Ad Network 内部 `server_request_id` 优化闭环。

第三，[AppsFlyer ICM bulletin](https://support.appsflyer.com/hc/en-us/articles/37857301293457-Bulletin-AppsFlyer-and-Google-attribution-solution-Open-BETA) 与 [Adjust Google ODM developer guide](https://dev.adjust.com/en/sdk/ios/plugins/google-odm/) 继续把 Google ODM / ICM 写成 SDK / AAP 集成问题：iOS 需要 Firebase 或 Google ODM SDK，Android 更偏 partner-managed path。这支持 `SdkMeasurementRuntimeTrace` 和 `MeasurementConformanceProfile`：`icm_enabled=true` 不是合规声明，必须写清 SDK、partner、region、consent、S2S fallback 和 `odm_info` 缺失语义。

第四，[Uncovering Relationships between Android Developers, User Privacy, and Developer Willingness to Reduce Fingerprinting Risks](https://research.google/pubs/uncovering-relationships-between-android-developers-user-privacy-and-developer-willingness-to-reduce-fingerprinting-risks/)（CHI 2026）提醒一个工程现实：平台限制和开发者善意不足以自动消灭 fingerprinting 风险，真正需要 enforcement、合规可解释性和可执行的 developer workflow。对本文的直接影响是：`DeviceSensitiveSignalPolicy`、`DeviceSensitiveSignalDerivationRecord`、debug-log policy、forbidden-field scan 和 conformance test suite 必须成为上线门槛。

落地结论：

1. 新增 `MeasurementConformanceProfile`，把 Profile A/B/C/D、MMP/SRN 合同、第三方库、敏感信号 policy、DP / non-DP 状态、fallback 和测试套件写成正式对象。
2. 新增 `9.19 conformance profile` mock，让广告主 app + MMP + Ad Network 的具体组合能声明“支持什么、不支持什么、哪里放松、哪里必须收紧”。
3. 新增 `15.5 RFC conformance gates` 与 `16.7 conformance test suite`，把 forbidden field、token replay、policy coverage、budget lifecycle 和 training manifest 做成可自动检查的验收项。
4. Phase 1 继续可以不对 request-level optimization 上 DP，但必须在 conformance profile 里标成 `no_dp_confidential`；只有 aggregate plane 有正式 budget / DP 计划时，才能对外宣称 DP aggregate reporting。

### 20.30 截至 2026-05-19 的最新 delta：composition 与 launch-clock evidence

本次复查没有改变主链路，但把两个之前容易被低估的生产问题补成协议对象：端到端 privacy composition，以及 launch / clock evidence。

第一，[W3C Attribution Level 1](https://www.w3.org/TR/attribution/) 最新公开版本是 `2026-05-14` Working Draft。文档继续把广告测量建模为 user-agent 侧保存 impression、conversion 时产生 encrypted histogram contribution、aggregation service 做 anti-replay 和 DP aggregate release；同时在 security considerations 中明确提醒 timing、shared memory/storage/network/CPU、global budget lock 等 side-channel 风险。对本文的影响是：端侧 Ask / PSM / Claim 路径不能只保证“字段没泄露”，还要避免从返回值、异常、耗时和日志量泄露 hit/miss、budget exhausted 或非零 conversion value。

第二，[Making Sense of Private Advertising: A Principled Approach to a Complex Ecosystem](https://petsymposium.org/popets/2026/popets-2026-0023.php)（PoPETs 2026）把 private advertising 的问题从单个协议提升到 ecosystem composition：targeting、engagement metrics、attribution、reporting 分别设计出的 privacy notion 不会自动组合成一个自然的整体隐私保证；只要广告系统还支持 market research，某些信息泄露就是系统效用的一部分。对本文的影响是：不能把 “ODM keeps identifiable info on device” + “SRN yes/no claim” + “aggregate report has DP” 相加后宣称端到端 DP。本文因此新增 `EcosystemPrivacyCompositionRecord`，要求显式列出 composed surfaces、raw sensitive inputs、external/internal release surfaces、residual leakage channels 和上线 gate。

第三，[Google Ads ICM 官方说明](https://support.google.com/google-ads/answer/16203286?hl=en-EN) 仍把 ICM 定位为 AAP interface 中更实时、事件级的 cross-channel attribution，并要求 S2S 集成把 on-device measurement `info` string 传给 AAP。这继续支持本文的边界：AAP / MMP reporting 是 partner compatibility surface，不是 Ad Network 内部 `server_request_id` 优化闭环的替代品；`odm_info` 可以在合约路径内传递，但不能进入 trainer raw feature。

第四，[Adjust Google ODM developer guide](https://dev.adjust.com/en/sdk/ios/plugins/google-odm/) 进一步把生产细节写实：Adjust SDK `5.4.1` 起支持 ODM plugin；如果 app 已使用 Firebase iOS SDK `11.14.0+`，`GoogleAdsOnDeviceConversion` 依赖会由 Firebase Analytics pod 带入；否则可显式加入 `GoogleAdsOnDeviceConversion`；并且准确归因的关键之一是尽可能早地捕获 app launch time。对本文的影响是：`boot_time` / launch time 既不是普通训练特征，也不是必须完全丢弃的信号，而应进入 `LaunchClockEvidenceRecord`，用粗桶供 attribution health / optimization weighting 使用，raw 值不释放给 MMP、普通日志或 trainer。

第五，[A Hardware-Anchored Privacy Middleware for PII Sharing Across Heterogeneous Embedded Consumer Devices](https://research.google/pubs/a-hardware-anchored-privacy-middleware-for-pii-sharing-across-heterogeneous-embedded-consumer-devices/) 虽然不是广告 measurement 论文，但它提出的 Contextual Scope Enforcement 对本文有直接工程启发：PII 能否释放不能只看字段名，还要看用户意图、workflow context 和接收方 scope。本文把这个思想落到 `DeviceSensitiveSignalPolicy`、`LaunchClockEvidenceRecord` 和 `EcosystemPrivacyCompositionRecord`：同一个 `advertiser_user_id:int64`、`raw_ip` 或 `boot_time_ms` 在 advertiser app、MMP/AAP、Ad Network trainer、aggregate report 中的合法状态不同，必须由协议对象显式声明。

落地结论：

1. 新增 `LaunchClockEvidenceRecord`，把 app launch time、SDK init delay、monotonic clock 和 raw boot time 的采集、分桶、release surface 与 side-channel mitigation 写清楚。
2. 新增 `EcosystemPrivacyCompositionRecord`，把 advertiser user id、`server_request_id`、`raw_ip`、`boot_time_ms`、`odm_info`、MMP winner、request-level label 和 aggregate release 放进同一张端到端 composition 风险表。
3. 新增 `9.20` 与 `9.21` mock payload，明确 `advertiser_user_id:int64` 在 Protobuf JSON 中建议编码成字符串，但类型契约仍是 int64；同时说明它不能和 `server_request_id` 合成万能 user row。
4. 新增 `15.6 composition 与 clock evidence gates`，要求 Profile B+ 在启用 MMP/AAP + SRN Confirm + request-level optimization 时必须产出 composition record。
5. 更新 `16.7 conformance test suite`，加入 launch-clock evidence、composition leak 与 side-channel regression 测试。

## 21. 参考资料

### 21.1 Research

1. [Mayfly: Private Aggregate Insights from Ephemeral Streams of On-Device User Data](https://research.google/pubs/mayfly-private-aggregate-insights-from-ephemeral-streams-of-on-device-user-data/)
2. [Confidential Federated Computations](https://research.google/pubs/confidential-federated-computations/)
3. [Scalable contribution bounding to achieve privacy](https://research.google/pubs/scalable-contribution-bounding-to-achieve-privacy/)
4. [It's My Data Too: Private ML for Datasets with Multi-User Training Examples](https://research.google/pubs/its-my-data-too-private-ml-for-datasets-with-multi-user-training-examples/)
5. [On the Differential Privacy and Interactivity of Privacy Sandbox Reports](https://research.google/pubs/on-the-differential-privacy-and-interactivity-of-privacy-sandbox-reports/)
6. [DP-Auditorium](https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/)
7. [Sequentially Auditing Differential Privacy](https://research.google/pubs/sequentially-auditing-differential-privacy/)
8. [Differential Privacy on Trust Graphs](https://research.google/pubs/differential-privacy-on-trust-graphs/)
9. [Empirical Privacy Variance](https://research.google/pubs/empirical-privacy-variance/)
10. [SNPeek](https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/)
11. [TDXRay](https://research.google/pubs/tdxray-microarchitectural-side-channel-analysis-of-intel-tdx-for-real-world-workloads/)
12. [Vεrity: Verifiable Local Differential Privacy](https://research.google/pubs/v%CE%B5rity-verifiable-local-differential-privacy/)
13. [About the Enhanced attribution model](https://support.appsflyer.com/hc/en-us/articles/41442782045073-About-the-Enhanced-attribution-model)
14. [Hardening Confidential Federated Compute against Side-channel Attacks](https://arxiv.org/abs/2603.21469)
15. [Google’s Approach to Protecting Privacy in the Age of AI](https://research.google/pubs/googles-approach-to-protecting-privacy-in-the-age-of-ai/)
16. [Proteus: A Practical Framework for Privacy-Preserving Device Logs](https://arxiv.org/abs/2603.06540)
17. [Who am I Talking to? A Large-Scale Measurement of Surface Attribution Across Real-World Security and Privacy Interfaces](https://research.google/pubs/who-am-i-talking-to-a-large-scale-measurement-of-surface-attribution-across-real-world-security-and-privacy-interfaces/)
18. [Predicted Incrementality by Experimentation (PIE) for Ad Measurement](https://arxiv.org/abs/2304.06828)
19. [PrivacyGo: Privacy-Preserving Ad Measurement with Multidimensional Intersection](https://arxiv.org/abs/2506.20981)
20. [Differentially Private Ad Conversion Measurement](https://arxiv.org/abs/2403.15224)
21. [Click Without Compromise: Online Advertising Measurement via Per User Differential Privacy](https://arxiv.org/abs/2406.02463)
22. [Private Ad Modeling with DP-SGD](https://research.google/pubs/private-ad-modeling-with-dp-sgd/)
23. [Training Differentially Private Ad Prediction Models with Semi-Sensitive Features](https://research.google/pubs/training-differentially-private-ad-prediction-models-with-semi-sensitive-features/)
24. [How Private are DP-SGD Implementations?](https://research.google/pubs/how-private-are-dp-sgd-implementations/)
25. [Balls-and-Bins Sampling for DP-SGD](https://research.google/pubs/balls-and-bins-sampling-for-dp-sgd/)
26. [On Convex Optimization with Semi-Sensitive Features](https://research.google/pubs/on-convex-optimization-with-semi-sensitive-features/)
27. [Beyond Per-Querier Budgets: Rigorous and Resilient Global Privacy Enforcement for the W3C Attribution API](https://arxiv.org/abs/2506.05290)
28. [Privacy on the Fly: A Predictive Adversarial Transformation Network for Mobile Sensor Data](https://arxiv.org/abs/2511.07242)
29. [Can privacy technologies replace cookies? Ad revenue in a field experiment](https://pubmed.ncbi.nlm.nih.gov/42085163/)
30. [Privacy-Enhanced versus Traditional Retargeting: Ad Effectiveness in an Industry-Wide Field Experiment](https://ideas.repec.org/p/net/wpaper/2406.html)
31. [The Privacy-Utility Trade-Off of Location Tracking in Ad Personalization](https://arxiv.org/abs/2603.12374)
32. [The TCF doesn't really A(A)ID -- Automatic Privacy Analysis and Legal Compliance of TCF-based Android Applications](https://arxiv.org/abs/2602.20222)
33. [Blind Targeting: Personalization under Third-Party Privacy Constraints](https://arxiv.org/abs/2507.05175)
34. [Privacy Preserving Conversion Modeling in Data Clean Room](https://arxiv.org/abs/2505.14959)
35. [Uncovering Relationships between Android Developers, User Privacy, and Developer Willingness to Reduce Fingerprinting Risks](https://research.google/pubs/uncovering-relationships-between-android-developers-user-privacy-and-developer-willingness-to-reduce-fingerprinting-risks/)
36. [Making Sense of Private Advertising: A Principled Approach to a Complex Ecosystem](https://petsymposium.org/popets/2026/popets-2026-0023.php)
37. [Cookie Monster: Efficient On-device Budgeting for Differentially-Private Ad-Measurement Systems](https://arxiv.org/abs/2405.16719)
38. [A Hardware-Anchored Privacy Middleware for PII Sharing Across Heterogeneous Embedded Consumer Devices](https://research.google/pubs/a-hardware-anchored-privacy-middleware-for-pii-sharing-across-heterogeneous-embedded-consumer-devices/)

### 21.2 Standards

1. [DAP](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap/)
2. [DAP Taskprov](https://datatracker.ietf.org/doc/draft-ietf-ppm-dap-taskprov/)
3. [VDAF](https://datatracker.ietf.org/doc/draft-irtf-cfrg-vdaf/)
4. [DAP Extensions for the Attribution API](https://datatracker.ietf.org/doc/draft-thomson-ppm-dap-attribution/)
5. [W3C Attribution Level 1](https://www.w3.org/TR/attribution/)
6. [RFC 9497: Oblivious Pseudorandom Functions (OPRFs) Using Prime-Order Groups](https://www.rfc-editor.org/rfc/rfc9497)
7. [RFC 9576: The Privacy Pass Architecture](https://www.ietf.org/rfc/rfc9576.html)
8. [RFC 9577: The Privacy Pass HTTP Authentication Scheme](https://www.ietf.org/rfc/rfc9577.html)
9. [GDPR Article 4 Definitions](https://gdpr-info.eu/art-4-gdpr/)
10. [EDPB Guidelines 01/2025 on Pseudonymisation](https://www.edpb.europa.eu/system/files/2025-01/edpb_guidelines_202501_pseudonymisation_en.pdf)
11. [California Consumer Privacy Act statute](https://cppa.ca.gov/regulations/pdf/ccpa_statute.pdf)
12. [IAB Tech Lab Attribution Data Matching Protocol (ADMaP)](https://iabtechlab.com/admap/)
13. [IAB Tech Lab Global Privacy Protocol](https://iabtechlab.com/gpp/)
14. [IAB Tech Lab Data Deletion Request Framework](https://iabtechlab.com/standards/data-deletion-request-framework/)
15. [W3C privacy-preserving-attribution cover page](https://www.w3.org/TR/privacy-preserving-attribution/all/)
16. [W3C Standards and Drafts Index](https://www.w3.org/TR/?status%5B0%5D=draftStandard)

### 21.3 Product / Integration

1. [Integrated Conversion Measurement](https://support.google.com/google-ads/answer/16203286?hl=en-EN)
2. [About on-device conversion measurement for iOS App campaigns](https://support.google.com/google-ads/answer/12119136?hl=en)
3. [App Conversion Tracking and Remarketing - Request/Response Specifications](https://developers.google.com/app-conversion-tracking/api/request-response-specs)
4. [Implement on-device conversion measurement with a standalone SDK](https://support.google.com/google-ads/answer/16384720?hl=en)
5. [GoogleAdsOnDeviceConversion SDK](https://github.com/googleads/google-ads-on-device-conversion-ios-sdk)
6. [AppsFlyer attribution model](https://support.appsflyer.com/hc/en-us/articles/207447053-AppsFlyer-attribution-model)
7. [Adjust Self-attributing network setup](https://help.adjust.com/en/article/self-attributing-network-san-setup)
8. [Adjust Assists](https://help.adjust.com/en/article/assists)
9. [Adjust self-attributing callbacks](https://help.adjust.com/en/article/self-attributing-network-callbacks)
10. [Understanding iOS App campaign measurement and reporting](https://support.google.com/google-ads/answer/16771743)
11. Google ODC / ODM On-Device Measurement 技术逆向与实现模型，2026-04-30，基于 2026-04-14 HAR 样本。
12. [Singular Google Ads Mobile App Campaigns Attribution Integration](https://support.singular.net/hc/en-us/articles/115003252786-Google-Ads-AdWords-Mobile-App-Campaigns-Attribution-Integration)
13. [Singular iOS SDK Advanced Options](https://support.singular.net/hc/en-us/articles/36198405689243-iOS-SDK-Advanced-Options?navigation_side_bar=true)
14. [IAB Tech Lab Device Attestation Support in OM SDK](https://iabtechlab.com/press-releases/device-attestation-support-in-open-measurement-sdk/)
15. [Open Measurement Device Attestation Implementation Guidance](https://iabtechlab.com/wp-content/uploads/2025/10/Open-Measurement-Device-Attestation-Implementation-Guidance.pdf)
16. [IAB Project Eidos](https://www.iab.com/news/iab-announces-project-eidos/)
17. [AppsFlyer and Google attribution solution Open Beta](https://support.appsflyer.com/hc/en-us/articles/37857301293457-Bulletin-AppsFlyer-and-Google-attribution-solution-Open-BETA)
18. [Branch Partners with Google on ICM](https://help.branch.io/account-hub/docs/branch-google-icm-for-enhanced-mobile-measurement)
19. [Airbridge now supports Google ICM](https://www.airbridge.io/en/blog/airbridge-google-icm)
20. [Airbridge Google Ads touchpoint definitions and ICM attribution data](https://help.airbridge.io/en/guides/ad-channel-touchpoint-types)
21. [Kochava Google Ads Integrated Conversion Measurement](https://www.kochava.com/ru/blog/google-ads-integrated-conversion-measurement/)
22. [Tenjin Google Ads Integrated Conversion Measurement support](https://tenjin.com/blog/tenjin-announces-early-support-for-google-ads-integrated-conversion-measurement/)
23. [Adjust Integrated Conversion Measurement overview](https://www.adjust.com/blog/integrated-conversion-measurement/)
24. [Google Privacy Sandbox: Update on Plans for Privacy Sandbox Technologies](https://privacysandbox.google.com/blog/update-on-plans-for-privacy-sandbox-technologies)
25. [Android MeasurementManager API reference](https://developer.android.com/reference/kotlin/android/adservices/measurement/MeasurementManager)
26. [Apple AdAttributionKit: Receiving ad attributions and postbacks](https://developer.apple.com/documentation/adattributionkit/receiving-ad-attributions-and-postbacks)
27. [Apple AdAttributionKit: Identifying conversion values with conversion tags](https://developer.apple.com/documentation/adattributionkit/conversion-tags)
28. [WWDC25: What's new in AdAttributionKit](https://developer.apple.com/videos/play/wwdc2025/221/)
29. [Google Ads Help: About Integrated Conversion Measurement for App Campaigns](https://support.google.com/google-ads/answer/16203286?hl=en-EN)
30. [Apple Developer: Measuring ad performance with AdAttributionKit](https://developer.apple.com/app-store/ad-attribution/)
31. [AppsFlyer: Privacy-preserving campaign measurement](https://support.appsflyer.com/hc/en-us/articles/20489739742609-Privacy-preserving-campaign-measurement)
32. [Adjust Developer Hub: Google On-device Conversion Measurement](https://dev.adjust.com/en/sdk/ios/plugins/google-odm/)

### 21.4 Engineering Components

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
11. [cloudflare/circl](https://github.com/cloudflare/circl)
12. [cloudflare/voprf-ts](https://github.com/cloudflare/voprf-ts)
13. [OpenFHE](https://openfhe-development.readthedocs.io/en/latest/)
14. [Microsoft SEAL](https://github.com/microsoft/SEAL)
15. [Lattigo](https://github.com/tuneinsight/lattigo)
16. [Concrete ML](https://docs.zama.org/concrete-ml/1.4/)
17. [EconML](https://www.microsoft.com/en-us/research/project/econml/)
18. [DoWhy](https://github.com/py-why/dowhy)

### 21.5 Patent / Prior Art

1. [Google LLC: Aggregated conversion measurement, US20220086240A1 / US11711436B2](https://patents.google.com/patent/US11711436B2/en)
2. [Microsoft Technology Licensing: On-device privatization of multi-party attribution data, US20240143416A1 / US12327150B2](https://patents.google.com/patent/US20240143416A1/en)
3. [Google LLC: Privacy-preserving and secure application install attribution, US20240095364A1 / WO2023214975A1](https://patents.google.com/patent/US20240095364A1/en)
4. [Google LLC: Secure attribution using attestation tokens, WO2023028293A1 / US20240220654A1](https://patents.google.com/patent/WO2023028293A1/en)
5. [Google LLC: Privacy preserving cross-domain machine learning, US20220405407A1](https://patents.google.com/patent/US20220405407A1/en)
