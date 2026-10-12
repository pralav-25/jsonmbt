# 在你的仓里接入 `.json.mbt`

> 本文是**面向下游仓**的接入指引。Vitro 的完整迁移实录（11 张 rules.json + 门禁证据）在
> `rustin-beep/Vitro` 的 `docs/current/07-质量与裁定/20261007_jsonmbt真相源迁移.md`。

## 为什么要多这一步（buying reason）

`.json.mbt` 的价值不在"更好读"，而在**MoonBit 编译器会替你看数据**：

| 缺陷 | `.json` | `.json.mbt` |
|---|---|---|
| 字段类型写错（`Int32` 字段填字符串） | 运行时才炸，或干脆不炸 | **编译期红** `[4014]` |
| 字段名拼错 | 静默忽略 | **编译期红** `[4044]` / `[4091]` |
| 字段缺失 | 静默用零值 | **编译期红** `[4044]` |
| 格式漂移 | 无感知 | `moon fmt` 归一 |

但这个价值**有前提**——文件不在 MoonBit 的包边界内，moon 就完全看不见它，等于白付成本。
本文就是那套前提的完整接法，全部结论都是实测出来的。

## 前提第 0 条（issue #4 实锤补充）：同目录多文件时 struct 名互不冲突

同一 moon 包内所有 `pub struct` 共享命名空间。importer 的嵌套 struct 名是
机器派生（取首样本字段名，`Id`/`Code` 这类零信息量名字高频），同目录多张
`.json.mbt` 时必然相撞（编译期 `[4051] declared twice`）。
**jsonmbt ≥ 本版已自动处理**：import 时扫描同目录已占名，后来者冲突名自动
加 stem 前缀（`Code` → `BCode`）——先到先得、单文件零变化。要语义名，
待 `--type-name-map`（#6-4）。子目录各自带 `moon.pkg` 则天然隔离，无此问题。

## 三个前提（缺一即失效）

### ① 所在目录必须带 `moon.pkg`

moon 只把**自带 `moon.pkg` 的目录**当包并编译其中的 `.json.mbt`。实测：只在仓根放一个
`moon.pkg` 时 `moon check` 报 `ran 1 task`（文件根本没被读）；给每个含 `.json.mbt` 的目录
各加一个，任务数才涨起来、才开始真正检查。

```bash
printf '\n' > data/moon.pkg      # 1 字节换行，即"空块"
```

⚠️ **只能空块**。实测 `{}` 与块式 `import (\n)` 两种写法**都报**
`Failed to calculate build plan`。

### ② `struct` 必须 `pub`

```moonbit
pub struct Config { port : Int32 }   # ✅
struct Config { port : Int }       # ❌ priv → 逐字段 unused_field 噪音 + moon info 不透明（Int 拼写此处无关——对照点是 pub/priv）
```

`moon info` 对 priv struct 只给不透明的 `type X`——而 `moon info` 产出的接口面正是
`.json.mbt` 白嫖来的 schema 出口（见下文「`.mbti` 入仓」）。

### ③ 经 `moon fmt` 归一

> **#18 后本节降级为历史说明**：import 产物**已是 fmt 不动点**（生成器宽度驱动渲染对齐
> fmt 规范形——`///|` 补齐、尾逗号规范形、填满式数组，层 2 金门常驻断言「产物过 fmt 零
> diff」）。新接入的仓**无需此步**；对旧产物（#18 前生成）跑一次 fmt 归一即可对齐。

`moon fmt` 会做两件事：给顶层 `struct` / `let` 补 `///|` 文档标记；**按行宽决定 record
折行**（短的折成单行、长的保持多行），大 Map 会逐项展开。

实测副作用是好的：**归一前后 `build` 产物不变**（7 张字节相等 + 4 张仅缩进风格差、值相等），
即 fmt 只改形态不改语义。

## 最小接入（单模块仓）

```bash
# 1. 转换（产物与源同目录同名 .json.mbt）
jsonmbt import data/config.json          # → data/config.json.mbt

# 2. 声明包边界
printf '\n' > data/moon.pkg

# 3. 归一 + 检查
moon fmt data
moon check
```

之后 `.json.mbt` 就是唯一真相源，`.json` 由 `jsonmbt build --pretty` 再生给下游消费者
（`build` 默认输出紧凑 JSON；**若下游按字节锚定对账，必须加 `--pretty`**，它对齐 Go
`json.Encoder.SetIndent` 的形态——数组恒逐元素展开，含单元素）。

> **字节口径（#30 钉死）**：`--pretty` 的语义锚是 **Go `json.Encoder` 那一族**，不是
> prettier。BYTE-EQ 只承诺「源是机器生成且格式策略一致（紧凑 / Go indent=2 族）」的
> 文件；人写 / prettier 风格源承诺**值层面等价**（`migrate` 报告的 LAYOUT-EQ /
> VALUE-EQ 档）。结构上「逐字节还原人写源」**不可达**：`.json.mbt` 是类型化重写而非
> 保格式载体——源的布局信息 import 时已丢，降级产物是重新序列化生成的；往类型头塞
> 布局元数据违背「类型即 Schema」的核心价值。prettier 口径若成真需求，走显式
> `--profile` 独立档（默认产物一字不动）。

## 多模块仓：`moon.work`

若仓里有多个 moon 项目（`moon.mod` 各在各的目录），在**仓根**加 `moon.work`，一条命令
覆盖全部：

```bash
moon work init
moon work use path/to/module-a
moon work use path/to/module-b
# 生成：members = ["./path/to/module-a", "./path/to/module-b"]
```

```bash
moon check          # 覆盖全部成员
moon fmt <member>   # ⚠️ 限定成员，见下方坑表
```

`members: [...]` / `include "..."` 两种手写语法**都报解析错**，必须用 `moon work` 命令生成。

## CI 接线（GitHub Actions）

```yaml
      - uses: hustcer/setup-moonbit@v1
        with:
          version: latest

      # ① 静态门禁：真相源坏了这里就红（类型错/字段错在编译期拦下）
      - name: .json.mbt static gate
        shell: bash
        run: moon check

      # ② 再生 .json 供下游消费（消费方零改动）
      - name: Regenerate .json
        shell: bash
        run: |
          set -e
          for m in $(find . -name '*.json.mbt' -not -path './_build/*'); do
            jsonmbt build --pretty "$m"
          done
```

`moon check` 应放在再生**之前**：真相源非法时 `build` 也会红（`J1001`/`J2003`/`J3004`），
但先拦在编译期更快、诊断更准。

### `.mbti` 入仓还是 gitignore？

两种做法都见过，**跟随你仓里既有的约定**：

- 若仓里已有 `pkg.generated.mbti` 入仓（Vitro 的 `moonbit/` 下有 25 个）→ scripts 侧也入仓。
  它是 `moon info` 生成的接口面，含 `.json.mbt` 的 struct 类型，**白嫖的 schema 出口**，
  也是"哪些 `.json.mbt` 在编译面内"的可读清单。实测内容稳定（重生成 md5 不变）。
- 否则 gitignore 掉，别让副产物污染提交。

## 验证你的接入真的生效（注入测试法）

光跑绿说明不了问题——**必须注入错误证明它会红**。两个要点：

1. **哨兵先自证**：注入后先打印文件内容确认改动落地，再看 rc。
2. **必须跨类型注入**：把 `String` 字段声明改成 `Int32`（或反之）。**同类型改数值不会红，
   而且这是正确的**——moon 抓类型/字段，不抓业务语义。业务语义（如"分层号写错了"）
   得由下游自己的门禁抓，两者互补。

```bash
cp data/config.json.mbt /tmp/bak
sed -i 's/^  schema : Int$/  schema : String/' data/config.json.mbt
grep -n 'schema : ' data/config.json.mbt    # ← 自证：确认改动落地
moon check                                   # ← 期望非 0，诊断含 [4014]
cp /tmp/bak data/config.json.mbt
```

判据：`rc ≠ 0` 且诊断码与预期一致。`moon check` 在 Windows 上错误退出码是 `127`。

## 机器生成 .json.mbt（emitter 作者契约，#19）

程序直产 `.json.mbt` 文本（不走 import）是机器写回域的正道，但有一条
**确定性契约**必须遵守：

> **Map 键序契约**：`build` 的 Map 输出键序 = `.json.mbt` 字面量的
> **源文本序**（不排序、非字典序——D-11 ④）。

- **禁止**依赖运行时 map 遍历序——Go 的 `for k := range m` / Py 的
  dict 迭代在部分场景序不稳定（Go map range 序随机），用它直接渲染
  `.mbt` → 同一数据两次生成产物不同 → 确定性破功（Vitro 侧 jmemit
  靠 round-trip 对拍兜住才发现此坑）；
- **正解**：以任意确定性序渲染（原文序 / 排序序 / 自定义稳定序皆可
  ——build 忠实保留你写的序，不强制形态）；
- struct 字段（record）同理：字段序 = 你写的序。

## 坑表（全部实测，勿再踩）

| 坑 | 表现 | 正解 |
|---|---|---|
| 文件不在带 `moon.pkg` 的目录 | `moon check` 报 `ran 1 task` / "no work to do"，文件根本没被读 | 逐目录加 `moon.pkg` |
| `moon.pkg` 写成 `{}` 或 `import ()` | `Failed to calculate build plan` | 空块（1 字节换行） |
| `moon build` 当门禁 | 注入类型错仍 rc=0 | 用 `moon check`（或 `moon test`） |
| `moon check`（全量）当门禁 | 跳过孤立包 | 仓根 `moon.work` + `moon check` |
| workspace 根跑无参数 `moon fmt` | **重排无关模块的源文件**（实测改了 `moonbit/codegen/addr.mbt` 13 行） | `moon fmt <member>` 限定成员 |
| YAML step name 含 `: ` | 整个 yml 解析失败（`mapping values are not allowed here`） | 给含冒号的值加引号 |
| 注入用同类型改数值 | 不红，且**这是正确的** | 跨类型注入；业务语义交给下游门禁 |
| 只在文件尾追加 `pub let` 验证 | 不红——**两个 `pub let` 在 MoonBit 语法上合法**（moon 不知单文档基数） | 注入到字段声明/值上 |
| `moon test` 门禁没跑 | 缺 registry 索引时依赖解析阶段就红 | CI 先 `moon update` |

## moon 的行为基线（2026-09 工具链实测）

| 命令 | 隔离立的包（含 `.json.mbt`） |
|---|---|
| `moon build` | ❌ 注入类型错仍 rc=0 |
| `moon test` | ✅ rc≠0（但只编译到测试目标，空跑无测试的包时价值有限） |
| `moon check`（全量） | ❌ 跳过孤立包 |
| `moon check`（`moon.work` 根级） | ✅ 覆盖全部成员 |
| `moon check <成员名当路径>` | ❌ "no work to do"——成员名不被当作路径 |

> 判定 moon 是否真检查了某个文件，**不能信 task 数或 "no work to do"**。用
> `moon check --dry-run | grep 'workspace-path'` 看真实编译单元，再用注入测试看 rc。
