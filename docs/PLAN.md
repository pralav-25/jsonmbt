# jsonmbt — typed JSON source files for MoonBit（.json.mbt）

> 状态：**计划书 v0.4.0**（2026-10-06 立项，同日四轮修订 v0.2/v0.3/v0.3.1；**2026-10-07 v0.4.0 定位与防御体系升级**：§0 护城河三件套 + 失效判据 / §2 质疑裁定表 + typify 覆盖 / §7 R1b 三层止损 + 新增 R7 + §7.1 保险单 / §10 R11 定位可证伪制度 + 结论入仓制度）· **状态唯一载体 = §5 里程碑表**（本文件其他处不写进度时点句）
> 格式：`.json.mbt` · 包/仓：`rustin-beep/jsonmbt` · CLI：`jsonmbt`

---

## 0. 一句话与第一性原理

**`.json.mbt` 是 JSON 的类型化源码形态**——以 MoonBit 子集表达的 JSON 数据，`moon check` 即 schema 验证、`moon fmt` 即格式统一，经 jsonmbt 引擎**降级输出干净、安全、确定性的 `.json`**。TS→JS 的关系，在 JSON 世界的复刻。

**第一性原理（压缩/解压模型）**：`.json.mbt` 是浓缩语言，`build` 降级是解压，`import` 是压缩。**解压对值无损且确定；类型头/注释是压缩侧元信息，不进解压契约**（元信息留在源格式里持续生效是特性非缺陷——TS 编译成 JS 也"丢"类型，没人说 TS 有损）——本规范全部边界裁定由此推出：空数组=压缩时信息不足（诚实标注）；Int64=压缩时选更大容器（无损优先）；字符串化=改数据本身（违反值无损契约，只能显式 opt-in）。

**排他性定位（形态先例矩阵的唯一空位）——三条腿同时成立才排他**：

1. **工具链白嫖**：数据格式的工具链 = **真实语言的工具链**。Jsonnet/CUE/Dhall/Nickel/KCL 全部为 fmt/LSP/IDE 自建全套（Dhall 的采用瓶颈即「集成、工具链、LSP 的完整体验」），jsonmbt 的 fmt/check/info/LSP 零成本继承 moon。
   **⚠ 此腿可被复制**：`config.rs` + 一个百行抽取器即可在 Rust 复现同款白嫖（`rustc`/`rustfmt`/`rust-analyzer` 照样免费）。**它是入场券，不是护城河。**
   *失效判据*：moon 对 `.json.mbt` 形态文件停止 check/fmt/LSP；或宿主语言删除 L0 所需语法 ≥1 处。
2. **受限子集的制度保证**：L0–L2 冻结使「任何人都不可能把逻辑塞进数据文件」成为**制度性事实**，逃生门原则承接溢出需求——通用语言给不了这一条。
   *失效判据*：某通用语言生态出现被广泛采用的等价制度性冻结实践。
3. **「文件 = 文档」格式法（D-7）**：一个 `.json.mbt` 恰好一个顶层 `pub let`。「从 `.rs`/`.go` 生成 JSON」**没有确定宾语**——这是通用语言结构上给不出的。
   *失效判据*：某通用语言工具链官方引入「文件级单文档」约定。

**求值分级冻结（L0–L2）是腿 2/3 的看门人**：白嫖只要求「子集」（`if`/函数也是合法 MoonBit，工具链白嫖能扛很久）；**先崩的是确定性降级**——降级器要么开始求值（= 造语言运行时），要么按 D-8 ② 拒绝；`let`/条件一旦能跨文件或带副作用，「这个文件的 JSON」无法定义（D-7 失守）。**逃生门原则**：json.mbt 表达不了的，写真 MoonBit 去（FFI/.wat 皆可）——那是隔壁房间，不是本格式的扩张理由；逃生门的存在让分级冻结变得可坚持（Go 的 cgo/汇编同理；Jsonnet 死于没有逃生门——所有需求都涌进 DSL 本体）。

## 1. 是什么

三段式定义（探针实证过的边界）：

1. **格式 = MoonBit 子集**：`struct` 定义 + `let` 字面量值。`.json.mbt` 是合法 MoonBit 源文件——moon 全家桶（check/fmt/info）零适配白嫖：
   - 类型即 Schema：字段类型/必填编译期验证，错误信息 IDE 级（探针实测：`Expr Type Mismatch / has type: String / wanted: Int` + 行列指向）
   - 重复键结构性不可能（record 重复 label 编译错）
   - 注释/尾逗号/格式统一天然合法
   - **语法实测补充**：record 字面量必须 `Server::{ ... }` 形态（裸 `Server { ... }` 报错 missing '::'）；record 字段位裸大整数字面量按期望类型定型（Int64 字段无需 L 后缀）；struct 定义字段换行分隔不收逗号、字面量收尾逗号
2. **求值分级**（核心规范，表达力 vs 可 diff 性的张力控制；分级冻结是求生不是保守——Jsonnet 功能蔓延是反面教材，逃生门原则见 §0）：
   - **L0 纯字面量**（MVP）：结构+值，零计算——diff 最友好基线
   - **L1 常量算术**（二期）：`port: 4000 + 43`
   - **L2 let 绑定引用**（二期）：单文件内 `let base = 443` → `port: base`
   - **禁用**：函数、条件、跨文件引用、任何副作用——保住"所见即所得"
3. **importer 摄取 + 降级单向**：
   - **降级**：`.json.mbt` → `.json` 确定性投影（类型名剥除、字面量直译）——方向单向
   - **摄取（importer）**：`jsonmbt import x.json` → 推断 struct（形状签名判重）+ 值直译，生成合法 `.json.mbt`。这是**摄取工具**不是语法反向（`.json` 不是 `.json.mbt` 的合法子集），桥由此搭上——存量 JSON 十亿级资产的迁移入口
   - 实测：10 样本合成矩阵 4 生成全绿 + 6 诚实拒绝；**Vitro 真实数据 44 张 19 裸 PASS / 25 REJECT 零死角**；**冻结分支 2469 张 48.1MB 全量压测 49% 裸 PASS、余下全部落在三个已实锤逃生门内（tagged-enum/空容器/动态键）——零未知形态**

## 2. 为什么（立项依据，全部一手实测）

1. **形态先例矩阵——市场已验证，空位确认**：

   | 先例 | 定位 | 体量 | 对 jsonmbt 的意义 |
   |---|---|---|---|
   | Jsonnet | 数据模板 → JSON | ~7k★，K8s/Grafana 在用 | 市场验证；功能蔓延 = R2 反面教材 |
   | CUE | 约束+统一 → JSON/OpenAPI | ~5k★ | CLI 动词面对齐对象；schema 导出设计参照 |
   | Dhall | total 类型化配置 | ~4k★ | **死因教训**：采用卡在「集成/工具链/LSP 完整体验」——自建工具链税是赛道通病，jsonmbt 白嫖 moon 零此税 |
   | Starlark | Python 确定性子集 | Google 系 | 「确定性语言子集」设计方法论的同类先例 |
   | Nickel/KCL | 新一代配置语言 | 新 | 赛道仍活跃；「又一个 DSL」难出头——「不是 DSL」是唯一差异化 |
   | **JSONC/JSON5** | JSON+注释（弱格式） | VS Code 承载 | **不做同类物**（自建工具链=Dhall 死因 + 正面撞在位者）；importer 支持 JSONC/JSON5 输入作迁移桥梁 |
   | **TypeScript satisfies** | `const x = {...} satisfies T` | TS 主流实践 | **需求存在最强证据**：类型化数据文件是真需求；jsonmbt 补上它缺的确定性降级一环 |

2. **JSON→MoonBit 类型推断有人做过但形态不构成威胁**：[gmlewis/json-to-moonbit](https://github.com/gmlewis/json-to-moonbit)——停更两年（toolchain 锚 2024-09）、1 star、纯片段生成器、**无「转回 JSON」闭环**。方向被验证过；差异化恰在「源格式 + 闭环」。
3. **schema 赛道四玩家全部错位**：typify.mbt、mizchi/jsonschema（5K 下载，**明确不支持从样本推断**——API 面已核实）、MoonJTD、moon_zod。输入全是 schema 不是数据文件。quicktype 的 20+ 目标语言无 MoonBit。`jsonmbt schema` 导出（P2）后四玩家变下游。**下游消费者另加 Rust 侧 `typify`（JSON Schema → Rust 类型）**——注意 **S → 各语言类型这一段已被 typify 占住**，jsonmbt 的差异化只在 **D（数据）→ S** 这一段，勿以为能独占整条链。
4. **vs YAML/TOML（人写配置在位霸主）——不同价值轴**：① **产物轴**（最硬）：YAML/TOML 的产物是自己；.json.mbt 的产物是 **JSON**——API 快照/testdata/CI 数据等「终态必须是 JSON」的场景 YAML 根本不参赛；② 类型轴：无 schema 无类型 vs 类型即文件头；③ 坑位对照：YAML 的 Norway 问题/隐式转换/缩进敏感、TOML 深嵌套 `[a.b.c]`/`[[x]]` 都是要学的语法——「不用学」是神话，区别只在显性还是踩坑式；④ 工具链轴：每语言生态各养解析器 vs 白嫖 moon 全家桶。
5. **「要学 MoonBit 子集」的反驳**：学的不是 MoonBit 是五个形态（struct/let/T::{}、[...]、四标量）；值体与 JSON 同构度高（`{port: 443}` ≈ `{"port": 443}`）；**语法由工具承载**——importer 生成类型头，人只改值；类型头兼职 schema 文档（JSON 要等价能力得额外学 JSON Schema，难十倍）。
6. **工具链维护税外包** + **命名三界无主**（`.json.mbt` 源格式 + 降级闭环 + 工具链白嫖的组合确认无主）。
7. **常见质疑与裁定（四轮外部评审收敛，2026-10-07）**——同类质疑直接引用本表，不再重跑：

   | 质疑 | 裁定 | 一手依据 |
   |---|---|---|
   | 选错宿主语言，Rust/Go 工程上更优 | **否** | §0 腿 1 可复制、腿 2/3 不可复制；换宿主 = 换产品 |
   | Rust/Go 生态同类工具全是反方向，需求不存在 | **部分否** | `go2cfg`（Go struct → jsonc/toml/yaml）即**正向**工具，缺口 = 生成一次即与类型脱钩；Go 世界的正向需求由 HCL/Jsonnet/CUE 承接（后两者参考实现即 Go）。真正空缺原因是**结构性**（§0 腿 3） |
   | 依赖 `moonbitlang/parser` 非公开 AST，不可持续 | **爆炸半径小** | 0.3.18→0.4.3 全接口 diff 96 行；本仓触及 10 类型中 7 个零变化、3 个仅加字段（被 `..` 吸收）——破坏性变更 0 次 |
   | 白嫖只是趁 MoonBit 工具链未固化，生态成熟即关窗 | **否** | TypeScript 十年反例（`const x = {...} satisfies T` / `.js` + `// @ts-check` / `tsconfig.json`）；成熟通常意味着 breaking 更少 |
   | `.mbti`/`.mbtx`/`.mbt.md` 等后缀可否扩展 | **见 §9 探针存档** | 仅 `.<name>.mbt.md` 候选（须 §8 评审；与 D-7 基数冲突需先定形态规则）；`.mbti` 只作 **schema 出口**（`moon info` 白嫖）；`.mbty` 与 `moon.pkg` pre-build 否决 |

## 3. 对谁（受众漏斗）

- **MoonBit 开发者**：配置/测试快照/数据文件的类型安全 + diff 格式噪音归零（第一波）；
- **JSONC 注释痛者**：「想给 JSON 加注释」的巨大存量——L0 全覆盖还多给类型和 fmt（第二波，importer 的 JSONC/JSON5 输入拆进入成本）；
- **非 MoonBit 生态**（五条路径，依赖从浅到深）：
  1. **产物消费者**（零感知层，量最大）：读 build 出的标准 JSON——protobuf 模式（producers 类型化 / consumers 标准化）；
  2. **CLI 黑盒用户**：import/build/check 当独立配置工具（**前提 = D-3 自持校验器**）；
  3. **Schema 书写者**：struct → `jsonmbt schema` → 喂 ajv/VS Code/OpenAPI——schema 四玩家变下游；
  4. **npm/npx 用户**：js 出口打 npm 包，`npx jsonmbt build` 一行进入；
  5. **在线页**：wasm-gc 粘贴→双向预览→下载，零安装。
- **机器生成管道（emitter 直产，importer 之外的第二入口）**：任意语言生成器按五条机械规则直产 .json.mbt（键去引号/值不变/尾逗号可留/字面量原样/头部加 struct+let），类型映射从源语言类型表直查（int→Int/int64→Int64/f64→Double/[]T→Array[T]）。落地三档：① 各语言自拼模板（零依赖）；② **官方 emitter 微包**（jsonmbt-go 先行，label/保留字/转义规则单点实现；其他语言等真实需求）；③ importer 面向存量文件。**已否决 C 库桥**（MoonBit→C→Go cgo 链路每环都比模板拼接贵，且 Go 产 .json.mbt ≈ 产 .json − 引号转义，无需调任何编译器）。
- **Vitro 协同**：第二个 wasm-gc 引擎、诊断方法论第二消费者、demo 互导流；**试点对象 = `diagnostics_data` 人审数据四张**（三张裸 PASS，concepts 加空容器启发后 PASS——真实数据实测可行）；**边界：Rust 冻结档案（2469 张 golden）不转**——档案活在分支上的意义就是不变，改写违背「历史快照不篡改」裁定；「能不能转」（能）与「该不该转」（活数据才转）是两个问题，**纳管判据 = 之后由谁维护**。
- **比赛申报**：名额二候选（独立仓，与 Vitro 非拆分）；如 linter 出山，作为主仓 0.9.0 伴生件。

## 4. 与 Vitro 的继承边界（**继承语言，不继承口音**）

| 继承 ✅ | 不继承 ❌ |
|---|---|
| J 系错误码稳定编号体系 | 教学卡默认全展开形态 |
| 位置精度（行列 + end 指向） | CLI 输出 emoji |
| 一行修复建议（help: ...） | "常见原因"默认内联 |
| 诊断内容资产（按需获取） | 教学定位本身 |
| 正/负样本锚纪律 | — |

**三层诊断形态**：
```
默认（一行）：config.mbt:3:9 [J3004] field 'port' expects Int32, got String
  help: change "443" to 443, or change the field type to String
按需（--explain J3004 / 链接）：教学全文 + 常见原因
在线页/详情面板：完整诊断卡（emoji + Vitro 风格全展开）——教学卡的家在这里
```

**importer 诊断的人话要求**（非生态用户是主要触发者）：拒绝信息必须可行动——「字段名 `content-type` 非法：连字符不可用于字段名，建议 `content_type`」，不是编译器原文；**「预期校准」话术**：拒绝文案说清「本格式已比浏览器多保真什么、停在哪、为什么」，让用户心智收敛为「jsonmbt ≥ 浏览器，永远」。

## 5. 里程碑（**状态唯一载体**——进度只在此表更新）

| 阶段 | 内容 | 验收锚 | 状态 |
|---|---|---|---|
| P0 探针 | 生态扫描 + moon 四件套行为矩阵 + 类型诊断采样 + parser→JSON 管道 + importer 探针四件（label 矩阵/推断原型/大文件性能/**null→Option·Int64·Map 三映射**）+ 竞品深扫 + **Vitro 真实数据两轮压测（44 张 + 冻结分支 2469 张）** | 管道输出合法 JSON；合成+真实+档案三层数据全测，REJECT 全部落在已实锤逃生门内 | ✅ 2026-10-06 |
| P1 MVP | L0 子集校验 + 降级输出器 + CLI（`build/check`，stdin `-` 约定，**D-10 rc/诊断通道契约**，**D-8 三不变量 + check=build dry-run**，**D-7 单文档基数**）+ **D-3 自持 L0 校验器**（伴生自持 fmt）+ 递归深度防护（参照 Vitro 陷阱 #28 wasm 栈预算探针法）+ 正负样本锚（含 D-9 字符串感知三形态 + 控制字符全族转义） | 端到端 `.json.mbt` → `.json` **按 D-11 规范化器 N 值语义等价**；诊断 ≤1 行 + help；**import→build 往返 N 等价锚**；10+ 样本锚 | 🟡 主体落地 2026-10-06：核心库（校验/降级/规范化）+ CLI（rc 0/1/4、stderr 前缀、原子写、stdin）+ moon test 语义锚全绿 + CLI 进程契约手验通过；**余项**：D-9 三形态锚与 import→build 往返锚属 importer 面（随 P1.5）、深度预算 128 待压测校准、层 2 Go 驱动骨架（P1.5 收口） |
| P1.5 | **importer v1**（形状签名判重 + tagged-enum 识别提示 + D-1 空容器启发 + D-2 Int64 推断落地）+ **`--check` 幂等闸**（flag 包/check 无写副作用/J9 证红）+ **确定性硬锚** + **AST 面快照入库（R1b-L1）** + **`.json.mbt` 的 struct 一律 `pub`**（换 `moon info` 白嫖完整 schema 出口，见 §2.3）+ 发 mooncakes **0.1.0**（首版勘误 2026-10-07：0.1.0 从未发布——mooncakes 无此包、git 无 publish 痕迹，首版直接 0.1.0） | 确定性锚全绿；check 闸 J9 证红；**Vitro diagnostics 四张试点**（.json.mbt 入仓 + 生成器读降级产物 + Vitro CI 加 `jsonmbt build --check` 步，锁版本） | 🟡 主体落地 2026-10-07：importer 全链（D-9 剥离/自持 RFC8259 解析器/形状推断 D-1 两级启发 + D-2 归一/生成）+ CLI import + `--check` 幂等闸（rc 2 首次占用，绿/红双验）+ moon test 49 锚全绿（含往返 N 等价锚）；层 2 Go 黑盒驱动雏形起步（tests/driver：golden 逐字节/rc 五值/幂等闸证红/确定性——issue #1 修复即首条锚）；**余项**：发 mooncakes **0.1.0**（首版勘误 2026-10-07：0.1.0 从未发布——mooncakes 无此包、git 无 publish 痕迹，首版直接 0.1.0）、层 2 驱动扩面（golden 文件化）、Vitro 四张试点（跨仓）——AST 面快照已落地（src/ast_snapshot_wbtest：自投影签名锚 L0 全变体，升级红=diff 投影逐节点定责）；exe 新鲜度门禁已落（驱动内置）；**#13/#14-3 处置 2026-10-08**：保留字字段名改名 + field-alias 注记（§6 终案）+ J4010 按容器路径分组——moon test 83 锚 / 层 2 驱动 16 用例全绿；**#14 批次 1+2a 落地 2026-10-08**：T?? 递归收窄 J2007 + 空容器 Never 默认占位（--strict 反向、J4031 hint、Never 预留）——层 1 91/91、层 2 25/25；**批次 2b 同日**：--fill 按声明类型重算值体（头逐字节保留、键集→变体消歧双形态、--fill --check 分档闸）——层 1 94/94、层 2 26/26，#14 三件全处置关单；**#5 doctor 落地 2026-10-08**：`jsonmbt doctor [dir]` 只读四项（包边界/撞名/check·build/fmt 影子）+ workspace 行，rc 1=挡住——层 2 20/20（+4 用例）；顺带实锤陷阱 #45（moon fmt 路径参数=包 pattern，项目外静默 rc=0 假成功）；**#6-4/#6-5 落地 2026-10-08**：--type-name-map（J1010 + unmatched hint）+ Map 值宿主派生（CasesEntry）+ migrate 三榜侦察（byte-eq/value-eq/reject，默认零写，内存 taken 模拟）——层1 87/87、层2 22/22；**#20/#21/#23 处置 2026-10-09**（#20/#21 = 60e684f 并行遗留批入库）：#20 importer 数组 null 泄漏收尾断言（JTNullLike 穿透容器残留即 fail loud——「靠调用方守约」变「靠机器」）+ #21 migrate emoji panic（UTF-16 码元 vs 码点索引同族第四处修复）；**#23 主诉求（build 无 -o → `.json.json`）HEAD 不复现**（唯一 `.json` 拼接点自 P1 未变 + import/migrate 三输出路径排查 + Vitro 原文件 `rules.json.mbt` 实测产 `rules.json` 正确——实录疑为 Vitro 滚动消费本仓 `_build` 旧/中间态 exe，陷阱 #41 下游版），处置 = 层 2 新锚 `default-output-name`（`.json` 存在 + `.json.json` 不存在点名拦截，埋雷证红 5 用例网）+ 落盘 hint 点名输出路径（建议 2）——层 1 104/104、层 2 30/30；**#24 处置 2026-10-10**（Vitro 教学资产批实战反馈，均 docs 级）：键域强校验指引三处落文（manual 可执行锚 + skill 3a + README——`Map[AlgoE, String]` 裸构造器键位 moon `[4014]` 语言层边界，本仓探针复核；正解带参枚举数组）+ `#|` 前导空格语义文档化（moon 原生语义非偏差）+ doctor 排版 note（全 `#|` 行统一前导空格 → hint 级 note，不计 rc；层 2 新锚 doctor-pipe-hint 红→绿）——层 1 106/106、层 2 31/31；**#22 落地 2026-10-10**（D-9 重写为输入 profile 单点定义 + 消解式收编尾逗号）：strip_jsonc 升级唯一宽松层（pending-comma 穿透注释消解 + last_sig guard + BOM 仅文件首，等长空格保行列），jsonparse 恒裸 RFC；--input json|jsonc（默认 jsonc，import/fill/migrate 三入口）；P2-6① 拆档（json 档保留原断言 + 默认档值等价翻转）；probe/samples 三合一样本 tsconfig_like + 层 2 第二循环与新用例 jsonc-input-profile——层 1 112/112、层 2 32/32；**#25 修复 2026-10-10**（L0 收 Group(Paren)：冗余圆括号剥除——moon fmt 规范产物可读，A((x))≡A(x) 合法 MoonBit 非预期收窄〔#16 同族：jsonmbt 不比 moon 严〕；分发层修复全值位统一剥 + Brace 块拒负锚 + ast 快照 G 变体登记 + probe/samples 样本 paren_payload）——层 1 114/114、层 2 32/32；**深度审阅处置 2026-10-10**（P1×3+P3×2 全修，审阅方突变注入验牙——禁用消解 4 红、guard 恒 false 负锚 panic 红）：P1-a lub 补 JTOption 臂（#20 元素位自聚合暴露旧空洞——Int? vs Int? 同型误拒）、P1-b unescape 花括号补代理检查（`\u{d800}` 曾 check 放行 build 崩——D-8 ① 被绕，#16 同族）、P1-c fill 标量 payload 空键 J3006（曾 panic）、P3 --strict 误用守卫 + CHANGELOG 增量链对账（104+2+6+2=114）——层 1 117/117、层 2 32/32；**#26 落地 2026-10-10**（emitter 含 `\n` 字符串产 `#|` 多行——教师循环形态保真，方案 1）：render_string_value 值位括号包裹 + 无前导空格规范形（\r 例外走转义）；探针实证 fmt 幂等（全值位合法 + fmt 归一缩进后不动）；教师循环端到端（未变条目 #| 存活/改值条目产 #|）；demo 矩阵勘误 JSONC 条目 + 补 #| 保形与圆括条目、skill 三处、README——层 1 118/118、层 2 32/32；**#27/#28/#29 处置 2026-10-10**（随机 12 项目实测批，#30 挂分析待裁定）：#27 l0_map 键 unescape（曾静默双层转义——migrate DIFF 哨兵首次抓真缺陷）、#28 is_legal_label 换 moon 词法区间表（π 类表外字母曾误判合法产 J0002；19 码点对账锚）、#29 migrate 只跳 .git/_build/node_modules/target + 跳过声明（点目录曾静默漏扫 42/650）——层 1 120/120、层 2 33/33；**#30 裁定落地 2026-10-10**（用户论证推翻 enhancement 定性：pretty=Go json.Encoder 选定口径非缺口，prettier 内联参数案撤销〔双主人冲突〕；结构性死结成文「逐字节还原人写源不可达」；migrate 三榜→四榜 LAYOUT-EQ〔紧凑归一逐字节等〕、VALUE-EQ 收窄为 1e2 类表示差；文档口径三处）——层 1 120/120、层 2 33/33；**#31 修复 2026-10-10**（保留字 stem 断链：D-7 期望名全链统一 sanitize_stem——build/check/doctor 曾用原文校验致 import 产物即红；方案 1+3 合体〔消费侧对齐 + D-7 语义成文「绑定名==sanitize_stem(stem)」常规恒等〕；层 2 新锚 reserved-stem-chain 四路全链）——层 1 120/120、层 2 34/34；**#18 落地 2026-10-10**（生成器重写为宽度驱动 fmt 不动点：整行≤84 record 单行尾逗号形/数组≤80/填满式 84/Map 无尾逗号/Some 折/#| 缩进////| 补齐——宽度按 UTF-8 字节〔金门实证〕；层 2 金门 fmt-fixed-point 影子真 fmt 零 diff 常驻断言〔moon 升级漂移即红〕；--fmt 退化 no-op；PLAN §9 与 codegen 头注释双勘误；层 1 锚重录 ×5、层 2 随迁 ×5）——层 1 120/120、层 2 35/35；**#33 断供处置 2026-10-12**（moon 0.1.20261012 安装阶段拒装 .mooncakes 旧 moon.mod.json 分发——传递依赖 parser@0.4.3→prettyprinter@0.4.10 断供，Vitro 下游 CI 五 job 红）：registry 实查 parser 0.4.4 deps 唯一差异 = pp 0.4.11（已迁 moon.mod 新格式）——moon.mod 一行升级即解，无需缓存 fmt 缓解 hack；层 1 137/137、层 2 39/40（唯一红 = #34 漂移显性化）；**#34 规范拼写落地 2026-10-13**（姊妹漂移：新版 moon fmt 归一化类型位置 Int→Int32/UInt→UInt32，import 产 Int 则 #18 不动点恒破——金门按设计显性化；D-13 裁定方案 A：show 产 Int32 + parse 双拼写识别存量零破坏 + UInt32 入 Unsupported；层 1 红名单 9 锚手工随迁〔拒 -u 粉饰——contains 锚查找串同步换新拼写〕；层 2 新锚 legacy-int-spelling J9 埋雷证红〔回退双识别 → 18 红〕）——层 1 137/137、层 2 41/41；**#35 内建类型名预留 2026-10-13**（派生名撞 MoonBit 内建类型名 → 遮蔽 → 产物非法保险丝 J0002；两条通路 = 遮蔽内建 J3004 / 自家 parse_type 判非 L0 J2007；trigger = indexion `kgf-transpile/c.json` 首键 `int`；种子扩为 parse_type 类型名全集 ∪ {Never}，16 名；真数据验证 MoonBit 生态 J0002 归零 84.07%→84.44%）；**#36 底型名逐文件唯一 2026-10-13**（codegen 逐文件发 `pub enum Never {}` → 同包 N 份重复 moon [4051]——actrun 88 张 / 78 份重复实测，删重复即全绿；探针证 moon **无内建 Never**；用户裁定方案 b：`<Stem>Never`（自持保留 + 无 import 顺序依赖 + 进 used_type_names 预留表）；样本锚与 mbti 重生成、smoke 随迁先红后绿）—— 层 1 139/139、层 2 42/42 |
| P2 | **npm 包**（js 出口）+ 在线试玩页（**粘贴 JSON 双向框**；2026-10-08 CI 接线：pages.yml 自动构建+smoke 门+GitHub Pages 部署 <https://rustin-beep.github.io/jsonmbt/>——npm 包/正式化仍待）+ **`jsonmbt schema` 导出**（下游清单含 **typify**——S→各语言类型已被占，本仓只做 **D→S**）+ **官方 emitter 微包 jsonmbt-go v1** | 双出口同构输出；npx 可跑；schema 经 ajv/VS Code 实测消费；Vitro 生成器直产试点 | P1.5 后 |
| P3 | L1/L2 求值分级 + `&` 去重/展开 + **diff 模式**（语义 diff——CI 基线翻转摘要）+ 键集漂移 Option 缺省（v2 观察项转正评估） | L1/L2 探针锚 + diff 人工验收 | P2 后 |
| P4 生态 | JSON Pointer / json_deriving 联动声明 / 规则手册 / （候选）validate 模式 | — | 远期 |

## 6. 技术决策记录

| 决策 | 裁定 | 依据 |
|---|---|---|
| AST 节点名 | struct 字面量 = `Expr::Record(type_name~, fields~)`；字面量 = `Constant::*` **源文本直传** | parser@0.4.3 mbti 校准 |
| 降级输出后端 | 字符串直拼；浮点输出 = `Json::Number` repr **源文本直传**（超范围大数 out-of-range fallback 保源文本），格式化面本仓不出现——ryu-pretty 对齐 / 禁裸 `to_string`（陷阱 #14 三分歧：整值 "1"、负零 "0"、中段指数）是**未来格式化面**的语义判据，非本仓调用面（10-07 勘误：Vitro `double_to_json_text` 为其仓私有、不可 import，原表述悬空）；N 层 canon = repr 缺失才 `to_string` 兜底（`src/normalize.mbt`） | 陷阱 #14 + 探针 + P1 实装 |
| **数值边界（实测修正）** | **MoonBit Int 是 32 位——真实编译界 2³¹−1，非 2⁵³**；Int64 精确到 2⁶³−1；record 字段位裸大整数字面量合法（无需后缀） | 用户亲测推翻 v0.2 的 2⁵³ 前提；教训：**MoonBit 整数语义不能从 JS/JSON 侧外推** |
| **null 映射** | 字段 `Option[T]`：`null → None`、值 → `Some(v)`——**无损直译**（探针④实锤 Some/None 合法） | 压缩/解压模型的自然推论 |
| **键名逃生门** | 非法 label（保留字/连字符/大写开头）→ 同对象整体 `Map[String, V]`（带引号键 = Map 字面量，探针④实锤；MoonBit Map 插入序=保序直译红利）；降级无引号还原。**适用面写死 = 同值类型对象**；**异值键对象（如 `{"Content-Type":"x","Content-Length":123}`）= 已知不可自动迁移子集**——阻断 issue 列逐字段类型请人工建模 struct（与 D-5 同族：v1 不做 per-key 合并推断） | tagged-enum/HTTP header 类真实数据高频 |
| **D-1 空容器（终案）** | **阻断 issue + 可行动诊断 + 两级复用启发**（①同签名组内其他样本的同名字段 → ②全文件同名字段他处非空 → 复用其元素类型，规则写死进锚；两级皆无线索才阻断；空对象无元素可抄、单独形态诊断。**#14-2a 补充（2026-10-08）：空容器占位形态 = `Never` 底型**——默认产出 `Array[Never]`/`Map[String,Never]`（零信息容器的精确刻画非逃逸非省略，输出逐字节不变；`--strict` 恢复旧行为），收窄解释非重开终案。审 P2-4 拍板：「同形」= 同签名组（即①级），实现即此，行为不变。**否决**字段省略+头注登记（违反无损与全有或全无）与 Json 类型逃逸（破 L0 纯度、病毒扩散） | 用户裁定；Vitro concepts.json 40% 空数组实证启发为主路径特性 |
| **D-2 大数（终案）** | **默认 Int64 推断**（值超 Int 全体上浮）；**跨样本无损方向归一**（同字段任一样本超 Int → 全体 Int64）；**超 Int64 诚实拒绝，不静默 Double 化**；**不采纳字段注解**（`#json_bigint` 触发 unused_attribute 黄牌，毁 check 干净卖点）；**字符串化 = 显式 opt-in**（保精度≠转字符串，两件事拆开） | 用户裁定；「默认字符串化」是 v0.2 设计陷阱（`{"id":123}` 变 `{"id":"123"}` 类型变了、往返不再无损） |
| **D-3 自持校验器** | `jsonmbt check` 内嵌 L0 校验器（几百行）+ `--moon-check` 可选深验；**按 mini-tsc 预期写**（L1/L2 落地时跟着长，moon 工具链万一不管用时已是独立类型检查器） | 非生态用户采用前提 |
| **D-4 跨文件引用** | 不做，单文件自持 | 试点数据 780 行内自持无压力 |
| **防线双层** | 内层 moon test 语义锚（随工具链漂移但漂移即编译红）+ **外层 Go 黑盒驱动 = 对外承诺的真防线**（CLI 进程契约/rc/stdout 字节/往返链/确定性/压测——只依赖 exe） | 脚本测试先满足稳定性（用户裁定）：moon test 计时与依赖随工具链漂移；外部调用走进程边界必须在进程层测（Vitro 硬防线全为 Go 黑盒的同构理由） |
| **脚本选型** | 层 2 驱动用 **Go**：五约束交集（独立于 moon/进程编排/零运行时依赖/兼职可维护/复用 Vitro 资产——smoke 驱动·exe 新鲜度门禁·golden 管理直接抄）；Rust/Python 逆版图裁定（刚退役），Node/TS 用漂移源测漂移源，shell 断言力不足，MoonBit 写 driver 过漂移工具链 | 版图一致：Go 本就是「驱动/归一化器」门 |
| importer 推断 | 形状签名判重；同构数组 `Array[T]`；阻断 issue 全有或全无；tagged-enum（`{Void:true}`）识别提示建模 enum；**字符串值疑似嵌套 JSON（JSON-in-JSON 双层形态）提示**（冻结分支 codegen golden 实测发现的观察项） | 探针 10 样本 + 4 原型 bug 预演 + 2469 压测 |
| CLI 动词面 | 对齐 CUE：`build`/`check`/`fmt`/`import`/`schema`/`diff` | 心智零迁移 |
| **值树底座** | **core/json 全套复用**（parse 自带深度预算、stringify、write_escaped 控制字符全族转义）；**实测关键校准**：`Json::Number` 的 repr **仅对超 Double 范围大数保留源文本**（out-of-range fallback），常规数字 1 与 1.0 值层不可分——由此 N 定值语义（N 层 1≡1.0）、「1≠1.0 保留」限定为降级输出侧职责（raw 直传），两维度分立 | P1 实装实测；避免自造第二套 JSON 管线 |
| **J 系错误码首批** | J0001 用法 / J0002 IO / J1001 .json.mbt 语法 / J1002 JSON 输入语法 / J2001–J2007 文档基数与类型头（缺/多 pub let、stem 不符、深度、顶层声明、重复 struct、类型面外）/ J3001–J3007 值面（非 L0、Map 键、无对应字面量、类型不匹配、未知/缺失/重复字段）；**只增不改**（D-10 纪律），每码至少一负样本锚 | P1 实装；定义在 src/diag.mbt |
| **CLI 进程面** | rc 0/1/4 已占用（2=漂移差异、3=保留，P1.5+）；诊断 = stderr 机器可读前缀；产物 = 紧凑 JSON（默认同名 .json，stdin `-` → stdout）；原子写 = 同目录临时文件 + rename（Windows 侧 remove-后-rename 的微小窗口期登记为平台限制）；文件输入必须 `.json.mbt` 后缀（防误伤） | P1 实装 + 手验（见 §9） |
| **自持 JSON 解析器** | importer 输入侧不用 core/json（三缺：number 源文本全程保形——core repr 仅超范围保留；重复键拒绝——core 静默后者覆盖；顶层行列诊断）；自持解析器产「全 repr 的 Json 树」与降级器同值模型，N 单源消费 | P1.5 实装实测（core/json lex_number 源码级确认） |
| **importer 阻断语义** | 单样本 null 字段 = J4003 阻断（Option 基型是信息论边界，多样本聚合是出路——诚实优先于猜测默认）；`--check` 幂等闸：重算与磁盘产物**行尾归一后比对**，漂移 rc 2 + J5001（D-10 有义分叉首次占用）；生成器无时间/版本戳（确定性硬锚前提） | P1.5 实装 |
| 命名 | 格式 `.json.mbt`（品牌不变量）/ **mooncakes 包 `vitro/jsonmbt`（发布账号 = vitro）** + GitHub 仓 `rustin-beep/jsonmbt`（两个命名空间不同——勘误 2026-10-07：曾把仓组织名误作发布账号名）/ CLI `jsonmbt` | owner=产品名重合产生定位噪音 |
| 竞品边界 | gmlewis = 先驱非威胁；schema 四玩家 = 下游；moonjson = "读"；jsonmbt = "写 + 类型 + 工具链 + 闭环"。README 主动声明共存 | 探针扫描 + 先例矩阵 |
| **open-object 逃生门（#14 重开追评登记，2026-10-08 观察项）** | 「固定字段 + 开放注记键」数据（Vitro single_source 实测：Lite 7 字段 + 任意 `_xxx_note` 人工注记 = 7 键集形态）与封闭 record/enum 阻抗失配——**D-5 enum 穷举在开放对象上是反模式**（每加注记扩变体 = 数据演化被类型锁死），该类形态登记为「维持 JSON 的合法不迁形态」。未来若进语言面：`// jsonmbt: open rest="notes"` 式注记（未知键收 Map 字段、降级展开回平铺键）——single_source 是现成验收样本；优先级不高，出现 ≥2 个下游案例再议（§8 走正式评审） | --fill 精确校验实测（7 形态全量普查）+ 该张判定维持 JSON |
| **D-5 已知面：payload `value` 键（审阅拍板 2026-10-08 不修）** | 标量 payload 降级用 `"value"` 键，struct payload 含 `value` 字段展平同键——J3008 只防 `case` 撞车不防 `value`（不对称）；拦截 `value` 字段会误伤合法数据（成本）而歧义可由 `case` 值区分（收益低）——登记已知面，出现真实数据卡点再议 | 深度审阅 P3 构造论证 |
| **type-name-map（#6-4 终案）** | `--type-name-map` 映射**最终派生名**→语义名（含 #4 前缀化形态；用户从首次产物复制键）；值校验 fail loud（J1010）；Map 值组名 = 宿主**字段**派生 +"Entry"（cases→CasesEntry——持有者是语义锚，条目键 a.c 无语义；数组位 fallback 首键） | issue #6/#6-4 评论拍板 + Vitro vm_digest 实测（Src_sha 误导） |
| **保留字字段名改名（#13 终案）** | 保留字类键（加 `_` 即合法：`where`→`where_`）确定性改名走 struct，类型名按原始键派生（`struct Where`）；**原始键由 `// jsonmbt: field-alias S.l = "k"` 注记承载**（合法 MoonBit 注释、fmt 幂等；build/check 预扫描注释层 + J3009 门禁）——纯语法逆映射在尾下划线邻域不可无歧义（`where` 与原生 `where_` 必撞），显式注记是唯一全解；不可改名键（点号/大写开头）维持 Map 逃生门，J4011 文案点名键因；**工具面非语言面**（产物仍是 MoonBit 子集，注释/改名后字段均为合法 MoonBit——不走 §8） | 探针（where_ 合法 + fmt 幂等 + `struct Where` 合法）+ issue #13 实测复现矩阵 + 尾下划线歧义不可消除的构造论证 |

## 7. 风险登记表

| # | 风险 | 概率 | 对冲 |
|---|---|---|---|
| R1 | moon 工具链 breaking 影响 .json.mbt 行为 | 中 | 探针行为矩阵固化为测试锚（P1 起）；moonbit 升级手册同款流程 |
| **R1b** | **依赖 moonbitlang/parser 的非公开 AST 面**（`@syntax.Expr` 等无兼容承诺——比「工具链一般性变化」更具体更危险） | 中 | **三层止损**：**L1 默认** = 锁 parser 版本（现锚 0.4.3）+ **AST 面快照入库**（`moon info` diff 即「逐节点定责」）+ 行为矩阵；**L2 机会主义** = `@syntax` 接触面收敛到单文件 extractor（转正条件：≥1 次因 AST 漂移改 `l0`）；**L3 应急** = `moon work` workspace 冻结快照（本地覆盖**已实测生效**，版本不匹配仅告警；上游 Apache-2.0）。**实测爆炸半径**：跨 4 版本（0.3.18→0.4.3）接触面破坏性变更 **0 次** |
| R2 | 求值分级被"加功能"诱惑突破 | 中（自律） | 分级冻结条款 + 逃生门原则（表达不了的写 MoonBit 去）；Jsonnet 蔓延史佐证；Vitro 诉求分流（语言面分级评审、工具面自由加，自家消费不跳级） |
| R3 | 大数/转义边角坑 | 高 | 每项进负样本锚；D-2 终案已裁 |
| R4 | 采用率：用户为何弃 JSON5/JSONC | 存在 | fmt+check+确定性三件套；**satisfies 模式流行度证需求真实**；MoonBit 生态内首发卡位；importer 拆迁移成本。**量化基线（诚实数字）**：P0 冻结分支 49% / 活数据 43%；**P1.5 重测（2026-10-07 化石批量）**：裸 PASS **49.6%**（1226/2469）——<80% 触发**升级高危**：但语境校准后定级——REJECT 100% 为单文件孤立空容器（golden 每文件独立、文件内无兄弟样本可借，两级启发无素材），**活数据 70%（32/46）不受此限**；真实结论 = 「单文件孤立空容器是裸 PASS 的地板，逃生门（Map/人工建模/emitter 直产——D-6 已实证 Go 直产可绕过 importer 推断）才是主路径」；对冲维持 + emitter 直产提前到主推 |
| R5 | 官方未来内建 typed-json | 低-中 | 规范与 MoonBit 类型系统深度绑定；即便内建，CLI diff 工具链仍是独立价值 |
| R6 | 键名合法性天花板（kebab-case/保留字/大写开头） | 高 | Map 逃生门 + 拒绝清单给可行动改名建议；实测：camelCase/snake_case 主流全兼容 + 中文键合法 |
| **R7** | **宿主语言面膨胀**——moon 新增语法/内建类型，或官方内建 typed-json，使 `.json.mbt` 成为冗余形态或被稀释 | 低-中 | 与 R5 区分：**R5 = 产品被抢，R7 = 格式合法性/定位被稀释**。对冲 = §0 腿 2/3 不依赖宿主语言演进；`schema`/`diff` 工具链的独立价值（同 R5）；迁移预案见 §7.1 |
| **性能已除名** | 551KB 实测全链 <1.1s（infer 0.03 + fmt 0.29 爆 10888 行 + check 0.74，0 errors）；9 struct/274KB 产物；**「大字面量与 fmt 互踩」的 Vitro 教训不适用于 record 形态** | — | — |

**压缩比实测（双口径）**：大文件 vs pretty JSON = 0.61×（564KB→341KB）、vs 紧凑 JSON = 1.26×、gzip 后 1.05×（传输无差异）；**行数口径（人眼维度）**：大文件 32,990 行 → 10,888 行 = **0.33×**（滚动量降 2/3，fmt 按 84 字节行宽打包 vs JSON 每标量一行的缩进噪音）；小文件多付 6–12 行类型头，换来值体单行内联 + 类型头即 schema 文档。定位语：**「YAML/TOML 是给人读的配置；JSON 是给机器读的数据；.json.mbt 是给机器读的数据的『人写形态』」**。

**§7.1 白嫖失效的 Plan B（保险单）**：与实现语言无关的可移植资产 = **语义层**（校验 / 类型环境 / 规范化 ≈900 行）+ **golden 语料** + **层 2 进程契约**（rc / stdout 字节 / 往返链）。触发条件 = R1 / R1b / R7 任一升级为高；届时按 R1b 的 L3（workspace 冻结）或上游 `Expr::json_repr` 桥路径迁移。**纪律意义**：这张保险单使「换语言」是预算内操作而非灾难——**正因如此，§0 腿 1 才敢被承认"可复制"**。

## 8. 规范决策点

| # | 决策点 | 裁定 | 状态 |
|---|---|---|---|
| D-1 | 空容器语义 | 阻断 issue + 同形复用启发（规则写死进锚）；否决省略登记与类型逃逸 | ✅ 终案 |
| D-2 | 大数策略 | Int64 默认推断 + 无损归一 + 超 Int64 拒绝；注解不采纳；字符串化 opt-in | ✅ 终案 |
| D-3 | 自持校验器 | 0.1.0 范围 + mini-tsc 预期 | ✅ 终案 |
| D-4 | 跨文件引用 | 不做，单文件自持 | ✅ 终案 |
| **D-5** | **键集漂移转正（enum 多态建模，2026-10-07 §8 二次裁定）**——触发证据三例（#7 异构数组 / facts svalue 2/22 / vm_digest 618 案例四键集） | 每种键集一个 struct + 带单参构造器包装（`enum Case { Standard(Std); CompileFail(FailCase) }`）——MoonBit 正规多态，不碰 null 语义、不碰 moon 全字段语法；**降级投影 = tag 对象展开**（payload 字段进顶层 + `"case"` tag 键；标量 payload = case+value 双键）；**tag 键冲突即拒 J3008**（payload 含 case 字段——构造器名与 payload 键撞车显式报错，不静默覆盖）；**import 不自动转**（三论证：拼错字段名 vs 真可选无解 / 自动推断会把数据错误静默类型化——坏条目变合法构造器吞进类型系统，违反 D-8 fail loud / emitter+人工面已覆盖——只开 emitter 与人工写入面）；**算式登记（用户精化）**：分组语义错误（类型对语义错）moon 不抓、靠 round-trip 兜底；转正增益 = 手写 emitter 拼字符串的编译期防线（键名拼错/转义错/分组漏）；「下游零改动」是加分非约束（六套 digest 有 --freeze-mb 全量重刷通道，tag 形态自由选型）；Vitro 六套是否铺开待 vm_diff 单点跑通 freeze 重刷循环再决策 | ✅ 转正（vm_diff 618 案例四键集实例已证：check/build 绿 + 两次 build 逐字节一致 + 除 tag 键全等 0 diff + 变体分布 602/9/5/2 精确对上） |
| D-6 | Go 直产 emitter（**第一档自拼 + 第二档微包雏形均实证 2026-10-07**：probe/vitro_gen 三张全链绿；probe/jsonmbt_go 库（单遍定型推断）化石 1226 张全链绿——见 §9） | 微包三档（自拼/官方库/importer），C 库桥否决。**双实现面约束：emitter 与 MoonBit 降级器受同一份 golden 往返用例约束**（同输入 → emitter 产 .json.mbt → build 降级 → 与原 JSON 值语义等价——往返锚即双实现对账锚） | ✅ 终案 |
| **D-7** | **文件→JSON 基数** | **一个 `.json.mbt` = 恰好一个顶层 `pub let`**（单文档语义；`pub` 消除 unused 警告守 check 干净）；**命名 = `sanitize_stem`(文件 stem)**（#31 全链统一：`config.json.mbt` → `pub let config` 常规恒等；保留字/数字开头等 stem 确定性加 `x_` 前缀〔`type.json` → `x_type`〕——import/build/check/doctor 四路同一口径，曾因 build 侧用原文校验致 import 产物即红）；**多于一个 `pub let` = 诊断错**（歧义文档）；其余 `let` = 文件内部绑定（**L2 落位由此锁死**，未来不改基数定义） | ✅ 终案（2026-10-10 补 sanitize 语义） |
| **D-8** | **build 三条不变量** | ① **校验先行，失败零产物**（含不覆盖已存在 .json）；② **非 L0 节点 fail loud**——删除原型 `_ => "null"` 兜底，遇函数调用/算术/条件即诊断中止；③ **产物原子写**（临时文件 + rename），失败不留半截产物。**`--check` 必须复用 build 的同一条校验路径**（check = build 的 dry-run——两套校验语义必漂移，Vitro 生成器 -check 契约同款纪律） | ✅ 终案 |
| **D-9** | **importer 输入 profile（单点定义，#22 重写 2026-10-10）** | **判据（可判定非枚举）**：只收「**字符层删/替空白**可消解为严格 JSON」的宽松特性，不收任何「token 层重写」。**收**：`//`、`/* */`、对象/数组/嵌套尾逗号、BOM（**仅文件首字符**——字符串内 U+FEFF 是合法 JSON 字符）；**不收**：`{,}`/`[,]`/`[1,,]`/`{"a":,}`（开头/孤立/值缺失逗号）、未闭合注释、单引号串、无引号 key、hex、`+1`、`.5`、`NaN`/`Infinity`（扩值域——JSON5 因此不进，比"留 v2"更硬的理由）。**落法 = 消解式**：`strip_jsonc` 是唯一宽松层（注释剥离器升级输入归一化器），尾逗号同一 pre-pass 等长空格消解，`jsonparse.mbt` 恒裸 RFC 8259——对拍基准不污染、诊断行列不漂移。**实现保证**：pending-comma 暂存（`,` + 穿透空白与注释见 `}`/`]` 才消解）+ **last_sig guard**（逗号前一非空白有效字符 ∈ `{` `[` `,` `:` 则不消解——`[,]` 超收防护全靠此条）。**CLI**：`--input <json\|jsonc>`（默认 **jsonc**；`json` = 裸 RFC 8259 注释也拒；**不复用 `--strict`**——#14-2a 空容器档已占用）；import 与 migrate 同旗标同默认。输入按内容探测（非扩展名）；剥离消解字节确定性锚（同输入输出恒定） | ✅ 终案（2026-10-10 重写；旧案「v1 = JSON + JSONC 注释剥离、JSON5 留 v2」只见注释未定尾逗号归属——「宽松性无单一归属层」正是 #22 病根） |
| **D-10** | **CLI 契约（rc + 诊断通道）** | **rc 五值表（与 Vitro CLI_PROTOCOL_V1 家族对齐 + 有义分叉）**：0 成功 / 1 输入错（校验/类型错） / **2 检测到漂移或差异**（--check 红、diff 有异——Vitro 2=trap 本仓无 trap，**有义占用须登记分叉**，借鉴 terraform detailed-exitcode）/ 3 保留 / 4 用法·IO 错。**纪律：rc 与标记行前缀只增不改**。**诊断通道 = stderr**（Vitro stdout 被程序输出占据故标记行走 stdout；本仓产物写文件、无程序输出），定义机器可读前缀 `jsonmbt: error [J3004] path:line:col …` + `--json` 结构化模式 | ✅ 终案 |
| **D-11** | **往返锚定义（值语义规范化）** | **`N(build(import(J))) == N(J)`**——「逐字节等价」结构上不成立（实测：JSON 合法的 `1e2` **写不成 MoonBit 字面量**——纯整数尾数接指数被拆成 `1`+标识符解析错，陷阱 #13 勘误：指数记法必须带小数点 `1.0e2` 合法）。**规范化器 N 钉死**：① 数值——整数走 Int 十进制文本；含 `.`/`e` 走 Double 的 ryu-pretty 规范形（**禁裸 to_string**；10-07 勘误：原「复用 Vitro ast 单源不重写」悬空——该函数其仓私有不可 import，本仓以 repr 源文本直传承载，规范形仅作 N 层判据）；指数记法按 ryu 短表示归一（实测 1e21→"1e+21" 与 JS stringify 同款；1.5e3→"1500" 展开形——core to_string 即规范形，审 P3 对齐）；② Int/Double 按源文本是否含 `.`/`e` 判型（`1`≠`1.0` 保留）；③ 字符串按解码后码点比较，输出侧统一转义（控制字符 `\u00XX`，对齐陷阱 #27）；④ 键序=源序不排序；⑤ null→None→null、空容器按 D-1。**登记不可逐字节已知面**：整数尾数指数（`1e2`）/ >Int64 / 超 17 位有效数字浮点 / **重复键=拒绝**（JSON 层重复键是病态输入，importer 不替它选语义——对齐「重复键结构性不可能」卖点） | ✅ 终案 |
| **D-12** | **enum 无参构造器字面量 + \| #| 多行字符串 入 L0**（2026-10-07 用户裁定：先实例证明再发包）——①无参构造器：期望 JTEnum 下查变体表，**降级投影 = 变体名字符串**（serde 惯例），jsonmbt 自持校验判变体存在性（拼错即 J3004 写时红——防线补位 moon [4031]，不依赖 moon 也有同等保护）；②#| 多行：每行净内容 
 连接（探针锚定元素形态）；**边界**：带 payload 构造器（E(3032)）v1 拒（投影无自然 JSON 形态——观察项，建模为全变体或 struct 字段）、裸构造器无类型上下文保守拒；enum/struct 类型头同形，resolve_custom 查表分化。**实例证明（Vitro error_codes 137 臂全枚举）**：check/build 往返值语义等价 + 拼错 1 变体双闸红（jsonmbt J3004 列全变体 + moon [4031]）+ 复绿——\#7 值域校验诉求的落地形态 | ✅ 实例已证（2026-10-07，137 臂） |
| **D-13** | **规范类型拼写：整数默认 `Int32`**（2026-10-13 用户裁定 #34 方案 A）——moon fmt（0.1.20261012+，moonc v0.10.15）对类型位置做**别名归一化** `Int`→`Int32`、`UInt`→`UInt32`（Int64/UInt64/Double/Bytes/Char 不动；探针实证），import 产出若仍写 `Int` 则 #18 fmt 不动点恒破（层 2 金门显性化红）。**裁定三件**：① `JType::show` 产 `Int32`（import 产物/诊断文本统一规范形）；② `parse_type` **双拼写识别**（`Int` \| `Int32` → JTInt）——`Int` 手写合法（同型别名，探针 moon check 双向赋值/泛型容器互传实证），**存量文件零破坏**（check=语义 dry-run 不重排版比对，手写 `Int` 文件 check/build 双绿实证）；③ `UInt32` 入 JTUnsupported 列表（fmt 归一拼写——不列则被 struct 分支误吞、诊断从「非 L0 类型」劣化为「未定义 struct」）。**CI 版本策略附带裁定**：`setup-moonbit version: latest` **维持不 pin**——latest + fmt-fixed-point 金门 = 漂移雷达（fail loud），漂移显性化是特性非事故 | ✅ 终案（层 2 新锚 legacy-int-spelling 常驻：混拼双绿 + J9 埋雷证红） |

## 9. 探针存档（证据链）

- **探针①label 合法性**：合法 = snake_case/驼峰（小写开头）/下划线开头/单字符/**中文键直接合法**；非法 = 大写开头（IDE 级报错）/字符串 label（语法不存在）/保留字（type/match/loop/case 实测）
- **探针②③推断原型**：10 样本 = 4 生成 0 errors + 6 诚实拒绝；形状签名判重 + 4 原型 bug 预演（签名判重/空对象假类型/定义不收逗号/嵌套值须递归渲染）
- **探针④三映射**：`Some(v)`/`None` 合法（null→Option）；record 字段位裸 Int64 字面量合法（无后缀）；带引号键 Map 字面量合法（键名逃生门）
- **探针（2026-10-13，#34 决定性）fmt 别名归一化 + Int/Int32 同型**：moon 0.1.20261012（moonc v0.10.15）的 `moon fmt` 对类型位置归一化 `Int`→`Int32`、`UInt`→`UInt32`（struct 字段/let 注解/泛型参数全位置；Int64/UInt64/Double/Bytes/Char 不动）——影子项目最小探针实证；`Int` 系 `Int32` **同型别名**（跨注解双向赋值 + `Array[Int]`/`Array[Int32]` 容器互传 `moon check` 全过）——规范拼写切换（D-13）零语义变化的根据
- **大文件性能**：551KB 全链 <1.1s——性能除名
- **探针⑥数字字面量（D-11 决定性）**：`1e2`（纯整数尾数接指数）**解析错**——被拆成 `1`+标识符；`1.5e3`/`100.0`/`1.0e2` 合法——**指数记法必须带小数点**；16 位整数字面量 Int64 位合法 / Int 位 out of range（再证 D-2 的 2³¹−1 界）。**陷阱 #13 勘误**：原文「e 记法浮点字面量不可用——写定点」不准，实情是「纯整数尾数不行，须带小数点」。**附带新陷阱 #42**：新工具链（rr_moon_mod 特性）下 `moon.mod.json`/JSON 式 `moon.pkg` 解析失败，必须 `moon.mod` + 块式 `moon.pkg`
- **Vitro 真实数据两轮**：现行仓 44 张 = 19 裸 PASS / 25 REJECT（非法键 39 处·空容器 22·异构 12·动态键文件名/诊断码约 15 张属 A 类不迁）；**冻结分支 2469 张 48.1MB = 49% 裸 PASS，REJECT 100% 落在 tagged-enum/空容器/动态键三门内，零未知形态**——importer 迄今最大规模实战验证
- **探针产物**：`D:\code\jsonmbt_probe\notes\`（label 件 + 4 生成件 + 大文件产物）——临时环境，P1 起样本迁入本仓 `probe/`，外部路径视为已失效
- **P1 前置探针（2026-10-06，AST 形态五件 + 底座选型）**：
  - **AST 白名单实锤**：Map 字面量 = 独立 `Expr::Map(elems)`（非 Record）；`Some(v)` = `Apply(func=Constr("Some"), [位置参数])`；`None` = `Constr("None")`；**负号直接进 Constant raw**（`-1` = `Int("-1")`，无需处理 Unary）；`123L` 的 `Constant::Int64` raw **不含 L 后缀**；record 字段位裸 object literal 合法（`type_name=None`）；**`d : Double = 1` 的 AST 保持 `Int("1")`**（定型是类型层，降级源文本直传）
  - **勘误（探针 C 误读）**：`Constant::String` 的 raw **未解码**（转义序列原样保留）——P0 探针 json_repr 的转义展示形态造成「已解码」误读；降级器补字符串解码器（`\'` `\"` `\\` `\n` `\r` `\t` `\b` `\f` `\0` `\xHH` `\u{1..6 位}`），解码进值树、输出侧统一 stringify 转义（单源）
  - **core/json repr 语义**：repr 仅超 Double 范围大数 Some（out-of-range fallback 保源文本）；常规数字值层不可分 1/1.0——N 值语义与降级保真两维度分立（§6 值树底座行）
  - **core 无同步 fs** → x/fs（read/write/remove）+ 自补三桩（stdin 读全量 / stderr 写 / 原子 rename，UTF-8 路径 Windows 侧宽字符转换）；`#cfg(target="native")` 分后端（`backend=` 谓词不存在——实测踩坑）
  - **中文边界**：中文可做字段 label 与 Map 键（P0 已证），**不可做 struct 类型名**（MoonBit 要求大写开头，中文按 lowercase 拒）——类型名英文、键位自由
  - **CLI 进程契约手验通过**（rc 0/1/4 全占、stderr `jsonmbt: error [J3004] path:line:col` + help、D-8 ① 失败零产物不覆盖旧文件、原子写无 tmp 残留、stdin→stdout、两次 build 逐字节一致）
- **P1.5 前置探针（2026-10-07，生成格式与先例）**：
  - **moon fmt 格式自由度实测**：~~多行 record/数组、内联单行全部 fmt-stable（零改动）~~ **#18 勘误（2026-10-10）**：此结论疑踩陷阱 #45（moon fmt path 参数静默假成功）——import 产物实非 fmt-stable（fmt 补 ///|、短 record 收敛单行、数组折回）；#18 已重写生成器为**宽度驱动 fmt 不动点**（整行≤84 record 单行尾逗号形/数组≤80/填满式/Some 折/#| 缩进——层 2 金门 fmt-fixed-point 常驻断言零 diff，moon 升级漂移即红），--fmt 退化 no-op。规则明细见 #18 issue 评论（13 形态探针+宽扫封盘）与金门迭代实录
  - **@generated 形态先例**（Vitro libc_data_gen/error_code_gen）：普通 `//` 注释行 + 禁手改说明；**不写时间/版本戳**（确定性：同输入两次 import 逐字节一致——升级不产噪音 diff）
  - **core/json lex_number 源码级确认**：repr 仅超 Double 范围 out-of-range fallback 时 Some——number 源文本全程保形必须自持解析器（§6 决策行）
  - **往返链手验**：import（JSONC 注释样本/Map 逃生门/Int64/Double）→ build 回 .json 键序与数值文本一致；`--check` 幂等 rc 0、改坏产物后 rc 2（J9 证红）；两次 import 逐字节一致
  - **issue #1 修复实录（2026-10-07，层 2 上岗首拦）**：write_stderr 按码元数写 UTF-8 字节串 → em-dash 截尾 2 字节（红：尾部 docume 逐字节证）；修复 = 长度改字节数（绿：document 完整）。层 2 Go 驱动首跑即拦住**第二层实锤**：Windows 文本模式把诊断 
  - **首轮深度审阅修复实录（2026-10-07，用户跑 workspace-review skill：P1×5 / P2×6 / P3×10）**：
- **Vitro 承接实测（2026-10-07，回答「能否承担 Vitro 的 JSON 任务」）**：scripts 下活跃 JSON 46 张批量 import——**32/46 全链过（70%，P0 时 19/44=43%）**，REJECT 14 张全为诚实阻断类（异构数组×5/异值键×3/孤立空容器×3/空对象×2/字段异构×1——diff digest 类本就该拒）；**试点对象 diagnostics_data 六张 6/6 import+check+往返 N 等价全绿**。实测钓出三缺陷（全修）：①emoji 代理对越界 panic（String.length 码元 vs to_array 码点，catalog.json 62 个 emoji 实锤）②带点键（"memory.dump"）只验首字符漏网产非法产物（is_legal_label 全字符化；**P1-1 保险丝首次实战拦截**）③保险丝吞原始诊断（改透出 failing check 全文——本次定位全靠它）
  - **D-6 第一档实证（probe/vitro_gen）**：Vitro JSON 产线摊清三角色（人审真相源→gen_diagnostics 产 .mbt / gen_diag 单源中间产物 / e4_export 运行时导出）；Go 自拼 .json.mbt 模板跑通（error_codes/catalog/patterns 三张：check 全过 + build 回 JSON 与原 JSON N 等价 + 顶层键序保持）——**机器生成端替代 JSON 的可行性已证**；json.Number 保数值文本形态（Go float64 会把 1.0 变 1）是 Go 侧关键坑
  - **可执行文档手册落地（src/manual.mbt.md，2026-10-07）**：fence 发现条件分离变量实测——**关键 = fence 标记 `mbt check`（文件名任意 `*.mbt.md` 均被发现；`*.json.mbt.md` 只是命名约定）**；标记 `moonbit` 不触发。手册 7 fence 全执行且绿（moon test 61→68——文档即锚，示例永不腐烂）；moon fmt 对 fence 零改动（fmt-stable）；CLI 段为纯文字（bash fence 不在执行面）。**语言面未动**：手册属工程文档（core/x 的 README.mbt.md 同款工具面），`.<name>.mbt.md` 作**数据文件形态**仍挂 §8 评审（§2 条目不变）
  - **Vitro 二批反馈三件（2026-10-07，#10/#11/#6）**：**#11（真 bug）异构诊断错位修复**——JTStruct 分裂改报字段集差异 + 分布计数（keyset_drift_diag：×602/×9/×5/×2 降序 + 总数，ShapeGroup 加 keys/count），不再泄漏 Src_sha 系派生名；vm_digest 实测 619 样本 5 键集精确报出（与 Vitro 侧计数对上）；**#10 import --fmt 实装**——产物落盘后 spawn moon fmt 单文件（run_cmd stub）、--check 互斥（写副作用纪律）、moon 缺位 J0002、版本锁定声明（升级 moon 一次性重排属预期）；build 侧不加（.json 无 fmt 概念）；**#6 Map 值命名**采纳（宿主键+Entry 派生，并入 #6-4 type-name-map）。附注：本仓 import 产物 fmt 零 diff（codegen 折行已规范），--fmt 价值在 emitter 紧凑产物场景  - **#12 处置三件（2026-10-08）**：提报方自撤 rc=0 指控（`echo 0` 字面量陷阱——本仓本地重验双证 rc=4 契约正常，J0002→`JCode::exit_code` 代码路径同证）；**① J0002 文案多因列举**（moon 缺 PATH vs 产物不在任何 moon workspace 覆盖——moon 原始报错经 system() 透传可见，文案引导对照；**不按 rc 值语义分支**：cmd 的 errorlevel 编码非契约）+ help 行现场声明半成功态（fmt 失败 = 产物保留未 fmt 形态 + rc=4）；**② `-o -` 纯验证通道**（build/import 通用，二进制 stub 字节契约复用 stdin→stdout 通道；与 `--check`/`--fmt` 互斥（盘面语义）；stdin→stdout 全管道拒——`json_stem_of("-")` 返 `Some("-")` 曾可产非法绑定名 `pub let -`）；**③ run_cmd Unix wait-status 解码**（子退 1 曾显 rc=256——**未经 Unix 实测**登记，本仓 CI 面 = Windows native）。**实测边界沉淀**：本仓 tmp/（无 moon.pkg 但向上可达根 moon.mod）fmt 正常——**fmt 盲区判定 = 向上可达 workspace 根 ≠ 静态检测的 moon.pkg 包边界**（fmt 盲区是静态检测盲区的真子集；盲区真代价 = 整个 moon 工具链不可见，fmt 只是先撞见的症状）。L2 驱动 9→12（odash-stdout-channel/odash-exclusive/fmt-fail-j0002；红→绿实录：旧 exe `-o -` 落盘名为 `-` 文件 + stdout 空 / `--check` 互斥缺失走 rc=2 / 旧文案无盲区指因）；moon test 78/78 不变（改动全在 cmd 层）
  - **pages playground demo（2026-10-08，P2 在线试玩页/js 出口提前预演）**：`pages/ffi` wrapper 包（js target，`link.js.exports` 三件 js_import/js_build/js_check——JSON 编码返回，诊断文本过 stringify 免转义地狱）+ `index.html` 双栏实时转换（overlay 语法高亮：textarea 透明文字叠高亮 pre）+ 21 卡样例矩阵（绿 10/红 7/.json.mbt 独有 4，真实引擎冒烟 22 断言 = `pages/smoke.mjs`，与卡片同步维护）。**实测三结论**：① src 包 **js/wasm 双后端 0 错编译**，js 后端 String=JS string 直通、ESM 可 import、d.ts 白送——demo 引擎路线；② **wasm-gc String ABI 当前断**：官方 FFI 文档 String→externref「iff JS string builtin is on」，moon 0.1.20260920 二进制无该配置键、`"js-string-builtins"` 传 moon.pkg 被静默忽略、wasm import 段空——P2 npm 包待工具链补开关后切 wasm-gc；③ **js 后端 release 会 tree-shake `link.exports` 导出**（main 保活引用仍丢，debug 构建可用）——P2 npm 包必须解。**#15**（J2007 help 文案与实现不一致：supported 列 `Option[T]` 实际拒，真语法 = 后缀糖 `T?`）由样例卡实测钓出。ffi.js 构建产物不入库（debug ~7.7MB；构建命令见页脚）
  - **批② facts 链实测 + 折行落地（2026-10-07）**：**机器写回域阻塞精确定位 D-5**——facts.json（svalue 仅 2/22 条目存在）与 vm_diff/golden_digest（618 案例**四种键集**：602 标准/9 带 compile_fail/5 带 known_mb_digest/2 双标记）实测证明：阻塞不是 emitter 能力（生成器知类型可直产）而是**语言面 D-5（可选字段）未转正**——struct 全字段必填表达不了省略键；**D-5 转正三例触发证据齐**（+ #7 异构数组），且书写形态有真设计张力（省略书写撞 moon record 全字段语法 / None 降级无键撞 D-11 null 无损语义）——提案待 §8 设计评审（#8 issue 对账回复附全案）。**#9 折行落地**：codegen 数组 ≥2 元素逐元素折行——catalog 产物 21 行/最长 13354 字符 → **312 行/最长 190 字符**（单卡行级 diff），fmt-stable 实证（moon fmt 零 diff）；快照锚同步
- **#7/#9 探针收口（2026-10-07，issue 回复 + §8 评审项登记）**：**#7 枚举值域三闸实测**——moon 侧完整支持（enum+字面量 moon check 0 错、拼错名 [4031] 写时红）而 jsonmbt L0 拒 Constr（J3001）——**放开裁定建议已提 §8**（构造器字面量入白名单——**修订 2026-10-07 二次探**：①「前缀语义类型面无解」结论**错误**——enum 带 payload（E(Int)/W(Int)）moon 0 错、拼构造器/payload 类型错双红，前缀集有限数字做 payload，**有解且优雅**；②全枚举变体（77 码）拼错字母级 [4031] 红；白名单泛化为「构造器字面量」与 Some/None 特判语义自洽，降级投影（E(3032)→?）评审定；③hex 形态类型面真无解（newtype 无值域）→ 库路线 mooncakes mizchi/moonbit_jsonschema 的 enum/pattern CI 旁路（双文件）或 jsonmbt 注记（单文件，另设计））。**#9 长文本三问**——MoonBit 有 #| 多行字符串（语法+编译面全合法、jsonmbt L0 拒——同挂 §8 评审，降级语义行拼接→
）；catalog 77 卡往返值语义 True + 两次 build 逐字节 True（中文/emoji 零转义噪音）；**排版痛点在数组不在字符串**（entries 单行 13354 字符）→ codegen 长数组逐元素折行（工具面，fmt-stable 已证）排下批
- **issue 采信批（2026-10-07，#4 修复 + #6 三小件）**：#4 跨文件撞名（方案 A 渐进式：同目录已占名扫描 + 冲突时后来者 stem 前缀 Code→BCode，先到先得单文件零变化；moon 编译面 [4051] 验收绿 + 防回归锚 + INTEGRATION 第 0 条前提）；#6-1 build --indent N（0..16，Vitro 4 张仅缩进差基线可字节对齐）；#6-2 import 落盘提示 moon fmt（产物非 fmt-stable 的假绿源——提示版先行，内置 fmt 待设计降级）；#6-3 build 缺 --pretty 提示（沉默错形态最贵）；L2 驱动 8→9（cli-hints：双 hint 正反 + --indent 1 形态锚）。采信待做：#6-4 type-name-map（#4 止血后不急）、#6-5 migrate（Vitro 迁完再产品化）、#5 doctor（设计采信含只诊断边界，排 P1.5 后）、#3 归档不实现
- **Vitro 真相源翻转试点落地（2026-10-07，tmp/vitro-pilot 克隆实操——「Vitro 负责人」视角实战）**：diagnostics_data 六张 .json.mbt 入仓为真相源（原 .json 删除）+ CI yml freshness 步前插 jsonmbt build 再生（下游 gen_diag/gen_diagnostics/moon 消费方零改动）。**兼容性硬需求实锤 → jsonmbt 新能力**：gen_diag 门禁按产物 sha 字节指纹锚定 → 再生 JSON 必须与 Go json.Encoder SetIndent 逐字节一致 → build_source 加 pretty?（indent=2 + 尾换行——core stringify 形态与 Go encoder 探针锚定一致）+ CLI --pretty。**红绿证据**：绿链 = 六张再生 BYTE-EQUAL × 6（**前提语境**：六张是 Go struct 序列化产物，字段声明序=源序——**审 P1 勘误：「与 Go encoder 逐字节一致」仅在键序=源序前提下成立**；Go map 序列化走字典序与 jsonmbt 源序必分叉，手写基线亦不承诺逐字节——那些场景承诺值语义等价。承诺限定已写入 api.mbt 注释；L2 补 Go encoder 真对拍 + 键序源序锚双用例）→ gen_diag/gen_diagnostics -check 双 OK → Vitro moon check 0 errors；红牙 = ①改坏 .json.mbt → J1001 门禁红 ②改数据值 → sha 指纹漂移红；复绿确认。**试点证明形态闭环**：.json.mbt 作真相源 + jsonmbt build 进 CI = 门禁有牙且对下游透明（Vitro 侧改动 = 六文件换格式 + yml 8 行）
  - **AST 面快照锚落地（R1b-L1，2026-10-07）**：src/ast_snapshot_wbtest——**自投影签名**（本仓定义的紧凑 AST 投影 `R[]()/A[]/M[]/F()/C()/K()`，锚节点种类+raw 参数）锚死「典型 L0 样本 → parser@0.4.3 AST 结构」；**不锚 parser 的 json_repr 调试输出**（长且形态无兼容承诺——投影由本仓定义、跨版本语义稳定）；覆盖白名单全变体（带名/裸 record、五 Constant 细类含负号 raw 与 Int64 无后缀、Array/Map/Some/None）；升级红时 diff 投影即定位变动节点（R1b 对冲流程的正体）
  - **化石分支双实现批量实测（2026-10-07，D-6 第二档雏形 + R4 数字重测）**：probe/jsonmbt_go（Go 库：单遍定型推断，含 sanitize stem/类型名、键序恒排序）× probe/fossil_batch（8-worker 驱动）对 frozen-oracle-snapshot 全量 2469 张跑双路——**Go emitter 与 MoonBit exe import 完全同数：1226/2469 全链过（check+build+值语义往返），checkFail/mismatch 双零**（D-6 双实现对账锚在真实数据全量规模首次全绿）；REJECT 1243 = 单文件孤立空容器 1233 + 孤立 null 10——golden 每文件独立、文件内无兄弟样本，D-1 两级启发无素材（R4 升级判定的根因面）。**实验钓出并修复**：①jsonmbt import 的 stem 带点产非法产物（"array_address.c" → sanitize_stem 前置清洗 + 双锚）②Go 侧同族三连（类型名/binding/键序确定性——只验首字符的教训在第二实现重演，佐证 A4 形态的普遍性）③驱动级并发竞态教训（同名平铺互踩 → 目录分桶）。**含 JSON-in-JSON 大字符串（result 字段 1.4MB 级）通过**——双层形态往返无损
    - **P1-1~4（import 产物非法四连，同性质）**：①指数源文本直传（1e2 写不成——须补 .0，`ensure_double_syntax`）+ **保险丝：import 产物回吃自家 check_source**（生成器 bug 永远到不了磁盘）；②控制字符转义坏插值（MoonBit 字符串 `\` 吃掉紧随 `\{`——整段源码落盘；三段运行时拼接修）+ jp_string 拒裸控制字符（RFC 8259 §7）；③④`JTEmpty` 中间态穿 Option/嵌套容器逃逸（Array[?]? / Array[Array[?]]）——判定递归化（has_empty_array/replace_empty_array）+ **收尾断言保险丝**（残留即 fail loud）；空容器无线索场景回归诚实阻断 J4001
    - **P1-5**：层 2 驱动缺 go.mod 按文档不可复现——根 go.mod 落地（`go run ./tests/driver` 直跑）
    - **P2**：stdin import 的 -o 语义（.json.mbt 整后缀剥 + 落盘）；probe 样本挂层 2 真门禁（probe-samples-golden：check + build vs 黄金逐字节）；exe 新鲜度门禁（mtime 法，排除测试文件——test 不在 native 构建面）；D-1 措辞统一两级（拍板：「同形」= 同签名组①级，实现即此，行为不变）；codegen `pub struct`（priv 每字段 unused_field 噪音 + moon info 不透明——schema 出口前提）；三处弱锚换牙（J1002 码值锚 / Some 内层类型 / D-1 启发非 Int 元素判别）
    - **P3 代码向**：Int64 下界 -2^63 误拒修复（特判，唯一超出正数累积界的可表示值）；normalize_json_text 单源化到自持 json_parse（core/json 退出主链——deprecated 参数/重复键静默/无行列三害全消，仓内上游警告清零）；CLI J 码单源化（jdiag_exit 替 15 处手写前缀）；hint 去重；BOM 按码点文本显示
    - **P3 文档向**：陷阱 #13 勘误回灌快照（「e 记法不可用」→「须带小数点」——正是 P1-1 认知根因）；README 锚数/状态回写；assets 数字互斥修正（x=176 实测为权威）+ 不可执行处方重写；D-11 指数表述对齐实现（ryu 短表示，1e+21 与 JS 同款）；normalize 注释 -0 勘误（实测 N(-0)==N(0)）
 转 
——C stub stderr 设二进制模式（机器可读通道跨平台字节一致，D-10）；层 2 第一天就兑现了「golden 逐字节拦人拦不到的」承诺
- 竞品与先例：§2 矩阵
- **AST 依赖面探针（2026-10-07，R1b 定价依据）**：接触面 = **2 函数 + 10 类型**、**38 处引用**落 6 文件（l0 19 / document 8 / tyenv 6 / diag 2 / unescape 2 / cmd 1）；`constant_shape` 对 `Constant` 13 变体**穷尽列举无 `_`**（上游加字面量变体 = 编译红）；跨版本 `0.3.18→0.4.3` 全接口 diff 96 行（`Expr` 删 `LexMatch`、`LexScan` 加 `streaming~`、`ForEach` 的 `binders~` 改名 `patterns~`），而**本仓触及面破坏性变更 0 次**（7 类型零变化 + 3 类型仅加字段被 `..` 吸收）。`moon work` 本地覆盖**实测生效**（consumer 要 `parser@0.4.3`、工作区成员给本地 `9.9.9` → 仅告警 + 测试通过）
- **moon 文件种类面探针（2026-10-07，后缀继承）**：moon 按**最后一段扩展名**分派工具链——`data.json.mbt` check/fmt/info 全生效；`doc.json.mbt.md` 的 **fence 被 `moon check` 校验 + `moon test` 执行 + `moon fmt` 归一**，且 fence 编译在**黑盒测试上下文**（与包内同名 `pub let` 不冲突、声明不进 `pkg.generated.mbti`）；`moon run script.json.mbtx` 可跑；**手写 `x.json.mbti` 被静默忽略**；`moon info` 对 `.json.mbt` 包产出 `pub struct` 带字段、priv struct 只有不透明 `type X`。**否决**：`.json.mbti` 源格式 / `.json.mbty` / `moon.pkg` pre-build（语义错配——产物须入仓、可 diff、原子写）
- **moon 静态检测接入探针（2026-10-07，批 C；Vitro 迁移返工两轮换来）**：
  - **动机**：`.json.mbt` 的核心卖点是白嫖 MoonBit 静态检查，但 Vitro 批②把 11 张放 `scripts/` 下（`moon.mod` 在 `moonbit/`、该处无 `moon.pkg`）→ **完全在包外，moon 一次都没参与**。工具有效但用不上 = 只换载体没买到东西。
  - **能力实测（包内）**：类型错（`Int` 赋字符串）→ `[4014]`；字段名错 → `[4044]`/`[4091]`；struct 字段缺失 → `[4044]`。**`.json` 写错照样能 `go run` 通过，这就是增量**。
  - **moon 行为基线（关键，勿再踩）**：`moon build --target native` **不**检查孤立包（注入类型错仍 rc=0）；`moon test --target native` **会**（rc=1）；`moon check` 全量**跳过**孤立包（只 2 tasks），`moon check <包名>` 才点名（rc=127）。→ **CI 的 `moon test` 天然兜底**，另加显式 L1-c 把契约写进 yml。
  - **接入三前提**：① 目录带 `moon.pkg`（`examples/` 与 `probe/samples/` 已加，样本默认放这两处）；② `struct` 必须 `pub`（priv 触发逐字段 `unused_field` 噪音 + `moon info` 不透明）；③ 经 `moon fmt` 归一（补 `///|` 标记；**按行宽决定折行**——短 record 折成单行，长的保持多行，故 import 产物非 fmt-stable）。
  - **工具链坑**：`moon fmt` 会把 0 字节 `moon.pkg` 改写成 1 字节换行（幂等，不破坏包识别）；但 `{}` 与块式 `import ()` 两种写法均报 `Failed to calculate build plan`——**只能用空块**（印证陷阱 #42 的块式要求）。
  - **红牙验收**（CI 原文命令）：类型错 → L1-b rc=1 `[4014]` / L1-c rc=127；字段名错 → rc=1/127 `[4044]`；恢复后 L1-a/b/c 全绿 + 层 2 Go 驱动 `total=5 failed=0` 未受影响。

## 10. 边界声明

jsonmbt 是通用开发工具，**不是教学产品**。`.json` 仍是机读标准形态，`.json.mbt` 只服务"人写 JSON"的场景。

**维持不做（有实锤理由）**：JSONC 输出带注释（破坏确定性）、多文件 include（D-4）、环境变体 CLI 糖、VS Code 专属插件（官方 LSP 覆盖）、字符串集合自动推断 enum（阈值判定破坏推断确定性——v2 观察项）、**JSONC 同类弱格式**（自建工具链=Dhall 死因，importer 输入支持即可）、**C 库桥**（D-6 否决）、**Rust 冻结档案转换**（档案不转——活在分支上的意义就是不变）。

**文档/实现比纪律（R10）**：v0.3.1（~24KB 规范）与实现（探针 68 行）的差距必须在 **P1 验收时清零**——每条 D 系裁定至少落一个测试锚，否则规范降级为草稿。规范先行是 P0 阶段的正常形态，纸面化不是。

**观察项转正制度**：全部观察项（字符串推断 enum / JSON-in-JSON 提示 / JSON Pointer / validate 模式 / D-5）必须带**转正触发条件**（信号 + 阈值 + 转正形态约束），无触发条件的观察项不予登记——防僵尸。

**定位主张可证伪制度（R11）**：§0 的每条护城河腿必须登记**失效判据**（腿 1 = 宿主停止服务该形态/删除 L0 语法；腿 2 = 出现被广泛采用的等价制度性冻结；腿 3 = 通用语言官方引入文件级单文档约定），并随升级复核。**无判据的定位主张不予登记**——防不可仲裁的立场（与「观察项转正制度」同款纪律，延伸到定位面）。

**结论入仓制度**：评审/探针产出的新结论先进 `docs/` 下的**未拍板笔记**，由用户裁定后并入 PLAN 正文；**禁止长期悬空**——悬空笔记在下次 PLAN 修订时清零（本制度本身即因 v0.4.0 前积压三份悬空笔记而立）。
