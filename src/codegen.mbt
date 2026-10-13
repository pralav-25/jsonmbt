// .json.mbt 生成器（importer 出口）：InferResult + 值树 → 源文件全文
// 格式 = moon fmt 不动点（#18，2026-10-10 重写——#18 前旧证伪结论已勘误）：
//   宽度驱动渲染——整行 ≤84 record 单行（尾逗号规范形）/ 超宽每字段行 /
//   数组 ≤80 单行、标量超宽填满式 / Map 每对一行 / Some( 折 / #| 随嵌套
//   缩进 / 每顶层声明补 ///|。层 2 金门（fmt-fixed-point）对 probe/samples
//   全样本 + 合成宽样本常驻断言「产物过 moon fmt 零 diff」——moon 升级
//   fmt 形态漂移即金门红（漂移显性化）
// 头部 @generated 标注（纪律 11，Vitro 形态）：不写时间/版本——确定性硬锚
// （同输入两次 import 逐字节一致）的前提

///|
/// MoonBit 浮点字面量文法适配（探针⑥：纯整数尾数接指数解析错，须带小数点——
/// 陷阱 #13 勘误）：JSON 合法的 1e2 / 1E6 / -1e3 在 .json.mbt 层写不成——
/// 最小改写 = 尾数补 ".0"（审 P1-1）
fn ensure_double_syntax(repr : String) -> String {
  let view = repr[:]
  let n = view.length()
  let mut e_at = -1
  for i = 0; i < n; i = i + 1 {
    if view[i] == 'e' || view[i] == 'E' {
      e_at = i
      break
    }
  }
  if e_at < 0 {
    return repr
  }
  // e 之前的尾数若不含 '.'：在 e 前插入（符号/整数尾数均可）
  if view[0:e_at].contains(".") {
    return repr
  }
  repr[:e_at].to_owned() + ".0" + repr[e_at:].to_owned()
}

///|
/// 字符串值渲染（#26 教师循环形态保真）：含 \n 的长文案产 `#|` 多行
/// （值位括号包裹 + 无前导空格规范形——moon 语义 `#| x` 空格入值，不产
/// 即不引入；回写不再把手写多行形态磨损成单行转义长串）；单行值保持
/// 转义形态。fmt 幂等（探针 2026-10-10：构造器/字段/Map 值/数组/Some
/// 位全合法，fmt 归一为值位括号 + 缩进 #|，二次 fmt 不动）。含 \r 的
/// 值不走多行——CRLF 行尾 \r 入值的语义在读取层有歧面，转义保真
fn render_string_value(s : String) -> String {
  if s.contains("\n") && !s.contains("\r") {
    let buf = StringBuilder()
    buf.write_string("(\n")
    for line in s.split("\n") {
      buf.write_string("#|")
      buf.write_string(line.to_owned())
      buf.write_string("\n")
    }
    buf.write_string(")")
    buf.to_string()
  } else {
    moonbit_escape(s)
  }
}

///|
/// 0..15 → 小写 hex 字符（\u{...} 写侧与 unescape 的 hex 读侧对齐——#32-2）
fn hex_lc(d : Int) -> Char {
  if d < 10 {
    (d + '0'.to_int()).unsafe_to_char()
  } else {
    (d - 10 + 'a'.to_int()).unsafe_to_char()
  }
}

///|
/// 解码值 → MoonBit 字面量转义（unescape 的逆向；\u{XX} 小写 hex 惯例）
fn moonbit_escape(s : String) -> String {
  let buf = StringBuilder()
  buf.write_char('"')
  for ch in s {
    match ch {
      '"' => buf.write_string("\\\"")
      '\\' => buf.write_string("\\\\")
      '\n' => buf.write_string("\\n")
      '\r' => buf.write_string("\\r")
      '\t' => buf.write_string("\\t")
      '\b' => buf.write_string("\\b")
      '\u{0C}' => buf.write_string("\\f")
      other =>
        if other.to_int() < 0x20 {
          // 三段运行时拼接：MoonBit 字符串里 \\ 会吃掉紧随的 \{ 插值——
          // 写成单串插值会整段源码落盘（审 P1-2 根因）
          buf.write_string("\\u{")
          // 小写 hex（与 unescape 的 1..6 位 hex 对齐——#32-2 实锤：曾写
          // 十进制，读侧按 hex 累加，两侧各自合法、值静默错位）
          let v = other.to_int()
          if v >= 16 {
            buf.write_char(hex_lc(v / 16))
          }
          buf.write_char(hex_lc(v % 16))
          buf.write_string("}")
        } else {
          buf.write_char(other) // 非 ASCII 按 UTF-8 原样（源文件即 UTF-8）
        }
    }
  }
  buf.write_char('"')
  buf.to_string()
}

///|
/// struct 定义段（字段每行——fmt canonical）
fn render_struct_def(name : String, fields : Array[(String, JType)]) -> String {
  let buf = StringBuilder()
  // pub struct（审 P2-5）：priv struct 每字段一条 unused_field 警告噪音，
  // 且 moon info 对 priv 只给不透明 type——schema 出口（P1.5 余项）依赖 pub
  buf.write_string("pub struct ")
  buf.write_string(name)
  buf.write_string(" {\n")
  for f in fields {
    buf.write_string("  ")
    buf.write_string(f.0)
    buf.write_string(" : ")
    buf.write_string(f.1.show())
    buf.write_string("\n")
  }
  buf.write_string("}\n")
  buf.to_string()
}

///|
/// struct 字段类型表（渲染上下文）
type StructTable = Map[String, Array[(String, JType)]]

///|
/// field-alias 反查表（渲染上下文，#13）：键 "Struct\u{1}json键" → 改名后
/// label——数据字面量的构造字段名与类型查表都走改名后形态
type AliasTable = Map[String, String]

///|
fn build_alias_table(aliases : Array[(String, String, String)]) -> AliasTable {
  let tab : AliasTable = Map([])
  for a in aliases {
    let (sname, label, key) = a
    tab["\{sname}\u{1}\{key}"] = label
  }
  tab
}

///|
fn alias_field_label(tab : AliasTable, sname : String, key : String) -> String {
  match tab.get("\{sname}\u{1}\{key}") {
    Some(label) => label
    None => key
  }
}

///|
fn build_struct_table(
  structs : Array[(String, Array[(String, JType)])],
) -> StructTable {
  let table : StructTable = Map([])
  for s in structs {
    table[s.0] = s.1
  }
  table
}

///|
fn struct_field_type(
  table : StructTable,
  sname : String,
  label : String,
) -> JType? {
  match table.get(sname) {
    Some(fields) =>
      match fields.iter().find_first(fn(f) { f.0 == label }) {
        Some((_, t)) => Some(t)
        None => None
      }
    None => None
  }
}

///|
/// struct 的隐含 JSON 键集（label 经 alias 逆映射 = json 键；无注记则恒等）
fn implied_json_keys(
  atab : AliasTable,
  sname : String,
  labels : Array[String],
) -> Array[String] {
  // atab 键 = "sname\u{1}json键" → value = label；反查 label → json 键
  let rev : Map[String, String] = Map([])
  atab.each(fn(k, label) {
    let sep = k.find("\u{1}")
    match sep {
      Some(i) =>
        if k[:i].to_owned() == sname {
          rev[label] = k[i + 1:].to_owned()
        }
      None => ()
    }
  })
  labels.map(fn(l) {
    match rev.get(l) {
      Some(k) => k
      None => l
    }
  })
}

///|
/// fill 严格校验：JSON 键集必须与 struct 隐含键集精确一致（多余 J3005 /
/// 缺失 J3006——「按已声明类型重算」语境下静默忽略 = 数据不同步吞错）
fn strict_check_keys(
  table : StructTable,
  atab : AliasTable,
  sname : String,
  ks : Array[String],
) -> Unit raise Diag {
  let labels : Array[String] = []
  match table.get(sname) {
    Some(fs) =>
      for f in fs {
        labels.push(f.0)
      }
    None => ()
  }
  let implied = implied_json_keys(atab, sname, labels)
  // 多余
  for k in ks {
    if !implied.contains(k) {
      raise Diag(
        code=JUnknownField,
        loc=dummy_loc(),
        message="unknown field '\{k}' — struct '\{sname}' declares: \{implied.join(", ")}",
        help=Some(
          "the source JSON has keys the declared type does not cover — update the struct header or the JSON",
        ),
        path="",
      )
    }
  }
  // 缺失
  for k in implied {
    if !ks.contains(k) {
      raise Diag(
        code=JMissingField,
        loc=dummy_loc(),
        message="missing field '\{k}' in '\{sname}' — declared in the type header but absent from the source JSON",
        help=Some(
          "fill only rewrites the value body; add the key to the JSON or drop it from the struct",
        ),
        path="",
      )
    }
  }
}

///|
/// 值渲染（期望类型驱动；嵌套一律内联单行）。strict_keys（#14-2b fill）：
/// 声明类型语境——struct 键集精确校验 + enum 按键集/tag 选变体；缺省
/// false = import 主路径现行为（推断产物与数据天然一致，无需校验）
fn render_value(
  table : StructTable,
  atab : AliasTable,
  j : Json,
  ty : JType?,
  enums? : Map[String, EnumDef] = Map([]),
  strict_keys? : Bool = false,
) -> String raise Diag {
  match (j, ty) {
    (Null, t) =>
      match t {
        Some(JTOption(_)) | None => "None"
        Some(other) =>
          if strict_keys {
            // #32-5②：fill 语境 null 进非 Option 声明位 = 数据与类型头矛盾
            // ——曾静默产 None（moon 类型错的产物落盘，rc 0）
            raise Diag(
              code=JFieldType,
              loc=dummy_loc(),
              message="null cannot fill a non-Option field of type '\{other.show()}'",
              help=Some(
                "use T? (Option) in the type header, or supply a value — fill never guesses",
              ),
              path="",
            )
          } else {
            "None" // import 防御（推断层保证 null ⇒ Option，此路不可达）
          }
      }
    (v, Some(JTOption(t))) =>
      "Some(\{render_value(table, atab, v, Some(t), enums~, strict_keys~)})"
    (True, _) => "true"
    (False, _) => "false"
    (Number(_, repr~), _) =>
      match repr {
        Some(t) => ensure_double_syntax(t)
        None => "0" // 自持解析器产物恒带 repr；防御
      }
    (String(s), Some(JTEnum(n))) if strict_keys =>
      // fill：JSON 值 = 变体名字符串（D-5 无参变体的降级投影）→ 裸构造器
      match enums.get(n) {
        Some(def) =>
          if def.variants.contains(s) {
            s
          } else {
            raise Diag(
              code=JFieldType,
              loc=dummy_loc(),
              message="enum '\{n}' has no variant '\{s}'",
              help=Some("variants of '\{n}': \{def.variants.join(" ")}"),
              path="",
            )
          }
        None =>
          raise Diag(
            code=JFieldType,
            loc=dummy_loc(),
            message="enum '\{n}' is not defined in this file",
            help=Some(
              ".json.mbt is single-file; declare the enum alongside the structs",
            ),
            path="",
          )
      }
    (String(s), _) => render_string_value(s)
    (Array(elems), t) => {
      let elem_ty : JType? = match t {
        Some(JTArray(et)) => Some(et)
        _ => None
      }
      let parts : Array[String] = []
      for e in elems {
        parts.push(render_value(table, atab, e, elem_ty, enums~, strict_keys~))
      }
      // #18 fmt 不动点：数组恒内联单行（`[a, b]`）；超宽由 block 路径
      // 分流（标量填满式/复合每元素行）——#9 的逐元素折行非 fmt 形态已撤
      "[\{parts.join(", ")}]"
    }
    (Object(o), Some(JTEnum(n))) if strict_keys =>
      // fill：键集漂移消歧（#14-2b）——按 tag 键（降级产物形态）或键集
      // 精确匹配选 payload 变体；无匹配 = J3004 fail loud（信息矛盾不该
      // 静默选边）
      fill_enum_variant(table, atab, enums, n, o)
    (Object(o), Some(JTStruct(name))) => {
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      if strict_keys {
        strict_check_keys(table, atab, name, ks)
      }
      for k in ks {
        let v = o.get(k).unwrap()
        let label = alias_field_label(atab, name, k)
        entries.push(
          "\{label}: \{render_value(table, atab, v, struct_field_type(table, name, label), enums~, strict_keys~)}",
        )
      }
      (if entries.length() == 0 {
        "\{name}::{}"
      } else {
        "\{name}::{ \{entries.join(", ")}, }"
      })
    }
    (Object(o), t) => {
      // Map 逃生门形态（推断产物的对象位只剩 Map 上下文）
      let vt : JType? = match t {
        Some(JTMap(_, v)) => Some(v)
        _ => None
      }
      let entries : Array[String] = []
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      for k in ks {
        let v = o.get(k).unwrap()
        entries.push(
          "\{moonbit_escape(k)}: \{render_value(table, atab, v, vt, enums~, strict_keys~)}",
        )
      }
      (if entries.length() == 0 {
        "{}"
      } else {
        // Map 单行无尾逗号（金门实证——与 record 单行的尾逗号形不同族）
        "{ \{entries.join(", ")} }"
      })
    }
  }
}

///|
/// fill 的 enum 变体消歧（#14-2b）：① o 含 "case" 字符串键（= 自身降级
/// 产物形态）→ 按 tag 选变体，payload = 剥 tag 后的对象；② 无 tag →
/// 键集与各 payload struct 的隐含键集精确匹配。选定后渲染
/// `Var(Px::{...})`（payload 以声明 struct 期望递归 strict 渲染）
fn fill_enum_variant(
  table : StructTable,
  atab : AliasTable,
  enums : Map[String, EnumDef],
  ename : String,
  o : Map[String, Json],
) -> String raise Diag {
  let (def, v, payload_keys) = resolve_enum_variant(table, atab, enums, ename, o)
  render_variant_payload(table, atab, enums, def, v, payload_keys, o)
}

///|
/// enum 对象 → (定义, 变体名, payload 键集) 消歧（#32-5 重构提出，
/// inline/block 两形共用）：① tag 键指示（降级产物形态）② 键集精确匹配；
/// 无匹配 = J3004 fail loud（信息矛盾不该静默选边）
fn resolve_enum_variant(
  table : StructTable,
  atab : AliasTable,
  enums : Map[String, EnumDef],
  ename : String,
  o : Map[String, Json],
) -> (EnumDef, String, Array[String]) raise Diag {
  let def = match enums.get(ename) {
    Some(d) => d
    None =>
      raise Diag(
        code=JFieldType,
        loc=dummy_loc(),
        message="enum '\{ename}' is not defined in this file",
        help=Some(
          ".json.mbt is single-file; declare the enum alongside the structs",
        ),
        path="",
      )
  }
  let ks : Array[String] = []
  o.each(fn(k, _) { ks.push(k) })
  // ① tag 键指示（降级产物形态——fill 吃自己的产物，round-trip 闭环）
  let variant : String? = match o.get("case") {
    Some(String(tag)) =>
      if def.payload_variants.contains(tag) {
        Some(tag)
      } else {
        raise Diag(
          code=JFieldType,
          loc=dummy_loc(),
          message="enum '\{ename}' has no payload variant '\{tag}'",
          help=Some("payload variants: \{def.payload_variants.join(" ")}"),
          path="",
        )
      }
    _ => None
  }
  let payload_keys : Array[String] = ks.filter(fn(k) { k != "case" })
  match variant {
    Some(v) => (def, v, payload_keys)
    None => {
      // ② 键集精确匹配
      for v in def.payload_variants {
        let pty = def.payload_types.get(v)
        match pty {
          Some(JTStruct(px)) => {
            let labels : Array[String] = []
            match table.get(px) {
              Some(fs) =>
                for f in fs {
                  labels.push(f.0)
                }
              None => ()
            }
            let implied = implied_json_keys(atab, px, labels)
            let same = payload_keys.length() == implied.length() &&
              payload_keys.iter().all(fn(k) { implied.contains(k) })
            if same {
              return (def, v, payload_keys)
            }
          }
          _ => ()
        }
      }
      raise Diag(
        code=JFieldType,
        loc=dummy_loc(),
        message="no variant of '\{ename}' matches key set { \{payload_keys.join(", ")} }",
        help=Some(
          "payload variants: \{def.payload_variants.join(" ")} — hand-pick by adding a \"case\" tag, or extend the enum",
        ),
        path="",
      )
    }
  }
}

///|
fn render_variant_payload(
  table : StructTable,
  atab : AliasTable,
  enums : Map[String, EnumDef],
  def : EnumDef,
  v : String,
  payload_keys : Array[String],
  o : Map[String, Json],
) -> String raise Diag {
  let pty = def.payload_types.get(v)
  match pty {
    Some(JTStruct(px)) => {
      // payload 对象（剥 tag 键）以声明 struct 期望 strict 递归
      let inner : Map[String, Json] = Map([])
      for k in payload_keys {
        inner[k] = o.get(k).unwrap()
      }
      "\{v}(\{render_value(table, atab, Json::object(inner), pty, enums~, strict_keys=true)})"
    }
    Some(other) => {
      // 审 P1-c：标量 payload 的源对象剥 tag 后无余键（缺 value 键）——
      // 数据与声明不同步，fail loud（曾 payload_keys[0] 越界 panic 且
      // 绕过校验先行——D-8 ①）
      if payload_keys.length() == 0 {
        raise Diag(
          code=JMissingField,
          loc=dummy_loc(),
          message="variant '\{v}' has a scalar payload but the source JSON carries no 'value' key",
          help=Some(
            "fill only rewrites the value body; add the payload key to the JSON or use a payload-less variant",
          ),
          path="",
        )
      }
      // #32-5③：标量 payload 剥 tag 后必须恰好一键——多余键曾静默吞
      //（strict_check_keys「静默忽略 = 吞错」同款）
      if payload_keys.length() > 1 {
        raise Diag(
          code=JFieldType,
          loc=dummy_loc(),
          message="variant '\{v}' has a scalar payload but the source JSON carries extra keys: \{payload_keys.join(", ")}",
          help=Some(
            "a scalar payload takes exactly one value key — drop the extras or model the payload as a struct",
          ),
          path="",
        )
      }
      "\{v}(\{render_value(table, atab, o.get(payload_keys[0]).unwrap(), Some(strip_option_shallow(other)), enums~, strict_keys=true)})"
    }
    None => "\{v}"
  }
}

///|
fn strip_option_shallow(t : JType) -> JType {
  match t {
    JTOption(x) => x
    other => other
  }
}

///|
/// 排版常数（#18 fmt 不动点；#32-4 手工规范形重采定界——生成器产物反推会
/// 因 block 化掩盖真值界，且多文件批扫撞 fmt 缓存假存活，须单文件逐档）：
/// 顶层整行 ≤80 存活（record/数组同界）；块内字段行 ≤81 存活（record 值
/// 实测 81/82 分界，数组值实测 ≥83——取保守 81，稳定优先于紧凑）
const FMT_TOP_WIDTH = 80

///|
const FMT_LINE_WIDTH = 81 // 块内字段行单行界（field_block_line 整行判定）

///|
const FMT_FILL_WIDTH = 84 // 标量数组填满式行宽（金门对账：synth 10 元素 81 收/89 断、B1 83 收/91 断——界 ∈[83,88] 取与行界统一的 84）

///|
/// 值内是否含 #| 多行形态（天然不可内联——值含真换行）
fn has_multiline(j : Json) -> Bool {
  match j {
    String(s) => s.contains("\n") && !s.contains("\r")
    Array(elems) => {
      let mut hit = false
      for e in elems {
        if has_multiline(e) {
          hit = true
          break
        }
      }
      hit
    }
    Object(o) => {
      let mut hit = false
      o.each(fn(_, v) { if has_multiline(v) { hit = true } })
      hit
    }
    _ => false
  }
}

///|
/// 行宽（UTF-8 字节数——金门实证：fmt 的宽度判定按字节，中文值 73 码点
/// 87 字节的行被展开而同宽 ASCII 行不展）
fn line_width(s : String) -> Int {
  let mut n = 0
  for c in s {
    let cp = c.to_int()
    let w = if cp <= 0x7F {
      1
    } else if cp <= 0x7FF {
      2
    } else if cp <= 0xFFFF {
      3
    } else {
      4
    }
    n = n + w
  }
  n
}

///|
/// 缩进串
fn ind(n : Int) -> String {
  let buf = StringBuilder()
  for _ in 0..<n {
    buf.write_char(' ')
  }
  buf.to_string()
}

///|
/// block 多行渲染（超宽/多行路径）：完整值块（行已含缩进）。形态语义与
/// render_value 同源（键集校验/enum 消歧透传），仅排版分块
fn render_block(
  table : StructTable,
  atab : AliasTable,
  j : Json,
  ty : JType?,
  indent : Int,
  enums? : Map[String, EnumDef] = Map([]),
  strict_keys? : Bool = false,
) -> String raise Diag {
  match (j, ty) {
    (v, Some(JTOption(t))) =>
      // Some( 折形 = fmt 规范形（#32-4 探针实测）：Some( 与值首行同行、
      // 值块以字段缩进为基准、闭 ) 贴块尾（曾产 Some(\\n  折形——fmt 改写
      // = 不动点破）；短值走 render_value 单行路径不经此处
      "Some(\{render_block(table, atab, v, Some(t), indent, enums~, strict_keys~)})"
    (Array(elems), t) => {
      let elem_ty : JType? = match t {
        Some(JTArray(et)) => Some(et)
        _ => None
      }
      // 元素分类：含复合（对象/数组/#|）→ 每元素一行（p7/A 探针——标量
      // 数组的「每元素行」会被 fmt 填满化，非稳定形态）；纯标量 → 填满式
      let has_compound = {
        let mut hit = false
        for e in elems {
          match e {
            Number(_) | True | False | Null => ()
            String(s) => if s.contains("\n") && !s.contains("\r") {
              hit = true
            }
            _ => hit = true
          }
        }
        hit
      }
      let buf = StringBuilder()
      buf.write_string("[\n")
      if has_compound {
        for e in elems {
          // 复合元素优先单行尾逗号形（fmt 实测：元素位 record 不展开，
          // 行宽 ≤84 即单行）；超宽/#| 才递归 block 展开
          let inline_e = render_value(table, atab, e, elem_ty, enums~, strict_keys~)
          let one = ind(indent + 2) + inline_e + ","
          buf.write_string(ind(indent + 2))
          if !has_multiline(e) && line_width(one) <= FMT_LINE_WIDTH {
            buf.write_string(inline_e)
          } else {
            buf.write_string(
              render_block(table, atab, e, elem_ty, indent + 2, enums~, strict_keys~),
            )
          }
          buf.write_string(",\n")
        }
      } else {
        let parts : Array[String] = []
        for e in elems {
          parts.push(render_value(table, atab, e, elem_ty, enums~, strict_keys~))
        }
        // 填满式：行首起逐元素 append，整行超 FMT_FILL_WIDTH 断行
        let mut cur = ind(indent + 2)
        let mut first = true
        for p in parts {
          let cand = if first {
            cur + p + ","
          } else {
            cur + " " + p + ","
          }
          if !first && line_width(cand) > FMT_FILL_WIDTH {
            buf.write_string(cur)
            buf.write_string("\n")
            cur = ind(indent + 2) + p + ","
          } else {
            cur = cand
          }
          first = false
        }
        buf.write_string(cur)
        buf.write_string("\n")
      }
      buf.write_string(ind(indent))
      buf.write_string("]")
      buf.to_string()
    }
    (Object(o), Some(JTStruct(name))) => {
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      if strict_keys {
        strict_check_keys(table, atab, name, ks)
      }
      let buf = StringBuilder()
      buf.write_string("\{name}::{\n")
      for k in ks {
        let v = o.get(k).unwrap()
        let label = alias_field_label(atab, name, k)
        buf.write_string(
          field_block_line(
            table,
            atab,
            label,
            v,
            struct_field_type(table, name, label),
            indent + 2,
            enums,
            strict_keys,
          ),
        )
      }
      buf.write_string(ind(indent))
      buf.write_string("}")
      buf.to_string()
    }
    (Object(o), Some(JTEnum(n))) if strict_keys => {
      // #32-5①：enum 位超宽对象走变体消歧——struct payload 出块形
      // A(\n  Px::{…}\n)；标量/无参形态复用 inline（曾落到下方 Map 兜底臂
      // ——enum 位放 Map 字面量 = 非法产物且变体/键集校验整体被跳过）
      let (def, v, pks) = resolve_enum_variant(table, atab, enums, n, o)
      let pty = def.payload_types.get(v)
      match pty {
        Some(JTStruct(_)) => {
          let inner : Map[String, Json] = Map([])
          for k in pks {
            inner[k] = o.get(k).unwrap()
          }
          "\{v}(\n\{ind(indent + 2)}\{render_block(table, atab, Json::object(inner), pty, indent + 2, enums~, strict_keys=true)}\n\{ind(indent)})"
        }
        _ => render_variant_payload(table, atab, enums, def, v, pks, o)
      }
    }
    (Object(o), t) => {
      // Map 超宽：每对一行（规则 5，无填满式）
      let vt : JType? = match t {
        Some(JTMap(_, v)) => Some(v)
        _ => None
      }
      let ks : Array[String] = []
      o.each(fn(k, _) { ks.push(k) })
      let buf = StringBuilder()
      buf.write_string("{\n")
      for k in ks {
        let v = o.get(k).unwrap()
        buf.write_string(
          field_block_line(
            table,
            atab,
            moonbit_escape(k),
            v,
            vt,
            indent + 2,
            enums,
            strict_keys,
          ),
        )
      }
      buf.write_string(ind(indent))
      buf.write_string("}")
      buf.to_string()
    }
    _ => render_value(table, atab, j, ty, enums~, strict_keys~)
  }
}

///|
/// 字段行渲染（block 路径）：短值内联（字段行宽 ≤84 且非多行）；超宽或
/// #| 多行按类型分块（k: [ 填满 / k: { 每对 / k: Some( 折 / k: ( 的 #| 块
/// ——E2 实测 #| 随嵌套缩进）。返回完整行（含缩进与行尾 ,\n）
fn field_block_line(
  table : StructTable,
  atab : AliasTable,
  label : String,
  v : Json,
  vt : JType?,
  indent : Int,
  enums : Map[String, EnumDef],
  strict_keys : Bool,
) -> String raise Diag {
  if v is String(s) && s.contains("\n") && !s.contains("\r") {
    let buf = StringBuilder()
    buf.write_string(ind(indent))
    buf.write_string("\{label}: (\n")
    for line in s.split("\n") {
      buf.write_string(ind(indent + 2))
      buf.write_string("#|")
      buf.write_string(line.to_owned())
      buf.write_string("\n")
    }
    buf.write_string(ind(indent))
    buf.write_string("),\n")
    return buf.to_string()
  }
  let inline = render_value(table, atab, v, vt, enums~, strict_keys~)
  let inline_line = "\{ind(indent)}\{label}: \{inline},"
  // #32-4：单行判定统一 = 整行宽 ≤ FMT_LINE_WIDTH（fmt 真值按整行，与值
  // 形态宽无关——数组/Map 曾用不含行前缀的值宽口径，78 值宽 + 前缀超界
  // 产单行被 fmt 展开）
  let fits = line_width(inline_line) <= FMT_LINE_WIDTH
  if !has_multiline(v) && fits {
    return "\{inline_line}\n"
  }
  // 块基准 = 字段缩进（fmt 实测：rules: [ 的元素缩进 4 = 字段 2 + 2，
  // 闭 ], 回字段 2——render_block 内部 +2 自洽）
  let block = render_block(table, atab, v, vt, indent, enums~, strict_keys~)
  "\{ind(indent)}\{label}: \{block},\n"
}

///|
/// 顶层值（#18）：整行内联 ≤84 且无 #| → 单行（fmt 收敛终态）；否则
/// block 多行。enums/strict_keys（#14-2b fill）透传——键集校验同 strict
fn render_top_value(
  table : StructTable,
  atab : AliasTable,
  j : Json,
  ty : JType?,
  enums? : Map[String, EnumDef] = Map([]),
  strict_keys? : Bool = false,
  prefix~ : String = "",
) -> String raise Diag {
  // 判定含行前缀（pub let x : T = ）——fmt 收敛界是整行宽（顶层实测 80）
  let inline = render_value(table, atab, j, ty, enums~, strict_keys~)
  let whole = prefix + inline
  if !has_multiline(j) && line_width(whole) <= FMT_TOP_WIDTH {
    return inline
  }
  render_block(table, atab, j, ty, 0, enums~, strict_keys~)
}

///|
/// 生成 .json.mbt 全文（import 主出口；无时间/版本戳——确定性）。
/// field-alias 注记（#13）紧随源行：原始 JSON 键 → 改名后字段的映射表，
/// build 侧据此还原键名（合法 MoonBit 注释——fmt 幂等，探针实锚）
fn generate_source(
  result : InferResult,
  root : Json,
  stem~ : String,
  src_name~ : String,
) -> String raise Diag {
  let table = build_struct_table(result.structs)
  let atab = build_alias_table(result.aliases)
  let buf = StringBuilder()
  buf.write_string(
    "// @generated by jsonmbt import —— 禁手改（再生成：jsonmbt import \{src_name}）。\n",
  )
  buf.write_string("// 源：\{src_name}\n")
  for a in result.aliases {
    let (sname, label, key) = a
    buf.write_string("// jsonmbt: field-alias \{sname}.\{label} = \"\{key}\"\n")
  }
  buf.write_string("\n")
  // #18 fmt 不动点：每个顶层声明前补 ///| 文档标记（fmt 规则 1——不产
  // 则 fmt 必改写），声明间空行分隔
  if result.uses_never {
    buf.write_string("///|\npub enum \{result.never_name} {}\n\n")
  }
  for s in result.structs {
    buf.write_string("///|\n")
    buf.write_string(render_struct_def(s.0, s.1))
    buf.write_string("\n")
  }
  match result.root_ty {
    Some(t) => {
      let pfx = "pub let \{stem} : \{t.show()} = "
      buf.write_string("///|\n")
      buf.write_string(pfx)
      buf.write_string(render_top_value(table, atab, root, Some(t), prefix=pfx))
      buf.write_string("\n")
    }
    None => {
      let pfx = "pub let \{stem} = "
      buf.write_string("///|\n")
      buf.write_string(pfx)
      buf.write_string(render_top_value(table, atab, root, None, prefix=pfx))
      buf.write_string("\n")
    }
  }
  buf.to_string()
}
