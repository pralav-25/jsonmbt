// 类型环境：文件内 struct 定义表 + MoonBit Type AST → jsonmbt 内部类型
// 自持校验器（D-3）的类型面——不跑 moon check 也能做「类型即 Schema」校验

///|
/// jsonmbt 认识的字段类型全集（L0 子集的类型面）。
/// Int 按 MoonBit 实测为 32 位（真实编译界 2^31-1，PLAN §6 数值边界）；
/// 界检查在值校验处做，这里只记形态。
priv enum JType {
  JTInt
  JTInt64
  JTDouble
  JTString
  JTBool
  JTOption(JType)
  JTArray(JType)
  JTMap(JType, JType) // K 仅接受 String（JSON 键即字符串；Map 逃生门适用面）
  JTStruct(String)
  JTEnum(String) // enum 名（§8 裁定 2026-10-07：无参构造器字面量入 L0，#7/#9 实例前置）
  JTUnsupported(String) // 表达了但 L0 不支持的类型（Unit/Arrow/Tuple/Any/未知名…）
  JTEmpty // 推断器内部中间态：空容器元素占位（推断定稿前消除，不进校验器）
  JTNullLike // 推断器内部中间态：值位 null 的占位（聚合前消除）
} derive(Eq)

///|
fn JType::show(self : JType) -> String {
  match self {
    // #34：规范拼写 Int32——moon fmt（0.1.20261012+）归一化类型位置
    // Int→Int32/UInt→UInt32，产出跟随否则 #18 fmt 不动点恒破；语义零变化
    //（Int 系 Int32 别名，探针 moon check 双向赋值/泛型互传实证同型）
    JTInt => "Int32"
    JTInt64 => "Int64"
    JTDouble => "Double"
    JTString => "String"
    JTBool => "Bool"
    JTOption(t) => "\{t.show()}?"
    JTArray(t) => "Array[\{t.show()}]"
    JTMap(k, v) => "Map[\{k.show()}, \{v.show()}]"
    JTStruct(n) => n
    JTEnum(n) => n
    JTUnsupported(s) => s
    JTEmpty => "?"
    JTNullLike => "null"
  }
}

///|
priv struct StructDef {
  name : String
  fields : Array[(String, JType, @basic.Location)] // (label, 类型, 字段位置)
  aliases : Map[String, String] // label → 原始 JSON 键（#13 field-alias 注记；默认空 = 恒等）
}

///|
/// enum 定义（Variant 形态）：v1 只收**无参**构造器（带参投影无自然
/// JSON 形态，挂观察——§8 裁定附带；带参 enum 定义本身合法入表、
/// 字面量侧拒）
priv struct EnumDef {
  name : String
  variants : Array[String] // 无参构造器名（降级投影 = 变体名字符串）
  payload_variants : Array[String] // 带单参构造器名（D-5 转正：tag 对象展开）
  payload_types : Map[String, JType] // 变体名 → 形参类型（payload 求值期望）
}

///|
/// 类型环境（struct 表 + enum 表——l0 查表校验变体存在性）
priv struct TypeEnv {
  structs : Map[String, StructDef]
  enums : Map[String, EnumDef]
}

///|
/// 从顶层声明收集 struct 定义。不认识的 TypeDecl 形态（enum/alias/abstract…）
/// 不进表——引用到时按 JTUnsupported 报；顶层混入非 struct 声明由 document 层把关。
fn collect_tyenv(impls : @list.List[@syntax.Impl]) -> TypeEnv raise Diag {
  let structs : Map[String, StructDef] = Map([])
  let enums : Map[String, EnumDef] = Map([])
  for i in impls {
    match i {
      TopTypeDef(decl) =>
        match decl.components {
          Record(fields~, ..) => {
            let name = decl.tycon
            // 双向查重（#32-11）：struct 撞 enum 同为 J2006——Record 臂曾只查
            // structs，enum 在前时漏报（同族双臂不对称，判定随声明顺序翻转）
            if structs.contains(name) || enums.contains(name) {
              raise Diag(
                code=JDupStruct,
                loc=decl.loc,
                message="duplicate struct definition '\{name}'",
                help=Some(
                  "rename one of the structs; .json.mbt keeps one schema per name",
                ),
                path="",
              )
            }
            let fs : Array[(String, JType, @basic.Location)] = []
            for f in fields {
              fs.push((f.name.label, parse_type(f.ty), f.loc))
            }
            structs[name] = { name, fields: fs, aliases: Map([]), }
          }
          Variant(ctors) => {
            // enum：无参构造器收进变体表；带参（ConsDecl.args 非空）拒收该变体
            let name = decl.tycon
            if enums.contains(name) || structs.contains(name) {
              raise Diag(
                code=JDupStruct,
                loc=decl.loc,
                message="duplicate type definition '\{name}'",
                help=Some(
                  "rename one of the types; .json.mbt keeps one schema per name",
                ),
                path="",
              )
            }
            let vs : Array[String] = []
            let pvs : Array[String] = []
            let pts : Map[String, JType] = Map([])
            for c in ctors {
              match c.args {
                Some(arg_list) => {
                  // D-5 转正：恰单形参的构造器入 payload 表（多参仍拒——
                  // 降级投影单值语义装不下多参）
                  let arr = arg_list.to_array()
                  if arr.length() == 1 {
                    pvs.push(c.name.name)
                    pts[c.name.name] = parse_type(arr[0].ty)
                  }
                }
                None => vs.push(c.name.name)
              }
            }
            enums[name] = {
              name,
              variants: vs,
              payload_variants: pvs,
              payload_types: pts,
            }
          }
          _ => () // 其余 TypeDecl 形态：引用到时按 JTUnsupported 报
        }
      _ => ()
    }
  }
  { structs, enums, }
}

///|
/// LongIdent → 点分名字（仅本地名合法——跨包引用不属于 L0）
fn longident_name(id : @syntax.LongIdent) -> String {
  match id {
    Ident(name~) => name
    Dot(pkg~, id~) => "\{pkg}.\{id}"
  }
}

///|
fn parse_type(t : @syntax.Type) -> JType {
  match t {
    Name(constr_id~, tys~, ..) => {
      let id = longident_name(constr_id.id)
      let params = tys.to_array() // List 构造器不公开——数组化再判 arity
      match (id, params.length()) {
        // #34：双拼写识别——规范形 Int32 + 存量手写 Int（同型别名，check 兼容不破）
        ("Int", 0) | ("Int32", 0) => JTInt
        ("Int64", 0) => JTInt64
        ("Double", 0) => JTDouble
        ("String", 0) => JTString
        ("Bool", 0) => JTBool
        ("Array", 1) => JTArray(parse_type(params[0]))
        ("Map", 2) => JTMap(parse_type(params[0]), parse_type(params[1]))
        ("Unit", 0)
        | ("Byte", 0)
        | ("Char", 0)
        | ("UInt", 0)
        | ("UInt32", 0)
        // fmt 归一拼写——不列则被 struct 分支误吞、诊断劣化
        | ("UInt64", 0)
        | ("Float", 0) => JTUnsupported(type_show_of(t)) // 有 MoonBit 定义但 JSON 无对应/非 L0 的内建
        (_, 0) => JTStruct(id) // 自定义 struct（无参裸名）；未定义名由 lookup_struct 报
        _ => JTUnsupported(type_show_of(t))
      }
    }
    Option(ty~, ..) => JTOption(parse_type(ty))
    _ => JTUnsupported(type_show_of(t))
  }
}

///|
/// 类型源形渲染仅用于诊断展示：未支持类型给原文提示（够用即可，不追求源文本级还原）
fn type_show_of(_t : @syntax.Type) -> String {
  "unsupported type"
}
