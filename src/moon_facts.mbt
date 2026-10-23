// 语言事实表（D-14④ 制度化，#38 终案）：moon 本尊语言事实的**单源镜像**。
// 本仓曾三次因自持副本脱同步吃败仗——#28 词法区间 / #35 内建类型名 /
// #38 关键字表，病根同一：「jsonmbt 自持 moon 语言事实副本 → 必然脱同步」。
// 纪律：同步 = 从提取源机械提取替换（一次性脚本，不人肉手抄）；
// 每表注明提取源与日期；各配层 2 雷达锚（漂移显性化——moon 工具链加
// 关键字/改词法区间 → CI 红 → 逼同步），与 #34「latest + 金门 = 漂移
// 雷达」同一设计语言。**不做构建期自动生成管道**（依赖 .mooncakes 缓存
// 布局，脆弱——D-14④ 裁定）。

///|
/// moon 硬关键字 58 词（moonc Parse error 级）。
/// 提取源：.mooncakes/moonbitlang/parser@0.4.4 `lexer/keywords.mbt` 的
/// `keyword_table`（2026-10-13 一次性脚本机械提取——不人肉抄表）。
/// 消费：① 发射端字段名判定（is_legal_label——生成器零警告零错误形态）
/// ② sanitize_stem（D-7 绑定名，仅硬词——保留词 stem 不收，D-14②）
/// ③ check 端硬词判定（J2008——对齐 moonc Parse error 分级，闭合
/// mooncakes parser 库字段位放行 vs moonc 硬拒的缝，PITFALLS #49）
let moon_hard_keywords : Array[String] = [
  "as", "else", "extern", "fn", "if", "let", "var", "proof_assert", "proof_let",
  "const", "match", "using", "mut", "type", "struct", "enum", "extenum", "trait",
  "derive", "while", "break", "continue", "import", "return", "throw", "raise", "try",
  "catch", "pub", "priv", "readonly", "true", "false", "_", "test", "loop", "for",
  "in", "impl", "with", "guard", "async", "is", "suberror", "and", "letrec", "enumview",
  "extend", "noraise", "defer", "errdefer", "lexmatch", "lexscan", "where", "declare",
  "nobreak", "nocancel", "package",
]

///|
/// moon 保留关键字 21 词（moonc [0035] 警告级、编译合法）。
/// 提取源：同上文件的 `reserved_keyword_table`（同日机械提取）。
/// 只进发射端字段名表（生成器产零警告形态）；**不进** sanitize_stem 与
/// check 端判定——moonc 警告级合法，收紧会打碎 stem 撞保留词存量文件
/// 的 D-7 契约（D-14②，挂观察项）
let moon_reserved_keywords : Array[String] = [
  "module", "move", "ref", "static", "super", "unsafe", "use", "await", "dyn", "abstract",
  "do", "final", "macro", "override", "typeof", "virtual", "yield", "local", "method",
  "alias", "assert",
]

///|
/// 发射端字段名口径：硬 + 保留全量（79 词）——importer 遇到即走改名
/// 通道（`k_` + field-alias 注记）；生成器产零警告零错误形态（与
/// D-13「生成器跟随最严规范形、校验端保持宽」同构——「不比 moon 严」
/// 是校验器纪律，生成器本就该保守）
fn is_reserved_label(name : String) -> Bool {
  is_hard_keyword(name) || moon_reserved_keywords.contains(name)
}

///|
fn is_hard_keyword(name : String) -> Bool {
  moon_hard_keywords.contains(name)
}

///|
/// moon 词法标识符区间表（#28）。提取源：moonbitlang/parser
/// `lexer/regex.mbt` 的 RE_LIDENT_START（2026-10-08 提取）。
/// 曾用「码点 ≥ 0x80 一律合法」近似，π(03C0)/А(0400)/א(05D0) 等**表外**
/// 字母被误判合法 → 直出非法 label 触发保险丝、报成 generator bug；
/// 修后表外键自动落入 Map 逃生门/保留字改名/J4011 既有分派。表内代表：
/// é(00E9) 中(4E2D) あ(3042) 가(AC00) 😀(1F600)；表外代表：π NBSP(U+3000
/// 空隙) 全角０(FF10)。勘误旧认知：「非 ASCII 一律合法」是过度概括）
let ident_ranges : Array[(Int32, Int32)] = [
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
/// moon 内建类型名表（#35）：派生 struct/enum 名不得占用语言类型名，
/// 否则 `{"a":{"int":{...}}}` 派生 `Int` 会遮蔽内建 → 产物非法（保险丝
/// J0002）。提取口径 = tyenv.parse_type 识别为类型的名字 ∪ {Never}
/// （2026-10-13 自 parse_type match 臂归集；`<Stem>Never` 底型名由
/// #36 逐文件另算，不在此表）。层 2 雷达锚：builtin-type-name-reserved
let builtin_type_names : Array[String] = [
  "Never", "Int", "Int32", "Int64", "Double", "String", "Bool", "Array", "Map", "Unit",
  "Byte", "Char", "UInt", "UInt32", "UInt64", "Float",
]
