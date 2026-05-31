# Web2App 深度研究报告

## 1. 研究范围

本文所说的 `Web2App`，聚焦如下完整链路：

`广告点击 -> Web/H5/中间页 -> App Store / Google Play / OEM 应用市场 -> 安装 -> 首次打开 -> 首次关键行为`

这里的关键不在于“是否一定经过 H5”，而在于是否存在一层可控的 Web 触点，用来承接广告意图、补充说服内容、保存上下文、执行分流路由，并在安装后尽可能把用户带回正确的 App 页面与正确的行为路径。

典型形态包括：

- 品牌落地页 / 活动 H5
- 广告平台内置浏览器中的网页
- Smart Banner / Journeys / Deepview
- Playable / 试用页 / 商品预览页
- 自有站跳应用商店的中间页

## 2. 核心判断

### 2.1 一句话定义

Web2App 不是“多加一个中间页”，而是一套把 `点击意图`、`页面上下文`、`安装归因`、`首开恢复` 串成闭环的移动增长系统。

### 2.2 公开资料下的行业格局

- `Google Ads` 仍是广告平台中原生 Web2App 产品化最完整的一家，已经形成 `Web to App Connect + Web to App Acquisition Measurement` 的双层能力：前者负责 deep link、app conversion tracking、优化建议，后者负责识别 `indirect installs` 与 `Web to app first conv.`。
- `TikTok Ads` 已明确支持“广告先到 web，再测量 app installs / in-app events”。对于内容种草、试玩、预览、利益点教育再安装的链路，TikTok 仍是最值得重点观察的平台之一。
- `Meta / Snap / X` 都可以承接 Web2App，但官方公开叙述更偏广告前台、创意形式、App 安装目标或事件回传；真正完整的 Web 路由、延迟深链、上下文恢复，通常仍要依赖 `Branch / AppsFlyer / Adjust / Singular` 等中台能力补齐。
- 深链与归因平台中，`Branch` 更偏“体验层与页面恢复”，`AppsFlyer` 更偏“web-to-app 增长与归因联动”，`Adjust` 更偏“路由、fallback 与 iOS 恢复稳定性”，`Singular` 更偏“参数转发与多平台优化信号回流”。
- `Firebase Dynamic Links` 已废弃且服务已于 `2025-08-25` 关闭。新项目不应再把它作为主方案，迁移方向应转向 `Universal Links + App Links`，iOS Web 入口可补 `Smart App Banner`。

### 2.3 真正难点不在跳转，而在链路连续性

Web2App 常见断点主要有四段：

- 广告点击到 Web 落地之间
- Web / in-app browser 到应用商店之间
- 应用商店安装到首次打开之间
- 首次打开到首个关键行为 / 归因回传之间

任何一段断裂，都会把链路退化成“有点击、也许有安装，但无法稳定恢复意图，也无法稳定优化投放”。

### 2.4 2026 年的增量变化

结合近期公开文档，Web2App 的行业重点正在从“能不能跳转”转向“能不能在隐私约束下稳定保留上下文”：

- Google Ads 已把 web campaign 带来的 `indirect installs` 和 `Web to app first conv.` 单独产品化，代表广告平台开始承认 Web 到 App 的间接贡献。
- TikTok Ads 已明确支持非 App 推广广告在 Web 落地页之后继续测量 app installs 与 in-app events，但要求每条广告只绑定一个 OS app，跨 iOS / Android 应拆 ad group。
- Snap 在 2025 年推出 `App Power Pack`，把 Playable App Ads、App End Cards、tCPA 等能力打包进 App 增长前台；它更像“广告内轻体验与安装转化增强”，而不是完整 Web2App 中台。
- X Ads 公开资料继续以 App installs、获批 MMP、SKAN/AMM 和 App Conversions measurement 为主；对非 App 目标 campaign，它更强调 app 转化的 halo effect 测量，而不是 Web 中间页闭环。
- Singular、Branch 等平台开始强调桌面 Web 到 App 的 QR code 路径，把 Web2App 从移动网页扩展到桌面网页、PC/Console 增长和跨设备归因。
- App Store 与 Google Play 的商店页也正在成为 Web2App 链路里的可控节点。Apple Custom Product Pages 可为不同广告或受众提供专属商店页，并可配置 deep link；Google Play Custom Store Listings 也支持通过唯一 URL 或 Google Ads campaign 展示定制商店页。它们能提高商店承接一致性，但不能替代首开 deferred deep link。
- Branch 在 2025 年底发布、2026 年更新的 SAN API-Driven Deferred Deep Linking，把 Google、Meta 等自归因网络的新安装 / 重装数据转成 App 首开可消费的 deep link data。这说明 SAN 流量的首开恢复正在被单独产品化，但仍需要 App 路由和业务 session 兜底。
- Adjust 的 ODDL、LinkMe 等能力说明 iOS 侧 deferred deep link 的核心矛盾已经变成“隐私合规 + 首开及时恢复 + 归因不阻塞路由”。
- Apple 的 AdAttributionKit 进一步确认了 iOS 侧的大方向：广告归因会更多依赖隐私阈值、延迟 postback、转化值和已注册广告网络，而不是用户级确定性追踪。Apple Ads 已在 2025 年 4 月 10 日纳入 AdAttributionKit 口径，但这仍是归因层变化，不等同于首开路由能力。
- Firebase Dynamic Links 已在 `2025-08-25` 关闭。历史链接和历史 SDK 不是“待升级项”，而是需要从主链路中移除的风险项。

### 2.5 公开资料校准后的稳定判断

本次补充复核后，可以把行业变化压缩成三个判断：

1. 广告平台正在补“可见性”，但不是都在补“路由”。Google 的 `indirect installs`、TikTok 的非 App 推广广告 app activity measurement、X 的 mobile conversions 与 Snap 的 App Power Pack，核心都是让平台或 MMP 更好看到 web campaign 后续 app 结果；它们并不自动解决安装后进入哪个 App 页面。
2. MMP / deep link 平台正在从“归因 SDK”变成“跨端会话系统”。AppsFlyer、Branch、Adjust、Singular 的共同方向，是把移动 Web、桌面 Web、QR code、CTV、PC/Console campaign、首开恢复和 Conversion API 回流统一到同一套 session / link / event 口径下。
3. iOS 侧应默认接受“体验实时、归因延迟”。AdAttributionKit、SKAN、ATT 和 MMP response 都可能影响报表粒度，但不应影响用户首次打开 App 时的页面恢复。首开路由要有独立的 deep link / session 载荷兜底，不能等待归因归属完成。

因此，2026 年评估 Web2App 方案时，最重要的问题不再是“能不能从 H5 跳到商店”，而是“点击、Web 会话、商店交接、首开恢复、媒体回传是否分别有独立且可观测的状态”。

### 2.6 本轮资料复核后的新增判断

本轮复核更明确地暴露出一个行业分层：广告平台在补“web campaign 带来的 app 结果”，MMP / deep link 平台在补“跨 Web、商店、App 的上下文连续性”。这两层可以协同，但不能互相替代。

- `AppsFlyer OneLink Smart Script` 的公开叙述直接点出了 Web2App 的两跳问题：用户先从广告到 Web，再从 Web 到商店；如果第二跳没有动态生成带归因参数的 outgoing link，安装可能被错误归因或归为 organic。
- `Branch Banners / Journeys / Deepviews` 更强调体验编排：按来源、行为、安装状态展示不同入口，并在未安装时通过 deferred deep linking 把用户送回原网页内容对应的 App 页面。
- `Adjust ODDL` 的产品逻辑说明，行业正在把 deferred deep link 交付从 attribution response 中拆出来，优先保证首开体验，再补齐归因。
- `Singular Links` 的公开文档更强调 tracking link、Universal Links / App Links、`_dl / _ddl / _p` 等参数承载，以及通过 Conversion APIs 把 Web、PC、Console、CTV 等入口的后续 App 事件回流给媒体。

因此，Web2App 不应只按“落地页 + 下载按钮”设计，而应按“三段承载”设计：广告点击负责捕获媒体上下文，Web 会话负责保存业务意图，App 首开负责恢复路由并上报可优化事件。

### 2.7 平台能力的三层分工

本轮资料复核后，行业方案可以更清楚地拆成三层，而不是笼统归为“Web2App 工具”：

| 层级 | 代表能力 | 主要产出 | 典型误读 |
| --- | --- | --- | --- |
| 媒体测量层 | Google `Web to App Acquisition Measurement`、TikTok 非 App 目标 app activity measurement、X App Conversions、Snap App Power Pack | 让 web campaign 后续 app install / in-app event 在媒体或 AAP/MMP 报表里可见 | 误以为媒体能看到 app 结果，就等于能恢复 App 页面 |
| 链接路由层 | Universal Links、App Links、OneLink、Branch Link、Adjust Link、Singular Link、Smart Banner、QR code | 决定已安装直达、未安装商店 fallback、受限浏览器兜底 | 误以为一个静态商店 URL 就是 Web2App |
| 首开上下文层 | Deferred deep link、ODDL / LinkMe、Branch Journeys / Deepviews、Web SDK session、服务端 link_id | 安装后把用户送回内容、商品、活动或 onboarding 分支 | 误把归因响应当成首开路由的前置条件 |

一个成熟方案通常三层都要有：媒体层解决“平台能不能学到信号”，路由层解决“用户能不能到正确入口”，首开上下文层解决“安装后意图是否还在”。如果预算或开发资源有限，优先级应是 `路由层 + 首开上下文层`，再补媒体优化信号；否则容易出现报表变好、体验仍断的假闭环。

### 2.8 近期资料复核后的执行口径

截至 2026-05-24，公开资料没有出现可以替代 `Web session + smart link + App 内路由 + 事件回传` 的单一平台能力。本轮核验中，Google 的 Web to App Acquisition Measurement、TikTok 2025 年底更新的非 App 推广广告 app activity measurement、Branch 2026-03 更新的 SAN API-Driven DDL、AppsFlyer Smart Script V2、Adjust Web-to-app / LinkMe、Firebase Dynamic Links 关闭 FAQ 仍指向同一结论：媒体平台增强 Web 后续 App 结果的可见性，MMP / deep link 平台增强第二跳与首开恢复，Apple / Android / Firebase 则继续定义系统边界和迁移风险。

1. `Google / TikTok / X / Snap / Meta` 应优先按“媒体测量与优化信号”理解。Google 的 `indirect installs` 与 `Web to app first conv.`、TikTok 非 App 推广广告的 app activity measurement、X 非 App campaign 的 App Conversions halo measurement、Snap App Power Pack、Meta CAPI / app event 回传，都能改善平台看到 App 结果的能力；它们不自动生成 Web CTA 第二跳，也不保证安装后进入指定 App 页面。
2. `AppsFlyer / Branch / Adjust / Singular` 应优先按“跨端会话与路由系统”理解。AppsFlyer Smart Script 负责把 `gclid / fbclid / ttclid / twclid / ScCid`、UTM、Web 页面状态和 `deep_link_value` 转成第二跳 OneLink；Branch Journeys / Deepviews / SAN DDL / NativeLink 负责体验编排、SAN 首开数据和 iOS 受限场景补强；Adjust ODDL / LinkMe 负责把 deferred deep link 交付从慢归因响应中拆出；Singular Web-to-App Forwarding / Links 负责 `_dl / _ddl / passthrough`、参数转发和 Conversion API 回流。
3. `Apple AdAttributionKit / SKAN / ATT` 属于归因层，不属于路由层。它们影响报表粒度、延迟、隐私阈值和 re-engagement 归因，但不能替代 Universal Links、App Links、App 内路由解析或首开 session 载荷。App 首开应先消费 deep link、`session_id`、`content_id` 等业务载荷，再等待归因结果补齐媒体归属。
4. `Firebase Dynamic Links` 已是历史断链风险。存量项目要扫描历史广告、邮件、二维码、活动页、社媒入口和短链域名，并重新设计已安装唤起、未安装 fallback、首开恢复和事件回传；只替换短链域名不足以完成迁移。
5. 桌面 Web、QR、CTV、PC / Console 到移动 App 的路径正在进入同一套 acquisition 闭环，但不能照搬移动点击归因。跨设备场景更依赖 QR token、S2S session、曝光窗口、partner 权限和 post-install event 去重。
6. `Apple Custom Product Pages / Google Play Custom Store Listings` 是商店承接层，不是归因或路由层。Apple 文档强调 CPP 可通过专属链接触达并可在 App Store Connect 中配置 deep link；Google Play 文档强调 CSL 可通过唯一 URL 或 Google Ads campaign 呈现。它们解决安装前一致性，首开恢复仍要由 smart link / deferred deep link / App 路由承担。

因此，完整 Web2App 方案至少要分别证明六件事：`媒体能看到结果`、`Web 第二跳能动态带参`、`Universal Links / App Links 真实生效`、`首开恢复不等待归因响应`、`post-install event 可回传且可去重`、`动态参数覆盖有白名单和审计`。任何平台只覆盖其中一两项时，都应作为补强件接入现有架构，而不是被当成端到端闭环。

### 2.9 2026-05-24 复核后的新增执行判断

本轮复核没有改变主结论，但让执行边界更清晰：`Web2App` 不是把 Web 广告“算成”App 安装，而是把 Web 会话、商店承接和 App 首开恢复拆成可验证的工程状态。

- `Google Ads` 的 Web to App Acquisition Measurement 继续强调 `indirect installs` 与 `Web to app first conv.`，并要求导入 first_open / in-app event；这说明 Google 正在补 web campaign 的 app 结果可见性，而不是替广告主托管 H5 CTA 的首开路由。
- `TikTok Ads` 的非 App 推广广告 app activity measurement 仍适合“内容先教育、App 后转化”的路径，但没有 MMP 或 App Events SDK 时只能看到商店流量；跨 iOS / Android 也不应共用同一条广告链路。
- `Meta` 侧公开叙述仍偏 App Promotion、Advantage+ App Campaigns、CAPI 和 app event 优化。MMP 文档显示 App Promotion / Install 可接 direct deep link 与 deferred deep link 字段，但 Meta 流量的首开恢复仍要依赖 MMP link、SAN 数据、AEM / SDK 配置和 App 内路由，不应被理解成 Meta 原生 Web2App 中台。
- `AppsFlyer / Branch / Adjust / Singular` 的差异进一步体现为四类职责：AppsFlyer 强在首跳到第二跳 OneLink 动态生成；Branch 强在 Journeys、Deepviews、SAN DDL 与 NativeLink 等体验恢复；Adjust 强在 ODDL / LinkMe 把路由交付从慢归因中拆出；Singular 强在 Web / PC / Console / CTV 参数转发和 Conversion API 回流。
- `Firebase Dynamic Links` 已经是生产风险，不是技术债清单里的普通升级项。凡是历史广告、二维码、邮件、活动页和社媒入口仍指向 FDL，都应按断链处理并重新验收 fallback、deferred restore 和事件回传。

因此，后续方案评审建议只问三个问题：`第二跳是否动态生成`、`首开是否能独立恢复业务上下文`、`首个关键事件是否能带着媒体与 Web 上下文回传并去重`。如果答案不完整，就不是完整 Web2App，只是“Web 到商店跳转”或“媒体结果补报”。

### 2.10 2026-05-25 增量复核后的边界修正

本次增量复核没有发现能替代现有链路架构的单点产品，但有四个边界需要写进方案评审：

1. `Google / TikTok` 的最新公开文档继续强化“Web campaign 后续 App 结果可见性”。Google 要求导入 `first_open` 与 app 内事件，TikTok 要求接入 MMP、App Events SDK 或 App Events API，并且一条广告只绑定一个 OS app。这类能力能改善媒体学习信号，但不能自动生成第二跳 smart link 或首开业务路由。
2. `Branch SAN API-Driven DDL` 已把 Google、Meta 等 SAN 的新安装 / 重装数据转成 deep link data，但 iOS 侧仍受 ATT 授权与 SAN 数据延迟影响；它是 SAN 首开恢复补强，不是对所有 Web2App 场景的通用替代。
3. `Apple Custom Product Pages` 的 deep link 能力有明确系统边界：CPP 可创建最多 70 个定制商店页，且只有 iOS 18 / iPadOS 18 及以上用户从页面点击 Open 时，配置的 deep link 才能把用户带到 App 内指定内容。因此 CPP 应被当成商店承接与已安装打开增强，而不是安装后 deferred deep link 的替代。
4. `Singular` 的 Web-to-App / PC / Console / CTV 文档进一步说明，跨端增长正在并入同一套 Web acquisition 口径；但这些能力的核心仍是 partner click ID、Conversion API、post-install / in-game event 回传和曝光窗口建模。跨设备场景必须保留 `session_id / QR token / placement_id`，否则无法区分移动 Web 点击、桌面扫码和 CTV 曝光贡献。

因此，当前最稳妥的执行口径是：媒体平台负责让 App 结果回到优化系统，MMP / deep link 平台负责让第二跳和首开载荷不断，商店页负责降低安装前叙事断层，自建业务 session 负责最终去重与路由兜底。

### 2.11 2026-05-26 增量校准：把“可测量”与“可恢复”分开验收

本次复核的新增信息没有推翻前述结论，但进一步确认了一个执行原则：广告平台越强调 Web campaign 后续 App 结果，越要把“媒体可测量”与“用户可恢复”分开验收。

1. `Google Ads` 的 Web to App Acquisition Measurement 明确服务于 web campaign 对 app install / first in-app conversion 的贡献识别，且适用范围集中在 Search、Performance Max、Shopping、Hotel 等 web campaign。它的前提是把 Android / iOS 的 `first_open` 与 app 内动作导入承载 web campaign 的 Google Ads 账号；因此它解决的是报告与优化信号，不是 Web CTA 第二跳生成。
2. `TikTok Ads` 对非 App Promotion campaign 的 app activity measurement 继续采用“Web/Traffic/Conversion 广告先到落地页，再绑定 app event tracking”的口径。公开文档强调必须接入 MMP、App Events SDK 或 App Events API，并且每条广告只能选择一个 Android 或 iOS app；这意味着 TikTok Web2App 放量前应把 OS 拆分、事件源、CTA smart link 和首开路由写入同一份 link spec。
3. `AppsFlyer Smart Script V2` 与 `OneLink Smart Banner V2` 的价值在第二跳：把首跳 URL、广告点击 ID、UTM、页面上下文和 `deep_link_value` 动态转成 outgoing OneLink。它们不能替代 App 侧 Unified Deep Linking 回调处理；如果 App 不消费 `deep_link_value / deep_link_sub*`，页面脚本生成正确链接也只能把用户带到商店或首页。
4. `Branch SAN API-Driven DDL` 的公开文档已把 SAN 流量的 deferred deep linking 独立成首开数据通道，尤其覆盖 Google、Meta 等自归因网络的新安装 / 重装。但它返回的是 SAN API 能提供的广告数据，不等于普通 Branch Link 的完整控制参数；业务上下文仍建议由 Web 侧 `session_id / content_id / link_id` 兜底。
5. `Adjust LinkMe / ODDL` 与 `Singular Web-to-App / Conversion APIs` 代表两类补强方向：前者优先解决 iOS 侧首开恢复及时性，后者优先解决 Web、PC、Console、CTV 到 App 后续事件的媒体回流。二者都不是“单独接入即可闭环”，仍要与 Universal Links / App Links、App 内路由和事件去重一起验收。
6. `Firebase Dynamic Links` 在 2025-08-25 关闭后，官方迁移文档也明确 App Links / Universal Links 不能完整复刻 FDL 的商店分流、deferred deep link、短链和点击分析能力。迁移方案不能只补系统深链文件，还要重建短链域名、fallback、首开恢复和历史入口审计。

落地上，建议把每条 Web2App 链路拆成四张验收表：`media measurement`、`web routing`、`store handoff`、`first-open restore`。媒体后台看到 `indirect install`、`app install` 或 `mobile conversion` 只能证明第一张表部分成立；只有第二跳带参、商店页一致、首开路由命中、首个关键事件回传并去重同时成立，才算完整 Web2App。

### 2.12 2026-05-27 增量校准：端到端能力要按“证据链”验收

本次增量复核继续指向同一判断：行业没有出现可以单独替代 `广告点击 -> Web session -> smart link -> store handoff -> first_open restore -> post-install event` 的平台能力。新增价值主要在于把验收证据链收紧：

1. `Google Ads` 与 `TikTok Ads` 都在强化“Web campaign 后续 App 结果可见”。Google 的 Web to App Acquisition Measurement 关注 indirect installs 与 web-to-app first conversion；TikTok 的非 App Promotion app activity measurement 要求接入 MMP、App Events SDK 或 App Events API，并且每条广告只能绑定一个 Android 或 iOS app。这类能力的验收证据是媒体报表和优化事件，不是用户首开页面。
2. `Branch SAN API-Driven DDL` 说明 SAN 流量的首开恢复正在被产品化，但其输入仍来自 Google、Meta 等 SAN API 可返回的数据。它可以补 SAN 新安装 / 重装的 deferred deep link data，不应替代 Web 侧自有 `session_id / content_id / link_id`。
3. `Apple Custom Product Pages` 的 deep link 是商店承接层增强，而不是安装后恢复层。公开文档显示，CPP deep link 随页面提审，并在 iOS 18 / iPadOS 18 及以上用户从 CPP 点击 Open 时生效；低版本、安装后从桌面图标打开、或用户未从 CPP Open 进入时，仍要依赖 deferred deep link / session response / App 内路由兜底。
4. `AppsFlyer Smart Script / Branch Journeys / Adjust ODDL / Singular Web-to-App` 的共同方向不是“替广告主多放一个按钮”，而是把第二跳、首开恢复和事件回流做成可审计状态。供应商能力再强，也必须落到 App 侧 SDK 回调、业务路由映射和事件去重。

因此，2026 年的 Web2App 方案评审应要求每条链路提交 6 类证据：`首跳参数已捕获`、`第二跳链接动态生成`、`商店页版本可追踪`、`首开路由命中`、`首个关键事件带上下文`、`媒体 / MMP / 内部报表可去重对账`。缺少其中任一项，都只能称为局部 Web-to-store 或 app result measurement，不能称为完整 Web2App 闭环。

### 2.13 2026-05-28 增量校准：不要让“平台可见”掩盖“业务不可恢复”

本次复核没有发现新的端到端替代方案，但进一步确认了一个风险：媒体平台和 MMP 正在让 Web 后续 App 结果更可见，团队容易因此低估 App 首开恢复和内部去重的工程工作量。

1. `Google Ads` 的 Web to App Acquisition Measurement 仍应理解为 web campaign 结果补全。它依赖 `first_open` 和 app 内事件导入，并把 indirect install、web-to-app first conversion 暴露给 Google Ads / AAP；但 Web CTA 链接如何动态带参、用户安装后进哪个 App 页面，仍要由 smart link、deferred deep link 和 App 路由解决。
2. `TikTok Ads` 的非 App Promotion app activity measurement 适合验证“内容落地页是否带来后续 App 行为”，但其约束很硬：每条广告只能绑定一个 Android 或 iOS app，且需要 MMP、App Events SDK 或 App Events API。灰度测试时不应把 iOS / Android、Web conversion 和 app event 放在同一条混合链路里一起判断。
3. `Branch SAN API-Driven DDL` 说明 SAN 流量首开数据正在被补强，但 iOS 侧仍受 ATT opt-in 与 SAN 数据延迟影响，并且返回的是 SAN API 能给出的广告数据。它可以增强 Google / Meta 新安装或重装后的 deep link data，不应替代 Web 侧自有 `session_id / content_id / link_id`。
4. `Apple Custom Product Pages` 的 deep link 应作为已安装打开和商店承接增强，而不是未安装后的首开恢复方案。只有符合系统版本、用户从 CPP 点击 Open、App 路由可解析等条件时，deep link 才能发挥作用；安装完成后从桌面图标首次打开仍需要 deferred restore 兜底。
5. `AppsFlyer / Adjust / Singular` 等供应商能力更像链路零件库：Smart Script / Smart Banner 解决第二跳与 Web 入口，ODDL / LinkMe 解决 iOS 首开恢复及时性，Web-to-App / Conversion APIs 解决事件回流。它们只有和 App SDK 回调、业务路由表、事件去重表一起验收，才构成闭环。

因此，5 月 28 日后的方案评审建议增加一条硬规则：任何 Web2App 链路只要不能在测试设备上复现 `首跳参数 -> 第二跳链接 -> 商店页版本 -> 首开路由 -> 首个关键事件 -> 媒体回传` 的完整证据链，就不应进入跨媒体放量。

### 2.14 2026-05-29 增量校准：把第二跳当成独立产品面验收

本次增量复核没有发现新的端到端替代方案，但更清楚地确认了一个执行重点：Web2App 的关键风险正在从“有没有中间页”转向“中间页上的第二跳是否可控”。公开资料中，Google 与 TikTok 继续强化 web campaign 后续 app install / in-app event 的可见性；AppsFlyer、Branch、Adjust、Singular 则继续把第二跳链接、首开恢复、跨设备事件回流拆成独立能力。

1. `Google Ads` 的 Web to App Acquisition Measurement 仍以 `indirect installs`、`Web to app first conv.` 和 app event 导入为核心，适用 Search、Performance Max、Shopping、Hotel 等 web campaign。它能证明 web campaign 对 App 结果有贡献，但不负责生成落地页 CTA 的 OneLink / Branch Link / Adjust Link / Singular Link。
2. `TikTok Ads` 的非 App Promotion app activity measurement 明确允许 web / traffic / conversion campaign 先到落地页，再测量 app installs 与 in-app events；但仍要求 MMP、App Events SDK 或 App Events API，并且每条广告只绑定一个 Android 或 iOS app。它的验收点是事件源和 OS 拆分，不是首开业务路由。
3. `AppsFlyer OneLink Smart Script V2` 把首跳 URL、click ID、UTM、referrer、页面状态和 `deep_link_value` 转成第二跳 OneLink；这说明 Web CTA 已经是一个需要配置、审计和测试的产品面，而不是前端随手放置的下载按钮。
4. `Branch SAN API-Driven DDL` 可以把 Google、Meta 等 SAN 的新安装 / 重装广告数据转成首开 deep link data，但返回范围受 SAN API 可提供字段约束。业务上下文仍应由 Web 侧 `session_id / content_id / link_id` 独立保存。
5. `Adjust LinkMe / ODDL` 与 `Singular Web-to-App / CTV-to-mobile` 的共同信号是：iOS 恢复及时性、跨设备曝光归因和 post-install event 回流都在被产品化，但它们仍分别属于路由补强、归因补强和优化信号补强，不能互相替代。

因此，5 月 29 日后的文档口径建议收紧为：`Web2App = 第二跳动态生成 + 首开上下文恢复 + 首个关键事件回传`。媒体后台能看到安装只是必要条件；如果 Web CTA 不是动态生成、首开不能恢复业务上下文、事件不能带链路 ID 去重，就不能算完整闭环。

### 2.15 2026-05-30 增量校准：把 Web CTA 纳入投放资产管理

本次公开资料复核继续支持前述判断：近期新增能力主要在补“Web 后续 App 结果可见性”和“受限场景首开恢复”，没有出现能单独覆盖广告点击、Web 会话、商店交接、首开路由与事件回传的端到端平台。因此，5 月 30 日后的执行重点应从“是否有落地页”进一步收紧到“Web CTA 是否像广告素材一样被管理”。

1. `Google Ads` 的 Web to App Acquisition Measurement 与 Web to App Connect 应继续按媒体测量和优化能力使用。它能把 web campaign 带来的 `indirect installs`、`Web to app first conv.` 暴露到 Google Ads / AAP 口径中，但前提仍是导入 `first_open` 和 app 内事件；它不负责保存落地页上的业务上下文。
2. `TikTok Ads` 对非 App Promotion campaign 的 app activity measurement 已明确覆盖“广告到 Web 落地页，再测量 App 安装和应用内事件”的路径。灰度时应把每条广告绑定的 OS app、MMP / App Events SDK / API 事件源、CTA 链接模板和首开路由表放在同一个验收单里，否则很容易把“平台能计数”误判为“用户能恢复”。
3. `AppsFlyer Smart Script / Smart Banner`、`Branch Journeys / Deepviews / SAN DDL`、`Adjust ODDL / LinkMe`、`Singular Web-to-App / Conversion APIs` 的共同价值，是把第二跳、首开恢复和后续事件回流拆成可配置、可观测、可审计的环节。它们不是互斥选项，而是分别补不同断点。
4. `Apple Custom Product Pages`、`Google Play Custom Store Listings`、`Smart App Banner` 等商店或系统入口能力，应被纳入 Web2App 方案，但只负责降低安装前或已安装打开时的叙事断层。安装后首次从桌面图标打开、归因延迟、ATT 未授权、Private Relay、受限内置浏览器等路径，仍需要 deferred deep link 或自建 session response 兜底。
5. `Firebase Dynamic Links` 关闭后的迁移风险仍应作为生产风险处理。迁移不是把短链域名换成 Universal Links / App Links 即可，而是要逐项重建广告入口、二维码、邮件、社媒入口、fallback、首开恢复、点击分析和历史链接归档。

因此，Web CTA 应成为独立投放资产：每个按钮或 banner 都应有 `link_id`、来源白名单、参数映射、商店 fallback、首开路由、事件去重键和回滚策略。若 CTA 只是静态商店链接，即使媒体后台能看到部分安装，也只能算 Web-to-store，不应纳入完整 Web2App 闭环统计。

### 2.16 2026-05-31 增量校准：把链路验收收敛到“可观测状态机”

本次复核没有发现新的端到端替代方案，但进一步确认：Web2App 的成熟度不取决于供应商名单，而取决于链路里每个状态是否可观测、可回滚、可对账。

1. `Google Ads` 的 Web to App Acquisition Measurement 仍是广告平台侧最清晰的 web campaign 后续 App 结果补全能力。它要求导入 `first_open` 与 app 内事件，并把 `indirect installs`、`Web to app first conv.` 暴露给 Google Ads / AAP；这能改善投放学习，但不能替 Web 页面生成第二跳链接，也不能替 App 首开恢复业务上下文。
2. `TikTok Ads` 的非 App Promotion app activity measurement 与 app attribution 配置继续说明，同一条广告只应绑定一个 OS app，且没有 MMP、App Events SDK 或 App Events API 时只能看到商店流量。实操中，TikTok 的 Web2App 灰度应把 `campaign objective`、`OS app`、`CTA smart link`、`first_open`、`首个关键事件` 作为一组配置发布。
3. `Branch SAN API-Driven DDL`、`Adjust ODDL / LinkMe`、`AppsFlyer Smart Script V2`、`Singular Web-to-App / Conversion APIs` 分别补强 SAN 首开数据、iOS 恢复及时性、第二跳动态生成和跨端事件回流。它们的共同边界是：都需要 App 内路由、业务 session 与事件去重承接，不能只靠 SDK 接入自动形成闭环。
4. `Snap App Power Pack`、Playable、App End Card、Meta Advantage+ App Campaigns、X app measurement 等前台能力更适合提升安装意图或回传可见性，不应被包装成 Web 中间页中台。若广告先落 Web，第二跳仍必须由 smart link 或自建路由承载点击参数和业务意图。
5. `Firebase Dynamic Links` 关闭后的风险已经进入历史入口治理阶段。任何仍散落在广告、邮件、短信、二维码、社媒 profile、活动页、客服脚本里的 FDL，都应视为断链入口；治理清单要记录替代 URL、fallback、首开恢复策略和旧链接归档，而不是只替换 SDK。

因此，后续评审建议把 Web2App 抽象成 6 个状态：`ad_click_captured`、`web_session_bound`、`cta_link_generated`、`store_handoff_tracked`、`first_open_restored`、`post_install_event_deduped`。每个状态都要有日志、失败原因和 owner；缺少任一状态，链路就只能算局部 Web-to-store 或 app result measurement。

## 3. 标准链路与职责拆解

```mermaid
flowchart LR
    A["Ad Click"] --> B["Web / H5 / Interstitial / In-app Browser"]
    B --> C["App Store / Google Play / OEM Store"]
    C --> D["Install + First Open"]
    D --> E["Deferred Deep Link / Context Restore"]
    E --> F["First Key Event"]
```

Web 页在这条链路里通常承担 5 个职责：

1. 承接广告意图，避免点击后直接跳商店造成信息断层。
2. 完成二次说服，补充玩法、权益、社会证明或价格信息。
3. 判断用户状态，区分“已安装”“未安装”“环境受限”三类路径。
4. 保存 campaign、creative、内容 ID、UTM、gclid、ttclid、fbclid 等上下文。
5. 在首开后把这些上下文恢复为正确页面、正确推荐位、正确首个事件。

因此，Web2App 真正优化的是 `点击 -> 首次关键行为`，而不是单独优化 `点击 -> 商店`。

### 3.1 四类常见落地架构

业界 Web2App 方案大体可以归为四类，区别不在页面长短，而在谁负责保存上下文、谁负责路由、谁负责把事件回传给媒体：

| 架构 | 典型路径 | 适用场景 | 主要风险 |
| --- | --- | --- | --- |
| 媒体直达商店 | ad click -> store -> install | 低解释成本、安装意图强的 App Install campaign | Web 意图缺失，安装后通常难恢复具体内容 |
| Web 承接后跳商店 | ad click -> H5 -> store -> first_open | 商品、内容、订阅、游戏试玩等需要二次说服的场景 | H5 若不接 MMP / deep link，只会增加流失 |
| Smart link / Smart banner | ad or owned traffic -> web -> smart link -> app/store | 自有站、SEO、CRM、内容页转 App | 需要 Web SDK、App SDK、Universal Links / App Links 协同 |
| 桌面 Web 到移动 App | desktop web -> QR code -> mobile store/app -> first_open | PC 决策、移动履约，如旅游、票务、金融、游戏、Console/PC 增长 | 跨设备归因弱，需要 QR link、session 和事件口径单独设计 |
| CTV / OTT 到移动 App | CTV ad -> QR / short link -> mobile store/app -> first_open | 大屏曝光、移动安装，如游戏、流媒体、订阅、品牌效果合一 | 无点击或弱点击环境下归因更依赖 MMP、QR token、时间窗口和聚合口径 |

成熟团队通常不会只选一种架构，而是按流量来源组合使用：买量链路优先保证媒体点击和事件回传，自有站链路优先保证首开恢复，桌面链路优先保证 QR 扫码后的跨设备上下文。

### 3.2 端到端状态机

真正上线时，Web2App 应被设计成状态机，而不是一个按钮：

1. `ad_click_captured`：媒体或 MMP 先捕获点击，保留 click id、UTM、creative、placement。
2. `web_context_created`：Web 页生成一次会话上下文，绑定内容、落地页版本、实验组和 CTA。
3. `route_decided`：根据 OS、浏览器、是否可能已安装、是否在 in-app browser 中决定直达 App、商店、Deepview、Smart Banner 或 QR。
4. `store_handoff`：进入 App Store / Google Play / OEM 市场前，把必要参数写入 MMP link、install referrer 或 deferred deep link 载荷。
5. `first_open_restored`：App 首开时先恢复页面和 onboarding 分支，再等待归因响应补齐媒体来源。
6. `first_key_event_reported`：首个关键事件同时带上业务上下文和媒体上下文，用于投放优化和内部复盘。

这个状态机的价值是把“体验路由”和“归因报表”拆开：用户首开不能等 SKAN、AdAttributionKit 或 MMP 慢响应；但投放优化必须在后续事件里拿到足够完整的来源和内容字段。

## 4. 基础设施要求

### 4.1 Universal Links / App Links

- `iOS Universal Links` 允许同一 HTTPS 链接在已安装时优先唤起 App，未安装时自然回落到网页。
- `Android App Links` 通过域名校验提升直达稳定性，减少弹窗和路径丢失。

它们决定的是“已安装用户能否无损回 App”。没有这层基建，Web2App 很容易退化成简单跳商店。

落地时要把它们当成域名基础设施，而不是单个活动页配置：

- iOS 需要维护 `apple-app-site-association`、Associated Domains、App 内路由解析和 Universal Link fallback。
- Android 需要维护 `assetlinks.json`、intent filters、包名 / SHA-256 证书指纹和 Play 商店 fallback。
- Web 中间页、MMP 链接域名、品牌域名和广告跳转域名要提前规划，否则容易出现“广告域能跳、品牌域不能唤起”或“短链能归因、长链不能恢复”的割裂。

### 4.2 Deferred Deep Linking

Deferred deep linking 解决的是：

`点击时未安装 -> 去商店安装 -> 首次打开后仍回到原内容 / 原活动 / 原 onboarding`

如果安装后只能回首页，广告和 Web 页里传递过来的意图基本已经丢失，首转效率通常会明显下降。

### 4.3 Fallback 与分流逻辑

成熟方案不是单一路径，而是一套分流策略：

- 已安装：优先直达 App 对应页
- 未安装且意图强：直送商店
- 未安装但还需说服：继续留在 Web
- 环境受限：回退到专门中间页或移动网页

尤其在 `Facebook/Instagram in-app browser`、Safari、部分系统弹窗策略和社交流量容器里，fallback 设计直接决定损耗高低。

需要特别注意的是，in-app browser 不只是一个展示容器，还会改变归因上下文。用户从 Facebook、Instagram、TikTok 等内置浏览器切到系统浏览器、再到商店和 App 时，浏览器标识、cookie、点击 ID 和设备侧信号都可能断裂。因此广告点击链接最好先被媒体或 MMP 捕获，再跳到品牌 Web 页；Web 页上的 CTA 再通过带参数的 smart link / deep link 进入商店或 App。

### 4.4 测量与事件回传

- Android 侧底座通常是 `Install Referrer + first_open + post-install events`
- iOS 侧底座通常是 `first_open + deep link restore + AdAttributionKit / SKAN`

如果 `first_open`、`registration`、`purchase` 等关键事件不能稳定回传给广告平台或 MMP，平台后续优化能力会迅速变弱。

测量设计上要区分三类事件：

- `路由事件`：点击、banner 展示、CTA、商店跳转、deep link 打开，用来诊断链路损耗。
- `归因事件`：install、first_open、re-engagement，用来判定媒体贡献。
- `业务事件`：注册、订阅、下单、首局、首购，用来喂给广告平台优化模型。

三类事件不能混在一个指标里看。只看安装会高估中间页价值，只看首购又会低估 Web 页对教育和筛选的贡献。

### 4.5 隐私归因与首开恢复要解耦

Web2App 容易把两个目标混在一起：一个是“把用户带到正确 App 页面”，另一个是“把安装和后续事件归因给正确来源”。在 2026 年的 iOS 环境下，这两件事必须分开设计。

- 路由层要尽量实时：用户首次打开 App 时，应立即基于 deep link、deferred deep link、剪贴板授权方案、session response 或本地缓存恢复页面。
- 归因层可以延迟：SKAN / AdAttributionKit postback、MMP 归因响应、媒体回传都可能滞后，不能成为首开路由的阻塞条件。
- 报表层要允许概率与聚合：iOS 侧出现 `null`、粗粒度转化值、延迟回传或隐私阈值不足，并不等于链路失败；它只说明该口径不能用于用户级复盘。

还要区分 `App AdAttributionKit` 和 `Web AdAttributionKit`：前者偏 App 安装与 re-engagement 归因，后者偏 App 内广告点击到网站后的 Web 转化测量。它们能提升隐私合规测量能力，但不会自动把安装后的用户送回商品页、内容页或 onboarding 分支。

AAK 的 re-engagement URL 也应按路由基建看待，而不是按归因字段看待。公开文档要求该 URL 是广告 App 已注册的 Universal Link；如果 Universal Link 配置、域名关联或 App 内路由解析不成立，归因框架无法替你恢复内容上下文。对 Web2App 来说，这再次说明 `Universal Links / App Links` 是底座，不是可选优化项。

因此更稳妥的架构是：`首开路由优先保证体验`，`归因回传随后补齐优化信号`。Adjust ODDL、LinkMe 这类能力，本质上也是在解决“不要等归因完成才交付 deferred deep link”的问题。

### 4.6 商店页连续性：CPP / CSL 是承接层，不是路由层

Web2App 不应把应用商店视为不可控黑盒。iOS 侧的 `Custom Product Pages`、Android 侧的 `Google Play Custom Store Listings`，都可以让不同广告、内容、地区或受众进入更匹配的商店页，减少从 H5 到商店之间的叙事断裂。

但商店页定制解决的是“安装前说服一致性”，不是“安装后上下文恢复”。落地时应把它放在链路中间层：

- Web CTA 根据 OS、campaign、content_id 选择对应 CPP / CSL URL，而不是所有流量共用默认商店页。
- CPP / CSL 的素材、文案和 Web 落地页承诺保持一致，避免用户到商店后看到完全不同的价值主张。
- 商店页 ID 要写入 `link_id / landing_variant / store_variant`，用于后续分析商店承接效率。
- 安装后仍要依赖 deferred deep link、session response 或 App 内路由恢复内容；不能因为用了 CPP / CSL 就省略首开载荷。
- Apple CPP 侧要额外注意 deep link 的系统门槛：公开文档显示，CPP 可创建最多 70 个页面，页面有唯一 URL；deep link 需要随 CPP 提审，并且只在 iOS 18 / iPadOS 18 及以上用户从 CPP 点击 Open 时生效。低版本、首次安装后的恢复和非 App Store Open 场景，仍要回到 smart link / deferred deep link 方案。

因此，2026 年更完整的链路应从 `Web -> Store -> App` 改成 `Web -> 定制商店页 -> 首开恢复`。前者优化安装前转化，后者保证安装后意图不丢。

## 5. 广告平台能力梳理

### 5.1 Google Ads：原生产品化最完整

Google Ads 已将 Web2App 明确产品化为 `Web to App Connect`，并配套 `Web to App Acquisition Measurement`。

从官方资料看，其能力闭环最完整的点在于：

- 在 Google Ads 内集中配置 deep linking、app conversion tracking、优化建议
- 支持 Search、Performance Max、Shopping、Hotel 等 web campaign 的 Web2App 优化
- 覆盖库存包括 Search、Shopping、Travel、Discover，以及部分 AdMob 覆盖；这意味着它并非只服务搜索广告，而是覆盖 Google 多类 web campaign 入口
- 可识别 `indirect installs`
- 可单列 `Web to app first conv.`
- 官方明确支持通过 Firebase、第三方 AAP/MMP、Google Play 导入 app 首开和 app 内事件
- `indirect installs` 至少要求把 Android / iOS 的 `first_open` 导入承载 web campaign 的 Google Ads 账号；`Web to app first conv.` 还要求导入 app 内动作，并至少将一个 app 内事件设为 primary action 参与出价
- Google 的公开口径强调“web campaign 先进入网页，再产生 app 安装 / 首个 app 内转化”这一间接路径；若广告直接跳 App Store / Google Play，则不属于该测量能力覆盖范围

另一个容易混淆的能力是 Google Ads 的 deferred deep linking。它面向“用户点击 App campaign、安装后进入指定 App 内页”的体验恢复，而不是 Web 中间页的通用上下文恢复。公开文档还给出明确限制：ad group deferred deep link 主要用于 Android 的 YouTube / AdMob 场景；要求 App 已实现 custom scheme 或 Android App Links，并在测量 SDK 中启用 deferred deep linking；用户需在一定窗口内安装并打开 App 才能恢复到指定深链。

同时，Google 也给出了很明确的边界：

- 该测量能力适用于“广告先到 web，再带来 app 安装”的路径
- 如果 web campaign 直接把人送到 App Store / Google Play，则不在这套测量范围内
- iOS 侧可见性仍受 ATT 同意和隐私框架约束，Google 公开口径也仅覆盖 ATT consented iOS 流量
- Google 表示同一次转化不会同时归给 App campaign 和 web campaign；但这只解决 Google / AAP 侧的重复上报，不替代企业内部对 web conversion、install、first_open、首个关键事件的去重规则
- 这套能力解决的是 web campaign 对 app install / first in-app conversion 的可见性，不替代 Universal Links、App Links 或 MMP deferred deep link 的路由职责
- Google DDL 解决的是 App campaign 安装后落到哪个 App 内页，Web to App Acquisition Measurement 解决的是 web campaign 贡献 app 结果的可见性；两者都不应被当成“任意 H5 CTA 自动恢复首开上下文”的完整方案

结论上，Google Ads 最适合高意图搜索、商品/服务决策需要先读信息的行业，以及已经完成 App 事件埋点与 deep link 基建的团队。

### 5.2 Meta：广告前台强，闭环通常要外补

Meta 没有像 Google 一样单独推出完整的 Web2App 总产品名，但具备多个关键组件：

- Facebook / Instagram 打开外链时通常会先进入 `in-app browser`
- `Playable Ads` 支持先试玩再安装
- `Conversions API` 支持更稳定回传 website、app、CRM、offline 等事件

这使 Meta 很适合承担：

- 创意前置预览
- 内容教育后再安装
- Web 行为与 App 行为的多源信号回传

但从公开资料看，Meta 对“web landing -> install -> first app event”并没有像 Google 那样做成原生一体化测量产品。实操里更常见的组合仍是：

- Meta 负责流量与创意
- 自建 Web 落地页负责承接与筛选
- MMP / deep link 平台负责参数继承、延迟深链、归因回流

近期 MMP 公开资料也进一步说明了 Meta 链路的边界：

- 付费 App install / re-engagement 场景可配置 direct deep link，但 deferred deep link 常依赖 MMP、Meta SDK、AEM / SAN 数据或广告目标限制，不是所有 Meta 入口都天然支持。
- AppsFlyer 的 Meta 集成文档显示，App Promotion / Install 目标下 direct deep link 与 deferred deep link 均可支持，常见做法是在广告层级的 Destination 中填写 DDL URL；这证明 Meta 可以承接深链字段，但字段能否在首开稳定变成 App 内页面，仍取决于 MMP、SDK 初始化和 App 路由解析。
- Branch 的 Facebook Ads DDL 文档则给出另一个边界：Facebook deferred deep linking 常需要 Branch Ad Link 和 passive deep view，而不是像部分 SAN 那样完全由 Branch 从 partner API 直接取回普通 Branch Link 数据。因此，Meta Web2App 更应按“广告配置 + MMP 接力 + App 路由”验收。
- iOS 侧受 ATT、AEM 和 in-app browser 影响更明显。部分 MMP 文档会要求在 Meta 归因优先、AEM payload 存在或用户未授权时调整 deep link 处理逻辑。
- Facebook App Links 更像 Meta 生态内的网页元数据标准，不等同于 iOS Universal Links / Android App Links，也不能替代跨媒体的 delayed / deferred context restore。

因此 Meta 链路的关键不是把所有用户尽快送商店，而是先明确 Web 页承担的角色：如果是游戏、工具、订阅或电商，Playable、内容预览、权益解释和社证信息通常能提高安装前意图；如果只是低信息量 H5，则很容易在 in-app browser 里增加一次无效跳转。

### 5.3 TikTok Ads：内容种草型 Web2App 的关键平台

TikTok 的公开资料对 Web2App 已经相当明确，核心体现在三层：

- `App Promotion`：直接做 app install / app event 优化
- `Non-app promotion campaigns + App activity measurement`：即使广告先到 web landing page，也可继续测量 app installs 与 in-app events
- `Deeplinks / Deferred Deeplinks`：覆盖已安装直达与未安装后的安装后恢复

TikTok 还明确给出实操限制：

- 一个广告仅能选择一个 app，即 Android 或 iOS 二选一
- 如混投双系统，部分数据可能丢失
- 建议拆分 iOS / Android ad group
- 若不接第三方 MMP 或 TikTok App Events SDK，TikTok Ads Manager 通常只能测到进入商店的流量，不能稳定把 install / in-app event 作为优化结果回传
- 公开帮助文档在 2025 年底仍沿用这一口径，说明 TikTok 的 Web2App 测量重点是“非 App 目标广告也可挂接 app event tracking”，而不是自动接管 Web CTA、商店 fallback 或安装后页面恢复

这意味着 TikTok 很适合“先种草、再转安装”的链路，但也要求更严格的 OS 拆分和测量配置。

### 5.4 Snapchat：更偏 App 增长前台

Snap 当前公开能力重心仍偏 App 增长前台，而非完整 Web2App 闭环中台：

- `App Power Pack` 强调新的 app 下载广告能力、交付与测量提升，公开材料称可用于 SKAN 与 Non-SKAN campaign
- `Playable App Ads` 等互动格式更适合“先试后装”的游戏和工具类 App，尤其适合把试玩、预览和安装意图筛选前置到广告内，而不是放到外部 H5
- `Sponsored Snaps`、App End Cards、tCPA 等能力更偏向提高 App 安装广告的触达、点击、预览质量和成本控制
- Snap 公开材料也持续强调 Pixel、MMP 集成和 attribution/measurement

这类能力适合做：

- 增量流量入口
- 更高沉浸感的 app 安装创意
- 与 MMP 结合的 App 增长投放
- 游戏、工具、娱乐类 App 的“广告内轻体验 -> 商店安装”路径

但从公开资料的完整度判断，Snap 在 Web 落地、参数继承、上下文恢复、延迟深链上，仍更像需要外部平台配套，而非原生自带完整闭环。

### 5.5 X Ads：以 App Install 为主，原生 Web2App 叙述较弱

X Business 公开资料仍以 `App installs campaign` 为主，强调：

- 从 X 平滑引导到应用商店
- 与获批 `MMP`、`SKAdNetwork`、`Advanced Mobile Measurement` 配合
- 优化目标仍以 app click / app install / app purchase optimization 为中心
- 官方移动 App 测量主要依赖获批 MMP，并要求通过 MMP 把安装、重开和 app event 回传到 X Ads
- 对非 App 目标广告，X 也提供 App Conversions measurement，用于观察品牌或触达类 campaign 带来的 app install / in-app conversion “halo effect”

因此更现实的判断是：

- X 可以承担流量触达与 App 安装目标
- X 的 Web2App 价值更偏“媒体触达后对 App 转化的补充测量”，而不是完整 Web 中间页产品
- 如果要跑严格意义的 Web2App，Web 中间页、参数继承、深链恢复与归因转发仍应由第三方能力承担

### 5.6 广告平台选择口径

从投放决策看，不应按“哪个平台能不能跳 App Store”来选 Web2App 方案，而应按链路角色选：

| 目标 | 更适合的平台 | 关键前提 |
| --- | --- | --- |
| 高意图搜索或商品决策后安装 | Google Ads | 已导入 app first_open / in-app event，并完成 deep link 基建 |
| 内容种草、试玩、预览后安装 | TikTok / Meta / Snap | Web 页有真实承接价值，且 iOS / Android 分组清晰 |
| 自有站、SEO、CRM、桌面 Web 转 App | Branch / AppsFlyer / Singular 等中台承接 | Web SDK、App SDK、smart link、QR code 和事件回传统一 |
| 以 App 安装为主、Web 只是补充解释 | X / Snap / Meta App Ads | 不把 Web 页当归因主链路，关键事件仍回传 MMP 或媒体 |

一句话：广告平台决定流量和优化目标，MMP / deep link 平台决定上下文能否跨 Web、商店和 App 继续传递。

补充判断：广告平台的 Web2App 能力越强，越要注意它解决的是“媒体可见性”还是“用户路由”。Google 的 `indirect installs`、TikTok 的非 App 目标 app activity measurement、X 的 App Conversions measurement 都能提升 web campaign 对 app 结果的可见性，但它们并不自动生成安装后页面恢复能力。页面恢复仍要由 App 路由、MMP deferred deep link 或自建 session 方案完成。

### 5.7 媒体能力边界：不要把测量产品当路由产品

公开资料里最容易被误读的一点，是把广告平台的 “web campaign 能看到 app 结果” 理解成 “web landing 能自动恢复 app 上下文”。两者不是同一层能力：

| 能力 | 解决的问题 | 不能替代 |
| --- | --- | --- |
| Google `indirect installs` / `Web to app first conv.` | Web campaign 对 app install 和首个 app conversion 的可见性 | App 首开路由、内容 ID 恢复、Universal Links / App Links |
| TikTok 非 App 推广广告的 app activity measurement | Web / traffic / conversion campaign 后续 app install 与 app event 的测量 | iOS / Android 分组、deferred deep link 载荷设计 |
| X App Conversions measurement | 非 App campaign 对 app 转化的补充观察 | Web 中间页参数继承、商店后首开恢复 |
| Snap App Power Pack / Playable App Ads | 广告内互动、试玩和安装意图筛选 | Web SDK、MMP link、安装后上下文恢复 |
| Meta CAPI / app event 回传 | 更稳定地把 website、app、CRM、offline 事件回传给 Meta | 跨商店安装后的页面恢复与深链分流 |

近期资料还强化了一个执行细节：媒体能否“看见 App 结果”通常依赖 MMP / SDK / API 事件接入，而不是广告落地页本身。TikTok 明确没有 MMP 或 App Events SDK 时只能测到商店流量；X 要求配置获批 MMP 后才能把 install、re-open 和 in-app event 送回 X Ads；Meta 的 CAPI 能接收 website、app、offline、CRM 等事件，但它服务的是优化与测量连接，不负责把安装后的用户送回具体 App 页面。

因此，做方案时应把媒体能力拆成三张表验收：

1. `流量表`：广告点击是否被媒体或 MMP 先捕获，click id、placement、creative 是否进入落地页。
2. `路由表`：已安装、未安装、受限浏览器、桌面 QR 等路径是否分别有目标页和 fallback。
3. `回传表`：first_open、首个关键事件、业务转化是否能按媒体要求回传，并与 Web 事件去重。

只完成第三张表，最多说明媒体报表更完整；只有三张表同时成立，才是可运营的 Web2App。

### 5.8 其他广告网络：多数是 App Install / Web Conversion 分离，Web2App 需外部中台串联

除 Google、TikTok、Meta、Snap、X 之外，Reddit、Quora、LinkedIn 等平台也能承接 App 增长或 Web 转化，但公开产品形态通常更接近两条分离链路：

- `App Install / App Promotion`：平台负责安装目标、移动端定向和 MMP 回传。
- `Website Traffic / Website Conversion`：平台负责落地页访问、站内转化和网页事件回传。

这类平台的共同特点是：它们可以把用户送到 Web，也可以优化 App 安装，但很少把 `web landing -> store -> first_open -> restored app context` 做成原生闭环。因此，实操时应默认采用外部中台串联：

1. 广告点击先进入媒体或 MMP tracking link，保留 click id、campaign、creative、placement。
2. Web 页只承接必要的内容解释和 CTA，不把归因参数藏在浏览器 cookie 里。
3. CTA 使用 OneLink、Branch Link、Adjust Link、Singular Link 或自建 smart link，负责 OS 分流、已安装唤起、未安装商店 fallback；如果是广告到 Web 再到商店的两跳链路，第二跳链接必须从首跳参数动态生成，不能只放一个静态商店 URL。
4. first_open 和首个关键事件通过 MMP 或 Conversion API 回传给对应媒体，而不是只看 Web conversion。

近期公开资料里，`Reddit` 的 App Install objective 明确依赖 MMP 与 SKAN 来归因 install / in-app actions，并在报表里区分 MMP reporting 与 SKAN reporting。`Quora` 的 App Install campaign 则要求先接入 MMP，并在 iOS 链路中区分 App Store URL 与第三方点击 tracker；同时建议 Android / iOS 分 ad set。这类规则说明，长尾网络的关键不是“是否能买 app install”，而是投放结构、MMP 链接、SKAN 限制和 post-install 事件映射是否提前设计。

对这类网络的评估口径不应是“能不能投 App”，而是“是否有稳定 MMP 集成、是否支持 iOS / Android 拆分、是否能把 post-install 事件回传为优化信号”。如果这些条件不成立，Web2App 更适合作为自有数据复盘链路，而不适合作为平台自动优化主链路。

## 6. 深链 / MMP / 归因平台能力梳理

### 6.1 AppsFlyer：最典型的 web-to-app 增长底座

AppsFlyer 在 Web2App 上的产品定义非常标准：

- `Smart Banners`
- `OneLink`
- `OneLink Smart Script`
- `Deferred deep linking`

结合近期文档更新，AppsFlyer 的公开重点包括：

- Smart Banners 面向 `mobile web-to-app`
- 支持 click-through、view-through、impression 统计
- 支持包括 SRN 在内的 web campaign 到 app 归因
- Smart Banner Web SDK v1 已废弃，现网应使用 `v2`
- Smart Banners 由 OneLink 驱动，可在已安装时 deep link，未安装时送对应商店
- OneLink Smart Script 面向广告或自然流量先到移动 Web、再从 Web 到商店的场景，核心作用是用首跳 URL 参数动态生成第二跳 OneLink，避免 app install 被错误归因或归为 organic
- AppsFlyer 2026 年的链接结构文档进一步明确：需要跨平台、deep link、Android App Links 或 iOS Universal Links 时应使用 OneLink；单平台场景可用 single-platform link。无论哪种，incoming engagement traffic 都应使用 HTTPS，并至少明确 media source、campaign、site ID / sub site ID 等归因字段
- Smart Script V2 的落地重点不是“页面上有脚本”，而是参数映射是否完整：`mediaSource`、`campaign` 等字段要有 incoming key、default value 与 override 规则；多页落地时要确认参数能跨页面保留；需要内容恢复时，应把商品、活动或内容 ID 写入 `deep_link_value` 或等价字段
- Smart Script V2 已公开支持常见 click ID 透传：`gclid`、`fbclid`、`ttclid`、`twclid`、`ScCid` 等字段可以从首跳进入第二跳 OneLink；这让 Web2App 的第二跳不再只是 UTM 继承，而是媒体点击 ID、Web 内容状态和 App 首开载荷的合并点
- 如果要分析网页来源，Smart Script V2 可把 `document.referrer` 映射到 `af_channel` 或 `af_sub1-5` 等字段；如果要把 Web 页面状态带到首开，可从 local storage 读取值并写入 outgoing OneLink 参数
- Smart Banner V2 的公开文档把 Web SDK、PBA snippet、Advanced SDK Verification 和 iOS 26 / Safari storage mode 放在同一集成路径下，说明 Web2App 前端入口也要验收 SDK 加载安全、浏览器存储策略和 cookie consent，而不只是看 banner 是否展示
- AppsFlyer 的 Unified Deep Linking 口径也说明，安装后恢复依赖 SDK 回调拿到 OneLink 参数；因此 Smart Script 只是生成第二跳链接，App 侧仍要处理 `deep_link_value`、`deep_link_sub*` 和业务路由，不应把网页脚本接入等同于首开恢复完成
- 因此，Web2App 的第二跳不要写成静态商店 URL。更稳妥的做法是从首跳 URL 中抽取 `pid`、`c`、`af_siteid`、UTM 或点击 ID，再动态生成 OneLink / attribution link，把媒体上下文带到安装和首开

它最适合拥有大量自有站、SEO、内容页、CRM 回流流量的团队，把 owned media 也纳入 App 增长漏斗。

### 6.2 Branch：体验层与上下文恢复最强

Branch 的 `Journeys + Deepviews + deep linking` 组合，本质上是在解决“先看内容、再装 App、安装后仍回内容”的体验问题。

公开资料里的核心特点是：

- 用 Journeys 把移动网站变成 App 安装入口
- 用 Deepviews 在未安装时提供移动 Web 预览页
- 支持 direct / deferred deep linking
- 支持基于 Web 行为做智能触达，如来源、回访次数、内容偏好
- 支持桌面 Web 通过 QR code 引导到移动 App，适合内容、电商、票务和旅游等桌面决策、移动履约的场景
- 支持把桌面站 banner、二维码、移动站 smart banner 与同一套 Branch Link / SDK 口径连接起来，减少“桌面上看、手机上装、App 里无法复盘”的断点

Branch 近期资料还把 SAN deferred deep linking 单独产品化，说明 Google、Meta 等自归因网络的 deferred deep link 数据需要通过专门 API / MMP 口径进入 App 首开回调，而不是天然包含在普通 Branch Link 中。该能力对新安装 / 重装更有价值，但 iOS 侧仍可能受 ATT 授权、SAN 数据延迟和归因窗口影响。因此，Branch 在 SAN 流量上的价值不是“绕开隐私限制”，而是在合规前提下把广告网络数据尽量转成 App 可消费的 deep link data。

需要特别注意的是，SAN API-Driven DDL 当前公开支持重点是 Google 与 Meta，面向新安装 / 重装时把 SAN 广告数据作为 deep link data 返回。它返回的是 SAN 能给回的数据，不会天然带上普通 Branch Link 的 `$ios_url`、`$android_deeplink_path`、`~campaign`、`~channel` 等控制或归因字段。只要链路里没有 Branch Link，落地页侧仍要用自有 `link_id / content_id / session_id` 保存业务上下文，避免首开只能依赖 SAN 返回结果。

Branch 的 `NativeLink` 则是另一类 iOS 侧补偿方案：它不依赖 IP 地址做 deferred deep linking，而是利用用户可选择的复制 / 粘贴机制在首次打开时恢复深链内容。这个能力适合受 Private Relay、跨浏览器跳转或 iOS 归因延迟影响较大的场景，但要把剪贴板权限提示、用户拒绝、系统版本差异纳入测试矩阵，不能把它当成静默且 100% 覆盖的路由通道。

Branch 特别适合内容、社区、电商、OTA、票务等对上下文恢复要求高的业务。

### 6.3 Adjust：路由、fallback 与 iOS 恢复能力强

Adjust 过去更偏归因底座，现在公开能力里也已补上了 Web2App 体验组件：

- `Deep links`
- `Deferred deep links`
- `LinkMe`
- `ODDL`
- `Smart Banners`

其中比较关键的点是：

- `LinkMe` 明确面向 `iOS 15+ Safari` 的 deferred deep linking 与 attribution reporting
- `ODDL` 强调把 deferred deep link 从归因响应中解耦，优先通过更快的 session response 交付首开路由；但该能力仍属于 Early Access，且公开文档提到最近点击窗口等限制，应按灰度能力评估
- ODDL 默认使用最近一次符合条件的 Adjust link engagement 来决定首开路由，公开文档提到 15 分钟窗口；SAN deferred deep link 不会因为 ODDL 自动加速，因为 SAN 归因来自独立 API / pipeline
- Smart Banners 允许从移动网页统一承接“已安装直达 / 未安装去商店”

因此，Adjust 更适合重视稳定性、fallback 与 iOS 恢复成功率的团队。

落地时要把 Adjust 这类能力当作“首开恢复加速层”，而不是归因准确性的唯一来源。尤其在 iOS 场景下，LinkMe、ODDL、概率匹配、SKAN / AdAttributionKit 分别服务不同目标：前两者偏体验恢复，后两者偏归因和聚合测量，不能混成一个验收指标。

### 6.4 Singular：参数转发与平台优化信号回流强

Singular 的典型优势不是前端交互组件，而是把 Web 参数保留下来，并继续输送给归因和媒体优化层。

公开方案中最关键的是：

- `Web SDK` 识别 UTM / Web campaign 参数
- 点击网页 CTA 后，自动把参数追加到 Singular Link，典型做法是把 web 参数打包进 `_web_params`
- Singular Web-to-App Forwarding 要求移动 App 已集成 Singular SDK、移动网站接入 Web SDK，且使用 Web-to-App baselink；公开文档要求 Web SDK 版本至少为 `1.0.8`
- 参数捕获优先级上，Singular 会优先使用 `wp_` 前缀的 Singular WP 参数，其次使用标准 UTM；常见映射包括 `utm_source -> Source`、`utm_campaign -> Campaign Name`、`utm_content -> Creative Name`
- Singular Links 支持标准 deep link、deferred deep link 和 passthrough 参数，常见字段包括 `_dl`、`_ddl`、`_p`，用于区分 App 内目标页、安装后目标页和业务上下文
- Web SDK 可通过 `openApp()` 直接跳转，也可用 `buildWebToAppLink()` 先生成链接再绑定到按钮或 QR code
- 通过 `Conversion APIs` 把安装和 post-install 事件继续回传给广告平台
- 支持移动 Web CTA 和桌面 Web QR code 两类 Web2App 路径
- Singular Links 允许在点击时动态覆盖 `_dl`、`_ddl`、fallback、iOS / Android redirect 等参数，也支持用 `_forward_params=1/2` 控制参数转发到商店、Web fallback 或 deep link 目标；这对多落地页复用同一 baselink 很有价值，但必须配置短链参数锁定和覆盖白名单，避免投放侧误改最终路由
- 支持把 Web、PC、Console、CTV campaign 的 install 与 post-install / in-game events 通过 partner Conversion APIs 回流给媒体，用于 web campaign 优化；但部分 web / PC / console / CTV postback 能力面向特定客户开放，选型时要确认账号权限
- Conversion Postbacks for Web / PC / Console 可把非移动端事件通过 partner cAPI 或其他 S2S endpoint 回传，用于媒体优化、内部同步或下游系统触发；但这属于优化信号层，不自动解决 App 首开页面恢复
- CTV-to-mobile attribution 更适合被看作“曝光到移动安装”的测量补强，常见前提是 partner 支持、曝光窗口、设备匹配和移动端 install / event 回传；如果同时使用 QR code，应把 QR token、CTV placement、移动端 first_open 串到同一链路 ID，避免把大屏曝光和移动 Web 点击混在一个归因口径里
- 2026 年更新的 CTV 文档说明，Singular 已支持 CTV-to-mobile app attribution；这会让大屏曝光进入移动 App acquisition 报表，但仍属于测量与归因扩展。若广告素材同时给出 QR code 或短链，应把扫码事件、CTV impression、移动 first_open 和首个关键事件分别入库，再由内部规则做贡献拆分
- 文档明确提醒 Facebook、Instagram、TikTok 等 in-app browser 到系统浏览器的上下文切换会造成归因损耗，应使用对应广告网络的 tracking link 格式先捕获点击

这类能力尤其适合多平台买量、归因体系复杂、希望把 Web 来源继续喂给媒体优化模型的团队。

如果团队主要诉求是“让媒体优化模型知道这个 app install 来自哪个 web campaign”，Singular 这类参数转发方案通常比单纯做一个短链更关键。它把 `utm_source`、`utm_campaign`、`utm_content` 等 Web 维度映射到移动归因报表，避免所有自有站安装都被粗暴归到 “Mobile Web to App” 一类。

但这类 forwarding 的核心仍是“归因参数继承”。如果安装后要回到具体内容、商品、权益页或 onboarding 分支，还必须同步设计 `_dl / _ddl / passthrough` 与 App 内路由解析；否则报表能看到来源，用户体验仍可能只落首页。

这一点也适用于自建方案：Web2App 的关键不是把所有参数无差别塞进最终 URL，而是确定哪些字段需要进入三条不同通道。`媒体字段` 要进入媒体和 MMP 报表，`业务字段` 要进入 App 首开路由，`诊断字段` 要进入内部日志和看板。三条通道可以共享同一个 click/session id，但不要依赖单一 query string 在 in-app browser、系统浏览器、商店和 App 之间完整存活。

### 6.5 Firebase：保留为测量层，不再适合作主链路

Firebase 现在的定位很清楚：

- `Firebase Dynamic Links` 已废弃并已结束服务
- 2025 年 8 月 25 日之后，既有 Dynamic Links 不再可作为稳定跳转入口
- 官方 FAQ 明确，custom domain 和 `page.link` 子域名承载的 Dynamic Links 都会停止工作，自动分配的 `page.link` 域名也不能保留或转移
- 官方迁移方向是 `App Links + Universal Links`
- iOS Web 入口可考虑 `Smart App Banners`

因此 Firebase 更适合作为：

- App analytics
- first_open / in-app events 采集
- 与广告平台或 MMP 的事件联动层

而不应再承担新的 Web2App 主路由职责。

需要额外强调：Firebase Dynamic Links 的退场不是简单替换短链域名。迁移时要重新设计“已安装唤起、未安装商店 fallback、安装后首开恢复、归因参数回传”四件事。单独接 Universal Links / App Links 只能解决已安装打开和部分网页 fallback，不能自动补齐短链管理、跨端商店分流、延迟深链和归因报表。

### 6.6 选型时不要只比较“深链能力”

AppsFlyer、Branch、Adjust、Singular 都能做 deep link / deferred deep link，但真实差异在重心：

| 选型问题 | 更应关注的能力 |
| --- | --- |
| 自有移动站流量大，想把 Web 访客转 App | Smart Banner、Web SDK、OneLink / Branch Link、Web campaign 到 app install 归因 |
| 内容页、商品页、票务页需要安装后回到原页面 | Deepview、Journeys、deferred deep link、App 内路由解析 |
| iOS 首开恢复不稳定，归因响应慢 | LinkMe、ODDL、session response、fallback 策略 |
| 多媒体买量，想把 Web 来源继续喂给平台优化 | 参数 forwarding、Conversion API、MMP 与媒体集成深度 |
| 桌面 Web 需要引导到移动 App | QR code deep link、desktop banner、跨设备 attribution 口径 |
| CTV / OTT 或大屏曝光需要带来移动安装 | QR code、CTV-to-mobile attribution、时间窗口、聚合与去重规则 |

选型时应先写清楚主问题：是“转化更多安装”、是“恢复正确内容”、是“减少 iOS 损耗”，还是“让媒体模型吃到更完整信号”。问题不同，最优平台也不同。

## 7. 设计 Web2App 方案时最该先想清楚的 8 件事

### 7.1 Web 页究竟承担什么角色

常见只有三种模式：

- `教育型`：高决策成本，先解释价值
- `筛选型`：先试用、预览、试玩，过滤高 intent
- `直推型`：仅保留极轻承接层，快速送商店

没有明确角色的中间页，通常只会增加流失。

### 7.2 iOS 与 Android 必须分开设计

- Android 重点是 `App Links + Install Referrer + first_open`
- iOS 重点是 `Universal Links + Smart App Banner / 中间页 + deferred deep link + AAK / SKAN`

两端的路由机制、可见性、归因粒度和浏览器限制并不对称，不能当一套系统处理。

### 7.3 “首开恢复”比“送到商店”更重要

如果安装后只能落首页，Web2App 的大部分价值已经损失。真正要保证的是：

- 页面内容 ID 是否被带入 App
- 首开是否进入正确内容页 / onboarding 分支
- 首个关键事件是否带着原始 campaign 上下文

### 7.4 参数设计要先于创意投放

至少要想清楚四类字段：

- 媒体参数：`utm_*`、`gclid`、`ttclid`、`fbclid`
- 广告参数：campaign、adset、creative、placement
- 内容参数：sku、content_id、landing_variant、offer_id
- 路由参数：deep_link_value、fallback_url、store_url、platform

如果参数体系混乱，后续不论接 AppsFlyer、Branch、Adjust 还是 Singular，都会出现“能跳但不能复盘”的问题。

### 7.5 指标不能只看安装量

至少应拆开看：

- `Landing Page -> Store CTR`
- `Store -> First Open CVR`
- `First Open -> First Key Event CVR`
- `Indirect Installs`
- `Web to App First Conversion`
- `Deferred Deep Link Coverage`
- `Context Restore Success Rate`

只有把“是否恢复了原意图”也纳入指标，Web2App 才能真正被优化。

### 7.6 自有站流量通常比买量更适合先做 Web2App

高 intent 的 SEO、内容页、CRM、私域、达人导流，往往比冷启动买量更适合先做 Web2App。原因很简单：

- 用户已经表现出更强兴趣
- Web 页有足够空间承接内容
- App 化后的留存和首转常常更高
- 实施难度通常低于跨媒体统一改造

### 7.7 不同流量入口要用不同链路，不要一套 H5 打全场

Web2App 的落地页不是统一模板，而是按流量意图选择链路长度：

| 入口 | 推荐链路 | 核心优化点 |
| --- | --- | --- |
| Google Search / Shopping / PMax | 高意图词 -> 信息承接页 -> 商店 / App -> 首个转化 | 保留 `gclid`、导入 `first_open` 与 app 内 primary event，观察 `indirect installs` 和 `Web to app first conv.` |
| TikTok / Meta 内容流 | 创意种草 -> 试玩 / 预览 / 权益解释 -> 商店 -> 首开恢复 | OS 分组、内容 ID 继承、首开 onboarding 分支 |
| SEO / 内容页 / CRM | 既有网页 -> Smart Banner / Journey -> App 或商店 | Web SDK、已安装直达、未安装 deferred deep link |
| 桌面 Web / PC / Console | 桌面页 -> QR code / 手机承接页 -> 商店 / App | QR link 与 Web session 绑定，安装后恢复桌面侧上下文 |
| CTV / OTT / 大屏广告 | 大屏曝光 -> QR / 短链 -> 手机承接页 -> 商店 / App | QR token、曝光窗口、MMP 归因和后续事件回流 |
| 再营销 / 已安装用户 | Web / 邮件 / 广告 -> Universal Link / App Link -> App 内容页 | 不走商店，优先校验直达成功率和 fallback |

如果入口意图弱，Web 页需要承担解释和筛选；如果入口意图强，Web 页应尽量轻，重点放在参数保存、商店分流和首开恢复。

### 7.8 首开路由不要等待归因响应

Web2App 的体验目标和归因目标要拆开：

- 体验侧：首次打开 App 时应尽快恢复页面、活动、商品、内容或 onboarding 分支。
- 归因侧：MMP、SKAN / AdAttributionKit、媒体 postback 可以延迟补齐，不应阻塞首屏路由。
- 报表侧：允许同一用户先以 session / deep link 载荷恢复体验，再在后续归因结果返回后补齐媒体来源。

Adjust ODDL 这类能力的价值正在于把 deferred deep link 交付从较慢的 attribution response 中解耦，优先通过更快的 session response 恢复首开内容。即使不用该产品，也应在自建方案里保留类似原则：`先恢复体验，后补齐归因`。

## 8. 落地蓝图

### 8.1 最小可行方案

如果团队从零开始，不建议一次性接满所有平台。更稳妥的 MVP 是：

1. 选一个高 intent 来源，如 Google Search、SEO 内容页、CRM 或 TikTok 内容流量。
2. 只做一个核心落地页模板，明确它是教育型、筛选型还是直推型。
3. 接入一个 deep link / MMP 主链路，统一生成 smart link、store fallback 和 deferred deep link。
4. App 侧只恢复一个高价值页面或 onboarding 分支，不要一开始覆盖所有路由。
5. 建立 `click -> landing -> CTA -> store -> first_open -> first_key_event` 的漏斗看板。

MVP 的验收标准不是“能跳到商店”，而是至少能回答三件事：哪个广告 / 内容带来安装，安装后是否回到正确 App 页面，首个关键事件是否带着原始上下文。

### 8.2 参数规范

建议把参数分成三层，避免媒体参数、业务参数和路由参数互相污染：

| 层级 | 示例字段 | 用途 |
| --- | --- | --- |
| 媒体层 | `utm_source`、`utm_campaign`、`gclid`、`fbclid`、`ttclid` | 归因、报表、媒体优化 |
| 业务层 | `content_id`、`sku`、`offer_id`、`creator_id`、`landing_variant` | Web 承接和 App 首开恢复 |
| 路由层 | `deep_link_value`、`fallback_url`、`store_url`、`platform`、`ddl` | 已安装直达、未安装 fallback、延迟深链 |

参数设计要遵循两个原则：广告平台能读的字段不要只放在内部字段里；App 首开必须使用的字段不要只依赖浏览器 cookie。

还要补充一个工程原则：`参数保真` 优先于 `参数丰富`。落地页可以记录很多诊断字段，但真正进入 smart link / deferred deep link 载荷的字段应保持短、稳定、可验证。推荐把载荷拆成：

- `link_id / session_id`：用于在服务端查完整上下文。
- `deep_link_value`：用于 App 首开立即路由。
- `campaign keys`：用于媒体和 MMP 归因。
- `content keys`：用于恢复商品、内容、活动或 onboarding 分支。

不要把完整落地页 URL、冗长 JSON、价格、用户标识或一次性实验全量塞进深链参数。参数越长，越容易在浏览器跳转、商店重定向、二维码扫描和复制粘贴场景里被截断或转义失败。

### 8.3 技术分工

一条稳定 Web2App 链路通常需要四类团队协同：

| 模块 | 主要责任 |
| --- | --- |
| 投放 / 增长 | 定义来源、创意、OS 拆分、优化事件和预算实验 |
| Web | 落地页、Smart Banner、CTA、参数保留、fallback 页面 |
| App | Universal Links / App Links、首开路由、SDK、事件埋点 |
| 数据 / MMP | 归因口径、事件回传、去重、报表、媒体 Conversion API |

常见失败点是只让 Web 团队做一个 H5，App 侧没有首开恢复，数据侧也没有把 web campaign 与 app event 对齐。这样最多得到一个跳转页，得不到 Web2App 系统。

### 8.4 实验优先级

建议按以下顺序做实验：

1. 已安装用户：Web CTA 是否能稳定唤起 App 并进入对应页。
2. 未安装用户：安装后是否能恢复内容 / 活动 / onboarding。
3. Web 页角色：教育型、筛选型、直推型哪种带来更高首个关键事件率。
4. OS 拆分：iOS 与 Android 的商店转化、首开恢复和归因可见性分别优化。
5. 桌面 Web：通过 QR code 把桌面决策流量转成移动 App 首开。

不要先优化按钮文案和页面视觉，再回头补参数和 SDK。Web2App 的最大损耗通常发生在链路断裂，而不是页面局部点击率。

### 8.5 上线验收清单

正式放量前，至少应完成以下验收：

| 验收项 | 通过标准 |
| --- | --- |
| 已安装用户直达 | iOS Universal Links / Android App Links 能打开 App 对应页，失败时有 Web fallback |
| 未安装用户安装后恢复 | 安装并首次打开后能进入指定内容、活动或 onboarding 分支 |
| 参数继承 | `utm_*`、点击 ID、内容 ID、落地页版本和路由参数能进入 MMP / App 首开事件 |
| 商店跳转 | iOS / Android 分别进入正确商店，跨 OS 广告不会混用同一 app 配置 |
| 定制商店页 | Apple CPP / Google Play CSL 与广告创意、Web 落地页和 App 首开目标一致，`store_variant` 可回传分析 |
| 事件回传 | `first_open` 与首个关键事件能回传给 MMP 和对应媒体平台 |
| 报表去重 | web conversion、install、first_open、first key event 的口径清楚，不重复计算 |
| 受限环境 | Facebook/Instagram/TikTok 内置浏览器、Safari、Chrome、桌面 QR code 至少各测一轮 |
| Web SDK 与存储 | Smart Banner / Web SDK 在 Safari、Chrome 和主要 in-app browser 中能保留必要状态；如启用 cookie mode，CMP 与隐私披露已覆盖 |
| 参数覆盖治理 | 动态追加的 `_dl`、`_ddl`、fallback、UTM、click id 有白名单和锁定规则，生产短链不会被任意 URL 参数覆盖 |
| 平台口径版本 | Google、TikTok、Meta、Snap、X、MMP 的文档日期、账号权限、适用 campaign 类型和 OS 限制已写入上线说明 |
| MMP SDK 回调 | AppsFlyer UDL、Branch init、Adjust session response、Singular SDK 等首开回调能在冷启动、重装、首次授权弹窗前后稳定返回业务载荷 |
| 媒体配置字段 | Meta DDL URL、TikTok app tracking、Google first_open 导入、X MMP event tag 等广告层配置与 MMP 后台一致 |

如果只能完成其中一部分，优先级应是：直达和首开恢复 > 参数继承 > 事件回传 > 页面转化优化。

更严格的 2026 版验收应把六项证明拆开归档：`媒体结果可见`、`第二跳动态带参`、`路由基建生效`、`首开恢复独立于归因响应`、`post-install event 回传与去重`、`参数覆盖受控`。缺少任一项，都要在上线说明里标为局部能力，而不是完整闭环。

### 8.6 测试矩阵

Web2App 不适合只用一台手机点一遍验收。上线前至少按以下矩阵抽样：

| 维度 | 必测组合 |
| --- | --- |
| OS | iOS 已安装 / iOS 未安装 / Android 已安装 / Android 未安装 |
| 浏览器容器 | Safari、Chrome、Facebook/Instagram in-app browser、TikTok in-app browser、X/Snap 内置浏览器 |
| 入口来源 | Google Search / PMax、TikTok web campaign、Meta 或 Snap 创意、SEO/CRM、自有桌面 Web QR |
| 链路动作 | 广告点击、落地页曝光、CTA、商店打开、安装、首次打开、首个关键事件 |
| 上下文字段 | click id、UTM、campaign、creative、content_id、landing_variant、deep_link_value、fallback_url |
| 报表口径 | Web analytics、MMP install、first_open、媒体后台 conversion、内部业务事件 |

验收时不要只看“是否打开 App”。更应该逐条确认：已安装用户是否进对页面，未安装用户首开是否恢复上下文，媒体后台是否能看到可优化事件，内部报表是否能把 Web 页面版本和 App 首个关键行为连起来。

### 8.7 数据看板与归因去重

Web2App 上线后至少需要一张端到端看板，而不是把 Web analytics、MMP 和媒体后台分开看。推荐的最小字段如下：

| 字段组 | 必备字段 | 作用 |
| --- | --- | --- |
| 用户与会话 | anonymous_id、web_session_id、mmp_click_id、app_instance_id | 串联 Web 会话、点击、安装与首开 |
| 媒体来源 | source、campaign、adset、creative、placement、click_id | 还原投放结构，支持平台优化 |
| 页面上下文 | landing_url、landing_variant、content_id、offer_id、cta_id | 判断 Web 页承接价值和首开恢复质量 |
| 路由结果 | route_type、store_opened、deep_link_opened、fallback_reason | 定位损耗发生在商店前还是首开前 |
| App 结果 | first_open_time、restore_success、first_key_event、revenue_event | 验证安装后的业务质量 |

去重口径要提前写清楚，尤其是以下三组关系：

- `web conversion` 与 `app first_open`：前者说明网页行为，后者说明安装后打开，不能直接相加。
- `install` 与 `first_open`：不同平台口径不同，内部看板应固定一个主口径，另一个作为诊断字段。
- `媒体归因` 与 `MMP 归因`：媒体自归因、MMP last click、SKAN / AdAttributionKit 聚合回传可能同时出现，报表应区分“优化口径”和“财务/复盘口径”。

实践上，Web2App 看板最有价值的不是总安装量，而是三类成功率：`store_handoff_success_rate`、`deferred_restore_success_rate`、`first_key_event_with_context_rate`。它们分别回答“有没有送到正确商店”“安装后有没有回到正确上下文”“首个关键行为有没有带着原始意图”。

### 8.8 归因产品与路由产品的验收拆分

上线验收时建议把供应商能力拆成两套清单，不要用一个“deep link 已接入”笼统带过。

| 验收域 | 主要问题 | 典型责任方 |
| --- | --- | --- |
| 路由验收 | 已安装能否打开 App；未安装后首开能否恢复内容；受限浏览器是否有 fallback | App、Web、deep link 平台 |
| 测量验收 | install、first_open、首个关键事件是否能归因；web campaign 参数是否进入媒体和 MMP 报表 | MMP、数据、投放 |
| 优化验收 | 平台是否能用 post-install event 出价；Conversion API / postback 是否带回 click id 或 campaign id | 投放、MMP、广告平台 |
| 诊断验收 | 每一步失败原因是否可记录；是否能按 OS、浏览器、媒体、落地页版本拆分 | 数据、Web、App |

这四类验收的节奏可以不同。路由验收必须在首批用户进入前完成；测量和优化验收可以先跑灰度流量校准；诊断验收则决定后续能不能快速定位损耗。

### 8.9 上线后的日常排障口径

正式放量后，Web2App 问题不要先按“媒体归因不准”归类，而应按链路断点排查：

| 现象 | 优先排查 | 常见修复方向 |
| --- | --- | --- |
| 落地页点击高，但商店打开低 | CTA 链接、in-app browser、store fallback、OS 判断 | 给不同 OS 使用独立链接，保留受限浏览器 fallback 页 |
| 商店打开正常，但 first_open 低 | 商店页、安装包、应用体积、首开崩溃、MMP SDK 初始化 | 拆 Android / iOS 漏斗，先用内部事件确认真实首开 |
| first_open 正常，但首开落首页 | deferred deep link 载荷、App 路由解析、session response | 把 `content_id`、`deep_link_value`、`landing_variant` 写入首开事件 |
| 媒体有安装，内部看板对不上 | 自归因口径、MMP last click、SKAN / AAK 延迟、去重规则 | 分开“优化口径”和“财务 / 复盘口径”，不要直接相加 |
| iOS 恢复率明显低于 Android | ATT、Safari / in-app browser、Universal Link、LinkMe / ODDL 配置 | 单独设计 iOS 路由与测试矩阵，不复用 Android 假设 |
| 桌面 QR 安装无法复盘 | QR link 是否带 session、扫码后是否生成 mobile session | 桌面 session、QR token、移动端 first_open 做同一链路 ID |
| CTV / 大屏广告有曝光无安装归因 | QR 是否唯一、曝光窗口是否配置、MMP 是否支持该 partner | 使用 campaign / placement 级 QR token，避免把大屏流量混入 organic |

排障顺序应固定为：`点击捕获 -> Web session -> CTA -> 商店 -> first_open -> 首开恢复 -> 首个关键事件 -> 媒体回传`。这样能避免团队在创意、页面和归因之间来回猜测。

### 8.10 最小监控指标

Web2App 上线后，日常监控不宜只看 CPI、CPA 或安装量。至少需要固定以下 8 个指标：

| 指标 | 说明 |
| --- | --- |
| `landing_to_cta_rate` | 判断 Web 页是否有承接价值 |
| `cta_to_store_rate` | 判断按钮、smart link、OS 分流和 in-app browser 是否稳定 |
| `store_to_first_open_rate` | 判断商店页、安装包、包体和首开稳定性 |
| `deferred_restore_success_rate` | 判断未安装用户首开后是否回到正确上下文 |
| `direct_deep_link_success_rate` | 判断已安装用户是否被正确唤起 |
| `first_key_event_with_context_rate` | 判断首个关键行为是否保留原始广告和业务上下文 |
| `media_postback_match_rate` | 判断 MMP / 媒体回传是否与内部事件可对账 |
| `duplicate_conversion_rate` | 判断 web conversion、install、first_open、first key event 是否被重复计算 |

这些指标要按 `OS`、`媒体`、`浏览器容器`、`落地页版本` 和 `是否已安装` 拆开看。只看总漏斗会掩盖 Web2App 最常见的问题：Android 表现正常、iOS 首开恢复失败；系统浏览器正常、社交 App 内置浏览器丢参；移动 Web 正常、桌面 QR 无法跨设备复盘。

### 8.11 媒体、MMP 与自建系统的交接清单

Web2App 真正上线时，最容易出问题的不是单点能力，而是三方交接。建议把交接文档压缩成以下字段，作为投放、Web、App、数据和供应商共同验收的最小合同：

| 交接点 | 必须明确 | 不明确时的后果 |
| --- | --- | --- |
| 广告点击到 Web | click id、UTM、campaign、creative、placement 由谁捕获，是否先经过 MMP / 媒体 tracking link | Web 页有访问，但安装归因可能掉到 organic 或错误来源 |
| Web CTA 到商店 / App | CTA 是动态 smart link 还是静态 store URL，是否按 OS、浏览器、已安装状态分流 | 页面点击率正常，但商店打开率、首开恢复率低 |
| 第二跳链接生成 | 首跳 click id、UTM、referrer、landing_variant、content_id 如何映射到 OneLink / Branch Link / Adjust Link / Singular Link，覆盖规则是否白名单化 | 媒体能看到部分安装，但业务上下文、创意版本或内容页在首开丢失 |
| Web / 广告到定制商店页 | 是否使用 Apple CPP / Google Play CSL，商店页版本如何映射到 campaign、content_id 和 App 首开目标 | 广告与 Web 已完成教育，但商店页承诺不一致，安装前流失或安装后意图断层 |
| Web session 到首开 | `link_id / session_id`、`deep_link_value`、`content_id` 存在哪里，App 首开如何拉取 | 安装后只能落首页，Web 说服内容无法延续 |
| 首开到媒体回传 | first_open、注册、订阅、购买等事件通过 MMP、SDK、S2S 还是 Conversion API 回传 | 媒体无法用 post-install event 优化，预算学习慢 |
| MMP 回调到 App 路由 | SDK 回调字段如何映射到 App 内页面、onboarding 分支和业务实验组，失败时如何 fallback | MMP 已归因但用户仍进首页，投放和体验口径割裂 |
| iOS 补强能力 | NativeLink、LinkMe、ODDL、AAK re-engagement URL 是否需要剪贴板授权、ATT、窗口期、Universal Link 或账号白名单 | 灰度测试可用，正式放量后因权限、窗口或系统剥参导致恢复率波动 |
| 报表去重 | web conversion、install、first_open、first key event 谁是主口径，谁是诊断口径 | 同一用户被多次计入增长贡献，ROI 被高估 |
| 文档版本 | 使用的广告平台、MMP、商店页、隐私归因文档发布日期或更新时间是什么 | 平台能力变更后，团队仍按旧规则投放或验收，导致“配置正确但口径已失效” |

实操建议是为每次 Web2App campaign 生成一个 `link spec`，至少包含：目标 OS、广告平台、落地页模板、MMP link 模板、fallback URL、CPP / CSL 商店页版本、App 内目标路由、首个关键事件、媒体回传事件、资料版本和验收负责人。没有这份交接清单时，团队通常会把问题归咎于“归因不准”，但真实原因往往是第二跳链接、商店页版本、首开载荷或事件回传口径没有被统一设计。

### 8.12 灰度放量门槛

Web2App 不适合“配置完成即全量”。建议把首批流量限制在单一平台、单一 OS、单一落地页模板和单一首开目标，先验证证据链，再扩展渠道与页面版本。这里的证据链不是媒体后台看到安装，而是测试设备和三方报表都能串起 `首跳参数 -> 第二跳链接 -> 商店页版本 -> 首开路由 -> 首个关键事件 -> 媒体回传`。

| 阶段 | 放量门槛 | 失败时先停什么 |
| --- | --- | --- |
| 技术灰度 | 已安装直达、未安装首开恢复、fallback、首个事件回传和链路参数都能在测试设备复现 | 停页面和媒体扩量，先修路由 |
| 第二跳灰度 | 首跳参数能动态生成第二跳 smart link，且覆盖规则、fallback、商店页版本和首开载荷都有日志 | 停静态下载按钮和新创意扩量，先修 link spec |
| 小预算实投 | 媒体后台、MMP、内部看板三方都能看到同一批 first_open / first_key_event，差异可解释 | 停优化事件出价，先校准归因和去重 |
| 跨 OS 扩展 | iOS / Android 分别有独立 link spec、商店页、fallback 和测试记录 | 停双端混投，先拆 ad group / campaign |
| 多媒体扩展 | 新媒体只新增 click id 和回传映射，不改业务路由主链路，且保留同一套证据链归档 | 停供应商切换，先复用已验证会话模型 |

灰度期最重要的不是 CPI 是否最低，而是 `deferred_restore_success_rate` 和 `first_key_event_with_context_rate` 是否稳定。若这两个指标不稳定，继续扩量只会把链路断点放大，并让媒体学习到低质量或错误归因的信号。

## 9. 平台对比结论

| 类型 | 代表 | 强项 | 边界 |
| --- | --- | --- | --- |
| 广告平台原生一体化最强 | Google Ads | Web campaign 到 app 安装/首转的定义最完整 | 仍依赖 app 事件、deep link 和 AAP/MMP 接入 |
| 内容种草型 Web2App 最明确 | TikTok Ads | 已公开支持 web 落地后的 app activity measurement | OS 拆分与 tracking 配置要求高 |
| 流量与创意前台强 | Meta / Snap / X | 创意形态多、流量大、可做内容前置承接或 App 安装增强 | 完整 Web2App 闭环通常需第三方补齐 |
| 体验层最成熟 | Branch | Journeys、Deepviews、上下文恢复强 | 需要 Web SDK + App SDK 协同 |
| web-to-app 增长底座强 | AppsFlyer | OneLink + Smart Banners + 归因联动成熟 | 体验层灵活度略依赖模板和接入方式 |
| 路由与归因底座稳 | Adjust | fallback、iOS 恢复、Smart Banners 能力强 | 更偏稳定性，不以体验编排见长 |
| 参数转发与媒体信号强 | Singular | Web SDK + forwarding + conversion APIs | 更偏企业级测量与优化架构 |
| 历史方案退场 | Firebase Dynamic Links | 历史集成多 | 新项目不应继续采用 |

从选型顺序看，可以按业务主矛盾倒推：

| 主矛盾 | 优先组合 |
| --- | --- |
| Google Search / PMax 等 web campaign 贡献 app install 但媒体看不清 | Google Web to App Connect + Web to App Acquisition Measurement + AAP/MMP app event 导入 |
| TikTok / Meta 内容先教育，安装后要回到具体内容或权益页 | 媒体 tracking link + 自建落地页 + Branch / AppsFlyer / Adjust / Singular deferred deep link |
| 自有移动站、SEO、CRM 有大量高意图访客 | Smart Banner / Journeys / OneLink Smart Script / Singular Web SDK，优先优化首开恢复率 |
| 桌面 Web、CTV、线下物料要带来移动安装 | QR code deep link + session/token + MMP 跨设备 attribution + post-install event 回传 |
| iOS 首开恢复不稳定 | Universal Links 基建复核 + LinkMe / ODDL 或等价 session response 方案 + 独立 iOS 测试矩阵 |
| 已安装用户 re-engagement 要兼顾测量与落页 | AdAttributionKit / SKAN 作为归因层，Universal Links + App 内路由作为体验层 |

因此，Web2App 选型不应问“哪家深链最好”，而应问“当前最大损耗发生在点击、Web CTA、商店、首开恢复、还是媒体回传”。供应商能力只有和损耗位置匹配，才会产生真实增量。

## 10. 常见误区

- 把 Web2App 误解成“广告先落 H5”。
- 只做跳转，不做安装后的上下文恢复。
- 只看安装量，不看首开后质量。
- 不拆 iOS / Android，直接共用一套路径和指标。
- 只依赖媒体平台后台，不做 MMP / 内部数据对账。
- 仍把 Firebase Dynamic Links 当新项目默认方案。
- 只优化商店前 CTR，不追首开恢复成功率和首转质量。
- 把 iOS Smart App Banner 当成完整 deferred deep link 方案，忽略它主要解决的是 Web 到 App Store / 已安装打开的入口体验。
- 忽略桌面 Web 到移动 App 的 QR code 路径，导致高意图桌面流量只能停留在网页转化。
- 把广告平台的 Web2App 测量能力当成路由能力，导致媒体后台能看到部分 app 结果，但用户首开仍落首页。
- 只做媒体回传，不做内部去重，最后出现 Web conversion、install、first_open、first key event 被重复计入同一增长贡献。

## 11. 最终结论

Web2App 不是附属跳转能力，而是移动增长中的一层中间系统。它连接广告点击、Web 承接、应用商店、首次打开、延迟深链恢复和事件回传，目标不是“多一个页面”，而是“少丢一段意图”。

如果按公开资料完整度与现实落地性做判断：

1. `Google Ads` 仍是广告平台里原生 Web2App 最完整的方案。
2. `TikTok Ads` 是“先内容承接、后 App 转化”最明确的平台之一。
3. `Meta / Snap / X` 更适合做流量与创意前台，完整链路通常要靠外部中台补齐。
4. `AppsFlyer / Branch / Adjust / Singular` 才是把 Web2App 真正做成完整系统的核心层，其中第二跳带参、首开 session response、SAN DDL 与 Web SDK forwarding 是 2026 年选型重点。
5. 新项目不应继续把 `Firebase Dynamic Links` 当主链路；存量项目还需要主动扫描历史广告、二维码、邮件和活动页中的 FDL 入口，避免 2025-08-25 之后形成断链。
6. `Apple Custom Product Pages / Google Play Custom Store Listings` 应作为商店承接层纳入方案，但它们只改善安装前一致性；首开恢复仍要靠 smart link、deferred deep link、session response 和 App 内路由完成。

最终验收不应停在“能否跳转”或“能否归因”，而要逐项确认：第二跳是否动态带参，首开恢复是否不等待归因响应，iOS 侧是否有 ATT / Private Relay / 剪贴板权限等异常路径兜底，首个关键事件是否能带着 Web 与媒体上下文回传并完成内部去重。

一句话压缩：Web2App 的真实资产不是中间页，而是能跨广告、Web、商店、App 和媒体回传持续保存意图的会话系统。广告平台负责让结果被看见，MMP / deep link / 自建 session 负责让意图不断线，App 内路由和事件体系负责把首开后的价值兑现出来；其中 Web CTA 本身也要像广告素材一样纳入版本、参数、fallback 和回滚管理。

## 12. 参考资料

### 广告平台

1. Google Ads, About Web to App Connect
   https://support.google.com/google-ads/answer/12131000?hl=en
2. Google Ads, Get started with Web to App Connect
   https://support.google.com/google-ads/answer/16400535?hl=en
3. Google Ads, Set up Web to App Connect to improve campaign performance
   https://support.google.com/google-ads/answer/15929459?hl=en
4. Google Ads, About Web to App Acquisition Measurement
   https://support.google.com/google-ads/answer/16440462?hl=en
5. Google Ads, About deferred deep linking
   https://support.google.com/google-ads/answer/16420273?hl=en
6. Google Ads, Set up and edit ad group deferred deep linking
   https://support.google.com/google-ads/answer/12373847?hl=en
7. TikTok Ads Manager, About the App Promotion Objective
   https://ads.tiktok.com/help/article/what-is-app-promotion-objective?lang=en
8. TikTok Ads Manager, How to measure app activity for non-app promotion campaigns
   https://ads.tiktok.com/help/article/how-to-measure-app-activity-for-non-app-promotion-campaigns?lang=en
9. TikTok Ads Manager, About Deeplinks
   https://ads.tiktok.com/help/article/understanding-deeplinks-and-deferred-deeplinks
10. TikTok Ads Manager, About Deferred Deeplinks
   https://ads.tiktok.com/help/article/about-deferred-deeplinks?lang=en
11. Meta for Business, Playable ads
   https://www.facebook.com/business/ads/playable-ad-format
12. Meta Business Help Center, About Conversions API
    https://www.facebook.com/business/help/AboutConversionsAPI
13. Facebook Help Center, View websites in the Facebook app
    https://www.facebook.com/help/289776536190480/
14. Snapchat for Business, App Power Pack
    https://forbusiness.snapchat.com/blog/app-power-pack?lang=en-US
15. Snapchat for Business, Sponsored Snaps
    https://forbusiness.snapchat.com/advertising/sponsored-snaps
16. Snapchat for Business, Snap Pixel
    https://forbusiness.snapchat.com/advertising/snap-pixel
17. X Business, App installs campaign
    https://business.x.com/en/advertising/campaign-types/app-installs
18. X Business, Mobile app measurement and attribution
    https://business.x.com/en/help/campaign-setup/create-an-app-installs-campaign/mobile-app-measurement-and-attribution
19. X Business, Mobile app advertising guide
    https://business.x.com/en/resources/mobile-app-advertising-guide
20. Snapchat for Business, Drive App Growth with Snapchat Ads
    https://forbusiness.snapchat.com/advertising/app-growth
21. Meta for Business, Advantage+ app campaigns
    https://www.facebook.com/business/ads/meta-advantage-plus/app-campaigns
22. Snapchat for Business, Snapchat App Power Pack
    https://forbusiness.snapchat.com/advertising/app-power-pack
23. TikTok Ads Manager, How to Set Up App Attribution
    https://ads.tiktok.com/help/article?aid=9656

### 深链、归因与系统基础设施

24. Apple Developer, Promoting Apps with Smart App Banners
    https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners
25. Apple Developer, Allowing apps and websites to link to your content
    https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content/
26. Apple Developer, Measuring ad performance with AdAttributionKit
    https://developer.apple.com/app-store/ad-attribution/
27. Apple Ads, Using AdAttributionKit to measure app ad performance
    https://ads.apple.com/app-store/help/attribution/0093-adattributionkit-to-measure-performance
28. Apple Ads, Measuring performance of ads on the App Store
    https://ads.apple.com/app-store/help/attribution/0028-measuring-ad-performance
29. Apple Ads, App ad attribution overview
    https://ads.apple.com/app-store/help/attribution/0094-ad-attribution-overview
30. Android Developers, About App Links
    https://developer.android.com/training/app-links/about
31. Android Developers, Google Play Install Referrer
    https://developer.android.com/google/play/installreferrer
32. AppsFlyer, Smart Banners—mobile web-to-app (for marketers)
    https://support.appsflyer.com/hc/en-us/articles/360000764837-Smart-Banners-mobile-web-to-app-for-marketers-
33. AppsFlyer, Web-to-App Deep Linking Solution
    https://www.appsflyer.com/products/deep-linking/web-to-app/
34. AppsFlyer, OneLink Smart Script overview
    https://support.appsflyer.com/hc/en-us/articles/360000677217-OneLink-Smart-Script-overview
35. AppsFlyer, Create deep linking and redirection links with OneLink
    https://support.appsflyer.com/hc/en-us/articles/208874366-Create-deep-linking-and-redirection-links-for-your-campaigns-with-OneLink
36. AppsFlyer, Deferred Deep Linking Solution
    https://www.appsflyer.com/products/deep-linking/deferred-deep-linking/
37. Branch, Web to App
    https://help.branch.io/using-branch/docs/web-to-app
38. Branch, Smart Banners & Web-to-App Engagement
    https://www.branch.io/products/banners/
39. Branch, Deepviews Overview
    https://help.branch.io/using-branch/docs/deepviews
40. Branch, Journeys: Desktop Banners
    https://help.branch.io/docs/desktop-journeys
41. Branch, QR Codes Overview
    https://help.branch.io/docs/qr-codes-1
42. Branch, Facebook Ads Deferred Deep Linking
    https://help.branch.io/marketer-hub/docs/facebook-ads-deferred-deep-linking
43. Branch, SAN API-Driven Deferred Deep Linking
    https://help.branch.io/developer-hub/docs/san-deferred-deep-linking
44. Adjust, Deep links
    https://help.adjust.com/en/article/deep-links
45. Adjust, LinkMe
    https://help.adjust.com/en/article/linkme
46. Adjust, Optimized Deferred Deep Linking
    https://help.adjust.com/en/article/optimized-deferred-deep-linking-oddl
47. Adjust, Smart banners
    https://help.adjust.com/en/article/smart-banners
48. Singular, Website-to-Mobile App Attribution Forwarding for Mobile Web
    https://support.singular.net/hc/en-us/articles/360042283811-Website-to-Mobile-App-Attribution-Forwarding-for-Mobile-Web
49. Singular, Web, Web-to-App, PC, & Console Campaign Optimization
    https://support.singular.net/hc/en-us/articles/30577283058459-Optimize-Web-Campaigns-for-Mobile-PC-Console-Acquisition-Using-Conversion-APIs
50. Singular, Singular Links / Tracking Links FAQ
    https://support.singular.net/hc/en-us/articles/360030934212-Singular-Links-Tracking-Links-FAQ
51. Singular, Mobile Attribution for Connected TV FAQ
    https://support.singular.net/hc/en-us/articles/13581281810331-Mobile-Attribution-for-Connected-TV-FAQ
52. Firebase, Dynamic Links Deprecation FAQ
    https://firebase.google.com/support/dynamic-links-faq
53. Firebase, Migrate from Dynamic Links to App Links & Universal Links
    https://firebase.google.com/support/guides/app-links-universal-links
54. Singular, Web SDK - Overview & Getting Started
    https://support.singular.net/hc/en-us/articles/41862111062299-Web-SDK-Overview-Getting-Started
55. Singular, Web SDK - Native JavaScript Implementation Guide
    https://support.singular.net/hc/en-us/articles/41863502734619-Web-SDK-Native-JavaScript-Implementation-Guide
56. Branch, Activation Migration Guide
    https://help.branch.io/marketer-hub/docs/activation-migration-guide
57. Reddit for Business, App Install Campaigns
    https://www.business.reddit.com/campaign-objective/app-installs
58. Quora Ad Support, How do Quora app install ads work?
    https://quoraadsupport.zendesk.com/hc/en-us/articles/115010300987-How-do-Quora-app-install-ads-work
59. LinkedIn Marketing Solutions, LinkedIn Ads
    https://business.linkedin.com/marketing-solutions/ads
60. X Ads API, Mobile Conversions
    https://docs.x.com/x-ads-api/measurement/mobile-conversions
61. X Ads API, Web Conversions
    https://docs.x.com/x-ads-api/measurement/web-conversions
62. Singular, Conversion Postbacks for Web, PC, and Console FAQ
    https://support.singular.net/hc/en-us/articles/19017155637403-Conversion-Postbacks-for-Web-PC-and-Console-FAQ
63. AppsFlyer, About link structure and parameters
    https://support.appsflyer.com/hc/en-us/articles/207447163-About-link-structure-and-parameters
64. AppsFlyer Developer Hub, OneLink Smart Script V2
    https://dev.appsflyer.com/hc/docs/dl_smart_script_v2
65. AppsFlyer, Set up Smart Script to convert web visitors
    https://support.appsflyer.com/hc/en-us/articles/4413588932241-Set-up-Smart-Script-to-convert-web-visitors
66. Apple Developer Documentation, AdAttributionKit
    https://developer.apple.com/documentation/AdAttributionKit
67. Branch, NativeLink Deferred Deep Linking
    https://help.branch.io/developer-hub/docs/nativelink-deferred-deep-linking
68. Apple Developer Documentation, handleTap(reengagementURL:)
    https://developer.apple.com/documentation/adattributionkit/appimpression/handletap%28reengagementurl%3A%29
69. Apple Developer Documentation, Receiving ad attributions and postbacks
    https://developer.apple.com/documentation/adattributionkit/receiving-ad-attributions-and-postbacks
70. AppsFlyer Developer Hub, OneLink Smart Banner V2
    https://dev.appsflyer.com/hc/docs/dl_smart_banner_v2
71. Apple Developer Documentation, reengagementOpenURLParameter
    https://developer.apple.com/documentation/adattributionkit/postback/reengagementopenurlparameter
72. Google Ads, Get the full value from your web and app channels
    https://support.google.com/google-ads/answer/14885959?hl=en
73. Singular, PC & Console - API Endpoint Reference
    https://support.singular.net/hc/en-us/articles/17499952586779-Singular-PC-Console-Server-to-Server-S2S-API-Endpoint-Reference
74. Singular, Clipboard-Based DDL FAQ
    https://support.singular.net/hc/en-us/articles/5626161387419-Clipboard-Based-DDL-FAQ
75. Apple Developer Documentation, Identifying conversion values with conversion tags
    https://developer.apple.com/documentation/adattributionkit/conversion-tags
76. Branch, In-App Routing
    https://help.branch.io/developer-hub/docs/in-app-routing
77. Adjust, Web-to-app
    https://help.adjust.com/en/article/web-to-app
78. X Business, Mobile app measurement and attribution
    https://business.x.com/en/help/campaign-setup/create-an-app-installs-campaign/mobile-app-measurement-and-attribution
79. Apple Developer, Custom Product Pages
    https://developer.apple.com/app-store/custom-product-pages/
80. Google Play Console Help, Create custom store listings to target specific user segments
    https://support.google.com/googleplay/android-developer/answer/9867158
81. AppsFlyer, Meta ads integration setup
    https://support.appsflyer.com/hc/en-us/articles/207033826-Meta-ads-integration-setup
82. X Ads API, Mobile Conversions
    https://docs.x.com/x-ads-api/measurement/mobile-conversions
83. Apple Developer Help, Configure multiple product page versions
    https://developer.apple.com/help/app-store-connect/create-custom-product-pages/configure-multiple-product-page-versions/
84. Apple Developer, Custom Product Pages on the App Store
    https://developer.apple.com/app-store/custom-product-pages/
85. Singular, Web, Web-to-App, PC, & Console Campaign Optimization
    https://support.singular.net/hc/en-us/articles/30577283058459-Web-Web-to-App-PC-Console-Campaign-Optimization
86. Singular, Conversion Postbacks for Web, PC, and Console FAQ
    https://support.singular.net/hc/en-us/articles/19017155637403-Conversion-Postbacks-for-Web-PC-and-Console-FAQ
87. AppsFlyer, Deep Linking Suite
    https://www.appsflyer.com/products/deep-linking/
88. AppsFlyer Developer Hub, iOS Unified Deep Linking
    https://dev.appsflyer.com/hc/docs/dl_ios_unified_deep_linking
89. Singular, Mobile Attribution for Connected TV (CTV) FAQ
    https://support.singular.net/hc/en-us/articles/13581281810331-Mobile-Attribution-for-Connected-TV-CTV-FAQ
90. Google Ads Help, New features to connect your web and app advertising in Google Ads
    https://support.google.com/google-ads/answer/16501674?hl=en
