# MoonBit 语言与工具链陷阱（快照）

> **来源**：Vitro 仓 `moonbit/AGENTS.md`（commit 8b7c67db，as_of 2026-10-06，moon 0.1.20260920）的全文快照——跨仓不引用所以整段复制。文中「本仓」与包路径（`bytecode/emitter.mbt` 等）指 **Vitro**；jsonmbt 侧**按规则参照，代码位置按需重找**。条目编号保持原号以便两边对照与后续同步。


> 以下是**工程语法/工具层**一手实证（多数来自真实编译器报错与探针），jsonmbt 开发前当既定事实读，可省一轮编译-报错循环。

1. **`ref` 是保留字**——可变局部状态用 `let mut x = 0`（`Array.push` 改内容**不需要** mut，mut 只管重新绑定；unused_mut 默认 error）。
2. **比较 trait 是 `Compare` 不是 `Ord`**——`derive(Debug, Eq, Compare, Hash, Default)`；derive 子句在类型体 `{}` 之后。
3. **`derive` 不能作方法名**（关键字）——S1 用 `Pos::from_byte_off` 替代。
4. **枚举构造器可与其余类型名同名**（`Type::Int` 与内置 `Int` 按期望类型消歧）；但**两个枚举的同名构造器**（`AssignOp::Assign` vs `Expr::Assign`）在构造与模式两处都要显式 `Expr::Assign(...)` 限定。
5. **跨包类型必须 `@pkg.` 前缀**——包括 struct 字段类型与函数签名参数（`loc : @source.SourceLoc`），裸类型名会撞"未定义"或静默歧义。
6. **无参构造器模式**要逐参数通配：`Literal(_, _, _)`——`Literal(..)` 不是合法通配。
7. **`for k, v in` 只解构 Map**——元组数组迭代用 `for t in arr` 后 `t.0 / t.1`。
8. **fn 参数不能 `mut`**（`mut stack : ...` 是解析错误）；局部重绑定不需要时勿加 mut。
9. **大写开头的局部绑定非法**（`let L = ...` 编译错）。
10. **`assert_true(x)` 单参数**——带消息断言用 `guard cond else { fail("...") }`。
11. **`String::substring` 已弃用**——用切片 `s[a:b]`（ASCII 安全场景免 try）+ `.to_owned()`（视图转拥有串；`.to_string()` 在视图上同样弃用）。
12. **`<+` / `<?` 宏右侧只能接模板字符串/对象字面量**——任意表达式（函数调用、Int）不合法，用 `buf.write_string("...\{interp}")`。
13. **`1e16` 等 e 记法浮点字面量不可用——勘误（jsonmbt 探针⑥ + P1-1 实锤）**：原文不准。实情是**纯整数尾数接指数（`1e2`）解析错**（被拆成 `1`+标识符），**须带小数点**（`1.5e3`/`1.0e2` 合法）。任何「源文本直传进 MoonBit 字面量」的生成器必须做 `ensure_double_syntax` 补点改写（jsonmbt src/codegen.mbt）——这条认知差正是 jsonmbt 审 P1-1（import 产非法产物）的根因。
14. **`Double::to_string` 与 serde_json/ryu 两处分歧**（实测）：整值 `1.0 → "1"`、负零 `-0.0 → "0"`；中段指数区间（≥1e16 / ≤1e-6）两侧记法不同。**JSON 浮点文本化必须走 `@ast.double_to_json_text`**（ryu-pretty 全区间对齐 + 非有限 → null）——那是单源，禁再写一份。
15. **moon fmt 宽度按 UTF-8 字节计**（中文 3 字节；超 ~84 字节爆开/折行）——**生成物与 fmt 会互踩**：gen_diag 的解法是生成流程内置 `moon fmt`，产物形态以 fmt 为准，gen 原始输出只是中间态。任何新生成器沿用此模式。
16. **doc 测试（docstring `mbt check` 块与 `*.mbt.md`）是黑盒**——被测包自动 import 为 `@self`，构造器要 `@pkg.Type::Variant` 形态；README.mbt.md 同理（它同时是可执行测试文件）。
17. **`moon.mod` / `moon.pkg` 是新格式**（非 .json）；`moon.pkg` 的 import 块声明依赖，代码内一律 `@alias.fn` 调用。
18. **mooncakes 发布规则**：module 名首段**必须等于发布者用户名**（`vitro/engine` ↔ 账号 `vitro`；403 User mismatch 即此因）；发布后 checksum 入 registry **不可覆盖**——修复只能递增版本；readme 字段须指向**根 `README.md`**（`README.mbt.md` 不会被模块页渲染）；索引同步有数分钟延迟（`moon add` 暂时 404 是正常节奏，轮询即可）。
19. **本仓库 bash 工具层的 heredoc 会吃一层反斜杠转义**（`\\n` 变真换行、`\r\n` 字面量损毁）——跨 heredoc 写 Go/代码文件时用 `chr()` 拼接或 python 中转写盘；此坑曾致 gen_diag 归一逻辑静默变空操作（P2-1 复盘）。
20. **core `Map`/`Set` 是可变哈希结构**（`Map::set(k,v)` / `Set::add(k)` 原地、返回 Unit；S3 实测）——勘察 M3 设想的"不可变结构共享快照"不成立，回滚快照 = `.copy()` 整表拷贝（教学符号表小，可接受）。
21. **`loop { ... }` 是函数式循环（deprecated 语法且 `break` 不适用）**——命令式循环写 `while true { ... break }`（S3 瀑布实测）。
22. **顶层常量用 `const`**（`let MAX_X = ...` 大写绑非法：Expected lower case identifier）。
23. **match guard 必须与模式同行**（`_ if cond =>` 跨行非法）；**或模式分支的构造器各自全参展开**（`Reference(..)` 不合法——`..` 剩余通配不存在，逐参数 `_`）。
24. **`String` 索引/`s[i]` 返回 UInt16 码元**（非 Char）——`write_char(s[i])` 类型错；切片 `substring(start=a, end=b)` 命名参数形态（位置参数形态非法）。
25. **数值位模式重解释**：`UInt64::to_int64` = `%u64.to_i64_reinterpret`（bitcast，正是 Rust `as i64`）；`Int64::to_int` 语义未文档化——i64→i32 截断自己写（低 32 位符号解释，见 parser/decl.mbt `i64_to_i32_bits`）；`Int::to_int64` 是符号扩展（= Rust `as i64`）。
26. **wbtest 不携带 `for "test"` import**（黑盒专用配置）——白盒测试要跨包输入就手工构造（如 token 数组），或把用例放黑盒。
27. **JSON 字符串输出必须转义 < 0x20 控制字符**（`\u00XX`，serde_json 口径）——C 转义序列（`\x4`）解析出的真字节原样写出即非法 JSON（S3 由 baseline 的 string_escape_octal_hex.c 差分抓出）。
28. **wasm 测试运行时的栈预算比 moonrun 更紧**（S3 实测：`interpret_declarator_node` **递归解释**形态 900 层过 / 1200 层溢出——目标 wasm；同函数迭代化后 1250 层全存活；`node_cross_count` 的纯计数递归在 wasm-gc/native 三后端 1250 层存活（S3 审阅实测）——旧区间只适用于"递归解释"形态，勿外推到计数函数）——深结构处理一律迭代化（显式栈/下钻折叠），不能依赖"Rust 侧能过的深递归这里也能过"。
29. **`String` 的 `compare` 与 `<`/`>` 均非字典序**（S5 bytecode 白盒实测：`"delta" > "charlie"` 为 **false**、`"delta".compare("charlie")` 返回 **-1**——疑似长度优先序）——排序/对拍类逻辑**禁用内置 String 比较**，按码元逐位自写字典序（见 bytecode/emitter.mbt `str_cmp`）；Go canonicalize 的 sort.Strings 是字节字典序，ASCII 域两者等价，非 ASCII 键域需显式裁定。

## MoonBit 语义实证补充（S6 建包批，2026-09-23 探针实测）

> 以下全部由一次性探针程序当场跑出真值（`inspect` 期望值锚），非文档推断。建新包前先把这些当既定事实，可省一轮编译-报错循环。

30. **struct 是"按引用"传递的**——**字段变更对调用方可见**，普通参数与 `self` 一样生效（实测：`fn bump(c : ProbeCtr) { c.n = c.n + 1 }` 连调两次后调用方看到 `n == 2`）。⇒ ① 需要"值语义"时得显式复制；② **这正是本仓 `MemoryMap`/`Memory` 能把"容器字段的变更"直接暴露给下游的原因**；③ 也意味着"返回内部结构"会暴露可写句柄，要控面就得控制返回类型。
31. **`mut` 字段的赋值不要求 `let mut`**——`let r = Rec::{ ... }` 后 `r.f = v` 合法（`mut` 只管**字段**，不管绑定；与陷阱 #1"mut 只管重新绑定"互补：那一句说的是局部变量，字段同理但受限更松）。match 绑定（`Some(r) => { r.f = v }`）同样合法。**结构展开 `{ ..r, f: v }` 可用**。
32. **`for k, v in` 对数组是 `(下标, 元素)` 解构，不是元组解构**（陷阱 #7 的补全）——`for a, b in array_of_tuples` 拿到的是 `Int` 下标，静默错类型，必须 `for t in arr { t.0 / t.1 }`；只有 `Map` 是 `(键, 值)`。
33. **core 的 `Map` 即 LinkedHashMap**（`linked_hash_map.mbt` 实现的就是 `Map`）——**迭代序 = 插入序**，且既有键 `set` **保持原插入位**（等键分支只写 value）；但**没有 `get_mut`**——就地改值要么 `update(k, fn(V?) -> V?)`（闭包内改 mut 字段），要么 `get` 出来改完 `set` 回去。⇒ "Vec + 平行索引"可整体换成 `Map[K, V]`：O(1) 定位 + 保序 + **失配面归零**（S6 memory 的 regions 即此形态，消掉坑 6 的根因）。
34. **弃用 API 三例（`moon check` 会给 `deprecated` 告警）**：`Array::new(capacity=)` → `Array(capacity=)`、`Deque::new()` → `Deque([])`、`Int::to_uint` / `UInt::to_int` → `reinterpret_as_uint` / `reinterpret_as_int`（**语义相同，只是把"重解释"写明**；注意 `to_uint64()` 未弃用）。
35. **`FixedArray[Byte]` 只有写侧 LE 原语**（`unsafe_write_uint32_le` / `..._uint64_le`），**读侧原语只在 `Bytes`**（`Bytes::unsafe_read_uint32_le`）——用 `FixedArray[Byte]` 当内存本体时，读必须手工 4/8 次索引拼装（与 Rust `i32::from_le_bytes([m[a],...])` 同形）。
36. **`moon build --target native main` 的 `main` 是目录过滤器而非包名**——目录是否被当包**只看有无 moon.pkg**：只写 main/main.mbt 漏 moon.pkg ⇒ 该目录不算包 ⇒ 构建任务数 0 ⇒ **EXIT=0 零输出零产物静默不构建**（2026-09-27 用户 bench 巩固工程实测；判定看"ran N tasks"的 N）。顺带：main 函数签名须无参 `fn main { ... }`（带参/带 raise 均拒绝），参数化用编译期 const 切换重编译。
37. **`String::replace` 只替换首个匹配**（2026-09-29 stdin 34 例批实锤：`a
b
c`.replace 得 `a-bc`）——全量替换必须循环 `while contains { replace }`（先例 `host_io.mbt::from_stdin_text` 的 CRLF 规整）；单符号场景（指数文本剥 +/-）不受影响。同族新单源：`InputState::from_stdin_text`（stdin 切行——行含尾换行，serve input 参数 / cmd/run -i 共用），勿再散拼。
38. **经 shell/python 管道写源码时反斜杠转义会层层衰减**（2026-09-23 P2-NUL 事故）：JSON→shell→python 三级解码会吃掉层层反斜杠（两层写法只剩一层，再经 python 字符串解析即成真字节）——`b"hello\x00"` 落成二进制文件、git 判 `w/-text`、15KB 测试 diff 不可见。写含转义序列的源码一律用 `chr(92)` 构造，或写完后 `source_hygiene` 扫一遍兜底。同族：注释里的 \n 会断行、Go 字符串里的 \n 会变真换行。
39. **测试宏的说明文字必须用 `msg=` 具名参数**——`assert_eq(a, b, "说明")` 会被拒（"requires 2 positional arguments"），写 `assert_eq(a, b, msg="说明")`；`assert_true`/`assert_false` 同理。另：**`_` 不能作 `for` 循环变量名**（`for _ = 0; ...` 是解析错误，换 `i`/`n`）。

40. **wasm-gc 导出三事实（2026-09-29 批五号一手实证）**：① 导出 = `pkgtype(kind: "foreign_library")` + `#export_name("名")` 属性（executable 形态只导 `_start`，pub fn 不自动导出）；② String 直传 = moon.pkg `options("link": {"wasm-gc": {"use-js-builtin-string": true}})` + 宿主 `new WebAssembly.Module(buf, {builtins:['js-string'], importedStringConstants:'_'})`（不开内建则 String 是 GC 引用类型、宿主无法构造——「type incompatibility」）；③ foreign_library 不拉 println 链 ⇒ 产物零**功能性** imports（import 段仅 "_" 字符串常量模块——字节层 ≈2000 条，旧 Node 以真实 import 呈现需宿主兜底）。注意 moon.pkg 的 link 不是顶层键（`link = {...}` 解析失败——须 `options("link": {...})`）。

41. **moon 跨会话/跨 target 增量缓存毒化（2026-10-06 批二双臂对拍实锤）**：并发会话改源后（实例：批二-b 改 `host/host_format.mbt` 的 printf 旗标），本会话 `moon build --release --target wasm-gc` 增量判定 up-to-date——产物**仍是旧代码**，而同刻构建的 native 产物是对的——「同源不同果」酷似 wasm-gc 后端语义 bug，极易误诊；`rm -rf moonbit/_build/wasm-gc` 强制全量重建即愈。**纪律：跨会话接过工作区后消费 wasm-gc/native 产物做行为验证前，先清对应 `_build/<target>` 增量重建**（CI 干净检出天然免疫，本地是唯一暴露面）；「产物 mtime 新」不构成「含新代码」证据（指纹一致三方全旧的 #81 形态同族）。双臂对拍（同输入跑 wasm 壳 vs native exe，`scripts/vitro_cli_smoke`）是最便宜的行为指纹。连坐提醒：`cp` 到 demo/ 的 wasm.wasm 若源自毒化构建同样带毒，demo_smoke 用例不踩该面时不报警。

42. **新工具链要求 `moon.mod` + 块式 `moon.pkg`（jsonmbt 侧回灌，2026-10-06 探针⑥实证）**：rr_moon_mod 特性的新工具链下 `moon.mod.json` / JSON 式 `moon.pkg` 解析失败——必须 `moon.mod` + 块式 `moon.pkg`。本条为 jsonmbt 侧实证回灌（非 Vitro 快照原生条目；编号沿用 jsonmbt PLAN §9 的 #42 登记，Vitro 侧将来若另立 #42 以两侧标注为准）。



43. **`.json.mbt` 的 moon 静态保护只在「带 `moon.pkg` 的目录」内生效**（2026-10-07 Vitro 迁移批 C 实证，11/11 逐张注入验证）：moon 只把**自带 `moon.pkg` 的目录**当包并编译其中的 `.json.mbt`。只在仓根放一个 `moon.pkg` 时 `moon check` 报 `ran 1 task`——**文件根本没被读**，等于买了 moon 工具链的静态检查却没接上（Vitro 首次迁移 11 张全放 `scripts/` 下、`moon.mod` 在 `moonbit/`，moon 一次都没参与，返工两轮）。另：`moon build` **不**检查孤立包（注入类型错仍 rc=0），`moon test` 与 `moon check` 才会红；`moon check` **全量会跳过孤立包**（须 `moon.work` 多 workspace 或显式进目录）。`moon.pkg` 只能空块——`{}` 与块式 `import ()` 均报 `Failed to calculate build plan`（呼应陷阱 42）。

44. **workspace 根跑无参数 `moon fmt` 会重排无关模块的源文件**（2026-10-07 Vitro 实测，13 行 diff）：`moon.work` 多成员仓里，无参数 `moon fmt`（336 tasks）把 `moonbit/codegen/addr.mbt` 的 `match` 分支缩进整体重排，而该文件本批并未触碰（已 `git checkout` 回滚）。**必须限定成员**：`moon fmt scripts`。另两条同源陷阱：① `moon fmt` 会把 0 字节 `moon.pkg` 改写成 1 字节换行（幂等，不破坏包识别），别误判为文件被改坏；② 判定 moon 是否真检查了某文件**不能信 task 数或 "no work to do"**——用 `moon check --dry-run | grep 'workspace-path'` 看真实编译单元，再用跨类型注入看 rc（同类型改数值不红是**正确的**，moon 抓类型/字段不抓业务语义）。


45. **`moon fmt <path>` 把 path 当「当前项目内的包过滤 pattern」——项目外/非包路径静默跳过且 rc=0**（2026-10-08 doctor 影子 fmt 三点对照探针实证，Git Bash `/tmp`=TEMP 同目录对照）：① cwd 在 moon 项目内、path 指向**项目外**目录（自带 moon.mod 也不行）→ rc=0 无输出不动作（假成功）；② cwd 在项目内、path 是**无 moon.pkg 的子目录** → 同样 rc=0 静默跳过；③ 报错形态仅在 cwd 自身不在任何 moon 项目时出现（"not in a Moon project"探测的是 **cwd**，与 path 参数无关）。**跨项目 fmt 的唯一可靠形态 = `cd <目标项目> && moon fmt`（无参数）**。jsonmbt 侧影响：doctor 影子检查用 `cd` 形态（cmd/jsonmbt/doctor.mbt `run_moon_fmt_in`）；给用户的 fix 文案须先接 moon.pkg 再 fmt（否则是静默无效指令）。与 #43/#44 同族——moon 工具链的「静默假成功」家族。

46. **moon 编译面扫描不豁免 `.gitignore`——「带 `moon.pkg` 的目录」全吞，嵌套 module 才是唯一边界**（2026-10-09 jsonmbt 仓探针双证）：`tmp/` 已在 .gitignore，放一个带 `moon.pkg` 的探针目录（内含故意未定义类型），仓根 `moon check` **照样编译报红**——报错日志引用 tmp 下文件路径 + `_build/**/check/tmp/<pkg>` 留编译产物双证。子目录自带 `moon.mod`/`moon.work`（嵌套 module）则被上级跳过（实测零产物）。**判「moon 会不会检查某目录」只看有无 moon.pkg 与嵌套边界，gitignore/是否入库无关**（AGENTS「环境注意」探针条目的机制根据）。逃生门现状（2026-10-09 实测）：官方逃生门是 moon.mod 的 `exclude`（#51/#593 已修到「exclude 可覆盖 gitignore」），**但 TOML 格式 `moon.mod` 不认 `exclude` 键**（`Unexpected key 'exclude' found in moon.mod`）——JSON 格式的逃生门在 TOML 新格式上缺失，rr_moon_mod 必选仓（本仓）暂无配置面逃生门，只剩纪律防；上游缺口待提 issue。

47. **moon 从 cwd 向上冒泡找最近构建文件作 root——子目录裸跑 `moon build` 构建的是「最近构建文件所在仓」**（2026-10-09 jsonmbt 仓实测）：在只有 `moon.pkg`（无 moon.mod）的子目录裸跑 `moon build`，构建的是仓根**全仓**（输出全是 src/ 警告），`_build` 落仓根；子目录自带 `moon.mod` 则自成 root。**tmp/vitro-pilot（Vitro 克隆，仓根无构建文件）里跑 `moon build` → root 冒泡到 jsonmbt 仓根** = 2026-10-08「构建落在错误的位置、exe 根本没更新、BYTE-DIFF 全是旧 exe 假象」事故的机制。纪律：行为验证前确认 cwd=root；嵌套克隆仓里跑 moon 命令前先想 root 是谁。同族事实：**moon build/check 失败退出码恒 127**（shell 惯例 127=command not found——判「命令不存在」前先看 stderr 全量）。

48. **Windows 构建报「拒绝访问 (os error 5)」/`Sys_error("...: Permission denied")` = 产物文件被外部句柄持有的写路径共享冲突**（2026-10-09 jsonmbt 仓受控复现，**推翻 2026-10-07「`.moon-lock` 被占」旧归因**）：python 以**共享读**（GENERIC_READ+FILE_SHARE_READ，最温和形态）持住 `_build` 产物 → 触发重编 → moon 报 `Sys_error("...p_flat.core: Permission denied")` rc=127；`FILE_FLAG_DELETE_ON_CLOSE`（delete-pending，rm -rf 清理中间态）同样复现。机制=Windows **写/替换**被持有文件的共享冲突以 ACCESS_DENIED 报出（CRT 层映射 "Permission denied"、Win32 层原生「拒绝访问 (os error 5)」，两文案同因=moon 两条写路径）；「**打开**」路径的冲突才报 32（SHARING_VIOLATION）——受控实验打「打开」路径只能复现 32，打「写」路径才复现 5。**`--target-dir` 有效的真因是换掉产物目录避开被持文件，不是绕开锁**（msvcrt.locking 锁 `.moon-lock` 时 moon 优雅阻塞——锁不拦 CreateFile，moon 间本就靠锁优雅互斥）。真实诱因=会话开头窗口：上会话清理的 delete-pending/编辑器 LSP·杀毒读产物/并发会话工具持句柄。处置：瞬时句柄重试即愈；频发时 `--target-dir <临时目录>`；上游改进候选=产物写失败带退避短重试（杀毒/LSP 瞬时句柄是高频真实诱因，业界常规）。与 #41 同族（#41 是「静默骗人」，本条是「当场挡路」——后者危险度低但别再错怪 moon-lock）。

49. **mooncakes 的 `moonbitlang/parser` 库与 moonc 内置 parser 是两份代码——关键字行为有缝**（2026-10-13 jsonmbt 仓 #38 探针实证）：字段位 `extend`（moon 硬关键字表成员）——moonc v0.10.15 编译 [3002] Parse error 硬拒，而 mooncakes parser 库 0.4.4 **放行**（`jsonmbt check` 走库 parser → rc=0 假绿）；`var` 类词两份表都有 → jsonmbt check 报 J1001（库 parser 拒）与 moonc 同向。后果：**「jsonmbt check 通过」≠「moonc 可编译」**——关键字域存在假绿缝，随两份代码各自演化动态变化。处置纪律：jsonmbt 已裁定 check 端自持硬关键字判定对齐 moonc（D-14③，施工后缝闭合）；其他消费 parser 库做校验器的项目同警戒——**库 parser 的「接受」不能当 moonc 的「接受」用，关键字域判决以 moonc 实跑为准**。

50. **`moon fmt --check` 是增量判定——未变更文件的存量欠账被「up to date」静默跳过 = 门禁假绿**（2026-10-23 jsonmbt 仓实测）：#34 批门禁记录「`moon fmt --check src` 零内容差异」为绿，但 2026-10-23 全仓 `moon fmt` 一跑，src/cmd/probe/samples 十余文件被归一（类型别名 `Int`→`Int32`/`UInt`→`UInt32`、**具名参数标记 `?`→`~`**、`if` 括号剥除、长行折行、尾空行删——约 200 行纯形态差）。机制：fmt 的 up-to-date 判定基于 `_build` 内的 fmt 缓存快照——文件自上次 fmt 后未动即跳过重排，`--check` 同路——**缓存里存的是「上次 fmt 时的形态」，不是「当前工具链会产出的形态」**；工具链升级（fmt 行为变）不会 invalidate 该缓存，只有文件本体变更（本批 stash→pop 循环改了 src）才连带暴露。与 #41（`_build` 缓存毒化「同源不同果」）同根：**跨工具链升级消费 `_build` fmt 缓存前先清缓存或强改一次文件面**；CI 里的 fmt 门禁在工具链升级后的首个批应跑一次无增量 `moon fmt`（或 `moon clean` 后 check）兜底。判别法：`--check` 输出「no work to do」≠「真幂等」——看到这句先怀疑缓存，用 `git status` 前后对比 `moon fmt` 是否真动文件来证。
