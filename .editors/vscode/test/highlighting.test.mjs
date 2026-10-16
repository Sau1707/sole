import assert from 'node:assert/strict';
import { readFile, readdir } from 'node:fs/promises';
import { createRequire } from 'node:module';
import test from 'node:test';
import textmate from 'vscode-textmate';
import oniguruma from 'vscode-oniguruma';

const require = createRequire(import.meta.url);
await oniguruma.loadWASM(await readFile(require.resolve('vscode-oniguruma/release/onig.wasm')));
const grammarPath = new URL('../syntaxes/sole.tmLanguage.json', import.meta.url);
const registry = new textmate.Registry({
  onigLib: Promise.resolve({
    createOnigScanner: patterns => new oniguruma.OnigScanner(patterns),
    createOnigString: value => new oniguruma.OnigString(value),
  }),
  loadGrammar: async () => textmate.parseRawGrammar(await readFile(grammarPath, 'utf8'), grammarPath.pathname),
});
const grammar = await registry.loadGrammar('source.sole');

function check(line, expected) {
  const { tokens } = grammar.tokenizeLine(line);
  for (const [text, scope] of expected) {
    const start = line.indexOf(text);
    assert.notEqual(start, -1, `Missing fixture text: ${text}`);
    const matching = tokens.filter(token => token.startIndex < start + text.length && token.endIndex > start);
    assert.ok(matching.length > 0 && matching.every(token => token.scopes.includes(scope)),
      `${text}: expected ${scope}, got ${matching.map(token => token.scopes).join('; ')}`);
  }
}

test('declarations, annotations, arrays, and extern functions', () => {
  check('extern def read(values: Point[4]) -> int32', [
    ['extern', 'storage.modifier.sole'],
    ['def', 'storage.type.function.sole'],
    ['read', 'entity.name.function.sole'],
    ['Point', 'entity.name.type.sole'],
    ['4', 'constant.numeric.sole'],
    ['int32', 'storage.type.sole'],
  ]);
  for (const kind of ['class', 'struct']) {
    check(`${kind} Point:`, [['Point', 'entity.name.type.sole']]);
  }
  check('def café() -> void:', [['café', 'entity.name.function.sole']]);
});

test('imports distinguish keywords and module names', () => {
  for (const module of ['core', 'math', 'strings', 'ascii', 'café', '_helpers']) {
    const line = `import ${module} # comment`;
    check(line, [
      ['import', 'keyword.control.import.sole'],
      ['import', 'keyword.control.import.python'],
      ['# comment', 'comment.line.number-sign.sole'],
    ]);
    const start = line.indexOf(module);
    const { tokens } = grammar.tokenizeLine(line);
    const matching = tokens.filter(token => token.startIndex < start + module.length && token.endIndex > start);
    assert.ok(matching.length > 0);
    for (const token of matching) assert.deepEqual(token.scopes, ['source.sole', 'variable.other.property.sole']);
  }
  check('import', [['import', 'keyword.control.import.sole']]);
  check('import # comment', [['# comment', 'comment.line.number-sign.sole']]);
  check('important = imports', [
    ['important', 'variable.other.readwrite.sole'],
    ['imports', 'variable.other.readwrite.sole'],
  ]);
  check('"import math"', [['import math', 'string.quoted.double.sole']]);
  check('# import math', [['import math', 'comment.line.number-sign.sole']]);
  const { ruleStack } = grammar.tokenizeLine('import math');
  const next = grammar.tokenizeLine('value = math.pi', ruleStack);
  assert.ok(next.tokens[0].scopes.includes('variable.other.readwrite.sole'));
});

test('import aliases use import keyword coloring', () => {
  check('import frontend.lexer as lexer', [
    ['import', 'keyword.control.import.sole'],
    ['import', 'keyword.control.import.python'],
    ['as', 'keyword.control.import.sole'],
    ['as', 'keyword.control.import.python'],
    ['frontend', 'variable.other.property.sole'],
    ['lexer', 'variable.other.property.sole'],
  ]);
  check('import assets as assets_alias', [
    ['assets', 'variable.other.property.sole'],
    ['assets_alias', 'variable.other.property.sole'],
  ]);
});

test('all dotted import components use the same property coloring', () => {
  for (const module of ['backend.ir', 'backend.literals', 'backend.types',
    'frontend.diagnostics', 'frontend.model', 'frontend.types', 'os.path',
    'package.subpackage.module']) {
    const line = `import ${module} # comment`;
    check(line, [
      ['import', 'keyword.control.import.python'],
      ['.', 'punctuation.separator.period.python'],
      ['# comment', 'comment.line.number-sign.sole'],
    ]);
    const { tokens, ruleStack } = grammar.tokenizeLine(line);
    let start = 'import '.length;
    for (const part of module.split('.')) {
      const matching = tokens.filter(token => token.startIndex < start + part.length && token.endIndex > start);
      assert.ok(matching.length > 0);
      for (const token of matching) assert.deepEqual(token.scopes, ['source.sole', 'variable.other.property.sole']);
      start += part.length + 1;
    }
    const next = grammar.tokenizeLine('backend.value', ruleStack);
    assert.ok(next.tokens[0].scopes.includes('variable.other.readwrite.sole'));
    assert.ok(next.tokens.some(token => token.scopes.includes('variable.other.property.sole')));
  }
});

test('control flow, booleans, self, calls, and operators', () => {
  check('if true && not false:', [
    ['if', 'keyword.control.sole'],
    ['true', 'constant.language.boolean.sole'],
    ['&&', 'keyword.operator.logical.sole'],
    ['not', 'keyword.operator.logical.sole'],
    ['false', 'constant.language.boolean.sole'],
  ]);
  check('print(self.read() + len(values))', [
    ['print', 'support.function.builtin.sole'],
    ['self', 'variable.language.self.sole'],
    ['read', 'entity.name.function.sole'],
    ['+', 'keyword.operator.sole'],
    ['len', 'support.function.builtin.sole'],
  ]);
});

test('variable declarations, parameters, references, and fields', () => {
  check('total: int32 = amount', [
    ['total', 'variable.other.readwrite.sole'],
    ['int32', 'storage.type.sole'],
    ['amount', 'variable.other.readwrite.sole'],
  ]);
  check('def add(amount: int32) -> int32:', [
    ['add', 'entity.name.function.sole'],
    ['amount', 'variable.other.readwrite.sole'],
  ]);
  check('self.value = counter.value + numbers[index]', [
    ['self', 'variable.language.self.sole'],
    ['value', 'variable.other.property.sole'],
    ['counter', 'variable.other.readwrite.sole'],
    ['numbers', 'variable.other.readwrite.sole'],
    ['index', 'variable.other.readwrite.sole'],
  ]);
  check('counter.read()', [
    ['counter', 'variable.other.readwrite.sole'],
    ['read', 'entity.name.function.sole'],
  ]);
  check('résultat = café', [
    ['résultat', 'variable.other.readwrite.sole'],
    ['café', 'variable.other.readwrite.sole'],
  ]);
});

test('symbolic logical operators stay distinct from bitwise operators', () => {
  check('true&&false||not false', [
    ['&&', 'keyword.operator.logical.sole'],
    ['||', 'keyword.operator.logical.sole'],
    ['not', 'keyword.operator.logical.sole'],
  ]);
  check('a & b | c', [
    ['&', 'keyword.operator.bitwise.python'],
    ['|', 'keyword.operator.bitwise.python'],
  ]);
  check('and && or', [
    ['and', 'variable.other.readwrite.sole'],
    ['or', 'variable.other.readwrite.sole'],
  ]);
  check('"and or && ||"', [['and or && ||', 'string.quoted.double.sole']]);
});

test('Python-compatible scopes for shared syntax', () => {
  check('def add(self, amount: int32) -> int32:', [
    ['def', 'storage.type.function.python'],
    ['add', 'entity.name.function.python'],
    ['self', 'variable.parameter.function.language.special.self.python'],
    ['amount', 'variable.parameter.function.language.python'],
    ['int32', 'support.type.python'],
  ]);
  check('class Counter:', [['class', 'storage.type.class.python'], ['Counter', 'entity.name.type.class.python']]);
  check('if true && not false:', [
    ['if', 'keyword.control.flow.python'],
    ['true', 'constant.language.python'],
    ['&&', 'keyword.operator.logical.python'],
  ]);
  check('print(self.read() + 42) # comment', [
    ['print', 'support.function.builtin.python'],
    ['self', 'variable.language.special.self.python'],
    ['read', 'meta.function-call.generic.python'],
    ['+', 'keyword.operator.arithmetic.python'],
    ['42', 'constant.numeric.python'],
    ['# comment', 'comment.line.number-sign.python'],
  ]);
  for (const [operator, scope] of [
    ['=', 'assignment'], ['==', 'comparison'], ['<=', 'comparison'],
    ['<<', 'bitwise'], ['>>', 'bitwise'], ['&', 'bitwise'], ['*', 'arithmetic'],
  ]) {
    check(`left ${operator} right`, [[operator, `keyword.operator.${scope}.python`]]);
  }
  check(String.raw`text = "hello\n"`, [
    ['hello', 'string.quoted.single.python'],
    [String.raw`\n`, 'constant.character.escape.python'],
  ]);
});

test('numeric formats', () => {
  for (const value of ['0', '42', '1_000', '0xff', '0XFF', '0b101', '0o77', '3.14', '.5', '1.', '1e-3', '1_000.5e+2']) {
    check(`value = ${value}`, [[value, 'constant.numeric.sole']]);
  }
});

test('strings protect comments and keywords, and highlight escapes', () => {
  check('print("# if true") # return', [
    ['# if true', 'string.quoted.double.sole'],
    ['# return', 'comment.line.number-sign.sole'],
  ]);
  check(String.raw`text: str = 'hello\n'`, [[String.raw`\n`, 'constant.character.escape.sole']]);
  check('text: str = r"hello"', [['hello', 'string.quoted.double.sole']]);
  let { ruleStack } = grammar.tokenizeLine('text: str = """first');
  const middle = grammar.tokenizeLine('# still a string', ruleStack);
  assert.ok(middle.tokens[0].scopes.includes('string.quoted.triple.double.sole'));
  ({ ruleStack } = grammar.tokenizeLine('last"""', middle.ruleStack));
  const after = grammar.tokenizeLine('return 0', ruleStack);
  assert.ok(after.tokens[0].scopes.includes('keyword.control.sole'));
});

test('compiler sources tokenize without leaving open strings', async () => {
  const directory = new URL('../../../compiler/', import.meta.url);
  for (const file of await readdir(directory, { recursive: true })) {
    if (!file.endsWith('.sole') || file.startsWith('tests/')) continue;
    let stack = textmate.INITIAL;
    for (const line of (await readFile(new URL(file, directory), 'utf8')).split(/\r?\n/)) {
      stack = grammar.tokenizeLine(line, stack).ruleStack;
    }
    assert.equal(stack.depth, 1, file);
  }
});

test('language registration and indentation rules', async () => {
  const manifest = JSON.parse(await readFile(new URL('../package.json', import.meta.url), 'utf8'));
  const config = JSON.parse(await readFile(new URL('../language-configuration.json', import.meta.url), 'utf8'));
  assert.deepEqual(manifest.contributes.languages[0].extensions, ['.sole']);
  assert.equal(config.comments.lineComment, '#');
  const indent = new RegExp(config.indentationRules.increaseIndentPattern);
  for (const line of ['def main() -> int32:', '    if true: # comment', 'else:', 'class Point:', 'while true:']) {
    assert.ok(indent.test(line), line);
  }
  for (const line of ['value: int32 = 0', '# if true:', 'print("hello:")', 'extern def read() -> int32']) {
    assert.ok(!indent.test(line), line);
  }
});
