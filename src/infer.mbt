// 形状推断器（importer v1 核心）：Json 值树 → struct 集 + 顶层类型
// 规则全部来自 PLAN 终案：
//   形状签名判重（键集相同 = 同 struct，字段序 = 首见样本键序——输出确定性）／
//   同构数组 Array[T]／D-1 空容器两级启发（同签名组内样本 → 全文件同名字段 →
//   阻断 J4001）／D-2 跨样本无损上浮（任一样本超 Int → 全体 Int64；超 Int64
//   诚实拒绝 J4020；Int64+Double 混合拒绝——静默 Double 化 = 精度红线）／
//   键名逃生门（保留字/连字符/大写开头 → 同值类型对象转 Map[String,V]，
//   异值键阻断 J4011）／tagged-enum 单键 true/false/null 形态 hint（J4030，
//   rc 0 不阻断）／null → Option[T]（基型由其他样本聚合；全 null J4003）

///|
let reserved_labels : Array[String] = [
  "fn", "let", "mut", "const", "return", "match", "if", "else", "loop", "while",
  "for", "in", "break", "continue", "true", "false", "struct", "enum", "type", "trait",
  "impl", "pub", "priv", "package", "import", "test", "as", "extern", "raise", "try",
  "catch", "defer", "guard", "when", "extenum", "async", "backed", "where", "is",
  "unit",
]

///|
fn is_reserved_label(name : String) -> Bool {
  reserved_labels.contains(name)
}

///|
/// 合法字段 label：小写字母开头（snake/驼峰）/下划线开头/非 ASCII（中文）；
/// 大写开头非法（类型名域）、保留字非法（探针①）；
/// **全字符验证**——其余字符限 [a-zA-Z0-9_] 与非 ASCII（Vitro rules.json
/// 实锤：曾只验首字符，"memory.dump" 带点键直进产物 → J1001——审 A4
/// 形态的 label 通道变体）
fn is_legal_label(name : String) -> Bool {
  // "_" 单独非法（#32-3）：moon 字段位拒 _（通配符非标识符）——放行会让
  // 空键经 k+"_" 伪装合法、"_ " 键直出非法字段触发保险丝
  if name == "" || name == "_" || is_reserved_label(name) {
    return false
  }
  let chars = name.to_array()
  let first = chars[0]
  if !lident_start_ok(first) {
    return false
  }
  for i = 1; i < chars.length(); i = i + 1 {
    if !ident_continue_ok(chars[i]) {
      return false
    }
  }
  true
}

///|
/// moon 词法标识符区间表（lexer/regex.mbt 的 RE_LIDENT_START——#28：
/// 曾用「码点 ≥ 0x80 一律合法」近似，π(03C0)/А(0400)/א(05D0) 等**表外**
/// 字母被误判合法 → 直出非法 label 触发保险丝、报成 generator bug；
/// 修后表外键自动落入 Map 逃生门/保留字改名/J4011 既有分派。表内代表：
/// é(00E9) 中(4E2D) あ(3042) 가(AC00) 😀(1F600)；表外代表：π NBSP(U+3000
/// 空隙) 全角０(FF10)。勘误旧认知：「非 ASCII 一律合法」是过度概括）
let ident_ranges : Array[(Int, Int)] = [
  (0x5F, 0x5F), // _
  (0x61, 0x7A), // a-z
  (0xA1, 0xAC),
  (0xAE, 0x2AF),
  (0x1100, 0x11FF),
  (0x1E00, 0x1EFF),
  (0x2070, 0x209F),
  (0x2150, 0x218F),
  (0x2E80, 0x2EFF),
  (0x2FF0, 0x2FFF),
  (0x3001, 0x30FF),
  (0x31C0, 0x9FFF),
  (0xAC00, 0xD7FF),
  (0xF900, 0xFAFF),
  (0xFE00, 0xFE0F),
  (0xFE30, 0xFE4F),
  (0x1F000, 0x1FBFF),
  (0x20000, 0x2A6DF),
  (0x2A700, 0x2EBEF),
  (0x2F800, 0x2FA1F),
  (0x30000, 0x323AF),
  (0xE0100, 0xE01EF),
]

///|
fn in_ident_ranges(cp : Int) -> Bool {
  for r in ident_ranges {
    if cp >= r.0 && cp <= r.1 {
      return true
    }
  }
  false
}

///|
/// 首字符（RE_LIDENT_START）：_ / a-z / 区间表（无 0-9、无 A-Z）
fn lident_start_ok(c : Char) -> Bool {
  in_ident_ranges(c.to_int())
}

///|
/// 续字符（RE_IDENT_CONTINUE = 区间表 + 0-9 + A-Z）
fn ident_continue_ok(c : Char) -> Bool {
  let cp = c.to_int()
  (cp >= 0x30 && cp <= 0x39) ||
  (cp >= 0x41 && cp <= 0x5A) ||
  in_ident_ranges(cp)
}

///|
/// 确定性字段改名（对象内首见序）：合法键恒等；保留字 + "_"；与先前键的
/// 改名撞车则续加下划线（原生 where_ 顶到 where__）。真键由 field-alias
/// 注记承载（纯语法逆映射在尾下划线邻域数学上不可无歧义——注记是唯一全解）
/// 「可改名」判定 = walk_value:618 的 is_legal_label(k) || is_legal_label(k+"_")
/// 内联（原独立谓词 is_sanitizable_label 零调用死代码——#32-20 删除）
fn sanitize_field_label(key : String, taken : Array[String]) -> String {
  let mut cand = if is_legal_label(key) { key } else { key + "_" }
  while taken.contains(cand) {
    cand = cand + "_"
  }
  cand
}

///|
fn is_legal_type_name(name : String) -> Bool {
  if name == "" {
    return false
  }
  let first = name[0]
  first >= 'A' && first <= 'Z'
}

///|
fn capitalize(s : String) -> String {
  if s == "" {
    return s
  }
  let first = s[0]
  if first >= 'a' && first <= 'z' {
    (first.to_int() - 32).unsafe_to_char().to_string() + s[1:].to_owned()
  } else {
    s
  }
}

///|
priv struct FieldSamples {
  label : String
  samples : Array[SampleTy] // 同签名组内全部样本的字段贡献
}

///|
priv enum SampleTy {
  NullSample
  Ty(JType)
}

///|
priv struct ShapeGroup {
  fields : Array[FieldSamples] // 按首见样本键序（label 为改名后形态）
  field_index : Map[String, Int] // 原始 JSON 键 → 字段下标
  mut resolved_name : String // 定名后回填（walk 期间 JTStruct 名即此）
  keys : Array[String] // 首见键序——原始 JSON 键（#11：诊断报字段集差异；#14-3：容器路径分组）
  mut count : Int // 样本计数（分布计数——人工建模分组直接可用）
  paths : Array[String] // 出现过的容器路径（首见序去重——#14-3 按容器分组）
  path_counts : Map[String, Int] // 路径 → 该处样本计数（分组小计的真值）
}

///|
priv struct InferCtx {
  groups : Map[String, ShapeGroup]
  group_order : Array[String]
  used_type_names : Array[String]
  name_cache : Map[String, String] // 签名 → struct 名
  aliases : Array[(String, String, String)] // (struct 名, 改名后 label, 原始 JSON 键)——field-alias 注记（#13）
  map_escape_keys : Array[String] // 走了 Map 逃生门的非法键（首见序去重——J4011 文案点名键因）
  type_map : Map[String, String] // 派生名 → 用户语义名（--type-name-map，#6-4）
  map_hits : Array[String] // 命中的映射键（首见序——unmatched = 键集 - 命中集）
  map_value_hints : Map[String, String] // 容器路径 → 组名基名（Map 值对象宿主键派生，#6-4）
  derived_claimed : Array[String] // 已被映射消费的派生名（未发射但占位——#23：同基名异签名组不得重算同一 derived）
  strict : Bool // #14-2a：空容器严格档（--strict）——启发无解时如旧 J4001/J4002 拒
  mut uses_never : Bool // #14-2a：产物用到 Never 底型（codegen 据此发 enum 定义）
  hints : Array[Diag]
  hint_keys : Array[String] // tagged-enum 提示去重（按键名）
  taken : Array[String] // 同目录已占类型名（跨文件去重——issue #4）
  stem : String
  fname : String
}

///|
priv struct InferResult {
  structs : Array[(String, Array[(String, JType)])] // (struct 名, 字段表)
  root_ty : JType?
  hints : Array[Diag]
  aliases : Array[(String, String, String)] // (struct 名, label, 原始键)——codegen 发射注记用
  map_hits : Array[String] // --type-name-map 命中键集（#6-4）
  uses_never : Bool // #14-2a：空容器 Never 占位发生（产物含 enum Never 定义）
}

///|
fn signature_of_keys(keys : Array[String]) -> String {
  let sorted = keys.copy()
  sorted.sort()
  sorted.join("\u{1}")
}

///|
/// 主入口：值树 → struct 集 + 顶层类型（walk 收集 → 组定稿 → D-1 二级启发）
fn infer_shapes(
  root : Json,
  stem~ : String,
  fname? : String = "<json>",
  taken? : Array[String] = [],
  type_name_map? : Map[String, String] = Map([]),
  strict? : Bool = false,
) -> InferResult raise Diag {
  let ctx : InferCtx = {
    groups: Map([]),
    group_order: [],
    // #14-2a：Never 预留——{"never":{...}} 的派生名不得占用底型名
    used_type_names: ["Never"],
    name_cache: Map([]),
    aliases: [],
    map_escape_keys: [],
    type_map: type_name_map,
    map_hits: [],
    map_value_hints: Map([]),
    derived_claimed: [],
    strict,
    uses_never: false,
    hints: [],
    hint_keys: [],
    taken,
    stem,
    fname,
  }
  // 顶层对象组预命名 capitalize(stem)（config.json → Config——D-7 命名同源）
  prename_top_group(ctx, root)
  let mut root_ty = walk_value(ctx, root, path="$")
  finalize_empty_root(ctx, root_ty)
  // 组定稿（首见序 = 确定性）
  let structs : Array[(String, Array[(String, JType)])] = []
  let pending_empty : Array[(String, String)] = [] // (struct 名, 字段名)
  for sig in ctx.group_order {
    let g = ctx.groups[sig]
    let fields : Array[(String, JType)] = []
    for fs in g.fields {
      let ty = merge_samples(ctx, fs.samples, fs.label, allow_empty_arr=true)
      fields.push((fs.label, ty))
      if has_empty_array(ty) {
        pending_empty.push((g.resolved_name, fs.label))
      }
    }
    structs.push((g.resolved_name, fields))
  }
  // D-1 第二级启发：全文件同名字段的非空数组元素类型（规则写死进锚）
  for pair in pending_empty {
    let (name, label) = pair
    let mut resolved : JType? = None
    for s in structs {
      if s.0 != name {
        for f in s.1 {
          if f.0 == label {
            match strip_option(f.1) {
              JTArray(t) =>
                if !has_empty_array(t) {
                  resolved = Some(t)
                  break
                }
              _ => ()
            }
          }
        }
      }
      if resolved is Some(_) {
        break
      }
    }
    match resolved {
      Some(t) => patch_empty_array(structs, name, label, t)
      // #14-2a：启发无线索的「真孤立」空容器默认不再整张拒——残留
      // JTEmpty 交给收尾统一 Never 占位（--strict 时在收尾如旧 raise）
      None => ()
    }
  }
  // 收尾（#14-2a 统一占位点）：JTEmpty 中间态不得逃逸进产物——strict =
  // 原保险丝语义（fail loud）；默认 = 递归替换为 Never 底型（对零信息
  // 容器是数学精确刻画，非猜测占位；输出逐字节不变），D-1 两级启发
  // 优先级在前（能推精确类型的绝不出 Never）
  for s in structs {
    for i, f in s.1 {
      if has_empty_array(f.1) {
        if ctx.strict {
          raise empty_arr_diag(ctx, s.0, f.0)
        }
        s.1[i] = (f.0, replace_empty_array(f.1, never_ty(ctx)))
      }
    }
  }
  if has_empty_array(root_ty) {
    if ctx.strict {
      raise empty_arr_diag(ctx, "(top level)", "(elements)")
    }
    root_ty = replace_empty_array(root_ty, never_ty(ctx))
  }
  // #20 收尾断言（与 #14-2a 空容器保险丝同风格）：JTNullLike 只是聚合信号，
  // 不得进入产物类型位置——曾泄漏使 codegen 把 `null` 渲染成类型名（Array[null]
  // → J1001）。此断言把「靠调用方守约」变成「靠机器」：正常流程不可达
  // （字段位 merge_samples / 元素位 Array 分支均已聚合），命中即产品缺陷。
  for s in structs {
    for f in s.1 {
      if has_null_like(f.1) {
        raise null_leak_diag(ctx, s.0, f.0)
      }
    }
  }
  if has_null_like(root_ty) {
    raise null_leak_diag(ctx, "(top level)", "(elements)")
  }
  {
    structs,
    root_ty: Some(root_ty),
    hints: ctx.hints,
    aliases: ctx.aliases,
    map_hits: ctx.map_hits,
    uses_never: ctx.uses_never,
  }
}

///|
/// 类型里是否残留空容器中间态（穿透 JTOption/JTArray/JTMap——审 P1-3/4：
/// 只查最外层会漏 Array[?]? / Array[Array[?]]）
fn has_empty_array(t : JType) -> Bool {
  match t {
    JTEmpty => true
    JTOption(x) | JTArray(x) => has_empty_array(x)
    JTMap(_, v) => has_empty_array(v)
    _ => false
  }
}

///|
/// 类型里是否残留 JTNullLike（#20 收尾断言）：穿透 JTOption/JTArray/JTMap
/// （与 has_empty_array 同口径——只查最外层会漏 Array[T?] 里的中间态）
fn has_null_like(t : JType) -> Bool {
  match t {
    JTNullLike => true
    JTOption(x) | JTArray(x) => has_null_like(x)
    JTMap(_, v) => has_null_like(v)
    _ => false
  }
}

///|
/// null 泄漏诊断（#20 收尾断言命中 = 内部缺陷，非用户输入错）
fn null_leak_diag(ctx : InferCtx, name : String, label : String) -> Diag {
  Diag(
    code=JAllNull,
    loc=dummy_loc(),
    message="internal: null leaked into a type position (\{name}.\{label}) — the aggregating caller did not lift it to Option",
    help=Some(
      "please report this with the input JSON — null must be aggregated before reaching a type position",
    ),
    path=ctx.fname,
  )
}

///|
/// Never 底型引用（#14-2a）——JTStruct 裸名（build 回吃时经产物自带
/// enum Never {} 定义 resolve 分化为 JTEnum；零构造器 = 免费护栏：
/// 元素位写值会被 moon [4014] 与 jsonmbt J3004 双侧拦下）
fn never_ty(ctx : InferCtx) -> JType {
  ctx.uses_never = true
  note_never_hint(ctx)
  JTStruct("Never")
}

///|
/// 占位提示（rc-0，去重一次）：告诉人哪天有非空样本了把 Never 换成真类型
fn note_never_hint(ctx : InferCtx) -> Unit {
  if !ctx.hint_keys.contains("never-placeholder") {
    ctx.hint_keys.push("never-placeholder")
    ctx.hints.push(
      Diag(
        code=JNeverHint,
        loc=dummy_loc(),
        message="empty container placeholder: Array[Never] / Array[Never?] / Map[String, Never] — replace Never with the real element type once a non-empty sample exists (or re-import)",
        help=Some(
          "--strict rejects empty containers without clues (pre-0.1 behavior)",
        ),
        path=ctx.fname,
      ),
    )
  }
}

///|
fn strip_option(t : JType) -> JType {
  match t {
    JTOption(x) => strip_option(x)
    other => other
  }
}

///|
fn prename_top_group(ctx : InferCtx, root : Json) -> Unit raise Diag {
  if root is Object(o) && o.length() > 0 {
    let keys : Array[String] = []
    o.each(fn(k, _) { keys.push(k) })
    let sig = signature_of_keys(keys)
    let name = alloc_type_name(ctx, capitalize(ctx.stem))
    ctx.name_cache[sig] = name
  }
}

///|
/// 顶层裸值兜底：JTNullLike/JTEmpty 出现在顶层 = 无类型可推（穿透容器）
fn finalize_empty_root(ctx : InferCtx, root_ty : JType) -> Unit raise Diag {
  if root_ty is JTNullLike {
    raise all_null_diag(ctx, "(top level)")
  }
  if has_empty_array(root_ty) && ctx.strict {
    // #14-2a：顶层空容器 strict 档如旧拒；默认交收尾统一 Never 占位
    raise empty_arr_diag(ctx, "(top level)", "(elements)")
  }
}

///|
/// #6-4：--type-name-map 语义错诊断（值非法/撞名）
fn bad_name_map_diag(ctx : InferCtx, msg : String) -> Diag raise Diag {
  raise Diag(
    code=JBadNameMap,
    loc=dummy_loc(),
    message="type-name-map error: \{msg}",
    help=Some(
      "keys are the auto-derived names from a first import; values must be legal, unused MoonBit type names",
    ),
    path=ctx.fname,
  )
}

///|
fn alloc_type_name(ctx : InferCtx, base : String) -> String raise Diag {
  // issue #4：嵌套 struct 机器派生名（Id/Code 等）在同目录多文件时撞
  // moon 包命名空间——后来者加 stem 前缀（先到先得，单文件零变化）
  let primed0 = if is_legal_type_name(base) { base } else { "Root" }
  let derived : String = if ctx.taken.contains(primed0) &&
    primed0 != capitalize(ctx.stem) {
    let prefixed = capitalize(ctx.stem) + primed0
    if is_legal_type_name(prefixed) && !slot_taken(ctx, prefixed) {
      prefixed
    } else {
      dedup_fallback(ctx, primed0)
    }
  } else {
    dedup_fallback(ctx, primed0)
  }
  // #6-4：派生名过语义映射——键 = 最终派生名（用户在首次 import 产物里
  // 看到的形态）；值校验 fail loud（非法/撞已占），命中记录供 unmatched 报告
  match ctx.type_map.get(derived) {
    Some(user) => {
      if !is_legal_type_name(user) {
        raise bad_name_map_diag(
          ctx,
          "'\{derived}' → '\{user}': not a legal type name (expect an Uppercase start)",
        )
      }
      // #23：撞名判据只对**发射名**（used_type_names）——derived 已被替换未发射，
      // 不得因它占位而误拒（否则 {"Bar":"Status"} 这类合法映射被假撞）
      if ctx.used_type_names.contains(user) ||
        (ctx.taken.contains(user) && user != capitalize(ctx.stem)) {
        raise bad_name_map_diag(
          ctx,
          "'\{derived}' → '\{user}': collides with another type in this file or directory",
        )
      }
      if !ctx.map_hits.contains(derived) {
        ctx.map_hits.push(derived)
      }
      // #23：派生名虽被替换未发射，仍须占位——否则同基名的**异签名**组下次
      // dedup 会再算出同一个 derived、再命中同一条映射 → 假撞（MoUI linux.json）
      if !ctx.derived_claimed.contains(derived) {
        ctx.derived_claimed.push(derived)
      }
      ctx.used_type_names.push(user)
      user
    }
    None => {
      ctx.used_type_names.push(derived)
      derived
    }
  }
}

///|
/// 派生名占位判定（#23/#24）：发射名 ∪ 被映射消费的派生名 ∪ 同目录别文件已占名
/// （taken，本文件顶层 stem 名除外——与前缀化判据同款豁免）。仅供 dedup/prefixed
/// 选名，**不**用于映射值的撞名判据（后者只看发射名——见 alloc_type_name）
fn slot_taken(ctx : InferCtx, n : String) -> Bool {
  ctx.used_type_names.contains(n) ||
  ctx.derived_claimed.contains(n) ||
  (ctx.taken.contains(n) && n != capitalize(ctx.stem))
}

///|
/// 去重兜底：primed 可用即用；被占则后缀 2/3/…（首见序确定性）
fn dedup_fallback(ctx : InferCtx, primed : String) -> String {
  if !slot_taken(ctx, primed) {
    return primed
  }
  let mut i = 2
  let mut candidate = ""
  while true {
    let c = "\{primed}\{i}"
    if !slot_taken(ctx, c) {
      candidate = c
      break
    }
    i = i + 1
  }
  candidate
}

///|
/// 容器路径尾段（宿主字段名提取，#6-4）：$.cases → cases；$ / …[] / 尾段
/// 非法形态 → ""（无宿主——调用方 fallback）
fn last_path_segment(path : String) -> String {
  match path.rev_find(".") {
    Some(i) => {
      let seg = path[i + 1:].to_owned()
      if seg == "" || seg.contains("[") || seg.contains("]") {
        ""
      } else {
        seg
      }
    }
    None => ""
  }
}

///|
/// 单值类型化（walk 全树；对象按可表达性分流：全合法/可改名键 → struct 组、
/// 其余非法键 → Map 逃生门）。path 为容器路径（$ 键锚——#14-3 分组用）
fn walk_value(
  ctx : InferCtx,
  j : Json,
  path? : String = "$",
) -> JType raise Diag {
  match j {
    Null => JTNullLike // 值位 null：上层样本聚合决定 Option
    True | False => JTBool
    Number(_, repr~) =>
      match repr {
        Some(t) =>
          if t.contains(".") || t.contains("e") || t.contains("E") {
            JTDouble
          } else {
            match numeric_text(t) {
              Ok(_, v) => if in_i32_range(v) { JTInt } else { JTInt64 }
              Overflow(_) => raise big_num_diag(ctx, t)
              Illegal => JTDouble // 理论不可达（自持解析器保证纯十进制）
            }
          }
        None => JTDouble
      }
    String(_) => JTString
    Array(elems) => {
      if elems.length() == 0 {
        return JTArray(JTEmpty)
      }
      let elem_path = path + "[]"
      // #20：元素位与字段位同口径——null 单独计数后聚 Option。
      // 旧实现直接调 lub，而 lub 的 `(JTNullLike, t) => t` 是「调用方已完成
      // Option 聚合」的契约（见 :730 注释）——元素位无人履行 → null 被静默
      // 丢弃，[null,1,2] 产出非法 .json.mbt（J0002 generator bug），
      // [null,null] 更把 JTNullLike 渲染成类型名 `null`。
      let mut elem : JType? = None
      let mut nulls = 0
      for e in elems {
        let t = walk_value(ctx, e, path=elem_path)
        if t is JTNullLike {
          nulls = nulls + 1
        } else {
          elem = Some(
            match elem {
              None => t
              Some(prev) => lub(ctx, prev, t, in_array=true)
            },
          )
        }
      }
      // 全 null 数组 = 零信息 + 可空 → Never?（#14-2a Never 底型范式的
      // 可空扩展；Array[Never?] 降级 [null,...] 无损）。直接给 never_ty
      // 而非 JTEmpty——replace_empty_array 把裸 JTEmpty 视作「数组本身为空」，
      // JTOption(JTEmpty) 会被它错解成 Array[Array[Never]?]。
      let base = match elem {
        None => never_ty(ctx)
        Some(t) => t
      }
      JTArray(if nulls > 0 { JTOption(base) } else { base })
    }
    Object(o) => {
      let keys : Array[String] = []
      o.each(fn(k, _) { keys.push(k) })
      if keys.length() == 0 {
        // #14-2a：空对象默认 Map[String, Never] 占位（零信息容器的精确
        // 刻画）；--strict 如旧 J4002 拒（D-1 终案形态收窄解释见 PLAN §6）
        if ctx.strict {
          raise empty_obj_diag(ctx)
        }
        return JTMap(JTString, never_ty(ctx))
      }
      register_tagged_enum_hint(ctx, keys, o)
      // 键分流（#13）：保留字类可改名键（where → where_）随 struct 走，
      // 原始键由 field-alias 注记承载；不可改名形态（点号/大写开头等）
      // 维持 Map 逃生门，键因登记供 J4011 文案点名
      let sanitizable = keys.all(fn(k) {
        is_legal_label(k) || is_legal_label(k + "_")
      })
      if sanitizable {
        walk_as_struct(ctx, keys, o, path~)
      } else {
        for k in keys {
          if !is_legal_label(k) && !is_legal_label(k + "_") {
            if !ctx.map_escape_keys.contains(k) {
              ctx.map_escape_keys.push(k)
            }
          }
        }
        // 键名逃生门：非 String 值类型聚合（同构 → Map；异值键 J4011）。
        // 值位对象的组名基名预登记**宿主字段**派生（#6-4 拍板：cases 值 →
        // CasesEntry——Map 持有者的名字才是语义锚；条目键（a.c）无语义）。
        // 宿主 = 当前 path 尾段（$.cases → cases）；数组位/顶层无宿主 →
        // 不登记，组名 fallback 首键派生（首见定型，确定性保持）
        let host = last_path_segment(path)
        let samples : Array[SampleTy] = []
        let ks : Array[String] = []
        o.each(fn(k, _) { ks.push(k) })
        for k in ks {
          let v = o.get(k).unwrap()
          if v is Object(_) && host != "" {
            let hint_path = path + "." + k
            if !ctx.map_value_hints.contains(hint_path) {
              ctx.map_value_hints[hint_path] = capitalize(sanitize_stem(host)) +
                "Entry"
            }
          }
          let t = walk_value(ctx, v, path=path + "." + k)
          samples.push(if t is JTNullLike { NullSample } else { Ty(t) })
        }
        JTMap(
          JTString,
          merge_samples(
            ctx,
            samples,
            "(map values)",
            allow_empty_arr=false,
            at_map=true,
          ),
        )
      }
    }
  }
}

///|
/// tagged-enum hint：恰一键、大写开头、值 true/false/null（{Void: true} 家族）
fn register_tagged_enum_hint(
  ctx : InferCtx,
  keys : Array[String],
  o : Map[String, Json],
) -> Unit {
  if keys.length() != 1 {
    return
  }
  let k = keys[0]
  // 空键守卫（#32-3）：k[0] 对空串越界 panic——绕过 J 码通道与 rc 五值；
  // 空键本身也非 tag 形态（大写开头），提前返回
  if k == "" {
    return
  }
  let first = k[0]
  let looks_tag = first >= 'A' &&
    first <= 'Z' &&
    o.get(k) is Some(True | False | Null)
  if looks_tag {
    // 去重（审 P3）：同形态多次出现只提示一次
    if ctx.hint_keys.contains(k) {
      return
    }
    ctx.hint_keys.push(k)
    ctx.hints.push(
      Diag(
        code=JTaggedEnumHint,
        loc=dummy_loc(),
        message="object looks like a tagged-enum constructor ('\{k}': ...)",
        help=Some(
          "consider hand-writing a MoonBit enum instead; jsonmbt imported it as-is",
        ),
        path=ctx.fname,
      ),
    )
  }
}

///|
fn walk_as_struct(
  ctx : InferCtx,
  keys : Array[String],
  o : Map[String, Json],
  path? : String = "$",
) -> JType raise Diag {
  // 签名 = 原始 JSON 键集（键集语义属 JSON 真相；改名只发生在 label 侧）
  let sig = signature_of_keys(keys)
  if !ctx.groups.contains(sig) {
    let g : ShapeGroup = {
      fields: [],
      field_index: Map([]),
      resolved_name: "",
      keys,
      count: 0,
      paths: [],
      path_counts: Map([]),
    }
    let labels : Array[String] = []
    let pairs : Array[(String, String)] = [] // (改名后 label, 原始键)
    for k in keys {
      let lbl = sanitize_field_label(k, labels)
      labels.push(lbl)
      pairs.push((lbl, k))
      g.field_index[k] = g.fields.length()
      g.fields.push({ label: lbl, samples: [], })
    }
    ctx.groups[sig] = g
    ctx.group_order.push(sig)
    // 命名：预命名（顶层）优先；Map 值对象用宿主键派生基名（#6-4——
    // cases 的值是完整条目，首键派生 Src_sha 误导）；否则组首**原始**键
    // capitalize（where → Where——大写保留字派生类型名合法，探针实锚）
    if !ctx.name_cache.contains(sig) {
      let base = match ctx.map_value_hints.get(path) {
        Some(hint) => hint
        None =>
          if g.keys.length() > 0 {
            capitalize(g.keys[0])
          } else {
            capitalize(ctx.stem)
          }
      }
      ctx.name_cache[sig] = alloc_type_name(ctx, base)
    }
    let name = ctx.name_cache[sig]
    ctx.groups[sig].resolved_name = name
    // 非恒等改名登记进 field-alias 集（组序 = 首见序，确定性）
    for pair in pairs {
      let (lbl, k) = pair
      if lbl != k {
        ctx.aliases.push((name, lbl, k))
      }
    }
  }
  let g = ctx.groups[sig]
  g.count = g.count + 1
  if !g.paths.contains(path) {
    g.paths.push(path)
  }
  g.path_counts[path] = match g.path_counts.get(path) {
    Some(n) => n + 1
    None => 1
  }
  let ks : Array[String] = []
  o.each(fn(k, _) { ks.push(k) })
  for k in ks {
    let t = walk_value(ctx, o.get(k).unwrap(), path=path + "." + k)
    g.fields[g.field_index[k]].samples.push(
      if t is JTNullLike {
        NullSample
      } else {
        Ty(t)
      },
    )
  }
  JTStruct(g.resolved_name)
}

///|
/// 样本聚合 → 字段类型（null → Option；全 null J4003；空数组可容忍项待二级启发）
fn merge_samples(
  ctx : InferCtx,
  samples : Array[SampleTy],
  label : String,
  allow_empty_arr~ : Bool,
  at_map? : Bool = false,
) -> JType raise Diag {
  let mut acc : JType? = None
  let mut nulls = 0
  for s in samples {
    match s {
      NullSample => nulls = nulls + 1
      Ty(t) =>
        acc = Some(
          match acc {
            None => t
            Some(prev) => lub(ctx, prev, t, in_array=false, at_map~)
          },
        )
    }
  }
  let base = match acc {
    None => raise all_null_diag(ctx, label)
    Some(t) => t
  }
  let with_opt = if nulls > 0 { JTOption(base) } else { base }
  if !allow_empty_arr && has_empty_array(with_opt) {
    // Map 值位空数组：strict 如旧拒；默认穿透 JTEmpty 中间态交给收尾
    // 统一 Never 占位（has_empty_array 穿透 JTMap——收尾能抓到）
    if ctx.strict {
      raise empty_arr_diag(ctx, "(map)", label)
    }
  }
  with_opt
}

///|
/// 类型合流（lub）：D-2 跨样本上浮；Int64+Double 拒绝（精度红线）；异构 J4010/J4012
fn lub(
  ctx : InferCtx,
  a : JType,
  b : JType,
  in_array~ : Bool,
  at_map? : Bool = false,
) -> JType raise Diag {
  match (a, b) {
    (JTInt, JTInt) => JTInt
    (JTInt, JTInt64) | (JTInt64, JTInt) | (JTInt64, JTInt64) => JTInt64
    (JTDouble, JTDouble) => JTDouble
    (JTInt, JTDouble) | (JTDouble, JTInt) => JTDouble
    (JTInt64, JTDouble) | (JTDouble, JTInt64) =>
      raise Diag(
        code=JBigNum,
        loc=dummy_loc(),
        message="Int64 and Double in the same aggregate: widening would silently lose precision",
        help=Some("store the numbers consistently, or hand-model the field"),
        path=ctx.fname,
      )
    (JTString, JTString) => JTString
    (JTBool, JTBool) => JTBool
    (JTEmpty, t) | (t, JTEmpty) => t // 空容器贡献无约束（D-1 启发链前置）
    (JTArray(t1), JTArray(t2)) => JTArray(lub(ctx, t1, t2, in_array~, at_map~))
    (JTStruct(s1), JTStruct(s2)) =>
      if s1 == s2 {
        JTStruct(s1)
      } else {
        // 键集漂移（缺键致签名分裂）是 D-5 域。#11：报**字段集差异 + 分布
        // 计数**（用户视角的真相），不泄漏派生类型名（Src_sha/Src_sha2
        // 是 shape inference 内部命名，无法定位）
        raise keyset_drift_diag(ctx, in_array, at_map)
      }
    (JTMap(_, v1), JTMap(_, v2)) =>
      JTMap(JTString, lub(ctx, v1, v2, in_array~, at_map~))
    (JTNullLike, t) | (t, JTNullLike) => t // null 由上层聚合 Option
    // 审 P1-a：#20 元素位自聚合后 JTOption 首次流入 lub（旧实现靠
    // (JTNullLike,t) 静默吞掉的空洞被暴露——Int? vs Int? 落 hetero）。
    // Option 外壳合流：内层递归 lub（同型保型、Int/Int64 上浮等语义
    // 不变）；null 由上方 NullLike 臂先行兜底（不收紧内层）
    (JTOption(x), JTOption(y)) =>
      JTOption(lub(ctx, x, y, in_array~, at_map~))
    (JTOption(x), t) | (t, JTOption(x)) =>
      JTOption(lub(ctx, x, t, in_array~, at_map~))
    _ => raise hetero_diag(ctx, in_array, "\{a.show()} vs \{b.show()}", at_map~)
  }
}

///|
/// 键集漂移诊断（#11 报字段集差异 + 分布计数；#14-3 按容器路径分组——
/// 顶层/嵌套单样本键集不再与数组元素混计，报「真漂移在哪」）
fn keyset_drift_diag(
  ctx : InferCtx,
  in_array : Bool,
  at_map : Bool,
) -> Diag raise Diag {
  // 全部容器路径（首见序去重）
  let paths : Array[String] = []
  for sig in ctx.group_order {
    let g = ctx.groups[sig]
    for p in g.paths {
      if !paths.contains(p) {
        paths.push(p)
      }
    }
  }
  // 按路径分组：同容器 ≥2 键集 = 真漂移（计数取该路径的小计——path_counts）
  let sections : Array[String] = []
  for p in paths {
    let rows : Array[String] = []
    let mut total = 0
    for sig in ctx.group_order {
      let g = ctx.groups[sig]
      let n = match g.path_counts.get(p) {
        Some(n) => n
        None => 0
      }
      if n > 0 {
        rows.push("×\{n} { \{g.keys.join(", ")} }")
        total = total + n
      }
    }
    if rows.length() >= 2 {
      // 计数降序（稳定：同数按首见序）
      let sorted = rows.copy()
      sorted.sort_by(fn(a, b) { cmp_rows(b, a) })
      sections.push(
        "at \{p}: \{sorted.length()} distinct key sets in \{total} samples: \{sorted.join("; ")}",
      )
    }
  }
  let dist = if sections.length() > 0 {
    sections.join(" | ")
  } else {
    // 退化面（跨路径合流撞形，无同容器漂移）：全量平铺兜底——如实报
    let rows : Array[String] = []
    let mut total = 0
    for sig in ctx.group_order {
      let g = ctx.groups[sig]
      if g.count > 0 {
        rows.push("×\{g.count} { \{g.keys.join(", ")} }")
        total = total + g.count
      }
    }
    let sorted = rows.copy()
    sorted.sort_by(fn(a, b) { cmp_rows(b, a) })
    "\{sorted.length()} distinct key sets in \{total} samples: \{sorted.join("; ")}"
  }
  raise Diag(
    code=if in_array {
      JHeteroArr
    } else if at_map {
      JMixedKeys
    } else {
      JHeteroField
    },
    loc=dummy_loc(),
    message="incompatible object shapes across samples (D-5 key-set drift): \{dist}",
    help=Some(
      "key-set drift is not auto-converted — hand-model each key set as an enum variant (D-5), or make the samples uniform; counts cover samples seen up to the first conflicting merge (the scan stops there), so treat them as lower bounds",
    ),
    path=ctx.fname,
  )
}

///|
fn cmp_rows(a : String, b : String) -> Int {
  // "×602 { ... }" 前缀数字比较
  fn count_of(s : String) -> Int {
    let stop = match s.find(" ") {
      Some(i) => i
      None => s.length()
    }
    let mut v = 0
    for c in s[1:stop] {
      if c < '0' || c > '9' {
        return 0
      }
      v = v * 10 + (c.to_int() - '0'.to_int())
    }
    v
  }
  count_of(a).compare(count_of(b))
}

///|
fn hetero_diag(
  ctx : InferCtx,
  in_array : Bool,
  what : String,
  at_map? : Bool = false,
) -> Diag raise Diag {
  // Map 逃生门路径的失败须点名键因（#13 文案错位修复）：真因是「键不是
  // 合法字段名 → 整对象被退化为 Map、异型值无法统一」，不是跨样本异构
  if at_map && ctx.map_escape_keys.length() > 0 {
    raise Diag(
      code=JMixedKeys,
      loc=dummy_loc(),
      message="cannot unify values under keys that are not legal MoonBit field labels (\{ctx.map_escape_keys.map(fn(k) { "'\{k}'" }).join(", ")}): \{what}",
      help=Some(
        "these keys force Map degradation (heterogeneous values cannot unify) — rename the keys in the JSON, or hand-write a struct",
      ),
      path=ctx.fname,
    )
  }
  raise Diag(
    code=if in_array {
      JHeteroArr
    } else if at_map {
      JMixedKeys // 异值键：Map 逃生门不适用（PLAN §6 键名逃生门适用面写死）
    } else {
      JHeteroField
    },
    loc=dummy_loc(),
    message="incompatible types across samples: \{what}",
    help=Some("split the data, or hand-write a struct with a precise type"),
    path=ctx.fname,
  )
}

///|
fn empty_arr_diag(
  ctx : InferCtx,
  sname : String,
  label : String,
) -> Diag raise Diag {
  raise Diag(
    code=JEmptyArr,
    loc=dummy_loc(),
    message="empty array with no element-type clue (struct '\{sname}', field '\{label}')",
    help=Some(
      "provide one non-empty sample for this field in the JSON (or hand-write the struct)",
    ),
    path=ctx.fname,
  )
}

///|
fn empty_obj_diag(ctx : InferCtx) -> Diag raise Diag {
  raise Diag(
    code=JEmptyObj,
    loc=dummy_loc(),
    message="empty object: no fields to infer a struct from",
    help=Some("give the object at least one field, or model it by hand"),
    path=ctx.fname,
  )
}

///|
fn all_null_diag(ctx : InferCtx, label : String) -> Diag raise Diag {
  raise Diag(
    code=JAllNull,
    loc=dummy_loc(),
    message="all samples are null: Option base type unknown ('\{label}')",
    help=Some(
      "provide one non-null sample, or hand-model the field as T? (Option)",
    ),
    path=ctx.fname,
  )
}

///|
fn big_num_diag(ctx : InferCtx, text : String) -> Diag raise Diag {
  raise Diag(
    code=JBigNum,
    loc=dummy_loc(),
    message="integer '\{text}' exceeds Int64",
    help=Some(
      "jsonmbt degrades numbers losslessly; to keep >Int64 digits, store a JSON string and import it as String",
    ),
    path=ctx.fname,
  )
}

///|
fn patch_empty_array(
  structs : Array[(String, Array[(String, JType)])],
  sname : String,
  label : String,
  t : JType,
) -> Unit {
  for s in structs {
    if s.0 == sname {
      for i, f in s.1 {
        if f.0 == label && has_empty_array(f.1) {
          s.1[i] = (label, replace_empty_array(f.1, t))
        }
      }
    }
  }
}

///|
/// 递归替换空容器中间态（穿透 JTOption/JTArray/JTMap——审 P1-3/4）
fn replace_empty_array(t : JType, elem : JType) -> JType {
  match t {
    JTEmpty | JTArray(JTEmpty) => JTArray(elem)
    JTOption(x) => JTOption(replace_empty_array(x, elem))
    JTArray(x) => JTArray(replace_empty_array(x, elem))
    JTMap(k, v) => JTMap(k, replace_empty_array(v, elem))
    other => other
  }
}
