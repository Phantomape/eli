# Google On-Device Measurement 隐私技术研究与技术规格说明

## 1. 文档目的

本文档面向“前沿隐私技术验证”项目，梳理 Google 在 on-device measurement 方向公开披露的论文、系统设计与产品资料，并将其整合为一份可用于技术评估、原型设计和架构对标的技术规格说明（spec）。

本文聚焦的问题是：

- Google 如何在设备侧执行或辅助执行 measurement 相关计算，而不把可识别原始数据直接回传到中心端。
- Google 公开论文中使用了哪些核心隐私技术：federated analytics、differential privacy、local DP、MPC、homomorphic encryption、TEE/confidential computing、数据最小化与贡献裁剪。
- Google Ads / Privacy Sandbox / Google Research 这几条线索如何拼接成一个合理的 on-device measurement 技术栈。

## 2. 范围与方法

### 2.1 研究范围

本文优先纳入三类资料：

1. Google Research 论文或白皮书页面中，直接讨论 measurement、reach/frequency、on-device analytics、federated analytics、confidential federated computations 的资料。
2. Google Ads 官方产品文档中，明确使用 “on-device conversion measurement” 的资料。
3. 与上述系统直接相关的底层隐私技术论文，用于补全设计原理。

### 2.2 证据分级

- A 级，直接相关：论文或官方文档直接讨论 on-device measurement、reach/frequency estimation、conversion measurement。
- B 级，强相关基础设施：论文不一定直接使用 “measurement” 命名，但明确支持设备侧隐私分析或聚合。
- C 级，背景性支撑：为理解 Google 技术路线提供上下文，但不应被误读为 Google Ads 产品的直接实现证据。

### 2.3 重要说明

Google 官方公开资料并没有完整披露 “Google Ads on-device conversion measurement” 的全部内部协议与代码路径。因此，本文中的“参考架构”和“系统规格”有两部分：

- 明确来自论文或官方文档的事实。
- 基于多篇论文和产品文档交叉整理出的工程性推断。

凡属推断，本文会显式标注“推断”。

## 3. 核心结论摘要

### 3.1 高层判断

Google 在 on-device measurement 方向的公开技术路线，不是单一算法，而是多种隐私技术的组合：

- 设备侧事件处理与数据最小化
- 设备侧或分布式贡献裁剪
- 差分隐私，尤其是 streaming DP / central DP / local DP
- 联邦分析（federated analytics）
- 多方安全计算（MPC）与同态加密，用于跨参与方 measurement
- 可信执行环境（TEE），用于把“服务端正确执行隐私机制”从信任假设变成可验证属性

### 3.2 与 Google Ads on-device conversion measurement 的关系

从官方帮助文档可确认，Google Ads 已在 iOS App campaigns 中提供 “on-device conversion measurement”：

- 一种路径使用第一方标识数据，例如邮箱或手机号，在设备侧完成隐私保护式测量。
- 另一种路径使用去标识、临时的 app event data，例如由设备信号和时间戳导出的特征。

但官方文档没有公开声明该产品具体对应哪一篇论文。因此，更稳妥的结论是：

- 产品层的 on-device conversion measurement 已经存在。
- 其底层思路与 Google Research 在 federated analytics、DP、confidential federated computations 以及 measurement sketching/MPC 方向的研究高度一致。
- 不能把单篇论文直接等同为该产品实现；更合理的做法是将它们视为同一技术路线下的研究与产品化证据。

## 4. 论文与资料清单

### 4.1 A 级：直接相关论文与资料

#### 4.1.1 Mayfly: Private Aggregate Insights from Ephemeral Streams of On-Device User Data (2024)

- 类型：Google Research 论文
- 相关度：A
- 关键词：federated analytics、ephemeral on-device data、streaming DP、group-by-sum

价值：

- 这是目前最接近 “on-device measurement” 系统形态的公开论文之一。
- 它明确处理“短期保留的设备侧事件流”，并支持 aggregate queries。
- 论文强调不做中心化持久化，而是在设备侧做窗口化、贡献界定与最小化，然后只在服务端做内存中的聚合并输出加噪后的结果。

对 spec 的启发：

- 适合作为“设备侧 measurement 管线”的基线架构。
- 特别适合事件统计、分组求和、趋势统计、分桶分析这类 measurement 工作负载。

#### 4.1.2 Privacy-centric Cross-publisher Reach and Frequency Estimation via Vector of Counts (2021)

- 类型：Google Research 论文
- 相关度：A
- 关键词：reach/frequency、local DP、cross-publisher measurement、VoC

价值：

- 这篇论文直接面向广告 measurement 的核心问题：跨发布方 reach 与 frequency。
- 使用 local differential privacy 方案，在严格隐私限制下估计 reach/frequency。
- 对 measurement 领域非常关键，因为它讨论的不是一般 analytics，而是广告效果和受众覆盖测量。

对 spec 的启发：

- 适合作为 cross-party / cross-publisher measurement 的统计估计层。
- 说明 measurement 系统可以在极强隐私约束下仍保留一定可用性。

#### 4.1.3 A System Design for Privacy-Preserving Reach and Frequency Estimation (2020)

- 类型：Google 系统设计文档
- 相关度：A
- 关键词：system design、MPC、private reach/frequency

价值：

- 该文档不是单纯算法论文，而是系统设计层面的说明。
- 它把 measurement 问题明确建模为一个 MPC-based system。
- 对理解工程实现尤其重要，因为它回答的是“如何部署”，不只是“如何估计”。

对 spec 的启发：

- 可作为跨机构 measurement 的服务端协议蓝本。
- 尤其适用于广告平台、测量方、发布方之间互不完全信任的场景。

#### 4.1.4 Privacy-Preserving Secure Cardinality and Frequency Estimation (2020)

- 类型：Google Research 论文
- 相关度：A
- 关键词：cardinality、frequency、HE、MPC、sketch

价值：

- 给 reach/frequency measurement 提供了更底层的安全估计方法。
- 组合了 HLL/Bloom-filter 风格草图与同态加密、MPC。
- 面向多方参与且不能互信的 cardinality/frequency estimation。

对 spec 的启发：

- 是 measurement sketch 层的重要候选。
- 适用于唯一触达、频次、交集规模等指标。

#### 4.1.5 About on-device conversion measurement for iOS App campaigns

- 类型：Google Ads 官方产品文档
- 相关度：A
- 关键词：on-device conversion measurement、iOS、app campaigns

可确认事实：

- Google Ads 产品已正式提供 on-device conversion measurement。
- 方案包含两条路径：
  - 使用第一方数据，例如 email / phone collected through app sign-in。
  - 使用去标识、临时 event data，例如由设备信号与时间戳推导的数据。
- 目标是提升 conversion observability、reporting 与 optimization，同时不把 identifiable information 暴露给 Google 或外部方。
- 文档明确提到此功能在 EEA、英国和瑞士不激活。

对 spec 的启发：

- 这为“设备侧归因/转化测量”提供了直接产品证据。
- 同时说明实际产品可能存在区域性合规分流。

#### 4.1.6 Implement on-device conversion measurement with a standalone SDK

- 类型：Google Ads 官方开发者文档
- 相关度：A
- 关键词：SDK、iOS、aggregate conversion info

可确认事实：

- Google 提供独立 SDK 接入方式。
- SDK 在设备侧生成 `aggregateConversionInfo`，再由调用方将其作为 `odm_info` 参数上传到 App Conversion API。
- 这表明 conversion measurement 的某一关键中间结果确实是在设备上生成的，且上传的是聚合/编码后的信息，而非直接明文原始事件。

对 spec 的启发：

- 可将 `aggregateConversionInfo` 视为“设备侧私有测量输出令牌”。
- SDK 模式说明 Google 已将部分 measurement 逻辑产品化为本地库，而不是完全依赖服务端。

### 4.2 B 级：强相关底层论文

#### 4.2.1 Confidential Federated Computations (2024)

- 类型：Google Research / arXiv
- 相关度：B
- 关键词：TEE、federated analytics、verifiability、DP

价值：

- 这篇论文解释了为什么“只做联邦计算”还不够。
- 它提出用 TEE + 开源代码来约束服务端行为，使隐私保证变得更可验证。
- 这对 measurement 产品非常关键，因为 measurement 往往需要平台方、广告方、分析方信任“聚合器没有越权”。

对 spec 的启发：

- 如果要做更高信任级别的 on-device measurement，服务端应考虑 confidential aggregation。
- 适合作为下一代 measurement backend 的可信执行架构。

#### 4.2.2 On-Device Algorithms for Public-Private Data with Absolute Privacy (2019)

- 类型：Google Research 论文
- 相关度：B
- 关键词：on-device computation、absolute privacy、public-private model

价值：

- 从理论上定义了“私有数据永不离开设备”的算法模型。
- 虽然不直接针对广告 measurement，但对 on-device analytics / recommendation / private mining 有基础性意义。

对 spec 的启发：

- 可作为“为什么某些计算必须在设备侧做”的理论依据。
- 强化了设备本地执行而非中心回传的设计原则。

#### 4.2.3 Private Aggregation of Trajectories (2022)

- 类型：Google Research 论文
- 相关度：B
- 关键词：trajectory aggregation、DP aggregation

价值：

- 研究如何对用户轨迹做差分隐私聚合。
- 虽然应用场景更偏 location / mobility measurement，但它证明了高敏感序列数据也能以聚合方式测量。

对 spec 的启发：

- 如果 on-device measurement 包含路径、时空、序列类事件，该论文提供可借鉴机制。

#### 4.2.4 Prochlo: Strong Privacy for Analytics in the Crowd (2017)

- 类型：Google Research 论文
- 相关度：B
- 关键词：Encode-Shuffle-Analyze、analytics pipeline

价值：

- 这是 Google 公开隐私分析技术路线的重要前身。
- 核心思想是把客户端编码、shuffle 混洗与分析拆分，降低单点看到可识别数据的能力。

对 spec 的启发：

- 虽然不是 today’s on-device conversion measurement 的直接证据，但它为 Google 后续 analytics 和 measurement 隐私架构提供了思想基础。

### 4.3 C 级：背景性支撑资料

#### 4.3.1 Federated Evaluation of On-device Personalization (2019)

- 类型：Google Research 论文
- 相关度：C
- 作用：说明 Google 长期具备大规模设备侧计算与评估能力，但不直接是 measurement 论文。

#### 4.3.2 Federated Heavy Hitters with Differential Privacy (2020)

- 类型：Google Research 论文
- 相关度：C
- 作用：说明 Google 在分布式、设备侧、差分隐私统计提取上已有成熟研究。

## 5. 技术归纳：Google on-device measurement 的隐私技术栈

基于上述资料，可以把 Google 的公开技术路线归纳为六层。

### 5.1 设备侧数据最小化层

职责：

- 在设备侧保留原始事件
- 做窗口化、截断、采样、贡献裁剪
- 只输出完成 measurement 所需的最小摘要

主要证据：

- Mayfly
- Google Ads on-device conversion measurement SDK 文档

设计原则：

- 原始标识符、原始事件序列、稳定可链接轨迹不应直接离开设备。
- 设备上优先生成短生命周期、任务特定的 measurement artifact。

### 5.2 设备侧编码与匿名化层

职责：

- 把设备原始观察编码成匿名化或半匿名化中间表示
- 执行本地随机化、贡献界定或局部摘要化

主要证据：

- Privacy-centric Cross-publisher Reach and Frequency Estimation via VoC
- Prochlo

设计原则：

- 输出对象最好是 sketch、token、aggregate info 或局部随机化结果，而不是明文字段。

### 5.3 联邦聚合层

职责：

- 从大量设备收集最小化消息
- 聚合后只暴露群体统计量

主要证据：

- Mayfly
- Confidential Federated Computations

设计原则：

- 聚合前不允许分析方查看单设备原始消息。
- 聚合后才允许结果进入分析与报表链路。

### 5.4 差分隐私层

职责：

- 防止从最终报表或查询接口中反推出单用户存在性或属性

主要证据：

- Mayfly
- VoC
- trajectory aggregation
- confidential federated computations

设计原则：

- 按工作负载区分 DP 机制：
  - count / histogram 类
  - group-by-sum 类
  - streaming analytics 类
- 必须明确隐私预算单位，例如 per-device / per-week。

### 5.5 多方安全测量层

职责：

- 在平台、发布方、第三方测量方之间做不互信条件下的联合 measurement

主要证据：

- Privacy-Preserving Secure Cardinality and Frequency Estimation
- A System Design for Privacy-Preserving Reach and Frequency Estimation

设计原则：

- cross-publisher reach/frequency 不应依赖一方获得全部可链接明文数据。
- sketch + HE/MPC 是合理路线。

### 5.6 可验证执行层

职责：

- 降低“服务端是否正确执行隐私机制”带来的信任负担

主要证据：

- Confidential Federated Computations

设计原则：

- 优先引入 TEE、remote attestation、开源聚合逻辑或可审计执行路径。

## 5A. Private Membership / PSI / PJC 技术线补充

本节补充一组与 measurement 强相关、但和差分隐私或联邦分析并不完全相同的密码学原语。这组技术的共同点是：它们处理的是“集合之间如何在不暴露明文元素的前提下进行匹配、判断或聚合”。

### 5A.1 三类技术的区别

#### Private Set Membership (PSM)

定义：

- 客户端想私密查询一个标识符是否属于服务端持有的集合。
- 输出通常只有一个 membership bit，即“在”或“不在”。

适合场景：

- 本地设备需要判断某个 token、app identifier、threat indicator、account marker 是否命中服务端集合。
- 服务端不应知道客户端到底查询了哪个值。

不适合直接解决的问题：

- 统计交集大小
- 计算交集上的转化和
- 做多方归因或 reach/frequency 聚合

#### Private Set Intersection (PSI)

定义：

- 双方想知道集合交集，或者至少知道交集规模。

适合场景：

- 判断两方数据里共同出现了哪些 ID。
- 统计相交用户数。

局限：

- 如果最终目标是广告 measurement，单纯 PSI 往往不够，因为 measurement 通常还要对交集上的值做求和、归因或进一步统计。

#### Private Join and Compute / Private Intersection-Sum (PJC / PI-Sum)

定义：

- 在私密求交的基础上，对交集记录的附加值继续做计算，例如求和、计数或内积。

适合场景：

- aggregate conversion measurement
- conversion attribution
- sales lift / matched outcome aggregation

结论：

- 从 measurement 角度看，PJC / PI-Sum 往往比 PSM 更贴近“广告转化测量”的核心需求。

### 5A.2 Google 的直接证据

#### 5A.2.1 Google 开源了 Private Set Membership (PSM) 实现

Google 在 GitHub 上公开了 `google/private-membership` 仓库，并将其定义为 Private Set Membership 协议。

可确认事实：

- 该仓库明确给出 PSM 的问题定义。
- 该仓库写明三项隐私目标：
  - 服务端不知道客户端查询的明文标识符。
  - 服务端不知道查询结果是命中还是未命中。
  - 客户端除 membership 结果外，学不到服务端集合的额外信息。
- 仓库依赖项中包含用于全同态加密的 `Shell`，表明该实现基于较强的密码学工具。

边界说明：

- 仓库 README 同时声明“这不是官方支持的 Google 产品”。
- 因此，这是 Google 具备该技术能力的强证据，但不是某个 Google 产品已经采用它的直接产品承诺。

#### 5A.2.2 Google Research 公开了更贴近 measurement 的 PJC / PI-Sum 路线

对 measurement 更关键的证据，来自 Google Research 关于交集计算与交集求和的论文。

##### Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions (2020)

价值：

- 论文直接把问题表述为“私密计算广告活动 aggregate conversion rate”。
- 其核心功能是 `Private Intersection-Sum with Cardinality`。
- 这意味着双方基于各自持有的用户标识集合，既能得到交集规模，也能得到交集上数值字段的总和，而不会额外暴露更多信息。

意义：

- 这是 Google 将集合密码学原语直接应用到广告 conversion measurement 的强证据。
- 它比单纯 PSM 更接近真实 measurement 工作负载。

##### Private Join and Compute from PIR with Default (2021)

价值：

- 论文引入 `PIR with default` 来构造 PJC。
- 摘要明确写出该构造可用于 `ads conversion measurement`。
- 同时强调它适用于两个数据库规模差异显著的场景，这一点很符合广告平台与广告主数据体量不对称的实际情况。

意义：

- 这说明 Google 不只是研究“能不能做私密求交”，而是在优化真正可部署的 measurement 协议。

### 5A.3 它和 on-device measurement 的关系

这一点需要谨慎区分“直接证据”和“工程推断”。

#### 可以直接确认的内容

- Google 公开具备 PSM 技术与实现。
- Google 公开具备 PSI / PJC / PI-Sum 方向的研究与开源实现。
- Google Research 论文明确把 PJC / PI-Sum 用于 ads conversion measurement。

#### 合理推断

- 推断：如果一个 on-device measurement 系统需要在设备侧判断某个 identifier 是否属于服务端集合，PSM 是很自然的候选原语。
- 推断：如果一个系统需要做 conversion attribution、aggregate conversion counting 或匹配后求和，PJC / PI-Sum 比纯 PSM 更合适。
- 推断：Google 的 on-device measurement 产品在某些步骤中可能使用 membership-style 查询，在另一些步骤中使用 join-and-compute 风格的协议。

#### 目前不能直接确认的内容

- 不能确认 Google Ads on-device conversion measurement 是否直接使用 `google/private-membership` 仓库中的 PSM 实现。
- 不能确认产品实现中究竟采用 PSM、PSI、PJC 还是多种协议组合。
- 不能确认设备侧与服务端各自承担多少密码学计算。

### 5A.4 对参考架构的启发

如果我们把 Google 的公开路线抽象成一个可复现的 measurement 系统，那么 set-based cryptography 应该被视为一个独立层，而不是差分隐私的替代品。

建议把它放在如下位置：

- 设备侧最小化之前：
  - 用 PSM 判断本地对象是否属于远端受控集合。
- 多方匹配阶段：
  - 用 PSI 或 PJC 完成跨方数据对齐。
- 聚合输出阶段：
  - 再叠加 DP、阈值化和最小群体规模保护。

换句话说：

- PSM / PSI / PJC 解决的是“如何私密匹配”。
- DP / federated analytics / confidential aggregation 解决的是“如何私密发布或聚合”。
- 一个完整的 on-device measurement 系统很可能同时需要两类能力。

### 5A.5 对你们项目的落地建议

如果你们想验证这一方向，建议把它拆成三个独立 PoC：

#### PoC-1：Private Membership Gate

目标：

- 验证设备侧仅凭一个 identifier 或 token，私密判断其是否存在于服务端集合中。

最小输出：

- bool membership result

适合验证的问题：

- 某类设备、某类用户、某个匿名 token 是否命中一个受控实验集合。

#### PoC-2：Private Intersection Cardinality

目标：

- 验证两方在不交换明文 ID 的情况下，得到交集规模。

最小输出：

- intersection size

适合验证的问题：

- matched reach
- overlap estimation

#### PoC-3：Private Intersection-Sum for Measurement

目标：

- 验证在私密匹配后，对交集记录上的数值字段求和。

最小输出：

- intersection cardinality
- intersection sum

适合验证的问题：

- aggregate conversions
- attributed value sum
- sales lift 风格聚合

优先级建议：

- 如果项目目标是“最接近广告转化测量”，优先做 PoC-3。
- 如果目标是“证明设备侧可私密查询服务端名单”，优先做 PoC-1。
- 如果目标是“验证多方匹配能力”，优先做 PoC-2。

## 5B. SRN Claim 在 Yes/No 约束下的协议选择

本节讨论一个更贴近现实产品约束的场景：

- MMP 持有全量广告主 conversion。
- MMP 必须逐条向各个 ad network 发送 claim request。
- 每个 ad network 只能返回 `yes` 或 `no`。
- MMP 基于各 network 的返回结果执行归因裁决，例如 last click。
- MMP 再向获胜 network 发送确认。

这个约束非常重要，因为它会改变最优技术选择。

### 5B.1 关键判断

在这种“外部接口必须是 yes/no”的条件下，最合适的前台协议不是 PJC，而是 membership-style claim protocol。

原因：

- PJC / PI-Sum 的优势在于“匹配后继续计算”，例如求和、比较、内积、聚合。
- 但当外部接口被压缩为单个布尔值时，PJC 的表达能力在 API 边界上无法充分体现。
- 与之相对，Private Membership 风格协议天然适合表达“某个 conversion query 是否属于 network 的可 claim 集合”。

因此可以把问题拆成两层：

- 前台 claim API：membership-style，输出 `yes/no`
- 后台验证、对账、聚合：可继续使用 PJC / PI-Sum

### 5B.2 从 ad network 视角的威胁模型

即使 network 只返回 `yes/no`，也仍然存在明显泄露面。

MMP 可能通过大量查询推断：

- network 对哪些用户或转化有覆盖
- network 的 match rate
- 哪些 campaign / 时间窗中 network 更强
- 哪些转化 network 是“差一点赢”
- network 的 click / impression 分布边界

因此，ad network 真正要保护的不是单个布尔值本身，而是：

- yes/no 背后隐含的 coverage map
- repeated probing 导致的 attribution boundary 泄露
- losers information 被长期累计成竞争情报

### 5B.3 协议层结论

从最强大脑、代表 ad network 利益最大化的角度，推荐如下组合：

- 前台主协议：policy-constrained private membership
- 后台审计与聚合：PJC / PI-Sum
- 外层系统控制：去重、限频、重放保护、query schema 固定化、审计日志

这里的 `policy-constrained private membership` 指的是：

- 外部看起来是 membership 查询
- 但 network 内部并不是做静态集合查找
- 而是在内部执行 `eligible_to_claim(conversion_query) -> bool`

该内部逻辑可以综合考虑：

- 是否存在匹配 click / impression
- attribution window
- touch precedence
- campaign eligibility
- anti-fraud / quality gate
- dedupe 规则

### 5B.4 为什么前台不建议直接暴露更丰富字段

如果 MMP 逐条收集的不只是 `yes/no`，而是：

- click timestamp
- impression timestamp
- campaign id
- touch type
- confidence score

那么 MMP 很容易长期重建 network 的投放覆盖、触达质量和竞争强弱。

因此，站在 ad network 视角，前台 claim API 的最佳实践应当是：

- `yes/no only`
- 不返回 claim reason
- 不返回 loser diagnostics
- 不返回多余 metadata

如果协议允许，最好返回：

- `yes/no`
- `signed claim token`

其中 claim token 应绑定以下内容：

- query id
- query hash
- policy version
- network id
- expiration

这样可以防止 claim 结果被跨上下文复用，并为后续确认提供可审计性。

### 5B.5 设计原则

#### Query key 最小化

- 不应使用长期稳定、跨任务可链接的用户标识。
- 优先使用短生命周期、任务专用、时间窗受限的 query key。

#### Query 去重与限频

- 同一 conversion 只能在受限规则下被询问有限次数。
- 必须阻止 MMP 通过微调时间戳或字段来探测 network 的边界条件。

#### One-shot 或 bounded-shot 查询

- 每个 conversion query 应有固定的 replay policy。
- 更推荐单次查询或少量受控重试。

#### Winner-only 后续确认

- MMP 对网络发送的 finalize / confirm 只应针对 winner。
- loser 不应收到多余信息。

#### 后台安全结算

- 如果后续需要 settlement、aggregate verification 或 outcome reconciliation，推荐在后台使用 PJC / PI-Sum，而不是在前台 claim API 中暴露更多字段。

### 5B.6 工程结论

在“必须返回 yes/no”的现实前提下：

- 对 claim 协议本身，membership-style 方案更合适。
- 对 claim 之后的验证、聚合和结算，PJC / PI-Sum 更合适。
- 最重要的不是把前台协议做得多复杂，而是控制 query key、频率、日志与 replay surface。

## 6. 参考系统规格（spec）

本节给出一个基于公开资料整合出的参考规格。除明确标注外，均为工程化推断，用于研究与原型，不应误解为 Google 官方内部实现文档。

### 6.1 目标

系统名称：

- Privacy-Preserving On-Device Measurement System

系统目标：

- 支持 install、reinstall、conversion、reach、frequency、aggregate event analytics 等 measurement 任务。
- 将可识别原始数据留在设备侧。
- 仅输出聚合统计或编码后的中间信息。
- 能在不同信任模型下运行：
  - 单平台聚合
  - 平台 + 第三方归因方
  - 跨发布方联合 measurement

非目标：

- 不提供用户级明细报表。
- 不支持任意维度、任意次数、无预算控制的明细查询。

### 6.2 角色

- Device Client：移动设备上的 app / SDK / browser 组件
- Measurement SDK：设备侧 measurement 执行库
- Aggregation Service：接收最小化消息并执行聚合
- Confidential Aggregator：可选，运行在 TEE 中
- Reporting Service：仅消费聚合结果，生成报表和优化信号
- Attribution Partner：第三方归因平台，可选

### 6.3 数据分类

- Raw Event：原始事件，例如首次打开、重装、点击、应用内行为
- First-Party Identifier：邮箱、手机号等用户主动提供数据
- Temporary Derived Signal：由 IP、时间戳或设备信号衍生出的短生命周期特征
- Local Sketch / Token：设备侧生成的 measurement 摘要
- Aggregate Output：可对外暴露的最终聚合结果

### 6.4 数据流

#### 6.4.1 设备侧收集

- SDK 读取本地事件与可用的第一方数据或临时派生信号。
- SDK 在设备侧完成规范化、去标识化、窗口化、贡献裁剪。

#### 6.4.2 设备侧计算

- 对 conversion 场景，SDK 生成类似 `aggregateConversionInfo` 的中间对象。
- 对 reach/frequency 场景，设备侧生成 sketch 或 randomized response 风格编码结果。
- 对 analytics 场景，设备侧生成 bounded contribution records。

#### 6.4.3 上送与聚合

- 仅上传中间对象，而不是原始事件明文。
- Aggregation Service 收集来自大量设备的消息。
- 服务端在聚合前不向分析方暴露单设备消息。

#### 6.4.4 隐私保护输出

- 聚合器执行 DP、阈值化、最小群体规模校验和结果裁剪。
- 仅把最终 aggregate output 暴露给 reporting / optimization 组件。

### 6.5 隐私要求

#### 6.5.1 数据最小化

- 原始事件不得长时间保存在中心端。
- 稳定标识符不得以可逆明文形式上传。
- 中间对象必须任务特定，避免复用为跨任务跟踪标识符。

#### 6.5.2 贡献约束

- 每个设备在固定时间窗口内的贡献必须可上界。
- 至少按以下维度之一限额：
  - 每设备每日
  - 每设备每周
  - 每 campaign / measurement key

#### 6.5.3 差分隐私

- 系统必须显式维护 privacy budget ledger。
- 预算应与查询类型和时间窗口绑定。
- 对 streaming analytics，优先采用 streaming DP/accounting。

#### 6.5.4 查询审计

- 所有 measurement query 必须可审计。
- 查询模板必须预定义，不允许任意 SQL 直接访问单设备数据。

#### 6.5.5 地域合规分流

- 系统应支持按地域关闭某些 measurement 能力。
- Google Ads 文档已证明至少 EEA / UK / CH 存在差异化激活策略。

### 6.6 安全与信任模型

#### 6.6.1 基础信任模型

- 假设设备端 SDK 行为可信到一定程度。
- 假设聚合服务不应访问单设备明文数据。

#### 6.6.2 增强信任模型

- 使用 TEE 承载聚合逻辑。
- 使用远程证明证明聚合逻辑与公开版本一致。
- 对跨方 measurement 使用 MPC / HE，避免一方看到全量交集数据。

### 6.7 推荐实现模式

#### 模式 A：产品级单平台 on-device conversion measurement

适用：

- iOS app conversion measurement
- 平台自有优化和报表

推荐技术组合：

- 设备侧 SDK
- 本地 token / aggregate info 生成
- 服务端聚合
- DP + 阈值化

#### 模式 B：跨发布方 reach/frequency measurement

适用：

- 广告投放跨 publisher 覆盖分析

推荐技术组合：

- 设备侧或参与方侧 sketch 构造
- MPC / HE
- DP post-processing

#### 模式 C：高信任隐私分析平台

适用：

- 需要对外证明聚合器不会越权

推荐技术组合：

- federated analytics
- confidential aggregation in TEE
- 开源聚合器逻辑
- 外部可验证性

## 7. 与 Google 公开产品的对应关系

### 7.1 可以直接确认的内容

- Google Ads 存在 on-device conversion measurement 产品能力。
- 该能力至少在 iOS App campaign 场景下提供。
- 该能力既支持第一方数据路径，也支持去标识、临时事件数据路径。
- Google 提供独立 SDK，且设备侧会生成 `aggregateConversionInfo` 供后续 API 使用。

### 7.2 基于公开研究的合理推断

- 推断：Google 的 on-device measurement 产品大概率共享了其 federated analytics / DP / confidential computation 的基础设施思想。
- 推断：对于 analytics 类 measurement，Mayfly 所代表的设备侧窗口化 + streaming DP 路线是非常贴近的参考实现。
- 推断：对于 reach/frequency 或跨方 measurement，Google 更可能采用 sketch + MPC/HE + DP 的组合，而不是简单的明文上报。

### 7.3 不能从公开资料直接确认的内容

- 不能确认 Google Ads on-device conversion measurement 的内部协议细节。
- 不能确认其是否直接复用某一篇论文的代码实现。
- 不能确认它在所有国家和产品线中使用相同机制。

## 8. 对你们项目的落地建议

如果你们的目标是“验证前沿隐私技术”，建议按三个阶段推进。

### 8.1 阶段一：最小可行原型

目标：

- 复现 on-device measurement 的基本思想，而不是先追求复杂加密协议。

建议实现：

- 本地事件缓存
- 设备侧窗口化与贡献裁剪
- 本地生成 measurement token
- 中心端仅接收 token 并输出聚合报表
- 简单 DP 噪声机制

### 8.2 阶段二：广告 measurement 原型

目标：

- 复现 reach/frequency / conversion 的私有估计能力。

建议实现：

- sketch-based cardinality/frequency estimator
- 去标识 measurement key
- campaign-level budget ledger
- 阈值化与最小人群规模

### 8.3 阶段三：高保证版本

目标：

- 验证“对平台也最小信任”的架构。

建议实现：

- TEE 聚合器
- remote attestation
- 可审计查询模板
- 多方安全计算版本的 reach/frequency

## 9. 研究空白与后续问题

以下问题在公开资料中仍不透明，值得继续研究：

- Google Ads on-device conversion measurement 的具体密码学协议是什么。
- `aggregateConversionInfo` 的编码结构、可链接性边界、重放防护与生命周期。
- 产品级系统如何做 privacy budget accounting 与 abuse prevention。
- 在 DP、MPC、TEE 三者之间，Google 在不同 measurement 场景下如何做成本与精度折中。
- 区域合规策略如何映射到底层技术开关。

## 10. 推荐参考文献

### 10.1 直接相关

1. Mayfly: Private Aggregate Insights from Ephemeral Streams of On-Device User Data. Google Research, 2024.
2. Privacy-centric Cross-publisher Reach and Frequency Estimation via Vector of Counts. Google Research, 2021.
3. A System Design for Privacy-Preserving Reach and Frequency Estimation. Google, 2020.
4. Privacy-Preserving Secure Cardinality and Frequency Estimation. Google Research, 2020.
5. About on-device conversion measurement for iOS App campaigns. Google Ads Help.
6. Implement on-device conversion measurement with a standalone SDK. Google Ads Help.
7. Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions. Google Research, 2020.
8. Private Join and Compute from PIR with Default. Google Research, 2021.
9. google/private-membership. Google GitHub repository.

### 10.2 强相关基础设施

1. Confidential Federated Computations. Google Research, 2024.
2. On-Device Algorithms for Public-Private Data with Absolute Privacy. WWW 2019.
3. Private Aggregation of Trajectories. PETS 2022.
4. Prochlo: Strong Privacy for Analytics in the Crowd. SOSP 2017.
5. google/private-join-and-compute. Google GitHub repository.

## 11. 附：一页式设计原则

- 尽量把原始数据留在设备侧。
- 上传的是 measurement artifact，不是明文事实表。
- 所有设备贡献必须有明确上界。
- 没有 DP / 阈值化 / 最小群体规模的 aggregate output 不应出现在报表层。
- 跨参与方 measurement 默认按不互信设计。
- 如果需要高可验证性，优先考虑 TEE + 可审计聚合逻辑。
- 把“产品文档事实”和“研究推断”分开写，避免过度归因。
