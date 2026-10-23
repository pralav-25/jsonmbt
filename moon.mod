name = "vitro/jsonmbt"

version = "0.1.0"

readme = "README.md"

repository = "https://github.com/rustin-beep/jsonmbt"

license = "MIT"

// 与 GitHub 仓库 topics 逐字一致（元信息单点归一，改一处须改另一处）

keywords = [
  "json",
  "config",
  "configuration",
  "schema",
  "typed",
  "codegen",
  "data-format",
  "deterministic",
  "serialization",
  "moonbit",
]

description = "typed JSON source files for MoonBit (.json.mbt) — moon-checked, fmt-stable, degrade-to-JSON"

import {
  "moonbitlang/parser@0.4.4",
  "moonbitlang/lexer@0.4.4",
  "moonbitlang/x@0.5.5",
}
