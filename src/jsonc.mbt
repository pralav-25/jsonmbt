// D-9 JSONC 输入归一化器（#22 重写 2026-10-10）：本函数是 importer 输入侧
// **唯一宽松层**——jsonparse 恒裸 RFC 8259（对拍基准不污染）。判据：只收
// 「字符层删/替空白可消解为严格 JSON」的特性（注释 / 尾逗号 / 文件首 BOM），
// 不收 token 层重写（单引号串、无引号 key、hex、NaN…——扩值域，永不在
// pre-pass 出现）。
//
// 机制：字符串字面量感知（裸正则必误伤 "http://x" / "a//b"——三形态负
// 样本锚钉死）；注释与尾逗号统一**等长空格替换**（换行原位保留）——诊断
// 行列不漂移；纯函数 = 字节确定性（同输入恒同输出）；无宽松特征的输入
// 零改动（输入按内容探测的实质：归一化后走同一条 parse 路径，不看扩展名）。
//
// 尾逗号消解（pending comma + last_sig guard）：
//   遇 `,` 暂存 → 穿透空白**与注释**看下一有效字符 → 见 `}`/`]` 且逗号的
//   前一非空白有效字符 ∉ {`\0`(文件首), `{`, `[`, `,`, `:`} 才把逗号位
//   替换为空格；否则暂存区原样 flush 留给 parser 拒。
//   last_sig guard 是 `{,}`/`[,]`/`[1,,]`/`{"a":,}` 不被超收的唯一保证
//   （纯「`,` 后见闭合」会把 `[,]` 消解成 `[]`——超收）。
//   BOM 仅消解**文件首字符**：字符串内 U+FEFF 是合法 JSON 字符（RFC 8259
//   允许任意 Unicode），全文件替换会破数据。

///|
/// 注释段 → 等长空格字符数组（换行原位；调用方保证 view[start] 起是
/// `//` 或 `/*`）——NORMAL 直写 / pending 暂存同一份转换
fn comment_to_spaces(
  view : Array[Char],
  n : Int,
  start : Int,
) -> (Array[Char], Int) {
  let out : Array[Char] = []
  let mut i = start
  if view[i + 1] == '/' {
    // 行注释：到行尾（不含换行——等长空格保行列）
    while i < n && view[i] != '\n' {
      out.push(' ')
      i = i + 1
    }
  } else {
    // 块注释：等长空格（换行保留原位）
    out.push(' ')
    out.push(' ')
    i = i + 2
    while i < n {
      if view[i] == '*' && i + 1 < n && view[i + 1] == '/' {
        out.push(' ')
        out.push(' ')
        i = i + 2
        break
      }
      if view[i] == '\n' {
        out.push('\n')
      } else {
        out.push(' ')
      }
      i = i + 1
    }
  }
  (out, i)
}

///|
/// 块注释闭合预检（#32-7）：`/*` 起点向后找不到 `*/` = 未闭合——D-9
/// 「不收」清单项，调用方不消解、剩余原文透传给 parser 拒（曾消费到
/// EOF 静默消解成合法输入——json 严格档拒而 jsonc 档收，档间自相矛盾）
fn block_comment_closed(view : Array[Char], n : Int, start : Int) -> Bool {
  let mut i = start + 2
  while i + 1 < n {
    if view[i] == '*' && view[i + 1] == '/' {
      return true
    }
    i = i + 1
  }
  false
}

///|
/// last_sig ∈ 不消解族（文件首哨兵 / 结构开括号 / 逗号 / 冒号）判定——
/// 开头逗号、孤立逗号、值缺失逗号全部由此落在「保留给 parser 拒」侧
fn comma_unsolvable(last_sig : Char) -> Bool {
  last_sig == '\u{0}' ||
  last_sig == '{' ||
  last_sig == '[' ||
  last_sig == ',' ||
  last_sig == ':'
}

///|
pub fn strip_jsonc(src : String) -> String {
  let view = src.to_array() // code-unit 索引会撞 surrogate——Char 级访问
  let n = view.length()
  let buf = StringBuilder()
  let mut i = 0
  let mut last_sig : Char = '\u{0}' // 最后输出的非空白有效字符（哨兵=文件首）
  let pending : Array[Char] = [] // 暂存区：[0]=逗号，其后=空白与注释空格形态
  let mut in_pending = false
  while i < n {
    let c = view[i]
    // ── pending 态：逗号已暂存，穿透空白与注释找判定字符 ──
    if in_pending {
      if c == ' ' || c == '\t' || c == '\n' || c == '\r' {
        pending.push(c)
        i = i + 1
        continue
      }
      if c == '/' && i + 1 < n && (view[i + 1] == '/' || view[i + 1] == '*') {
        if view[i + 1] == '*' && !block_comment_closed(view, n, i) {
          // 未闭合块注释（#32-7）：暂存原样 flush + 剩余透传——parser 在
          // '/' 本位报 trailing content
          for ch in pending {
            buf.write_char(ch)
          }
          pending.clear()
          while i < n {
            buf.write_char(view[i])
            i = i + 1
          }
          return buf.to_string()
        }
        let (spaces, ni) = comment_to_spaces(view, n, i)
        for sc in spaces {
          pending.push(sc)
        }
        i = ni
        continue
      }
      // 有效字符抵达：判定消解或原样 flush（本字符落回 NORMAL 处理）
      if (c == '}' || c == ']') && !comma_unsolvable(last_sig) {
        buf.write_char(' ') // 逗号位 → 空格（等长）
        for k in 1..<pending.length() {
          buf.write_char(pending[k])
        }
      } else {
        for ch in pending {
          buf.write_char(ch)
        }
        // flush 的暂存首字符是逗号——last_sig 必须跟上：孤立逗号（v,,）
        // 虽因前逗号顶位仍被 parser 拒，但报错会从逗号本位（U+002C）漂到
        // 闭合括号（U+005D）——「保位」锚埋雷实锤此 guard 的真实价值
        last_sig = ','
      }
      pending.clear()
      in_pending = false
      // 不 continue：c 落回下方 NORMAL
    }
    // ── NORMAL 态 ──
    // BOM：仅文件首字符消解为空格（字符串内 U+FEFF 是合法 JSON 字符）
    if i == 0 && c == '\u{FEFF}' {
      buf.write_char(' ')
      i = i + 1
      continue
    }
    // 字符串字面量：原样透传直到闭合引号（\" 转义跳过）——感知的核心
    if c == '"' {
      buf.write_char('"')
      i = i + 1
      let mut closed = false
      while i < n {
        let sc = view[i]
        if sc == '\\' && i + 1 < n {
          buf.write_char(sc)
          buf.write_char(view[i + 1])
          i = i + 2
        } else if sc == '"' {
          buf.write_char('"')
          i = i + 1
          closed = true
          break
        } else {
          buf.write_char(sc)
          i = i + 1
        }
      }
      if !closed {
        // 未闭合字符串：交给 JSON 解析器报错（这里只保透传）
        return buf.to_string()
      }
      last_sig = '"'
      continue
    }
    // 行注释 / 块注释：等长空格（last_sig 不受影响）
    if c == '/' && i + 1 < n && (view[i + 1] == '/' || view[i + 1] == '*') {
      if view[i + 1] == '*' && !block_comment_closed(view, n, i) {
        // 未闭合块注释（#32-7）：剩余原文透传（与未闭合字符串同款交给
        // parser 报错——字符串感知剥离只对**闭合的**注释生效）
        while i < n {
          buf.write_char(view[i])
          i = i + 1
        }
        return buf.to_string()
      }
      let (spaces, ni) = comment_to_spaces(view, n, i)
      for sc in spaces {
        buf.write_char(sc)
      }
      i = ni
      continue
    }
    // 逗号：进暂存（`[1,,]` 的第二逗号经 pending→flush→再进 pending 自然处理）
    if c == ',' {
      pending.push(',')
      in_pending = true
      i = i + 1
      continue
    }
    buf.write_char(c)
    if c != ' ' && c != '\t' && c != '\n' && c != '\r' {
      last_sig = c
    }
    i = i + 1
  }
  // EOF 残留暂存：原样 flush（未闭合尾逗号留给 parser 报）
  for ch in pending {
    buf.write_char(ch)
  }
  buf.to_string()
}
