// jsonmbt migrate（issue #6-5）：批量迁移侦察三榜报告——把「探测哪些能迁」
// 从下游仓手写 shell 脚本（逐张 import → build --pretty → cmp 原文 → 分类）
// 产品化。默认**零写**（侦察契约：跑前后目录不变）；--write 才落盘非
// reject 产物。rc：任一 reject/diff → 1（CI 迁移完成度闸）；全 byte/value → 0。
//
// 三榜（判定优先级降序）：
//   BYTE-EQ (pretty|compact)：行尾归一后逐字节相等——可直接进 CI 对账
//   VALUE-EQ：值语义等价、键序不敏感（@src.json_value_eq）——风格差，
//             接 CI 对账前须确认字节口径
//   REJECT：import 阻断（J 码 + 消息首行）
// 内存 taken 累积 = 模拟「逐张真实迁移」的同目录撞名序列（#4 前缀化
// 复现），前缀化发生时告警指向 --type-name-map。

///|
/// 收集待迁 .json（跳过 .git/_build/node_modules/target；**其余点目录照扫**
///（#29：.vscode/.github/.devcontainer 类人写配置曾是 migrate 的核心受众
/// 却被 `has_prefix(".")` 一刀切静默漏扫——随机 12 项目实测 650 张漏 42
/// 张全在点目录）；跳过已有同名 .json.mbt 的——已迁移不重复报）。
/// skipped_dirs 累积被跳过的目录名（报告声明用——静默漏扫即静默谎言）
fn collect_json_files(
  dir : String,
  prefix : String,
  out : Array[(String, String)], // (显示相对路径, 盘面路径)
  skipped_dirs : Array[String],
) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for e in entries {
    let full = dir + "/" + e
    let disp = prefix + e
    if e.has_suffix(".json") && file_exists(full) {
      if !file_exists(dir + "/" + e[:e.length() - 5].to_owned() + ".json.mbt") {
        out.push((disp, full))
      }
    } else if dir_exists(full) {
      // 点目录只跳 .git（版本库内部——无迁移语义）；_build/node_modules/
      // target = 依赖与产物目录（非数据源）
      if e == ".git" || e == "_build" || e == "node_modules" || e == "target" {
        if !skipped_dirs.contains(disp) {
          skipped_dirs.push(disp)
        }
      } else {
        collect_json_files(full, disp + "/", out, skipped_dirs)
      }
    }
  }
}

///|
/// 产物 struct 名扫描（taken 累积与前缀化告警的判据）
fn struct_names_of(content : String) -> Array[String] {
  let names : Array[String] = []
  for line in content.split("\n") {
    if line.has_prefix("pub struct ") {
      let rest : String = line[11:].to_owned()
      let name = rest[:first_space_or_end(rest)].to_owned()
      if name.length() > 0 {
        names.push(name)
      }
    }
  }
  names
}

///|
/// 行尾 + 尾换行归一后逐字节比对
fn byte_eq(a : String, b : String) -> Bool {
  let na = normalize_eol(a)
  let nb = normalize_eol(b)
  trim_trailing_nl(na) == trim_trailing_nl(nb)
}

///|
fn trim_trailing_nl(s : String) -> String {
  // #21：索引必须与 to_array() 同口径。String::length() 是 **UTF-16 码元数**，
  // Array[Char] 是**码点数**——含星面字符（emoji）时前者更大 → chars[end-1]
  // 越界 panic。同族已在 src/jsonparse.mbt / src/jsonc.mbt / src/unescape.mbt
  // 三处用 view.length() 修过（见 importer_test.mbt 的 emoji 回归锚），
  // cmd/ 层这一处漏网；且 panic 会中断整批 migrate 扫描。
  let chars = s.to_array()
  let mut end = chars.length()
  while end > 0 && (chars[end - 1] == '\n' || chars[end - 1] == '\r') {
    end = end - 1
  }
  let buf = StringBuilder()
  for i = 0; i < end; i = i + 1 {
    buf.write_char(chars[i])
  }
  buf.to_string()
}

///|
/// 盘面目录既有 .json.mbt/.mbt 的顶层 struct 名（真实 import 的
/// scan_taken_struct_names 同语义——migrate 的 taken 模拟起始值，审阅 P2）
fn dir_taken_names(dir : String) -> Array[String] {
  let names : Array[String] = []
  let entries = @fs.read_dir(dir) catch { _ => return names }
  for e in entries {
    if e.has_suffix(".mbt") && file_exists(dir + "/" + e) {
      let text = @fs.read_file_to_string(dir + "/" + e) catch { _ => continue }
      for name in struct_names_of(text) {
        if !names.contains(name) {
          names.push(name)
        }
      }
    }
  }
  names
}

///|
fn run_migrate(root_arg : String, write : Bool, jsonc? : Bool = true) -> Int {
  if !dir_exists(root_arg) {
    return jdiag_exit(@src.JIO, "migrate: '\{root_arg}' is not a directory")
  }
  print_out("jsonmbt migrate \{root_arg}\{if write { " --write" } else { "" }}")
  let files : Array[(String, String)] = []
  let skipped_dirs : Array[String] = []
  collect_json_files(root_arg, "", files, skipped_dirs)
  // #29：跳过目录显式声明（静默漏扫即静默谎言——.git/_build/node_modules/target）
  if skipped_dirs.length() > 0 {
    print_out(
      "skipped \{skipped_dirs.length()} dir(s): \{skipped_dirs.join(", ")}",
    )
  }
  if files.length() == 0 {
    print_out(
      "no .json found under '\{root_arg}' (files with an existing .json.mbt twin are skipped)",
    )
    return 0
  }
  print_out("scanned: \{files.length()} json file(s)\n")
  // 内存 taken 模拟（#4 逐张迁移的撞名序列复现）——**per-directory**：
  // 起始值 = 盘面既有 .json.mbt/.mbt 的 struct 名（真实 import 走
  // scan_taken_struct_names 扫输出目录；审阅 P2：曾 taken=[] 起始，
  // 已迁移孪生的撞名被漏报、--write 产物与真实 import 不一致 → --check
  // rc=2 自相矛盾）；迁移过程中产物名再累积进所在目录的 taken
  let taken_by_dir : Map[String, Array[String]] = Map([])
  let seen_dirs : Array[String] = []
  for f in files {
    let d = filepath_dir(f.1)
    if !seen_dirs.contains(d) {
      seen_dirs.push(d)
      taken_by_dir[d] = dir_taken_names(d)
    }
  }
  let mut n_byte = 0
  let mut n_value = 0
  let mut n_layout = 0 // #30：仅排版差（紧凑归一逐字节等）
  let mut n_reject = 0
  for f in files {
    let (disp, full) = f
    let raw = @fs.read_file_to_string(full) catch {
      _ => {
        print_out("\{disp} → REJECT (cannot read)")
        n_reject = n_reject + 1
        continue
      }
    }
    let stem = match json_stem_of(full) {
      // 原文 stem 直传（#32-6 单点归一）：sanitize 在 import_source 内部
      // 单点发生（不动点化后幂等）——cmd 侧预清洗是历史双口径残留
      Some(s) => s
      None => {
        print_out("\{disp} → REJECT (no usable stem)")
        n_reject = n_reject + 1
        continue
      }
    }
    // import（taken 传入 → 跨文件前缀化在此发生；--input 档同口径透传）
    let outcome = Ok(
      @src.import_source(
        raw,
        path=disp,
        stem~,
        taken_names=taken_by_dir[filepath_dir(full)],
        jsonc~,
      ),
    ) catch {
      e =>
        if e is @src.Diag(..) {
          Err(e.render())
        } else {
          Err("internal: non-Diag error")
        }
    }
    match outcome {
      Err(rendered) => {
        // J 码 + 消息首行（render 首行 = jsonmbt: error [Jxxxx] path:l:c msg）
        let first : String = match rendered.find("\n") {
          Some(i) => rendered[:i].to_owned()
          None => rendered
        }
        print_out("\{disp} → REJECT \{first}")
        n_reject = n_reject + 1
        continue
      }
      Ok(o) => {
        let content = o.content
        // 降级产物（compact / pretty）与原文件的值树（失败 = 不可比，保守按不等）
        let built_compact : String? = Some(
          @src.build_source(content, path=disp + ".mbt"),
        ) catch {
          _ => None
        }
        let built_pretty : String? = Some(
          @src.build_source(content, path=disp + ".mbt", pretty=true),
        ) catch {
          _ => None
        }
        let value_eq = match (built_compact, parse_for_cmp(raw, jsonc)) {
          (Some(bc), Some(orig)) =>
            match parse_for_cmp(bc, jsonc) {
              Some(bj) => @src.json_value_eq(orig, bj)
              None => false
            }
          _ => false
        }
        // #30 LAYOUT-EQ：仅排版差——原文件 parse 后紧凑归一与 built_compact
        // **逐字节**等（值树+键序+转义规范形全等，差只在源文件的空白/换行
        // 布局）。字符层"剥空白"会误伤字符串值内的语义空白，故用对称归一；
        // 转义形态差（\u4e2d vs 中）与键序差正确落 VALUE-EQ
        let layout_eq = match (built_compact, parse_for_cmp(raw, jsonc)) {
          (Some(bc), Some(orig)) => orig.stringify() == bc
          _ => false
        }
        let mut kind = "DIFF (round-trip mismatch — please report)"
        match built_pretty {
          Some(bp) =>
            if byte_eq(bp, raw) {
              kind = "BYTE-EQ (pretty)"
              n_byte = n_byte + 1
            }
          None => ()
        }
        if kind == "DIFF (round-trip mismatch — please report)" {
          match built_compact {
            Some(bc) =>
              if byte_eq(bc, raw) {
                kind = "BYTE-EQ (compact)"
                n_byte = n_byte + 1
              }
            None => ()
          }
        }
        if kind == "DIFF (round-trip mismatch — please report)" && layout_eq {
          kind = "LAYOUT-EQ (whitespace only)"
          n_layout = n_layout + 1
        }
        if kind == "DIFF (round-trip mismatch — please report)" && value_eq {
          kind = "VALUE-EQ"
          n_value = n_value + 1
        }
        if kind == "DIFF (round-trip mismatch — please report)" {
          // 往返值不等：理论不可达（无损承诺）——诚实榜，出现即产品缺陷信号
          n_reject = n_reject + 1
        }
        print_out("\{disp} → \{kind}")
        // #4 前缀化告警：产物含 capitalize(stem)+X 形态 → 指路语义命名
        let prefix_probe = capitalize_cli(stem)
        for name in struct_names_of(content) {
          if name.length() > prefix_probe.length() &&
            name.has_prefix(prefix_probe) {
            print_out(
              "  note: '\{name}' is a stem-prefixed collision name — consider --type-name-map for a semantic name",
            )
            break
          }
        }
        // taken 累积（同目录下一张的撞名语境；跨目录互不影响——真实
        // import 的扫描基准就是输出目录）
        let dir_taken = taken_by_dir[filepath_dir(full)]
        for name in struct_names_of(content) {
          if !dir_taken.contains(name) {
            dir_taken.push(name)
          }
        }
        // --write：非 reject/diff 落盘
        if write && !kind.has_prefix("DIFF") {
          atomic_write(
            full[:full.length() - 5].to_owned() + ".json.mbt",
            content,
          ) catch {
            _ => print_out("  error: cannot write '\{disp}.json.mbt'")
          }
        }
      }
    }
  }
  print_out(
    "\nsummary: \{files.length()} file(s): \{n_byte} byte-eq, \{n_layout} layout-eq, \{n_value} value-eq, \{n_reject} reject",
  )
  if n_value > 0 {
    print_out(
      "hint: \{n_value} value-eq file(s) — confirm the byte-level contract (e.g. --pretty --indent N) before wiring CI freshness checks",
    )
  }
  if n_reject > 0 {
    1
  } else {
    0
  }
}

///|
fn parse_for_cmp(text : String, jsonc : Bool) -> Json? {
  let stripped = if jsonc { @src.strip_jsonc(text) } else { text }
  Some(@src.json_parse(stripped, fname="<cmp>")) catch {
    _ => None
  }
}

///|
/// cmd 层的 stem 清洗（sanitize_stem 在 src 层是 pub——直接复用）
fn sanitize_stem_cli(name : String) -> String {
  @src.sanitize_stem(name)
}

///|
fn capitalize_cli(s : String) -> String {
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
