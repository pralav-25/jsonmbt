// cmd 层单测锚（层 1 内层；native-only 包——跑法
// MOON_CC=clang moon test -p vitro/jsonmbt/cmd/jsonmbt --target native）

///|
test "#32-1 : normalize_eol 全量归一（core String::replace 只换首处）" {
  // 审阅实锤：replace 单次语义让多行 CRLF 只归一首个 \r\n，幂等闸/doctor/
  // migrate 三面假红——CRLF 只来自外部 checkout（自家产物恒 LF），锚须专门构造
  inspect(normalize_eol("a\r\nb\r\nc"), content="a\nb\nc")
  inspect(normalize_eol("a\r\nb"), content="a\nb")
  inspect(normalize_eol("a\nb"), content="a\nb")
}
