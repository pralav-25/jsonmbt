# Changelog

本仓全部可见变更记录。格式与纪律见 [AGENTS.md](AGENTS.md) 纪律 6。

## [Unreleased]

### Fixed（issue #37：taken 前缀化家族自洽——后续同基名组不退回未前缀 dedup）

- **现象**：`alloc_type_name` 的跨文件撞名前缀化（#4）只对组「首个」名生效——同文件**后续**同基名组在前缀名被占后退回**未前缀** `dedup`，去抢全局裸名号段（MoUI `checks/` 17 文件实测：`harmonyos.json` 产 `HarmonyosStatus, Status5, Status6, Status7`，期望 `HarmonyosStatus, HarmonyosStatus2, HarmonyosStatus3`）。非正确性缺陷（#24 后无撞名、产物能编译），属命名面质量：名字与源文件失联 + 号段随目录文件数/顺序漂移
- **修法（issue 一行改法）**：前缀化分支 `dedup_fallback(primed0)` → `dedup_fallback(prefixed)`——前缀合法时整个家族在 `<Stem><Base>` 号段内自洽 dedup（前缀非法才退回裸名，保留原兜底）
- **锚**：层 1 新锚「#37 taken 前缀化家族自洽」先红（现状 `Status2/3` 实证）后绿 + 回吃合法断言；#24 层 1/层 2 锚随迁（`BStatus + Status3` → `BStatus + BStatus2`——「不复用 taken 裸名」本质断言不变，层 2 加「不得抢全局裸名号段」反向断言）——145 → **146**
- **附带（#38 批时差遗留补齐）**：`moon info` 重生成三个 mbti 的 `Int`→`Int32` 接口形跟随（#38 批 `moon info` 跑在全仓 fmt 归一之前——源码类型位置已归一、mbti 未跟，语义零变化，D-13 规范拼写）
- 门禁：层 1 **146/146**、层 2 **44/44**

### Dependencies（lexer@0.4.2→0.4.4：`\x00` regex 与新 moonc 不兼容——#33 同族传递依赖处置）

- **现象**：#38 批全仓 `moon fmt` 打破 `.mooncakes` 编译缓存后，`moon test/check` 首次真重编 `moonbitlang/lexer` 即红：`lexer.mbt:348` 的 `re"^...[\x00-\x7F]"` 报 `[4172]`（新 moonc regex 不支持 `\x00` 转义，要求 `\u{0}`）。此前全绿靠旧编译器产的缓存——**工具链升级不 invalidate 依赖包编译缓存**（PITFALLS #50 同根的编译侧形态：缓存掩盖上游不兼容直到被打破）
- **上游修复链**（parser 仓 2026-10-19~22）：`3b0e26a` fix(lexer) 去 hex escape → `16b7aca` release lexer 0.4.4 with the ASCII byte literal fix
- **修法**：根 `moon.mod` `moonbitlang/lexer@0.4.2 → 0.4.4`（moon 解析接受根声明覆盖 parser@0.4.4 钉的 0.4.2；parser 本体不动——10-22 上游 `45f96a6` 移除 `parse_file` API，暂不追）——lexer 0.4.4 装上后 146 锚全绿
- **锚**：既有全量即锚（test/check 红→绿）

### Fixed（issue #38 / D-14：保留字表与 moon 本尊硬同步 + check 端硬关键字判定 J2008——语言事实表单源化）

- **现象**：自持 40 词保留字表与 moon 本尊关键字表脱同步——`{"extend":1}` import **rc=0 静默产出非法 `.json.mbt`**（moonc `[3002]` Parse error）；`var` 类词被库 parser 拒、兜成误导性 **J0002「internal generator bug」**。同类第三次（#28 词法区间 / #35 内建类型名 / #38 关键字表），病根同一 =「jsonmbt 自持 moon 语言事实副本 → 必然脱同步」
- **根因（双 parser 缝，PITFALLS #49）**：import 保险丝的自检端走 mooncakes `moonbitlang/parser` 库 0.4.4——与 moonc 是**两份代码**，字段位 `extend` 库放行 vs moonc 0.10.15 硬拒，「接受」判决不能跨 parser 通用
- **修法（D-14 八条，2026-10-13 终案）**：① 新增 `src/moon_facts.mbt` **三表单源集中**（#38 关键字 **58 硬 + 21 保留**、#28 词法区间、#35 内建类型名——每表注明提取源 `.mooncakes/moonbitlang/parser@0.4.4 lexer/keywords.mbt` + 日期，一次性脚本机械提取不人肉抄）；② 发射端口径 = **79 词全量**（生成器零警告零错误形态），删 `when`/`backed`/`unit` 三个 moon 表没有的失效词；③ `sanitize_stem` **只同步 58 硬词**（保留词 stem = moonc 警告级合法不收——D-7 存量零破坏）；④ **check 端真修 J2008**：struct 遍历处自持「字段名不得为硬关键字」判定（语义 = 对齐 moonc Parse error 分级：硬词拒/保留词放行，非「比 moon 严」）——「jsonmbt check 通过 ≈ moonc 可编译」承诺闭合
- **行为变化**：`unit`/`when`/`backed` 字段名 改名→**直出**（修过度改名）；新增硬词（`var`/`derive`/`with`/`extend`…21 个）与保留词（`module`…21 个）字段名 直出坏文件/J0002 → **改名 + field-alias 注记**（往返无损）
- **锚（红→绿全流程）**：层 1 J2008 锚先红（手写 `extend` 字段 = check 假绿 BUILD-SUCCEEDED 实证）后绿 + 行为锚 ×5（三词直出/新词改名/保留词改名/撞名两级/sanitize_stem 分级）——139 → **145**；层 2 双锚 `reserved-words-full-table`（79 词 import → 同一影子 moon 项目**批量一次** `moon check`：零 error 零 `[0035]`）+ `check-verdict-consistency`（79 词手写文件 jsonmbt check 与真 moon check **判决逐词一致**：58 硬双红 / 21 保留双绿〔moon 带 `[0035]` 警告〕；硬/保留词分两个影子项目防连坐）——**旧 exe 证红**（`var` import rc=4 J0002 形态 + `extend` check 假绿，stash→重建旧 exe→跑红→恢复→重建→绿，J9 埋雷义务）→ 重建后 **44/44**
- **漂移雷达**：双锚常驻 = 表同步雷达（moon 保留词升硬/硬词降级 → 词表内判决一致性破 → CI 红）；moon 新增**全新**关键字不在 79 词表内——同步义务随 `moon_facts.mbt` 更新时一并落到层 2 词表副本（防线独立性：不读 jsonmbt 源码）
- **文档**：skill 1a/2 条目重写（79 词口径 + J2008 + 三词直出）、manual 键名两通道、README 口径引用、PLAN §8 D-14 + §5 里程碑；MOONBIT_PITFALLS 新增 **#50**（`moon fmt --check` 增量假绿——本批全仓 `moon fmt` 暴露 #34 后存量欠账约 200 行：类型别名/具名参数 `?`→`~`/括号剥除/长行折行/尾空行，纯形态零语义，145 锚全绿实证安全，随本批归一）
- 门禁：层 1 **145/145**、层 2 **44/44**（moon 在场真跑）、`moon info` 接口面 +`JHardKeywordField`（J2008）、`moon fmt --check` 全仓真绿

### Fixed（issue #36：空容器底型名逐文件唯一 `<Stem>Never`——同包多文件不重复声明）

- **现象**：codegen 逐文件发 `pub enum Never {}`（per-file `uses_never` 驱动）——整仓 JSON 迁入同一 moon 包时 **N 份重复声明** → moon `[4051]`。实测 `mizchi/actrun` 88 张 → 86 张 import 通过 → 同目录 `moon check` 红，**78/86 文件各声明一次**；脚本删掉 77 份重复（留 1）即 **全绿（0 error）** ⇒ 该重复是唯一拦路者。**旗舰场景**（整仓 JSON → 一个 moon 包）直接阻断，`docs/INTEGRATION.md` §0 只覆盖了 `pub struct` 无冲突
- **前置探针**：MoonBit **无内建 `Never`**（`pub let x : Array[Never] = []` → *The type Never is undefined*）⇒ 底型必须自带声明，非可删项
- **修法（用户裁定方案 b）**：底型名 = **`<Stem>Never`**（`never_type_name` = `sanitize_stem` + `capitalize`，非 A-Z 起头加 `T` 前缀保合法）——逐文件唯一（同目录 stem 唯一）⇒ 同包不再重复；**自持性保留**（不依赖 sibling 是否先 import，无 import 顺序依赖，`--check` 幂等不受 sibling 影响）；该名同时进 `used_type_names` 预留表（派生 struct 名不得占用）
- **锚**：层 1 新锚「Never 底型逐文件唯一名」（两 stem 两名 + 自持 build 回吃）；#14-2a 主锚与全 null 锚随迁（`Array[TNever]` / `Map[String, TNever]` / `Array[TNever?]`）；层 2 `never-placeholder` 随迁并扩「同目录两文件底型名互异」断言；样本锚 `probe/samples/empty_containers.json.mbt` 与 `pkg.generated.mbti` 重生成（`sample-import-regen` 闸抓到过期——正是它存在的意义）
- **pages 链**：`smoke.mjs` 空容器专断随迁（stem `demo` → `DemoNever`）——重生成 ffi.js 后 smoke **先红后绿**（`SMOKE ALL OK`）
- **文档**：manual「空容器占位」/ skill 规则 1d / pages/index.html 演示卡 / 本 CHANGELOG
- 门禁：层 1 **139/139**、层 2 **42/42**、`moon fmt --check src` 零内容差异

### Fixed（issue #35：派生名不得占用 MoonBit 内建类型名——让位后保险丝不再误报 J0002）

- **现象**：JSON 对象首键为**内建类型名小写**（`int`/`string`/`bool`/`double`/`unit`/`char`/`byte`/`float`/`int32`/`int64`…）时，派生名 `capitalize(key)` 撞 MoonBit 类型名 → 产物非法 → **保险丝 J0002**（`internal: import produced an invalid .json.mbt`）。两条通路：① `Int32`/`Int` 系遮蔽内建 → 字段解析成内建 → `[J3004] expects Int32, got record/object`；② `Char`/`Byte`/`Float`/`Unit` 被 jsonmbt **自己的** `parse_type` 判为非 L0 → `[J2007] field type is outside the L0 subset`
- **实测触发**：`trkbt10/indexion` 的 `kgf-transpile/c.json`——首键 `int` 的「语言类型映射表」（真实高频形态）
- **根因**：`used_type_names` 只播下 `["Never"]`，未预留内建名
- **修法**：播种扩为 **`tyenv.parse_type` 识别为类型的名字 ∪ {Never}**（16 个：`Never Int Int32 Int64 Double String Bool Array Map Unit Byte Char UInt UInt32 UInt64 Float`）——派生名自动让位（`Int`→`Int2`）；映射值撞名判据随之收紧（把类型名当值用＝同样的遮蔽病）
- **锚**：层 1 新锚「派生名让位内建类型名」（`int`/`char`/`string`/`bool`/`unit` 五例，修前 `Diag` 红）；层 2 新锚 `builtin-type-name-reserved`
- **真数据验证**：修复后 MoonBit 生态 5 仓 270 张 **J0002 归零**，`indexion` 该张转 LAYOUT-EQ，通过率 84.07% → **84.44%**
- 门禁：层 1 **139/139**、层 2 **42/42**

### Fixed（issue #34 / D-13：moon fmt 归一化 Int→Int32——规范拼写跟随，存量零破坏）

- **现象**：#33 处置后层 2 唯一红 = `fmt-fixed-point` 金门——moon 0.1.20261012（moonc v0.10.15）的 `moon fmt` 对类型位置做**别名归一化**（`Int`→`Int32`、`UInt`→`UInt32`；Int64/UInt64/Double/Bytes/Char 不动，探针实证），import 产物写 `Int` 则 #18 fmt 不动点恒破——金门按设计显性化（非 #33 升级引入）
- **前置探针**：`Int` 系 `Int32` **同型别名**（跨注解双向赋值 + 泛型容器互传 `moon check` 全过）——拼写切换零语义变化
- **修法（用户裁定方案 A，D-13 终案）**：① `JType::show` 产 `Int32`（import 产物/诊断文本统一规范形）；② `parse_type` **双拼写识别**（`Int` | `Int32` → JTInt）——手写 `Int` 合法、存量文件 check/build 双绿实证；③ `UInt32` 入 JTUnsupported（fmt 归一拼写——不列则被 struct 分支误吞、诊断劣化）；**CI `version: latest` 维持不 pin**（latest + 金门 = 漂移雷达 fail loud）
- **锚**：层 1 红名单 9 锚手工随迁（negative_test ×2 / manual.mbt.md ×2 / importer_test 快照+查找串——**拒 `moon test -u` 粉饰**〔contains 锚查找串未随迁被刷成 `false` 废锚〕，含 `\n` 转义行走 Edit 工具避 heredoc 反斜杠折半坑）；期望样本随迁 5 处（examples/server + probe/samples/server,vitals——`port`/`x`/`retries` 注解）；**层 2 新锚 `legacy-int-spelling`**（Int/Int32 同文件混拼 check/build 双绿 + UInt32 → J2007 非 struct 误判）——J9 埋雷证红（临时回退双识别 → 18 红连带〔show 产 Int32 与 parse 只认 Int 的产出/解析不一致态〕）→ 恢复全绿
- **文档**：README（示例/Option 行/诊断样例三处）/ skill 手写规则 1e（规范拼写条目）/ PLAN D-13 + §5 里程碑 + §9 探针存档（fmt 归一化 + 同型实证）
- 门禁：层 1 **137/137**、层 2 **41/41**（金门复绿——红→绿闭环）

### Fixed（issue #33：moon 0.1.20261012 拒装传递依赖旧格式——parser 0.4.3→0.4.4 升级）

- **现象**：moon 0.1.20261012（moonc v0.10.15）在安装/解析阶段拒绝 `.mooncakes` 内仍以 `moon.mod.json` 分发的传递依赖（`moon.mod.json ... is no longer supported. Run moon fmt to migrate to moon.mod`，rc=127）——依赖链 jsonmbt → moonbitlang/parser@0.4.3 → moonbit-community/prettyprinter@0.4.10；`moon update` 本身过、`moon fmt` 只迁本项目不触缓存，项目侧无法自救
- **修法 = 上游跟进路径**：registry 实查 prettyprinter **0.4.11**（2026-10-11）已迁 `moon.mod` 新格式分发，parser **0.4.4**（2026-10-12）deps 与 0.4.3 **唯一差异**即 pp 0.4.10→0.4.11——`moon.mod` 一行 `parser@0.4.4`，lexer/x 不动，无需缓存缓解 hack
- **红→绿**：同版 moon 本地复现断供（rc=127 同款报错）→ 升级后缓存确认 `moon.mod` 新格式；`MOON_CC=clang` native release 构建 rc=0（10 warnings 均本仓既有）；pages js 链路 SMOKE ALL OK
- **门禁**：层 1 **137/137**；层 2 **39/40**——唯一红 `fmt-fixed-point` 为**姊妹漂移非本批引入**（新版 `moon fmt` 归一化类型位置 `Int`→`Int32`，探针实证 `UInt`→`UInt32` 同改写、`Int64/UInt64/Double/Bytes/Char` 不动），拆 **#34** 走 PLAN §8 评审（规范类型拼写 = 语言面决策，本批不夹带）
- CI `setup-moonbit version: latest` 未 pin 维持（#34 附带决策点：latest + 金门 = 漂移雷达 fail loud）

### Fixed（issue #18：import 产物收敛 moon fmt 不动点——生成器宽度驱动重写 + 层 2 金门）

- **勘误定谳**：PLAN §9「全部形态 fmt-stable」旧结论证伪（疑踩陷阱 #45 静默假成功）——import 产物实非 fmt-stable（fmt 补 `///|`、短 record 收敛单行、数组折回）；codegen 头注释与 PLAN §9 双勘误成文
- **生成器重写为宽度驱动 fmt 不动点**（按 #18 评论封盘的 13 形态探针 + 本轮金门迭代补探）：整行 ≤84 record 单行**尾逗号规范形**（`S::{ k: v, }`——嵌套递归内联；**宽度按 UTF-8 字节**，金门实证中文行 73 码点 87 字节被展开）；超宽每字段行；数组 ≤80 单行、标量超宽**填满式**（行宽 84，B1/synth 对账定界）、复合元素每元素一行（record 元素单行尾逗号形）；Map 单行**无尾逗号**、超宽每对一行；`Some(` 折；`#|` 随嵌套缩进（#26 语义兼容）；每顶层声明补 `///|`；空容器 `{}`
- **层 2 金门 `fmt-fixed-point`**：probe/samples 全输入 + 3 合成宽样本（#|/宽 record/25 元素数组）→ 影子 moon 项目跑真 fmt → 逐字节零 diff 常驻断言——**moon 升级 fmt 形态漂移即金门红**（漂移显性化）；修复前红（首张 empty_containers 即抓）；import 拒绝的输入（形态拒绝）跳过不计
- **`--fmt` 退化 no-op**（spawn moon fmt 路径删除——旧「moon 缺席 rc=4 半成功态」契约随之作废；旗标保留零破坏 + hint）；旧「run moon fmt」hint 撤销（import 静默）
- **锚随迁**：层 1 快照/保留字/type-name-map/fill×2 重录新形态（120/120）；层 2 cli-hints（import 静默）/fmt-fail（no-op 契约）/fill×3 随迁（35/35 含金门）
- 门禁：层 1 **120/120**、层 2 **35/35**（双 exe）

### Fixed（issue #31：保留字 stem 断链——D-7 期望名全链统一走 sanitize_stem）

- **现象**：`type.json`/`in.json`/`match.json` 等保留字文件名——import 按 `sanitize_stem` 产 `x_type` 绑定（rc=0 合法产物），CLI build/check 用 **stem 原文**做 D-7 校验 → J2003「import 成功、build 即红」；doctor 同病误诊（让人去改名而非暴露口径不一致）
- **修法（方案 1+3 合体）**：消费侧两处对齐（`main.mbt` run_one 与 `doctor.mbt` 各一处 `expected_name` 走 `@src.sanitize_stem`，match 形态保 None 传播语义）+ **D-7 语义成文**：绑定名 == `sanitize_stem(stem)`（确定性映射；常规 stem 恒等 → 既有文件零行为变化）——PLAN D-7 行、api 注释、skill 规则 2 三处同步
- **锚**：层 2 新锚 `reserved-stem-chain`（import→build→check→doctor 四路全链 + 常规 stem 错名仍 J2003 回归锚）；埋雷证红（临时还原 build 侧原文校验 → 断链锚红）
- 门禁：层 1 **120/120**（无涉回归确认）、层 2 **34/34**（双 exe）

### Added（issue #30 裁定落地：migrate 四榜 LAYOUT-EQ 档 + pretty 字节口径钉死——用户裁定，撤 prettier 内联参数案）

- **定性修正（用户论证，本仓采纳）**：pretty 档「恒展开数组」不是能力缺口而是**选定设计**——`build_source` 的 pretty 分支就一行标准库 `stringify(indent)`（布局策略归 moon 标准库），语义锚自始是 **Go `json.Encoder` 口径**（api.mbt 注释 + 层 2 `pretty-vs-go-encoder` 锚在跑 + Go indent 同样展开单元素数组）——42.9% BYTE-EQ 量的是样本构成（人写占比），不是产品能力；**prettier 内联参数案撤销**（双主人冲突威胁 Vitro Go 口径门禁 + prettier 是随版本漂的全局 doc 算法）
- **结构性死结成文**：`.json.mbt` 是类型化重写非保格式载体——源布局信息 import 时已丢、降级产物重新序列化，「逐字节还原人写源」架构上不可达（塞布局元数据违背类型即 Schema）；prettier 口径若成真需求走显式 `--profile` 独立档（默认产物一字不动）
- **migrate 三榜 → 四榜**：新档 **LAYOUT-EQ (whitespace only)**——原文件 parse 紧凑归一与 built_compact **逐字节**等（值树+键序+转义规范形全等，差只在排版与表示；字符层剥空白会误伤字符串值内语义空白，故对称归一）——人写/prettier 源大多落此（issue 实测 107/129 张形态），「值层面可替换性」可见；VALUE-EQ 收窄为表示差不归一形态（如 `1e2`——.json.mbt 侧写不出的指数记法〔陷阱 #13〕）；summary 行四榜计数
- 层 2 `migrate-three-boards` 随迁（layout 样本=人写短数组内联形态 + value 样本换 `1e2`；**转义形态差 `\u4e2d` 被对称归一消解落 LAYOUT——分层比原设想更准**：转义差与空白差同属「重新序列化会归一」的表示差）
- 文档口径三处：README 契约清单（字节口径条目）/ INTEGRATION.md（口径 blockquote + 死结说明）/ skill（四榜 + 迁移面口径）
- 门禁：层 1 **120/120**（无涉回归确认）、层 2 **33/33**（双 exe）

### Fixed（issue #27/#28/#29：随机 12 项目实测批三 bug——静默改写/词法对齐/漏扫）

- **#27 Map 键不反转义（静默数据改写，P1 级）**：`l0_map` 键曾直拼源码原文——含 `\` `"` 转义的键（jest transform 正则键形态）降级多转义一层、值被静默改写且 check 过；按处方一行修（`unescape_string(raw, el.key_loc)`——与字段值路径同款），重复键判定随之按解码值（D-11）。**migrate DIFF 哨兵首次在第三方真实数据抓到真缺陷**（nestjs sample/*/jest.json，4/608 张）；验收：紧凑原源往返逐字节回源、migrate 判 BYTE-EQ
- **#28 is_legal_label 对齐 moon 词法区间表**：`>= 0x80` 近似曾把 π/А/א/अ/ก 等表外字母误判合法 → 直出非法 label 触发保险丝报成 J0002 generator bug；替换为 lexer 硬编码表（RE_LIDENT_START/RE_IDENT_CONTINUE，22 区间三函数）。19 码点对账全锚（π → Map 逃生门；é/中/😀 表内合法；异值键样本从 J0002 变 J4011 可行动诊断）；**旧认知勘误**：「非 ASCII 一律合法」是过度概括
- **#29 migrate 点目录漏扫**：`has_prefix(".")` 一刀切静默漏扫 .vscode/.github/.devcontainer 类人写配置（实测 650 张漏 42 张全在点目录）——改**只跳 .git/_build/node_modules/target** + 跳过目录显式声明输出（`skipped N dir(s): …`）；层 2 新锚 `migrate-dotdirs`
- 门禁：层 1 **120/120**（+2 锚）、层 2 **33/33**（+1 用例）、三张 issue 原复现终态手验；**#30（pretty 数组布局）挂分析评论待裁定**（三案评估：1+2 组合建议）

### Added（issue #26：emitter 对含 `\n` 字符串产 `#|` 多行——教师循环形态保真，方案 1）

- **动机**：`#|` 手写真源（43 条长中文）→ build 降级 → 改值 → `--fill` 回写——全部条目（含未变的）磨损成单行转义长串，写作面单向退化；`#|` 多行是手写面核心可读性卖点，回写必须保形
- **落法（方案 1，工具面）**：`render_string_value`——值含 `\n` 产 `(\n#|行\n…)` 值位括号包裹 + **无前导空格规范形**（moon 语义 `#| x` 空格入值，不产即不引入——与 #24 语义对齐）；单行值保持转义；**含 `\r` 的值例外走转义单行**（CRLF 行尾 `\r` 入值语义在读取层有歧面，转义保真）
- **探针先行（fmt 幂等形态）**：构造器 payload/record 字段/Map 值/数组元素/Some 内全值位 moon 合法；fmt 归一为「值位括号包裹 + `#|` 随嵌套缩进」，二次 fmt 不动——emitter 产顶格 `#|`，fmt 一跑归一、幂等（#25 的 Group(Paren) 恰好铺平 `#|`×括号×fmt 共存）
- **教师循环端到端实证**：`#|` 真源 → build → 改一条值 → `--fill` 回写——未变条目 `#|` 原样存活、改值条目产 `#|` 多行（不再磨损）；方案 2（增量保形）的动机随形态恢复消失，不做
- **锚**：层 1 红→绿（含 `\n` 产 `#|` + 单行保持 + 回吃往返无损 + `\r` 例外）+ 埋雷证红（临时还原旧 escape 分支 → `#|` 形态断言红）；JSON 输入的 `\n` 转义在 moon 源码层用 `\u{5c}n` 构造（heredoc 产不出 `\\n`——环境坑又实锤一次，锚写法对齐 D-9 三形态锚先例）
- **文档三面**：demo 矩阵——「JSONC 注释剥离」条目勘误（「JSON 输入侧不吃尾逗号」已过时→尾逗号/BOM 全收）+ `#|` 条目补回写保形 + 新「冗余圆括号剥除」条目（#25 顺带补齐 demo 面）；skill——规则 5 补 emitter 规范形 + `--fill` 工作流补「教师循环形态保真」段 + emitter 纪律新增第 4 条；README importer 段补一句
- 门禁：层 1 **118/118**、层 2 **32/32**（双 exe）、pages smoke ALL OK（demo 矩阵更新后 31 断言全绿）

### Fixed（深度审阅处置 2026-10-10：P1×3 修 + P3×2 修——审阅探针/突变注入双验）

- **P1-a `lub` 缺 `JTOption` 臂**：`#20` 元素位自聚合后 JTOption 首次流入 lub，旧匹配表落 hetero——`[{"a":[null,1]},{"a":[null,2]}]` 报 `Int? vs Int?` **同型误拒**（旧实现靠 `(JTNullLike,t)` 静默吞掉的空洞被 #20 暴露）；补 Option 双向臂（内层递归 lub——同型保型/上浮语义不变，null 由 NullLike 臂先行兜底）；双样本锚 + 真异构仍拒负锚
- **P1-b `unescape` 花括号路径缺代理检查**：`\u{d800}` 只查 >0x10FFFF 上限——代理点 `unsafe_to_char` 后降级链 panic 且 **check 放行 build 崩**（绕过 D-8 ① 校验先行）；moon 本尊 `[4064]` 拒（审阅实测）——jsonmbt 不比 moon 严；花括号分支补定长 `\uXXXX` 同款代理区检查 → J3003（#16 同族逐处对齐）；锚含 0x10FFFF 合法收码点断言
- **P1-c `--fill` 标量 payload 空键 panic**：`{"case":"Scalar"}`（无 value 键）对声明 `Scalar(Int)` 在 `render_variant_payload` 取 `payload_keys[0]` 越界 panic；改 J3006 fail loud（fill 只重写值体——数据与声明不同步不吞错）；#14-2b 新代码的可达性空洞
- **P3 `--strict` 误用守卫**：build/check 带 `--strict` 曾静默忽略（与同批 `--input` 自立的 fail-loud 纪律相悖）——补 JUsage（strict 是推断档，build/check 无推断面）；层 2 `jsonc-input-profile` 补断言
- **P3（文档）CHANGELOG 增量链自洽**：#22 段 `+7` 勘误为净 +6（P2-6① 迁移是重写非新增——链条 104+2+6+2=114 对账）
- 门禁：层 1 **117/117**（+3 锚）、层 2 **32/32**（双 exe）、四件终 exe 手验（P1-b check 侧先拒 = D-8 ① 恢复）

### Fixed（issue #25：L0 拒绝冗余圆括号包裹的字面量——moon fmt 规范产物可读）

- **定性**：`A(("x"))` 是合法 MoonBit（fmt 幂等保留该形态——实测复核：payload 构造器位保留双括号、数组位收敛单层），值上严格等价 `A("x")`——拒绝即「合法 MoonBit 子集」承诺的非预期收窄（与 #16 转义宽集同族：jsonmbt 不比 moon 严），互操作 bug 级（真源进 fmt 跑的 workspace 即触发，Vitro #60 批一实录）
- **修法**：`l0_expr` 新增 `Group` 分支——`Group(Paren)` 递归剥除（多层括号自然解、depth+1 计入防括号炸弹）、`Group(Brace)`（花括号块 = 副作用序列面）仍 J3001 拒（负锚：`A({ let s = "a" s })` 合法 MoonBit 但拒）；分发层修复 = **所有值位统一剥**（payload/数组元素/record 字段/Map 值/Some 内），不止 issue 建议的 payload/数组两处
- **AST 快照登记**：`ast_snapshot_wbtest` 投影加 `G(p/b, …)` 变体 + 快照样本括号字段（parser 升级对冲面补齐）
- **锚**：层 1 红→绿（`A(("double"))`/`A((#| 多行))`/三层括号值等价 + Brace 负锚）；probe/samples 新样本 `paren_payload`（fmt 后单层括号形态 + `#|` 带空格，moon check 干净——首版 enum 形态触发 `unused_constructor` warning 改自由数组，payload 位防线在层 1 锚）
- 层 1 **114/114**（+2）、层 2 **32/32**（probe-samples 自动消费新样本）、build 0 err

### Added（issue #22：JSONC 尾逗号收编——消解式，D-9 重写为输入 profile 单点定义）

- **判据（可判定非枚举）**：只收「字符层删/替空白可消解为严格 JSON」的宽松特性——注释、对象/数组/嵌套尾逗号、BOM（仅文件首）收；`{,}`/`[,]`/`[1,,]`/`{"a":,}`、单引号串、无引号 key、hex、`NaN`/`Infinity` 永不收（扩值域——JSON5 因此不进）；tsconfig/eslintrc/settings.json 类真实文件直接进
- **落法 = 消解式**：`strip_jsonc` 从注释剥离器升级**输入归一化器**（唯一宽松层），尾逗号同一 pre-pass **等长空格消解**（诊断行列不漂移）；`jsonparse.mbt` 恒裸 RFC 8259——对拍基准不污染（parser 仅删两处 `(trailing comma is not JSON)` 括号注释：消解式下不可达，防误导）
- **机制**：pending-comma 暂存（穿透空白**与注释**看有效字符才判定）+ last_sig guard（逗号前一非空白有效字符 ∈ `{ [ , :` 或文件首则不消解）+ BOM 仅 `pos==0`；埋雷实锤 guard 的真实价值 = 报错位正确性（禁用时报错从 U+002C 漂到 U+005D——「保位」锚先红）
- **CLI `--input <json|jsonc>`**：默认 jsonc；json = 裸 RFC 8259（注释也拒）；import/fill/migrate 三入口同旗标；别值 J0001、非 import/migrate verb 误用拒绝；**不复用 `--strict`**（#14-2a 已占用）；库层 `import_source`/`fill_source` 新增 `jsonc? : Bool = true` 出口面参数（mbti 已同步）
- **锚拆档（防线净增）**：P2-6① 原断言迁移至 json 档锚（永久保留——重写非新增）+ 默认档翻转为值等价锚；负锚五形态（开头/孤立/值缺失逗号）；BOM 锚（文件首消解 + 字符串内 U+FEFF 保留）；穿透注释锚；保位列位锚；层 1 **112/112**（净 +6 = 五新锚 + manual 摄取章可执行锚；审 P3 勘误：原记 +7 误将 P2-6① 重写作新增——增量链 104+2(#24)+6(#22)+2(#25)=114 自洽）
- **层 2 第五件**：probe/samples 新样本对 `tsconfig_like`（.jsonc 三合一输入 + 人写语义命名 .json.mbt + golden .json）；caseProbeSamples 扩第二循环（.jsonc 输入 → import → build 与 golden 比 + `--input json` 同输入必拒）；新用例 `jsonc-input-profile`（旗标值域/误用/双档对拍）——层 2 **32/32**

### Added（issue #24：Vitro 教学资产批实战反馈——建模指引 + `#|` 空格语义 + doctor 排版 note）

- **键域强校验指引三处落文**（#24-1）：manual 新可执行锚「键域强校验——带参枚举数组」（`Map[AlgoE, String]` 裸构造器键位 moon 本尊即 `[4014]` 拒——语言层边界，本仓探针复核；正解 = 带参枚举数组，降级 `[{"case","value"}]`）+ skill 规则 3a + README importer 段——Vitro 两轮探针摸出来的路，写下来免重摸
- **`#|` 前导空格语义文档化**（#24-2）：moon 原生语义 `#| x` 值 = `" x"`（非 jsonmbt 偏差）——manual 新可执行锚 + skill 规则 5 补句
- **doctor 排版 note**（#24-2b）：「全部非空 `#|` 行统一前导空格」形态 → note 行（hint 级——不计 ❌/⚠️、不改 rc：接线闸不掺内容口味；空行/纯空格行不参与统计，缩进 `#|` 不参与——moon 标记顶格，漏报无害）；层 2 新锚 `doctor-pipe-hint`（红→绿：实装前证红 + 对照组无 note 断言）
- 层 1 **106/106**（manual +2 可执行锚）、层 2 **31/31**（+1 用例）

### Fixed（issue #23：build 无 -o 默认输出名护栏 + 落盘 hint 点名输出路径）

- **主诉求在 HEAD 不复现**（三重证据：`main.mbt` 唯一 `.json` 拼接点自 P1 MVP 未变；import/migrate 三条输出路径全排查无坑形态；Vitro 原文件 `rules.json.mbt` 原名实测产出 `rules.json` 正确）——issue 实录的 `.json.json` 最可能源于 Vitro 滚动消费本仓 `_build` exe 时的旧/中间态产物（陷阱 #41 下游版）。处置 = 锚死契约 + 补建议 2，不改动正确行为
- **层 2 新锚 `default-output-name`**：单/多输入 `x.json.mbt` 无 `-o` → 断言 `x.json` 存在且 `x.json.json` 不存在（issue 实录老坑形态点名拦截）+ 产物内容正确；埋雷证红（临时注入剥 `.mbt` 坑形态 → 5 用例红，含本锚）后排雷全绿
- **落盘 hint 点名实际输出路径**（issue 建议 2）：`build without --pretty emits compact JSON → '<target>'`——下游批量脚本漏 `-o` 时 hint 只说形态不说去向帮不上忙；带 `--pretty` 静默、`-o -` 无落盘 hint 契约不变
- 层 2 30/30（+1 用例）；层 1 104/104、build 0 err（无涉改动，回归确认）

### Added（issue #19：Map 键序契约进下游文档）

- INTEGRATION.md 新节「机器生成 .json.mbt（emitter 作者契约）」：Map 键序 = 源文本序（不排序——D-11 ④）、禁止依赖运行时 map 遍历序（Go range 序随机——Vitro jmemit 实测踩坑）、任意确定性序皆可；README 契约清单同步一行。行为无变化（契约一直在，本次补文档面——锚早已在位：probe/samples Map golden 锁键序 + PLAN D-11 ④ + skill emitter 纪律 2）

### Added（issue #17：数字降级规范化契约成文——方案 C）

- README 契约段 + 层 1 专用锚：整数族（Int/Int64）解析值归一（`-0`→`0`、`0x10`→`16`、Int64 全精度文本保留）；Double 源拼写透传（`1.50` 原样——避免解析-再格式化精度伪影）。方案 B（规范化为最短往返）被否：破坏透传的无损设计且收益仅限「人工改拼写」场景（机器生成源天然稳定）。层 1 97/97

### Fixed（issue #16：字符串转义宽集对齐 moon 词法）

- `unescape_string` 补三形态：`\/`（JSON 惯用，moon 实测接受）；`\uXXXX` 定长（moon 词法宽于文档——rc=0 接受，「MoonBit 接受 ⇒ 必须接受」）；**代理对合成**（`\ud83d\ude80` → 🚀，UTF-16 语义）；**孤立代理拒收**（J3003）
- 勘误（逐项实测）：#16 主表 7 项中 5 项（`\t \n \" \\` 等）在最新 exe 已工作（审计为 10-07 旧版）；「import 含转义 JSON 全灭」推测不成立——JSON 侧解析器一直支持 RFC 8259 全转义集
- README 转义契约成文（输入侧 = moon 词法宽集；输出侧 = 最小转义 + 非 ASCII 裸 UTF-8，同值异形输入产同一规范形）
- 层 1 两锚（宽集对齐 + import 往返值等价与规范形）→ 96/96；probe/samples 新样本对 `escapes`（全转义族，moon check 同源双验）；层 2 26/26

### Added（issue #14 批次 2b：`--fill` 按已声明类型重算值体 + 分档闸）

- `import x.json --fill x.json.mbt`——第三条注记通道（类型定义本身）落地：读已有产物的类型头（analyze：structs/enums/field-alias 注记全收），**以声明类型驱动渲染源 JSON 值体**——空容器直吃声明元素类型（不再 Never/启发）、键集漂移按声明 enum 消歧（`case` tag 键或键集精确匹配双形态——fill 能吃自身降级产物，round-trip 闭环）；无匹配变体 J3004、键集多余/缺失 J3005/J3006（数据不同步不吞错）
- **头逐字节保留**：切分点 = `pub let` 行内首个 ` = `（注解属类型头）——人工改名、新增 struct、手写注释全部存活（层 2 断言）
- `--fill --check` **分档幂等闸**：头保留语境下校验值体与源 JSON 同步（源变 rc 2 J5001）——不再惩罚人工语义命名（与 `--type-name-map` 双通道共存）
- `-o -` 预览；`--type-name-map`/`--strict` 与 fill 互斥（语义不交集，J0001 fail loud）
- 渲染器 `strict_keys` 参数化（一套双模式，import 主路径零变化）；`fill_source` 出口（moon info 登记）
- 层 1 94/94（fill 三用例：直填/消歧双形态/负样本）、层 2 26/26（fill 用例：头保留/同步 rc0/源变 rc2/预览/互斥）

### Added（issue #14 批次 1+2a：T?? 收窄 + 空容器 Never 占位）

- **T?? 递归收窄 J2007**（批次 1）：实测 `String??` 下 `None` 与 `Some(None)` 降级都成 `"a":null`——静默压平违反 §0 无损与 D-8 ②；`scan_supported_type` 嵌套 Option 分支 fail loud（任意深度递归拒，J2007 专属文案指向三态评审状态）。推断链只加一层 Option——**纯手写面，现存绿文件零影响**（层 1 三形态锚 + 层 2 golden 双证）。三态展平式（None=缺席/Some(None)=null/值）走 §8 评审；容器位（Map 值/数组元素）结构上无法缺席，评审落地前一并收窄
- **空容器 Never 底型占位（默认）**（批次 2a）：J4001/J4002 不再整张拒——`exemptions : Array[Never]` / `cfg : Map[String, Never]`，产物含 `pub enum Never {}`（fmt 归一形态，探针实锚）；**一条机制同解空数组+空对象**（零信息容器的数学精确刻画——非猜测占位，输出逐字节不变）；**免费护栏**：元素位写值被 moon `[4014]` 与 jsonmbt J3004 双侧拦下；D-1 两级启发优先级保持（能推精确类型的绝不出 Never，收尾统一占位只兜真孤立）
- **`--strict` 反向 opt-in**（严格档=旧行为）：空容器启发无解时如旧 J4001/J4002 拒（J4001/J4002 语义收窄到 strict 档——旧锚已迁移 strict 形态）
- **J4031**（新码，rc 0）：占位 hint——非空样本出现后换真类型（或 re-import）
- **Never 预留**：`used_type_names` 初始含 Never——`{"items":[{"never":1}]}` 派生组名被迫去重 Never2，底型名不被占用
- probe/samples 新样本对 `empty_containers`（fmt-stable + moon check 编译面 + golden 往返）；层 1 91/91（+2 用例，3 旧锚迁移）、层 2 25/25（+1 用例）

### Fixed（深度审阅处置：P1×1 + P2×2 + P3×3 修 / P3×1 拍板登记）

- **P1 部署门不挡红**：`pages/smoke.mjs` 断言失败只有 `console.log`、rc 恒 0——`pages.yml`「smoke 红不上线」承诺不成立。修：末尾 `if (bad) process.exit(1)` + 头注从「一次性勘探勿入防线」改为部署门口径（注入复现双向验证：坏断言 rc=1 / 正常 rc=0）
- **P2 嵌套 enum payload 误报**：`enum Field { Named(Col) }` + 字面量 `Named(X)` 被误报 J3004——payload 形参类型存 parse_type 原值（JTStruct 裸名），payload_case 消费点漏 `resolve_custom`（root/struct 字段侧都 resolve，唯 payload 漏）。修：消费点 resolve；层 1 新用例先行红（审阅注入证明锚聋——修复后 87→88 锚仍绿说明原 87 无此路径）
- **P2 migrate taken 模拟失真**：目录已有 .json.mbt 孪生时 taken=[] 起始漏盘面名——`--write` 产物与真实 import 不一致 → `import --check` rc=2 自相矛盾。修：per-directory 预扫盘面既有 .mbt struct 名作起始 taken + 目录级累积（跨目录互不影响，对齐真实 import 的输出目录扫描基准）；层 2 新用例（前缀化告警 + 自洽闸 rc=0 + BId 形态）先行红
- **P3 J4010/J4011 截断计数**：诊断在首个冲突合并处短路，后续样本未入分布——「N distinct in M samples」实为下界。修：help 明示「counts cover samples seen up to the first conflicting merge — treat them as lower bounds」（层 2 golden 先行红同步）
- **P3 pages.yml 缺 MOON_CC**：与其自身注释/index.html 页脚「同款命令勿单侧漂移」矛盾——补 `env: MOON_CC: clang`（js 后端实际不走 C 编译器，仅为三处命令形态一致）
- **P3 矩阵与 smoke 不同步**：index.html Option 卡 `Some("x")` vs smoke `None`——smoke 改为 index 卡逐字同步 + None→null 语义专断另立一条（BUILD 集 4→5，「全部过冒烟」承诺成立）
- **P3 payload `value` 键不对称（拍板：登记不修）**：标量 payload 用 `"value"` 键、struct payload 含 `value` 字段展平同键——J3008 只防 `case` 不防 `value`。拦 `value` 会误伤合法数据字段（真实成本）vs 实际歧义可由 `case` 值区分（收益低）——登记为 D-5 已知面（PLAN §6）
- 审阅「已排除」两项（cmp_rows `×` 偏移未致排序失效、`#|` 行不误触注记扫描）确认不处置

### Fixed（issue #15：J2007 help 文案与实现对齐）

- J2007/J4003/J3004/J3006 四处 help 文案的 `Option[T]` → `T? (Option)`——Option 的合法写法是 MoonBit 后缀糖 `T?`（前缀形态 `Option[Int]` 被 parse 判 JTUnsupported 拒收），文案列 `Option[T]` 为 supported 是指路被拒写法（pages playground 样例卡实测发现）。方案 A（改文案）；方案 B（放开前缀别名）按 issue 论证不做（引出产物 fmt 形态问题）
- 层 1 两处逐字节锚先行红（negative_test 115/208）→ 绿 87/87；层 2 新增 `j2007-help-text` stderr 逐字节 golden，23/23 绿

### Added（pages 体验：加载等待提示 + README 直入标签）

- `pages/index.html`：引擎改**动态 `import()`**——静态 import 会把整个交互脚本卡在 ffi.js（~7.8MB）下载期（输入框可见但零反馈）；现先绑 UI 并显示「⏳ 引擎加载中」状态（新 `#status.loading` 样式），就绪后自动跑初始转换，失败显式报错（网络/GitHub Pages 分发问题可诊断）；下载期间的手动转换提示「将在就绪后自动执行」
- README 顶部（banner 下）加**在线试玩直入标签**：<https://rustin-beep.github.io/jsonmbt/>
- 验证：页面 module 脚本 `node --check` 语法过；动态导入链 node 实跑（import→build 往返）绿；smoke 22 断言复跑绿

### Added（issue #6-5：`jsonmbt migrate` 批量迁移侦察三榜报告）

- `jsonmbt migrate [dir] [--write]`——把「探测哪些能迁」从下游仓手写 shell 脚本产品化：逐张 import → build（pretty+compact）→ 与原文件比对三榜：**BYTE-EQ**（行尾归一逐字节相等，可直进 CI 对账）/ **VALUE-EQ**（值语义等价键序不敏感——新 `@src.json_value_eq` 树比；风格差，接 CI 前须确认字节口径，报告尾 hint）/ **REJECT**（J 码 + 消息首行）；DIFF 兜底榜（往返值不等理论不可达——出现即缺陷信号）
- **默认零写**（侦察契约）；`--write` 落盘非 reject 产物；rc：任一 reject/diff → 1（迁移完成度闸）
- **内存 taken 累积**模拟「逐张真实迁移」的同目录撞名序列（#4 前缀化复现）；前缀名出现时 note 行指路 `--type-name-map`
- 已有同名 `.json.mbt` 孪生的文件跳过（已迁移不重复报）；JSONC 原文件因注释恒落 VALUE-EQ（如设计）
- 层 2 +1 用例（三榜分类/零写/--write/rc/空目录），22/22 绿

### Added（issue #6-4：`--type-name-map` + Map 值宿主派生命名）

- `import --type-name-map <map.json>`：机器派生名（Id/File2/Print_int 等零信息量形态）→ 语义名映射；**键 = 最终派生名**（用户从首次 import 产物复制——含 #4 跨文件前缀化形态如 ItemsId）；值校验 fail loud（非法类型名/撞已占类型 → **J1010** 新码；映射文件坏 JSON → J1002、形态非对象/值非串 → J1010）；未命中键 → hint 不阻断（typo 核对提示）；build/check 误用该 flag → JUsage
- **Map 值类型命名改宿主字段派生**（issue 评论拍板）：`cases : Map[String, Src_sha]`（首键派生，值实为完整条目——误导）→ `Map[String, CasesEntry]`（Map 持有者名字为语义锚）；数组位/顶层无宿主 → fallback 首键派生；首见定型，确定性保持
- `ImportOutcome` 增 `unmatched` 出口（层 1 锚）；层 2 +1 用例（映射全链/J1010×2/hint/宿主派生），21/21 绿

### Added（pages CI 接线：GitHub Pages 自动部署）

- `.github/workflows/pages.yml`：push master / PR / 手动触发——js 引擎构建（debug，release tree-shake 坑已登记）→ **22 断言 smoke 作部署门**（断言红不上线）→ index.html + ffi.js 上传 → `deploy-pages` 发布；PR 只验不部署
- Pages 站点经 API 启用（`build_type=workflow`）：<https://rustin-beep.github.io/jsonmbt/>（HTTPS 强制；index.html ESM 相对路径天然兼容项目子路径）
- index.html 页脚更新为 CI 自动部署说明

### Added（issue #5：`jsonmbt doctor` 只读接入诊断）

- `jsonmbt doctor [dir]`——诊断「这个仓的 .json.mbt 有没有真正接上 MoonBit 工具链」（Vitro 批②最大坑：不在包边界内的文件 moon 完全看不见，「验证了没被编译的东西等于没验证」）。**只诊断不 setup**（包怎么切/workspace 怎么分是用户仓的结构决策）
- 每文件四项：包边界（moon.pkg 在本目录 + 祖先链模块根；❌ 给一行修复）/ 跨文件 struct·enum 撞名（moon 编译期才炸的坑提前拦）/ check·build（含 D-7 stem 归属，纯内存）/ fmt 稳定（TEMP 影子包实测——同目录一次 spawn，per-file 结果表）；另有 workspace 上下文行
- rc：任一 ❌ → 1（CI 直接挂闸）；全 ✅/⚠️ → 0；moon 缺席/临时目录缺席 → fmt 项诚实 ⚠️ 不误报
- 全程只读（验收 4：跑前后目录快照不变）；影子包用完递归清理
- 新 FFI stub `jsonmbt_is_windows`（跨平台 shell 重定向语法分叉）
- **陷阱 #45 登记**（doctor 影子开发中实测）：`moon fmt <path>` 把 path 当项目内包过滤 pattern，项目外/非包路径**静默跳过且 rc=0**——跨项目 fmt 唯一可靠形态 = `cd <目标> && moon fmt`；fix 文案按包边界状态分叉（未接包时先接再 fmt）
- 层 2 +4 用例（无包 ❌ / 撞名 ❌ / 完整接入无 ❌ / 只读快照），20/20 绿

### Fixed（issue #13：保留字字段名 + issue #14-3：J4010 报告粒度）

- **#13 保留字字段名（`where` 等）**：修复前任一保留字键把整对象踢进 Map 逃生门——同层异类型兄弟值统一失败时泄漏出与保留字毫无关系的 `J4011 incompatible types across samples`（文案错位），单字段对象则**静默降级** `Map[String, V]`（无提示的毒产物）。修复：保留字类键（加 `_` 即合法——探针实锚 `where_` 合法 + fmt 幂等）确定性改名走 struct；类型名按**原始键**派生（`where` → `struct Where`，大写保留字合法）
- **`// jsonmbt: field-alias <Struct>.<label> = "<json键>"` 注记**（合法 MoonBit 注释，fmt 幂等）：产物头部发射非恒等改名表，build/check 预扫描注释层（moon parser 剥注释）按注记还原 JSON 键。纯语法逆映射在尾下划线邻域**数学上不可无歧义**（`where`→`where_` 与原生键 `where_` 任何确定性后缀规则都撞），显式注记是唯一全解——手写文件也因此首次能表达保留字键对象
- 撞名两级下划线：`{"where":1,"where_":2}` → 字段 `where_`/`where__` 双注记，往返无损
- **J3009**（新码，只增不改）：注记畸形（行文法）或语义错（指向不存在的 struct/字段、恒等注记、隐含 JSON 键碰撞、重复注记）一律 fail loud
- **#13 文案**：不可改名键（点号/大写开头等，本批范围外）维持 Map 逃生门，但失败文案改为点名键因（`cannot unify values under keys that are not legal MoonBit field labels ('a.b')`），不再误导用户去查不存在的跨样本异构
- **#14-3 J4010 键集分布按容器路径分组**：`at $.entries[]: 2 distinct key sets in 2 samples: ×1 { a, b }; ×1 { a, c }`——顶层/嵌套单样本键集不再与数组元素混计（修复前报 `4 distinct key sets` 把顶层 doc 也计入）；跨路径合流撞形无同容器漂移时回退全量平铺（诚实兜底）
- probe/samples 新样本对 `reserved_keys`（Vitro demo_ui_lint 形态：rules 数组含 where 字段 + 异类型兄弟）；层 2 驱动 +4 用例（往返/两份新文案 golden/J3009 门禁），16/16 绿

### Added（pages playground：P2 js 出口预演）

- `pages/` 前端 demo：JSON ↔ .json.mbt 双栏实时转换（overlay 语法高亮）+ 21 卡「能吃下什么」能力矩阵，全部过真实引擎冒烟（`pages/smoke.mjs`，22 断言）
- `pages/ffi` wrapper 包（js 后端出口三件 js_import/js_build/js_check）——src 包 js/wasm 双后端 0 错编译实测；wasm-gc String ABI 缺口（js-string-builtins 未支持）与 js release tree-shake 坑登记（PLAN §7）

### Added（§8 二次裁定：D-5 键集漂移转正）

- enum 带单参构造器字面量入 L0：降级投影 = tag 对象展开（payload 字段进顶层 + `"case"` 键；标量 payload 加 `"value"` 键）
- tag 键冲突即拒：payload struct 含 `case` 字段 → J3008（不静默覆盖）
- import 侧不自动转（缺键异构仍拒——拼错 vs 真可选无解 + 数据错误静默类型化违反 fail loud）；建模入口 = emitter 直产 / 人工改写
- vm_diff 实例：618 案例四键集 enum 建模，check/build 绿、两次 build 逐字节一致、除 tag 键全等 0 diff、变体分布 602/9/5/2 精确对上

### Added

- `jsonmbt build/check/import` CLI 三动词（D-10 rc 五值表：0/1/2/4 已占用，3 保留）
- L0 子集校验器 + 确定性降级器（紧凑与 `--pretty`/`--indent N` 形态；pretty 与 Go encoder 在键序=源序前提下逐字节一致）
- importer v1：形状签名判重 / D-1 空容器两级启发 / D-2 Int64 上浮 / 键名逃生门（Map）/ tagged-enum hint（J4030）
- `--check` 幂等闸（rc 2 + J5001）；import 产物跨文件撞名自动 stem 前缀去重（#4）
- J 系错误码 20 个（J0001–J5001，只增不改）；诊断 stderr 机器可读前缀 + 尾换行行契约
- 层 2 Go 黑盒驱动（`tests/driver`：进程契约/样本黄金/幂等证红/确定性/exe 新鲜度门禁）
- probe 实验资产：`vitro_gen`（D-6 第一档）/ `jsonmbt_go` + `fossil_batch`（第二档雏形，化石 2469 张双实现对照）
- 可执行使用手册 `src/manual.mbt.md`（mbt check fence 即锚）

### Added（§8 裁定 D-12）

- enum 无参构造器字面量入 L0：有限词表字段的写时值域校验（jsonmbt check 即红，拼错变体 J3004 列全变体；降级投影 = 变体名字符串）
- `#|` 多行字符串入 L0：长中文文本多行书写，降级 = 行净内容以 
 连接
- 边界：带 payload 构造器（E(3032)）v1 拒（观察项）；裸构造器无类型上下文拒

### Added（issue #12 处置）

- `-o -` 纯验证通道（build/import 通用）：产物改道 stdout（二进制 stub，字节契约）——CI 验证降级全链不落盘即验（check 不含降级 codegen，两者不可互替）；与 `--check`/`--fmt` 互斥（盘面语义），stdin→stdout 全管道因无绑定 stem 来源拒绝
- 补录（上批遗漏）：`import --fmt`（#10）——产物落盘后 spawn `moon fmt <单文件>` 归一 fmt-stable 形态

### Fixed

- emoji 代理对越界 panic；带点键/带点 stem 漏网；stderr 截断（issue #1）与 stdout CRLF；多诊断粘行
- （issue #12）J0002 moon fmt 失败文案：改多因列举（moon 缺 PATH vs 产物不在任何 moon workspace 覆盖——moon 原始报错经 system() 透传可见，文案引导对照），弃「is the moon toolchain installed?」单一误导；help 行声明半成功态（fmt 失败 = 产物保留未 fmt 形态 + rc=4，脚本按 rc 判红）
- （issue #12）`jsonmbt_run_cmd` Unix 分支 wait-status 解码（子进程退 1 曾会显示 rc=256；Windows system() 本就直返 exit code）——**未经 Unix 实测**（本仓 CI 面 = Windows native），Unix 环境首跑须验
- （勘误）#12 正文「报错路径退 rc=0」系提报方复现方法错误（`echo 0` 打印字面量非 `$?`）；本地重验两处均 rc=4 契约正常（提报方已在评论中撤回）
