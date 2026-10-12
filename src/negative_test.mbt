// J 系负样本锚（每码至少一条；红→绿纪律的绿面固化）
// 锚的期望文本 = 诊断 render 的机器可读前缀形态（D-10 契约）
// 行列值以 parser 实测为准锚死——工具链升级若动位置，此锚即红（R1 对冲）

///|
fn expect_diag(
  src : String,
  expected : String,
  path? : String = "t.json.mbt",
) -> Unit {
  let d = try {
    let _ = @src.build_source(src, path~, expected_name="t")
    // 走到这里说明本应失败——inspect 用占位串保证红
    "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("unexpected error type") }
  }
  if d != expected {
    println("MISMATCH\nexpected: \{expected}\nactual:   \{d}")
    abort("diagnostic mismatch")
  }
}

///|
test "J1001 : 语法错转发 parser 报告" {
  let src = "pub let t = {"
  expect_diag(
    src, "jsonmbt: error [J1001] t.json.mbt:1:14 Unexpected end of file, missing simple expression here.\n  help: keep the file valid MoonBit: struct defs + one top-level pub let of literals",
  )
}

///|
test "J2001 : 缺顶层 pub let" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
  expect_diag(
    src, "jsonmbt: error [J2001] t.json.mbt:1:1 no top-level pub let binding\n  help: add `pub let <file-stem> = ...` — the file degrades to one JSON document",
  )
}

///|
test "J2002 : 多个顶层 pub let" {
  let src =
    #|pub let t = 1
    #|pub let u = 2
  expect_diag(
    src, "jsonmbt: error [J2002] t.json.mbt:2:1 multiple top-level pub let bindings\n  help: one .json.mbt file degrades to exactly one JSON document (D-7)",
  )
}

///|
test "J2003 : stem 不符（stdin 免检由 CLI 面覆盖）" {
  let src = "pub let other = 1"
  expect_diag(
    src, "jsonmbt: error [J2003] t.json.mbt:1:1 top-level binding is 'other' but the file stem is 't'\n  help: rename the binding (or the file) so they match — this keeps one name per document",
  )
}

///|
test "J2004 : 嵌套深度超预算" {
  // 129 层嵌套数组（预算 128）
  let mut src = "pub let t = "
  let mut tail = ""
  for i = 0; i < 129; i = i + 1 {
    src = src + "["
    tail = tail + "]"
  }
  src = src + "1" + tail
  expect_diag(
    src, "jsonmbt: error [J2004] t.json.mbt:1:142 nesting exceeds the depth budget of 128\n  help: flatten the data or split it into several .json.mbt files",
  )
}

///|
test "J2005 : 顶层非 struct/pub let 声明" {
  let src =
    #|fn f() -> Int {
    #|  1
    #|}
    #|
    #|pub let t = 1
  expect_diag(
    src, "jsonmbt: error [J2005] t.json.mbt:1:1 top-level fn declaration\n  help: a .json.mbt file contains struct definitions and one pub let — nothing else",
  )
}

///|
test "J2006 : 重复 struct 定义" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|struct T {
    #|  b : Int
    #|}
    #|
    #|pub let t : T = T::{ a: 1 }
  expect_diag(
    src, "jsonmbt: error [J2006] t.json.mbt:5:1 duplicate struct definition 'T'\n  help: rename one of the structs; .json.mbt keeps one schema per name",
  )
}

///|
test "J2007 : 字段类型超出 L0 支持面" {
  let src =
    #|struct T {
    #|  a : (Int, Int)
    #|}
    #|
    #|pub let t : T = T::{ a: (1, 2) }
  expect_diag(
    src, "jsonmbt: error [J2007] t.json.mbt:2:3 field type is outside the L0 subset\n  help: supported field types: Int/Int64/Double/String/Bool/T? (Option)/Array[T]/Map[String,T]/struct",
  )
}

///|
test "J3002 : Map 键非字符串" {
  let src = "pub let t = { 1: \"a\" }"
  expect_diag(
    src, "jsonmbt: error [J3002] t.json.mbt:1:15 map key must be a string literal, got Int\n  help: JSON object keys are strings; quote the key",
  )
}

///|
test "J3003 : Char 字面量无 JSON 对应" {
  let src = "pub let t = 'x'"
  expect_diag(
    src, "jsonmbt: error [J3003] t.json.mbt:1:13 Char literal has no JSON counterpart\n  help: JSON values are null/bool/number/string/array/object only",
  )
}

///|
test "J3004 : 字段类型不匹配（PLAN §4 的原型例）" {
  let src =
    #|struct T {
    #|  port : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  port: "443",
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:9 expects Int32, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}

///|
test "J3004 : Int 界外上浮提示（D-2）" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 3000000000,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:6 expects Int (32-bit), got 3000000000\n  help: change the field type to Int64, or use a value within ±2147483647",
  )
}

///|
test "J3004 : 超 Int64 诚实拒绝（D-2）" {
  let src =
    #|struct T {
    #|  a : Int64
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 99999999999999999999,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:6 expects Int64, got 99999999999999999999\n  help: the value exceeds Int64; keep exact digits by storing a String explicitly",
  )
}

///|
test "J3005 : 未知字段" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 1,
    #|  b: 2,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3005] t.json.mbt:7:3 unknown field 'b'\n  help: struct 'T' has fields: a",
  )
}

///|
test "J3006 : 缺必填字段" {
  let src =
    #|struct T {
    #|  a : Int
    #|  b : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 1,
    #|}
  expect_diag(
    src, "jsonmbt: error [J3006] t.json.mbt:6:17 missing field 'b' in 'T'\n  help: provide the field explicitly; T? (Option) fields use None",
  )
}

///|
test "J3007 : Map 重复键拒绝（D-11：JSON 层重复键是病态输入）" {
  let src = "pub let t = { \"k\": 1, \"k\": 2 }"
  expect_diag(
    src, "jsonmbt: error [J3007] t.json.mbt:1:23 duplicate key \"k\"\n  help: merge the two entries; a degraded object never carries duplicate keys",
  )
}

///|
test "J1002 : JSON 输入语法错（normalize_json_text）" {
  let d = try {
    let _ = @src.normalize_json_text("{,}")
    "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("unexpected error type") }
  }
  let ok = d != "BUILD-SUCCEEDED-BUT-DIAGNOSTIC-EXPECTED" && d.contains("J1002")
  inspect(ok, content="true")
}

///|
test "P2-6② : Some(v) 内层期望类型校验判别（Int? 字段给 Some(\"x\")）" {
  let src =
    #|struct T {
    #|  opt : Int?
    #|}
    #|
    #|pub let t : T = T::{
    #|  opt: Some("x"),
    #|}
  expect_diag(
    src, "jsonmbt: error [J3004] t.json.mbt:6:13 expects Int32, got String literal\n  help: change the field type to String, or remove the quotes",
  )
}

///|
test "J2007 : 嵌套 Option（T??）收窄——静默压平是无损红线违例（#14-1 批次1）" {
  // 现状实测：String?? 下 None 与 Some(None) 都降级 "a":null——信息静默
  // 压平（§0 解压无损 + D-8② 违例）。三态定义（缺席/null/值）走 §8 正式
  // 评审；在此之前嵌套 Option 一律 J2007 fail loud（递归拒任意深度——
  // 推断链只加一层 Option，此面纯手写，现存绿文件零影响）
  // 形态①：直接 T??
  expect_diag(
    "struct S {\n  a : String??\n}\npub let t : S = S::{ a: None }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
  // 形态②：容器位嵌套（Array 元素类型——JSON 容器位结构上无法缺席，
  // 三态评审落地前一并收窄）
  expect_diag(
    "struct S {\n  b : Array[Int??]\n}\npub let t : S = S::{ b: [] }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
  // 形态③：三层（递归口径一次说清）
  expect_diag(
    "struct S {\n  c : Int???\n}\npub let t : S = S::{ c: None }\n", "jsonmbt: error [J2007] t.json.mbt:2:3 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
}

///|
test "unescape : MoonBit 词法宽集对齐——斜杠转义与 uXXXX 定长（#16）" {
  // moon 实测接受 \/ 与 \uXXXX（moon check rc=0，2026-10-09 探针）——
  // 「.json.mbt = 合法 MoonBit 源文件」承诺要求 jsonmbt 接受 moon 接受的一切
  // （#16 主表的 \t \n \" \ \b \f \r 七项在最新 exe 已工作——本锚
  // 补真缺口三项 + 全族回归）
  let good =
    #|struct T { s : String }
    #|pub let t : T = T::{ s: "a\/b 中\u4e2d \ud83d\ude80 \t\n\"\b\f\r\\" }
  inspect(
    @src.build_source(good, path="t.json.mbt", expected_name="t"),
    content="{\"s\":\"a/b 中中 🚀 \\t\\n\\\"\\b\\f\\r\\\\\"}",
  )
  // 孤立高代理（无低位跟随）→ 病态输入拒收
  let bad =
    #|struct T { s : String }
    #|pub let t : T = T::{ s: "\ud83d" }
  let d = try {
    let _ = @src.build_source(bad, path="t.json.mbt", expected_name="t")
    "SUCCEEDED"
  } catch {
    e => if e is @src.Diag(..) { e.render() } else { abort("non-Diag") }
  }
  inspect(d.contains("[J3003]"), content="true")
}

///|
test "数字降级规范化契约锚（#17 方案 C 成文）——Int 系解析值 / Double 源拼写" {
  let doc =
    #|struct N {
    #|  a : Int
    #|  b : Double
    #|  c : Int
    #|  d : Int64
    #|  e : Double
    #|}
    #|
    #|pub let n : N = N::{
    #|  a: -0,
    #|  b: 1.50,
    #|  c: 0x10,
    #|  d: 9223372036854775807,
    #|  e: 0.1,
    #|}
  // 契约（README 同文）：整数族走解析值归一（负零塌缩 / 进制归一）；
  // Double 保源拼写（避免解析-再格式化的精度伪影）；Int64 全精度文本保留
  inspect(
    @src.build_source(doc, path="n.json.mbt", expected_name="n"),
    content="{\"a\":0,\"b\":1.50,\"c\":16,\"d\":9223372036854775807,\"e\":0.1}",
  )
}

///|
test "#25 : 花括号块 payload 拒（Group::Brace——副作用序列非字面量）" {
  // 花括号块做 payload 是合法 MoonBit（moon check 过——块内 let + 尾
  // 表达式）但非纯字面量——圆括号剥除不扩到花括号块（#25 修复的边界锚）
  let src = "enum A { A(String) }\npub let t : Array[A] = [\n  A({\n    let s = \"a\"\n    s\n  }),\n]\n"
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "SUCCEEDED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("non-Diag") }
  }
  inspect(d.contains("braced block is outside the L0"), content="true")
}

///|
test "审 P1-b : 花括号转义代理区拒收（与定长 \\uXXXX 分支同款 J3003）" {
  // moon 本尊对 "\u{d800}" 报 [4064]（审阅实测）——jsonmbt 不比 moon 严；
  // 旧实现只查 >0x10FFFF 上限，代理点 unsafe_to_char 后降级链 panic
  //（check 放行 build 崩——绕过 D-8 ① 校验先行）。定长分支 #16 已有
  // 同款检查，花括号路径漏网（同族逐处对齐）
  let d = try {
    let _ = @src.build_source(
      "pub let v = \"\\u{d800}\"",
      path="v.json.mbt",
      expected_name="v",
    )
    "SUCCEEDED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("non-Diag") }
  }
  inspect(d.contains("[J3003]"), content="true")
  // 合法上限（0x10FFFF 非代理）照常收——降级为裸 UTF-8（非 ASCII 不转义）；
  // 码点断言：`"` + U+10FFFF(=1114111) + `"`（inspect 字面串在该字符上
  // 有显示同形字节异的差异噪音，码点级断言更硬）
  let ok = @src.build_source(
    "pub let v = \"\\u{10FFFF}\"",
    path="v.json.mbt",
    expected_name="v",
  )
  let cps = ok.to_array()
  inspect(cps.length() >= 3, content="true")
  inspect(cps[1].to_int(), content="1114111")
}

///|
test "J2007 : enum payload 位嵌套 Option 同拦（#32-10——曾绕过预检静默压平）" {
  expect_diag(
    "enum E {\n  A(Int??)\n}\npub let t : E = A(None)\n",
    "jsonmbt: error [J2007] t.json.mbt:4:1 nested Option (T??) is outside the L0 subset — degradation would silently flatten None and Some(None) into the same null\n  help: use T? for nullable; the three-state encoding (absent vs null vs value) is under review — model the distinction by hand until then",
  )
}

///|
test "J2006 : enum 与 struct 同名顺序无关（#32-11——enum 在前曾漏报）" {
  expect_diag(
    "enum T {\n  A\n}\nstruct T {\n  x : Int\n}\npub let t : T = T::{ x: 1 }\n",
    "jsonmbt: error [J2006] t.json.mbt:4:1 duplicate struct definition 'T'\n  help: rename one of the structs; .json.mbt keeps one schema per name",
  )
}

///|
test "#32-19 : 臂级负样本——J3003 UInt/UInt64 字面量（parser 收、L0 拒）" {
  expect_diag("pub let t = 1U", "jsonmbt: error [J3003] t.json.mbt:1:13 UInt literal has no JSON counterpart\n  help: JSON values are null/bool/number/string/array/object only")
  expect_diag("pub let t = 1UL", "jsonmbt: error [J3003] t.json.mbt:1:13 UInt64 literal has no JSON counterpart\n  help: JSON values are null/bool/number/string/array/object only")
}

///|
test "#32-19 : 兜底臂与重复字段臂——Tuple 走 J3001 白名单外、record 重复字段 J3007" {
  // Tuple 自由值直达 `_` 兜底臂（头注释「不设 null 兜底」教训的锚定）
  expect_diag("pub let t = (1, 2)", "jsonmbt: error [J3001] t.json.mbt:1:13 this expression is outside the L0 pure-literal subset\n  help: use a literal value (record, array, map, or scalar); for anything computed, write real MoonBit instead")
  expect_diag(
    "struct T {\n  a : Int\n}\npub let t : T = T::{ a: 1, a: 2 }\n",
    "jsonmbt: error [J3007] t.json.mbt:4:28 duplicate field 'a'\n  help: merge the two values into one; a degraded object never carries duplicate keys",
  )
}

///|
test "#32-19 : enum 与 enum 同名（Variant 臂双向查重的对侧锚）" {
  expect_diag(
    "enum T {\n  A\n}\nenum T {\n  B\n}\npub let t = T::A\n",
    "jsonmbt: error [J2006] t.json.mbt:4:1 duplicate type definition 'T'\n  help: rename one of the types; .json.mbt keeps one schema per name",
  )
}
