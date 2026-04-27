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
- Singular、Branch 等平台开始强调桌面 Web 到 App 的 QR code 路径，把 Web2App 从移动网页扩展到桌面网页、PC/Console 增长和跨设备归因。
- Adjust 的 ODDL、LinkMe 等能力说明 iOS 侧 deferred deep link 的核心矛盾已经变成“隐私合规 + 首开及时恢复 + 归因不阻塞路由”。
- Firebase Dynamic Links 已在 `2025-08-25` 关闭。历史链接和历史 SDK 不是“待升级项”，而是需要从主链路中移除的风险项。

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

## 5. 广告平台能力梳理

### 5.1 Google Ads：原生产品化最完整

Google Ads 已将 Web2App 明确产品化为 `Web to App Connect`，并配套 `Web to App Acquisition Measurement`。

从官方资料看，其能力闭环最完整的点在于：

- 在 Google Ads 内集中配置 deep linking、app conversion tracking、优化建议
- 支持 Search、Performance Max、Shopping、Hotel 等 web campaign 的 Web2App 优化
- 可识别 `indirect installs`
- 可单列 `Web to app first conv.`
- 官方明确支持通过 Firebase、第三方 AAP/MMP、Google Play 导入 app 首开和 app 内事件

同时，Google 也给出了很明确的边界：

- 该测量能力适用于“广告先到 web，再带来 app 安装”的路径
- 如果 web campaign 直接把人送到 App Store / Google Play，则不在这套测量范围内
- iOS 侧可见性仍受 ATT 同意和隐私框架约束

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

这意味着 TikTok 很适合“先种草、再转安装”的链路，但也要求更严格的 OS 拆分和测量配置。

### 5.4 Snapchat：更偏 App 增长前台

Snap 当前公开能力重心仍偏 App 增长前台，而非完整 Web2App 闭环中台：

- `App Power Pack` 强调新的 app 下载广告能力、交付与测量提升
- `Playable App Ads` 等互动格式更适合“先试后装”的游戏和工具类 App
- `Sponsored Snaps` 提供更强的沉浸式触达与转化入口
- Snap 公开材料也持续强调 Pixel、MMP 集成和 attribution/measurement

这类能力适合做：

- 增量流量入口
- 更高沉浸感的 app 安装创意
- 与 MMP 结合的 App 增长投放

但从公开资料的完整度判断，Snap 在 Web 落地、参数继承、上下文恢复、延迟深链上，仍更像需要外部平台配套，而非原生自带完整闭环。

### 5.5 X Ads：以 App Install 为主，原生 Web2App 叙述较弱

X Business 公开资料仍以 `App installs campaign` 为主，强调：

- 从 X 平滑引导到应用商店
- 与 `MMP`、`SKAdNetwork`、`Advanced Mobile Measurement` 配合
- 优化目标仍以 app click / app install / app purchase optimization 为中心
- 官方移动 App 测量主要依赖获批 MMP，不提供自有 SDK / Ads API 归因能力

因此更现实的判断是：

- X 可以承担流量触达与 App 安装目标
- 但如果要跑严格意义的 Web2App，Web 中间页、参数继承、深链恢复与归因转发仍应由第三方能力承担

## 6. 深链 / MMP / 归因平台能力梳理

### 6.1 AppsFlyer：最典型的 web-to-app 增长底座

AppsFlyer 在 Web2App 上的产品定义非常标准：

- `Smart Banners`
- `OneLink`
- `Deferred deep linking`

结合近期文档更新，AppsFlyer 的公开重点包括：

- Smart Banners 面向 `mobile web-to-app`
- 支持 click-through、view-through、impression 统计
- 支持包括 SRN 在内的 web campaign 到 app 归因
- Smart Banner Web SDK v1 已废弃，现网应使用 `v2`
- Smart Banners 由 OneLink 驱动，可在已安装时 deep link，未安装时送对应商店

它最适合拥有大量自有站、SEO、内容页、CRM 回流流量的团队，把 owned media 也纳入 App 增长漏斗。

### 6.2 Branch：体验层与上下文恢复最强

Branch 的 `Journeys + Deepviews + deep linking` 组合，本质上是在解决“先看内容、再装 App、安装后仍回内容”的体验问题。

公开资料里的核心特点是：

- 用 Journeys 把移动网站变成 App 安装入口
- 用 Deepviews 在未安装时提供移动 Web 预览页
- 支持 direct / deferred deep linking
- 支持基于 Web 行为做智能触达，如来源、回访次数、内容偏好
- 支持桌面 Web 通过 QR code 引导到移动 App，适合内容、电商、票务和旅游等桌面决策、移动履约的场景

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
- `ODDL` 强调把 deferred deep link 从归因响应中解耦，优先通过更快的 session response 交付首开路由；但该能力仍属于 Early Access，应按灰度能力评估
- Smart Banners 允许从移动网页统一承接“已安装直达 / 未安装去商店”

因此，Adjust 更适合重视稳定性、fallback 与 iOS 恢复成功率的团队。

### 6.4 Singular：参数转发与平台优化信号回流强

Singular 的典型优势不是前端交互组件，而是把 Web 参数保留下来，并继续输送给归因和媒体优化层。

公开方案中最关键的是：

- `Web SDK` 识别 UTM / Web campaign 参数
- 点击网页 CTA 后，自动把参数追加到 Singular Link
- 通过 `Conversion APIs` 把安装和 post-install 事件继续回传给广告平台
- 支持移动 Web CTA 和桌面 Web QR code 两类 Web2App 路径
- 文档明确提醒 Facebook、Instagram、TikTok 等 in-app browser 到系统浏览器的上下文切换会造成归因损耗，应使用对应广告网络的 tracking link 格式先捕获点击

这类能力尤其适合多平台买量、归因体系复杂、希望把 Web 来源继续喂给媒体优化模型的团队。

### 6.5 Firebase：保留为测量层，不再适合作主链路

Firebase 现在的定位很清楚：

- `Firebase Dynamic Links` 已废弃并已结束服务
- 官方迁移方向是 `App Links + Universal Links`
- iOS Web 入口可考虑 `Smart App Banners`

因此 Firebase 更适合作为：

- App analytics
- first_open / in-app events 采集
- 与广告平台或 MMP 的事件联动层

而不应再承担新的 Web2App 主路由职责。

需要额外强调：Firebase Dynamic Links 的退场不是简单替换短链域名。迁移时要重新设计“已安装唤起、未安装商店 fallback、安装后首开恢复、归因参数回传”四件事，单独接 Universal Links / App Links 只能解决其中一部分。

## 7. 设计 Web2App 方案时最该先想清楚的 6 件事

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

## 9. 平台对比结论

| 类型 | 代表 | 强项 | 边界 |
| --- | --- | --- | --- |
| 广告平台原生一体化最强 | Google Ads | Web campaign 到 app 安装/首转的定义最完整 | 仍依赖 app 事件、deep link 和 AAP/MMP 接入 |
| 内容种草型 Web2App 最明确 | TikTok Ads | 已公开支持 web 落地后的 app activity measurement | OS 拆分与 tracking 配置要求高 |
| 流量与创意前台强 | Meta / Snap / X | 创意形态多、流量大、可做内容前置承接 | 完整 Web2App 闭环通常需第三方补齐 |
| 体验层最成熟 | Branch | Journeys、Deepviews、上下文恢复强 | 需要 Web SDK + App SDK 协同 |
| web-to-app 增长底座强 | AppsFlyer | OneLink + Smart Banners + 归因联动成熟 | 体验层灵活度略依赖模板和接入方式 |
| 路由与归因底座稳 | Adjust | fallback、iOS 恢复、Smart Banners 能力强 | 更偏稳定性，不以体验编排见长 |
| 参数转发与媒体信号强 | Singular | Web SDK + forwarding + conversion APIs | 更偏企业级测量与优化架构 |
| 历史方案退场 | Firebase Dynamic Links | 历史集成多 | 新项目不应继续采用 |

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

## 11. 最终结论

Web2App 不是附属跳转能力，而是移动增长中的一层中间系统。它连接广告点击、Web 承接、应用商店、首次打开、延迟深链恢复和事件回传，目标不是“多一个页面”，而是“少丢一段意图”。

如果按公开资料完整度与现实落地性做判断：

1. `Google Ads` 仍是广告平台里原生 Web2App 最完整的方案。
2. `TikTok Ads` 是“先内容承接、后 App 转化”最明确的平台之一。
3. `Meta / Snap / X` 更适合做流量与创意前台，完整链路通常要靠外部中台补齐。
4. `AppsFlyer / Branch / Adjust / Singular` 才是把 Web2App 真正做成完整系统的核心层。
5. 新项目不应继续把 `Firebase Dynamic Links` 当主链路。

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
5. TikTok Ads Manager, About the App Promotion Objective  
   https://ads.tiktok.com/help/article/what-is-app-promotion-objective?lang=en
6. TikTok Ads Manager, How to measure app activity for non-app promotion campaigns  
   https://ads.tiktok.com/help/article/how-to-measure-app-activity-for-non-app-promotion-campaigns?lang=en
7. TikTok Ads Manager, About Deeplinks  
   https://ads.tiktok.com/help/article/understanding-deeplinks-and-deferred-deeplinks
8. TikTok Ads Manager, About Deferred Deeplinks  
   https://ads.tiktok.com/help/article/about-deferred-deeplinks?lang=en
9. Meta for Business, Playable ads  
   https://www.facebook.com/business/ads/playable-ad-format
10. Meta Business Help Center, About Conversions API  
    https://www.facebook.com/business/help/AboutConversionsAPI
11. Facebook Help Center, View websites in the Facebook app  
    https://www.facebook.com/help/289776536190480/
12. Snapchat for Business, App Power Pack  
    https://forbusiness.snapchat.com/advertising/app-power-pack
13. Snapchat for Business, Sponsored Snaps  
    https://forbusiness.snapchat.com/advertising/sponsored-snaps
14. Snapchat for Business, Snap Pixel  
    https://forbusiness.snapchat.com/advertising/snap-pixel
15. X Business, App installs campaign  
    https://business.x.com/en/advertising/campaign-types/app-installs

### 深链、归因与系统基础设施

16. Apple Developer, Promoting Apps with Smart App Banners  
    https://developer.apple.com/documentation/webkit/promoting-apps-with-smart-app-banners
17. Apple Developer, Allowing apps and websites to link to your content  
    https://developer.apple.com/documentation/xcode/allowing-apps-and-websites-to-link-to-your-content/
18. Android Developers, About App Links  
    https://developer.android.com/training/app-links/about
19. Android Developers, Google Play Install Referrer  
    https://developer.android.com/google/play/installreferrer
20. AppsFlyer, Smart Banners—mobile web-to-app (for marketers)  
    https://support.appsflyer.com/hc/en-us/articles/360000764837-Smart-Banners-mobile-web-to-app-for-marketers-
21. AppsFlyer, Web-to-App Deep Linking Solution  
    https://www.appsflyer.com/products/deep-linking/web-to-app/
22. AppsFlyer, Deferred Deep Linking Solution  
    https://www.appsflyer.com/products/deep-linking/deferred-deep-linking/
23. Branch, Web to App  
    https://help.branch.io/marketer-hub/docs/web-to-app
24. Branch, Enable Deepviews  
    https://help.branch.io/marketer-hub/docs/enable-deepviews
25. Adjust, Deep links  
    https://help.adjust.com/en/article/deep-links
26. Adjust, LinkMe  
    https://help.adjust.com/en/article/linkme
27. Adjust, Optimized Deferred Deep Linking  
    https://help.adjust.com/en/article/optimized-deferred-deep-linking-oddl
28. Adjust, Smart banners  
    https://help.adjust.com/en/article/smart-banners
29. Singular, Website-to-Mobile App Attribution Forwarding for Mobile Web  
    https://support.singular.net/hc/en-us/articles/360042283811-Website-to-Mobile-App-Attribution-Forwarding-for-Mobile-Web
30. Singular, Web, Web-to-App, PC, & Console Campaign Optimization  
    https://support.singular.net/hc/en-us/articles/30577283058459-Optimize-Web-Campaigns-for-Mobile-PC-Console-Acquisition-Using-Conversion-APIs
31. Firebase, Dynamic Links Deprecation FAQ  
    https://firebase.google.com/support/dynamic-links-faq
32. Firebase, Migrate from Dynamic Links to App Links & Universal Links  
    https://firebase.google.com/support/guides/app-links-universal-links
33. Singular, Web SDK - Overview & Getting Started
    https://support.singular.net/hc/en-us/articles/41862111062299-Web-SDK-Overview-Getting-Started
34. Singular, Web SDK - Native JavaScript Implementation Guide
    https://support.singular.net/hc/en-us/articles/41863502734619-Web-SDK-Native-JavaScript-Implementation-Guide
35. Branch, Journeys Overview
    https://help.branch.io/v1/docs/journeys-overview
36. Branch, Deepviews Overview
    https://help.branch.io/docs/deepviews
37. Branch, Journeys: Desktop Banners
    https://help.branch.io/docs/desktop-journeys
38. X Business, Mobile app measurement and attribution
    https://business.x.com/en/help/campaign-setup/create-an-app-installs-campaign/mobile-app-measurement-and-attribution.html
