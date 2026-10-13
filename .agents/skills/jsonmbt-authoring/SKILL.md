---
name: jsonmbt-authoring
description: ".json.mbt 类型化 JSON 数据文件的手写与机器生成指南——五命令（build/check/import/doctor/migrate）、子集规则、enum 键集建模、保留字字段名与 field-alias、emitter 纪律、round-trip 兜底。Use when authoring or editing .json.mbt files, wiring jsonmbt into a repo's CI or freeze loop, migrating .json data sources, or debugging J-codes. 触发词：jsonmbt、.json.mbt、类型化 JSON、数据真相源、J3004/J4011、round-trip、doctor、migrate、type-name-map"
---

# jsonmbt 数据文件写作指南

`.json.mbt` = JSON 的类型化源码形态：**MoonBit 子集写数据，确定性降级回 JSON**。类型即 Schema——字段名拼错、类型不配、值越界在 `moon check` 编译期红（行列级），而非运行期。

## 心智模型

一句话：`.json.mbt` 是用 MoonBit 语法写的数据文件；`build` 是它的「另存为 JSON」；`moon check` 是它的「JSON Schema 校验器」。

## 五命令

```bash
jsonmbt import  x.json -o x.json.mbt      # 一次性迁移：JSON → .mbt（形状推断）
jsonmbt import  x.json --check            # 幂等闸：重导入必须逐字节一致（rc=2 漂移）
jsonmbt import  x.json --type-name-map m.json  # 机器派生名 → 语义名（键=首次产物里的派生名，含前缀化形态）
jsonmbt import  x.json --strict           # 空容器严格档：启发无解时如旧 J4001/J4002 拒（默认 Never 占位）
jsonmbt import  x.json --fill x.json.mbt [--check]  # 按已有产物的类型头重算值体（头逐字节保留）；--check=值体同步闸（rc=2 源变）
jsonmbt import  x.json [--input json|jsonc]  # 输入 profile：默认 jsonc（注释/尾逗号/文件首 BOM 消解——tsconfig 类直进）；json=裸 RFC 8259
jsonmbt build   x.json.mbt -o x.json      # 确定性降级（同输入永同输出；失败零产物）
jsonmbt build   x.json.mbt -o -           # build 链纯验证：stdout 出件（check 不跑降级链）
jsonmbt check   x.json.mbt                # 只验不写（校验+内存构造，无降级 codegen）
jsonmbt migrate  [dir] [--write] [--input json|jsonc]  # 批量迁移侦察：四榜报告（默认零写；rc 1=有 reject）
jsonmbt doctor   [dir]                    # 只读诊断：.json.mbt 是否真接上 moon 工具链（四项）
```

`-o -` = 产物改道 stdout（build/import 通用；与 `--check`/`--fmt` 互斥——两者都是盘面语义）。CI 验证 build 链通不通用 `-o - | md5sum` 或 shell 层丢弃——**别用 `-o nul`**（挂 rename 语义报错）。

rc 语义：`0` ok / `1` 输入错 / `2` 漂移（--check）/ `4` 用法错。CI 闸按 rc 判红。

## 手写规则（子集边界——工具会在报错里重申，但前置知道少走弯路）

1. **类型即 Schema**：`struct` 定义即数据形状；可空字段写后缀糖 `T?`（`null` ↔ `None`）——**`Option[T]` 前缀形态被 J2007 拒**；**嵌套 `T??` 同拒**（静默压平违反无损——三态编码在 §8 评审）。改数据先看 struct；
1e. **整数规范拼写 `Int32`**（#34/D-13）：moon fmt（0.1.20261012+）把类型位置 `Int` 归一为 `Int32`（`UInt`→`UInt32` 同理）——import 产物与 fmt 不动点跟此形；手写 `Int` 是同型别名、check/build 照常绿（存量零破坏），新文件建议直接写 `Int32`；
1a. **保留字字段名**（#13）：JSON 键是 MoonBit 保留字（`where`/`type`…）时 import 自动改名（`where_`）并在产物头发 `// jsonmbt: field-alias Struct.label = "原键"` 注记，build/check 按注记还原 JSON 键；**手写文件也可用该注记**表达保留字键对象（注记行文法错/指向不存在的 struct 或字段/恒等注记 = J3009 fail loud）；
1b. **字符串转义契约**（#16）：`.json.mbt` 侧接受 moon 词法接受的一切（`\' \" \\ \/ \n \r \t \b \f \0 \xHH \u{...} \uXXXX`，含代理对合成；孤立代理拒）；降级输出 = 最小转义集 + 非 ASCII 裸 UTF-8（同值异形输入产同一规范形）；
1c. **数字降级契约**（#17）：整数族解析值归一（`-0`→`0`、`0x10`→`16`）；`Double` 源拼写透传（`1.50` 原样——避免精度伪影）；Int64 全精度文本保留；
1d. **空容器占位**（#14-2a）：import 遇推断无线索的空数组/空对象 → `Array[<Stem>Never]` / `Map[String, <Stem>Never]`（产物自带 `pub enum <Stem>Never {}`——零构造器 = 免费护栏，元素位写值 moon `[4014]` 红）；**底型名逐文件唯一（#36）**：`x.json` → `XNever`，同目录多文件各发一份不再重复声明（moon `[4051]`），文件仍自持；`--strict` 恢复旧拒绝（J4001/J4002 只在 strict 档出现）；手写空容器字段直接声明真元素类型（`Array[String]` + `[]`）即无此面；
2. **一个文件一个顶层文档**：`foo.json.mbt` 内有且只有一个 `pub let foo : ...`——**绑定名 = sanitize_stem(文件 stem)**（常规 stem 恒等；保留字/数字开头文件名确定性加 `x_` 前缀：`type.json` 产物绑定 `x_type`，import/build/check/doctor 四路同口径，#31）；
3. **键集不齐的数组用带参 enum**（D-5）：每种键集一个 struct，`enum Case { A(Ax); B(Bx) }`，字面量 `A(Ax::{ field: value })`。降级投影 = tag 对象展开（payload 进顶层 + `"case"` tag 键）；**payload 字段禁止叫 `case`**（J3008 显式拒）；**payload 形参也可以是 enum 名**（`enum Field { Named(Col) }` + `Named(X)`——标量 payload 走 `{"case":…,"value":…}` 形态）；已知面：struct payload 含 `value` 字段展平后与标量 payload 的 `value` 键同形（J3008 只防 `case` 不防 `value`——实际可由 case 值区分，登记不修）；
3a. **键域强校验（有限键集「拼错红」）→ 带参枚举数组**（#24）：`enum AlgoSuggestion { BubbleSort(String); … }` + `[BubbleSort("文案"), …]`——拼错变体名 moon check 写时红；降级 `[{"case":"BubbleSort","value":"…"}]`，下游按 case 值机械投影键名。**别用 `Map[AlgoE, String]`**：Map 字面量键位不接受裸构造器——moon 本尊即 `[4014]` Constr Type Mismatch（语言层边界非 jsonmbt 限制；Vitro 教学资产批两轮探针实录）；
4. **import 不自动转缺键异构**（J4010/J4011 fail loud）——拼错字段名与真可选无法区分，自动推断会把数据错误静默类型化。遇拒看报错里的字段集差异与分布计数（**按容器路径分组**：`at $.entries[]: N distinct key sets…`——顶层不再与数组元素混计；计数是**下界**，扫描在首个冲突合并处短路），手工建模 enum 或补齐键；
5. **长文本用 `#|` 多行字符串**（D-12）——中文长描述不用拼 `\n`；**`#|` 后的首个空格属于值**（moon 原生语义：`#| 冒泡` 值 = `" 冒泡"`——排版习惯想加空格观感时，`#|` 后直接写内容；「全部 `#|` 行统一前导空格」的形态 doctor 会给 note 提示，#24）；**import/--fill 对含 `\n` 的值产回 `#|` 多行**（值位括号包裹、无前导空格规范形——教师循环 build→改值→fill 回写不磨损手写多行形态，#26；含 `\r` 的值例外走转义单行）；
6. **大数 >Int64 拒收**（J4020）：降级要求无损——要保留超长数字请以 String 字段承载；
7. **全 null 列无法推断类型**（J4003）：至少给一个非 null 样本，或手工把字段建成 `Option[T]`；
8. **注释与尾逗号天然合法**——这是相对 JSON 的核心书写优势，用真注释写「这字段为什么存在」；输入侧对偶：`import`/`migrate` 默认 jsonc 档（注释/尾逗号/BOM 消解直进，#22/D-9——与 `.json.mbt` 语法侧的尾逗号是两件事）。

## 迁移面（批量场景）

1. **第一入口 = `jsonmbt migrate [dir]`**：四榜侦察（**BYTE-EQ** 可直进 CI 对账——仅限「机器生成且格式策略一致」的源 / **LAYOUT-EQ**（#30）值+键序+转义规范形全等、差只在排版与表示（人写/prettier 源大多落此——值层面可无感替换，字节层不可）/ **VALUE-EQ** 值等但表示差不归一（如 `1e2` 指数形态——.json.mbt 侧写不出）/ REJECT 带 J 码原因）——别再手写「逐张 import → cmp → 分类」shell 脚本；默认零写，`--write` 才落盘非 reject 产物；**字节口径**：`--pretty` 语义锚 = Go `json.Encoder`（数组恒展开），不承诺对齐 prettier——「逐字节还原人写源」架构上不可达（.json.mbt 是类型化重写非保格式载体，布局信息 import 时已丢）；
2. **撞名前缀化**：同目录多文件嵌套 struct 重名时后来者加 stem 前缀（`Id` → `BId`）——migrate 报告会 note 指路；语义命名入口 = `--type-name-map`（键 = 产物里的最终派生名，逐条改语义名）；
3. **接入诊断**：迁移完先跑 `jsonmbt doctor [dir]`——「文件在不在 moon 包边界内、有没有真被编译」是返工两轮换来的最大坑（moon 看不见 = 验证了没被编译的东西）。

## 注记三通道与 --fill 工作流（#14 终案）

类型与数据谁说了算，三条通道各司其职：

| 通道 | 承载 | 工具 |
|---|---|---|
| **带外 map** | 机械改名（派生名→语义名，可复现） | `--type-name-map` |
| **带内注释** | 表达不成类型的东西（原始 JSON 键名） | `// jsonmbt: field-alias`（#13） |
| **类型定义** | 元素类型/键集消歧（人声明，机器填充） | `--fill`（#14-2b） |

`--fill` 稳态工作流（人工语义命名不被幂等闸惩罚的解）：

```bash
jsonmbt import x.json -o x.json.mbt     # 首迁（类型头草稿）
# 人工改类型头：语义命名 / 补真实元素类型 / D-5 enum 建模 / 新增 struct
jsonmbt import x.json --fill x.json.mbt --check   # CI 闸：只校验值体与源同步（头保留语义）
# 源 JSON 变了 → 重算值体（类型头逐字节不动，含人工改动全部存活）：
jsonmbt import x.json --fill x.json.mbt
```

消歧能力：空容器直吃声明元素类型；键集漂移按声明 enum 选变体（`case` tag 或键集精确匹配双形态——**fill 能吃自身降级产物**）；数据与声明不同步 fail loud（无匹配变体 J3004 / 多余键 J3005 / 缺键 J3006）。`--fill` 与 `--type-name-map`/`--strict` 互斥（J0001）。

**教师循环形态保真（#26/#18）**：`#|` 手写真源 → build 降级 JSON → 改值 → `--fill` 回写——含 `\n` 的值产回 `#|` 多行（值位括号包裹、`#|` 随嵌套缩进的 fmt 不动点形态），未改条目形态照旧——写作面不再单向磨损；教师循环 = build ⇄ fill 的双向桥稳态用法。

## 机器写回（emitter）纪律

1. **程序生成别走 import**——import 是人的迁移工具；直接产 .mbt 文本 + `jsonmbt build` 验证；
2. **Map 键序由 .mbt 文本序决定**：从 Go map range 直接输出会翻车（遍历序随机）——必须原文顺序抽取或显式排序，否则确定性破功；
3. **round-trip 是链路语义闸，必跑——但「round-trip 绿 ≠ 数据语义正确」**：它防的是**链路引入的漂移**（emitter 装错变体、编解码不对称、归一化丢信息——build 再生对拍即红）；**不防**：①手写源头错（靠 freeze diff 人审）②值超域（99999 稳定往返 99999，绿——需消费侧 guard 或值域校验）。另一个第二用途：emitter 形态版本升级时，round-trip 可证「纯形态重构、语义零变化」；
4. **含 `\n` 的长文案产 `#|` 多行**（#26 起，#18 后为 fmt 不动点形态）：值位括号包裹、`#|` 行**随嵌套缩进**（字段位 +2）、`#|` 后无前导空格（空格入值——moon 语义）；单行值保持转义形态、含 `\r` 的值走转义单行；
5. **fmt 不动点**（#18 重写，2026-10-10）：`jsonmbt import` 产物**即 moon fmt 不动点**（宽度驱动渲染：整行 ≤84 record 单行尾逗号形/数组 ≤80/标量填满式/`Some(` 折/`#|` 随嵌套缩进/`///|` 补齐）——接 moon 门禁**无需再 fmt**；`--fmt` 旗标保留但为 **no-op**（既有脚本零破坏，输出 hint）。层 2 金门 `fmt-fixed-point` 常驻断言零 diff——**moon 工具链升级若漂移 fmt 形态，金门即红**（漂移显性化：此时勿手 fmt 掩盖，应报上游跟进渲染器）。**程序 emitter（自己产 .mbt 的下游）**：对齐 jsonmbt 形态最稳；要跑 fmt 用 `cd <目标项目> && moon fmt`——`moon fmt <path>` 把 path 当包过滤 pattern，项目外路径**静默跳过且 rc=0**（陷阱 #45）；fmt 形态与手写并存时以 moon fmt 为准归一。

## Agent 协作纪律（下游仓收录时抄这段）

- **只改 .json.mbt 真相源**；再生的 .json 通常已 `.gitignore` 遮蔽或属读侧产物——改错侧 = 白改；
- 修改流程：改 `.mbt` → `jsonmbt check`（或 `moon check`）→ `jsonmbt build` 再生 → 提交两者（若 .json 入仓）；
- 看到文件头 `// @generated ... 禁手改（再生成：...）`：这是机器写回面——**不要手改**，跑头部标注的再生命令；
- 改坏不慌：所有错误是编译期行列级（J 码 + help 指路），按 help 修即可；数据错误不会静默落盘（build 失败零产物）。

## 常见 J 码速查

| 码 | 含义 | 处置 |
|---|---|---|
| J2003 | 绑定名 ≠ 文件 stem | 改绑定名或文件名 |
| J2007 | 字段类型超出 L0（`Option[T]` 前缀 / 嵌套 `T??`） | 可空一律写后缀糖 `T?`；三态编码在 §8 评审 |
| J3003 | 字符串转义畸形（含孤立代理） | 转义集 = moon 词法宽集（见规则 1b）；孤立代理补低位 |
| J3004 | 字段类型不配 | 按 expects/got 修字面量（enum 变体拼错、fill 无匹配变体也在此） |
| J3005/J3006 | 未知字段 / 缺必填字段（fill 的数据不同步也在此） | 对齐类型头与数据 |
| J3008 | tag 键与 payload 字段撞车 | payload 字段改名（只防 `case`；`value` 是登记的已知面） |
| J3009 | field-alias 注记畸形/语义错 | 按行文法修：`// jsonmbt: field-alias S.label = "json键"` |
| J1010 | --type-name-map 值非法/撞已占类型 | 值改合法且未占的大写开头类型名 |
| J4001/J4002 | 空容器无线索（**仅 --strict 档**） | 默认已 Never 占位；strict 下给样本或手工声明真类型 |
| J4003 | 全 null 列类型未知 | 给非 null 样本或手工 `T?` |
| J4010/J4011 | import 遇缺键异构（按容器路径分组报告） | 看字段集差异与分布（下界），手工建模 enum 或 `--fill` |
| J4020 | 整数超 Int64 | 改 String 字段承载 |
| J4030/J4031 | hint 级（rc 0）：tagged-enum 识别 / Never 占位提示 | 非错误——按提示优化建模 |

**语法参考全貌**：`src/manual.mbt.md`（可执行手册——「语法参考：与 MoonBit 的对应」大章：文件骨架 / 类型头全集 / 值体全集 / 转义契约 / 数字契约 / 键名两通道 / 空容器占位 / 禁止面；「值域枚举与多行文本」大章：enum 值域 / `#|` 前导空格语义 / 键域强校验带参枚举数组；代码块即 `mbt check` fence 锚，`moon test` 逐块执行）。
