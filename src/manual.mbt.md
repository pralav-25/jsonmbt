# jsonmbt 使用手册（可执行文档）

> `.json.mbt` 是 JSON 的类型化源码形态：以 MoonBit 子集表达的 JSON 数据，
> `moon check` 即 schema 验证、`moon fmt` 即格式统一，经 jsonmbt 引擎
> **降级输出干净、安全、确定性的 `.json`**。
>
> 本文档的代码块是 `mbt check` fence——`moon test` 会逐块执行（文档即锚，
> 示例永不腐烂）。API 面来自本包 `pkg.generated.mbti`。

## 降级：`.json.mbt` → `.json`

`build_source` 接受源文本，产出**紧凑、键序 = 源序**的 JSON（类型名剥除、
字面量直译；数值保留源文本形态）：

```mbt check
///|
test "manual : build 基础形态" {
  let src =
    #|struct Server {
    #|  port : Int
    #|  host : String
    #|  tags : Array[String]
    #|}
    #|
    #|pub let server : Server = Server::{
    #|  port: 8080,
    #|  host: "localhost",
    #|  tags: ["a", "b"],
    #|}
  let json = @src.build_source(
    src,
    path="server.json.mbt",
    expected_name="server",
  )
  inspect(
    json,
    content="{\"port\":8080,\"host\":\"localhost\",\"tags\":[\"a\",\"b\"]}",
  )
}
```

CLI 形态：`jsonmbt build server.json.mbt` → 同目录 `server.json`；
`jsonmbt build -` 从 stdin 读、产物写 stdout。

## 摄取：JSON/JSONC → `.json.mbt`

**输入 profile（D-9 重写，#22 2026-10-10）**：默认 **jsonc 档**——注释
（`//`、`/* */`）、尾逗号（对象/数组/嵌套）、文件首 BOM 在 `strip_jsonc`
归一化器里**等长空格消解**（诊断行列不漂移；`jsonparse` 恒裸 RFC 8259）；
`--input json` = 裸 RFC 8259（这些特性全拒）。**不收**：`{,}`/`[,]`/
`[1,,]`/`{"a":,}`（开头/孤立/值缺失逗号）、单引号串、无引号 key、hex、
`NaN`/`Infinity`——判据：只收「字符层删/替空白可消解为严格 JSON」的
特性，不收任何 token 层重写（扩值域）。注意与 `.json.mbt` 语法侧的
「尾逗号天然合法」是两件事：那是 MoonBit 语法，这是输入侧宽松度。

```mbt check
///|
test "manual : JSONC 尾逗号消解（值等价）" {
  let with_tc = @src.import_source(
    "{\"a\":1, \"b\":[1,2,], // note\n}",
    path="t.json",
    stem="t",
  )
  let without = @src.import_source(
    "{\"a\":1, \"b\":[1,2]}",
    path="t.json",
    stem="t",
  )
  inspect(with_tc.content, content=without.content)
}
```

`import_source` 做形状推断（形状签名判重 / D-1 空容器两级启发 /
D-2 大数上浮 / 键名逃生门），生成带 `@generated` 头的合法 `.json.mbt`：

```mbt check
///|
test "manual : import 推断（单样本 null 诚实拒绝）" {
  let ok = try {
    let _ = @src.import_source(
      "{\"port\": 8080, \"retries\": null}",
      path="config.json",
      stem="config",
    )
    "succeeded"
  } catch {
    e => if e is @src.Diag(..) { "rejected" } else { abort("non-Diag") }
  }
  // null 字段需非 null 样本聚 Option 基型——单样本无线索（J4003）
  inspect(ok, content="rejected")
}
```

```mbt check
///|
test "manual : import 生成形态（多样本 null → Option + 键名逃生门）" {
  let outcome = @src.import_source(
    "{\"items\": [{\"v\": null}, {\"v\": 7}], \"meta\": {\"x-tag\": \"v\"}}",
    path="config.json",
    stem="config",
  )
  inspect(outcome.content.contains("v : Int32?"), content="true") // 组内聚合 → Option[Int32]
  inspect(outcome.content.contains("pub struct Config"), content="true")
  // 连字符键（x-tag）所在对象走 Map 逃生门——同值类型整体 Map[String, V]
  inspect(
    outcome.content.contains("meta : Map[String, String]"),
    content="true",
  )
}
```

CLI 形态：`jsonmbt import config.json` → `config.json.mbt`；
`jsonmbt import config.json --check` 是幂等闸——磁盘产物与重算结果
**行尾归一后比对**，漂移即 rc 2（D-10 的有义分叉）。

## 校验：check = build 的 dry-run

`check_source` 与 build 走**同一条校验路径**（两套校验语义必漂移——D-8），
无任何写副作用。所有诊断走 stderr 机器可读前缀：

```mbt check
///|
test "manual : 诊断的机器可读形态" {
  let src =
    #|struct T {
    #|  port : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  port: "443",
    #|}
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "no-error"
  } catch {
    e => e.render()
  }
  inspect(
    d,
    content="jsonmbt: error [J3004] t.json.mbt:6:9 expects Int32, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}
```

## 往返等价：规范化器 N

D-11 的往返锚语义：`N(build(import(J))) == N(J)`——N 做**值语义**规范化
（RFC 8259 数字是抽象数值：1 ≡ 1.0；键序不敏感；超范围大数按源文本保真）。
「1 ≠ 1.0 保留」属**降级输出侧**（源文本直传），两个维度分立：

```mbt check
///|
test "manual : N 值语义等价" {
  let a = @src.normalize_json_text("{\"v\": 1}")
  let b = @src.normalize_json_text("{\"v\": 1.0}")
  inspect(a, content=b) // N 层：1 ≡ 1.0
}

///|
test "manual : build 层文本保真" {
  let s1 = @src.build_source(
    "pub let t = 1",
    path="t.json.mbt",
    expected_name="t",
  )
  let s2 = @src.build_source(
    "pub let t = 1.0",
    path="t.json.mbt",
    expected_name="t",
  )
  inspect(s1 == s2, content="false") // build 层：源文本直传
}
```

## 语法参考：`.json.mbt` 与 MoonBit 的对应

一句话：**`.json.mbt` = MoonBit 的「数据切片」**——文件里只允许「类型定义
+ 一个顶层绑定」，值体只允许纯字面量。moon 把它当合法源文件（check/fmt/
IDE 全家桶直接能用），jsonmbt 在其上追加「确定性降级为 JSON」的契约。
**接受原则：moon 词法接受的一切字符串/字面量形态，jsonmbt 必须接受**
（[#16](https://github.com/rustin-beep/jsonmbt/issues/16) 确立）。

### 文件骨架（D-7 单文档）

`struct`/`enum` 定义（任意个，可带注释）+ **恰好一个**
`pub let <stem> [: T] = <字面量>`——绑定名必须等于文件名 stem（`cfg.json.mbt`
→ `pub let cfg`，J2003 指路）：

```mbt check
///|
test "manual : 文件骨架与 stem 同名" {
  let src =
    #|// 任意注释存活
    #|struct Rule {
    #|  id : String
    #|}
    #|
    #|pub let rule : Rule = Rule::{ id: "r1" }
  inspect(
    @src.build_source(src, path="rule.json.mbt", expected_name="rule"),
    content="{\"id\":\"r1\"}",
  )
}
```

### 类型头全集（与 JSON 的对应）

| 类型写法 | JSON 对应 | 备注 |
|---|---|---|
| `Int32`（别名 `Int` 同型合法）/ `Int64` / `Double` / `String` / `Bool` | number/number/number/string/boolean | `Int32` 32 位（2³¹−1 实测界）；规范拼写 `Int32` 跟随 moon fmt 归一（#34/D-13——手写 `Int` 照常收，存量零破坏）；Int64 全精度文本保留 |
| `T?`（**后缀糖**） | `null` ↔ 值 | **`Option[T]` 前缀形态 J2007 拒**；嵌套 `T??` 同拒（三态编码在 §8 评审） |
| `Array[T]` | array | 同构元素 |
| `Map[String, V]` | object（键序 = 书写序） | 键名逃生门（见下） |
| 自定义 `struct` | object（键 = 字段名） | 类型即 schema |
| `enum`（D-5/D-12） | 变体名字符串 / tag 对象 | 无参变体 = 字符串；带参 = payload 展开 + `"case"` 键 |

### 值体全集（L0 纯字面量——求值分级冻结）

record `S::{ ... }`、数组 `[...]`、map 字面量 `{ "键": 值 }`、`Some(v)` /
`None`、enum 构造器（`Unit` / `Named(Payload)`）、字符串（含 `#|` 多行）、
数字字面量。**任何计算（`1 + 2`）、标识符引用、跨文件引用 = J3001
fail loud**（「所见即所得」是降级确定性的前提）。值位冗余**圆括号**
（`A(("x"))`——moon fmt 规范产物形态）剥除后照常收（值语义零变化，
花括号块仍拒）——「合法 MoonBit 子集」在括号上不比 moon 严（#25）。

### 字符串转义（契约，#16）

- 接受面 = **moon 词法宽集**：`\' \" \\ \/ \n \r \t \b \f \0 \xHH
  \u{...}` 与 `\uXXXX` 定长（含 `\uD8xx\uDCxx` 代理对合成——moon 实测
  全接受，孤立代理拒）；
- 输出面 = 最小转义集（控制符/引号/反斜杠）+ 非 ASCII 裸 UTF-8
  （`"\u4e2d"` 与裸 `中` 产同一输出——同值异形归一为规范形）。

```mbt check
///|
test "manual : 转义宽集（moon 接受 ⇒ jsonmbt 接受）" {
  let src =
    #|struct T { s : String }
    #|pub let t : T = T::{ s: "a\/b 中\u4e2d \ud83d\ude80" }
  inspect(
    @src.build_source(src, path="t.json.mbt", expected_name="t"),
    content="{\"s\":\"a/b 中中 🚀\"}",
  )
}
```

### 数字（契约，#17）

整数族（`Int`/`Int64`）走**解析值归一**（`-0` → `0`、`0x10` → `16`——
JSON 只有十进制）；`Double` 保**源拼写透传**（`1.50` 原样输出，不归一为
`1.5`——避免解析-再格式化的精度伪影）。

### 键名两通道（#13）

- **保留字键**（`where`/`type`… 加 `_` 即合法）：import 自动改名
  （`where_`）+ 文件头注记 `// jsonmbt: field-alias S.label = "原键"`
  还原（手写文件也可用——注记行文法/指向错误 = J3009）；
- **不可改名键**（`a.b` 带点、大写开头）：该对象整体走
  `Map[String, V]` 逃生门（同值类型才能统一）。

### 空容器占位（#14-2a）

推断无线索的空数组/空对象 → `Array[<Stem>Never]` / `Map[String, <Stem>Never]`
（产物自带 `pub enum <Stem>Never {}` 零构造器定义——**免费护栏**：元素位写值
在 moon 编译期 `[4014]` 红）；`--strict` 恢复旧拒绝行为（J4001/J4002）。
**#36：底型名逐文件唯一**（`empty_containers.json` → `Empty_containersNever`）——
同目录多文件各发一份底型定义不再重复声明（moon `[4051]`），文件仍自持
（不依赖 sibling 是否先 import）。

## L0 类型面（速查版）

字段类型全集：`Int`（32 位，真实编译界 2³¹−1）/ `Int64` / `Double` /
`String` / `Bool` / `T?`（后缀糖——**`Option[T]` 前缀形态 J2007 拒**，
嵌套 `T??` 同拒）/ `Array[T]` / `Map[String, V]`（键名逃生门）/ 自定义
`struct` / `enum`（D-5/D-12 转正）。求值分级 L0（纯字面量）冻结——
任何计算（`1 + 2`、引用、条件）都是 J3001 fail loud：

```mbt check
///|
test "manual : L0 白名单 fail loud" {
  let src =
    #|pub let t = { "a": 1 + 2 }
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "no-error"
  } catch {
    e => e.render()
  }
  inspect(d.contains("[J3001]"), content="true")
}
```

## J 系错误码速查

| 码段 | 语义 |
|---|---|
| J000x | 用法 / IO（rc 4） |
| J100x | 语法：.json.mbt（J1001）/ JSON 输入（J1002）/ 重复键（J1003） |
| J200x | 文档基数（D-7）与类型头：缺/多 pub let、stem 不符、深度、顶层声明、类型面外 |
| J300x | 值面：非 L0、Map 键、无对应字面量、类型不匹配、未知/缺失/重复字段 |
| J400x | importer 阻断：D-1 家族（空容器/全 null）、异构、超 Int64（D-2 诚实拒绝） |
| J4030 | tagged-enum 识别提示（hint 级，rc 0） |
| J4031 | 空容器 Never 占位提示（hint 级，rc 0，#14-2a） |
| J1010 | type-name-map 语义错（#6-4）；J3009 field-alias 注记错（#13） |
| J500x | 漂移/差异（rc 2——`--check` 幂等闸首例） |

rc 五值表（D-10）：`0` 成功 / `1` 输入错 / `2` 检测到漂移或差异 /
`3` 保留 / `4` 用法·IO 错。

## 值域枚举与多行文本（§8 裁定 2026-10-07）

有限词表字段用 `enum` 表达——**拼错变体在 `jsonmbt check` 即红**（写时校验，
防线补位 moon `[4031]`）；降级投影 = 变体名字符串：

```mbt check
///|
test "manual : enum 值域（写时红）" {
  let src =
    #|enum Status {
    #|  VerifiedRun
    #|  Open
    #|}
    #|struct Ledger {
    #|  status : Status
    #|}
    #|
    #|pub let ledger : Ledger = Ledger::{
    #|  status: VerifiedRun,
    #|}
  inspect(
    @src.build_source(src, path="l.json.mbt", expected_name="ledger"),
    content="{\"status\":\"VerifiedRun\"}",
  )
}
```

```mbt check
///|
test "manual : 拼错变体即红" {
  let d = try {
    let _ = @src.build_source(
      "enum S { A }\nstruct T { s : S }\npub let t : T = T::{ s: B }",
      path="t.json.mbt",
      expected_name="t",
    )
    "ok"
  } catch {
    e => if e is @src.Diag(..) { e.render() } else { "non-diag" }
  }
  inspect(d.contains("has no variant 'B'"), content="true")
}
```

长文本用 `#|` 多行字符串（每行净内容以 `\n` 连接降级）：

```mbt check
///|
test "manual : #| 多行文本" {
  let out = @src.build_source(
    "pub let m = #|第一行\n#|第二行",
    path="m.json.mbt",
    expected_name="m",
  )
  inspect(out, content="\"第一行\\n第二行\"")
}
```

**边界（2026-10-08 D-5 转正后勘误）**：带单参构造器（`Named(Payload)`）
**已支持**——降级投影 = tag 对象展开（payload 字段进顶层 + `"case"` 键；
标量 payload 加 `"value"` 键）；**payload 字段禁止叫 `case`**（J3008；
`value` 与标量形态同键是登记的已知面——可由 case 值区分）。裸构造器无
类型上下文时语义不明，保守拒绝（J3001）。

**`#|` 前导空格入值**（issue #24，2026-10-10）：`#| x` 的首空格属于
值的一部分（moon 原生语义，非 jsonmbt 偏差）——排版习惯写的「`#| 内容`」
降级后每行都带前导空格。要空格分隔观感又不进值，`#|` 后直接写内容：

```mbt check
///|
test "manual : #| 前导空格入值" {
  let out = @src.build_source(
    "pub let m = #| 冒泡",
    path="m.json.mbt",
    expected_name="m",
  )
  inspect(out, content="\" 冒泡\"")
}
```

**键域强校验 → 带参枚举数组**（issue #24）：想让「键拼错写时红」的
有限键集（枚举域），**不要**用 `Map[AlgoE, String]`——Map 字面量键位
不接受裸构造器，moon 本尊即 `[4014]` Constr Type Mismatch（语言层边界
非 jsonmbt 限制，本仓探针复核 2026-10-10）。正解 = 带参枚举数组：拼错
变体名 `moon check` 写时红，降级 `[{"case","value"}]`，下游按 `case`
值机械投影键名（Vitro 教学资产批 43 算法名实录）：

```mbt check
///|
test "manual : 键域强校验——带参枚举数组" {
  let src =
    #|enum AlgoSuggestion {
    #|  BubbleSort(String)
    #|  QuickSort(String)
    #|}
    #|pub let suggestions : Array[AlgoSuggestion] = [
    #|  BubbleSort("相邻交换，逐步冒泡"),
    #|  QuickSort("分治分区，递归排序"),
    #|]
  inspect(
    @src.build_source(
      src,
      path="s.json.mbt",
      expected_name="suggestions",
    ),
    content="[{\"case\":\"BubbleSort\",\"value\":\"相邻交换，逐步冒泡\"},{\"case\":\"QuickSort\",\"value\":\"分治分区，递归排序\"}]",
  )
}
```

