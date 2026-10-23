// MoonBit 字符串字面量解码器（探针实测：Constant::String 的 raw 未解码——
// 转义序列原样保留在源文本里；值树必须存解码值，输出侧由 stringify 统一转义）
// 转义集（#16 实测对齐 moon 词法宽集）：\' \" \\ \/ \n \r \t \b \f \0
// \xHH \u{1..6 位十六进制} \uXXXX（定长，含 \uD8xx\uDCxx 代理对合成——
// moon check 对上述全族 rc=0，「.json.mbt = 合法 MoonBit 源文件」承诺
// 要求 jsonmbt 接受 moon 接受的一切）

///|
fn unescape_string(raw : String, loc : @basic.Location) -> String raise Diag {
  let buf = StringBuilder()
  let view = raw.to_array() // code-unit 索引会撞 surrogate——Char 级访问
  let n = view.length()
  let mut i = 0
  while i < n {
    let ch = view[i]
    if ch == '\\' {
      i = i + 1
      if i >= n {
        raise malformed_string(raw, loc)
      }
      match view[i] {
        '\'' => buf.write_char('\'')
        '"' => buf.write_char('"')
        '\\' => buf.write_char('\\')
        '/' => buf.write_char('/') // JSON 惯用 \/ —— moon 词法接受（#16 探针）
        'n' => buf.write_char('\n')
        'r' => buf.write_char('\r')
        't' => buf.write_char('\t')
        'b' => buf.write_char('\b')
        'f' => buf.write_char('\f')
        '0' => buf.write_char('\u{0}')
        'x' => {
          // \xHH：恰好两位十六进制
          if i + 2 >= n {
            raise malformed_string(raw, loc)
          }
          match hex_pair(view[i + 1], view[i + 2]) {
            Some(b) => {
              buf.write_char(b.to_int().unsafe_to_char())
              i = i + 2
            }
            None => raise malformed_string(raw, loc)
          }
        }
        'u' =>
          // \u{...}：花括号内 1..6 位十六进制（MoonBit 文档形态）
          if i + 1 < n && view[i + 1] == '{' {
            let mut j = i + 2
            let mut acc : UInt32 = 0U
            let mut digits = 0
            let mut closed = false
            while j < n {
              let c = view[j]
              if c == '}' {
                closed = true
                break
              }
              match hex_digit(c) {
                Some(d) => {
                  acc = acc * 16U + d.reinterpret_as_uint()
                  digits = digits + 1
                  j = j + 1
                }
                None => raise malformed_string(raw, loc)
              }
            }
            // 审 P1-b：代理区（0xD800–0xDFFF）非字符，moon 本尊 [4064] 拒
            // 收——定长 \uXXXX 分支同款检查（#16）此前在花括号路径漏网；
            // 接受后 unsafe_to_char 产代理点、降级链 to_utf8_bytes panic
            //（check 放行 build 崩 = 绕过 D-8 ① 校验先行）
            if !closed ||
              digits == 0 ||
              digits > 6 ||
              acc > 0x10FFFFU ||
              (acc >= 0xD800U && acc <= 0xDFFFU) {
              raise malformed_string(raw, loc)
            }
            buf.write_char(acc.reinterpret_as_int().unsafe_to_char())
            i = j
          } else {
            // \uXXXX 定长 4 位（moon 词法接受——#16 探针；JSON 惯用形态）。
            // 代理对 \uD8xx\uDCxx 合成为单码点（UTF-16 语义）；孤立代理拒
            if i + 4 >= n {
              raise malformed_string(raw, loc)
            }
            let cp = match
              four_hex(view[i + 1], view[i + 2], view[i + 3], view[i + 4]) {
              Some(v) => v
              None => raise malformed_string(raw, loc)
            }
            i = i + 4
            if cp >= 0xD800 && cp <= 0xDBFF {
              // 高代理：必须紧跟 \uXXXX 低位代理
              if i + 6 >= n || view[i + 1] != '\\' || view[i + 2] != 'u' {
                raise malformed_string(raw, loc)
              }
              let lo = match
                four_hex(view[i + 3], view[i + 4], view[i + 5], view[i + 6]) {
                Some(v) => v
                None => raise malformed_string(raw, loc)
              }
              if lo < 0xDC00 || lo > 0xDFFF {
                raise malformed_string(raw, loc)
              }
              let combined = 0x10000 + (cp - 0xD800) * 0x400 + (lo - 0xDC00)
              buf.write_char(combined.unsafe_to_char())
              i = i + 6
            } else if cp >= 0xDC00 && cp <= 0xDFFF {
              // 孤立低代理：病态
              raise malformed_string(raw, loc)
            } else {
              buf.write_char(cp.unsafe_to_char())
            }
          }
        _ => raise malformed_string(raw, loc)
      }
      i = i + 1
    } else {
      buf.write_char(ch)
      i = i + 1
    }
  }
  buf.to_string()
}

///|
fn four_hex(a : Char, b : Char, c : Char, d : Char) -> Int32? {
  match (hex_digit(a), hex_digit(b), hex_digit(c), hex_digit(d)) {
    (Some(w), Some(x), Some(y), Some(z)) =>
      Some(w * 4096 + x * 256 + y * 16 + z)
    _ => None
  }
}

///|
fn hex_digit(ch : Char) -> Int32? {
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
fn hex_pair(hi : Char, lo : Char) -> Byte? {
  match (hex_digit(hi), hex_digit(lo)) {
    (Some(a), Some(b)) => Some((a * 16 + b).to_byte())
    _ => None
  }
}

///|
fn malformed_string(raw : String, loc : @basic.Location) -> Diag {
  Diag(
    code=JBadLiteral,
    loc~,
    message="malformed escape sequence in string literal \"\{raw}\"",
    help=None,
    path="",
  )
}
