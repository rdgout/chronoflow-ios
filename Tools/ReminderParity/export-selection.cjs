const fs = require('node:fs');
const path = require('node:path');
const vm = require('node:vm');
const cp = require('node:child_process');
const root = process.argv[2] || '/Users/rickgout/Sites/chronoflow-mobile';
const ts = require(path.join(root, 'node_modules/typescript'));
const cases = [];
let test = '';
const identity = key => `${key.type}|${key.localDate}|${key.ordinal}`;
const fixtures = Object.fromEntries(['S1','S2','S3','S4','S5','S6'].map(key => [key, JSON.parse(fs.readFileSync(path.join(root, `src/data/mock/fixtures/plans/${key}.json`)))]));
function evaluate(file, imports, globals = {}) {
  const exports = {};
  vm.runInNewContext(ts.transpileModule(fs.readFileSync(file, 'utf8'), {compilerOptions:{module:ts.ModuleKind.CommonJS,target:ts.ScriptTarget.ES2022}}).outputText,
    {exports, require: key => { if (!(key in imports)) throw Error(key); return imports[key]; }, ...globals}, {filename:file});
  return exports;
}
const selection = evaluate(path.join(root,'src/reminders/selection.ts'), {'@/plan/check-state':{checkIdentity:identity}});
const original = selection.reminderDrafts;
selection.reminderDrafts = (...args) => {
  const expected = original(...args);
  cases.push(JSON.parse(JSON.stringify({test,blocks:args[0],settings:args[1],now:args[2],options:args[3]||{},expected})));
  return expected;
};
// Assertions remain in Swift: each fixture compares the complete RN output, including every member and date.
const expectation = new Proxy(function(){}, {get:()=>expectation,apply:()=>expectation});
function it(name, fn) {test=name;fn();}
it.each = rows => (name, fn) => rows.forEach(row => it(name + ' ' + JSON.stringify(row), () => fn(...(Array.isArray(row)?row:[row]))));
function describe(name, fn) {fn();}
describe.each = rows => (name, fn) => rows.forEach(row=>fn(...(Array.isArray(row)?row:[row])));
evaluate(path.join(root,'src/reminders/__tests__/selection.test.ts'), {
  '@/data/mock/fixtures/plans':{planFixtures:fixtures}, '@/plan/check-state':{checkIdentity:identity}, '@/reminders/selection':selection,
}, {it,describe,expect:expectation});
const result = {source: 'src/reminders/__tests__/selection.test.ts', commit:cp.execFileSync('git',['-C',root,'rev-parse','HEAD'],{encoding:'utf8'}).trim(), cases};
fs.writeFileSync('Packages/ChronoFlowKit/Tests/RemindersTests/Fixtures/selection.json',JSON.stringify(result,null,2)+'\n');
process.stdout.write(`${cases.length} RN selection vectors\n`);
