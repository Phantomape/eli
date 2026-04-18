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

### 论文与研究资料

1. Google Research, Practical Secure Aggregation for Federated Learning on User-Held Data
2. Google Research, Confidential Federated Computations
3. Google Research, Privacy-Preserving Secure Cardinality and Frequency Estimation
4. Google Research, Private Join and Compute from PIR with Default
5. Google Research, Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions
6. NIST, De-Identification of Personal Information
7. NIST, Guidelines for Evaluating Differential Privacy Guarantees

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
- Google Research, Practical Secure Aggregation for Federated Learning on User-Held Data: https://research.google/pubs/practical-secure-aggregation-for-federated-learning-on-user-held-data/
- Google Research, Confidential Federated Computations: https://research.google/pubs/confidential-federated-computations/
- Google Research, Privacy-Preserving Secure Cardinality and Frequency Estimation: https://research.google/pubs/privacy-preserving-secure-cardinality-and-frequency-estimation/
- Google Research, Private Join and Compute from PIR with Default: https://research.google/pubs/private-join-and-compute-from-pir-with-default/
- Google Research, Private Intersection-Sum Protocols with Applications to Attributing Aggregate Ad Conversions: https://research.google/pubs/private-intersection-sum-protocols-with-applications-to-attributing-aggregate-ad-conversions/
- NIST, De-Identification of Personal Information: https://www.nist.gov/publications/de-identification-personal-information
- NIST, Guidelines for Evaluating Differential Privacy Guarantees: https://www.nist.gov/publications/guidelines-evaluating-differential-privacy-guarantees
