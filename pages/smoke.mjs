// pages 样例矩阵全量冒烟——与 index.html 样例矩阵同步：绿区应 ok、红区应报
// 对应 J 码、build 侧断言降级产物特征。**部署门**（pages.yml 调用）：断言
// 红必须 exit 1——红不上线（审阅 P1 处置：曾只有 console.log，rc 恒 0，
// CI 门不挡红）
import { js_import, js_build } from './ffi.js';

const EAT = [
  '{"id": 1, "name": "demo", "cfg": {"debug": true, "ratio": 0.5}}',
  '{"tags": ["api", "web"], "matrix": [[1, 2], [3, 4]]}',
  '{"users": [{"nickname": null, "id": 1}, {"nickname": "x", "id": 2}]}',
  '{\n  // 用户配置\n  "port": 8080,\n  "hosts": ["a", "b"]\n}',
  '{"Content-Type": "application/json", "x_custom": "v"}',
  '{"actions": [{"Void": true}, {"Copy": true}]}',
  '{"id": 9007199254740993}',
  '{"pi": 3.14159, "neg": -0.5, "exp": 1e10}',
  '{"list": [], "nested": {"list": [1, 2]}}',
  '{"emoji": "🚀 中文"}',
  '{"rules": [{"where": ".btn", "targets": ["btn-primary"]}]}',
  '{"exemptions": [], "meta": {}}',
];
const REJECT = [
  ['{"rows": [1, "a"]}', 'J4010'],
  ['{"id": 1, "u": null}', 'J4003'],
  ['{"big": 123456789012345678901234567890}', 'J4020'],
  ['{"k": 1, "k": 2}', 'J1003'],
  // 空对象/孤立空数组（原 J4002/J4001）已默认 Never 占位（#14-2a，
  // 绿区卡展示）——REJECT 面换真拒形态：
  ['{"a": }', 'J1002'],
  ['{"id": 1, "x": null, "y": null}', 'J4003'],
  ['{"Content-Type": "text/html", "Content-Length": 123}', 'J4011'],
];
const BUILD = [
  ['enum tag 展开', 'struct Pt {\n  x : Int\n  y : Int\n}\nenum Shape {\n  Dot(Pt)\n  Unit\n}\npub let shapes : Array[Shape] = [Dot(Pt::{ x: 1, y: 2 }), Unit]', r => r.ok && r.json.includes('"case":"Dot"') && r.json.includes('"Unit"')],
  ['Option（index 卡逐字同步）', 'struct S {\n  nick : String?\n}\npub let s : S = S::{ nick: Some("x") }', r => r.ok && r.json === '{"nick":"x"}'],
  ['Option None→null（语义专断）', 'struct S {\n  nick : String?\n}\npub let s : S = S::{ nick: None }', r => r.ok && r.json === '{"nick":null}'],
  ['多行字符串', 'pub let doc : String = #|\n#| 第一行\n#| 第二行', r => r.ok && r.json.includes('第一行')],
  ['嵌套 enum payload（index 卡逐字同步）', 'enum Col {\n  X\n}\nenum Field {\n  Named(Col)\n}\npub let f : Field = Named(X)', r => r.ok && r.json === '{"case":"Named","value":"X"}'],
  ['注释尾逗号丢弃', 'pub let s = {\n  "a": 1, // 会消失\n}', r => r.ok && r.json === '{"a":1}'],
];

let bad = 0;
for (const s of EAT) {
  const r = JSON.parse(js_import(s, 'demo'));
  if (!r.ok) { bad++; console.log('EAT 应绿却红:', r.error.split('\n')[0]); }
}
for (const [s, jcode] of REJECT) {
  const r = JSON.parse(js_import(s, 'demo'));
  if (r.ok || !r.error.includes(jcode)) { bad++; console.log('REJECT 应含', jcode, 'got:', r.ok ? 'ok!' : r.error.split('\n')[0]); }
}
for (const [name, s, ok] of BUILD) {
  const r = JSON.parse(js_build(s));
  if (!ok(r)) { bad++; console.log('BUILD', name, 'FAIL:', JSON.stringify(r).slice(0, 160)); }
}
// repr 保真专断（两段式：import content → build json）
const i64 = JSON.parse(js_build(JSON.parse(js_import('{"id": 9007199254740993}', 'demo')).content));
if (!(i64.ok && i64.json === '{"id":9007199254740993}')) { bad++; console.log('Int64 repr FAIL:', JSON.stringify(i64).slice(0, 120)); }
// 保留字往返专断（#13：EAT[10] 的语义断言——改名+注记+键还原）
const rk = JSON.parse(js_import(EAT[10], 'demo'));
const rkOk = rk.ok && rk.content.includes('// jsonmbt: field-alias Where.where_ = "where"') && rk.content.includes('where_ : String');
if (!rkOk) { bad++; console.log('reserved-key import FAIL:', JSON.stringify(rk).slice(0, 160)); }
else {
  const rkBuilt = JSON.parse(js_build(rk.content));
  if (!(rkBuilt.ok && rkBuilt.json === '{"rules":[{"where":".btn","targets":["btn-primary"]}]}')) { bad++; console.log('reserved-key roundtrip FAIL:', JSON.stringify(rkBuilt).slice(0, 160)); }
}
// 空容器底型占位专断（#14-2a + #36：EAT[11]——空容器不再整张拒；
// 底型名逐文件唯一 <Stem>Never，此处 stem="demo" → DemoNever）
const nv = JSON.parse(js_import(EAT[11], 'demo'));
const nvOk = nv.ok && nv.content.includes('pub enum DemoNever {}') && nv.content.includes('Array[DemoNever]') && nv.content.includes('Map[String, DemoNever]');
if (!nvOk) { bad++; console.log('never-placeholder FAIL:', JSON.stringify(nv).slice(0, 160)); }
else {
  const nvBuilt = JSON.parse(js_build(nv.content));
  if (!(nvBuilt.ok && nvBuilt.json === '{"exemptions":[],"meta":{}}')) { bad++; console.log('never roundtrip FAIL:', JSON.stringify(nvBuilt).slice(0, 160)); }
}
// 转义宽集往返专断（#16：\uXXXX/代理对 → 规范形裸 UTF-8）
{
  const B = String.fromCharCode(92);
  const es = JSON.parse(js_import('{"s": "a' + B + 'tb' + B + 'u4e2d' + B + 'ud83d' + B + 'ude80"}', 'demo'));
  const esOk = es.ok && es.content.includes(B + 't') && es.content.includes('中');
  if (!esOk) { bad++; console.log('escape import FAIL:', JSON.stringify(es).slice(0, 160)); }
  else {
    const esBuilt = JSON.parse(js_build(es.content));
    if (!(esBuilt.ok && esBuilt.json === '{"s":"a' + B + 'tb' + String.fromCharCode(0x4e2d, 0xd83d, 0xde80) + '"}')) { bad++; console.log('escape roundtrip FAIL:', JSON.stringify(esBuilt).slice(0, 160)); }
  }
}
// 数字契约专断（#17：整数归一 / Double 透传——index 卡逐字同步）
{
  const nc = JSON.parse(js_build('struct N {\n  a : Int\n  b : Double\n  c : Int\n}\npub let n : N = N::{\n  a: -0,\n  b: 1.50,\n  c: 0x10,\n}'));
  if (!(nc.ok && nc.json === '{"a":0,"b":1.50,"c":16}')) { bad++; console.log('number-contract FAIL:', JSON.stringify(nc).slice(0, 160)); }
}
console.log(bad === 0 ? 'SMOKE ALL OK (eat 12 + reject 7 + build 7 + i64 1 + rk/nv/es/nc 4)' : 'SMOKE BAD=' + bad);
if (bad) process.exit(1); // 部署门契约：断言红 = rc 1（pages.yml 据此阻断 deploy）
