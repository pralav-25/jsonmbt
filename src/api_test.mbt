// 内层语义锚（防线内层——moon test；探针结论的固化面）
// 样本三层锚（AGENTS 环境注意）：JSON 期望 ↔ .json.mbt 源 ↔ 降级产物

///|
test "smoke : 全类型正样本端到端" {
  let src =
    #|struct Server {
    #|  port : Int
    #|  host : String
    #|  ratio : Double
    #|  big : Int64
    #|  tags : Array[String]
    #|  meta : Map[String, String]
    #|  backup : Bool
    #|  retries : Int?
    #|}
    #|
    #|pub let server : Server = Server::{
    #|  port: 8080,
    #|  host: "a\"b\\c\n\u{e9}",
    #|  ratio: 1.5e3,
    #|  big: 9223372036854775807,
    #|  tags: ["x", "y"],
    #|  meta: { "Content-Type": "text/plain" },
    #|  backup: true,
    #|  retries: None,
    #|}
  let out = @src.build_source(
    src,
    path="server.json.mbt",
    expected_name="server",
  )
  inspect(
    out,
    content="{\"port\":8080,\"host\":\"a\\\"b\\\\c\\né\",\"ratio\":1.5e3,\"big\":9223372036854775807,\"tags\":[\"x\",\"y\"],\"meta\":{\"Content-Type\":\"text/plain\"},\"backup\":true,\"retries\":null}",
  )
}

///|
test "smoke : Some 展开 + 嵌套 struct + 裸 object literal" {
  let src =
    #|struct Inner {
    #|  x : Int
    #|}
    #|struct Outer {
    #|  inner : Inner
    #|  d : Double
    #|  opt : Int?
    #|}
    #|
    #|pub let o : Outer = Outer::{
    #|  inner: { x: 1 },
    #|  d: 1,
    #|  opt: Some(443),
    #|}
  let out = @src.build_source(src, path="o.json.mbt", expected_name="o")
  inspect(out, content="{\"inner\":{\"x\":1},\"d\":1,\"opt\":443}")
}

///|
test "smoke : 负样本 fail loud（J3001 函数调用不兜底 null）" {
  let src =
    #|struct T {
    #|  a : Int
    #|}
    #|
    #|pub let t : T = T::{
    #|  a: 1 + 2,
    #|}
  let d = try {
    let _ = @src.build_source(src, path="t.json.mbt", expected_name="t")
    "no-error"
  } catch {
    e => e.render()
  }
  inspect(
    d,
    content="jsonmbt: error [J3001] t.json.mbt:6:6 arithmetic expression is outside the L0 pure-literal subset\n  help: use a literal value (record, array, map, or scalar); for anything computed, write real MoonBit instead",
  )
}

///|
test "正样本 : 顶层自由值（标量/数组/Map，无 struct 头）" {
  inspect(
    @src.build_source("pub let t = 42", path="t.json.mbt", expected_name="t"),
    content="42",
  )
  inspect(
    @src.build_source(
      "pub let t = [1, \"a\", true, None]",
      path="t.json.mbt",
      expected_name="t",
    ),
    content="[1,\"a\",true,null]",
  )
  inspect(
    @src.build_source(
      "pub let t = { \"x\": [1.5, -2], \"y\": {} }",
      path="t.json.mbt",
      expected_name="t",
    ),
    content="{\"x\":[1.5,-2],\"y\":{}}",
  )
}

///|
test "正样本 : 空容器/空串/None/Some 嵌套" {
  let src =
    #|pub let t = {
    #|  "empty_arr": [],
    #|  "empty_obj": {},
    #|  "empty_str": "",
    #|  "none": None,
    #|  "some_arr": Some([1]),
    #|}
  inspect(
    @src.build_source(src, path="t.json.mbt"),
    content="{\"empty_arr\":[],\"empty_obj\":{},\"empty_str\":\"\",\"none\":null,\"some_arr\":[1]}",
  )
}

///|
test "正样本 : 数值形态面（负数/下划线/十六进制/Int64 后缀/指数带小数点）" {
  let src =
    #|pub let t = {
    #|  "neg": -1,
    #|  "sep": 1_000,
    #|  "hex": 0x1F,
    #|  "i64": 123L,
    #|  "big_i64": 9223372036854775807,
    #|  "exp": 1.5e3,
    #|  "dint": 100.0,
    #|  "neg_zero": -0,
    #|}
  inspect(
    @src.build_source(src, path="t.json.mbt"),
    content="{\"neg\":-1,\"sep\":1000,\"hex\":31,\"i64\":123,\"big_i64\":9223372036854775807,\"exp\":1.5e3,\"dint\":100.0,\"neg_zero\":0}",
  )
}

///|
test "正样本 : 控制字符全族转义（D-11 ③，U+00XX 形态）" {
  // 源文本须含字面转义序列（\\u{1} 经 MoonBit 字符串转义后是 \ + u{1}）
  let src = "pub let t = \"a\\u{1}b\\u{1f}c\\td\\ne\""
  inspect(
    @src.build_source(src, path="t.json.mbt"),
    content="\"a\\u0001b\\u001fc\\td\\ne\"",
  )
}

///|
test "正样本 : 中文键（label/Map 位合法；struct 类型名须大写开头——中文只进键位）" {
  let src =
    #|struct Config {
    #|  端口 : Int
    #|  表头 : Map[String, String]
    #|}
    #|
    #|pub let t : Config = Config::{
    #|  端口: 80,
    #|  表头: { "内容类型": "文本" },
    #|}
  inspect(
    @src.build_source(src, path="t.json.mbt", expected_name="t"),
    content="{\"端口\":80,\"表头\":{\"内容类型\":\"文本\"}}",
  )
}

///|
test "正样本 : 深度 127 在预算内通过（J2004 边界内邻）" {
  let mut src = "pub let t = "
  let mut tail = ""
  for i = 0; i < 127; i = i + 1 {
    src = src + "["
    tail = tail + "]"
  }
  src = src + "1" + tail
  let out = @src.build_source(src, path="t.json.mbt", expected_name="t")
  inspect(out.length() == 127 * 2 + 1, content="true")
}

///|
test "D-11 等价锚 : N(build(x)) == N(J)（值语义等价）" {
  // 三对：全类型 / Map+Option / 指数展开（1.5e3 ≡ 1500.0 双 Double 相等）
  let pairs : Array[(String, String)] = [
    (
      "pub let t = { \"a\": 1, \"b\": \"x\", \"c\": [1, 2], \"d\": None }", "{\"a\":1,\"b\":\"x\",\"c\":[1,2],\"d\":null}",
    ),
    (
      "struct S {\n  o : Int?\n  m : Map[String, Int]\n}\npub let t : S = S::{ o: Some(3), m: { \"k\": 9 } }",
      "{\"o\":3,\"m\":{\"k\":9}}",
    ),
    (
      "pub let t = { \"x\": 1.5e3, \"y\": 1500.0 }", "{\"x\":1500.0,\"y\":1500.0}",
    ),
  ]
  for pair in pairs {
    let (src, json) = pair
    let built = @src.build_source(src, path="t.json.mbt", expected_name="t")
    let n1 = @src.normalize_json_text(built)
    let n2 = @src.normalize_json_text(json)
    inspect(n1, content=n2)
  }
}

///|
test "D-11 双维度锚 : 值语义 1 ≡ 1.0（N 层）；降级文本 1 ≠ 1.0（build 层）" {
  // N 层：RFC 8259 数字是抽象数值——1 与 1.0 规范化后等价
  let a = @src.normalize_json_text("{\"v\":1}")
  let b = @src.normalize_json_text("{\"v\":1.0}")
  inspect(a, content=b)
  inspect(a, content="{\"v\":1}")
  // build 层：源文本直传（类型头是压缩侧元信息，不改写值文本——PLAN §0）
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
  inspect(s1 == s2, content="false")
}

///|
test "#25 : 冗余圆括号包裹剥除（Group::Paren——moon fmt 产物可读）" {
  // A(("x")) / A((#| 多行)) 是合法 MoonBit（moon fmt 幂等保留该形态——
  // 真源进 fmt 跑的 workspace 后被 jsonmbt 拒是互操作 bug）：圆括号不
  // 改值语义，与 A("x") 严格等价；多层括号递归剥
  let src =
    #|enum A { A(String) }
    #|pub let t : Array[A] = [
    #|  A("plain"),
    #|  A(("double")),
    #|  A((
    #|#| 多行
    #|)),
    #|  A((("triple"))),
    #|]
  inspect(
    @src.build_source(src, path="t.json.mbt", expected_name="t"),
    content="[{\"case\":\"A\",\"value\":\"plain\"},{\"case\":\"A\",\"value\":\"double\"},{\"case\":\"A\",\"value\":\" 多行\"},{\"case\":\"A\",\"value\":\"triple\"}]",
  )
}

///|
test "#27 : Map 键往返反转义——解码值语义（曾静默双层转义）" {
  // 键含 \ " 与转义序列（jest transform 正则键形态）：import 产物键正确
  // 转义，build 回来曾直拼源码原文再转义 = 双层（静默数据改写，migrate
  // DIFF 哨兵首次在第三方真实数据抓到——nestjs sample/*/jest.json）。
  // 修后 l0_map 键走 unescape（与字段值路径同款），往返逐字节回源
  let json = "{\"m\":{\"a\u{5c}\u{5c}b\":1,\"c\u{5c}\"d\":2,\"e\u{5c}nf\":3}}"
  let out = @src.import_source(json, path="m.json", stem="m").content
  let built = @src.build_source(out, path="m.json.mbt", expected_name="m")
  inspect(built, content=json)
}

///|
test "#32-20 : hex 形态 Int64 下界可表示即收（-0x8000000000000000 曾误拒 J3004）" {
  // 十进制下界 -9223372036854775808 已收（PLAN §9 修复实录）；hex 同值形态
  // 曾走十进制特判残留误拒——值可表示 = 应产 Int64
  let out = @src.import_source(
      "{\"a\":-9223372036854775808}",
      path="t.json",
      stem="t",
    ).content
  inspect(out.contains("Int64"), content="true")
  let src_hex = "struct A {\n  a : Int64\n}\npub let t : A = A::{ a: -0x8000000000000000, }\n"
  let built = @src.build_source(src_hex, path="t.json.mbt", expected_name="t")
  inspect(built.contains("-9223372036854775808"), content="true")
}

///|
test "#32-20 : Map 非 String 键类型头预检 J2007（曾落值层 J3004 层/码漂移）" {
  let d = try {
    let _ = @src.build_source(
      "struct S {\n  m : Map[Int, String]\n}\npub let t : S = S::{ m: {} }\n",
      path="t.json.mbt",
      expected_name="t",
    )
    "BUILD-SUCCEEDED-BUT-DIAG-EXPECTED"
  } catch {
    e => if e is Diag(..) { e.render() } else { abort("non-Diag") }
  }
  inspect(d.contains("[J2007]"), content="true")
}
