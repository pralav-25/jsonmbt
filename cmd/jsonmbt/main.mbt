// jsonmbt CLI（P1 动词面：build / check）
// 契约（D-10/D-8）：rc 0 成功 / 1 输入错 / 4 用法·IO 错（2=漂移差异、3=保留，P1 未占用）；
// 诊断走 stderr（机器可读前缀 jsonmbt: error [Jxxxx] path:line:col …）；
// build 产物走文件（默认同名 .json）或 stdout（stdin `-` 时）；原子写 = 临时文件 + rename；
// 校验先行失败零产物（check = build 的 dry-run——同一条校验路径）

///|
/// -o -（产物改道 stdout）判定（#12）
fn is_dash_out(out_opt : String?) -> Bool {
  match out_opt {
    Some("-") => true
    _ => false
  }
}

///|
/// 产物上 stdout：二进制 stub 直写（绕开 println 在 Windows 文本模式的
/// CRLF 改写——字节契约，issue #1 表亲；#12 起 `-o -` 同走此通道）
fn write_product_stdout(content : String) -> Unit {
  let bytes = @unicode.to_utf8_bytes(content)
  jsonmbt_write_stdout(bytes, bytes.length())
  jsonmbt_write_stdout(@unicode.to_utf8_bytes("\n"), 1)
}

///|
fn write_stderr(s : String) -> Unit {
  // 长度必须是 UTF-8 字节数（s.length() 是码元数——多字节字符按码元数
  // 写入会截尾，issue #1：em-dash 每个多丢 2 字节）
  // 行契约（审 P2-2）：每条输出以换行收尾——多诊断连发（多文件）不得
  // 粘行，否则下游按行解析破坏（...literalsjsonmbt: error... 实锤）
  let s2 = if s.has_suffix("\n") { s } else { s + "\n" }
  let bytes = @unicode.to_utf8_bytes(s2)
  jsonmbt_write_stderr(bytes, bytes.length())
}

///|
/// J 码诊断单源出口（审 P3：CLI 15 处手写 [Jxxxx] 前缀 → 统一走 Diag 构造，
/// 码值与渲染只此一家）
fn jdiag_exit(code : @src.JCode, msg : String, help~ : String? = None) -> Int32 {
  let d = @src.Diag(code~, loc=dummy_loc(), message=msg, help~, path="")
  write_stderr(d.render())
  @src.JCode::exit_code(code)
}

///|
fn usage() -> Int32 {
  write_stderr(
    "jsonmbt — typed JSON source files for MoonBit (.json.mbt)\n" +
    "usage:\n" +
    "  jsonmbt build <file.json.mbt...|-> [-o <out.json>|-] [--pretty] [--indent <n>]\n" +
    "  --indent <n> sets the width (1..16) and only applies with --pretty\n" +
    "  jsonmbt check <file.json.mbt...|->\n" +
    "  jsonmbt import <file.json|-> [-o <out.json.mbt>|-] [--check] [--fmt] [--type-name-map <map.json>] [--strict] [--input json|jsonc]\n" +
    "  jsonmbt import <file.json> --fill <file.json.mbt> [--check] — refill the value body from the declared type header\n" +
    "  jsonmbt doctor [dir] — read-only diagnosis: is this repo's .json.mbt really wired into moon?\n" +
    "  jsonmbt migrate [dir] [--write] [--input json|jsonc] — batch scout: byte-eq / value-eq / reject report per .json\n" +
    "degrade: .json.mbt -> .json (deterministic, compact); `-` reads stdin, `-o -` writes to stdout\n" +
    "ingest: .json/.jsonc -> .json.mbt (shape inference); --check = idempotence gate; --type-name-map renames derived struct names\n" +
    "--input: jsonc (default) accepts comments / trailing commas / leading BOM; json = strict RFC 8259\n" +
    "rc: 0 ok / 1 input error (doctor: blocked) / 2 drift detected (--check) / 4 usage/IO",
  )
  4
}

///|
/// hint 渲染（rc-0 提示走 stderr；前缀 jsonmbt: hint——机器可读同 D-10 纪律）
fn print_hint(e : @src.Diag) -> Unit {
  write_stderr(
    e.render().replace(old="jsonmbt: error [", new="jsonmbt: hint ["),
  )
}

///|
/// 行尾归一（CRLF→LF）后比对（纪律 11：幂等闸的比对口径）
fn normalize_eol(s : String) -> String {
  // replace_all：core String::replace 只换第一处（#32-1 实锤——多行 CRLF
  // 残留让幂等闸/doctor/migrate 三面假红；CRLF 只来自外部 checkout）
  s.replace_all(old="\r\n", new="\n")
}

///|
/// 输出文件名 → stem：.json.mbt 整后缀优先剥（si.json.mbt → si，
/// 审 P2-1：只去最后一段会产出非法 `pub let si.json`）；其余形态退化到末段
fn json_stem_of(path : String) -> String? {
  let base = basename(path)
  if base.has_suffix(".json.mbt") && base.length() > ".json.mbt".length() {
    return Some(base[:base.length() - ".json.mbt".length()].to_owned())
  }
  let dot = base.rev_find(".")
  match dot {
    Some(i) => if i > 0 { Some(base[:i].to_owned()) } else { None }
    None => Some(base)
  }
}

///|
/// --indent N 的小数字解析（0..99——无外部解析依赖）
fn parse_small_uint(s : String) -> Int32? {
  if s.length() == 0 || s.length() > 2 {
    return None
  }
  let mut v = 0
  for c in s {
    if c < '0' || c > '9' {
      return None
    }
    v = v * 10 + (c.to_int() - '0'.to_int())
  }
  Some(v)
}

///|
fn scan_taken_struct_names(target : String) -> Array[String] {
  // target = 即将写出的输出产物路径（审 P1：以输出目录为基准、排除输出
  // 自身——上一轮自家嵌套 struct 不得算"已占名"，否则幂等闸打翻）
  let names : Array[String] = []
  if target == "-" {
    return names
  }
  let dir = filepath_dir(target)
  let entries = @fs.read_dir(dir) catch { _ => return names }
  for e in entries {
    if (e.has_suffix(".json.mbt") || e.has_suffix(".mbt")) &&
      e != basename(target) {
      let text = @fs.read_file_to_string(dir + "/" + e) catch { _ => continue }
      for line in text.split("\n") {
        if line.has_prefix("pub struct ") {
          let rest : String = line[11:].to_owned()
          let name = rest[:first_space_or_end(rest)].to_owned()
          if name.length() > 0 {
            names.push(name)
          }
        }
      }
    }
  }
  names
}

///|
fn first_space_or_end(s : String) -> Int32 {
  match s.find(" ") {
    Some(i) => i
    None => s.length()
  }
}

///|
fn filepath_dir(path : String) -> String {
  let a = path.rev_find("/")
  let b = path.rev_find("\\")
  let cut = match (a, b) {
    (Some(x), Some(y)) => if x > y { x } else { y }
    (Some(x), None) => x
    (None, Some(y)) => y
    (None, None) => return "."
  }
  path[:cut].to_owned()
}

///|
/// --type-name-map 文件 → 派生名→语义名映射（#6-4）。形态校验：顶层对象、
/// 键值全 String；坏 JSON → J1002、形态错 → J1010（与 infer 侧同码族）
fn load_type_name_map(path : String) -> Map[String, String] raise @src.Diag {
  let text = @fs.read_file_to_string(path) catch {
    _ => raise io_diag("cannot read type-name-map '\{path}'")
  }
  // 与 import 同链（含 JSONC 容忍——映射表可带注释说明各键用途）
  let root = @src.json_parse(@src.strip_jsonc(text), fname=path) catch {
    e => raise e
  }
  let out : Map[String, String] = Map([])
  match root {
    Object(o) =>
      o.each(fn(k, v) {
        match v {
          String(s) => out[k] = s
          _ =>
            raise @src.Diag(
              code=@src.JBadNameMap,
              loc=dummy_loc(),
              message="type-name-map '\{path}': value of '\{k}' must be a string",
              help=Some("format: {\"DerivedName\": \"SemanticName\", ...}"),
              path~,
            )
        }
      })
    _ =>
      raise @src.Diag(
        code=@src.JBadNameMap,
        loc=dummy_loc(),
        message="type-name-map '\{path}' must be a JSON object of {\"DerivedName\": \"SemanticName\"}",
        help=Some(
          "run a first import, copy the auto-derived struct names as keys",
        ),
        path~,
      )
  }
  out
}

///|
fn run_import(
  path : String,
  out_opt : String?,
  check : Bool,
  fmt : Bool,
  type_name_map~ : Map[String, String] = Map([]),
  strict~ : Bool = false,
  jsonc~ : Bool = true,
) -> Int32 {
  let src = read_input(path) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "cannot read '\{path}'")
      }
  }
  // stem：文件名去扩展；stdin 必须配 -o（从 -o 取 stem——D-7 命名同源）
  let display = if path == "-" { "<stdin>" } else { path }
  let stem = if path == "-" {
    match out_opt {
      Some("-") =>
        // #12：全管道（stdin→stdout）无 stem 来源——绑定名必须等于
        // 文件 stem（D-7），无文件名即无从推导，fail loud
        return jdiag_exit(
          @src.JUsage,
          "stdin → stdout (-o -) has no file name to derive the binding stem from — import a named file instead",
        )
      Some(o) =>
        match json_stem_of(o) {
          Some(s) => s
          None =>
            return jdiag_exit(
              @src.JUsage,
              "-o needs a file name to derive the stem from",
            )
        }
      None =>
        return jdiag_exit(
          @src.JUsage,
          "importing stdin requires -o <out.json.mbt>",
        )
    }
  } else {
    match json_stem_of(path) {
      Some(s) => s
      None => return jdiag_exit(@src.JUsage, "'\{path}' has no usable stem")
    }
  }
  // issue #4：同目录已占类型名感知——嵌套 struct 撞 moon 包命名空间时
  // 后来者自动加 stem 前缀（先到先得；单文件/不冲突零变化）
  // 审 P1 修正：①排除**输出产物自身**（原只排输入 .json——第二轮 import
  // 把自家上一轮的嵌套 struct 当已占名 → B 级联漂移成 AB → --check 打翻）
  // ②扫描基准 = **输出目录**（-o 跨目录时输入目录的扫描是瞄错的靶）
  // #12：-o - = 产物上 stdout（纯验证/预览通道，无盘面目标）
  let dash_out = is_dash_out(out_opt)
  let import_target = match out_opt {
    Some("-") => "-"
    Some(o) => o
    None => path[:path.length() - ext_len(path)].to_owned() + ".json.mbt"
  }
  // taken 扫描基准 = 输出目录（#4）；stdout 产物不进 moon 包、单次输出
  // 无撞名对象 → 不扫（扫了 cwd 反而引入环境相关的产物差异）
  let taken : Array[String] = if dash_out {
    []
  } else {
    scan_taken_struct_names(import_target)
  }
  let outcome = @src.import_source(
    src,
    path=display,
    stem~,
    taken_names=taken,
    type_name_map~,
    strict~,
    jsonc~,
  ) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "internal: non-Diag error")
      }
  }
  for h in outcome.hints {
    print_hint(h)
  }
  // #6-4：映射键未命中 → hint（不阻断——映射表可超前写；typo 核对提示）
  for k in outcome.unmatched {
    write_stderr(
      "jsonmbt: hint: type-name-map key '\{k}' matched no generated type name — check it against the struct names in the output",
    )
  }
  let target = import_target
  if check && fmt {
    return jdiag_exit(
      @src.JUsage,
      "--fmt writes to the product file — incompatible with --check (no write side effects)",
    )
  }
  // #12：--check 比对盘面 / --fmt 归一盘面产物——两者都要磁盘目标，
  // 与 -o -（stdout，无盘面）互斥；fail loud 而非静默忽略
  if dash_out && (check || fmt) {
    return jdiag_exit(
      @src.JUsage,
      "-o - (stdout) takes no disk product — incompatible with --check (compares disk) and --fmt (formats disk)",
    )
  }
  if check {
    // 幂等闸（纪律 11）：重算产物与磁盘比对（行尾归一）；漂移 rc 2（D-10）
    let existing = Some(@fs.read_file_to_string(target)) catch { _ => None }
    let up_to_date = match existing {
      Some(disk) => normalize_eol(disk) == normalize_eol(outcome.content)
      None => false
    }
    if up_to_date {
      return 0
    }
    return jdiag_exit(
      @src.JDrift,
      "'\{target}' is not up to date with '\{display}' (import --check)",
      help=Some("re-run: jsonmbt import \{display}"),
    )
  }
  if path == "-" {
    match out_opt {
      Some(_) =>
        // stdin + -o：落盘（usage 承诺；审 P2-1——原实现无条件 println 返回）
        atomic_write(target, outcome.content) catch {
          e =>
            if e is @src.Diag(..) {
              return print_diag_exit(e)
            } else {
              return 4
            }
        }
      None => {
        // stdout 产物走二进制 stub：println 在 Windows 文本模式发 CRLF，
        // 产物字节契约破坏（L2 pretty 用例实锤；issue #1 的 stdout 表亲）
        let bytes = @unicode.to_utf8_bytes(outcome.content)
        jsonmbt_write_stdout(bytes, bytes.length())
        jsonmbt_write_stdout(@unicode.to_utf8_bytes("\n"), 1)
      }
    }
    return 0
  }
  // #18：import 产物已是 fmt 不动点（宽度驱动渲染 + ///| + 尾逗号规范形
  // ——层 2 金门 fmt-fixed-point 常驻断言），接 moon 门禁无需再 fmt——
  // 旧 hint（"not fmt-stable yet"）作废撤销
  if dash_out {
    write_product_stdout(outcome.content)
    return 0
  }
  atomic_write(target, outcome.content) catch {
    e => if e is @src.Diag(..) { return print_diag_exit(e) } else { return 4 }
  }
  if fmt {
    // #18：--fmt 退化为 no-op 保险（产物即不动点，无需 spawn moon fmt；
    // 保留旗标 = 既有脚本零破坏）。moon 升级致 fmt 形态漂移时金门会红，
    // 此处不再吞掉差异——漂移显性化后由本仓跟进渲染器
    write_stderr(
      "jsonmbt: hint: --fmt is a no-op — import output is already at the moon fmt fixed point (#18)",
    )
  }
  0
}

///|
fn ext_len(path : String) -> Int32 {
  let base = basename(path)
  let dot = base.rev_find(".")
  match dot {
    Some(i) => base.length() - i
    None => 0
  }
}

///|
fn dummy_loc() -> @basic.Location {
  {
    start: { fname: "", lnum: 1, bol: 0, cnum: 0, },
    end: { fname: "", lnum: 1, bol: 0, cnum: 0, },
  }
}

///|
/// J0002：IO 错（无位置语义）
fn io_diag(msg : String) -> @src.Diag {
  @src.Diag(code=@src.JIO, loc=dummy_loc(), message=msg, help=None, path="")
}

///|
fn print_diag_exit(e : @src.Diag) -> Int32 {
  write_stderr(e.render())
  @src.JCode::exit_code(e.code())
}

///|
/// 末段文件名（跨 / 与 \）
fn basename(path : String) -> String {
  let a = path.rev_find("/")
  let b = path.rev_find("\\")
  let cut = match (a, b) {
    (Some(x), Some(y)) => if x > y { x } else { y }
    (Some(x), None) => x
    (None, Some(y)) => y
    (None, None) => return path
  }
  path[cut + 1:].to_owned()
}

///|
/// config.json.mbt → config；非 .json.mbt 后缀 → None
fn stem_of(path : String) -> String? {
  let base = basename(path)
  if base.has_suffix(".json.mbt") && base.length() > ".json.mbt".length() {
    Some(base[:base.length() - ".json.mbt".length()].to_owned())
  } else {
    None
  }
}

///|
fn read_input(path : String) -> String raise @src.Diag {
  if path == "-" {
    @unicode.to_utf8_string(jsonmbt_read_stdin())
  } else {
    @fs.read_file_to_string(path) catch {
      _ => raise io_diag("cannot read '\{path}'")
    }
  }
}

///|
/// 原子写（D-8 ③）：同目录临时文件 + rename；失败清理临时文件
fn atomic_write(target : String, content : String) -> Unit raise @src.Diag {
  let tmp = target + ".jsonmbt-tmp"
  @fs.write_string_to_file(tmp, content) catch {
    _ => raise io_diag("cannot write '\{tmp}'")
  }
  let from_b = @unicode.to_utf8_bytes(tmp)
  let to_b = @unicode.to_utf8_bytes(target)
  if jsonmbt_rename(from_b, from_b.length(), to_b, to_b.length()) != 0 {
    @fs.remove_file(tmp) catch {
      _ => ()
    }
    raise io_diag("cannot finalize '\{target}' (rename failed)")
  }
}

///|
fn main {
  @sys.exit(main_rc())
}

///|
fn main_rc() -> Int32 {
  let args = @env.args()
  if args.length() < 3 {
    return usage()
  }
  let verb = args[1]
  if verb != "build" &&
    verb != "check" &&
    verb != "import" &&
    verb != "doctor" &&
    verb != "migrate" {
    return jdiag_exit(@src.JUsage, "unknown command '\{verb}'")
  }
  // migrate（#6-5）：[dir] [--write] [--input json|jsonc]——侦察三榜报告；默认零写
  if verb == "migrate" {
    let mut dir = "."
    let mut write = false
    let mut jsonc = true // D-9（#22）：默认 jsonc 档（注释/尾逗号/BOM 消解）
    let mut i = 2
    while i < args.length() {
      let a = args[i]
      if a == "--write" {
        write = true
      } else if a == "--input" {
        if i + 1 >= args.length() {
          return jdiag_exit(
            @src.JUsage,
            "--input requires an argument: json | jsonc",
          )
        }
        match args[i + 1] {
          "json" => jsonc = false
          "jsonc" => jsonc = true
          _ =>
            return jdiag_exit(
              @src.JUsage,
              "--input accepts 'json' (strict RFC 8259) or 'jsonc' (comments / trailing commas / BOM; default)",
            )
        }
        i = i + 1
      } else if a == "-h" || a == "--help" {
        return usage()
      } else if a.has_prefix("-") {
        return jdiag_exit(
          @src.JUsage,
          "migrate takes a directory and/or --write/--input (scout report; --write also lands non-reject products)",
        )
      } else {
        if dir != "." {
          return jdiag_exit(@src.JUsage, "migrate takes at most one directory")
        }
        dir = a
      }
      i = i + 1
    }
    return run_migrate(dir, write, jsonc~)
  }
  // doctor（#5）：独立参数面——恰好一个可选目录（默认 "."），无产物 flags
  if verb == "doctor" {
    if args.length() > 3 {
      return jdiag_exit(
        @src.JUsage,
        "doctor takes at most one directory argument",
      )
    }
    let dir = if args.length() == 3 { args[2] } else { "." }
    if dir.has_prefix("-") && dir != "." {
      return jdiag_exit(
        @src.JUsage,
        "doctor takes a directory, not flags (read-only diagnosis)",
      )
    }
    return run_doctor(dir)
  }
  let paths : Array[String] = []
  let mut out_opt : String? = None
  let mut do_check = false
  let mut do_fmt = false // import --fmt（#10）：产物落盘后跑 moon fmt 归一
  let mut do_pretty = false
  let mut do_indent : Int32? = None // --pretty 缩进宽度（#6-1）；None = 未给（提示判据）
  let mut type_map_path : String? = None // import --type-name-map <file>（#6-4）
  let mut do_strict = false // import --strict（#14-2a）：空容器严格档（如旧 J4001/J4002 拒）
  let mut strict_given = false // --strict 显式出现（审 P3：build/check 误用拒绝——同 --input 同批纪律）
  let mut do_jsonc = true // --input（#22/D-9）：jsonc 档（默认）——false = 裸 RFC 8259
  let mut input_given = false // --input 显式出现（非 import verb 误用判据——防静默无效参数）
  let mut fill_path : String? = None // import --fill <file>（#14-2b）：按已声明类型重算值体
  let mut i = 2
  while i < args.length() {
    let a = args[i]
    if a == "-o" || a == "--output" {
      if i + 1 >= args.length() {
        return jdiag_exit(@src.JUsage, "-o requires an argument")
      }
      out_opt = Some(args[i + 1])
      i = i + 2
    } else if a == "--check" {
      do_check = true
      i = i + 1
    } else if a == "--fmt" {
      do_fmt = true
      i = i + 1
    } else if a == "--pretty" {
      do_pretty = true
      i = i + 1
    } else if a == "--indent" {
      if i + 1 >= args.length() {
        return jdiag_exit(
          @src.JUsage,
          "--indent requires a number 1..16 (e.g. --indent 1|2|4)",
        )
      }
      match parse_small_uint(args[i + 1]) {
        Some(n) =>
          if n >= 1 && n <= 16 {
            do_indent = Some(n)
          } else {
            return jdiag_exit(
              @src.JUsage,
              "--indent must be 1..16 (0 is ambiguous — use --pretty for pretty, omit for compact)",
            )
          }
        None =>
          return jdiag_exit(
            @src.JUsage,
            "--indent requires a number 1..16 (e.g. --indent 1|2|4)",
          )
      }
      i = i + 2
    } else if a == "--strict" {
      do_strict = true
      strict_given = true // 审 P3：非 import verb 误用判据（防静默无效参数）
      i = i + 1
    } else if a == "--input" {
      // D-9（#22）：输入 profile 旗标——jsonc（默认）= 注释/尾逗号/BOM
      // 消解；json = 裸 RFC 8259。不复用 --strict（#14-2a 空容器档已占用）
      if i + 1 >= args.length() {
        return jdiag_exit(
          @src.JUsage,
          "--input requires an argument: json | jsonc",
        )
      }
      input_given = true
      match args[i + 1] {
        "json" => do_jsonc = false
        "jsonc" => do_jsonc = true
        _ =>
          return jdiag_exit(
            @src.JUsage,
            "--input accepts 'json' (strict RFC 8259) or 'jsonc' (comments / trailing commas / BOM; default)",
          )
      }
      i = i + 2
    } else if a == "--fill" {
      if i + 1 >= args.length() {
        return jdiag_exit(
          @src.JUsage,
          "--fill requires an existing .json.mbt file (its type header is reused)",
        )
      }
      fill_path = Some(args[i + 1])
      i = i + 2
    } else if a == "--type-name-map" {
      if i + 1 >= args.length() {
        return jdiag_exit(
          @src.JUsage,
          "--type-name-map requires a file argument",
        )
      }
      type_map_path = Some(args[i + 1])
      i = i + 2
    } else if a == "-h" || a == "--help" {
      return usage()
    } else {
      paths.push(a)
      i = i + 1
    }
  }
  if paths.length() == 0 {
    return usage()
  }
  // stdin `-` 只允许单输入；build/check 的文件路径必须 .json.mbt 后缀（防误伤）
  for p in paths {
    if p == "-" {
      if paths.length() > 1 {
        return jdiag_exit(@src.JUsage, "'-' (stdin) must be the only input")
      }
    } else if verb != "import" && stem_of(p) is None {
      return jdiag_exit(
        @src.JUsage,
        "'\{p}' is not a .json.mbt file (use `-` for stdin)",
      )
    }
  }
  if verb == "import" {
    if paths.length() != 1 {
      return usage()
    }
    // 审 P3：import 的产物形态由生成器定（fmt-canonical），--indent 与它
    // 无关——静默忽略是"沉默错形态"（与 #6-3 同罪），明确拒绝
    if do_indent is Some(_) {
      return jdiag_exit(
        @src.JUsage,
        "--indent applies to build only (import output shape is generator-defined)",
      )
    }
    // #14-2b：--fill <file> = 按已声明类型重算值体（类型头逐字节保留）
    if fill_path is Some(f) {
      if type_map_path is Some(_) {
        return jdiag_exit(
          @src.JUsage,
          "--fill reuses the declared type header — there are no derived names to map (--type-name-map is for plain import)",
        )
      }
      if do_strict {
        return jdiag_exit(
          @src.JUsage,
          "--strict tunes empty-container inference; --fill skips inference entirely",
        )
      }
      return run_fill(paths[0], f, out_opt, do_check, do_fmt, jsonc=do_jsonc)
    }
    // #6-4：--type-name-map 是 import 专属（build/check 侧先拒——下方
    // 共享解析循环收 flag，非 import verb 到达此处即误用）
    let type_map : Map[String, String] = match type_map_path {
      Some(p) => load_type_name_map(p) catch { e => return print_diag_exit(e) }
      None => Map([])
    }
    return run_import(
      paths[0],
      out_opt,
      do_check,
      do_fmt,
      type_name_map=type_map,
      strict=do_strict,
      jsonc=do_jsonc,
    )
  }
  // import 专属 flag 出现在其他 verb = 误用（fail loud，防静默无效参数）
  if type_map_path is Some(_) {
    return jdiag_exit(@src.JUsage, "--type-name-map applies to import only")
  }
  if fill_path is Some(_) {
    return jdiag_exit(@src.JUsage, "--fill applies to import only")
  }
  if strict_given {
    // 审 P3：--strict 是空容器推断档（#14-2a）——build/check 无推断面，
    // 曾静默忽略（与同批 --input 自立的 fail-loud 纪律相悖）
    return jdiag_exit(
      @src.JUsage,
      "--strict applies to import only (it tunes shape inference, which build/check never runs)",
    )
  }
  if input_given {
    return jdiag_exit(
      @src.JUsage,
      "--input applies to import/migrate only (build takes .json.mbt sources, not JSON)",
    )
  }
  // verb 专属 flags（#32-13）：--check/--fmt 是 import 的幂等/归一闸、-o 与
  // 输出形态 flags 是产物面——放错 verb 曾静默忽略（build x --check 产物照写、
  // check -o 无声过），「防静默无效参数」纪律同批装全
  if verb == "build" && (do_check || do_fmt) {
    return jdiag_exit(
      @src.JUsage,
      "--check/--fmt applies to import only (build always validates its product; use import --check for the idempotence gate)",
    )
  }
  if verb == "check" {
    if do_check || do_fmt {
      return jdiag_exit(
        @src.JUsage,
        "--check/--fmt applies to import only (check is already the validation dry-run)",
      )
    }
    if out_opt is Some(_) {
      return jdiag_exit(
        @src.JUsage,
        "-o applies to build/import only (check writes nothing)",
      )
    }
    if do_pretty || do_indent is Some(_) {
      return jdiag_exit(
        @src.JUsage,
        "--pretty/--indent shape build output only (check writes nothing)",
      )
    }
  }
  if paths.length() > 1 && out_opt is Some(_) {
    return jdiag_exit(@src.JUsage, "-o accepts a single input")
  }
  let mut rc = 0
  for p in paths {
    let r = run_one(verb, p, out_opt, do_pretty, do_indent)
    if r != 0 {
      rc = r
    }
  }
  rc
}

///|
fn run_one(
  verb : String,
  path : String,
  out_opt : String?,
  pretty : Bool,
  indent : Int32?,
) -> Int32 {
  let src = read_input(path) catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "cannot read '\{path}'")
      }
  }
  // #31：期望名走 sanitize_stem（与 import 同口径——保留字 stem〔type/in/
  // match…〕import 产 x_type 绑定，曾用原文校验必 J2003：链路断在第二步）。
  // D-7 语义 = 绑定名 == sanitize_stem(stem)：确定性映射，常规 stem 恒等
  let expected_name = if path == "-" {
    None
  } else {
    match stem_of(path) {
      Some(s) => Some(@src.sanitize_stem(s))
      None => None
    }
  }
  let display = if path == "-" { "<stdin>" } else { path }
  // check = build 的 dry-run（同一条校验路径——D-8）
  if verb == "check" {
    @src.check_source(src, path=display, expected_name?) catch {
      e =>
        if e is Diag(..) {
          return print_diag_exit(e)
        } else {
          return jdiag_exit(@src.JIO, "internal: non-Diag error")
        }
    }
    return 0
  }
  // build：校验先行，失败零产物（D-8 ①）；--pretty 与 Go encoder 逐字节对齐
  let product = @src.build_source(
    src,
    path=display,
    expected_name?,
    pretty~,
    indent~,
  ) catch {
    e =>
      if e is Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "internal: non-Diag error")
      }
  }
  // 产物去向：stdin 默认 stdout（-o 可改道文件）；文件默认同名 .json；
  // `-o -` 恒改道 stdout（#12：build 链纯验证通道——降级+序列化全链跑到、
  // 不落盘即验；CI/脚本配 `-o - | md5sum` 或 shell 层丢弃，工具不认识设备名）
  if path == "-" {
    match out_opt {
      Some("-") => write_product_stdout(product)
      Some(o) =>
        atomic_write(o, product) catch {
          e => if e is Diag(..) { return print_diag_exit(e) } else { return 4 }
        }
      None => write_product_stdout(product)
    }
    return 0
  }
  if is_dash_out(out_opt) {
    write_product_stdout(product)
    return 0
  }
  let target = match out_opt {
    Some(o) => o
    None => path[:path.length() - ".json.mbt".length()].to_owned() + ".json"
  }
  // #6-3：未加 --pretty 的"沉默错形态"提示——下游按字节指纹锚定时
  // 紧凑产物会打翻指纹，且报错指向"数据变了"而非"命令漏了参数"
  if not(pretty) && indent is Some(_) && path != "-" {
    write_stderr(
      "jsonmbt: hint: --indent without --pretty has no effect — pretty output is required for indentation",
    )
  }
  if not(pretty) && path != "-" {
    // #23 建议2：落盘 hint 点名实际输出路径——下游批量脚本漏 -o 时
    // 曾连环产出 .json.json 副产物不自知，hint 只说形态不说去向帮不上忙
    write_stderr(
      "jsonmbt: hint: build without --pretty emits compact JSON → '\{target}'; if a downstream anchors by byte fingerprint, re-run with --pretty [--indent N]",
    )
  }
  atomic_write(target, product) catch {
    e => if e is Diag(..) { return print_diag_exit(e) } else { return 4 }
  }
  0
}

///|
/// --fill 执行路径（#14-2b）：读源 JSON + 盘上产物的类型头 → 声明类型驱动
/// 渲染值体 → 头逐字节保留写回。--check = 分档幂等闸（头保留语境下的
/// 值体同步校验：源 JSON 变了/声明字段无对应数据 → rc 2 J5001）
fn run_fill(
  path : String,
  fill_target : String,
  out_opt : String?,
  check : Bool,
  fmt : Bool,
  jsonc~ : Bool = true,
) -> Int32 {
  let src = read_input(path) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "cannot read '\{path}'")
      }
  }
  let existing = @fs.read_file_to_string(fill_target) catch {
    _ =>
      return jdiag_exit(
        @src.JIO,
        "cannot read fill target '\{fill_target}'",
        help=Some(
          "--fill needs an existing .json.mbt whose type header is reused",
        ),
      )
  }
  // #32-5④：不传 stem（期望名不绑源 JSON 文件名）——fill 语义 = 保留
  // 目标文件类型头只重写值体，绑定名校验在产物创建时已发生过
  let filled = @src.fill_source(
    src,
    existing,
    path~,
    fill_path=fill_target,
    jsonc~,
  ) catch {
    e =>
      if e is @src.Diag(..) {
        return print_diag_exit(e)
      } else {
        return jdiag_exit(@src.JIO, "internal: non-Diag error")
      }
  }
  if check {
    // 分档幂等闸：与盘上产物行尾归一后比对（同 import --check 口径）
    let up_to_date = normalize_eol(filled) == normalize_eol(existing)
    if up_to_date {
      return 0
    }
    return jdiag_exit(
      @src.JDrift,
      "'\{fill_target}' value body is not up to date with '\{path}' (import --fill --check)",
      help=Some("re-run: jsonmbt import \{path} --fill \{fill_target}"),
    )
  }
  // 输出目标：-o - 预览（stdout）；-o <file> 另存；缺省写回 fill 目标自身
  if is_dash_out(out_opt) {
    write_product_stdout(filled)
    return 0
  }
  let target = match out_opt {
    Some(o) => o
    None => fill_target
  }
  atomic_write(target, filled) catch {
    e => if e is @src.Diag(..) { return print_diag_exit(e) } else { return 4 }
  }
  if fmt {
    let cmd = "moon fmt \"\{target}\""
    let bytes = @unicode.to_utf8_bytes(cmd)
    let rc = jsonmbt_run_cmd(bytes, bytes.length())
    if rc != 0 {
      return jdiag_exit(
        @src.JIO,
        "moon fmt failed (rc=\{rc}) on '\{target}' — moon missing from PATH, or the file is outside any moon workspace (see moon's own error above)",
        help=Some(
          "--fmt failure keeps the unformatted product on disk; gate on rc (4 here), not on the product file",
        ),
      )
    }
  }
  0
}
