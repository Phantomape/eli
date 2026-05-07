# 隐私技术入门：给初学者的系统性介绍

## 1. 这份文档写给谁

这份文档写给“隐私技术小白”。

目标不是把你变成密码学研究员，而是让你先建立一套足够实用的心智模型：

- 常见隐私技术到底分别在解决什么问题
- 它们之间有什么区别
- 什么时候应该用哪一类技术
- 为什么很多方案听起来都叫“隐私保护”，但能力边界完全不同

如果你以后要看广告测量、clean room、on-device measurement、federated learning、PSM、TEE、DP、MPC 这些方案，这份文档可以作为总览地图。

## 2. 先建立一个总框架

很多初学者一上来会问：

- PSM 是什么？
- clean room 是什么？
- TEE 是什么？
- DP 又是什么？

更好的问法其实是：

- 我到底想保护什么？
- 我怕谁看到什么？
- 我是想“少收数据”、还是“能算但看不到原始数据”、还是“结果也不能泄露个体信息”？

从实战角度，常见隐私技术可以先分成六大类：

1. `数据最小化与去标识化`
2. `差分隐私（DP）`
3. `可信执行环境（TEE）/ Confidential Computing`
4. `Data Clean Room`
5. `密码学安全计算`
6. `联邦学习 / 联邦分析`

它们不是互斥关系。很多真实系统会把几类技术叠在一起用。

例如：

- clean room 往往会配分析规则和聚合阈值
- federated analytics 往往会配 secure aggregation 和 DP
- TEE 往往会作为 clean room 或 confidential analytics 的执行底座
- PSM / PSI / PJC 往往负责“私密匹配”，DP 负责“私密发布”

## 3. 最基础的一层：数据最小化与去标识化

### 3.1 它是什么

这是最常见、也最容易理解的一类隐私方法。

核心思想：

- 少收
- 少存
- 少分享
- 去掉直接标识符
- 只保留完成任务必需的数据

常见做法：

- 删除姓名、手机号、邮箱
- 把精确时间改成时间桶
- 把精确位置改成城市或区域
- 把用户 ID 换成伪标识符
- 只保留聚合数据，不保留明细

### 3.2 它解决什么问题

它主要解决：

- “不要把太敏感的数据暴露得太直接”
- “降低普通数据共享的风险”

### 3.3 它不解决什么问题

这是初学者最容易误解的地方。

去标识化不等于绝对安全。

NIST 长期都在强调：

- de-identification 不是单一技术
- 去标识后的数据在某些条件下仍然可能被重新识别

所以：

- `去标识化` 很重要
- 但它通常不是“最强隐私保证”

### 3.4 什么时候适合用

适合：

- 低到中等风险的数据共享
- 内部分析
- 做进一步隐私技术前的预处理

不适合单独用在：

- 高敏感数据
- 多方对账
- 对抗强辅助信息攻击的场景

## 4. 差分隐私（Differential Privacy, DP）

### 4.1 一句话理解

差分隐私是在“发布统计结果或训练模型”时，给个体提供数学上可量化的隐私保护。

OpenDP 对它的解释非常适合初学者：

- 看输出结果时，不应能明显判断某个个体是否在原始数据里

### 4.2 它通常怎么做

最常见的直觉是：

- 对统计结果加噪声

例如：

- 真正购买人数是 1000
- 对外发布时变成 997 或 1006

但 DP 不只是“随便加点噪声”，而是：

- 需要定义隐私单位
- 需要约束每个人最多贡献多少
- 需要跟踪累计隐私损耗

### 4.3 为什么它重要

因为传统匿名化经常挡不住：

- differencing attack
- linkage attack
- 辅助信息重识别

DP 的价值在于：

- 给出更严格、可解释、可累计的风险框架

### 4.4 你需要记住的三个关键词

#### 1. 隐私单位

你在保护谁？

- 一条记录
- 一个用户
- 一个设备
- 一周内某个用户的所有行为

如果这个没定义清楚，DP 方案很容易“看起来很强，实际保护对象不明确”。

#### 2. 贡献上界

一个用户最多能影响多少结果？

如果一个用户能贡献无限多行数据，DP 很难做稳。

#### 3. 隐私预算

DP 不是无限次免费查询。

每次发布结果都会消耗预算。  
问得越多、越细、越频繁，风险越高。

### 4.5 DP 的优点

- 理论强
- 可量化
- 适合统计发布和报表分享
- 适合与其他技术组合

### 4.6 DP 的缺点

- 不直观
- 参数选择难
- 小群体、小样本、高维分析时会明显损失可用性
- 如果产品和运营团队不理解预算管理，很容易误用

### 4.7 什么时候适合用

适合：

- 聚合报表
- benchmark
- 统计共享
- 隐私保护型分析
- 联邦学习后的模型或指标发布

不适合单独解决：

- 多方私密匹配
- 原始数据共享控制
- “谁也不能看到中间明细”的执行约束

## 5. Trusted Execution Environment（TEE）与 Confidential Computing

### 5.1 一句话理解

TEE 是一种硬件支持的“受保护运行环境”，可以在数据正在被处理时保护它。

Google Cloud 官方对 Confidential Computing 的定义很直接：

- 它是对 `data in use` 的保护
- 依赖硬件级的 TEE

也就是：

- 数据静态加密，保护的是存储时
- 传输加密，保护的是传输时
- TEE/Confidential Computing 保护的是“正在计算时”

### 5.2 它解决什么问题

它主要解决：

- 我需要计算数据
- 但不希望宿主机管理员、平台运营者、普通服务进程随意看到明文

### 5.3 它是怎么工作的

初学者只需要抓住两个点：

1. 代码和数据在一个隔离环境里运行
2. 可以通过 `attestation` 远程证明这个环境确实是可信的、代码版本是预期的

### 5.4 TEE 的优点

- 很适合“要算，但不想把明文给平台”的场景
- 工程上通常比纯 MPC 更容易落地
- 很适合作为 clean room、机密分析、联合计算的底层

### 5.5 TEE 的局限

- 不是“万能魔法盒”
- 仍然依赖硬件、实现和运维边界
- 侧信道、防配置错误、日志泄露、输出约束都仍然重要
- 它保护的是“执行环境”，不自动保护“输出结果”

### 5.6 什么时候适合用

适合：

- confidential analytics
- 多方联合计算
- data collaboration
- 在不共享明文前提下运行受限分析代码

## 6. Data Clean Room

### 6.1 一句话理解

clean room 不是某一种单独的密码学算法，而是一种“受控的数据协作环境”。

Google BigQuery 官方的说法很清楚：

- data clean room 是一个安全增强的环境
- 多方可以共享、联结、分析数据
- 但不移动或不暴露底层原始数据

### 6.2 它通常包含什么

一个 clean room 通常会包含：

- 访问控制
- 查询模板或分析规则
- 原始数据不可直接导出
- 聚合阈值
- 审计日志
- 有时再叠加 TEE、DP 或 query review

### 6.3 它解决什么问题

它解决的是：

- 两家或多家机构想联合分析数据
- 但不想直接把明细表互相发来发去

典型场景：

- 广告测量
- 受众洞察
- campaign planning
- 联合研究

### 6.4 它的优点

- 非常贴近业务
- 容易被商业团队理解
- 可以承载多方合作

### 6.5 它的局限

初学者一定要记住：

- clean room 本身不是强隐私保证的同义词

一个 clean room 的隐私强度，取决于：

- 有没有严格查询限制
- 有没有阈值
- 有没有 DP
- 有没有 TEE
- 是否允许导出太细的结果

所以：

- `clean room` 更像“产品/环境形态”
- 不是“某个单独数学性质”

## 7. PSM：Private Set Membership

### 7.1 一句话理解

PSM 用来回答一个很具体的问题：

- 客户端想知道“我的某个标识符是否属于服务端集合”
- 但双方都不想多泄露额外信息

Google 开源仓库 `google/private-membership` 对它的定义非常清楚。

### 7.2 它保护什么

理想目标是：

- 服务端不知道客户端查了什么明文标识符
- 服务端不知道结果是命中还是没命中
- 客户端除了 yes/no 外，不知道服务端集合的其他内容

### 7.3 它适合什么场景

适合：

- 私密查名单
- 私密判断某 token / ID 是否属于某集合
- 某些风控、资格判断、黑名单/白名单类场景

### 7.4 它不适合什么场景

它不擅长：

- 计算交集大小
- 匹配后求和
- 多方归因结算
- 复杂统计分析

如果你要的是：

- “共同用户有多少”
- “共同用户上的 value 总和是多少”

那通常需要的就不是纯 PSM，而是 PSI / PJC 这类技术。

## 8. PSI：Private Set Intersection

### 8.1 一句话理解

PSI 用来解决：

- 两方各有一个集合
- 想知道交集
- 但不想暴露全集

### 8.2 它适合什么场景

适合：

- 重合用户规模估计
- 对账前的安全匹配
- 联合受众分析

### 8.3 它的局限

PSI 常常只是第一步。

因为真实业务里很多时候不只想知道：

- “哪些 ID 重合了”

还想知道：

- 交集上有多少转化
- 交集上的 value sum
- 交集上的某类标签统计

这时 PSI 可能不够，需要上 PJC / PI-Sum。

## 9. PJC / PI-Sum：Private Join and Compute / Private Intersection-Sum

### 9.1 一句话理解

这是“私密匹配之后继续计算”的技术。

Google Research 的多篇论文都直接把它用于广告 conversion measurement。

### 9.2 它能做什么

典型输出包括：

- 交集大小
- 交集 value 总和
- 某些 join 后聚合结果

### 9.3 为什么它重要

它比 PSM、PSI 更贴近很多商业场景，例如：

- 广告转化测量
- matched outcome analysis
- 多方结算

### 9.4 它的代价

- 协议更复杂
- 通信与计算成本更高
- 工程实现门槛更高

## 10. MPC / Secure Computation

### 10.1 一句话理解

MPC（安全多方计算）是一大类方法：

- 多个互不完全信任的参与方
- 一起算一个函数
- 但尽量不暴露各自输入

### 10.2 你可以把它理解成什么

如果普通计算像：

- 大家把数据交给一个中心服务端来算

那 MPC 更像：

- 大家不把完整明文交出去
- 协议本身保证大家只学到允许知道的输出

### 10.3 常见子类

包括但不限于：

- secure aggregation
- garbled circuits
- secret sharing
- 两方或三方安全计算

### 10.4 它适合什么

适合：

- 联邦聚合
- 多方对账
- 私密匹配与结算
- 跨机构联合分析

### 10.5 它的局限

- 通常比普通系统更复杂
- 延迟和成本更高
- 协议选择与威胁模型很关键

### 10.6 一个很实用的特例：Secure Aggregation

Google 关于 federated learning 的论文里，secure aggregation 是一个非常关键的实用子类。

它的目标很朴素：

- 每个设备有一个私有更新值
- 服务端只应看到“聚合和”，不应看到单设备值

这是联邦学习、联邦分析里的常见基础件。

## 11. 同态加密（Homomorphic Encryption, HE）

### 11.1 一句话理解

同态加密允许你：

- 在密文上直接做计算
- 不先解密

Microsoft SEAL 项目页对 HE 的描述很直白：

- 可以直接对加密数据执行计算
- 不需要在过程中解密

### 11.2 为什么它很吸引人

因为它看起来像“最理想的隐私计算”：

- 数据是加密的
- 云端还能算

### 11.3 它的现实情况

要冷静一点：

- HE 很强
- 但通常也更重、更慢、更难调优

不是所有业务都适合直接上全功能 HE。

很多时候会用：

- 部分同态
- 有限运算深度
- 与其他协议混搭

### 11.4 它适合什么

适合：

- 一些固定结构的聚合或求和
- 某些安全统计和查询
- 部分私密机器学习场景

### 11.5 它不适合什么

不适合一上来就当成：

- 所有隐私问题的默认答案

## 12. 联邦学习（Federated Learning, FL）

### 12.1 一句话理解

联邦学习是：

- 数据留在设备或本地节点
- 只上传模型更新或统计更新
- 再由服务端聚合

TensorFlow Federated 官方文档的核心思想也是：

- 数据是分散的
- 计算以聚合形式进行

### 12.2 它解决什么问题

它解决的是：

- 我想训练模型
- 但不想把所有原始训练数据先集中收集到服务器

### 12.3 它不自动保证什么

这是非常关键的一点：

- FL 不等于自动隐私安全

为什么？

因为模型更新本身也可能泄露信息。

所以真实系统里，FL 往往还要配：

- secure aggregation
- differential privacy
- participant sampling
- auditing

### 12.4 什么时候适合用

适合：

- 设备侧个性化
- 分布式模型训练
- 不便集中收集训练数据的场景

## 13. 联邦分析（Federated Analytics）

### 13.1 一句话理解

联邦分析和联邦学习很像，但它的目标通常不是训练模型，而是：

- 统计
- 计数
- 分桶
- 报表

### 13.2 它和联邦学习的区别

- 联邦学习：更偏模型训练
- 联邦分析：更偏指标计算和统计洞察

### 13.3 常见组合

联邦分析常常和下面几类技术配合：

- secure aggregation
- differential privacy
- TEE / confidential federated computations

## 14. Clean Room、TEE、MPC、DP 到底是什么关系

初学者最容易混淆这几个词。

可以这样记：

### 14.1 Clean Room

更像：

- 受控合作环境
- 产品形态

### 14.2 TEE

更像：

- 受保护执行环境
- 基础设施能力

### 14.3 MPC / HE / PSM / PSI / PJC

更像：

- 密码学协议或原语
- 具体计算方法

### 14.4 DP

更像：

- 输出发布层的数学隐私保证

一句话总结：

- `clean room` 决定合作怎么组织
- `TEE / MPC / HE` 决定数据怎么算
- `DP` 决定结果怎么安全发布

## 15. 初学者最常见的误区

### 误区 1：匿名化了就安全了

不一定。  
很多匿名化数据在有辅助信息时仍可被重识别。

### 误区 2：联邦学习天然隐私

不一定。  
没有 secure aggregation 和 DP，模型更新也可能泄露信息。

### 误区 3：clean room 等于密码学安全

不一定。  
如果查询限制很弱，仍可能泄露很多信息。

### 误区 4：TEE 等于什么都不用担心

不对。  
TEE 解决的是“执行中保护”，不是一切问题的终点。

### 误区 5：DP 只要加点噪声就行

不对。  
DP 需要明确：

- 保护对象
- 贡献上界
- 预算管理
- 发布策略

### 误区 6：密码学协议越强越应该默认用

不一定。  
越强往往越复杂、越贵、越慢。  
工程上通常要在：

- 风险
- 性能
- 成本
- 可解释性

之间找平衡。

## 16. 如何为一个业务问题选技术

这里给你一个非常实用的简化版决策树。

### 如果你的问题是：

#### “我想分享统计结果，但不想泄露个人信息”

优先想：

- DP
- 阈值
- 聚合发布

#### “我想让两家公司联合分析，但不互发原始表”

优先想：

- clean room
- TEE
- PSI / PJC
- 再叠加 DP

#### “我想在设备侧训练模型，不想收原始数据”

优先想：

- federated learning
- secure aggregation
- user-level DP

#### “我只想判断某个 ID 是否属于一个远端集合”

优先想：

- PSM

#### “我想知道双方共同用户有多少 / 共同价值和是多少”

优先想：

- PSI
- PJC / PI-Sum

#### “我想在不暴露明文数据的情况下做计算”

优先想：

- TEE
- MPC
- HE

具体选哪个，看：

- 参与方之间的信任程度
- 对性能的要求
- 数据规模
- 是否需要实时

## 17. 给初学者的推荐学习顺序

如果你现在是小白，我建议按这个顺序学。

### 第一步：先学概念，不要先学公式

先把这几个问题想清楚：

- 我保护谁
- 我怕谁
- 我保护输入、执行过程，还是输出

### 第二步：先掌握四个最重要的词

- de-identification
- DP
- clean room
- TEE

这四个词能帮你看懂大量业务方案。

### 第三步：再学集合和匹配类协议

- PSM
- PSI
- PJC / PI-Sum

这类技术在广告测量、联合分析、对账里特别常见。

### 第四步：最后再学联邦与高阶密码学

- federated learning
- secure aggregation
- MPC
- HE

## 16A. 隐私技术选型表

这一节把常见技术放到一张更适合产品和工程讨论的表里。为了方便理解，这里的“性能”是粗粒度判断，不是严格 benchmark。

| 技术 | 核心优点 | 核心缺点 | 性能/工程代价 | 最适合场景 | 不适合单独解决的问题 |
| --- | --- | --- | --- | --- | --- |
| 去标识化 / 数据最小化 | 简单、直观、低成本、几乎所有项目都该先做 | 不能提供强数学保证，仍可能被重识别 | 低 | 内部分析、共享前预处理、低风险数据交换 | 高敏感多方协作、强攻击者场景 |
| 差分隐私 DP | 有数学保证，适合安全发布统计结果 | 参数难、预算难、样本小或维度高时噪声大 | 中 | 聚合报表、benchmark、模型/统计发布 | 私密匹配、执行环境保护 |
| TEE / Confidential Computing | 非常适合“要算但不想暴露明文”的场景，工程上比纯 MPC 更易落地 | 依赖硬件和实现边界，输出仍可能泄露，需要 attestation 和治理 | 中 | clean room、联合计算、机密分析、受控执行 | 单靠它不能保证发布结果安全 |
| Data Clean Room | 业务上容易理解，便于多方合作，能承载治理规则 | 不是单一强隐私原语，强度取决于规则、阈值、是否叠加 TEE/DP | 中 | 广告测量、联合分析、合作报表 | 没有强查询限制时容易泄露 |
| PSM | 很适合 yes/no 资格判断，信息暴露面小 | 只能回答 membership，不适合复杂聚合 | 中 | 私密查名单、资格校验、claim gating | 求交集大小、求和、复杂归因 |
| PSI | 适合私密求交，适合先做安全匹配 | 常常只够做第一步，业务上经常还要继续算值 | 中到高 | 用户重合分析、受众 overlap、对账前匹配 | 交集求和、复杂 value attribution |
| PJC / PI-Sum | 很贴近广告测量和联合结算，能在交集上求和/聚合 | 协议更复杂、工程成本更高 | 高 | conversion measurement、matched outcome、settlement | 实时、高频、低延迟的通用分析 |
| MPC / Secure Computation | 多方信任假设最弱，适合强隐私联合计算 | 实现复杂、成本高、延迟高、产品团队不易理解 | 高 | 多方结算、联合分析、私密归因 | 低预算、强实时、快速试点 |
| 同态加密 HE | 可以对密文直接计算，隐私故事很强 | 通常更重、更慢、适用运算受限 | 高 | 某些求和、统计、固定结构查询 | 通用实时系统、复杂任意业务逻辑 |
| 联邦学习 FL | 不必集中原始训练数据，适合分布式训练 | 不自带完全隐私，需要 secure aggregation / DP 等配套 | 中到高 | 设备侧模型训练、分布式学习 | 私密数据共享、报表发布 |
| 联邦分析 FA | 适合不集中数据的统计分析 | 粒度和查询形式受限，仍需 secure aggregation/DP | 中 | 分布式指标统计、设备侧分析 | 复杂多方匹配、任意交互式分析 |

### 16A.1 一个非常实用的简化结论

如果你只想先抓住每类技术最典型的“擅长点”，可以先记成下面这几句：

- 去标识化：`先把敏感程度降下来`
- DP：`安全发布统计结果`
- TEE：`让数据在运行时也尽量受保护`
- clean room：`让多方能在受控环境里合作`
- PSM：`安全地回答 yes/no`
- PSI：`安全地找共同集合`
- PJC / PI-Sum：`安全地匹配后再算总和`
- MPC：`多方一起算，但尽量不暴露输入`
- HE：`对加密数据直接算`
- FL / FA：`数据不集中，计算结果回来`

## 16B. Mock 数据例子：用数据流理解这些技术

这一节不追求数学严谨，而是用最小 mock 数据把“data flow 长什么样”讲清楚。

### 16B.1 去标识化 / 数据最小化

原始表：

```text
user_id | email              | city        | exact_ts             | purchase_value
u1      | a@example.com      | San Jose    | 2026-04-19 10:01:12  | 9.99
u2      | b@example.com      | San Jose    | 2026-04-19 10:03:44  | 19.99
u3      | c@example.com      | Santa Clara | 2026-04-19 10:04:10  | 4.99
```

做完最小化后可能变成：

```text
pseudo_id | region     | time_bucket        | purchase_bucket
p_u1      | Bay Area   | 2026-04-19 10:00h  | 0-10
p_u2      | Bay Area   | 2026-04-19 10:00h  | 10-20
p_u3      | Bay Area   | 2026-04-19 10:00h  | 0-10
```

你能直观看到：

- 邮箱没了
- 精确城市变成大区域
- 秒级时间变成小时桶
- 精确金额变成区间

它的作用是：

- 减少直接敏感度

但注意：

- 这仍然不是最强隐私

### 16B.2 差分隐私 DP

真实统计：

```text
campaign A purchases = 100
campaign B purchases = 12
```

发布时可能变成：

```text
campaign A purchases = 103
campaign B purchases = 9
```

Data flow 可以理解为：

1. 先算真实聚合值
2. 控制每个用户最大贡献
3. 再按 DP 机制加噪声
4. 对外只发加噪结果

适合你脑子里的画面是：

```text
Raw data -> Aggregate count -> Clip contribution -> Add noise -> Publish
```

### 16B.3 TEE / Confidential Computing

假设两家公司 A 和 B 都不想直接把明文给对方，但想算联合报表。

公司 A 数据：

```text
user_id | campaign | value
u1      | c1       | 10
u2      | c1       | 20
```

公司 B 数据：

```text
user_id | retained_d7
u1      | 1
u2      | 0
```

在 TEE 模式下，直觉式 data flow 是：

1. A 把受限输入送入 TEE
2. B 把受限输入送入 TEE
3. TEE 内部跑批准过的 join/aggregate 逻辑
4. 只输出：

```text
campaign c1:
- users = 2
- retained_d7 = 1
- average_value = 15
```

关键点：

- 明细不是直接给对方
- 但最终仍然能算出联合结果

### 16B.4 Clean Room

可以把 clean room 想象成“带规则的联合分析房间”。

公司 A：

```text
campaign | installs
c1       | 1000
c2       | 500
```

公司 B：

```text
campaign | d7_retained
c1       | 300
c2       | 220
```

clean room 中允许的 SQL/分析结果可能只有：

```text
campaign | installs | d7_retained | d7_retention
c1       | 1000     | 300         | 0.30
c2       | 500      | 220         | 0.44
```

但不允许：

- 导出原始 user-level rows
- 查样本太小的群体
- 任意组合探测

所以 clean room 的 data flow 更像：

```text
Party A data \
             -> governed environment -> approved aggregate query -> result
Party B data /
```

### 16B.5 PSM

服务端集合：

```text
{token_1, token_3, token_9}
```

客户端想问：

```text
Is token_3 in the set?
```

输出只有：

```text
yes
```

理想情况下：

- 服务端不知道你查的是 `token_3`
- 客户端也不知道集合里还有 `token_1` 和 `token_9`

这就是最典型的 yes/no data flow。

### 16B.6 PSI

公司 A 集合：

```text
{u1, u2, u3, u4}
```

公司 B 集合：

```text
{u2, u4, u5}
```

输出交集：

```text
{u2, u4}
```

或者只输出交集大小：

```text
2
```

这是最基础的“先匹配上谁重合了”。

### 16B.7 PJC / PI-Sum

公司 A：

```text
u1
u2
u3
u4
```

公司 B：

```text
u2 -> 10
u3 -> 20
u5 -> 5
```

输出可能是：

```text
intersection cardinality = 2
intersection sum = 30
```

其中交集是 `u2, u3`，对应 value sum 是 `10 + 20`。

这就是：

- 先 join
- 再 compute

### 16B.8 联邦学习

假设 3 台设备各自本地训练一个小更新。

设备 1：

```text
gradient = [0.2, -0.1]
```

设备 2：

```text
gradient = [0.0, -0.2]
```

设备 3：

```text
gradient = [0.1, 0.1]
```

服务端最终看到的理想结果是聚合值：

```text
sum = [0.3, -0.2]
```

而不是单台设备的明细梯度。

这就是联邦学习最经典的 data flow：

```text
local training -> local update -> secure aggregation -> global update
```

### 16B.9 Confidential Federated Analytics / Provably Private Insights

这是 2025-2026 很值得初学者关注的一层，因为它把：

- 设备侧数据最小化
- TEE 中的受控处理
- 可验证的软件供应链 / attestation
- 最终 DP 发布

叠成了一个可以真正落地的 AI 时代分析链路。

一个最小 mock 例子：

设备端原始数据：

```json
{
  "device_id": "dev_7f3a",
  "feature": "recorder_summary",
  "user_opt_in": true,
  "local_artifact": {
    "transcript": "need to buy charger before flight",
    "lang": "en",
    "ts_bucket": "2026-04-20T10"
  }
}
```

设备实际上传的不是“开放式原文给分析师”，而更像：

```json
{
  "ciphertext": "base64:7Yh...",
  "workflow_digest": "sha256:ppi-workflow-v3",
  "policy": {
    "allowed_purpose": "topic_histogram",
    "retention": "ephemeral",
    "approved_output": "dp_histogram_only"
  }
}
```

TEE 内允许执行的步骤：

```json
[
  {"step": 1, "name": "decrypt_in_tee"},
  {"step": 2, "name": "llm_classify_topic", "model": "gemma-3-4b"},
  {"step": 3, "name": "clip_user_contribution", "max_topics": 1},
  {"step": 4, "name": "dp_histogram", "epsilon": 1.0},
  {"step": 5, "name": "publish_aggregate_only"}
]
```

最终对外输出：

```json
{
  "feature": "recorder_summary",
  "window": "2026-W16",
  "topic_histogram_dp": {
    "reminder": 128,
    "meeting": 94,
    "travel": 51
  }
}
```

它最值得你记住的 data flow 是：

```text
device local raw data
-> device chooses what to upload
-> encrypt with workflow constraint
-> TEE attests approved code
-> LLM or analytics step runs inside TEE
-> DP aggregate only
-> publish
```

### 16B.10 Private Cloud AI Inference

如果你想理解 Apple PCC 或类似 private AI compute 方案，可以先看最小请求格式。

设备请求：

```json
{
  "request_id": "req_20260420_001",
  "task": "rewrite_email",
  "prompt": "rewrite this to sound more concise",
  "private_context": {
    "draft": "Hi team, I wanted to follow up regarding the launch timeline..."
  },
  "target_model": "large-cloud-model",
  "policy": {
    "no_storage": true,
    "no_training_use": true
  }
}
```

发送前，设备会先验证远端节点身份与可验证软件版本；到服务端后，理想化的处理边界是：

```json
{
  "attested_node": "pcc-node-18",
  "build_measurement": "pcc-release-2025-10-24",
  "allowed_runtime": [
    "request_decrypt",
    "model_inference",
    "response_encrypt"
  ],
  "disallowed_runtime": [
    "shell_access",
    "general_purpose_logging",
    "debug_dump_user_payload"
  ]
}
```

最终返回：

```json
{
  "request_id": "req_20260420_001",
  "output": "Following up on the launch timeline. Please share the latest target date and blockers.",
  "server_trace": "ephemeral"
}
```

对初学者来说，这类方案的关键不是“云上 AI 也能算”，而是：

- 设备先验真再发送
- 节点只能跑被公开/可验证的软件
- 管理员权限不应等于可读用户明文
- 输出仍然要单独治理，不能把“执行安全”误当成“结果天然安全”

### 16B.11 DP Synthetic Data with LLM Inference

Google Research 在 2025 年给了一个很适合写进 primer 的方向：不用重新训练大模型，也能用推理式流程做 DP synthetic data。

敏感种子样本：

```json
[
  {"age_band": "25-34", "condition": "asthma", "drug": "A"},
  {"age_band": "35-44", "condition": "asthma", "drug": "B"},
  {"age_band": "25-34", "condition": "diabetes", "drug": "C"}
]
```

推理式生成链路可以抽象成：

```text
sensitive seed rows
-> many parallel prompts to base LLM
-> candidate synthetic rows
-> DP aggregation / filtering
-> release synthetic dataset
```

一个极简输出例子：

```json
[
  {"age_band": "25-34", "condition": "asthma", "drug": "A_like", "count_dp": 11},
  {"age_band": "35-44", "condition": "asthma", "drug": "B_like", "count_dp": 8},
  {"age_band": "25-34", "condition": "diabetes", "drug": "C_like", "count_dp": 7}
]
```

### 16B.12 组合式系统的 End-to-End Mock Data

很多初学者看懂单个 PET 之后，还是不知道真实系统里“数据到底怎么流”。下面给 3 个更接近生产系统的 mock data。

#### 例子 A：Confidential Federated Analytics / PPI

设备侧事件：

```json
{
  "device_id": "dev_e91f",
  "feature": "smart_reply",
  "event_ts": "2026-04-21T08:15:00Z",
  "raw_artifact": {
    "prompt_class": "email_reply",
    "draft_language": "en",
    "llm_output": "Thanks, I can do Thursday afternoon."
  }
}
```

上传到服务端前，设备把原始内容压成受策略约束的密文包：

```json
{
  "ciphertext": "base64:AbCd...",
  "policy_id": "ppi-smart-reply-v1",
  "allowed_workflow_digest": "sha256:workflow_20260421",
  "privacy_unit": "device_week",
  "max_contribution": 1
}
```

TEE 中允许执行的步骤：

```json
[
  {"step": 1, "name": "decrypt"},
  {"step": 2, "name": "llm_extract_topic", "output_schema": {"topic": "string"}},
  {"step": 3, "name": "clip", "rule": "one topic per privacy unit"},
  {"step": 4, "name": "aggregate"},
  {"step": 5, "name": "release_dp_histogram", "epsilon": 1.1, "delta": 1e-6}
]
```

最终可发布结果：

```json
{
  "feature": "smart_reply",
  "window": "2026-W17",
  "topic_histogram_dp": {
    "meeting_coordination": 183,
    "follow_up": 91,
    "travel_planning": 24
  }
}
```

这里最重要的是把数据流拆成 4 层：

- `原始内容在设备侧`
- `上传的是受限密文包`
- `TEE 中只允许运行白名单 workflow`
- `对外只放 DP 聚合结果`

#### 例子 B：Clean Room + Analysis Rules

广告主侧表：

```text
hashed_email | campaign_id | purchase_value | purchase_date
h1           | c7          | 39.99          | 2026-04-20
h2           | c7          | 14.50          | 2026-04-20
h3           | c9          | 72.10          | 2026-04-21
```

媒体侧表：

```text
hashed_email | placement_id | impression_cnt | click_cnt
h1           | p3           | 12             | 1
h3           | p9           | 5              | 1
h4           | p3           | 8              | 0
```

clean room 规则：

```json
{
  "join_key": "hashed_email",
  "analysis_rule": "differential_privacy",
  "aggregation_threshold": 50,
  "allowed_dimensions": ["campaign_id", "placement_id"],
  "disallowed_outputs": ["hashed_email", "row_level_export"],
  "epsilon_budget": 8.0,
  "delta_budget": 1e-6
}
```

允许的查询形态：

```sql
SELECT
  campaign_id,
  placement_id,
  COUNT(*) AS matched_users,
  SUM(purchase_value) AS revenue
FROM joined_view
GROUP BY 1, 2
```

外部能拿到的结果更像：

```text
campaign_id | placement_id | matched_users_dp | revenue_dp
c7          | p3           | 86               | 2419.3
c9          | p9           | 64               | 1930.8
```

这说明 clean room 不是“数据不动就安全了”，而是：

- `join 怎么做` 被约束
- `query 怎么写` 被约束
- `什么不能导出` 被约束
- `预算能用多少次` 被约束

### 16B.13 Clean Room Synthetic Data / 协作建模的 Mock Data

如果你想把 privacy tech 用到“联合建模、但又不共享原始训练样本”的场景，可以把系统想成下面这条链路。

参与方原始表：

```json
{
  "airline_bookings": [
    {"join_id": "h:01", "tier": "gold", "route": "SFO-HND", "spend_usd": 1800, "booked": 1},
    {"join_id": "h:02", "tier": "silver", "route": "LAX-JFK", "spend_usd": 420, "booked": 1}
  ],
  "hotel_stays": [
    {"join_id": "h:01", "city": "Tokyo", "nights": 3, "ancillary_spend_usd": 260, "converted": 1},
    {"join_id": "h:77", "city": "New York", "nights": 1, "ancillary_spend_usd": 90, "converted": 0}
  ]
}
```

进入 clean room 后，双方通常不会直接导出 join 后明细，而是先声明模板和输出边界：

```json
{
  "template_id": "joint-promo-synth-v1",
  "join_key": "join_id",
  "output_mode": "synthetic_only",
  "column_types": {
    "tier": "categorical",
    "route": "categorical",
    "city": "categorical",
    "spend_usd": "numerical",
    "nights": "numerical",
    "converted": "categorical"
  },
  "privacy_controls": {
    "epsilon": 3.0,
    "privacy_threshold": 20,
    "data_access_budget": {
      "lifetime_runs": 10,
      "monthly_runs": 4
    }
  }
}
```

平台执行时更像是在跑一个受控作业，而不是把明细表交给训练代码：

```json
[
  {"step": 1, "name": "join_under_policy"},
  {"step": 2, "name": "apply_thresholding_and_preprocessing"},
  {"step": 3, "name": "generate_synthetic_training_rows"},
  {"step": 4, "name": "emit_synthetic_output_only"},
  {"step": 5, "name": "decrement_access_budget"},
  {"step": 6, "name": "publish_audit_metrics"}
]
```

训练代码真正看到的可能是下面这种 synthetic dataset：

```json
[
  {"tier": "gold", "route": "SFO-HND", "city": "Tokyo", "spend_usd_bucket": "1500-1999", "nights": 3, "converted": 1},
  {"tier": "silver", "route": "LAX-JFK", "city": "New York", "spend_usd_bucket": "300-499", "nights": 1, "converted": 0},
  {"tier": "gold", "route": "SEA-HND", "city": "Tokyo", "spend_usd_bucket": "1500-1999", "nights": 4, "converted": 1}
]
```

而治理/运维侧更关心的是这类元数据：

```json
{
  "job_id": "crml_job_20260422_01",
  "template_id": "joint-promo-synth-v1",
  "result_type": "synthetic_dataset",
  "rows_emitted": 50000,
  "remaining_access_budget": {
    "lifetime_runs": 9,
    "monthly_runs": 3
  },
  "monitoring": {
    "cloudwatch_metrics_enabled": true,
    "query_runtime_ms": 8420
  }
}
```

这个例子要帮助初学者看懂 5 件事：

- `训练代码` 不一定接触真实 join 后样本
- `synthetic output only` 是产品策略，不只是模型技巧
- `epsilon / threshold` 和 `access budget` 是两种不同控制面
- `审计与监控` 已经是生产 clean room 的一部分
- `可落地 privacy tech` 往往同时包含数据、策略、执行和运维

#### 例子 C：Private Cloud AI Inference

设备提交请求：

```json
{
  "request_id": "req_20260421_019",
  "attested_service": "private-cloud-ai-v2",
  "task": "summarize_notes",
  "private_context": {
    "notes": [
      "Customer asked to delay renewal to May 1.",
      "Security review still blocked on DPA."
    ]
  },
  "policy": {
    "retain_logs": false,
    "allow_training": false,
    "max_ttl_seconds": 300
  }
}
```

服务端执行策略：

```json
{
  "measurement": "sha256:pcc_style_build_202604",
  "debug_interfaces": [],
  "egress_filters": ["model_output_only"],
  "audit_record": "ephemeral_request_metadata_only"
}
```

返回结果：

```json
{
  "request_id": "req_20260421_019",
  "summary": "Renewal moved to May 1; security review is blocked on the DPA.",
  "retention": "not_stored"
}
```

如果你从系统设计角度看，这类方案的关键不是“模型在云上”，而是：

- `请求前先验真`
- `执行镜像可审计`
- `运行时接口受限`
- `日志和训练回流默认被禁`

它适合写进你的心智模型里，因为它说明：

- synthetic data 不是天然安全
- LLM 也不是天然隐私
- 真正可落地的是“LLM inference + DP aggregation/filtering”的组合

### 16B.14 Reasoning-Driven Synthetic Data / Dataset Mechanism Design 的 Mock Data

如果你想理解 2026 年 synthetic data 的一个新趋势，可以把它想成：不是“从几条 seed row 出发，逐条仿写”，而是先设计整个数据集该长什么样，再去生成样本。

一个面向隐私敏感客服场景的输入，不一定直接是原始聊天记录，也可能先被抽象成一个“数据集设计任务”：

```json
{
  "dataset_goal": "train_support_classifier",
  "domain": "refund_and_account_recovery",
  "privacy_mode": "synthetic_first",
  "target_axes": {
    "coverage": ["refund", "chargeback", "account_lock", "2fa_reset"],
    "complexity": ["simple", "multi-turn", "policy_edge_case"],
    "quality": ["schema_valid", "policy_consistent", "label_verified"]
  },
  "hard_constraints": {
    "forbid_raw_chat_export": true,
    "allow_seedless_generation": true,
    "release_format": "jsonl"
  }
}
```

系统先产出的可能不是样本，而是一个 taxonomy / scaffold：

```json
{
  "taxonomy": [
    {
      "topic": "refund",
      "subtopics": ["duplicate_charge", "late_delivery", "policy_exception"]
    },
    {
      "topic": "account_lock",
      "subtopics": ["suspicious_login", "device_change", "travel_false_positive"]
    }
  ],
  "sampling_plan": {
    "global_diversity_target": 0.9,
    "local_variants_per_leaf": 8,
    "complex_case_ratio": 0.35
  }
}
```

随后才进入 meta-prompt 和实例化阶段：

```json
[
  {
    "leaf": "refund.policy_exception",
    "meta_prompt": "customer asks for refund outside standard window after a delivery outage",
    "variants": 8
  },
  {
    "leaf": "account_lock.travel_false_positive",
    "meta_prompt": "customer locked out after travel-triggered risk rule",
    "variants": 8
  }
]
```

最终给训练或评测系统的 synthetic rows 可能长这样：

```json
[
  {
    "scenario_id": "syn_001",
    "intent": "refund",
    "complexity": "multi-turn",
    "user_message": "I am outside the refund window, but the outage delayed the shipment by 9 days.",
    "policy_label": "manual_review",
    "quality_checks": ["schema_valid", "critic_pass"]
  },
  {
    "scenario_id": "syn_002",
    "intent": "account_recovery",
    "complexity": "policy_edge_case",
    "user_message": "I changed phones while traveling and now every login looks suspicious.",
    "policy_label": "step_up_auth",
    "quality_checks": ["schema_valid", "critic_pass"]
  }
]
```

而真正决定它能不能落地的，往往是这类控制与评测元数据：

```json
{
  "generation_run_id": "simula_style_20260424_01",
  "release_decision": "internal_only",
  "evaluation": {
    "taxonomic_coverage": 0.93,
    "complexity_score": 0.71,
    "critic_disagreement_rate": 0.04
  },
  "governance": {
    "seed_data_required": false,
    "human_review_sample_rate": 0.05,
    "raw_sensitive_logs_retained": false
  }
}
```

这个 mock data 要说明的是：

- 新一代 synthetic data 系统越来越像 `dataset control plane`
- 控制点从“单条像不像真数据”转向“覆盖、复杂度、质量能不能分别调”
- 对 privacy-sensitive AI 来说，`不导出原始语料 + 先设计数据集结构` 往往比单纯仿写几条样本更重要

### 16B.15 Operational Privacy Control Plane / 双预算与事件流的 Mock Data

如果你已经理解了 DP、clean room、synthetic data 和 TEE，下一步最容易缺失的直觉其实不是“还有什么算法”，而是“这些能力怎么变成一个可长期运行的系统”。

下面这个 mock data 故意不强调模型本身，而强调治理与运维面。

协作创建时的控制面配置：

```json
{
  "collaboration_id": "cr_20260425_ads_measurement",
  "members": [
    {"role": "publisher", "account": "pub-west"},
    {"role": "advertiser", "account": "adv-central"},
    {"role": "measurement_partner", "account": "meas-lab"}
  ],
  "query_template": {
    "template_id": "campaign_lift_v4",
    "join_keys": ["hashed_email", "device_cohort_id"],
    "allowed_dimensions": ["campaign_id", "geo_region", "week"],
    "blocked_dimensions": ["raw_timestamp", "full_zip"]
  },
  "release_controls": {
    "aggregation_threshold": 50,
    "differential_privacy": {
      "epsilon": 1.2,
      "delta": 1e-6,
      "privacy_unit": "user_30d"
    }
  },
  "budgets": {
    "privacy_budget": {
      "monthly_epsilon_cap": 8.0,
      "remaining_epsilon": 5.6
    },
    "access_budget": {
      "monthly_query_cap": 40,
      "remaining_queries": 27
    }
  },
  "ops": {
    "cloudwatch_metrics": true,
    "eventbridge_events": true,
    "result_receivers": ["publisher", "advertiser"]
  }
}
```

一次分析请求：

```json
{
  "analysis_run_id": "run_20260425_0042",
  "template_id": "campaign_lift_v4",
  "requested_breakdown": ["campaign_id", "week"],
  "filters": {
    "geo_region": ["US-WEST", "US-SOUTH"],
    "campaign_type": ["video"]
  },
  "requested_metrics": [
    "matched_reach",
    "dp_conversion_count",
    "dp_revenue_sum"
  ]
}
```

执行前的策略检查：

```json
{
  "policy_check": "pass",
  "reasons": [
    "template_allowed",
    "dimensions_allowed",
    "remaining_privacy_budget_sufficient",
    "remaining_access_budget_sufficient"
  ],
  "budget_effect": {
    "epsilon_to_spend": 0.7,
    "access_budget_to_spend": 1
  }
}
```

可发布结果：

```json
[
  {
    "campaign_id": "c7",
    "week": "2026-W17",
    "matched_reach": 1184,
    "dp_conversion_count": 86,
    "dp_revenue_sum": 2419.3
  },
  {
    "campaign_id": "c9",
    "week": "2026-W17",
    "matched_reach": 903,
    "dp_conversion_count": 64,
    "dp_revenue_sum": 1930.8
  }
]
```

系统发出的事件与监控元数据：

```json
[
  {
    "event_type": "analysis.completed",
    "analysis_run_id": "run_20260425_0042",
    "delivered_to": ["publisher", "advertiser"]
  },
  {
    "event_type": "budget.updated",
    "remaining_epsilon": 4.9,
    "remaining_queries": 26
  },
  {
    "metric_namespace": "CleanRoom/Queries",
    "query_runtime_ms": 5310,
    "bytes_scanned_gb": 12.4
  }
]
```

如果分析不是简单 SQL，而是 PySpark / Spark workload，控制面还会出现算力与运行参数：

```json
{
  "analysis_template": "clinical_outcome_model_v2",
  "engine": "pyspark",
  "worker_compute": {
    "instance_type": "r6i.4xlarge",
    "workers": 8,
    "spark_properties": {
      "spark.executor.memoryOverhead": "4096",
      "spark.sql.shuffle.partitions": "800",
      "spark.task.maxFailures": "3",
      "spark.network.timeout": "600s"
    }
  },
  "privacy_controls": {
    "analysis_rule": "custom",
    "approved_by_members": ["hospital_a", "pharma_b"],
    "output_policy": "aggregate_only"
  }
}
```

这类参数看起来像普通数据工程配置，但在 privacy system 里很关键：

- large-scale clean room 不只要“能保护”，还要“跑得完、成本可控、失败可诊断”
- Spark 参数本身不提供隐私保证，但决定受控分析能不能承载真实生产 workload
- 这也是为什么 2026 年的 clean room 产品越来越像 `隐私治理 + 数据工程运行时`

这个例子真正要让你记住的是：

- 真实系统里通常不只有 `privacy budget`，还会有 `access budget`
- `模板约束`、`可发布维度`、`结果接收方` 也是一等控制面
- `事件流 + 监控` 决定它能不能接进长期运营系统
- 很多所谓“已落地的 privacy tech”本质上是 `PET + governance + observability`

### 16B.16 Clinical LLM + DP / 医疗文本生成的 Mock Data

2026 年关于 clinical LLM 的研究有一个很现实的信号：隐私控制不再只是“训练时加噪声”，而是开始细化到输入敏感度、分层预算、实时审计和生成过程的泄漏响应。

假设医院想用 LLM 生成出院小结，但不希望模型把患者身份、诊断细节或罕见组合泄漏出去。

原始请求：

```json
{
  "request_id": "clin_20260428_019",
  "patient_id": "p_884291",
  "task": "discharge_summary",
  "input_tokens": [
    {"text": "Jane Doe", "category": "patient_identifier"},
    {"text": "47-year-old", "category": "demographics"},
    {"text": "HER2-positive breast cancer", "category": "diagnosis"},
    {"text": "trastuzumab", "category": "medication"},
    {"text": "nausea improved after dose adjustment", "category": "clinical_note"}
  ]
}
```

进入模型前，系统先做敏感度标注和预算分配：

```json
{
  "privacy_unit": "patient_episode",
  "dp_accountant": "rdp",
  "budget_policy": {
    "patient_identifier": {"epsilon_cap": 0.02, "noise_multiplier": 2.8},
    "diagnosis": {"epsilon_cap": 0.08, "noise_multiplier": 1.9},
    "demographics": {"epsilon_cap": 0.05, "noise_multiplier": 2.2},
    "clinical_note": {"epsilon_cap": 0.12, "noise_multiplier": 1.4}
  },
  "sequence_policy": {
    "max_tokens": 512,
    "adaptive_clipping": true,
    "risk_score_threshold": 0.72
  }
}
```

生成中，审计模块持续检查输出风险：

```json
[
  {
    "step": 64,
    "leakage_risk_score": 0.31,
    "action": "continue"
  },
  {
    "step": 147,
    "leakage_risk_score": 0.78,
    "trigger": "rare_diagnosis_plus_demographic_combo",
    "action": "increase_noise_and_generalize"
  }
]
```

最终发布的内容不再带可识别细节：

```json
{
  "request_id": "clin_20260428_019",
  "released_summary": "The patient completed treatment for a breast cancer subtype and tolerated therapy after medication adjustment. Follow-up oncology care is recommended.",
  "privacy_spend": {
    "epsilon_spent": 0.19,
    "delta": 1e-6,
    "privacy_unit": "patient_episode"
  },
  "audit_result": {
    "membership_inference_risk": "low",
    "pii_detected": false,
    "rare_combo_generalized": true
  }
}
```

这个 mock data 想表达的不是“医疗 LLM 已经完全解决”，而是一个更稳的工程判断：

- LLM 场景里要先定义 `privacy unit`，否则 example-level DP 很可能保护不到真实患者
- 文本生成要考虑 token / section / patient episode 的组合消耗
- 对高敏场景，`实时审计 + 输出泛化 + 预算记账` 比单纯声明“用了 DP”更接近可落地系统

### 16B.17 Federated Credit Risk / 金融联邦风控的 Mock Data

另一个 2026 年研究信号来自金融场景：联邦学习本身不能自动防止梯度泄漏，真实系统往往要在 `standard FL`、`DP-FL` 和 `HE-FL` 之间权衡准确率、计算开销、可审计性和合规要求。

五家银行参与训练时，每家只保留本地贷款数据：

```json
[
  {
    "bank_id": "bank_a",
    "local_rows": 180000,
    "features": ["income_bucket", "loan_amount", "credit_score", "asset_value", "default_label"]
  },
  {
    "bank_id": "bank_b",
    "local_rows": 95000,
    "features": ["income_bucket", "loan_amount", "credit_score", "asset_value", "default_label"]
  }
]
```

训练配置可以明确写成三种模式：

```json
{
  "model": "logistic_regression_credit_risk",
  "rounds": 5,
  "local_epochs": 1000,
  "modes": {
    "standard_fl": {
      "privacy_control": "none",
      "expected_risk": "model_update_leakage"
    },
    "dp_fl": {
      "mechanism": "gaussian",
      "accountant": "renyi_dp",
      "candidate_epsilon": [14.13, 8.65, 5.74],
      "clip_norm": 1.0
    },
    "he_fl": {
      "scheme": "ckks",
      "encrypted_aggregation": true,
      "expected_tradeoff": "higher_compute_overhead"
    }
  }
}
```

一次训练回合里，客户端上传的不是原始申请人数据：

```json
{
  "round": 3,
  "client_update": {
    "bank_id": "bank_a",
    "mode": "dp_fl",
    "clipped_gradient_norm": 1.0,
    "noise_sigma": 1.35,
    "epsilon_spent_to_date": 8.65
  }
}
```

聚合后，模型评估报告应该同时写准确率和隐私 / 成本：

```json
[
  {"mode": "standard_fl", "accuracy": 0.91, "privacy_guarantee": "none", "compute_overhead": "low"},
  {"mode": "dp_fl", "accuracy": 0.88, "privacy_guarantee": "formal_dp", "compute_overhead": "medium"},
  {"mode": "he_fl", "accuracy": 0.90, "privacy_guarantee": "encrypted_aggregation", "compute_overhead": "high"}
]
```

这类场景给初学者的关键直觉是：

- FL 解决的是“数据不集中”，不自动解决“更新不泄漏”
- DP 更像可量化的泄漏上界，HE 更像计算过程中的机密性保护
- 金融、医疗这类 regulated domain 最终要比较的是 `risk reduction per unit of accuracy / latency / cost`

### 16B.18 IoT / Edge Privacy Aggregation 的 Mock Data

IoT 场景很适合用来理解“为什么真实系统经常要组合 HE、MPC 和 DP”。假设一个城市想统计不同区域的空气质量和噪声，但不希望单个设备或家庭的连续测量被平台直接看到。

设备侧原始测量：

```json
[
  {
    "device_id": "sensor_017",
    "zone": "west_school_area",
    "window": "2026-04-29T08:00:00Z/2026-04-29T08:05:00Z",
    "pm25": 18.4,
    "noise_db": 61.2
  },
  {
    "device_id": "sensor_018",
    "zone": "west_school_area",
    "window": "2026-04-29T08:00:00Z/2026-04-29T08:05:00Z",
    "pm25": 21.7,
    "noise_db": 64.9
  }
]
```

设备不上传明文，而是上传加密测量和证明元数据：

```json
{
  "device_id": "sensor_017",
  "zone": "west_school_area",
  "window": "2026-04-29T08:00:00Z/2026-04-29T08:05:00Z",
  "encrypted_payload": {
    "scheme": "paillier",
    "enc_pm25": "paillier:ciphertext:8fa2...",
    "enc_noise_db": "paillier:ciphertext:23bc..."
  },
  "device_attestation": {
    "firmware_hash": "sha256:7ad1...",
    "key_epoch": "2026-W18"
  }
}
```

边缘节点只做密文聚合，不解开单个设备：

```json
{
  "edge_node": "edge_west_03",
  "zone": "west_school_area",
  "window": "2026-04-29T08:00:00Z/2026-04-29T08:05:00Z",
  "device_count": 142,
  "encrypted_aggregate": {
    "sum_pm25": "paillier:ciphertext:sum_91d...",
    "sum_noise_db": "paillier:ciphertext:sum_4c8..."
  },
  "secret_shares_used": ["share_a", "share_c", "share_d"],
  "threshold_policy": {
    "min_devices": 50,
    "min_key_shares": 3
  }
}
```

云端只发布加噪后的区域级统计：

```json
{
  "zone": "west_school_area",
  "window": "2026-04-29T08:00:00Z/2026-04-29T08:05:00Z",
  "released_metrics": {
    "dp_avg_pm25": 20.1,
    "dp_avg_noise_db": 63.7
  },
  "privacy": {
    "mechanism": "gaussian",
    "epsilon": 1.0,
    "delta": 1e-6,
    "privacy_unit": "device_day"
  },
  "quality": {
    "device_count": 142,
    "relative_error_estimate": 0.031
  }
}
```

这条数据流里，每层保护的东西不同：

- HE 让平台不能直接看到单个设备测量值
- threshold / secret sharing 避免单个节点独自解密
- DP 让发布的区域指标不被某个设备强烈影响
- attestation 和 key epoch 负责把设备可信状态纳入治理

真正落地时，还需要补掉线、恶意设备、异常值裁剪、长期预算累计和密钥轮换；这些不属于单个算法，但决定系统能不能长期运行。

### 16B.19 Profile-Then-Simulate / 金融合成交易数据的 Mock Data

金融、广告和风控团队经常希望生成“像真实用户行为”的合成数据，用于模型开发、测试和合作方沙箱。2026 年的一个重要提醒是：LLM 可以生成可读、可用的数据，但不一定忠实保留原始分布。

一种更谨慎的做法是先把真实用户压缩成 DP profile，再让 simulator 生成交易。

原始用户行为不会直接进入 LLM：

```json
{
  "user_id": "u_4819",
  "transactions_30d": [
    {"merchant_category": "grocery", "amount": 42.10, "hour": 18, "fraud_label": false},
    {"merchant_category": "fuel", "amount": 63.20, "hour": 7, "fraud_label": false},
    {"merchant_category": "electronics", "amount": 980.00, "hour": 2, "fraud_label": true}
  ]
}
```

DP profiling 后只保留统计轮廓：

```json
{
  "profile_id": "dp_profile_2041",
  "privacy_unit": "account_30d",
  "dp_profile": {
    "monthly_spend_bucket": "500-1500",
    "top_categories": ["grocery", "fuel", "electronics"],
    "night_transaction_rate_bucket": "medium",
    "high_value_purchase_rate_bucket": "low",
    "fraud_risk_bucket": "elevated"
  },
  "privacy_spend": {
    "epsilon": 0.8,
    "delta": 1e-6
  }
}
```

LLM simulator 根据 profile 生成合成交易：

```json
[
  {
    "synthetic_account_id": "syn_acct_901",
    "merchant_category": "grocery",
    "amount": 39.80,
    "hour": 17,
    "label": "legitimate"
  },
  {
    "synthetic_account_id": "syn_acct_901",
    "merchant_category": "electronics",
    "amount": 910.00,
    "hour": 1,
    "label": "suspicious"
  }
]
```

但发布前必须做 fidelity 和 bias evaluation：

```json
{
  "evaluation_run_id": "fin_synth_eval_20260602",
  "generator": "profile_then_simulate_llm",
  "baseline": "direct_dp_synthesis",
  "checks": {
    "fraud_recall_delta_vs_real": -0.11,
    "category_distribution_jsd": 0.18,
    "amount_bucket_ks_stat": 0.22,
    "demographic_segment_drift": "medium"
  },
  "release_decision": "reject_for_model_training_allow_for_ui_testing",
  "reason": "LLM prior shifted categorical and fraud distributions"
}
```

这个例子想说明：

- DP profile 保护的是输入用户行为，但不保证 LLM 生成分布忠实
- LLM 生成数据适合 demo、UI 测试、流程联调，不一定适合训练风控模型
- synthetic data 的 release gate 应该看 downstream utility 和 segment drift，而不只看样本是否自然
- 对结构化高风险任务，传统 DP synthesis 仍然可能更稳

### 16B.20 Consent-aware Clean Room / 把同意信号带进协作执行层的 Mock Data

很多 clean room 入门解释只讲“双方不共享原始表”，但真实业务还会问一个更细的问题：

- 即使技术上能 join，这条记录在当前目的下是否被允许使用？

下面用一个广告测量例子说明 consent-aware clean room 的数据流。

Advertiser 有 campaign exposure 表：

```json
[
  {
    "advertiser_user_key": "adv_hash_001",
    "campaign_id": "spring_sale_2026",
    "impression_ts": "2026-04-27T10:01:00Z",
    "purpose": "measurement"
  },
  {
    "advertiser_user_key": "adv_hash_002",
    "campaign_id": "spring_sale_2026",
    "impression_ts": "2026-04-27T10:05:00Z",
    "purpose": "measurement"
  }
]
```

Retailer 有 purchase 表，但每条记录还带着 consent / purpose 状态：

```json
[
  {
    "retailer_user_key": "ret_hash_991",
    "sku_category": "running_shoes",
    "purchase_amount": 128.00,
    "purchase_ts": "2026-04-28T18:31:00Z",
    "consent": {
      "measurement": "granted",
      "activation": "denied",
      "model_training": "denied",
      "updated_at": "2026-04-20T09:00:00Z"
    }
  },
  {
    "retailer_user_key": "ret_hash_992",
    "sku_category": "running_shoes",
    "purchase_amount": 76.00,
    "purchase_ts": "2026-04-28T19:44:00Z",
    "consent": {
      "measurement": "withdrawn",
      "activation": "denied",
      "model_training": "denied",
      "updated_at": "2026-04-28T12:00:00Z"
    }
  }
]
```

Entity resolution / ID mapping 只输出 clean room 内部可用的 join key：

```json
[
  {
    "clean_room_join_key": "crjk_6f21",
    "advertiser_user_key": "adv_hash_001",
    "retailer_user_key": "ret_hash_991",
    "match_confidence": 0.97
  },
  {
    "clean_room_join_key": "crjk_9a04",
    "advertiser_user_key": "adv_hash_002",
    "retailer_user_key": "ret_hash_992",
    "match_confidence": 0.95
  }
]
```

clean room 执行时先应用 purpose filter，再运行模板：

```sql
SELECT
  e.campaign_id,
  p.sku_category,
  COUNT(DISTINCT j.clean_room_join_key) AS matched_buyers,
  SUM(p.purchase_amount) AS revenue
FROM advertiser_exposures e
JOIN id_mapping j
  ON e.advertiser_user_key = j.advertiser_user_key
JOIN retailer_purchases p
  ON j.retailer_user_key = p.retailer_user_key
WHERE e.purpose = 'measurement'
  AND p.consent:measurement = 'granted'
  AND p.purchase_ts >= e.impression_ts
GROUP BY 1, 2;
```

发布前的治理层会记录：哪些记录被排除、消耗了什么预算、输出是否通过阈值：

```json
{
  "analysis_run_id": "acr_20260428_0031",
  "template_id": "campaign_conversion_measurement_v4",
  "purpose": "measurement",
  "records_seen": 2,
  "records_excluded_by_consent": 1,
  "records_excluded_by_threshold": 0,
  "access_budget": {
    "table": "retailer_purchases",
    "period": "monthly",
    "remaining_runs": 27
  },
  "privacy_budget": {
    "epsilon_spent": 0.15,
    "epsilon_remaining": 2.35
  },
  "release_decision": "approved"
}
```

最终输出不包含用户级明细：

```json
[
  {
    "campaign_id": "spring_sale_2026",
    "sku_category": "running_shoes",
    "matched_buyers_dp": 1042,
    "revenue_dp": 128940.50
  }
]
```

这个 mock data 想说明：

- clean room 的“可用数据”不是原始表全集，而是 `identity match + purpose filter + policy filter` 后的可分析集合
- consent withdrawal 应该影响后续查询，而不是只停留在收集端
- access budget 和 privacy budget 解决的是不同问题：前者限制访问次数，后者限制统计泄漏
- 真实落地里，audit log 要能解释“为什么这条记录没有参与这次 collaboration”

### 16B.21 Clean Rooms ML / 合成训练数据 / Consent Function 的 Mock Data

这个例子把 2026 年已经能在主流 clean room 产品里看到的几条线放在一起：

- `privacy-enhanced synthetic dataset generation`
- `Clean Rooms ML lookalike / audience modeling`
- `DP privacy budget`
- `membership inference attack threshold`
- `GPP / TCF consent string decode`
- `result receiver / activation policy`

业务场景：

- 零售商有购买和会员标签
- 媒体平台有广告曝光和受众 seed
- 双方想训练 lookalike / propensity 模型
- 但不希望把真实 join 后训练明细交给任一方
- 同时必须尊重每条记录上的 consent signal

输入 1：媒体平台的 seed audience：

```json
[
  {
    "publisher_user_id": "pub_1001",
    "hashed_email": "sha256:8b4f...",
    "campaign_id": "spring_running_2026",
    "seed_reason": "clicked_product_video",
    "gpp_string": "DBABLA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA",
    "event_ts": "2026-04-29T10:14:03Z"
  },
  {
    "publisher_user_id": "pub_1002",
    "hashed_email": "sha256:aa19...",
    "campaign_id": "spring_running_2026",
    "seed_reason": "visited_category_page",
    "gpp_string": "DBABLA~CPXxRfAPXxRfAAfKABENB-CgAAAAAAAAAAYgAAAAAAAA",
    "event_ts": "2026-04-29T10:19:44Z"
  }
]
```

输入 2：零售商的训练特征，只暴露给 collaboration 内的受控任务：

```json
[
  {
    "retailer_user_id": "ret_771",
    "hashed_email": "sha256:8b4f...",
    "features": {
      "shoe_category_views_30d": 6,
      "running_purchase_180d": 1,
      "avg_order_value_bucket": "75_100",
      "loyalty_tier": "gold"
    },
    "label": {
      "purchased_running_shoes_14d": 1
    },
    "consent": {
      "measurement": true,
      "model_training": true,
      "activation": false,
      "source": "gpp_decode"
    }
  },
  {
    "retailer_user_id": "ret_882",
    "hashed_email": "sha256:aa19...",
    "features": {
      "shoe_category_views_30d": 1,
      "running_purchase_180d": 0,
      "avg_order_value_bucket": "25_50",
      "loyalty_tier": "standard"
    },
    "label": {
      "purchased_running_shoes_14d": 0
    },
    "consent": {
      "measurement": true,
      "model_training": false,
      "activation": false,
      "source": "gpp_decode"
    }
  }
]
```

平台侧可以先把 GPP / TCF consent string 解析成可执行字段。真实产品里这通常不是隐私算法本身，但它决定了后续 PET 是否用在了合法的数据子集上：

```sql
SELECT
  hashed_email,
  consent_gpp_v1_decode(gpp_string) AS decoded_gpp,
  CASE
    WHEN decoded_gpp.sale_opt_out = false
     AND decoded_gpp.targeted_advertising = true
    THEN true
    ELSE false
  END AS eligible_for_model_training
FROM publisher_seed_events;
```

合成训练数据模板可以把输出强制设为 synthetic，并要求配置 DP 参数和 membership inference 约束：

```json
{
  "template_id": "lookalike_training_synthetic_v1",
  "output_mode": "synthetic_only",
  "join_key": "hashed_email",
  "filters": [
    "publisher.eligible_for_model_training = true",
    "retailer.consent.model_training = true"
  ],
  "synthetic_data_parameters": {
    "epsilon": 1.25,
    "max_membership_inference_attack_score": 0.62,
    "column_classification": {
      "shoe_category_views_30d": "numerical",
      "running_purchase_180d": "categorical",
      "avg_order_value_bucket": "categorical",
      "loyalty_tier": "categorical",
      "purchased_running_shoes_14d": "categorical"
    }
  },
  "minimum_training_rows": 500,
  "result_receiver": "media_platform_activation_account"
}
```

clean room 内部会生成一个不可回溯到真实用户的 synthetic training channel：

```json
[
  {
    "synthetic_row_id": "syn_000001",
    "shoe_category_views_30d": 5,
    "running_purchase_180d": 1,
    "avg_order_value_bucket": "75_100",
    "loyalty_tier": "gold",
    "purchased_running_shoes_14d": 1
  },
  {
    "synthetic_row_id": "syn_000002",
    "shoe_category_views_30d": 2,
    "running_purchase_180d": 0,
    "avg_order_value_bucket": "50_75",
    "loyalty_tier": "standard",
    "purchased_running_shoes_14d": 0
  }
]
```

训练 / 推理任务只看到 synthetic channel 或受控 lookalike job 输出：

```json
{
  "clean_rooms_ml_job_id": "crm_ml_20260430_0182",
  "job_type": "lookalike_audience",
  "training_input": "synthetic_channel:syn_train_20260430_01",
  "seed_min_size": 500,
  "privacy_controls": {
    "epsilon_spent": 1.25,
    "membership_inference_attack_score": 0.58,
    "user_level_metrics_released": false
  },
  "output": {
    "audience_segment_id": "seg_running_lal_20260430",
    "rows": 184230,
    "contains_seed_users": false,
    "contains_training_user_ids": false
  }
}
```

审计日志要能解释数据为什么没有进入训练：

```json
{
  "audit_event_id": "audit_20260430_8912",
  "template_id": "lookalike_training_synthetic_v1",
  "records_seen": 1280441,
  "records_excluded": {
    "missing_join_key": 19302,
    "gpp_or_tcf_not_eligible": 310448,
    "retailer_model_training_consent_false": 221905,
    "minimum_group_threshold": 487
  },
  "release_decision": "approved",
  "reason": "synthetic output passed privacy threshold and consent filters"
}
```

这个 mock data 想说明：

- `consent decode` 是把法律 / 产品同意信号变成计算条件，不是事后报表
- synthetic data 的隐私参数应该出现在模板和审计日志里，而不是藏在训练脚本里
- Clean Rooms ML 的重点不是“模型完全看不到任何统计规律”，而是减少双方通过 seed、训练集、输出 segment 反推出对方用户的机会
- membership inference threshold、minimum seed size、user-level metric suppression 和 DP epsilon 应该一起看
- 对广告和零售媒体场景来说，落地架构通常是 `consent-aware filtering -> protected join -> synthetic or lookalike job -> controlled result receiver -> audit`

### 16B.22 Privacy Sandbox + Clean Room / 广告测量的 Mock Data

这个例子把浏览器侧 PET 和企业侧 clean room 放在同一条测量链路里看。真实系统不一定完全长这样，但它能帮助初学者理解：为什么“浏览器不发用户级日志”之后，后端仍然需要 TEE、聚合、阈值和审计。

业务场景：

- DSP 通过 Privacy Sandbox 做转化测量
- 浏览器只产生 event-level 或 aggregatable report
- summary report 在可信执行环境或聚合服务中计算
- 广告主把最终聚合结果带进 clean room，与一方销售数据做 campaign-level 校验

浏览器侧的广告展示事件可以先被压成有限字段，而不是完整用户日志：

```json
{
  "browser_report_id": "ara_evt_20260501_001",
  "source_event_id": "src_9f32",
  "attribution_destination": "advertiser.example",
  "trigger_data": "purchase",
  "campaign_bucket": 4312,
  "coarse_value": "high",
  "report_type": "aggregatable",
  "user_id_available_to_adtech": false
}
```

聚合服务或 TEE 看到的是 encrypted aggregatable reports，输出是 bucket-level summary：

```json
{
  "aggregation_job_id": "agg_20260501_18",
  "input_reports": 1249088,
  "privacy_controls": {
    "thresholding": true,
    "noise_added": true,
    "raw_user_level_export": false
  },
  "summary_report": [
    {
      "campaign_bucket": 4312,
      "conversion_type": "purchase",
      "dp_noisy_count": 18420,
      "dp_noisy_value_sum": 912340.0
    },
    {
      "campaign_bucket": 4313,
      "conversion_type": "signup",
      "dp_noisy_count": 6231,
      "dp_noisy_value_sum": 0
    }
  ]
}
```

广告主或 measurement partner 再把 summary report 放进 clean room，与一方订单表做 campaign-level 对账，而不是重新导出浏览器用户日志：

```json
{
  "clean_room_query": "campaign_incrementality_check_v2",
  "join_scope": "campaign_bucket_only",
  "inputs": [
    "privacy_sandbox_summary_report",
    "advertiser_order_aggregate_by_campaign"
  ],
  "blocked_columns": [
    "hashed_email",
    "device_id",
    "ip_address",
    "raw_browser_report_id"
  ],
  "output": {
    "campaign_bucket": 4312,
    "reported_conversions": 18420,
    "advertiser_orders": 17988,
    "delta_pct": 2.4,
    "release_status": "approved_aggregate_only"
  }
}
```

这条 mock flow 想说明：

- Privacy Sandbox 这类浏览器侧方案把用户级信号变成受限报告，不等于后端治理可以省略
- TEE / aggregation service 解决的是“如何产生 summary”，clean room 解决的是“summary 如何与合作方数据协作”
- 后端 clean room 不应该试图把 summary report 还原成用户级明细
- campaign bucket、阈值、噪声、blocked columns 和 audit log 是同一条隐私设计链路上的控制点

### 16B.23 Enterprise RAG / 隐私保护检索的 Mock Data

企业 RAG 和文档检索场景很容易被误解成“只要向量化就安全了”。实际上，embedding、reranker 输入、query log、retrieval result 都可能泄露敏感信息。

假设一家医疗设备公司要做内部文档搜索，原始文档片段长这样：

```json
{
  "doc_id": "quality_case_20260429_07",
  "access_group": "quality_team",
  "text": "Customer reported intermittent battery swelling in batch B-17 after 11 months.",
  "labels": ["field_issue", "battery", "regulated_quality_record"]
}
```

一个更谨慎的 on-premise / sovereign retrieval flow 可以先把文档处理成受权限和用途约束的索引对象：

```json
{
  "chunk_id": "chk_8f21",
  "doc_id": "quality_case_20260429_07",
  "embedding_store": "local_vector_db",
  "access_policy": {
    "allowed_groups": ["quality_team", "regulatory_affairs"],
    "blocked_groups": ["sales"],
    "export_allowed": false
  },
  "redaction_status": {
    "pii_removed": true,
    "batch_id_generalized": false
  }
}
```

用户查询时，系统不应该把所有 query 和候选文档发给外部 API，而是先在本地完成检索和轻量 rerank：

```json
{
  "query_id": "q_20260502_001",
  "user": {
    "role": "quality_engineer",
    "groups": ["quality_team"]
  },
  "query": "battery swelling complaints after one year",
  "retrieval_pipeline": [
    {"step": "local_sparse_retrieval", "top_k": 100},
    {"step": "local_vector_retrieval", "top_k": 100},
    {"step": "policy_filter", "rule": "document_acl_intersection"},
    {"step": "lightweight_local_reranker", "model": "hr-qda-style"},
    {"step": "answer_generation", "mode": "grounded_summary_only"}
  ]
}
```

返回结果可以只暴露用户有权看的片段和引用，而不是导出完整文档集合：

```json
{
  "query_id": "q_20260502_001",
  "results": [
    {
      "chunk_id": "chk_8f21",
      "score": 0.87,
      "citation": "quality_case_20260429_07",
      "snippet": "Intermittent battery swelling was reported after roughly 11 months in one production batch."
    }
  ],
  "audit": {
    "chunks_filtered_by_acl": 37,
    "external_api_used": false,
    "query_logged": "metadata_only"
  }
}
```

这个例子的关键点是：

- RAG 的隐私边界不只在训练数据，也在 `query -> retrieval -> rerank -> answer -> log`
- 轻量本地 reranker 可以是数据主权方案的一部分，不一定所有语义排序都要调用云端大模型
- ACL / purpose filter 必须在 retrieval 和 rerank 之间强制执行，否则 reranker 可能看到用户无权访问的候选片段
- query log 默认也可能敏感，最好只保留元数据或做聚合统计

### 16B.24 Production DP-SDG / 生产级差分隐私合成表格数据的 Mock Data

2026 年 PEPR 的多个议题都在强调同一件事：DP synthetic data 真正落地时，难点不只是“会不会加噪声”，而是能不能把 schema、public/private column split、validity constraints、utility evaluation 和 privacy budget 变成可重复运行的生产流水线。

假设一家金融公司要给欺诈检测团队开放一份可共享的合成交易数据。原始数据不能直接给下游团队：

```json
{
  "transaction_id": "txn_91f2",
  "user_id": "u_248801",
  "age_band": "35-44",
  "state": "CA",
  "merchant_category": "electronics",
  "amount_usd": 842.17,
  "device_risk_score": 0.73,
  "is_fraud": false,
  "event_time": "2026-05-02T18:23:11Z"
}
```

生产系统更适合先把字段分成公开上下文、敏感特征、受限标签和禁止发布字段：

```json
{
  "dataset": "card_transactions_2026w18",
  "privacy_unit": "user_id",
  "columns": [
    {"name": "state", "class": "public_context"},
    {"name": "age_band", "class": "public_context"},
    {"name": "merchant_category", "class": "private_feature"},
    {"name": "amount_usd", "class": "private_feature", "constraint": "amount_usd >= 0"},
    {"name": "device_risk_score", "class": "private_feature", "constraint": "0 <= score <= 1"},
    {"name": "is_fraud", "class": "restricted_label"},
    {"name": "transaction_id", "class": "blocked"},
    {"name": "user_id", "class": "blocked"}
  ]
}
```

DP-SDG 任务本身应该像一个带 release gate 的 job，而不是一次性 notebook：

```json
{
  "job_id": "dpsdg_20260503_001",
  "mechanism": "marginal_based_generator",
  "budget": {
    "epsilon": 3.0,
    "delta": 1e-7,
    "accounting_scope": "weekly_release"
  },
  "conditioning": {
    "public_columns": ["state", "age_band"],
    "private_columns": ["merchant_category", "amount_usd", "device_risk_score", "is_fraud"]
  },
  "scale_runtime": {
    "engine": "spark",
    "partition_key": "state",
    "max_columns": 220
  },
  "release_gate": {
    "validity_checks_required": true,
    "membership_inference_max_risk": 0.54,
    "utility_tasks": ["fraud_model_auc", "segment_distribution_drift"]
  }
}
```

合成输出不应该带真实 ID，而应该带生成批次和约束检查结果：

```json
{
  "synthetic_batch_id": "syn_20260503_001",
  "rows": [
    {
      "synthetic_user_key": "syn_u_00091",
      "age_band": "35-44",
      "state": "CA",
      "merchant_category": "electronics",
      "amount_usd": 799.30,
      "device_risk_score": 0.69,
      "is_fraud": false
    }
  ],
  "quality_report": {
    "fraud_model_auc_delta": -0.021,
    "invalid_rows_removed": 18,
    "segment_drift_flags": ["high_amount_TX_18_24"]
  },
  "privacy_report": {
    "epsilon_spent": 3.0,
    "release_approved": true,
    "attack_tests": ["membership_inference", "nearest_neighbor", "attribute_inference"]
  }
}
```

这个 mock data 想说明：

- DP-SDG 的生产形态是 `classify columns -> allocate budget -> generate -> validate -> attack test -> release`
- public/private column split 能把预算花在真正敏感的列上，而不是对所有列一视同仁
- 合成数据的质量要看下游任务和分布漂移，不只看单行样本是否自然
- release gate 必须能拒绝一次看起来“像真数据”但隐私或效用不达标的生成结果

### 16B.25 Edge FL with Concept Drift / 带漂移治理的边缘联邦学习 Mock Data

2026 年 5 月的 FedDriftGuard 研究把一个经常被 primer 忽略的问题讲得很清楚：边缘设备上的数据分布会变，用户行为、传感器环境、地区事件都会让模型出现 concept drift。FL 如果只说“原始数据不上传”，仍然可能在真实环境里因为漂移导致偏差、失效或隐私预算浪费。

假设一个智能家居系统用联邦学习训练设备侧异常检测模型，每个客户端上报的不是原始事件，而是本地更新和漂移摘要：

```json
{
  "client_id": "device_cluster_7a",
  "round": 184,
  "local_examples": 420,
  "drift_signal": {
    "type": "gradual",
    "score": 0.81,
    "suspected_cause": "seasonal_temperature_pattern"
  },
  "model_update": {
    "format": "sparse_gradient",
    "top_k": 1200,
    "compressed": true
  },
  "privacy": {
    "mechanism": "client_level_dp",
    "clip_norm": 1.0,
    "epsilon_increment": 0.08
  }
}
```

服务器端聚合器不应该只做普通 FedAvg，而要把漂移、资源成本和隐私预算一起纳入调度：

```json
{
  "aggregation_round": 184,
  "participants_sampled": 5000,
  "aggregation_policy": "drift_adaptive_secure_aggregation",
  "drift_buckets": [
    {"bucket": "stable", "clients": 3820, "noise_multiplier": 0.9},
    {"bucket": "gradual_drift", "clients": 940, "noise_multiplier": 1.1},
    {"bucket": "sudden_drift", "clients": 240, "noise_multiplier": 1.4}
  ],
  "resource_controls": {
    "periodic_transmission": true,
    "update_sparsification": true,
    "max_upload_kb_per_client": 256
  }
}
```

发布到生产前，评估报告应该把 accuracy 和 privacy 放在同一张表里：

```json
{
  "candidate_model": "edge_anomaly_v184",
  "evaluation": {
    "stable_f1": 0.91,
    "drifted_f1": 0.84,
    "adaptation_latency_rounds": 3,
    "communication_cost_delta": "-24%"
  },
  "privacy_accounting": {
    "epsilon_total_this_month": 4.7,
    "budget_limit": 6.0,
    "release_allowed": true
  },
  "deployment": {
    "rollout": "canary",
    "rollback_if_drifted_f1_below": 0.78
  }
}
```

这类系统的关键不是把 `FL + DP` 写进架构图，而是明确：

- 漂移检测影响聚合权重、噪声调度和发布节奏
- DP budget 是长期账户，不是每轮局部参数
- 压缩、稀疏化和周期上传是隐私工程的一部分，因为它们影响可观测性、成本和攻击面
- FL 的安全边界还要继续配 secure aggregation、客户端抽样、投毒检测和回滚策略

### 16B.26 IIoT Secure FL / 隐私、鲁棒性与可解释性一起进入数据流的 Mock Data

2026 年 5 月的 TrustFed-RHIO 研究，以及 2026 年 4 月的 AP-PPFL 研究，都指向同一个更现实的 IIoT / IoT 方向：边缘联邦学习不能只说“原始数据不上传”，还要同时处理攻击检测、恶意客户端、梯度泄漏、模型解释和部署证据。

假设一个工业园区有多个工厂节点共同训练入侵检测模型。每个节点本地保留原始网络流量，只上传经过裁剪、加密或加噪的训练信号：

```json
{
  "site_id": "plant_west_03",
  "round": 42,
  "local_data_window": "2026-05-04T08:00:00Z/2026-05-04T09:00:00Z",
  "raw_data_stays_local": true,
  "feature_summary": {
    "flow_count": 128044,
    "selected_features": ["packet_rate", "dst_port_entropy", "tcp_flag_ratio", "failed_auth_count"],
    "selector": "feature_importance_optimized"
  },
  "privacy_update": {
    "gradient_format": "clipped_vector",
    "clip_norm": 1.0,
    "mechanism": "client_level_dp",
    "epsilon_increment": 0.12
  },
  "security_signal": {
    "local_poisoning_score": 0.08,
    "suspected_attack_family": "none"
  }
}
```

聚合层需要同时做隐私保护和鲁棒性检查。一个更接近生产的聚合记录应该长这样：

```json
{
  "aggregation_job": "iiot_ids_round_42",
  "participants": 64,
  "secure_compute": {
    "mode": "dual_server_or_secure_aggregation",
    "gradient_visibility": "no_plaintext_gradient_to_single_server",
    "he_scheme": "additive_homomorphic_encryption"
  },
  "robustness": {
    "similarity_check": "cosine_similarity_on_protected_updates",
    "filtered_clients": 3,
    "filter_reason": "gradient_deviation_above_threshold"
  },
  "privacy_accounting": {
    "epsilon_total": 3.9,
    "monthly_limit": 6.0,
    "release_allowed": true
  }
}
```

模型发布不应该只给一个 accuracy，还要给安全、解释和隐私维度：

```json
{
  "candidate_model": "iiot_intrusion_detector_v42",
  "evaluation": {
    "accuracy": 0.982,
    "f1_score": 0.976,
    "latency_ms_p95": 18,
    "poisoning_resilience_test": "passed"
  },
  "explainability": {
    "method": ["SHAP", "LIME"],
    "top_features_for_alert": ["failed_auth_count", "dst_port_entropy", "packet_rate"]
  },
  "deployment_gate": {
    "privacy_budget_ok": true,
    "robustness_ok": true,
    "operator_review_required": true
  }
}
```

这条 mock data 想说明：

- IIoT 里的 FL 不是“隐私训练”单一问题，而是 `privacy + robustness + explainability + latency` 的联合问题
- 如果要检测 poisoning，系统不能简单依赖明文梯度；否则鲁棒性检查本身会变成隐私泄漏点
- HE / dual-server / secure aggregation 保护的是更新过程，DP 保护的是个体贡献对模型或统计发布的影响，XAI 保护的是上线后的可解释运营
- 对工业场景，落地证据应该包括攻击评估、隐私预算、延迟、回滚和人工复核，而不是只给模型指标

### 16B.27 Clean Room External Data / 外部湖仓数据接入的 Mock Data

Snowflake Data Clean Rooms 的外部 S3 connector 文档给了一个很现实的落地信号：clean room 不一定要求所有数据先搬进同一个平台，企业也会希望把 S3 / Iceberg / lakehouse 里的数据以受控方式接进协作环境。

一个简化的 external data registration 可以长这样：

```json
{
  "clean_room": "retail_media_measurement_q2",
  "provider": "publisher_a",
  "external_dataset": {
    "storage": "s3",
    "bucket_uri": "s3://publisher-a-cleanroom/exposures/2026/05/",
    "file_format": "parquet",
    "table_type": "external_table"
  },
  "access_boundary": {
    "iam_role_arn": "arn:aws:iam::123456789012:role/snowflake_cleanroom_connector",
    "allowed_prefix": "exposures/2026/05/*",
    "explicit_provider_approval_required": true
  },
  "governance": {
    "raw_export_allowed": false,
    "templates_allowed": ["campaign_lift_v3", "reach_frequency_v2"],
    "external_table_risk_notice_acknowledged": true,
    "consent_management_source": "external_policy_engine"
  }
}
```

这条 mock data 想说明：

- clean room 的工程边界正在靠近企业已有 lakehouse，而不是只处理平台内原生表
- 外部数据接入会引入 IAM、service account、prefix scope、文件格式和 provider approval 等新的安全面
- 文档也明确提醒：clean room 本身不自动替客户管理 data subject consent；consent / purpose / jurisdiction 需要额外接入执行链路
- 对初学者来说，`数据不复制` 不等于 `没有风险`，外部表权限、connector 责任边界和下游用途控制都要显式设计

### 16B.28 Clean Room Observability / 协作查询监控的 Mock Data

AWS Clean Rooms 2026-01 的 detailed monitoring 更新说明，clean room 进入生产之后，性能、成本和查询运行状态本身也要成为治理对象。广告主监控 lift analysis query，不只是为了省钱，也是在确认协作没有变成不可解释的黑盒。

一个协作查询监控事件可以长这样：

```json
{
  "collaboration_id": "collab_campaign_lift_2026_q2",
  "query_id": "query_lift_2026_05_07_001",
  "runner": "advertiser_measurement_role",
  "template": "campaign_lift_v3",
  "metrics": {
    "duration_ms": 48210,
    "scanned_rows": 982340112,
    "output_rows": 18,
    "compute_cost_usd_estimate": 12.44
  },
  "privacy_controls": {
    "aggregation_threshold_checked": true,
    "raw_result_export_allowed": false,
    "data_access_budget_spent": 1,
    "remaining_daily_budget": 11
  },
  "alerts": {
    "performance_anomaly": false,
    "unexpected_dimension_drilldown": false,
    "budget_near_limit": false
  }
}
```

这条 mock data 想说明：

- privacy tech 的生产化不只看算法，还看 observability、budget、alert 和审计
- clean room 查询如果运行成本异常、输出过细、访问预算消耗过快，都应该被监控
- 对业务团队，监控指标要能解释“这次协作是否按模板、预算和输出策略执行”，而不只是“SQL 成功了”

## 16C. 这些技术怎么用到 Ad Network 里

这一节把前面的技术直接放到 ad network 场景里来看。

### 16C.1 Model Optimization

#### 目标

- 更早识别高质量用户
- 更稳地训练 pLTV / pROAS / churn / fraud 模型

#### 可用技术

##### 去标识化 + clean room

适合：

- ad network 与广告主或平台先做安全协作分析
- 生成 cohort-level 训练标签或 benchmark

##### 联邦学习 + secure aggregation

适合：

- 数据分散在设备或多个合作方，不适合直接集中

##### TEE / confidential analytics

适合：

- 在不暴露明文特征表的情况下做特征拼接、标签生成或联合训练前处理

##### DP

适合：

- 发布模型效果 benchmark
- 对外共享学习结果或统计指标

#### 一个 ad network 的典型例子

目标：

- 训练“高质量安装预测模型”

传统做法：

- 只用 click、device、geo、publisher placement

引入隐私技术后可升级为：

- 在 clean room / TEE 中与广告主或游戏平台联合生成
  - tutorial completion bucket
  - d3 retention bucket
  - ad-engagement bucket
- 再把这些 bucket 作为标签或监督信号输入 ad network 模型

这样得到的是：

- 更丰富的质量信号
- 但不必直接拿到合作方原始明细

### 16C.2 Bidding

#### 目标

- 决定一个展示值多少钱
- 值不值得出价
- 该给什么 value bucket

#### 可用技术

##### clean room + matched aggregate analysis

适合：

- 先找出什么样的 source / creative / app context 真正带来高质量用户

##### PJC / PI-Sum

适合：

- 与合作方做 matched value measurement
- 得到更准确的后链路价值估计

##### 联邦学习

适合：

- 多设备或多方共同更新价值模型

#### 一个直观例子

假设 ad network 原本只知道：

- publisher X 的 CTR 很高

但通过隐私保护联合分析后知道：

- publisher X 的 tutorial completion 很低
- publisher Y 的 CTR 稍低，但 matched D7 quality 更高

那 bidding 策略就可以从：

- `bid on highest CTR`

升级成：

- `bid on highest quality-adjusted expected value`

### 16C.3 Attribution

#### 目标

- 确认哪个 network / campaign / touch 应获得转化 credit

#### 可用技术

##### PSM

适合：

- 在 yes/no claim 流程里做资格判断

##### PSI / PJC

适合：

- 私密求交
- 转化求和
- aggregate conversion measurement

##### TEE

适合：

- 把 adjudication 或聚合逻辑放在受保护环境里执行

#### 一个直观例子

MMP 有 conversion 集合，network 有 touch 集合。

如果只是判断：

- “这个转化你要不要 claim？”

那 PSM 风格就很自然。

如果还要算：

- “你一共匹配上多少转化？”
- “匹配上的 value sum 是多少？”

那更适合用 PJC / PI-Sum。

### 16C.4 流量策略（Traffic Strategy）

#### 目标

- 决定哪些流量值得多买
- 哪些 source 要限量
- 哪些 publisher / app / geo / creative 组合应该被优先或降权

#### 可用技术

##### clean room + 聚合洞察

适合：

- source quality ranking
- publisher quality benchmarking
- creative-to-app fit analysis

##### DP

适合：

- 安全共享群体层级流量表现

##### TEE / confidential clean room

适合：

- 与大媒体、游戏平台、引擎公司做更深层联合流量分析

#### 一个直观例子

ad network 可能从联合分析中发现：

```text
Source A:
- install 高
- CTR 高
- D7 retained quality 低

Source B:
- install 中
- CTR 中
- tutorial completion 高
- hybrid value 高
```

那流量策略可以改成：

- 降低 Source A 的预算
- 提高 Source B 的预算
- 对 Source A 只保留某些高质量 app 或 creative 组合

### 16C.5 Fraud 与质量风控

#### 目标

- 筛掉无效流量
- 识别虚假转化和异常行为

#### 可用技术

##### PSM / PSI

适合：

- 某些黑名单、资格判断、风险交集分析

##### clean room / TEE

适合：

- 多方联合风险建模
- 不互发明细的风险相关性分析

##### 联邦学习

适合：

- 分散设备端或合作方联合训练风控模型

#### 一个直观例子

广告主看到异常购买行为，ad network 看到异常点击模式。

双方不直接交换用户明细，而是在受控环境里输出：

```text
publisher P:
- suspicious overlap score = high
- confirmed low-quality segment rate = elevated
```

这就足够指导流量收缩和风控策略。

## 16D. 对 Ad Network 的一个简单选型建议

如果你是 ad network，从落地顺序看，我建议这样理解：

### 第一阶段：先做能产生业务价值的聚合合作

优先上：

- 去标识化
- clean room
- TEE
- 阈值 / DP 发布

原因：

- 最容易落地
- 最容易让商业团队理解
- 最容易验证合作值不值得做

### 第二阶段：再做私密匹配与联合归因/结算

优先上：

- PSM
- PSI
- PJC / PI-Sum

原因：

- 更贴近 measurement、对账、归因和 matched value

### 第三阶段：最后做协同学习

优先上：

- 联邦学习
- secure aggregation
- confidential federated analytics

原因：

- 这是上限最高，但工程和治理最复杂的一层

## 17A. AI 时代补充：把治理与 Private AI 也纳入学习顺序

如果你是第一次系统接触 privacy tech，我建议按这个顺序建立心智模型：

1. 先学 threat model，而不是先背缩写。
2. 再区分三个层面：输入侧最小化、执行侧受控、输出侧匿名化。
3. 先理解产品形态：clean room / confidential analytics / on-device analytics / federated systems。
4. 再学匹配类协议：PSM、PSI、PJC / PI-Sum。
5. 再学执行保护：TEE / Confidential Computing 与 attestation。
6. 再学输出保护：DP、aggregation threshold、privacy budget。
7. 最后再学协同学习：federated learning、secure aggregation、confidential federated analytics。

如果你是做产品或平台落地，可以把问题简化成下面 5 句：

- 我到底想少收什么数据？
- 我到底不想让谁看到明文？
- 我到底允许系统输出多细的结果？
- 我到底要不要跨组织 / 跨设备联合计算？
- 我到底能不能把 attestation、budget、query policy 这些治理机制工程化？

一个实用的学习路线是：

```text
de-identification
-> clean room / analysis rules
-> TEE / attestation
-> DP / privacy budget
-> PSM / PSI / PJC
-> federated analytics / federated learning
-> AI-era private analytics / private cloud AI
```

到这一步你再看各种新名词，就不容易迷路。

## 18A. 2025-2026 最新前沿与落地信号（截至 2026-05-07）

这一节只放我认为“既前沿，又足够能指导工程判断”的信号。

### 18A.1 差分隐私从“学术概念”进入更明确的工程评估框架

2025-03-06，NIST 正式发布 `SP 800-226 Guidelines for Evaluating Differential Privacy Guarantees`。

它对初学者最重要的意义不是又发了一篇 DP 文档，而是明确强调：

- 不能只盯着 epsilon
- 要看完整的 privacy pyramid
- 要看 privacy hazards，也就是那些在工程实现里把 DP 做“名义上成立、实际很脆弱”的坑

如果你在评估任何“我们做了 DP”的产品，这份文档现在应该是最实用的起点之一。

### 18A.2 Private AI 的主线开始清晰：不是单点 PET，而是组合栈

2025-01-22，Google Research 把 `Parfait` 明确成一个面向 private AI 的开源技术栈，把：

- federated learning / analytics
- secure aggregation
- DP
- TEE 中的 externally verifiable workflows

放在同一个工程框架里。

这很重要，因为它代表行业前沿不再把 privacy tech 看成孤立工具，而是把它们当成一条可组合的数据路径。

### 18A.3 “非结构化 AI 数据也能做可验证隐私分析”开始从概念走向实证

2025-10-30，Google Research 发布 `Provably Private Insights (PPI)`，把：

- LLM 结构化摘要 / 分类
- TEE 中受控执行
- 用户级 DP 直方图发布

组合起来，用于分析 Pixel Recorder 这类生成式 AI / 语音转写场景。

这代表一个非常新的拐点：

- 以前 privacy analytics 主要处理结构化表
- 现在开始处理 transcript、summary、topic 这类非结构化 AI 数据

对做 AI 产品的人，这比传统 cohort 报表更值得关注。

### 18A.4 Synthetic data 的前沿也在转向“推理式 + DP”

2025-03-18，Google Research 提出 `Generating synthetic data with differentially private LLM inference`。

它的工程启发非常直接：

- 不一定要重训一个 DP 模型
- 可以用现成 LLM 做并行推理
- 再用 DP 聚合/筛选把输出变成可发布数据

这给很多想做内部数据协作、测试数据、建模沙箱的团队提供了更现实的路线。

### 18A.5 TEE 仍然关键，但 2026 的研究再次提醒它不是“隐私魔法盒”

NDSS 2026 的 `SNPeek` 直接把结论讲清楚了：

- confidential VM / TEE 很重要
- 但 side-channel 仍然是实在存在的风险

所以今天更成熟的写法应该是：

- `TEE 是执行保护层`
- `不是完整隐私保证本身`

工程上仍然要叠加：

- 输出限制
- DP / aggregation threshold
- 可验证构建与 attestation
- workload 级的 side-channel review

### 18A.6 DP synthetic data 的路线开始分叉：不仅是推理式 LLM，也包括更轻量的 conditional generator

如果你只看 2025 上半年，很容易把 “DP synthetic data” 理解成一条单一路线：`off-the-shelf LLM inference + DP aggregation`。

但 Google Research 在 2025-08-14 又公开了 `Beyond billion-parameter burdens: Unlocking data synthesis with a conditional generator`，给出另一条很值得工程团队关注的信号：

- 不一定非要上 billion-scale LLM
- 可以用更小的 conditional generator
- 用 topic / cluster / metadata 作为控制信号
- 在强隐私预算下也尽量保持下游可用性

这对 primer 很重要，因为它把 “可落地 synthetic data” 从一个偏前沿、偏重算力的方向，拉回到了更现实的工程问题：

- 你是不是一定需要生成自由文本？
- 你能不能接受结构化或半结构化输出？
- 你最关心的是 `time-to-first-sample`、`GPU 成本`，还是 `downstream utility`？

对多数业务团队来说，2025 年后的更成熟理解应该是：

- `DP synthetic data` 不是一条算法
- 而是一组路线选择：`DP fine-tuning`、`DP inference`、`conditional generator`
- 具体选型要看数据形态、预算、部署成本和下游任务

### 18A.7 前沿重点开始从“有没有 PET”转向“能不能审计、配额化、持续运营”

如果说 2024 年前后的关键词还是 `TEE / DP / clean room` 本身，那到 2025 下半年到 2026 年初，一个更成熟的信号已经很明显：

- 不只是“有隐私增强技术”
- 而是“这些技术能不能被预算化、模板化、审计化、监控化”

这里有三条特别值得 primer 记住的产品/研究信号：

- BigQuery 当前文档已经明确写到：`differential privacy enforcement in BigQuery data clean rooms` 已 GA，而 `parameter-driven privacy budgeting` 仍在 preview
- AWS Clean Rooms 在 2025-10-02 上线 `data access budgets`，把“这份数据还能被跑多少次”变成一等治理对象
- AWS Clean Rooms 又在 2026-01-02 上线 collaboration query 的详细监控，把 clean room 从“能跑”推进到“可观测、可运维”

与之对应，研究侧也在补“可验证性”短板：Google Research 的 `DP-Auditorium` 与 `Sequentially Auditing Differential Privacy` 这条线都说明，DP 不该只停留在参数宣称，还要有黑盒审计与持续验证能力。

对初学者来说，这一节真正要记住的不是更多缩写，而是一个工程判断标准：

- `成熟的 privacy system = 保护机制 + 发布约束 + 配额控制 + 审计/监控`

### 18A.8 Synthetic data 的前沿继续前移：从“生成几条像样样本”转向“把整个数据集当作可设计对象”

2026-04-16，Google Research 发布了 `Designing synthetic datasets for the real world: Mechanism design and reasoning from first principles`，介绍 `Simula` 这条路线。

它对 primer 很重要，不只是因为又多了一个 synthetic data 框架，而是因为它把问题重新定义了：

- 不是先拿一些 seed row 再逐条仿写
- 而是先定义数据集要覆盖哪些概念空间
- 再分别控制全局覆盖、本地多样性、复杂度和质量校验

这和很多团队正在做的 privacy-sensitive AI 非常契合，因为真实需求往往不是“像真数据”，而是：

- 能不能不导出原始敏感语料
- 能不能系统性覆盖长尾 edge case
- 能不能把质量与复杂度变成可审计、可调参的控制面

更值得注意的是，Google 在同一篇文章里明确说 Simula 已被用于 Gemma 生态、Gemini safety classifiers，以及 Android scam detection / Google Messages spam filtering 这类实际产品线。对初学者来说，这说明 synthetic data 的前沿已经不只是“研究论文里的数据增强”，而是在进入：

- `privacy-sensitive AI training`
- `safety classifier bootstrapping`
- `没有足够真实数据、又不适合直接碰原始数据` 的生产工程

这也补充了前面 2025 年的两条路线：

- `DP inference / DP aggregation`
- `conditional generator`

到 2026，视角进一步升级为：

- `dataset-level mechanism design`

也就是把 synthetic data 做成一个可以运营、评估、约束的数据控制平面，而不只是一个采样器。

### 18A.9 主流平台的控制面开始收敛：模板、双预算、监控、事件流正在成为默认配套

如果把 2025-2026 这些一手资料放在一起看，一个非常值得写进 primer 的结论是：主流平台虽然底层实现不同，但控制面正在明显收敛。

当前能直接从官方资料验证到的收敛点至少有四类：

- `模板化查询与分析规则`：BigQuery clean rooms 的 analysis rules / query templates，Snowflake clean rooms 的 join / projection policy
- `输出保护`：BigQuery clean rooms 与 Snowflake clean rooms 都把 differential privacy 做成平台能力
- `双预算化`：AWS Clean Rooms 明确把 `privacy budget` 之外的 `data access budgets` 也产品化
- `运维事件流`：AWS Clean Rooms 已提供 CloudWatch 详细监控与 EventBridge 事件发布

这条信号对工程判断很重要，因为它说明：

- 真正成熟的 privacy platform 不会只回答“能不能隐私增强”
- 它还必须回答“谁能跑、还能跑几次、结果给谁、出了问题怎么观测”

换句话说，到 2026 年，一个更稳妥的判断标准已经变成：

- `deployable privacy tech = protected execution or protected output + governed query surface + budgets + observability hooks`

### 18A.10 DP LLM 的前沿正在从“能不能做”进入“怎么规模化训练、微调、审计”

2025 下半年到 2026 初，DP + LLM 这条线已经比“给训练加噪声”清晰很多。几条信号可以放在一起看：

- Google Research 在 2025-05-23 讨论 `user-level differential privacy` 微调 LLM，强调当一个用户贡献多条样本时，example-level DP 不一定保护到真正的用户单位
- 2025-09-12 的 `VaultGemma` 把 1B 参数开源模型从头用 DP 训练出来，并给出 DP scaling laws，说明隐私预算、数据预算和算力预算必须一起设计
- 2025-11-12 的 `JAX-Privacy 1.0` 把 DP 训练进一步工具链化，目标是让 JAX / Keras 生态里的 DP-ML 更接近可复现实验和可部署工程
- 2025 NeurIPS 的 `Sequentially Auditing Differential Privacy` 则提醒：DP 机制不能只靠参数声明，还需要黑盒审计和持续验证
- 2026-04-29 的 `PrunePrivyTune` 把结构化剪枝、LoRA fine-tuning 和 DP-SGD 放到同一条路线里，说明隐私 LLM 的工程问题也包括模型尺寸、推理延迟和敏感域部署成本

这条线对工程团队的启发是：

- 做 LLM 隐私保护时，先问 `privacy unit` 是 sequence、example、user，还是 account / device
- 再问预算是用在 pretraining、fine-tuning、inference aggregation，还是发布后的统计洞察
- 最后问能否被工具链复现、被审计器验证、被产品控制面限制，并且能否在可接受延迟和成本下部署

换句话说，DP LLM 的成熟路线正在变成：

- `privacy unit definition + DP training/inference mechanism + compression or PEFT strategy + privacy accounting + auditing + release policy`

### 18A.11 Clinical LLM 的 DP 研究开始强调“分层预算 + 实时审计”

2026-04-02，Scientific Reports 发表的 clinical LLM DP 框架把几个工程点放在同一个系统里讨论：上下文敏感的噪声校准、按医疗数据类别分配隐私预算、RDP accounting、实时隐私审计，以及当泄漏风险升高时触发自适应缓解。

这条信号值得放进 primer，不是因为某个具体模型已经可以直接复制到生产，而是因为它说明高敏文本生成的隐私工程正在从：

- `训练时做一次 DP-SGD`

转向：

- `输入敏感度分类`
- `patient / episode 级 privacy unit`
- `长序列生成中的组合预算`
- `运行时泄漏监测`
- `输出泛化或拒绝策略`

对医疗、法务、客服质检这类高敏 LLM 场景来说，真正可落地的设计通常不是单点算法，而是 `DP mechanism + policy-aware prompting / decoding + runtime audit + release control`。

### 18A.12 Regulated FL 的研究正在从“能训练”转向“能比较 DP、HE 与业务成本”

2026-01-02，Scientific Reports 的联邦信用风险模型研究把 standard FL、DP-FL 和 HE-FL 放在同一个贷款审批预测任务里比较。

这个案例的价值在于它非常适合帮助初学者建立 trade-off 直觉：

- standard FL 准确率可以高，但不能自动提供模型更新的机密性保证
- DP-FL 可以给出可记账的隐私预算，但会牺牲一部分准确率
- HE-FL 可以保护聚合过程中的密文计算，但通常带来更高计算开销

这也是 regulated domain 的典型判断方式：不要只问“有没有用 FL”，而要问：

- `更新有没有泄漏风险`
- `隐私预算如何累计`
- `加密计算保护的是哪个阶段`
- `准确率、延迟、算力成本和审计证据是否能一起交付`

### 18A.13 组合式 PET 在 IoT / 边缘聚合里继续变得更具体

2026-04-28，Scientific Reports 发表了一篇 IoT 隐私聚合研究，把 Paillier 同态加密、Shamir secret sharing / secure computation 和差分隐私放在同一个三层架构里讨论：

- IoT device 侧先加密测量值
- edge node 侧做 secure aggregation / distributed computation
- cloud 侧在阈值解密前注入 calibrated DP noise

它的价值不在于“这就是唯一正确架构”，而是给 primer 提供了一个很好的工程直觉：

- HE 保护的是测量值在传输和聚合过程中的明文暴露
- MPC / secret sharing 降低对单个可信第三方的依赖
- DP 保护的是最终发布统计结果中的个体贡献

这类组合在 smart city、工业 IoT、医疗监测里尤其自然，因为单个传感器数据可能敏感，但业务真正需要的常常只是区域级、时间窗级或设备群级指标。

同时也要保留谨慎判断：这篇研究主要是模拟和公开数据实验，威胁模型是 semi-honest adversary；如果落到生产，还要补强恶意节点、设备密钥管理、掉线容错、异常传感器和长期预算累计。

### 18A.14 Clinical synthetic notes 给了一个反直觉提醒：DP fine-tuning 不等于合规去标识化

2026 年 Intelligent Systems with Applications 的一篇 clinical note synthetic generation 研究专门评估了 DP fine-tuning LLM 生成临床文本的泄漏风险。

它的结论对初学者非常重要：即使使用较严格的 privacy budget，生成文本中仍可能重新出现 PHI；而且同样的 epsilon 在不同模型、不同生成设置下，泄漏行为并不一致。

这补充了前面 clinical LLM 的“分层预算 + 实时审计”观点：

- DP 参数是必要的风险控制信号，但不是 HIPAA / GDPR / PIPL 语境下的完整合规结论
- 文本生成还需要 PHI detector、rare-combination detector、manual review、输出泛化和拒绝发布机制
- 对 clinical notes 这种长文本，`privacy unit`、训练语料记忆、解码策略和后处理审计要一起看

换句话说，在高敏文本里，最稳的产品表述不是“用了 DP 所以安全”，而是：

- `DP training or inference + leakage evaluation + de-identification checks + release governance`

### 18A.15 LLM synthetic data 的评估重点开始从“能生成”转向“是否忠实保留分布”

USENIX PEPR 2026 的 `Profile-Then-Simulate` 分享了一个很贴近生产的金融合成数据经验：先把用户属性和行为压缩成 DP profile，再让 LLM simulator 生成交易数据。

这个方向听起来很吸引人，因为它把高维金融行为先压缩成更容易保护的 profile，再用 LLM 扩展成可测试、可建模的数据。

但分享里的关键教训是：LLM 生成的数据虽然可用，直接 DP synthesis 在 fraud detection utility 和 distributional fidelity 上仍然更强；主要误差来源不是 DP noise，而是 LLM 对“典型金融行为”的先验偏差覆盖了输入分布。

这条信号很适合写进 primer，因为它提醒团队：

- LLM synthetic data 不该只评估“看起来像不像”
- 要看下游任务指标，例如 fraud recall、calibration、segment-level distribution drift
- 要特别检查 demographic / categorical feature 是否被模型先验拉偏
- 在结构化金融、风控、广告归因这类任务里，传统 DP synthesis 仍可能比 LLM simulator 更可靠

所以 2026 年更成熟的 synthetic data 选型不是“LLM 还是非 LLM”，而是：

- `生成机制 + DP 保护点 + distribution fidelity evaluation + downstream task validation`

### 18A.16 DP for data sharing 的问题边界正在从“样本共享”转向“知识共享”

2026-04-23，Computer Networks 在线发表了一篇关于差分隐私、数据共享和生成式 AI 全生命周期应用的综述。

它值得补进 primer，不是因为综述本身提出了某个单点新算法，而是因为它把 DP 在 AI 时代的问题边界讲得更贴近工程现实：

- 过去很多团队把隐私数据共享理解成“能不能安全地发样本”
- 生成式 AI 场景里，更重要的问题变成“能不能释放可用知识，同时控制训练、推理和数据流里的记忆泄漏”
- DP 的位置也不再只是训练时 DP-SGD，而是覆盖 `model training + interactive inference + data flow + release governance`

这对产品设计有一个直接启发：如果你要做 AI 数据协作，不要只问“训练集有没有 DP”，还要问：

- prompt / retrieval 里是否会带入原始敏感片段
- inference output 是否需要 DP aggregation、filtering 或 redaction
- synthetic data 是否有 release gate
- privacy spend 是否能跨训练、评估、查询和发布阶段记账

所以在 AI 场景里，DP 更像一条贯穿系统生命周期的控制线，而不是训练脚本里的一个参数。

### 18A.17 DP + LLM data augmentation 的一个新方向：把 DP 放到判别和过滤环节

2026 年 Neural Networks 的一篇研究提出 `LLM generation + DP-based discriminator + distribution-aligned filtering` 的 data augmentation 框架。

这个方向很有意思，因为它承认一个现实问题：直接让大模型在巨大文本输出空间里做强 DP 生成，噪声成本很高，质量也容易下降。

于是它把思路从：

- `对生成本身强行加 DP`

转向：

- `用 LLM 生成候选样本`
- `用带 DP 的 discriminator / filtering 机制选择更有用、更贴近分布的样本`

这给工程团队一个更细的设计空间：

- 生成模型可以负责语言自然度
- DP 机制可以负责对私有域样本的选择和统计约束
- release gate 可以继续检查重复、PHI / PII、rare combination 和 distribution drift

但这也不能被理解成“LLM synthetic data 自动安全”。它仍然要回答：

- DP 保护的是 discriminator 看到的哪一层数据
- 候选生成是否可能复述 base model 记忆
- filtering 是否引入 segment bias
- 最终数据是用于 UI 联调、模型训练，还是外部共享

### 18A.18 TEE 的最新教训更明确：要把 side-channel evaluation 当成工程交付物

NDSS 2026 的 SNPeek / FARFETCH'D 研究继续提醒：CVM / TEE 很适合做 privacy-preserving workload，但它不自动消除 side-channel 风险。

研究者在生产 AMD SEV-SNP 硬件上做了可配置 tracing 和自动化泄漏估计，并在 PIR、private heavy hitters、Wasm UDF 等隐私 workload 上发现了以前不容易被注意到的泄漏路径。

对 primer 来说，最重要的不是某个具体攻击细节，而是工程判断：

- `attestation` 证明代码和环境符合预期，但不等于证明没有 side-channel leakage
- TEE clean room 或 confidential analytics 需要把 constant-time、oblivious memory、DP output control 和 workload-specific leakage test 放进上线清单
- 对高敏协作，安全评审不应只看“是否运行在 CVM”，还要看“是否测过这个 workload 在这个硬件 / runtime / query pattern 下的泄漏”

换句话说，TEE 的成熟落地路径不是少做治理，而是把可信执行、泄漏评估和输出控制一起产品化。

### 18A.19 Clean room 的最新产品化信号：从 API 到 UI，再到自然语言辅助治理

截至 2026-05-01，Snowflake Data Clean Rooms 的 2026 年 4 月更新给了一个很清晰的落地信号：clean room 正在从“专家 API / 专家 SQL 工具”继续向“多人协作平台”演进。

最值得注意的是：

- 2026-04-09：Collaboration API GA，支持对称多方协作、灵活角色和细粒度访问控制
- 2026-04-23：provider 可以查看 Freeform SQL Data Offering 的 view 名称和 column policy
- 2026-04-30：Snowsight 里的 Data Clean Rooms UI 进入 public preview，可浏览、创建、加入、编辑 collaboration、运行分析，并接入 Cortex Code 做自然语言辅助

这对技术选型的启发是：

- clean room 的核心能力正在从 `secure query` 扩展为 `secure collaboration operations`
- 治理面不仅要控制数据和 SQL，还要控制成员、模板、审批、代码、可见性和 UI 操作
- AI assistant / natural-language coding 进入 clean room 后，审批、可见性和审计会更重要，因为用户更容易生成复杂查询

所以，面向 2026 的 clean room 设计不能只问“有没有 DP / PSI / TEE”。更实际的问题是：

- 谁能创建 collaboration
- 谁能把数据 offering 注册进去
- 谁能批准模板或 freeform SQL
- provider 能否看见 view 和 column policy
- UI / agentic assistant 生成的操作是否能被审计

### 18A.20 Privacy-enhanced synthetic data 开始 API 化：epsilon 与攻击阈值进入配置面

AWS Clean Rooms 的合成数据 API 文档把一个研究界常讨论的问题变成了很具体的产品接口：生成 synthetic ML data 时，参数里直接包含：

- `epsilon`
- `columnClassification`
- `maxMembershipInferenceAttackScore`

这说明 synthetic data 的工程化方向正在从“生成看起来像的数据”转向“生成过程有可配置的隐私阈值和失败条件”。

对 primer 来说，这个信号很重要：

- `epsilon` 让团队能把 synthetic data 纳入 DP 预算讨论
- `membership inference attack score` 让平台能在结果过于接近原始数据时拒绝发布
- `column classification` 迫使团队先说明哪些字段是数值、类别或敏感字段，而不是把整张表直接扔给生成器

这也提醒一个常见误区：synthetic data 不是自动安全。真正可落地的 synthetic data pipeline 应该至少包括：

- 输入字段分类
- 训练 / 生成权限控制
- DP 或其他隐私参数
- membership inference / attribute inference 检查
- 输出用途限制
- 审计日志

如果没有这些控制，它更像测试数据生成工具，而不是 privacy technology。

### 18A.21 Synthetic data 的反向提醒：深度学习生成数据可能只是“重新编码”

2026 年 2 月，`Privacy-Enhancing or Privacy-Elusion Technology?` 给 synthetic data 讨论补了一个很重要的负面边界：如果过参数化深度学习模型从真实个人数据中学到的是某种“隐私欺骗式编码”，那么输出虽然看起来不像原始记录，也可能仍然携带可被解码的个体信息。

这条研究信号对 primer 很重要，因为它提醒我们不要把“样本看起来不同”误当成“已经匿名化”。更稳的工程表达应该是：

- synthetic data 需要证明或评估 `unit-level dissimilarity`
- 需要 membership inference、attribute inference、nearest-neighbor、record linkage 等攻击评估
- 如果没有 formal guarantee 或充分攻击测试，pseudo-synthetic data 不应被轻易当成匿名数据
- 对外共享时，仍要把 legal basis、用途限制、访问控制和审计纳入治理

这也解释了为什么 AWS Clean Rooms 这类产品会把 `epsilon`、`columnClassification`、`maxMembershipInferenceAttackScore` 放进配置面：synthetic data 的可落地形态不是“生成器输出一份文件”，而是“生成、验证、拒绝发布、审计”连成一条流水线。

### 18A.22 企业 RAG 的隐私重点正在从“模型训练”扩展到“检索链路”

2026 年 2 月的 `A lightweight privacy-preserving reranker enables customizable hybrid retrieval for enterprise document search` 提供了一个很实用的信号：在企业检索里，隐私不一定总靠更重的密码学协议或更大的私有模型，有时更现实的路径是：

- 文档和索引留在企业本地或受控环境
- 使用轻量 reranker 降低部署和推理成本
- 通过 query-document attention 改善排序质量
- 避免把私有文档、query log 和候选片段发送给外部 API

它对 AI 应用的启发是：RAG 的隐私面至少包括 `document indexing`、`query embedding`、`candidate reranking`、`answer generation` 和 `logging`。如果只说“模型没有用客户数据训练”，但查询和候选文档都被发到外部服务，隐私风险仍然存在。

所以 enterprise RAG 的落地选型应同时问：

- embedding 和 reranker 在哪里运行
- retrieval candidate 是否先经过 ACL / purpose filter
- query log 是否保留原文
- answer 是否带引用和最小必要片段
- 是否需要 DP 聚合来发布搜索分析指标

### 18A.23 Clean room 自定义代码让能力变强，也让治理面变宽

Snowflake Data Clean Rooms 在 2026-03-05 的更新中支持在 collaboration 中上传和使用自定义 Python 代码；同年 3 月底又把 Cortex Code 接入 Collaboration Data Clean Rooms 的对象浏览、注册、创建、审批和分析流程。

这条信号很重要，因为 clean room 正在从“受控 SQL 模板”扩展到“受控代码执行与 agentic 操作”。这会带来更强的分析能力，也会带来新的治理要求：

- 自定义代码要有审批、版本、依赖和输出策略
- 代码能访问哪些 data offering、view、column policy 必须可见
- natural-language assistant 生成的操作也要进入 audit trail
- 对 PySpark / Python / freeform SQL 的自由度越高，threshold、DP、result receiver 和 provider visibility 越不能省

换句话说，2026 年的 clean room 不再只是“把 SQL 锁住”。它更像一个 `secure collaboration runtime`：数据、代码、成员、审批、预算、可观测性都要一起治理。

### 18A.24 DP Synthetic Data 正在从“算法可行”走向“工程系统”

PEPR 2026 的 `DPSynth` 和 `Generating High-Quality Tabular Synthetic Data at Scale` 都在补一个很实际的缺口：DP 合成数据如果要在公司内部长期使用，必须解决生产约束，而不是只给出一个漂亮的研究 demo。

这类系统的工程重点包括：

- 支持上百列甚至更高维的 tabular data
- 对 public/private column split 做预算分配
- 对真实业务约束做 validity checks，例如金额非负、枚举值合法、标签比例不崩
- 在 Beam / Spark 这类分布式执行环境里可扩展
- 给非 DP 专家提供合理默认值和明确 release gate

对 primer 的启发是：DP-SDG 不应该被写成“用 DP 生成一份假数据”。更准确的表达是：

- `privacy accounting` 负责数学边界
- `schema/constraint layer` 负责业务有效性
- `utility evaluation` 负责下游可用性
- `attack evaluation` 负责反向检查
- `release workflow` 负责把失败结果挡住

### 18A.25 Chatbot analytics 的隐私重点是“洞察发布”，不是“保存完整对话”

PEPR 2026 的 `A DP Framework for Gaining Insights into AI Chatbot Use` 指向一个正在变得很常见的场景：平台想理解用户如何使用 chatbot，但不应该把完整对话日志当作普通产品分析数据长期随意查询。

它的工程路线更接近：

- 对 conversation 做 private clustering
- 对主题和关键词做 DP extraction
- 用 partition selection 避免小群体主题泄露
- 用 histogram summarization 发布聚合洞察
- 把 benchmark 质量和隐私预算放在同一个评估流程里

这对 AI 产品很重要。很多团队会说“我们不训练用户数据”，但 product analytics 仍然可能把用户问题、疾病、财务、工作内容暴露给内部分析系统。更稳的设计是把 chatbot analytics 当成一个 DP 发布问题，而不是普通日志 SQL 问题。

### 18A.26 FHE 的瓶颈开始转向存储与数据移动

IBM Research 在 DATE 2026 的 FHEIns 研究把 HE 的落地瓶颈说得更工程化：对于面向数据库和大规模数据应用的 FHE，问题不只在密码学算子慢，还在密文膨胀导致的内存和 I/O 压力。FHEIns 的思路是把部分 FHE kernel 推到靠近 SSD 的 in-storage processing，以利用存储内部带宽。

这条研究信号对初学者很有价值，因为它提醒我们：

- FHE 的工程瓶颈可能在 `ciphertext size -> memory pressure -> storage I/O`
- 加速不一定只靠 GPU / ASIC，也可能靠 near-data processing
- “能在密文上计算”距离“能在 TB 级数据库上经济地计算”还有系统工程距离
- 评估 HE 方案时要问数据规模、访问模式、I/O 放大、密钥管理和可观测性

所以 HE 在 primer 里应该被理解为一类很强的计算原语，但落地时必须和数据库、存储、调度和成本模型一起看。

### 18A.27 边缘 FL 的新重点：漂移、隐私预算和资源约束要一起调度

2026 年 5 月发表的 FedDriftGuard 研究把 FL 的一个现实问题放到台面上：边缘环境里的数据不是静态的，用户行为、传感器条件和环境变化会造成 sudden、gradual、recurrent drift。只用 FedAvg 或 DP-FedAvg，可能同时遇到模型性能下降、收敛变慢、通信成本高和隐私预算使用不经济。

它对工程设计的启发是：

- drift detection 应该进入客户端或聚合层
- 聚合权重、噪声调度和上传频率可以随漂移状态变化
- DP budget 要按长期训练任务管理，而不是按单轮孤立理解
- 压缩、稀疏化、周期传输是边缘 FL 的现实约束，不是可选优化

这也补足了“联邦学习天然隐私”这个误区：FL 只是降低原始数据集中化，真实系统仍要处理梯度泄露、投毒、漂移、掉线、预算耗尽和部署回滚。

### 18A.28 IIoT / IoT 的最新信号：隐私 FL 必须和投毒防御、可解释性一起设计

2026-04-28 的 AP-PPFL 和 2026-05-04 的 TrustFed-RHIO 都把一个现实问题讲得更明确：联邦学习在 IoT / IIoT 里经常同时面对两类风险。

- 一类是隐私风险：梯度、模型更新和中间统计可能被服务器或攻击者用于推断本地数据
- 另一类是安全风险：恶意客户端可以上传 manipulated gradients，让全局模型偏移、误报或漏报

这两类风险会互相拉扯。很多 poisoning defense 希望看明文梯度或明文异常信号，但这又可能削弱隐私保护。AP-PPFL 的价值在于把 Paillier 同态加密、dual-server secure computation、参数重要性投票和 cosine-similarity filtering 放到同一个框架里，试图同时保护梯度机密性和过滤恶意更新。

TrustFed-RHIO 则把另一个落地维度补进来：IIoT 攻击检测不只要隐私，还要特征选择、延迟、鲁棒性和可解释性。它把 DP-enhanced FL、特征选择优化，以及 SHAP / LIME 这类解释方法组合起来，用于工业 IoT 攻击检测。

对 primer 来说，这条线的工程启发很直接：

- `FL` 不是完整安全边界，只是“不集中原始数据”的训练拓扑
- `DP` 保护贡献影响，但不自动抵御恶意客户端
- `HE / secure aggregation / dual-server` 可以保护更新计算过程，但要明确不串谋假设和计算成本
- `robust aggregation / poisoning filter` 要避免为了检测攻击而重新暴露明文梯度
- `XAI` 在工业场景不是装饰，而是帮助安全运营人员判断模型告警能否执行

所以 IIoT privacy tech 的成熟表述应该从：

- `用 FL 保护数据`

升级为：

- `用 protected update + robust filtering + DP accounting + explainability + deployment gate 共同保护训练和上线`

### 18A.29 DAP / VDAF：MPC 正在变成可标准化的 telemetry 基础设施

IETF Privacy Preserving Measurement 工作组的 Distributed Aggregation Protocol（DAP）是 2026 年值得放进 primer 的一个信号：MPC 不再只是在论文里做“两方安全求和”，而是开始被写成浏览器、App、SDK 和独立聚合服务都能实现的互联网协议。

DAP 的核心数据流很适合初学者理解：

1. 客户端本地生成一个 measurement，例如“某功能是否被使用”或“一次延迟值”。
2. 客户端不把 measurement 明文发给单一服务器，而是把它切成两份 input shares。
3. 两个 non-colluding aggregators 分别拿到一份 share。
4. aggregators 通过 VDAF 协议验证和聚合 share。
5. collector 只拿到聚合结果，而不是单个用户的原始 measurement。

Mock data 可以长这样：

```json
{
  "client_measurement": {
    "client_id": "device_local_only",
    "metric": "ai_summary_used",
    "value": 1,
    "time_bucket": "2026-05-06T10:00:00Z/1h"
  },
  "dap_upload": {
    "task_id": "feature-usage-v1",
    "report_id": "rpt_7f3a",
    "leader_input_share": "base64url:share_a...",
    "helper_input_share": "base64url:share_b...",
    "public_extensions": {
      "time_bucket": "2026-05-06T10:00:00Z/1h"
    }
  },
  "collector_output": {
    "task_id": "feature-usage-v1",
    "time_bucket": "2026-05-06T10:00:00Z/1h",
    "aggregate": {
      "sum_ai_summary_used": 184231,
      "contributing_reports": 1290044
    }
  }
}
```

这条线的工程启发是：

- `secure aggregation` 可以作为标准协议和托管服务出现，而不只是某个 FL 系统里的内部组件
- privacy boundary 来自 `客户端分片 + 两个聚合方不串谋 + VDAF 验证 + 只发布聚合结果`
- 它适合 telemetry、浏览器测量、产品使用指标、错误率统计这类“只需要总体统计”的场景
- 它不适合需要按用户回查、低阈值 drill-down、复杂 join 后明细分析的场景

### 18A.30 DP 工具链的新重点：实现 bug 本身就是隐私风险

PEPR 2026 的 “Privacy in Theory, Bugs in Practice” 把一个很实际的问题讲清楚：DP 的数学定义强，不代表工程实现天然正确。DP 库、DP SQL engine、budget accountant、clipping、noise sampler、partition selection、thresholding、seed management 任一环节出错，都可能让理论保证失效。

这对 primer 很重要，因为很多团队会把 DP 理解成：

- 找一个库
- 配 epsilon
- 跑查询
- 输出结果

更成熟的工程流程应该是：

- 明确保护单位、邻接关系、贡献上界和组合规则
- 对 DP mechanism 做单元测试和统计测试
- 对边界参数做 fuzz / property testing
- 对 SQL rewrite、group-by、join、filter、空分区和小分区做灰盒测试
- 把 privacy budget consumption 写进审计日志
- 对发布结果做回归测试，防止后续优化绕过 noise / threshold

Mock data 可以把 DP audit log 设计成这样：

```json
{
  "query_id": "q_campaign_reach_2026_05_06",
  "privacy_unit": "user_id",
  "mechanism": "dp_count",
  "epsilon_spent": 0.35,
  "delta_spent": 1e-8,
  "contribution_bounds": {
    "max_rows_per_user": 3,
    "max_groups_per_user": 2
  },
  "release_policy": {
    "min_noisy_count": 100,
    "blocked_dimensions": ["zip_code", "raw_device_id"]
  },
  "tests": {
    "noise_sampler_statistical_test": "pass",
    "partition_selection_edge_cases": "pass",
    "sql_rewrite_regression": "pass"
  }
}
```

一个很实用的判断是：如果一个 DP 系统不能解释“每次发布消耗了多少预算、保护哪个单位、哪些测试证明实现没有被绕过”，它还只是研究 demo，不是生产隐私基础设施。

### 18A.31 LLM 私有微调的主线：威胁模型、审计和工具链比口号更重要

PEPR 2026 的 “Private Tuning of LLMs in Practice” 延续了 VaultGemma / JAX Privacy 这条线：企业把 proprietary data 用于 LLM fine-tuning 时，隐私风险不是抽象的“模型可能泄露”，而是要明确成可测试的 threat model。

一个可落地的 LLM DP fine-tuning 数据流可以是：

```json
{
  "training_job": {
    "base_model": "gemma-family-model",
    "fine_tuning_dataset": "customer_support_redacted_v3",
    "privacy_unit": "customer_account_id",
    "dp_method": "DP-SGD",
    "clipping_norm": 1.0,
    "target_epsilon": 8.0,
    "delta": 1e-7
  },
  "risk_checks": {
    "memorization_probe": "before_and_after_comparison",
    "canary_extraction_test": "pass",
    "membership_inference_eval": "pass",
    "utility_eval": {
      "support_resolution_score_delta": -0.018
    }
  },
  "release_gate": {
    "privacy_accountant_attached": true,
    "model_card_includes_dp_limits": true,
    "deployment_approved": true
  }
}
```

对初学者最重要的不是记住某个库名，而是记住 LLM privacy 的落地顺序：

1. 先定义要防谁、保护哪个训练集、攻击者能看到什么。
2. 再决定是否用 DP fine-tuning、TEE inference、RAG redaction、synthetic data 或组合方案。
3. 最后用 extraction / memorization / utility evaluation 证明方案没有只停留在架构图上。

### 18A.32 Clean room 的下一步不是“更多连接器”，而是把连接器纳入责任边界

截至 2026-05-07，clean room 产品化已经明显进入 connector / external table / lakehouse federation 阶段。Snowflake 文档显示，Data Clean Room 可以通过 connector 访问 Amazon S3 中的外部 parquet 数据；AWS Clean Rooms 也在 2026-02 支持 remote Apache Iceberg REST catalogs。

这对 primer 的增量启发是：clean room 的安全边界不再只是平台内表、模板和输出阈值，还包括：

- 外部存储 bucket / prefix 的最小权限
- connector service account 的身份与轮换
- 外部表是否被 provider 显式允许
- consumer 是否知道自己正在分析 external table
- 第三方 connector 的责任边界和附加条款
- consent / data use rights 是否随数据进入协作执行层

更直白地说，`clean room can access external data` 是落地能力，但不是隐私保证。它让数据工程更顺，但也要求把 IAM、catalog、connector、consent、purpose 和 audit 放进同一张架构图。

### 18A.33 Clean room 可观测性正在成为隐私工程的一部分

AWS Clean Rooms 2026-01 的 detailed monitoring 更新很适合补进导论：它把 collaboration SQL query 的运行指标发布到 CloudWatch，用于性能、资源和成本监控。表面看这是运维功能，但对隐私工程也重要。

原因是生产 clean room 不是一次性演示，而是长期协作系统。它需要持续回答：

- 哪些成员在跑哪些模板
- 查询运行是否突然变慢或扫描异常增大
- 访问预算是否被快速消耗
- 输出是否出现过细维度或异常小桶
- payer / runner / creator 的操作是否能追溯

所以 clean room 的成熟度可以这样判断：如果它只有访问控制和模板，没有 monitoring、audit、budget、alert 和 release review，就还没有真正进入生产运营形态。

## 18B. 已落地场景与可引用案例

这一节只放已经明确能引用到产品、平台或云能力的案例。

### 18B.1 Gboard：confidential federated analytics 已用于新词发现

Google Research 在 2025-03-04 公开了 Gboard 的 confidential federated analytics 落地。

它很适合作为 primer 里的“生产级 cross-device private analytics”案例，因为它同时体现了：

- 设备侧原始数据不集中到普通分析平台
- 服务器侧处理步骤是受约束、可验证的
- 最终结果以 DP 形式发布

而且这不是 demo，文中直接给出了跨 `900+` 语言的新词发现背景，以及 “两天发现 3600 个印尼语缺失词” 这种具体效果信号。

### 18B.2 Pixel Recorder：PPI 已开始处理 AI 时代的非结构化使用洞察

Google Research 在 2025-10-30 公开说明，PPI 已部署到 Pixel 的 Recorder 应用，用 Gemma 3 4B 在 TEE 中对 transcript 做 topic classification，再用 DP 输出聚合洞察。

这很值得引用，因为它说明：

- private analytics 已不只是 count / sum
- 可以开始处理 transcript、summary、user intent 这种 AI 原生数据
- 但仍然保持“只发 DP 聚合结果，不放出原始明文”

### 18B.3 Apple Private Cloud Compute：private cloud AI 的代表性架构

Apple 在 2024-06-10 首次公开 PCC 架构，并在 2024-10-24 进一步公开 Security Guide、Virtual Research Environment 与部分关键源码。

它可作为“private cloud AI”最典型的引用案例，因为它把以下东西一起做了出来：

- 设备验真后再发送请求
- 生产镜像透明化 / 可验证
- 无通用 shell、无通用日志
- 允许研究者自行检查二进制、透明日志与虚拟化运行环境

即使你不采用 Apple 的具体实现，这种“可验证云上 AI”模式已经是一个明确产品方向。

### 18B.4 BigQuery Data Clean Rooms：云上受控协作环境的典型产品形态

Google Cloud 的 BigQuery data clean rooms 已经是非常适合 business / analytics 团队理解的落地形态。

它值得写进 primer，不是因为“clean room 很新”，而是因为它把治理做成了具体产品能力：

- analysis rules
- aggregation threshold
- differential privacy analysis rule
- query templates

这让 clean room 从“概念上的安全协作房间”变成了可操作的平台控件集合。

截至 2026-04-22，BigQuery 文档还给了一个很实用的状态信号：

- `differential privacy enforcement in BigQuery data clean rooms` 已 GA
- `parameter-driven privacy budgeting` 仍是 preview

这提醒你在设计方案时要区分：

- 已稳定可依赖的发布控制
- 仍在演进中的预算控制接口

### 18B.5 AWS Clean Rooms：把 privacy budget 与访问次数预算产品化

AWS Clean Rooms 已有 DP 能力；到 2025-10-02 又新增 `data access budgets`，可限制表在 SQL、PySpark、训练或推理场景下被分析的次数；到 2026-01-02 又新增 collaboration query 的详细监控，支持把查询指标发布到 CloudWatch。

这很值得引用，因为它说明工业界开始把两种预算都产品化：

- `privacy budget`
- `access budget`

前者约束“能泄露多少统计信息”，后者约束“这份数据总共能被碰多少次”。

而 2026 年初的监控能力又补上了第三层：

- `operational observability`

对很多真实合作来说，这三层缺一不可，因为没有观测就很难把 clean room 当成长期运行的生产系统。

### 18B.6 AWS Clean Rooms ML synthetic data：联合建模但不暴露真实训练样本

2025-11-30，AWS Clean Rooms 又把 `privacy-enhancing synthetic datasets` 做成了可直接用于 custom ML training 的产品能力。

这很值得写进 primer，因为它对应的是很多团队真正会遇到的场景：

- 双方想联合训练回归 / 分类模型
- 但不愿意把 join 后明细直接交给训练代码
- 希望平台只发 synthetic output，并把隐私参数和阈值留在治理层

这类场景说明 synthetic data 已经不只是研究论文中的“可能方向”，而是开始进入：

- campaign optimization
- fraud detection
- medical research

这类可以直接落到业务预算和模型训练流程里的产品能力。

### 18B.7 Android Private Compute Core / PCC-compliant on-device AI：已经不是概念，而是大规模产品约束

如果你希望 primer 不只覆盖“云上的 privacy tech”，那 Android 体系里的 `Private Compute Core (PCC)` 也值得保留为已落地案例。

Android Developers 在 2024-10-24 公开说明 Gemini Nano / AICore 的隐私与安全设计时，明确写到 AICore 是 `PCC compliant`，只能与有限的合规系统组件交互，且不能直接访问互联网。

这类案例的价值在于它说明：

- on-device private AI 不只是“模型放在端上”
- 还包括进程隔离、网络出口限制、受控模型下载路径
- 以及把 AI runtime 放进更严格的系统级隐私边界

如果再结合 Android 官方虚拟化 use case 文档里 `Content Safety On-device` 的案例，你会发现 “privacy-preserving on-device inference” 已经不是论文概念，而是服务于超大规模终端的产品工程实践。

### 18B.8 Snowflake Data Clean Rooms：template-driven clean room 已成为主流平台形态之一

如果你希望 primer 里的 clean room 案例不只来自单一云厂商，那 Snowflake 也是很值得补进去的已落地平台。

Snowflake 官方文档明确把 Data Clean Rooms 描述为可配置、隔离的协作环境，参与方可以指定：

- 哪些查询能跑
- 哪些列可 join / 可投影
- 是否启用 differential privacy

而且它已经不是“只能做 provider-consumer 的静态房间”这种早期形态。文档当前状态显示，新 collaboration experience 已经可用，能力也覆盖：

- inventory forecasting
- last touch attribution
- multi-party insights
- machine learning

这对 primer 很有价值，因为它让读者更容易建立一个现实判断：

- clean room 不是某一家公司的专有术语
- 主流产品形态正在收敛到 `template + join policy + projection policy + optional DP + controlled activation`
- 工程重点不在“有没有一个神秘算法”，而在“能不能把查询能力产品化为受控模板”

### 18B.9 Microsoft Viva Insights：DP 已经进入企业组织分析产品，而不只是研究工具

Microsoft 的 Viva Insights 也值得作为一个“DP 已落地”的引用案例保留。

Microsoft Learn 的技术隐私指南明确写到，organization insights 通过三层机制保护聚合结果：

- minimum group sizes
- differential privacy
- distribution masking

更具体地说，文档直接说明 differential privacy 已用于 organization insights，目标是让管理者看见群体层面的协作模式，但不能有把握地推出某个个体的具体情况。

这个案例的重要性在于：

- 它不是 clean room，也不是研究 demo
- 它说明 DP 已经进入日常企业分析产品
- 它把 DP 放在一个非常典型的“高敏感、强解释、面向非隐私专家用户”的产品环境里

对初学者来说，这个例子能帮助建立一个很实用的直觉：

- DP 不只属于 census、学术 benchmark 或广告测量
- 它同样适合组织分析、Copilot 使用度量、员工协作指标这类容易引发个体可识别风险的场景

### 18B.10 AWS Clean Rooms：clean room 已开始接入长期运营与自动化工作流

如果你想给读者一个“clean room 不只是一次性查询房间，而是长期运行系统”的案例，AWS Clean Rooms 现在已经足够典型。

除了前面提到的 DP、data access budgets 和 CloudWatch 详细监控外，AWS 在 2025-07-31 还上线了 EventBridge 事件发布，在 2025-04-30 上线了 multiple results receivers。

这两个点看起来不像密码学论文里的创新，但对真实落地很关键，因为它们说明 clean room 已经开始具备：

- `异步工作流集成`
- `多方结果分发`
- `结果校验与协作透明度`

对产品团队来说，这类能力的价值在于：

- 你可以把 clean room 查询接进 activation、报表、告警和审批流
- 你可以把“谁收到什么结果”做成可配置治理，而不是线下约定
- 这让 privacy collaboration 更像生产系统，而不是专家手工操作

### 18B.11 AWS Clean Rooms PySpark：隐私协作开始承载真实大规模数据工程 workload

2025-03-18，AWS Clean Rooms 让 PySpark 可用于 clean room；2025-09-04 又支持 PySpark job 的 compute size 配置；2026-01-15 支持 PySpark analysis template 参数；到 2026-04-17，进一步支持为 PySpark job 配置 Spark properties，例如 memory overhead、task concurrency、network timeout。

这条产品演进很值得引用，因为它说明 clean room 的落地边界已经从：

- `固定 SQL 聚合`

扩展到：

- `可参数化分析模板`
- `自定义 PySpark 算法`
- `按 workload 调整算力`
- `按 analysis 调整 Spark runtime 参数`

AWS 官方给的例子包括广告测量和制药 / 医疗机构在真实世界临床试验数据上的协作分析。对 primer 来说，这个案例的重点不是 AWS 某个参数本身，而是一个更大的落地信号：

- privacy tech 真正进入生产后，瓶颈经常不是密码学原语，而是 `runtime tunability`
- 只有当性能、失败诊断、成本控制、模板审批和输出治理都能一起工作时，clean room 才能从“安全查询环境”变成“可长期使用的数据协作平台”

### 18B.12 AWS Clean Rooms remote Iceberg catalog：clean room 开始贴近企业现有 lakehouse

2026-02-18，AWS Clean Rooms 支持 remote Apache Iceberg REST catalogs。它的落地意义在于：协作方可以把已经在 S3 和远程 catalog 里管理的 Iceberg 表直接接进 clean room，而不是先复制表元数据或额外搭 ETL。

这对 primer 很有价值，因为它说明 clean room 的生产化不只是隐私算法成熟，还包括与现有数据平台的摩擦下降：

- publisher / advertiser 可以用各自已有 catalog 做广告 spend 分析
- 数据不需要为了协作而先移动到一个新系统
- governance surface 更接近企业已经在用的 lakehouse / catalog 管理方式

换句话说，clean room 的落地能力正在从 `secure query product` 扩展到 `secure collaboration layer over existing data estate`。

### 18B.13 AWS Clean Rooms incremental ID mapping：always-on measurement 需要增量身份映射

2025-09-26，AWS Clean Rooms 与 AWS Entity Resolution 的集成支持 incremental ID mapping。

这条更新看起来很产品化，但对隐私技术很关键：很多广告测量和受众协作不是一次性 batch join，而是每天都有新用户、新购买、新删除、新 consent 状态。

如果没有增量处理，团队通常会被迫：

- 重跑完整 ID mapping
- 复制更多中间数据
- 让协作结果滞后
- 增加重复访问数据的次数

增量 ID mapping 把 clean room 更明确地推向 always-on collaboration：

- measurement partner 可以持续维护离线购买数据
- advertiser / publisher 可以更新 campaign outcome 分析
- privacy controls 仍然留在 collaboration 内，而不是散落到外部手工流程

### 18B.14 AWS Clean Rooms change requests：协作关系本身也进入治理面

2025-12-18，AWS Clean Rooms 支持对已有 collaboration 发起 change request，包括增加成员、修改成员能力、调整 auto-approval 设置，并要求成员审批和记录 change history。

这条案例补足了一个常被忽略的点：隐私系统保护的不只是数据表和查询，也保护协作关系的变化。

典型例子是 publisher 和 advertiser 已经建好 clean room 后，advertiser 想把 marketing agency 加为结果接收方。技术上这不是新算法，但治理上非常关键：

- 新成员不能绕过既有隐私控制
- 结果接收权需要被显式审批
- 成员变化需要可追溯

对企业落地来说，这类 capability 往往决定 clean room 能不能长期运行，因为真实业务协作里的成员、角色、数据提供方和结果接收方都会变化。

### 18B.15 OneTrust + Snowflake：consent-aware clean room 把同意信号带进协作执行层

2026-04-28，OneTrust 宣布与 Snowflake 合作，把 OneTrust consent signals 嵌入 Snowflake Data Clean Rooms 的多方协作流程。

这条案例很适合补进 primer，因为它说明 clean room 的治理边界正在继续前移：

- 早期 clean room 更关注“原始数据不外流”
- 进阶 clean room 关注 query template、join policy、projection policy、DP 和阈值
- consent-aware clean room 则把“这个用户 / 这条记录是否允许用于这个目的”也带进协作执行环境

对广告、出版商、零售媒体和数据合作团队来说，这个方向非常现实。很多合作不是简单地问“表能不能 join”，而是要同时满足：

- 这条记录是否有当前有效 consent
- consent 是否覆盖 measurement、activation、model training 等具体用途
- 用户撤回后，后续 collaboration 是否会自动排除
- audit log 能否解释某次输出为什么包含或不包含某类记录

这说明隐私技术正在从 `compute privacy` 扩展到 `policy-aware computation`。真正可落地的 clean room 不能只会算，还要能把 consent、purpose、retention、access budget 和 output policy 一起执行。

### 18B.16 Snowflake Collaboration API GA：clean room 从 provider-consumer 走向对称多方协作

Snowflake Data Clean Rooms 在 2026-02-05 预览新的 Collaboration Data Clean Rooms 架构，并在 2026-04-09 的更新中把 Collaboration API 推到 GA。

这个变化值得引用，因为它代表 clean room 产品形态从传统的 provider / consumer 模式，继续走向：

- fully symmetric collaboration
- multi-party participation
- flexible roles
- fine-grained access controls
- collaboration-level configuration APIs

这对真实业务很重要。广告主、publisher、agency、measurement partner、retail media network 往往不是一对一关系；每一方可能既提供数据，也接收结果，还需要对模板、自动审批和数据访问做不同授权。

所以，Snowflake 这类更新的意义不是“又多了一个 API”，而是说明 clean room 正在变成一个多方治理系统，而不仅是两张表之间的安全 join。

### 18B.17 Snowflake Freeform SQL visibility：自由分析也要回到 provider 可见的治理面

2026-04-23，Snowflake Data Clean Rooms 更新了 Freeform SQL Data Offerings 的可见性：data provider 可以通过 `VIEW_DATA_OFFERINGS` 查看 Freeform SQL View 名称和 column policies。

这条看起来很小，但对落地很关键。很多团队希望 clean room 支持更自由的 SQL 或自定义代码，因为固定模板无法覆盖所有分析需求；但自由度越高，provider 越需要知道：

- 暴露出去的是哪一个 view
- 哪些列策略正在生效
- 是否存在不该投影或不该 join 的字段
- review / approval 时能否看到足够上下文

因此，生产级 clean room 的方向不是简单地“开放 freeform SQL”，而是：

- `自由分析能力 + provider visibility + column policy + approval workflow + audit`

只有这样，自定义分析才不会绕开治理层。

### 18B.18 Snowflake Trust Center Data Security GA：隐私协作前先知道敏感数据在哪里

2026-04-24，Snowflake 宣布 Trust Center 里的 Data Security experience GA，支持自动识别 PII、PCI、PHI 等高风险数据类别，并在 Snowsight 里集中展示分类结果、合规映射、masking policy 覆盖情况和分类错误。

这条案例不是 clean room 算法，但对 privacy tech primer 很重要，因为很多隐私协作失败不是因为没有 PET，而是因为团队根本不知道：

- 哪些表含有敏感字段
- 哪些列已经有 masking policy
- 哪些对象分类失败，需要人工决定
- 哪些数据类别会影响 clean room、DP 发布、合成数据训练或外部共享策略

所以一个更完整的生产链路应该是：

- `sensitive data discovery -> classification/tagging -> masking / policy -> clean room or PET execution -> audit`

这说明 privacy tech 的落地越来越像一套控制面，而不是单个计算协议。

### 18B.19 Snowflake Data Clean Rooms UI in Snowsight：clean room 进入日常协作界面

Snowflake 在 2026-04-30 的 Data Clean Rooms 更新中把 Snowsight 里的 clean room UI 推到 public preview。

这个案例值得引用，因为它说明 clean room 已经不再只是 API 或后台流程，而是进入数据团队日常使用的工作台：

- browse collaboration
- create / join / edit collaboration
- run analysis
- use Cortex Code for natural-language assistance

对企业落地来说，这意味着隐私系统的风险边界也变了：

- 更多非底层工程用户会直接操作 collaboration
- natural-language assistance 会降低复杂查询和配置变更的门槛
- 因此 template approval、column policy visibility、operation audit 和 role design 会变得更关键

简化地说，clean room 的成熟不是“让更多人绕过治理更快查数据”，而是“让更多人能在治理框架里完成协作”。

### 18B.20 AWS Clean Rooms privacy-related functions：把 consent string 变成可执行查询条件

AWS Clean Rooms SQL reference 已经提供 `consent_gpp_v1_decode` 和 `consent_tcf_v2_decode` 这类 privacy-related functions。

这条落地案例很适合补进 primer，因为它连接了两个过去常常分离的层：

- consent / policy 层：用户是否同意某类处理
- computation 层：某条记录是否能进入某次 clean room analysis

在广告、publisher、retail media 和跨境数据协作里，真实问题经常不是“能不能安全 join”，而是：

- 这条记录在当前 jurisdiction 下能不能用于 measurement
- 是否能用于 targeted advertising
- 是否能进入 model training
- 用户撤回后，后续分析是否自动排除

因此，这类函数不是小工具，而是 `policy-aware computation` 的基础积木。它让 clean room 查询可以直接把 GPP / TCF 解析结果作为 filter、template precondition 或 audit field。

### 18B.21 AWS Clean Rooms ML privacy protections：lookalike 建模的保护边界更明确

AWS Clean Rooms ML 文档把 lookalike / audience modeling 的隐私风险讲得比较工程化：核心风险是 membership inference，即训练数据方推断 seed data 里有哪些人，或 seed data 方推断训练数据里有哪些人。

文档列出的产品保护包括：

- seed data provider 不直接观察 Clean Rooms ML 输出
- training data provider 看不到 seed data
- lookalike model 基于训练数据的随机样本创建，并包含大量不匹配 seed audience 的用户
- 每个 seed-specific 参数可使用多个 seed customer
- 建议 seed data 至少 500 用户
- 不向 training data provider 提供 user-level metrics

这对 primer 很有价值，因为它把“privacy-preserving ML”从抽象口号落到了具体 threat model：

- 谁可能从输出反推谁在输入里
- 哪些中间指标不能暴露
- seed size 为什么是隐私控制，而不只是模型质量要求
- 为什么用户级指标通常比聚合模型效果更危险

在实际设计 ad network / retail media lookalike 时，这类保护边界比“用了 ML，所以先进”更重要。

### 18B.22 PrunePrivyTune：把模型压缩、DP fine-tuning 和泄漏评估放在一条链路里

2026 年 4 月发表的 PrunePrivyTune 很适合放进 primer，因为它不是只说“给 LLM 加 DP”，而是把三个生产中会同时出现的问题连起来：

- 模型太大，部署和推理成本高
- fine-tuning 可能记住敏感训练样本
- 合成文本看起来有用，但可能仍然过于接近原始训练数据

它的工程链路可以简化成：

1. 先用 layer representation 的相似性找出冗余 transformer layer，做结构化 pruning
2. 再用 LoRA 做参数高效 fine-tuning
3. fine-tuning 阶段使用 DP-SGD，限制单个样本对更新的影响
4. 最后用训练数据抽取攻击、perplexity、BERTScore 等指标评估合成输出是否过度贴近训练数据

这条研究线给落地系统的启发是：`privacy-preserving LLM` 不应该只看训练时有没有 DP，还要看压缩、微调、合成输出、攻击评估是不是连成闭环。

### 18B.23 Privacy Sandbox case studies：浏览器侧 PET 已经进入广告投放与测量试点

Google Privacy Sandbox 的公开案例能帮助初学者看到另一类落地路径：不是把所有数据放进 clean room，而是先在浏览器侧减少可用的用户级跟踪信号。

两个值得放进导论的案例：

- MiQ 测试 Attribution Reporting API，用于 conversion measurement，并探索把 summary reports 放到云端 TEE 中处理。
- Audigent / NextRoll 使用 Protected Audience API，把 interest group 激活到 DSP 工作流里，公开案例提到大规模浏览器覆盖、数百万次 impressions 和跨大量域名投放。

这里的技术重点不是“浏览器 API 取代所有 PET”，而是：

- 用户级事件被限制在浏览器 / API 边界内
- 输出更偏 aggregate、delayed、thresholded 或 noisy
- 后端仍然需要 TEE、aggregation service、clean room、审计和业务校验

因此，Privacy Sandbox 更适合被理解成 `on-device / browser-mediated privacy boundary`，它和 clean room、TEE、DP 是互补关系。

### 18B.24 Fifty5Blue / Meta / AWS Clean Rooms：PSI 落地的关键是 consent + audit + scale

AWS 2026 年 3 月的 Fifty5Blue 案例很适合作为真实落地引用。它的业务问题不是抽象的“安全求交”，而是 cross-media measurement 里的 panel data exchange：

- Fifty5Blue 有一组已同意参与的 panelists
- publisher 有广告 impression logs
- Fifty5Blue 只想拿到这些 consented panelists 的曝光数据
- publisher 不应该知道完整 panelist membership
- 外部 auditor 要能验证 Fifty5Blue 确实只请求了已同意用户

案例里把 AWS Clean Rooms 用作 PSI 协作环境，并配合 S3、KMS、CloudTrail、bucket versioning 做审计。它还提到，相比此前基于 HE 的 PSI 方案，这种方式在集成和单日数据分析上更容易扩展。

这给 primer 的落地启发是：

- PSI 不是单独存在的协议，而是业务流程的一步
- consent 过滤必须发生在 match 前后都可解释的位置
- 审计能力不是附加文档，而是隐私系统的一部分
- scale、成本、排障时间经常决定 PET 能否上线

### 18B.25 SPH Media / Decentriq：TEE clean room 用于受监管广告主的一方数据协作

Decentriq 的 SPH Media 案例展示了另一条落地路线：用 TEE-backed clean room 支撑 publisher 与受监管广告主的一方数据协作。

这个案例里，SPH Media 和一家 global wealth manager 上传 hashed email，在 clean room 里完成：

- shared customer matching
- 基于共享特征创建 lookalike audience
- publisher 侧激活 audience
- 用点击率和站内继续浏览等指标评估效果

案例还提到，平台和双方都不能直接访问彼此数据，且该设计经过新加坡 PDPC 评估，认为没有导致双方之间披露个人数据；A/B 测试中，更小、更近期的 lookalike segment 表现更好。

它对 primer 的价值在于：TEE clean room 的卖点不是“把所有东西都加密了所以万无一失”，而是把一方数据协作变成受限操作：

- 输入是 hashed identifiers 和有限特征
- 计算发生在 enclave / clean room 中
- 输出是可激活 segment 或聚合效果指标
- 合规评估、audience freshness、segment size 也会影响隐私和业务效果

### 18B.26 Comscore / AWS Clean Rooms：媒体测量正在从“搬数据”转向“协作查询”

Comscore 的 AWS case study 是一个更传统但很重要的落地场景：媒体测量公司需要把 panel data 与多个外部数据源交叉分析，以提升 audience 和 campaign effectiveness 的洞察质量。

这个案例值得放进 primer，因为它说明 clean room 的一个朴素价值：

- 以前常见做法是把数据从一个环境迁移到另一个环境，再在内部分析
- clean room 让多方可以在受控环境里 match、analyze、collaborate
- join key、double-blind matching、pre-encrypted S3 data、BI dashboard 都是工程化落地的一部分

这类案例提醒我们，PET 不只是“更强密码学”，也包括减少数据复制、减少长期明文落地、减少为一次分析临时搭建高风险管道。

### 18B.27 PMIRS：多模态检索里的隐私保护开始从单点算法走向系统组合

2026 年 Scientific Reports 的 PMIRS 论文讨论了多用户、多模态 image-text retrieval 的隐私保护。它把几个并不陌生的组件组合在一起：

- federated learning：训练时尽量让用户数据留在本地
- lightweight CLIP-like encoder：把图文转成 embedding
- block-wise projection：对 query embedding 做混淆
- AES-CBC：加密推理过程中的 query / result
- Diffie-Hellman：处理多用户 key management

它的启发不是“这就是多模态隐私的最终答案”，而是：当 AI 应用变成 retrieval、RAG、agent memory、enterprise search 时，隐私边界会跨过训练、索引、查询、返回结果和多用户授权。只讨论训练集 DP 或只讨论传输加密都不够。

### 18B.28 Snowflake custom Python in Data Clean Rooms：受控协作开始支持自定义代码

Snowflake Data Clean Rooms 在 2026-03-05 的更新中支持 collaboration 里上传和使用 custom Python code。这个案例值得单独写进落地部分，因为真实企业协作经常不满足于固定 SQL：

- 广告测量可能需要自定义归因、分桶和异常过滤
- 生命科学协作可能需要自定义统计或特征工程
- 金融风控可能需要更复杂的模型评分或校验逻辑

但 custom code 也意味着 clean room 的治理边界要扩大。生产系统需要能回答：

- 谁提交了代码
- 代码版本和依赖是什么
- 代码能读取哪些列
- 输出是否仍然遵守 threshold / DP / result receiver 规则
- 失败、重跑和性能指标是否可观测

这个案例把 clean room 的定位进一步推向 `受控计算平台`，而不只是 `受控查询界面`。

### 18B.29 Snowflake Collaboration Data Clean Rooms：多方协作从 preview 走向 GA

Snowflake 在 2026-04-09 的 Data Clean Rooms 更新中把 Collaboration API 标为 GA。这个变化值得写进落地案例，因为它把 clean room 从传统的 provider / consumer 双方模型推向更对称的多方协作模型。

Snowflake 文档里的 `Multi-party insights` 模板给了一个很具体的广告测量例子：

- Publisher 提供曝光数据
- Advertiser 提供购买数据
- Identity Partner 提供 customer spine
- 三方通过标准化 join key 做聚合分析
- collaboration specification 控制谁能运行模板、谁能访问 data offering、谁只是贡献数据

这类产品形态说明 clean room 的落地重点正在从“两个表能不能 join”变成“多个参与方的角色、权限、模板、审批、激活和成本如何被治理”。

### 18B.30 OneTrust + Snowflake：consent signal 开始进入 clean room 执行链路

OneTrust 在 2026-04-28 宣布把 consent signals 嵌入 Snowflake Data Clean Rooms。这个案例很适合放进 primer，因为它把 privacy tech 从“数据能不能被安全计算”推进到“这条数据按用户授权到底能不能被用于这个目的”。

一个落地系统里，consent-aware clean room 至少要能回答：

- 这条用户记录是否允许用于 analytics
- 是否允许用于 activation
- 是否允许与某类 partner 协作
- consent 变更后，下游 clean room 是否能及时反映
- audit trail 是否能证明查询和激活遵守了用户选择

这说明 clean room 的隐私控制不应只停在 join threshold、blocked columns 和 DP；真实生产环境还需要把 consent、purpose、jurisdiction 和 data use policy 接进执行链路。

### 18B.31 Snowflake Data Clean Rooms UI in Snowsight：业务用户入口也要纳入治理

Snowflake 在 2026-04-30 的更新中把 Data Clean Rooms UI in Snowsight 标为 public preview，并且集成 Cortex Code 的自然语言辅助。这个案例看起来像 UI 更新，但对隐私工程有一个更深的含义：当 clean room 从工程团队的 API 变成业务团队可操作的界面，治理面会扩大。

需要关注的不是“有 UI 了”，而是：

- 自然语言生成的分析是否仍受 template、role、approval 和 output policy 限制
- 业务用户创建或加入 collaboration 时是否能看清数据用途和权限
- activation 操作是否有 consent / purpose gate
- UI 操作、agentic 操作和 API 操作是否进入同一套审计

这条案例补充了一个落地判断：privacy tech 越产品化，越要把人机交互层纳入威胁模型。

### 18B.32 Divvi Up / Firefox：DAP 已经用于生产级隐私 telemetry

Divvi Up 是 ISRG 的 privacy-preserving metrics 服务，基于 DAP / VDAF，并由 Janus 实现 leader / helper 等角色。Divvi Up 官方材料和 PEPR 2026 program 都把 Firefox 作为真实部署信号：这不是“把 MPC 跑在小样本 benchmark 上”，而是把隐私聚合接进大规模软件 telemetry。

一个 Firefox / App telemetry 的简化数据流可以是：

```json
{
  "client_event": {
    "metric": "crash_recovery_succeeded",
    "value": 1,
    "local_context": {
      "app_version": "128.0",
      "platform": "windows"
    }
  },
  "privacy_transform": {
    "protocol": "DAP",
    "vdaf": "Prio3",
    "shares": ["sent_to_leader", "sent_to_helper"]
  },
  "operator_roles": {
    "leader": "Divvi Up / Janus",
    "helper": "independent_aggregator",
    "collector": "product_metrics_team"
  },
  "published_metric": {
    "platform": "windows",
    "app_version": "128.0",
    "sum_crash_recovery_succeeded": 504932,
    "report_count": 877104
  }
}
```

这个案例给 primer 的落地判断是：

- 当业务目标只是 population-level metric，不要默认收集用户级明细再做脱敏
- DAP 把“不要让任何单方看到用户 measurement 明文”做成可复用协议
- 生产系统仍然要处理 task configuration、batching、重放保护、聚合阈值、运营监控和独立聚合方治理
- 如果 collector 后续发布过细分桶，仍可能需要 DP、阈值或发布审查

### 18B.33 Attribution API + DAP：广告测量正在把 DP aggregation 写进协议层

2026-02 的 IETF draft “DAP Extensions for the Attribution API” 说明了另一个落地趋势：浏览器广告测量不只是“在 clean room 里 join 两张表”，也可能把 attribution reporting、DP aggregation 和 DAP 这类隐私测量协议结合起来。

可以把它理解成下面的数据流：

```json
{
  "source_event": {
    "source_site": "publisher.example",
    "campaign_id": "cmp_42",
    "coarse_time": "2026-05-06"
  },
  "trigger_event": {
    "advertiser_site": "shop.example",
    "conversion_value_bucket": "purchase_50_100"
  },
  "browser_report": {
    "api": "Attribution Reporting API",
    "aggregation": "DAP extension",
    "dp_mode": "aggregate_report_with_noise"
  },
  "advertiser_output": {
    "campaign_id": "cmp_42",
    "noisy_conversion_count": 12034,
    "noisy_value_sum_bucketed": 812000
  }
}
```

这条线对 ad tech 很关键：浏览器侧 PET、clean room、PSI / PJC、server-side attribution 不是互斥路线。它们分别适合不同控制点：

- 浏览器侧协议适合减少跨站用户级跟踪
- clean room 适合已有一方数据的多方协作分析
- PSI / PJC 适合私密匹配和交集求和
- DP 适合最终聚合结果发布

### 18B.34 DP SQL / DP library testing：隐私系统需要把测试结果也产品化

Oblivious 在 PEPR 2026 的 DP library grey-box testing 分享里提到，用新测试框架在 11 个开源 DP 库中发现 13 个 bug。这个案例虽然是研究/工程分享，但非常适合作为“落地场景”引用：DP 一旦进入 SQL engine 或 BI 平台，就必须像数据库一样有测试、兼容性、回归和发布纪律。

落地系统可以把 DP 测试结果作为 release artifact：

```json
{
  "dp_engine_release": "dp-sql-2026.05",
  "supported_mechanisms": ["dp_count", "dp_sum", "dp_histogram"],
  "test_report": {
    "mechanism_property_tests": 1840,
    "sql_rewrite_regressions": 612,
    "known_edge_cases": [
      "empty_group",
      "single_user_dominates_group",
      "join_expands_contribution",
      "floating_point_noise_sampler"
    ],
    "blocking_failures": 0
  },
  "release_gate": {
    "privacy_review": "approved",
    "security_review": "approved",
    "budget_accounting_compatibility": "approved"
  }
}
```

这提醒初学者：隐私技术落地不只是选算法，还包括让算法在升级、迁移、SQL 优化、配置变更和产品操作中持续正确。

### 18B.35 Snowflake external S3 connector：clean room 开始直接贴近外部数据湖

Snowflake Data Clean Room 的 Amazon S3 external data connector 已经 GA。它允许协作者从 clean room 中访问云存储里的 parquet 数据，并要求 provider 显式允许使用 external table；文档同时提示外部表会带来额外安全风险，且 data subject consent management 仍由客户负责。

这个案例值得作为落地引用，因为它把 clean room 从“平台内受控协作”推进到“跨存储边界的受控协作”。真实企业不会为了每次协作都复制一份完整明细表，更多时候会希望把已有 lakehouse、catalog、IAM 和 clean room 连起来。

落地判断：

- connector 减少 ETL 和数据复制，但扩大了 IAM / external table / third-party connector 的治理面
- provider approval、consumer warning、最小权限和 bucket prefix scope 是隐私协作的一部分
- consent 不会因为数据进入 clean room 就自动成立，需要接入 OneTrust 这类 consent / data use governance 层或自建 policy engine

### 18B.36 AWS Clean Rooms detailed monitoring：协作查询进入可观测运营

AWS Clean Rooms 在 2026-01-02 支持 collaboration SQL query 的 detailed monitoring，并把 query performance 与 resource utilization 发布到 CloudWatch。AWS 给的例子是广告主监控 campaign lift analysis query 的性能和成本。

这个案例说明 clean room 已经不只是“能安全 join”，而是要进入日常运营：

- 数据提供方关心访问预算、查询频率和输出策略
- 分析方关心任务耗时、扫描量和成本
- 平台团队关心异常查询、重试、失败和容量
- 隐私团队关心是否出现过细分析、异常反复查询或预算绕过

所以 clean room 的落地证据不应只包括架构图，还应包括 monitoring dashboard、alert rule、query audit log 和 budget consumption record。

## 18. 一页式总结

- `去标识化`：先把明显敏感信息拿掉，但不等于绝对安全。
- `DP`：保护统计结果和模型输出，不让单个人的影响过于明显。
- `TEE`：保护“数据正在被计算时”的执行环境。
- `clean room`：受控的数据合作环境，不是单一算法。
- `PSM`：私密查名单，只回答 yes/no。
- `PSI`：私密求交集。
- `PJC / PI-Sum`：私密匹配后再做求和或聚合。
- `MPC`：多方一起算，不直接暴露各自输入。
- `HE`：在密文上直接做计算。
- `联邦学习`：数据不集中，模型更新来回走。
- `联邦分析`：数据不集中，统计结果来回聚合。

最重要的一句：

- 很多真实系统不是“选一种隐私技术”，而是“把几种技术叠起来”。

## 19. 推荐继续阅读

下面这些都是比较靠谱的一手或高质量资料：

### 官方与项目资料

1. Google Cloud, Confidential Computing overview
2. Google Cloud, Google Cloud Attestation
3. Google Cloud BigQuery, Share sensitive data with data clean rooms
4. Google GitHub, `google/private-membership`
5. TensorFlow Federated, Federated Learning overview
6. OpenDP, What is Differential Privacy?
7. Microsoft Research, Microsoft SEAL
8. Apple Security Research, Security research on Private Cloud Compute
9. Google Research, Parfait: Enabling private AI with research tools
10. AWS Clean Rooms, Differential Privacy
11. BigQuery, Restrict data access using analysis rules
12. BigQuery, Use differential privacy
13. BigQuery, Extend differential privacy
14. Android Developers Blog, An introduction to privacy and safety for Gemini Nano
15. Android Open Source Project, Virtualization use cases
16. AWS Clean Rooms, Privacy-enhanced synthetic dataset generation
17. Google Research, DP-Auditorium
18. Snowflake Documentation, Snowflake Data Clean Rooms overview
19. Microsoft Learn, Viva Insights technical privacy guide
20. Google Research, Designing synthetic datasets for the real world
21. Snowflake Documentation, Differential privacy in Snowflake Data Clean Rooms
22. AWS Clean Rooms, multiple results receivers
23. AWS Clean Rooms, EventBridge events
24. Google Research, Differentially Private Insights into AI Use
25. Google Research, Reasoning-Driven Synthetic Data Generation and Evaluation
26. Google Research, VaultGemma
27. Google Research, Differentially private machine learning at scale with JAX-Privacy
28. AWS Clean Rooms, configurable Spark properties for PySpark
29. AWS Clean Rooms, remote Apache Iceberg REST catalogs
30. AWS Clean Rooms, incremental ID mapping with AWS Entity Resolution
31. AWS Clean Rooms, change requests for existing collaborations
32. Scientific Reports, Integrated privacy-preserving data aggregation framework for IoT networks
33. Intelligent Systems with Applications, DP fine-tuning LLMs for synthetic clinical notes
34. USENIX PEPR 2026, Profile-Then-Simulate
35. OneTrust, consent-aware data clean rooms with Snowflake
36. Snowflake Data Clean Rooms, Collaboration API GA
37. Snowflake Data Clean Rooms, Freeform SQL Data Offering visibility
38. Snowflake Trust Center, Data Security GA
39. Snowflake Data Clean Rooms, UI in Snowsight public preview
40. AWS Clean Rooms, privacy-related consent functions
41. AWS Clean Rooms ML, privacy protections for lookalike modeling
42. AWS Clean Rooms API, ML synthetic data parameters
43. Google Privacy Sandbox, MiQ Attribution Reporting API case study
44. Google Privacy Sandbox, Audigent and NextRoll Protected Audience API case study
45. AWS for Industries, Fifty5Blue cross-media measurement with AWS Clean Rooms
46. Decentriq, SPH Media first-party data collaboration case study
47. AWS, Comscore data collaboration with AWS Clean Rooms
48. Snowflake Data Clean Rooms, custom Python code in collaborations
49. Snowflake Data Clean Rooms, Cortex Code support in Collaboration Data Clean Rooms
50. Snowflake Data Clean Rooms, Collaboration API GA
51. Snowflake Documentation, Multi-party insights template
52. OneTrust, consent-aware data clean rooms with Snowflake
53. Snowflake Data Clean Rooms UI in Snowsight public preview
54. Snowflake Data Clean Rooms, external data from Amazon S3
55. AWS Clean Rooms, detailed monitoring for collaboration queries

### 论文与研究资料

1. Google Research, Practical Secure Aggregation for Federated Learning on User-Held Data
2. Google Research, Confidential Federated Computations
3. Google Research, Privacy-Preserving Secure Cardinality and Frequency Estimation
4. Google Research, Private Join and Compute from PIR with Default
5. Google Research, Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions
6. NIST, De-Identification of Personal Information
7. NIST, Guidelines for Evaluating Differential Privacy Guarantees
8. Google Research, Discovering new words with confidential federated analytics
9. Google Research, Toward provably private insights into AI use
10. Google Research, Generating synthetic data with differentially private LLM inference
11. Google Research, SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs
12. Google Research, Beyond billion-parameter burdens: Unlocking data synthesis with a conditional generator
13. Google Research, Sequentially Auditing Differential Privacy
14. AWS Clean Rooms, Privacy-enhanced synthetic dataset generation
15. Google Research / TMLR, Reasoning-Driven Synthetic Data Generation and Evaluation
16. Google Research, Differentially Private Insights into AI Use
17. Google Research, Fine-tuning LLMs with user-level differential privacy
18. Google Research, Scaling Laws for Differentially Private Language Models
19. Google Research, JAX-Privacy: A library for differentially private machine learning
20. Scientific Reports, An adaptive differential privacy framework for clinical LLMs
21. Scientific Reports, Privacy-preserving federated credit risk models
22. Computer Networks, Differential Privacy for Data Sharing: Evolution and Full-Lifecycle Applications in Generative AI
23. Scientific Reports, An integrated privacy preserving data aggregation framework for IoT networks using homomorphic encryption and secure computation
24. Intelligent Systems with Applications, Assessment of differentially private fine-tuning of large language models for synthetic clinical note generation
25. USENIX PEPR 2026, Profile-Then-Simulate: Can LLMs Faithfully Generate Differentially Private Synthetic Data?
26. Computer Networks, Differential Privacy for Data Sharing: Evolution and Full-Lifecycle Applications in Generative AI
27. Neural Networks, Differentially private data augmentation via LLM generation with discriminative and distribution-aligned filtering
28. NDSS 2026, SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs
29. Machine Learning, PrunePrivyTune: Accelerating Language Models with Pruning and Differentially Private Fine-Tuning
30. Scientific Reports, A privacy-preserving multi-user retrieval system for multimodal artificial intelligence
31. Information Polity, Privacy-Enhancing or Privacy-Elusion Technology? A Critical View of (Pseudo)Synthetic Data Based on Deep Learning
32. Discover Computing, A lightweight privacy-preserving reranker enables customizable hybrid retrieval for enterprise document search
33. USENIX PEPR 2026, DPSynth: From Research to Production
34. USENIX PEPR 2026, Generating High-Quality Tabular Synthetic Data at Scale
35. USENIX PEPR 2026, A DP Framework for Gaining Insights into AI Chatbot Use
36. Scientific Reports, FedDriftGuard adaptive federated learning with differential privacy
37. IBM Research, FHEIns: Fully Homomorphic Encryption Acceleration for Large Data Applications
38. Scientific Reports, TrustFed-RHIO: optimization-driven DP federated learning for IIoT attack detection
39. Cybersecurity, AP-PPFL: anti-poisoning privacy-preserving federated learning

## 20. 参考链接

- Google Cloud Confidential Computing overview: https://cloud.google.com/confidential-computing/docs/confidential-computing-overview
- Google Cloud Attestation: https://cloud.google.com/confidential-computing/docs/attestation
- BigQuery data clean rooms: https://cloud.google.com/bigquery/docs/data-clean-rooms
- Google private-membership: https://github.com/google/private-membership
- TensorFlow Federated overview: https://www.tensorflow.org/federated/federated_learning
- TensorFlow Federated with Differential Privacy: https://www.tensorflow.org/federated/tutorials/federated_learning_with_differential_privacy
- OpenDP, What is Differential Privacy?: https://opendp.org/what-is-differential-privacy/
- OpenDP, Typical Workflow: https://docs.opendp.org/en/stable/getting-started/typical-workflow.html
- Microsoft SEAL: https://www.microsoft.com/en-us/research/project/microsoft-seal/
- Apple Security Research, Security research on Private Cloud Compute: https://security.apple.com/blog/pcc-security-research/
- Apple Security Research, Private Cloud Compute overview: https://security.apple.com/com/blog/private-cloud-compute/
- Google Research, Parfait: Enabling private AI with research tools: https://research.google/blog/parfait-enabling-private-ai-with-research-tools/
- AWS Clean Rooms Differential Privacy: https://docs.aws.amazon.com/clean-rooms/latest/userguide/differential-privacy.html
- AWS Clean Rooms data access budgets announcement: https://aws.amazon.com/about-aws/whats-new/2025/10/aws-clean-rooms-data-access-budgets/
- BigQuery analysis rules: https://cloud.google.com/bigquery/docs/analysis-rules
- BigQuery, Use differential privacy: https://cloud.google.com/bigquery/docs/differential-privacy
- BigQuery, Extend differential privacy: https://cloud.google.com/bigquery/docs/extend-differential-privacy
- Android Developers Blog, An introduction to privacy and safety for Gemini Nano: https://android-developers.googleblog.com/2024/10/introduction-to-privacy-and-safety-gemini-nano.html
- Android Open Source Project, Virtualization use cases: https://source.android.com/docs/core/virtualization/usecases
- AWS Clean Rooms synthetic data generation: https://docs.aws.amazon.com/clean-rooms/latest/userguide/synthetic-data-generation.html
- Google Research, DP-Auditorium: https://research.google/pubs/dp-auditorium-a-large-scale-library-for-auditing-differential-privacy/
- Snowflake Data Clean Rooms overview: https://docs.snowflake.com/en/user-guide/cleanrooms/getting-started
- Microsoft Learn, Viva Insights technical privacy guide: https://learn.microsoft.com/en-us/viva/insights/advanced/privacy/privacy
- Google Research, Designing synthetic datasets for the real world: https://research.google/blog/designing-synthetic-datasets-for-the-real-world-mechanism-design-and-reasoning-from-first-principles/
- Snowflake, Differential privacy in Snowflake Data Clean Rooms: https://docs.snowflake.com/en/user-guide/cleanrooms/differential-privacy.html
- AWS Clean Rooms, multiple results receivers: https://aws.amazon.com/about-aws/whats-new/2025/04/aws-clean-rooms-multiple-results-receivers-collaboration/
- AWS Clean Rooms, EventBridge events: https://aws.amazon.com/about-aws/whats-new/2025/07/aws-clean-rooms-publishes-events-amazon-eventbridge/
- Google Research, Practical Secure Aggregation for Federated Learning on User-Held Data: https://research.google/pubs/practical-secure-aggregation-for-federated-learning-on-user-held-data/
- Google Research, Confidential Federated Computations: https://research.google/pubs/confidential-federated-computations/
- Google Research, Privacy-Preserving Secure Cardinality and Frequency Estimation: https://research.google/pubs/privacy-preserving-secure-cardinality-and-frequency-estimation/
- Google Research, Private Join and Compute from PIR with Default: https://research.google/pubs/private-join-and-compute-from-pir-with-default/
- Google Research, Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions: https://research.google/pubs/private-intersection-sum-protocols-with-applications-to-attributing-aggregate-ad-conversions/
- Google Research, Discovering new words with confidential federated analytics: https://research.google/blog/discovering-new-words-with-confidential-federated-analytics/
- Google Research, Toward provably private insights into AI use: https://research.google/blog/toward-provably-private-insights-into-ai-use/
- Google Research, Generating synthetic data with differentially private LLM inference: https://research.google/blog/generating-synthetic-data-with-differentially-private-llm-inference/
- Google Research, Beyond billion-parameter burdens: Unlocking data synthesis with a conditional generator: https://research.google/blog/beyond-billion-parameter-burdens-unlocking-data-synthesis-with-a-conditional-generator/
- Google Research, Differentially Private Insights into AI Use: https://research.google/pubs/differentially-private-insights-into-ai-use/
- Google Research, Sequentially Auditing Differential Privacy: https://research.google/pubs/sequentially-auditing-differential-privacy/
- Google Research, SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs: https://research.google/pubs/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/
- Google Research, Reasoning-Driven Synthetic Data Generation and Evaluation: https://research.google/pubs/reasoning-driven-synthetic-data-generation-and-evaluation/
- Google Research / TMLR, Reasoning-Driven Synthetic Data Generation and Evaluation: https://openreview.net/forum?id=QtSI0l2Xsb
- Google Research, VaultGemma: https://research.google/blog/vaultgemma-the-worlds-most-capable-differentially-private-llm/
- Google Research, Fine-tuning LLMs with user-level differential privacy: https://research.google/blog/fine-tuning-llms-with-user-level-differential-privacy/
- Google Research, Differentially private machine learning at scale with JAX-Privacy: https://research.google/blog/differentially-private-machine-learning-at-scale-with-jax-privacy/
- Google DeepMind, JAX-Privacy: https://github.com/google-deepmind/jax_privacy
- arXiv, Scaling Laws for Differentially Private Language Models: https://arxiv.org/abs/2501.18914
- arXiv, JAX-Privacy: A library for differentially private machine learning: https://arxiv.org/abs/2602.17861
- AWS Clean Rooms, configurable Spark properties for PySpark: https://aws.amazon.com/about-aws/whats-new/2026/04/aws-clean-rooms-configurable-properties-pyspark/
- AWS Clean Rooms API, WorkerComputeConfigurationProperties: https://docs.aws.amazon.com/clean-rooms/latest/apireference/API_WorkerComputeConfigurationProperties.html
- AWS Clean Rooms, remote Apache Iceberg REST catalogs: https://aws.amazon.com/about-aws/whats-new/2026/02/aws-clean-rooms-remote-iceberg-catalogs/
- AWS Clean Rooms, incremental ID mapping with AWS Entity Resolution: https://aws.amazon.com/about-aws/whats-new/2025/09/aws-clean-rooms-incremental-id-mapping-entity-resolution/
- AWS Clean Rooms, change requests for existing collaborations: https://aws.amazon.com/about-aws/whats-new/2025/12/clean-rooms-change-requests-existing-collaborations/
- Scientific Reports, An adaptive differential privacy framework for clinical LLMs: https://www.nature.com/articles/s41598-026-45883-6
- Scientific Reports, Privacy-preserving federated credit risk models: https://www.nature.com/articles/s41598-025-34536-9
- Computer Networks, Differential Privacy for Data Sharing: Evolution and Full-Lifecycle Applications in Generative AI: https://www.sciencedirect.com/science/article/abs/pii/S1389128626003476
- Scientific Reports, An integrated privacy preserving data aggregation framework for IoT networks using homomorphic encryption and secure computation: https://www.nature.com/articles/s41598-026-48831-6
- Intelligent Systems with Applications, Assessment of differentially private fine-tuning of large language models for synthetic clinical note generation: https://www.sciencedirect.com/science/article/pii/S2667305326000347
- USENIX PEPR 2026, Profile-Then-Simulate: Can LLMs Faithfully Generate Differentially Private Synthetic Data?: https://www.usenix.org/conference/pepr26/presentation/bouzid
- Neural Networks, Differentially private data augmentation via LLM generation with discriminative and distribution-aligned filtering: https://www.sciencedirect.com/science/article/abs/pii/S0893608026001309
- NDSS 2026, SNPeek: Side-Channel Analysis for Privacy Applications on Confidential VMs: https://www.ndss-symposium.org/ndss-paper/snpeek-side-channel-analysis-for-privacy-applications-on-confidential-vms/
- OneTrust, consent-aware data clean rooms with Snowflake: https://www.globenewswire.com/news-release/2026/04/28/3282829/0/en/OneTrust-Introduces-a-New-Approach-to-Consent-Aware-Data-Clean-Rooms.html
- Snowflake Data Clean Rooms updates, Apr 9 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-04-09-dcr.html
- Snowflake Data Clean Rooms updates, Apr 23 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-04-23-dcr.html
- Snowflake Data Security in the Trust Center GA: https://docs.snowflake.com/en/release-notes/2026/other/2026-04-24-data-security-trust-center-ga
- Snowflake Data Clean Rooms updates, Apr 30 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-04-30-dcr
- AWS Clean Rooms, privacy-related functions: https://docs.aws.amazon.com/clean-rooms/latest/sql-reference/privacy-related-functions.html
- AWS Clean Rooms ML, privacy protections: https://docs.aws.amazon.com/clean-rooms/latest/userguide/ml-privacy.html
- AWS Clean Rooms API, MLSyntheticDataParameters: https://docs.aws.amazon.com/clean-rooms/latest/apireference/API_MLSyntheticDataParameters.html
- Google Privacy Sandbox, MiQ Attribution Reporting API case study: https://privacysandbox.google.com/resources/case-studies/miq
- Google Privacy Sandbox, Audigent and NextRoll Protected Audience API case study: https://privacysandbox.google.com/resources/case-studies/audigent-nextroll
- AWS for Industries, Fifty5Blue cross-media measurement with AWS Clean Rooms: https://aws.amazon.com/blogs/industries/privacy-enhanced-cross-media-measurement-how-fifty5blue-formerly-kantar-media-leveraged-aws-clean-rooms-to-establish-audit-transparency-during-panel-data-exchange/
- Decentriq, SPH Media first-party data collaboration case study: https://www.decentriq.com/case-study/sph-media-explores-first-party-data-collaboration-with-decentriqs-data-clean-rooms
- AWS, Comscore Maintains Privacy while Cross-Analyzing Data Using AWS Clean Rooms: https://aws.amazon.com/solutions/case-studies/comscore/
- Springer Machine Learning, PrunePrivyTune: https://link.springer.com/article/10.1007/s10994-026-07016-y
- Scientific Reports, A privacy-preserving multi-user retrieval system for multimodal artificial intelligence: https://www.nature.com/articles/s41598-026-40734-w
- Information Polity, Privacy-Enhancing or Privacy-Elusion Technology? A Critical View of (Pseudo)Synthetic Data Based on Deep Learning: https://journals.sagepub.com/doi/10.1177/0282423X251412328
- Discover Computing, A lightweight privacy-preserving reranker enables customizable hybrid retrieval for enterprise document search: https://link.springer.com/article/10.1007/s10791-026-09993-z
- Snowflake Data Clean Rooms updates, Mar 5 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-03-05-dcr
- Snowflake Data Clean Rooms updates, Mar 26 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-03-26-dcr
- Snowflake Data Clean Rooms updates, Apr 9 2026: https://docs.snowflake.com/en/release-notes/2026/other/2026-04-09-dcr
- Snowflake Data Clean Rooms, Multi-party insights: https://docs.snowflake.com/en/user-guide/cleanrooms/collab-multi-party-insights
- Snowflake, Data Clean Rooms Enable Privacy-First Multiparty Collaboration: https://www.snowflake.com/en/blog/data-clean-rooms-multiparty-collaboration/
- OneTrust, consent-aware data clean rooms with Snowflake: https://www.onetrust.com/news/onetrust-introduces-a-new-approach-to-consent-aware-data-clean-rooms/
- USENIX PEPR 2026, DPSynth: From Research to Production: https://www.usenix.org/conference/pepr26/presentation/pravilov-dpsynth
- USENIX PEPR 2026, Generating High-Quality Tabular Synthetic Data at Scale: https://www.usenix.org/conference/pepr26/presentation/gade
- USENIX PEPR 2026, A DP Framework for Gaining Insights into AI Chatbot Use: https://www.usenix.org/conference/pepr26/presentation/pravilov-chatbot
- Scientific Reports, FedDriftGuard adaptive federated learning with differential privacy for concept drift in edge environments: https://www.nature.com/articles/s41598-026-51535-6
- IBM Research, FHEIns: Fully Homomorphic Encryption Acceleration for Large Data Applications: https://research.ibm.com/publications/fheins-fully-homomorphic-encryption-acceleration-for-large-data-applications-with-in-storage-processing
- Scientific Reports, TrustFed-RHIO: an optimization-driven differential privacy federated learning framework for secure and explainable IIoT attack detection: https://www.nature.com/articles/s41598-026-45277-8
- Cybersecurity, AP-PPFL: an anti-poisoning privacy-preserving federated learning method: https://link.springer.com/article/10.1186/s42400-026-00583-6
- NIST, De-Identification of Personal Information: https://www.nist.gov/publications/de-identification-personal-information
- NIST, Guidelines for Evaluating Differential Privacy Guarantees: https://www.nist.gov/publications/guidelines-evaluating-differential-privacy-guarantees
- IETF PPM Working Group, Distributed Aggregation Protocol latest draft: https://ietf-wg-ppm.github.io/draft-ietf-ppm-dap/draft-ietf-ppm-dap.html
- IETF, Distributed Aggregation Protocol for Privacy Preserving Measurement draft-16: https://www.ietf.org/archive/id/draft-ietf-ppm-dap-16.html
- IETF, Distributed Aggregation Protocol Extensions for the Attribution API draft: https://www.ietf.org/ietf-ftp/internet-drafts/draft-thomson-ppm-dap-attribution-01.html
- Divvi Up, Writing DAP standards: https://divviup.org/blog/writing-dap-standards/
- Divvi Up, Firefox privacy-preserving metrics deployment: https://divviup.org/blog/divvi-up-in-firefox/
- Divvi Up, About Divvi Up: https://divviup.org/about/
- USENIX PEPR 2026, Conference Program: https://www.usenix.org/conference/pepr26/program
- USENIX PEPR 2026, Production Multi-Party Computation via the Distributed Aggregation Protocol: https://www.usenix.org/conference/pepr26/presentation/geoghegan
- USENIX PEPR 2026, Privacy in Theory, Bugs in Practice: Grey-Box Testing for Differential Privacy Libraries: https://www.usenix.org/conference/pepr26/presentation/simmons-marengo
- USENIX PEPR 2026, Private Tuning of LLMs in Practice: From VaultGemma to Custom Fine-Tuning: https://www.usenix.org/conference/pepr26/presentation/pravilov-llms
- Snowflake Data Clean Room, external data from an Amazon S3 bucket: https://docs.snowflake.com/en/user-guide/cleanrooms/external-data-aws
- AWS Clean Rooms, detailed monitoring for collaboration queries: https://aws.amazon.com/about-aws/whats-new/2026/01/clean-rooms-detailed-monitoring-collaboration-queries/
