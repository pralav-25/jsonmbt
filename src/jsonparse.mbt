// 自持 RFC 8259 解析器（importer 的输入侧基石）——core/json 满足不了三件事：
// ① number 源文本形态（Int/Double 判型依据——D-11 ②；core 的 repr 仅超范围保留）
// ② 重复键拒绝（D-11：JSON 层重复键是病态输入，不替它选语义——core 静默后者覆盖）
// ③ 顶层诊断的行列（core 的 Position 无文件名语义）
// 键序：Map 插入序 = 源序（D-11 ④）。深度预算与 L0 同源（MAX_DEPTH）。
// 产物 = Json 值树（Number 全带 repr=源文本——与降级器同一值模型，N 单源消费）

///|
priv struct JParser {
  view : Array[Char] // Char 级访问（StringView 索引是 code unit——surrogate 陷阱）
  n : Int32
  mut pos : Int32
  mut line : Int32 // 当前行（1 起）
  mut bol : Int32 // 当前行首偏移（列 = pos - bol + 1，编译器口径）
  fname : String
}

///|
fn JParser::new(src : String, fname : String) -> JParser {
  let view = src.to_array()
  // n = 码点数（view.length）——src.length() 是 UTF-16 码元数：星面字符
  // （emoji 代理对）时码元 > 码点，n 虚大 → 索引越界 panic（Vitro
  // catalog.json 62 个 emoji 实锤——fail loud 契约不允许 panic）
  { view, n: view.length(), pos: 0, line: 1, bol: 0, fname, }
}

///|
fn jp_error(p : JParser, code : JCode, msg : String, pos~ : Int32 = -1) -> Diag {
  let at = if pos >= 0 { pos } else { p.pos }
  // bol 是「错误位置所在行」的行首——从记录点重算（换行已即时推进 line/bol）
  Diag(
    code~,
    loc={
      start: { fname: p.fname, lnum: p.line, bol: p.bol, cnum: at, },
      end: { fname: p.fname, lnum: p.line, bol: p.bol, cnum: at, },
    },
    message=msg,
    help=None,
    path=p.fname,
  )
}

///|
fn chars_slice(view : Array[Char], start : Int32, stop : Int32) -> String {
  let buf = StringBuilder()
  for i = start; i < stop; i = i + 1 {
    buf.write_char(view[i])
  }
  buf.to_string()
}

///|
fn jp_peek(p : JParser) -> Char? {
  if p.pos < p.n {
    Some(p.view[p.pos])
  } else {
    None
  }
}

///|
fn jp_advance(p : JParser, ch : Char) -> Unit raise Diag {
  if p.pos >= p.n || p.view[p.pos] != ch {
    let got = match jp_peek(p) {
      Some(c) => "'\{c}'"
      None => "end of input"
    }
    raise jp_error(p, JJsonSyntax, "invalid JSON: expected '\{ch}', got \{got}")
  }
  ignore(())
  if ch == '\n' {
    p.line = p.line + 1
    p.bol = p.pos + 1
  }
  p.pos = p.pos + 1
}

///|
fn jp_skip_ws(p : JParser) -> Unit {
  while p.pos < p.n {
    match p.view[p.pos] {
      ' ' | '\t' | '\n' | '\r' => {
        if p.view[p.pos] == '\n' {
          p.line = p.line + 1
          p.bol = p.pos + 1
        }
        p.pos = p.pos + 1
      }
      _ => break
    }
  }
}

///|
/// 码点 → `U+XXXX` 形态（十六进制，不足 4 位补零）——诊断消息用。
/// 旧实现把**十进制**码点直接接在 `U+` 后（`]` = 93 十进制 → 报成 "U+93"，
/// 误导定位）；十六进制才是 `U+` 惯例。
fn cp_label(cp : Int32) -> String {
  let digits = "0123456789ABCDEF".to_array()
  let mut v = cp
  let rev : Array[Char] = []
  if v <= 0 {
    rev.push('0')
  }
  while v > 0 {
    rev.push(digits[v % 16])
    v = v / 16
  }
  let buf = StringBuilder()
  buf.write_string("U+")
  let mut pad = 4 - rev.length()
  while pad > 0 {
    buf.write_char('0')
    pad = pad - 1
  }
  let mut i = rev.length() - 1
  while i >= 0 {
    buf.write_char(rev[i])
    i = i - 1
  }
  buf.to_string()
}

///|
pub fn json_parse(src : String, fname~ : String = "<json>") -> Json raise Diag {
  let p = JParser::new(src, fname)
  jp_skip_ws(p)
  let v = jp_value(p, 0)
  jp_skip_ws(p)
  if p.pos < p.n {
    raise jp_error(
      p,
      JJsonSyntax,
      "invalid JSON: trailing content after the top-level value ('\{p.view[p.pos]}')",
    )
  }
  v
}

///|
fn jp_value(p : JParser, depth : Int32) -> Json raise Diag {
  if depth > MAX_DEPTH {
    raise jp_error(
      p,
      JDeep,
      "JSON nesting exceeds the depth budget of \{MAX_DEPTH}",
    )
  }
  jp_skip_ws(p)
  match jp_peek(p) {
    None =>
      raise jp_error(p, JJsonSyntax, "invalid JSON: unexpected end of input")
    Some('{') => jp_object(p, depth)
    Some('[') => jp_array(p, depth)
    Some('"') => Json::string(jp_string(p))
    Some('t') => {
      jp_literal(p, "true")
      Json::boolean(true)
    }
    Some('f') => {
      jp_literal(p, "false")
      Json::boolean(false)
    }
    Some('n') => {
      jp_literal(p, "null")
      Json::null()
    }
    Some(c) =>
      if c == '-' || (c >= '0' && c <= '9') {
        jp_number(p)
      } else {
        // 不可见字符（BOM 等）按码点文本显示（审 P3：unexpected '' 不可见）
        raise jp_error(
          p,
          JJsonSyntax,
          "invalid JSON: unexpected character \{cp_label(c.to_int())}",
        )
      }
  }
}

///|
fn jp_literal(p : JParser, word : String) -> Unit raise Diag {
  for ch in word {
    if p.pos >= p.n || p.view[p.pos] != ch {
      raise jp_error(p, JJsonSyntax, "invalid JSON: expected '\{word}'")
    }
    p.pos = p.pos + 1
  }
}

///|
/// RFC 8259 number 文法：-?(0|[1-9]\d*)(\.\d+)?([eE][+-]?\d+)?——严格（前导零拒）
fn jp_number(p : JParser) -> Json raise Diag {
  let start = p.pos
  if jp_peek(p) == Some('-') {
    p.pos = p.pos + 1
  }
  // int 部分
  match jp_peek(p) {
    Some('0') => p.pos = p.pos + 1
    Some(c) if c >= '1' && c <= '9' =>
      while jp_peek(p) is Some(d) && d >= '0' && d <= '9' {
        p.pos = p.pos + 1
      }
    _ => raise jp_error(p, JJsonSyntax, "invalid JSON: malformed number")
  }
  // frac
  if jp_peek(p) == Some('.') {
    p.pos = p.pos + 1
    if !jp_digit_ahead(p) {
      raise jp_error(
        p,
        JJsonSyntax,
        "invalid JSON: malformed number (digits required after '.')",
      )
    }
    while jp_peek(p) is Some(d) && d >= '0' && d <= '9' {
      p.pos = p.pos + 1
    }
  }
  // exp
  match jp_peek(p) {
    Some('e') | Some('E') => {
      p.pos = p.pos + 1
      if jp_peek(p) is Some(s) && (s == '+' || s == '-') {
        p.pos = p.pos + 1
      }
      if !jp_digit_ahead(p) {
        raise jp_error(
          p,
          JJsonSyntax,
          "invalid JSON: malformed number (digits required in exponent)",
        )
      }
      while jp_peek(p) is Some(d) && d >= '0' && d <= '9' {
        p.pos = p.pos + 1
      }
    }
    _ => ()
  }
  let text = chars_slice(p.view, start, p.pos)
  // Double 值：交 core/json（单源；纯数字文本必成）
  let d : Double = try {
    match @json.parse(text) {
      Number(d, ..) => d
      _ => 0.0
    }
  } catch {
    _ => 0.0
  }
  Json::number(d, repr=text)
}

///|
fn jp_digit_ahead(p : JParser) -> Bool {
  jp_peek(p) is Some(d) && d >= '0' && d <= '9'
}

///|
/// 字符串：全转义（\" \\ \/ \b \f \n \r \t \uXXXX 含代理对；孤立代理拒绝）
fn jp_string(p : JParser) -> String raise Diag {
  jp_advance(p, '"')
  let buf = StringBuilder()
  let mut closed = false
  while p.pos < p.n {
    let c = p.view[p.pos]
    if c == '"' {
      p.pos = p.pos + 1
      closed = true
      break
    }
    if c == '\\' {
      p.pos = p.pos + 1
      if p.pos >= p.n {
        break
      }
      match p.view[p.pos] {
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/')
        'b' => buf.write_char('\b')
        'f' => buf.write_char('\f')
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'u' => {
          p.pos = p.pos + 1
          let cp = jp_hex4(p)
          // 代理对：D800-DBFF 高位须接 DC00-DFFF 低位；孤立代理 = 病态，诚实拒绝
          if cp >= 0xD800 && cp <= 0xDBFF {
            if p.pos + 1 < p.n &&
              p.view[p.pos] == '\\' &&
              p.view[p.pos + 1] == 'u' {
              let save = p.pos
              p.pos = p.pos + 2
              let low = jp_hex4(p)
              if low >= 0xDC00 && low <= 0xDFFF {
                let combined = 0x10000 + (cp - 0xD800) * 0x400 + (low - 0xDC00)
                buf.write_char(combined.unsafe_to_char())
              } else {
                raise jp_error(
                  p,
                  JJsonSyntax,
                  "invalid JSON: lone surrogate \\u...",
                  pos=save,
                )
              }
            } else {
              raise jp_error(
                p,
                JJsonSyntax,
                "invalid JSON: lone surrogate \\u...",
              )
            }
          } else if cp >= 0xDC00 && cp <= 0xDFFF {
            raise jp_error(
              p,
              JJsonSyntax,
              "invalid JSON: lone surrogate \\u...",
            )
          } else {
            buf.write_char(cp.unsafe_to_char())
          }
          continue // hex4 已推进 pos
        }
        other =>
          raise jp_error(
            p,
            JJsonSyntax,
            "invalid JSON: invalid escape '\\\{other}'",
          )
      }
      p.pos = p.pos + 1
    } else if c == '\n' {
      raise jp_error(p, JJsonSyntax, "invalid JSON: raw newline inside string")
    } else if c.to_int() < 0x20 {
      // RFC 8259 §7：控制字符必须转义——裸控制字符是病态输入，诚实拒绝
      raise jp_error(
        p,
        JJsonSyntax,
        "invalid JSON: raw control character inside string (must be escaped)",
      )
    } else {
      buf.write_char(c)
      p.pos = p.pos + 1
    }
  }
  if !closed {
    raise jp_error(p, JJsonSyntax, "invalid JSON: unterminated string")
  }
  buf.to_string()
}

///|
fn jp_hex4(p : JParser) -> Int32 raise Diag {
  let mut v = 0
  for i = 0; i < 4; i = i + 1 {
    match jp_peek(p) {
      Some(c) => {
        let d = if c >= '0' && c <= '9' {
          c.to_int() - '0'.to_int()
        } else if c >= 'a' && c <= 'f' {
          c.to_int() - 'a'.to_int() + 10
        } else if c >= 'A' && c <= 'F' {
          c.to_int() - 'A'.to_int() + 10
        } else {
          -1
        }
        if d < 0 {
          raise jp_error(
            p,
            JJsonSyntax,
            "invalid JSON: \\u escape requires 4 hex digits",
          )
        }
        v = v * 16 + d
        p.pos = p.pos + 1
      }
      None =>
        raise jp_error(
          p,
          JJsonSyntax,
          "invalid JSON: \\u escape requires 4 hex digits",
        )
    }
  }
  v
}

///|
fn jp_array(p : JParser, depth : Int32) -> Json raise Diag {
  jp_advance(p, '[')
  let arr : Array[Json] = []
  jp_skip_ws(p)
  if jp_peek(p) == Some(']') {
    p.pos = p.pos + 1
    return Json::array(arr)
  }
  while true {
    arr.push(jp_value(p, depth + 1))
    jp_skip_ws(p)
    match jp_peek(p) {
      Some(',') => p.pos = p.pos + 1
      Some(']') => {
        p.pos = p.pos + 1
        break
      }
      _ =>
        raise jp_error(
          p,
          JJsonSyntax,
          "invalid JSON: expected ',' or ']' in array",
        )
    }
  }
  Json::array(arr)
}

///|
fn jp_object(p : JParser, depth : Int32) -> Json raise Diag {
  jp_advance(p, '{')
  let obj : Map[String, Json] = Map([])
  jp_skip_ws(p)
  if jp_peek(p) == Some('}') {
    p.pos = p.pos + 1
    return Json::object(obj)
  }
  while true {
    jp_skip_ws(p)
    if jp_peek(p) != Some('"') {
      raise jp_error(
        p,
        JJsonSyntax,
        "invalid JSON: object key must be a string",
      )
    }
    let key = jp_string(p)
    // D-11：重复键 = 病态输入，不替它选语义（对齐「降级产物绝不带重复键」）
    if obj.contains(key) {
      raise jp_error(
        p,
        JDupKey,
        "duplicate key \"\{key}\" in JSON object",
        pos=p.pos,
      )
    }
    jp_skip_ws(p)
    jp_advance(p, ':')
    let v = jp_value(p, depth + 1)
    obj[key] = v
    jp_skip_ws(p)
    match jp_peek(p) {
      Some(',') => p.pos = p.pos + 1
      Some('}') => {
        p.pos = p.pos + 1
        break
      }
      _ =>
        raise jp_error(
          p,
          JJsonSyntax,
          "invalid JSON: expected ',' or '}' in object",
        )
    }
  }
  Json::object(obj)
}
