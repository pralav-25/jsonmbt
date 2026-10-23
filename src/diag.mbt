// 诊断模型：J 系稳定错误码 + 位置（行列）+ 一行修复建议（继承 Vitro 纪律：
// 码只增不改；默认一行 + help，教学全文走未来的 --explain/在线页）
// rc 映射（D-10）：J0001/J0002 → 4（用法/IO）；J1xxx/J2xxx/J3xxx → 1（输入错）

///|
pub(all) enum JCode {
  JUsage // J0001 用法错（未知子命令/参数缺失）
  JIO // J0002 IO 错（读写失败）
  JSyntax // J1001 .json.mbt 语法错（parser Report）
  JJsonSyntax // J1002 JSON 输入语法错（对拍/N 的 JSON 侧输入；importer 同族复用）
  JDupKey // J1003 JSON 重复键（病态输入，不替它选语义——D-11）
  JBadNameMap // J1010 type-name-map 语义错：值非合法类型名/撞已占类型/映射文件形态非对象（#6-4）
  JNoDoc // J2001 缺顶层 pub let（D-7）
  JMultiDoc // J2002 多个顶层 pub let（D-7）
  JStemMismatch // J2003 pub let 名与文件 stem 不符（D-7；stdin 免）
  JDeep // J2004 嵌套深度超预算
  JBadTop // J2005 顶层出现 struct/pub let 之外的声明
  JDupStruct // J2006 重复 struct 定义名
  JBadFieldType // J2007 struct 字段类型超出 L0 支持面（Unit/Arrow/Tuple/跨包名…）
  JHardKeywordField // J2008 struct 字段名为 moon 硬关键字（#38 D-14③——对齐 moonc Parse error 分级，闭 mooncakes parser 库字段位假绿缝）
  JNotLiteral // J3001 表达式超出 L0 纯字面量子集（D-8 ② fail loud）
  JMapKey // J3002 Map 字面量键非字符串
  JBadLiteral // J3003 字面量类型 JSON 无对应（Char/Byte/Bytes/Regex/UInt…）
  JFieldType // J3004 字段类型不匹配
  JUnknownField // J3005 未知字段（struct 无此字段）
  JMissingField // J3006 缺必填字段
  JDupField // J3007 重复字段
  JTagCollision // J3008 enum payload 字段与 tag 键（case）撞车——D-5 转正规格
  JBadAlias // J3009 字段改名注记（// jsonmbt: field-alias）畸形或语义错（#13）
  JEmptyArr // J4001 孤立空数组：元素类型无线索（D-1 阻断，两级启发后仍无解）
  JEmptyObj // J4002 空对象：无字段可推（D-1 空对象单独形态）
  JAllNull // J4003 全 null：Option 基型无信息（D-1 家族）
  JHeteroArr // J4010 异构数组（元素类型不相容）
  JMixedKeys // J4011 异值键对象：Map 逃生门不适用，请人工建模 struct
  JHeteroField // J4012 字段跨样本类型不相容
  JBigNum // J4020 超 Int64 整数（D-2 诚实拒绝；字符串化是显式 opt-in）
  JTaggedEnumHint // J4030 疑似 tagged-enum 提示（hint 级，rc 0，建议手写 enum）
  JNeverHint // J4031 空容器 Never 占位提示（hint 级，rc 0，#14-2a——非空样本后换真类型）
  JDrift // J5001 --check 检测到漂移（rc 2——D-10 有义分叉，diff 族同段扩展）
}

///|
pub fn JCode::num(self : JCode) -> String {
  match self {
    JUsage => "J0001"
    JIO => "J0002"
    JSyntax => "J1001"
    JJsonSyntax => "J1002"
    JDupKey => "J1003"
    JBadNameMap => "J1010"
    JNoDoc => "J2001"
    JMultiDoc => "J2002"
    JStemMismatch => "J2003"
    JDeep => "J2004"
    JBadTop => "J2005"
    JDupStruct => "J2006"
    JBadFieldType => "J2007"
    JHardKeywordField => "J2008"
    JNotLiteral => "J3001"
    JMapKey => "J3002"
    JBadLiteral => "J3003"
    JFieldType => "J3004"
    JUnknownField => "J3005"
    JMissingField => "J3006"
    JDupField => "J3007"
    JTagCollision => "J3008"
    JBadAlias => "J3009"
    JEmptyArr => "J4001"
    JEmptyObj => "J4002"
    JAllNull => "J4003"
    JHeteroArr => "J4010"
    JMixedKeys => "J4011"
    JHeteroField => "J4012"
    JBigNum => "J4020"
    JTaggedEnumHint => "J4030"
    JNeverHint => "J4031"
    JDrift => "J5001"
  }
}

///|
/// rc（D-10 五值表）：4 = 用法·IO 错；1 = 输入错（校验/类型错）；
/// 2 = 检测到漂移/差异（import --check / diff，P1.5 起占用）；hint 级码 rc 0。
pub fn JCode::exit_code(self : JCode) -> Int32 {
  match self {
    JUsage | JIO => 4
    JTaggedEnumHint | JNeverHint => 0
    JDrift => 2
    _ => 1
  }
}

///|
pub(all) suberror Diag {
  Diag(
    code~ : JCode,
    loc~ : @basic.Location,
    message~ : String,
    help~ : String?,
    path~ : String
  ) // loc.start.fname 为空时的兜底显示名
}

///|
fn pos_of(loc : @basic.Location) -> (Int32, Int32) {
  // bol = 行首字节偏移，cnum = 文件级字节偏移 → 列 = cnum - bol + 1（编译器口径）
  let p = loc.start
  (p.lnum, p.cnum - p.bol + 1)
}

///|
/// 机器可读前缀（D-10）：`jsonmbt: error [J3004] path:line:col message`
/// + 可选 `  help: ...` 一行。渲染文本 = stderr 通道的全部形态（--json 模式 P1 后续工具面扩展）。
pub fn Diag::render(self : Diag) -> String {
  if self is Diag(code~, loc~, message~, help~, path~) {
    let (line, col) = pos_of(loc)
    let fname = if loc.start.fname != "" { loc.start.fname } else { path }
    // 前缀按 rc 分化（#32-20）：hint 级码（rc=0）不是 error——曾硬编码
    // "error"，wasm/js 直连消费者（不走 CLI print_hint 兜底）拿到
    // "jsonmbt: error [J4031]" 的 rc-0 提示
    let tag = if code.exit_code() == 0 { "hint" } else { "error" }
    let head = "jsonmbt: \{tag} [\{code.num()}] \{fname}:\{line}:\{col} \{message}"
    match help {
      Some(h) => head + "\n  help: " + h
      None => head
    }
  } else {
    abort("unreachable: Diag has exactly one constructor")
  }
}

///|
/// 诊断码读取（CLI rc 决策用）
pub fn Diag::code(self : Diag) -> JCode {
  if self is Diag(code~, ..) {
    code
  } else {
    abort("unreachable: Diag has exactly one constructor")
  }
}
