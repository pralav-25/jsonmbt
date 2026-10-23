// jsonmbt doctor（issue #5）：只读诊断「.json.mbt 有没有真正接上 MoonBit 工具链」。
// 动机（Vitro 批②实锤的最大坑）：不在 moon 包边界内的文件 moon 完全看不见，
// 「验证了没被编译的东西等于没验证」——没有任何工具会告诉你这一点。
// 边界（issue 定案）：**只诊断，不 setup**——包怎么切/workspace 怎么分/CI 怎么
// 接线是用户仓的结构决策，工具代管属侵入；全程零写盘（fmt 幂等检查在系统
// 临时目录建影子包跑，用完即删，不碰用户文件——验收 4 只读纪律）。
// 检查项：包边界（moon.pkg + 模块根）/ 跨文件撞名 / check·build（含 D-7
// stem 形态归属——J2003）/ fmt 稳定（影子包实测）/ workspace 上下文。
// rc：任一 ❌ → 1；全 ✅/⚠️ → 0（CI 直接挂闸）。

///|
/// stdout 行输出（emoji/中文 = UTF-8 字节直写——write_stderr 同款字节契约）
fn print_out(s : String) -> Unit {
  let s2 = if s.has_suffix("\n") { s } else { s + "\n" }
  let bytes = @unicode.to_utf8_bytes(s2)
  jsonmbt_write_stdout(bytes, bytes.length())
}

///|
fn file_exists(p : String) -> Bool {
  @fs.path_exists(p)
}

///|
fn dir_exists(p : String) -> Bool {
  @fs.is_dir(p) catch {
    _ => false
  }
}

///|
/// 影子 spawn 命令构造：平台分叉的静默重定向（moon 自身输出不污染报告）
fn quiet_cmd(cmd : String) -> String {
  if jsonmbt_is_windows() == 1 {
    "\{cmd} >NUL 2>&1"
  } else {
    "\{cmd} >/dev/null 2>&1"
  }
}

///|
fn run_quiet(cmd : String) -> Int32 {
  let full = quiet_cmd(cmd)
  let bytes = @unicode.to_utf8_bytes(full)
  jsonmbt_run_cmd(bytes, bytes.length())
}

///|
/// 目录祖先链（含自身）——从文件所在目录向上找 moon.pkg 之外的模块根用
fn ancestor_dirs(dir : String) -> Array[String] {
  let out : Array[String] = []
  let mut cur = dir
  out.push(cur)
  while true {
    let next = filepath_dir(cur)
    if next == cur || next == "." {
      // "." 也查一遍（相对根场景 cwd 可能就有 moon.mod）后终止
      if next == "." && !out.contains(".") {
        out.push(".")
      }
      break
    }
    out.push(next)
    cur = next
  }
  out
}

///|
/// 祖先链上找模块根：moon.work / moon.mod（命中即返回 (kind, path)）
fn find_module_root(dir : String) -> (String, String)? {
  for d in ancestor_dirs(dir) {
    if file_exists(d + "/moon.work") {
      return Some(("moon.work", d))
    }
    if file_exists(d + "/moon.mod") {
      return Some(("moon.mod", d))
    }
  }
  None
}

///|
/// 递归收集 .json.mbt（跳过隐藏目录与 _build/node_modules/target——
/// 构建缓存不是数据真相源；返回 (显示相对路径, 盘面路径, 所在目录)）
fn collect_json_mbt(
  dir : String,
  prefix : String,
  out : Array[(String, String, String)],
) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for e in entries {
    let full = dir + "/" + e
    let disp = prefix + e
    if e.has_suffix(".json.mbt") {
      out.push((disp, full, dir))
    } else if dir_exists(full) &&
      // #32-20（#29 同族）：点目录一刀切漏扫 .github/.vscode 类人写配置——
      // 对齐 migrate 跳过表（显式跳 .git/_build/node_modules/target）
      e != ".git" &&
      e != "_build" &&
      e != "node_modules" &&
      e != "target" {
      collect_json_mbt(full, disp + "/", out)
    }
  }
}

///|
/// 顶层类型声明名扫描（struct/enum——含 priv 形态；moon 包命名空间 =
/// 同目录全部 .mbt 文件）。返回 名 → 文件名列表（仅跨文件重复者）
fn scan_type_name_clashes(dir : String) -> Array[(String, Array[String])] {
  let by_name : Map[String, Array[String]] = Map([])
  let entries = @fs.read_dir(dir) catch { _ => return [] }
  for e in entries {
    if !(e.has_suffix(".mbt") && file_exists(dir + "/" + e)) {
      continue
    }
    let text = @fs.read_file_to_string(dir + "/" + e) catch { _ => continue }
    for line in text.split("\n") {
      let name = top_level_type_name(line)
      match name {
        Some(n) =>
          match by_name.get(n) {
            Some(files) => if !files.contains(e) { files.push(e) }
            None => by_name[n] = [e]
          }
        None => ()
      }
    }
  }
  let clashes : Array[(String, Array[String])] = []
  by_name.each(fn(k, v) { if v.length() > 1 { clashes.push((k, v)) } })
  // 确定性：按类型名排序输出
  clashes.sort_by(fn(a, b) { a.0.compare(b.0) })
  clashes
}

///|
/// #24-2b：「全部非空 #| 行统一前导空格」排版信号判定——moon 语义里
/// `#| x` 的空格入值（" x"），统一形态大概率是排版习惯而非语义意图。
/// 空行（净内容空）与纯空格行（净内容单空格）不参与统计（排版间隔的
/// 归属语义模糊，保守跳过）；行首缩进的 #| 不参与（moon 标记顶格——
/// 漏报无害，hint 是启发非闸）
fn pipe_lines_all_spaced(text : String) -> Bool {
  let mut content = 0
  let mut spaced = 0
  for line in text.split("\n") {
    let l : StringView = line
    if l.has_prefix("#|") {
      let rest : StringView = l["#|".length():]
      if rest.length() == 0 || (rest[0] == ' ' && rest.length() == 1) {
        continue
      }
      content = content + 1
      if rest[0] == ' ' {
        spaced = spaced + 1
      }
    }
  }
  content > 0 && spaced == content
}

///|
/// 行首顶层声明形态 → 类型名（"pub struct X {" / "struct X {" /
/// "pub enum E" / "enum E"；字段行/缩进行不匹配）
fn top_level_type_name(line : StringView) -> String? {
  let view = line
  let rest : StringView = if view.has_prefix("pub struct ") {
    view["pub struct ".length():]
  } else if view.has_prefix("struct ") {
    view["struct ".length():]
  } else if view.has_prefix("pub enum ") {
    view["pub enum ".length():]
  } else if view.has_prefix("enum ") {
    view["enum ".length():]
  } else {
    return None
  }
  let stop = first_space_or_end(rest.to_owned())
  if stop == 0 {
    return None
  }
  Some(rest[:stop].to_owned())
}

///|
fn try_create_dir(path : String) -> Bool {
  try {
    @fs.create_dir(path)
    true
  } catch {
    _ => false
  }
}

///|
fn try_write(path : String, content : String) -> Bool {
  try {
    @fs.write_string_to_file(path, content)
    true
  } catch {
    _ => false
  }
}

///|
fn try_read(path : String) -> String? {
  Some(@fs.read_file_to_string(path)) catch {
    _ => None
  }
}

///|
/// 系统临时目录（TEMP/TMPDIR/TMP 依次；缺席 → None → fmt 项降级 ⚠️）
fn shadow_root() -> String? {
  match @env.get_env_var("TEMP") {
    Some(t) => if t.length() > 0 { return Some(t) }
    None => ()
  }
  match @env.get_env_var("TMPDIR") {
    Some(t) => if t.length() > 0 { return Some(t) }
    None => ()
  }
  match @env.get_env_var("TMP") {
    Some(t) => if t.length() > 0 { return Some(t) }
    None => ()
  }
  None
}

///|
/// 影子 fmt 命令：必须 cd 进影子项目再裸跑——实测（2026-10-08 三点
// 对照探针）`moon fmt <path>` 把 path 当**当前项目内**的包过滤 pattern，
// 项目外路径静默跳过且 rc=0（假成功）；cd 后子 shell 内的项目根=影子
fn run_moon_fmt_in(dir : String) -> Int32 {
  let cmd = if jsonmbt_is_windows() == 1 {
    "cd /d \"\{dir}\" && moon fmt >NUL 2>&1"
  } else {
    "cd \"\{dir}\" && moon fmt >/dev/null 2>&1"
  }
  let bytes = @unicode.to_utf8_bytes(cmd)
  jsonmbt_run_cmd(bytes, bytes.length())
}

///|
/// 影子检查结果：目录级跳过原因，或 per-file 稳定表（显示名 → fmt 后不变）
priv enum ShadowOut {
  ShadowAll(String) // 目录级原因（moon 缺席/临时目录缺席/影子构建失败/fmt 失败）
  ShadowPerFile(Map[String, Bool]) // fmt 跑完：每文件 stable 标记
}

///|
/// 影子包构建 + fmt + 比对。同目录全部 .json.mbt 拷进影子 moon 项目，
/// 跑一次 moon fmt，副本与原件行尾归一后比对——全程不碰用户文件（只读纪律）
fn fmt_shadow_body(
  files : Array[(String, String, String)],
  shadow : String,
) -> ShadowOut {
  // 最小 moon 项目骨架（影子探针实锚：name+version 的 moon.mod 即被接受）
  if !try_create_dir(shadow) {
    return ShadowAll("shadow dir error")
  }
  if !try_write(
      shadow + "/moon.mod",
      "name = \"jsonmbt/doctor-shadow\"\nversion = \"0.1.0\"\n",
    ) {
    return ShadowAll("shadow dir error")
  }
  if !try_write(shadow + "/moon.pkg", "") {
    return ShadowAll("shadow dir error")
  }
  for f in files {
    let src = match try_read(f.1) {
      Some(s) => s
      None => return ShadowAll("shadow copy error ('\{f.0}')")
    }
    if !try_write(shadow + "/" + basename(f.1), src) {
      return ShadowAll("shadow copy error")
    }
  }
  let rc = run_moon_fmt_in(shadow)
  if rc != 0 {
    return ShadowAll(
      "moon fmt failed in shadow (rc=\{rc}); run `moon fmt <dir>` to see why",
    )
  }
  let per_file : Map[String, Bool] = Map([])
  for f in files {
    let original = match try_read(f.1) {
      Some(s) => s
      None => return ShadowAll("shadow re-read error ('\{f.0}')")
    }
    let formatted = match try_read(shadow + "/" + basename(f.1)) {
      Some(s) => s
      None => return ShadowAll("shadow copy missing after fmt")
    }
    per_file[f.0] = normalize_eol(original) == normalize_eol(formatted)
  }
  ShadowPerFile(per_file)
}

///|
/// 递归清理（x/fs 的 remove_dir 只删空目录——影子包内含文件时须先逐个
/// 删文件；清理失败不致命，TEMP 区残留无害但不留为敬）
fn rm_rf(dir : String) -> Unit {
  let entries = @fs.read_dir(dir) catch { _ => return }
  for e in entries {
    let full = dir + "/" + e
    if dir_exists(full) {
      rm_rf(full)
    } else {
      @fs.remove_file(full) catch {
        _ => ()
      }
    }
  }
  @fs.remove_dir(dir) catch {
    _ => ()
  }
}

///|
fn fmt_shadow_check(files : Array[(String, String, String)]) -> ShadowOut {
  // moon 在场探测（静默）
  if run_quiet("moon version") != 0 {
    return ShadowAll("moon not found in PATH")
  }
  let root = match shadow_root() {
    Some(r) => r
    None => return ShadowAll("no TEMP/TMPDIR/TMP")
  }
  let shadow = "\{root}/jsonmbt-doctor-\{@env.now()}"
  let outcome = fmt_shadow_body(files, shadow)
  rm_rf(shadow)
  outcome
}

///|
fn run_doctor(root_arg : String) -> Int32 {
  if !dir_exists(root_arg) {
    return jdiag_exit(@src.JIO, "doctor: '\{root_arg}' is not a directory")
  }
  print_out("jsonmbt doctor \{root_arg}")
  // workspace 上下文（诊断信息行，不参与 rc）
  match find_module_root(root_arg) {
    Some((kind, path)) => print_out("workspace: \{kind} at \{path}")
    None =>
      print_out(
        "workspace: ⚠️ no moon.mod/moon.work found above '\{root_arg}'",
      )
  }
  let files : Array[(String, String, String)] = []
  collect_json_mbt(root_arg, "", files)
  if files.length() == 0 {
    print_out("no .json.mbt found under '\{root_arg}'")
    return 0
  }
  // 按所在目录分组（首见序——撞名与 fmt 影子都以目录为单位）
  let by_dir_order : Array[String] = []
  let by_dir : Map[String, Array[(String, String, String)]] = Map([])
  for f in files {
    match by_dir.get(f.2) {
      Some(arr) => arr.push(f)
      None => {
        by_dir[f.2] = [f]
        by_dir_order.push(f.2)
      }
    }
  }
  // fmt 影子每目录预跑一次（spawn moon fmt 一次，per-file 结果表——
  // 逐文件各自调用会 O(n²) 重复 spawn 且报告张冠李戴）
  let shadow_by_dir : Map[String, ShadowOut] = Map([])
  for d in by_dir_order {
    shadow_by_dir[d] = fmt_shadow_check(by_dir[d])
  }
  let mut blocked = 0
  let mut warned = 0
  for f in files {
    let (disp, full, dir) = f
    print_out("\n\{disp}")
    let mut bad = false
    // ① 包边界：moon.pkg 必须在**本目录**（moon 包 = 目录级；祖先的 moon.pkg
    // 不覆盖子目录）；模块根在祖先链
    if file_exists(dir + "/moon.pkg") {
      match find_module_root(dir) {
        Some((kind, path)) =>
          print_out(
            "  ✅ package boundary — moon.pkg in \{dir} (\{kind} at \{path})",
          )
        None => {
          print_out(
            "  ⚠️ package boundary — moon.pkg present but no moon.mod/moon.work above '\{dir}' (orphan package)",
          )
          warned = warned + 1
        }
      }
    } else {
      print_out(
        "  ❌ package boundary — no moon.pkg in '\{dir}': moon cannot see this file",
      )
      print_out(
        "     fix: create an empty moon.pkg there (POSIX: printf '\\n' > \{dir}/moon.pkg)",
      )
      bad = true
    }
    // ② 跨文件撞名（moon 编译期才炸的坑——doctor 提前拦）
    let clashes = scan_type_name_clashes(dir)
    let mine : Array[(String, Array[String])] = []
    for c in clashes {
      for f in c.1 {
        if f == basename(full) {
          mine.push(c)
          break
        }
      }
    }
    if mine.length() == 0 {
      print_out("  ✅ struct names — unique across .mbt files in \{dir}")
    } else {
      for c in mine {
        print_out(
          "  ❌ struct names — '\{c.0}' declared in \{c.1.join(", ")} (moon build would fail)",
        )
      }
      bad = true
    }
    // ③ check/build（含 D-7 stem 形态归属 J2003；build 纯内存不落盘）。
    // 读取与校验分离捕获：IOError（读不出）与 Diag（校验红）各自成文
    let mut src_ok = false
    let text_opt = Some(@fs.read_file_to_string(full)) catch { _ => None }
    match text_opt {
      None => {
        print_out("  ❌ check/build — cannot read '\{full}'")
        bad = true
      }
      Some(text) => {
        // #31：与 import/build 同口径走 sanitize_stem（保留字 stem 曾被
        // 误诊为「绑定名不匹配」——其实是四路 expected_name 口径不一致）
        let expected_name = match stem_of(full) {
          Some(s) => Some(@src.sanitize_stem(s))
          None => None
        }
        let check_ok = try {
          let _ = @src.check_source(text, path=disp, expected_name?)
          let _ = @src.build_source(text, path=disp, expected_name?)
          true
        } catch {
          e => {
            print_out("  ❌ check/build — \{e.render()}")
            false
          }
        }
        if check_ok {
          print_out("  ✅ check/build — ok")
          src_ok = true
          // #24-2b：全部非空 #| 行统一前导空格 → 排版信号 note（hint 级，
          // 不计 warned/blocked——接线闸不掺内容口味）。空格入值是 moon
          // 语义非 jsonmbt 偏差；统一形态大概率是排版习惯而非语义意图
          if pipe_lines_all_spaced(text) {
            print_out(
              "  note: every #| line starts with a leading space — that space is part of the value (moon semantics); strip it in the source if unintended",
            )
          }
        } else {
          bad = true
        }
      }
    }
    // ④ fmt 稳定（影子包；只读纪律——内容未过 check 的文件该项跳过）
    if !src_ok {
      print_out(
        "  ⚠️ fmt-stability — skipped (file does not pass check/build)",
      )
      warned = warned + 1
    } else {
      match shadow_by_dir[dir] {
        ShadowAll(reason) => {
          print_out("  ⚠️ fmt-stability — not checked (\{reason})")
          warned = warned + 1
        }
        ShadowPerFile(table) =>
          match table.get(disp) {
            Some(true) => print_out("  ✅ fmt-stable")
            _ => {
              print_out(
                "  ⚠️ fmt-stability — '\{disp}' is not fmt-stable",
              )
              // fix 文案按包边界分叉：moon fmt 只作用于包内文件——目录未接
              // moon.pkg 时 `moon fmt <dir>` 是 rc=0 的静默假成功（实测
              // 2026-10-08），先接包再 fmt 才有效
              if file_exists(dir + "/moon.pkg") {
                print_out(
                  "     fix: run `moon fmt \{dir}` and commit the result",
                )
              } else {
                print_out(
                  "     fix: add moon.pkg in '\{dir}' first, then run `moon fmt \{dir}` (fmt silently skips non-package dirs)",
                )
              }
              warned = warned + 1
            }
          }
      }
    }
    if bad {
      blocked = blocked + 1
    }
  }
  print_out(
    "\nsummary: \{files.length()} file(s): \{files.length() - blocked} ok, \{blocked} blocked, \{warned} warned",
  )
  if blocked > 0 {
    1
  } else {
    0
  }
}
