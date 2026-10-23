// L0 校验器 + 值提取（D-3 自持校验器的核心；D-8 ② fail loud 在此落地）
// 白名单（全部探针实锤，PLAN §9）：
//   Record(type_name?, fields) / Array / Map / Some(v)=Apply(Constr) / None=Constr
//   Constant::{Int, Int64, Double, Bool, String}——raw 为源文本（负号在 raw 内、
//   Int64 无 L 后缀、转义已解码），数值直传 Json::Number 的 repr 保真
// 白名单之外的一切 Expr = 非 L0 = J3001（不设 null 兜底——探针原型的教训）
// 类型对值校验：期望类型 JType? 驱动（无注解上下文 = 自由值，仅白名单 + 深度）

///|
const MAX_DEPTH : Int32 = 128
// 深度预算（Vitro 陷阱 #28 探针法）：先取保守值，压测校准后钉死进锚；超限 J2004

///|
/// 数值源文本 → Json：剥 MoonBit 允许的下划线分隔符（JSON 不允许）；
/// Double 占位仅供 as_number 消费，repr 保真（stringify/N 走源文本）
fn num_json(raw : String, loc : @basic.Location) -> Json raise Diag {
  match numeric_text(raw) {
    Ok(t, _) => {
      // 透传 core parse 的完整 Number 语义（value+repr：超范围大数自动走
      // out-of-range fallback 保源文本），再把 repr 钉到归一文本 t——
      // 降级输出按 t（源文本直传），值语义归一由 N 侧 canon 负责
      let parsed : Json? = Some(@json.parse(t)) catch { _ => None }
      match parsed {
        Some(j) =>
          if j is Number(d, ..) {
            Json::number(d, repr=t)
          } else {
            abort("unreachable: numeric text parses to Number")
          }
        None =>
          raise Diag(
            code=JBadLiteral,
            loc~,
            message="malformed numeric literal '\{raw}'",
            help=None,
            path="",
          )
      }
    }
    Overflow(t) =>
      raise Diag(
        code=JBadLiteral,
        loc~,
        message="numeric literal '\{raw}' exceeds Int64 (normalized '\{t}')",
        help=None,
        path="",
      )
    Illegal =>
      raise Diag(
        code=JBadLiteral,
        loc~,
        message="malformed numeric literal '\{raw}'",
        help=None,
        path="",
      )
  }
}

///|
priv enum NumParse {
  Ok(String, Int64) // (十进制文本, Int64 视图；浮点时视图为占位 0)
  Overflow(String)
  Illegal
}

///|
/// raw 字面量 → 十进制文本：剥下划线；0x/0o/0b 进制归一（JSON 只有十进制）；
/// 整数全过 Int64 累加器——溢出即 Overflow（D-2 超 Int64 诚实拒绝的判据）
fn numeric_text(raw : String) -> NumParse {
  let s = raw.replace(old="_", new="")
  if s == "" {
    return Illegal
  }
  // 符号
  let neg = s[0] == '-'
  let digits : StringView = if neg || s[0] == '+' { s[1:] } else { s[:] }
  // 进制前缀（浮点不与进制前缀共存）
  let base : Int32 = if digits.length() > 2 {
    match digits[0:2] {
      "0x" | "0X" => 16
      "0o" | "0O" => 8
      "0b" | "0B" => 2
      _ => 10
    }
  } else {
    10
  }
  let body : StringView = if base == 10 { digits } else { digits[2:] }
  if base != 10 && body == "" {
    return Illegal
  }
  // 浮点（仅十进制）：含 . / e / E——Double 占位走 @json.parse，界检查不适用
  if base == 10 &&
    (body.contains(".") || body.contains("e") || body.contains("E")) {
    return Ok(s, 0L)
  }
  // 整数：UInt64 累加（溢出检测），十进制输出。界按符号分侧：正数
  // 2^63-1；负数放宽到 2^63（-2^63 是唯一「超出正界却可表示」的单点，
  // #32-20：hex/0o/0b 形态曾因只特判十进制而误拒——进制无关的界内放行）
  let mut acc : UInt64 = 0UL
  let bound : UInt64 = if neg {
    9223372036854775808UL
  } else {
    9223372036854775807UL
  }
  for ch in body {
    let d = digit_value(ch)
    match d {
      Some(k) => {
        // acc*base + k <= bound  ⇔  acc <= (bound-k)/base（整除安全侧）
        if acc > (bound - k.to_uint64()) / base.to_uint64() {
          return Overflow(s)
        }
        acc = acc * base.to_uint64() + k.to_uint64()
      }
      None => return Illegal
    }
  }
  if acc == 9223372036854775808UL {
    // 仅 neg 可达（正侧 bound 较紧）；恒为 min 单点
    return Ok("-9223372036854775808", -9223372036854775808L)
  }
  // acc ≤ 2^63-1（2^63 单点已上返）→ reinterpret 无损
  let v = if neg {
    -acc.reinterpret_as_int64()
  } else {
    acc.reinterpret_as_int64()
  }
  Ok("\{v}", v)
}

///|
fn digit_value(ch : Char) -> Int32? {
  if ch >= '0' && ch <= '9' {
    Some(ch.to_int() - '0'.to_int())
  } else if ch >= 'a' && ch <= 'f' {
    Some(ch.to_int() - 'a'.to_int() + 10)
  } else if ch >= 'A' && ch <= 'F' {
    Some(ch.to_int() - 'A'.to_int() + 10)
  } else {
    None
  }
}

///|
/// J3004 helper
fn type_mismatch(
  loc : @basic.Location,
  expected : String,
  got : String,
  help~ : String? = None,
) -> Diag {
  Diag(
    code=JFieldType,
    loc~,
    message="expects \{expected}, got \{got}",
    help~,
    path="",
  )
}

///|
/// J3001 helper：非 L0 表达式
fn not_literal(loc : @basic.Location, what : String) -> Diag {
  Diag(
    code=JNotLiteral,
    loc~,
    message="\{what} is outside the L0 pure-literal subset",
    help=Some(
      "use a literal value (record, array, map, or scalar); for anything computed, write real MoonBit instead",
    ),
    path="",
  )
}

///|
fn check_depth(depth : Int32, loc : @basic.Location) -> Unit raise Diag {
  if depth > MAX_DEPTH {
    raise Diag(
      code=JDeep,
      loc~,
      message="nesting exceeds the depth budget of \{MAX_DEPTH}",
      help=Some("flatten the data or split it into several .json.mbt files"),
      path="",
    )
  }
}

///|
fn in_i32_range(v : Int64) -> Bool {
  v >= -2147483648L && v <= 2147483647L
}

///|
/// L0 提取主函数：Expr → Json 值树（校验与降级同一趟——D-8 check=build 同路径的前提）
fn l0_expr(
  env : Map[String, StructDef],
  enums : Map[String, EnumDef],
  e : @syntax.Expr,
  ty : JType?, // 期望类型；None = 无类型上下文（自由值）
  depth : Int32,
) -> Json raise Diag {
  check_depth(depth, expr_loc(e))
  match e {
    Constant(c~, loc~) => l0_constant(c, ty, loc)
    Record(type_name~, fields~, loc~, ..) =>
      l0_record(env, enums, type_name, fields, ty, depth, loc)
    Array(exprs~, loc~, ..) => {
      let elem_ty : JType? = match ty {
        Some(JTArray(t)) => Some(t)
        Some(other) => raise type_mismatch(loc, other.show(), "array")
        None => None
      }
      let arr : Array[Json] = []
      for e2 in exprs {
        arr.push(l0_expr(env, enums, e2, elem_ty, depth + 1))
      }
      Json::array(arr)
    }
    Map(elems~, loc~) => l0_map(env, enums, elems, ty, depth, loc)
    Group(expr~, group~, loc~) =>
      // #25：冗余圆括号剥除——Group(Paren) 是 moon fmt 规范产物形态
      //（真源进 fmt 跑的 workspace 后 jsonmbt 拒合法 MoonBit 属互操作
      // bug）；圆括号不改值语义，递归剥（多层括号自然解）。花括号块
      // = 副作用序列面，非字面量
      match group {
        Paren => l0_expr(env, enums, expr, ty, depth + 1)
        Brace => raise not_literal(loc, "braced block")
      }
    Apply(func~, args~, loc~) => {
      // Some(v)：func = Constr(Some)，单个位置参数（探针实锤形态）
      let is_some = func is Constr(constr~, ..) && constr.name.name == "Some"
      if is_some {
        // 恰好一个位置参数才视为 Some(v)（List 构造器不公开——按 head/size 检查）
        let arg : @syntax.Expr? = if args.length() == 1 {
          match args.head() {
            Some({ value, kind: Positional, }) => Some(value)
            _ => None
          }
        } else {
          None
        }
        match arg {
          Some(v) =>
            match ty {
              Some(JTOption(t)) => l0_expr(env, enums, v, Some(t), depth + 1)
              Some(other) =>
                raise type_mismatch(
                  loc,
                  other.show(),
                  "Some(...)",
                  help=Some(
                    "wrap values in Some(...) only for T? (Option) fields",
                  ),
                )
              None => l0_expr(env, enums, v, None, depth + 1)
            }
          None =>
            raise not_literal(loc, "Some(...) with non-positional arguments")
        }
        // 带 payload 构造器：D-5 转正（§8 2026-10-07 二次裁定）——enum 单
        // payload 构造器字面量入 L0，降级投影 = tag 对象展开（payload 字段
        // 进顶层 + "case" tag 键）；标量 payload = {"case":名,"value":值}
      } else if func is Constr(constr~, ..) && args.length() == 1 {
        match args.head() {
          Some({ value, kind: Positional, }) =>
            payload_case(env, enums, constr.name.name, value, ty, depth, loc)
          _ => raise not_literal(loc, "constructor with non-positional payload")
        }
      } else {
        raise not_literal(loc, "function call")
      }
    }
    Constr(constr~, loc~) =>
      if constr.name.name == "None" {
        match ty {
          Some(JTOption(_)) | None => Json::null()
          Some(other) => raise type_mismatch(loc, other.show(), "null")
        }
      } else {
        // §8 裁定（2026-10-07，#7/#9 实例前置）：无参构造器字面量入 L0——
        // 期望 enum 下降级投影 = 变体名字符串（serde 惯例）；jsonmbt 自持
        // 校验查变体表（拼错变体在本闸即红，补位 moon [4031] 防线）
        enum_case(enums, constr.name.name, ty, loc)
      }
    Unary(..) => raise not_literal(expr_loc(e), "unary operator expression")
    Infix(..) => raise not_literal(expr_loc(e), "arithmetic expression")
    If(..) => raise not_literal(expr_loc(e), "if expression")
    Ident(..) => raise not_literal(expr_loc(e), "identifier reference")
    Interp(..) => raise not_literal(expr_loc(e), "string interpolation")
    MultilineString(elems~, loc~) => {
      // §8 裁定（2026-10-07，#9）：#| 多行字符串入 L0——每行净内容以 \n
      // 连接（探针锚：元素形态 String(净行)，无换行符）；插值行属计算面拒
      let buf = StringBuilder()
      let mut first = true
      for el in elems {
        if el is @syntax.MultilineStringElem::String(s) {
          if not(first) {
            buf.write_char('\n')
          }
          buf.write_string(s)
          first = false
        } else {
          raise not_literal(loc, "multiline string with interpolation")
        }
      }
      match ty {
        Some(JTString) | None => Json::string(buf.to_string())
        Some(other) =>
          raise type_mismatch(loc, other.show(), "multiline string")
      }
    }
    _ => raise not_literal(expr_loc(e), "this expression")
  }
}

///|
/// 自定义名解析：JTStruct(n) 在 struct 表 miss 而 enum 表命中时改写为
/// JTEnum（parse_type 裸名统一产 JTStruct——enum/struct 在类型头同形，
/// 查表时分化）
fn resolve_custom(
  env : Map[String, StructDef],
  enums : Map[String, EnumDef],
  ty : JType,
) -> JType {
  match ty {
    JTStruct(n) =>
      if not(env.contains(n)) && enums.contains(n) {
        JTEnum(n)
      } else {
        ty
      }
    JTOption(t) => JTOption(resolve_custom(env, enums, t))
    JTArray(t) => JTArray(resolve_custom(env, enums, t))
    JTMap(k, v) => JTMap(k, resolve_custom(env, enums, v))
    other => other
  }
}

///|
/// 带 payload 构造器字面量（D-5 转正，§8 二次裁定 2026-10-07）：
/// 期望 enum 单参变体 → 降级投影 = tag 对象展开：
///   struct payload：{"case": 变体名, ...payload 字段展开进顶层}
///   标量 payload：{"case": 变体名, "value": payload}
/// tag 键冲突即拒（payload struct 含 "case" 字段 → J3008——D-5 规格：
/// 构造器名与 payload 键撞车显式报错，不静默覆盖）
fn payload_case(
  env : Map[String, StructDef],
  enums : Map[String, EnumDef],
  variant : String,
  payload : @syntax.Expr,
  ty : JType?,
  depth : Int32,
  loc : @basic.Location,
) -> Json raise Diag {
  match ty {
    Some(JTEnum(name)) | Some(JTOption(JTEnum(name))) => {
      // 变体存在性：带参变体在 EnumDef.payload_variants（与无参表分开收）
      let def = lookup_enum(enums, name, loc)
      if not(def.payload_variants.contains(variant)) {
        raise Diag(
          code=JFieldType,
          loc~,
          message="enum '\{name}' has no payload variant '\{variant}'",
          help=Some("payload variants: \{def.payload_variants.join(" ")}"),
          path="",
        )
      }
      // payload 求值：期望类型 = 该变体的形参类型（enum 定义处收）。
      // 形参为 enum 名时 parse_type 产 JTStruct 裸名——与 root/struct 字段
      // 侧同款 resolve_custom 查表分化（审阅 P2：曾漏，嵌套 payload 误报 J3004）
      let arg_ty = def.payload_types
        .get(variant)
        .map(fn(t) { resolve_custom(env, enums, t) })
      let pj = l0_expr(env, enums, payload, arg_ty, depth + 1)
      // tag 对象展开
      let obj : Map[String, Json] = Map([])
      match pj {
        Object(fields) => {
          if fields.contains("case") {
            raise Diag(
              code=JTagCollision,
              loc~,
              message="payload struct of '\{variant}' has a field named 'case' (tag key collision)",
              help=Some(
                "rename the field, or use a payload-less variant — the degraded object must carry the 'case' tag",
              ),
              path="",
            )
          }
          obj["case"] = Json::string(variant)
          fields.each(fn(k, v) { obj[k] = v })
          Json::object(obj)
        }
        other => {
          obj["case"] = Json::string(variant)
          obj["value"] = other
          Json::object(obj)
        }
      }
    }
    Some(other) =>
      raise type_mismatch(
        loc,
        other.show(),
        "payload variant '\{variant}'",
        help=Some("payload enum literals need an enum-typed field"),
      )
    None =>
      raise not_literal(loc, "payload variant '\{variant}' (no type context)")
  }
}

///|
fn lookup_enum(
  enums : Map[String, EnumDef],
  name : String,
  loc : @basic.Location,
) -> EnumDef raise Diag {
  match enums.get(name) {
    Some(def) => def
    None =>
      raise Diag(
        code=JFieldType,
        loc~,
        message="enum '\{name}' is not defined in this file",
        help=Some(
          ".json.mbt is single-file; declare the enum alongside the structs",
        ),
        path="",
      )
  }
}

///|
/// 无参构造器字面量的 enum 案（§8 裁定）：期望 JTEnum → 查变体表 →
/// 投影 = 变体名字符串；变体不存在 = J3004（jsonmbt 侧防线，对齐 moon
/// [4031] 的写时红）
fn enum_case(
  enums : Map[String, EnumDef],
  variant : String,
  ty : JType?,
  loc : @basic.Location,
) -> Json raise Diag {
  match ty {
    Some(JTEnum(name)) =>
      match enums.get(name) {
        Some(def) =>
          if def.variants.contains(variant) {
            Json::string(variant)
          } else {
            raise Diag(
              code=JFieldType,
              loc~,
              message="enum '\{name}' has no variant '\{variant}'",
              help=Some("variants of '\{name}': \{def.variants.join(" ")}"),
              path="",
            )
          }
        None =>
          raise Diag(
            code=JFieldType,
            loc~,
            message="enum '\{name}' is not defined in this file",
            help=Some(
              ".json.mbt is single-file; declare the enum alongside the structs",
            ),
            path="",
          )
      }
    Some(JTOption(inner)) => enum_case(enums, variant, Some(inner), loc)
    Some(other) =>
      raise type_mismatch(
        loc,
        other.show(),
        "enum variant '\{variant}'",
        help=Some("enum literals need an enum-typed field"),
      )
    None =>
      // 无类型上下文的裸构造器：语义不明（moon 侧同样无法定型），保守拒
      raise not_literal(loc, "enum variant '\{variant}' (no type context)")
  }
}

///|
fn l0_constant(
  c : @syntax.Constant,
  ty : JType?,
  loc : @basic.Location,
) -> Json raise Diag {
  match c {
    Int(raw) =>
      match ty {
        Some(JTInt) =>
          match numeric_text(raw) {
            Ok(_, v) =>
              if in_i32_range(v) {
                num_json(raw, loc)
              } else {
                raise type_mismatch(
                  loc,
                  "Int (32-bit)",
                  "\{raw}",
                  help=Some(
                    "change the field type to Int64, or use a value within ±2147483647",
                  ),
                )
              }
            Overflow(_) =>
              raise type_mismatch(
                loc,
                "Int (32-bit)",
                "\{raw}",
                help=Some(
                  "the value exceeds even Int64; keep exact digits by storing a String explicitly",
                ),
              )
            Illegal => num_json(raw, loc) // 交由 num_json 统一报 J3003
          }
        Some(JTInt64) =>
          match numeric_text(raw) {
            Ok(_, _) => num_json(raw, loc)
            Overflow(_) =>
              raise type_mismatch(
                loc,
                "Int64",
                "\{raw}",
                help=Some(
                  "the value exceeds Int64; keep exact digits by storing a String explicitly",
                ),
              )
            Illegal => num_json(raw, loc)
          }
        // 探针 p5：`d : Double = 1` 的 AST 是 Int 字面量——源文本直传（类型头是
        // 压缩侧元信息，不改写值文本——PLAN §0 第一性原理）
        Some(JTDouble) | None => num_json(raw, loc)
        Some(other) => raise type_mismatch(loc, other.show(), "Int literal")
      }
    Int64(raw) =>
      match ty {
        Some(JTInt64) | None => num_json(raw, loc)
        Some(other) => raise type_mismatch(loc, other.show(), "Int64 literal")
      }
    Double(raw) =>
      match ty {
        Some(JTDouble) | None => num_json(raw, loc)
        Some(other) => raise type_mismatch(loc, other.show(), "Double literal")
      }
    Bool(b) =>
      match ty {
        Some(JTBool) | None => Json::boolean(b)
        Some(other) =>
          raise type_mismatch(
            loc,
            other.show(),
            if b {
              "true"
            } else {
              "false"
            },
          )
      }
    String(raw) =>
      match ty {
        Some(JTString) | None => Json::string(unescape_string(raw, loc))
        Some(other) =>
          raise type_mismatch(
            loc,
            other.show(),
            "String literal",
            help=Some("change the field type to String, or remove the quotes"),
          )
      }
    Char(_) => raise bad_literal(loc, "Char")
    Byte(_) => raise bad_literal(loc, "Byte")
    Bytes(_) => raise bad_literal(loc, "Bytes")
    UInt(_) => raise bad_literal(loc, "UInt")
    UInt64(_) => raise bad_literal(loc, "UInt64")
    Float(_) => raise bad_literal(loc, "Float (JSON has no 32-bit float)")
    Regex(_) => raise bad_literal(loc, "Regex")
    BigInt(_) => raise bad_literal(loc, "BigInt")
  }
}

///|
fn bad_literal(loc : @basic.Location, what : String) -> Diag {
  Diag(
    code=JBadLiteral,
    loc~,
    message="\{what} literal has no JSON counterpart",
    help=Some("JSON values are null/bool/number/string/array/object only"),
    path="",
  )
}

///|
/// env 查表；缺定义即 raise（不用 get_or——default 立即求值会无条件 raise）
fn lookup_struct(
  env : Map[String, StructDef],
  name : String,
  loc : @basic.Location,
) -> StructDef raise Diag {
  match env.get(name) {
    Some(d) => d
    None => missing_struct(name, loc)
  }
}

///|
/// Record → JSON 对象；期望 struct 时做字段集校验（未知/缺失/重复）
fn l0_record(
  env : Map[String, StructDef],
  enums : Map[String, EnumDef],
  type_name : @syntax.TypeName?,
  fields : @list.List[@syntax.FieldDef],
  ty : JType?,
  depth : Int32,
  loc : @basic.Location,
) -> Json raise Diag {
  check_depth(depth, loc)
  // 定位本 record 的 schema：期望 struct 名 / 字面量类型名 / 自由对象（三者）
  let sd : StructDef? = match (ty, type_name) {
    (Some(JTStruct(n)), Some(tn)) => {
      let q = longident_name(tn.name)
      if q != n {
        raise type_mismatch(
          loc,
          n,
          q,
          help=Some("the record label must match the field type"),
        )
      }
      Some(lookup_struct(env, n, loc))
    }
    (Some(JTStruct(n)), None) => Some(lookup_struct(env, n, loc))
    (Some(other), _) =>
      raise type_mismatch(
        loc,
        other.show(),
        "record/object",
        help=Some(
          "wrap the value in the field's type, e.g. StructName::{ ... }",
        ),
      )
    (None, Some(tn)) => {
      let q = longident_name(tn.name)
      Some(lookup_struct(env, q, loc))
    }
    (None, None) => None
  }
  let obj : Map[String, Json] = Map([])
  for f in fields {
    let label = f.label.name
    // field-alias（#13）：struct 侧字段名 → 原始 JSON 键（注记承载；缺省恒等）
    let key = match sd {
      Some(d) =>
        match d.aliases.get(label) {
          Some(k) => k
          None => label
        }
      None => label
    }
    if obj.contains(key) {
      raise Diag(
        code=JDupField,
        loc=f.label.loc,
        message="duplicate field '\{label}'",
        help=Some(
          "merge the two values into one; a degraded object never carries duplicate keys",
        ),
        path="",
      )
    }
    let fty : JType? = match sd {
      Some(d) =>
        match d.fields.iter().find_first(fn(f) { f.0 == label }) {
          Some((_, t, _)) => Some(resolve_custom(env, enums, t))
          None =>
            raise Diag(
              code=JUnknownField,
              loc=f.label.loc,
              message="unknown field '\{label}'",
              help=Some("struct '\{d.name}' has fields: \{field_names(d)}"),
              path="",
            )
        }
      None => None
    }
    obj[key] = l0_expr(env, enums, f.expr, fty, depth + 1)
  }
  // 缺字段：record 字面量必须给全字段（Option 字段写 None——D-5 v1 先拒对齐）
  match sd {
    Some(d) =>
      for f in d.fields {
        let implied = match d.aliases.get(f.0) {
          Some(k) => k
          None => f.0
        }
        if !obj.contains(implied) {
          raise Diag(
            code=JMissingField,
            loc~,
            message="missing field '\{f.0}' in '\{d.name}'",
            help=Some(
              "provide the field explicitly; T? (Option) fields use None",
            ),
            path="",
          )
        }
      }
    None => ()
  }
  Json::object(obj)
}

///|
/// Map 字面量 → JSON 对象（键名逃生门的降级侧；key 必须 String 字面量）
fn l0_map(
  env : Map[String, StructDef],
  enums : Map[String, EnumDef],
  elems : @list.List[@syntax.MapExprElem],
  ty : JType?,
  depth : Int32,
  loc : @basic.Location,
) -> Json raise Diag {
  check_depth(depth, loc)
  let vty : JType? = match ty {
    Some(JTMap(k, v)) => {
      // JSON 键即字符串：非 String 键类型在类型头层即拒（Map 逃生门适用面）
      if !(k is JTString) {
        raise type_mismatch(
          loc,
          "Map[String, V]",
          "Map with non-String keys",
          help=Some("JSON object keys are strings; declare Map[String, V]"),
        )
      }
      Some(v)
    }
    Some(other) => raise type_mismatch(loc, other.show(), "map literal")
    None => None
  }
  let obj : Map[String, Json] = Map([])
  for el in elems {
    // #27：键取**解码值**（与 :554 字段值路径同款 unescape）——曾直拼源码
    // 原文，含 \ " 或转义序列的键（jest transform 正则键等）降级时被多转义
    // 一层 = 静默数据改写；重复键判定随之按解码值（D-11 值语义）
    let key = match el.key {
      String(raw) => unescape_string(raw, el.key_loc)
      other =>
        raise Diag(
          code=JMapKey,
          loc=el.key_loc,
          message="map key must be a string literal, got \{constant_shape(other)}",
          help=Some("JSON object keys are strings; quote the key"),
          path="",
        )
    }
    if obj.contains(key) {
      raise Diag(
        code=JDupField,
        loc=el.key_loc,
        message="duplicate key \"\{key}\"",
        help=Some(
          "merge the two entries; a degraded object never carries duplicate keys",
        ),
        path="",
      )
    }
    obj[key] = l0_expr(env, enums, el.expr, vty, depth + 1)
  }
  Json::object(obj)
}

///|
fn constant_shape(c : @syntax.Constant) -> String {
  match c {
    Bool(_) => "Bool"
    Int(_) => "Int"
    Int64(_) => "Int64"
    Double(_) => "Double"
    String(_) => "String"
    Char(_) => "Char"
    Byte(_) => "Byte"
    Bytes(_) => "Bytes"
    UInt(_) => "UInt"
    UInt64(_) => "UInt64"
    Float(_) => "Float"
    Regex(_) => "Regex"
    BigInt(_) => "BigInt"
  }
}

///|
/// 类型头引用了本文件未定义的 struct（L0 单文件自持，D-4）
fn missing_struct(name : String, loc : @basic.Location) -> StructDef raise Diag {
  raise Diag(
    code=JFieldType,
    loc~,
    message="struct '\{name}' is not defined in this file",
    help=Some(
      ".json.mbt is single-file and self-contained; define the struct here",
    ),
    path="",
  )
}

///|
fn field_names(d : StructDef) -> String {
  let buf = StringBuilder()
  for i, f in d.fields {
    if i > 0 {
      buf.write_string(", ")
    }
    buf.write_string(f.0)
  }
  buf.to_string()
}

///|
/// Expr 自带位置的便捷取用
fn expr_loc(e : @syntax.Expr) -> @basic.Location {
  @syntax.loc_of_expression(e)
}
