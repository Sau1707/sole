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
  for (const kind of ['struct']) {
    check(`${kind} Point:`, [
      [kind, 'storage.type.sole'],
      [kind, 'storage.type.class.python'],
      ['Point', 'entity.name.type.sole'],
      ['Point', 'entity.name.type.class.python'],
    ]);
  }
  check('def café() -> void:', [['café', 'entity.name.function.sole']]);
});

test('built-in C namespace distinguishes calls from strings and comments', () => {
  check('data = ¢.malloc(64)', [
    ['¢', 'variable.language.c-api.sole'],
    ['.', 'punctuation.accessor.sole'],
    ['malloc', 'support.function.builtin.sole'],
  ]);
  check('¢ . free(data)', [['free', 'support.function.builtin.sole']]);
  check('"¢.malloc"', [['¢.malloc', 'string.quoted.double.sole']]);
  check('# ¢.malloc', [['¢.malloc', 'comment.line.number-sign.sole']]);
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

test('named imports distinguish paths, names, aliases, and punctuation', () => {
  check('from math.vector import Vector as Renamed, dot # comment', [
    ['from', 'keyword.control.import.sole'],
    ['import', 'keyword.control.import.python'],
    ['as', 'keyword.control.import.sole'],
    ['math', 'variable.other.property.sole'],
    ['vector', 'variable.other.property.sole'],
    ['Vector', 'variable.other.property.sole'],
    ['Renamed', 'variable.other.property.sole'],
    ['dot', 'variable.other.property.sole'],
    ['.', 'punctuation.separator.period.python'],
    [',', 'punctuation.separator.sole'],
    ['# comment', 'comment.line.number-sign.sole'],
  ]);
  check('fromage = 1', [['fromage', 'variable.other.readwrite.sole']]);
  check('"from core import len"', [['from core import len', 'string.quoted.double.sole']]);
});

test('control flow, booleans, calls, and operators', () => {
  check('if true && not false:', [
    ['if', 'keyword.control.sole'],
    ['true', 'constant.language.boolean.sole'],
    ['&&', 'keyword.operator.logical.sole'],
    ['not', 'keyword.operator.logical.sole'],
    ['false', 'constant.language.boolean.sole'],
  ]);
  check('print(read(value) + len(values))', [
    ['print', 'support.function.builtin.sole'],
    ['value', 'variable.other.readwrite.sole'],
    ['read', 'entity.name.function.sole'],
    ['+', 'keyword.operator.sole'],
    ['len', 'support.function.builtin.sole'],
  ]);
});

test('named struct constructors', () => {
  check('pair = Pair(second=2, first=1)', [
    ['Pair', 'entity.name.function.sole'],
    ['second', 'variable.other.readwrite.sole'],
    ['first', 'variable.other.readwrite.sole'],
    ['=', 'keyword.operator.assignment.python'],
    ['2', 'constant.numeric.sole'],
    ['1', 'constant.numeric.sole'],
  ]);
});

test('removed features are not highlighted as supported keywords', () => {
  for (const word of ['class', 'enum', 'union', 'match', 'case', 'self', 'lambda']) {
    check(word, [[word, 'variable.other.readwrite.sole']]);
  }
});

test('range loops', () => {
  for (const args of ['stop', 'start, stop']) {
    check(`for i in range(${args}):`, [
      ['for', 'keyword.control.sole'],
      ['i', 'variable.other.readwrite.sole'],
      ['in', 'keyword.control.sole'],
      ['range', 'support.function.builtin.sole'],
      ['range', 'support.function.builtin.python'],
      ['stop', 'variable.other.readwrite.sole'],
    ]);
  }
  check('iterator.range(stop)', [['range', 'entity.name.function.sole']]);
  for (const word of ['enum_value', 'unionized', 'matches', 'cases', 'format', 'inside', 'range_limit']) {
    check(word, [[word, 'variable.other.readwrite.sole']]);
  }
  check('"enum union match case for in +="', [['enum union match case for in +=', 'string.quoted.double.sole']]);
  check('# enum union match case for in +=', [['enum union match case for in +=', 'comment.line.number-sign.sole']]);
});

test('plus assignment is one assignment token rather than arithmetic plus', () => {
  for (const line of ['total += 1', 'total+=1']) {
    check(line, [['+=', 'keyword.operator.assignment.python']]);
    const start = line.indexOf('+=');
    const { tokens } = grammar.tokenizeLine(line);
    const matching = tokens.filter(token => token.startIndex < start + 2 && token.endIndex > start);
    assert.equal(matching.length, 1);
    assert.equal(matching[0].startIndex, start);
    assert.equal(matching[0].endIndex, start + 2);
    assert.ok(!matching[0].scopes.includes('keyword.operator.arithmetic.python'));
  }
  check('total = left + right', [
    ['=', 'keyword.operator.assignment.python'],
    ['+', 'keyword.operator.arithmetic.python'],
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
  check('item.value = counter.value + numbers[index]', [
    ['item', 'variable.other.readwrite.sole'],
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
  check('def add(amount: int32) -> int32:', [
    ['def', 'storage.type.function.python'],
    ['add', 'entity.name.function.python'],
    ['amount', 'variable.parameter.function.language.python'],
    ['int32', 'support.type.python'],
  ]);
  check('struct Counter:', [['struct', 'storage.type.class.python'], ['Counter', 'entity.name.type.class.python']]);
  check('if true && not false:', [
    ['if', 'keyword.control.flow.python'],
    ['true', 'constant.language.python'],
    ['&&', 'keyword.operator.logical.python'],
  ]);
  check('print(read(value) + 42) # comment', [
    ['print', 'support.function.builtin.python'],
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

test('byte literals include their prefix and protect comment characters', () => {
  for (const quote of ["'", '"']) {
    const scope = `string.quoted.${quote === "'" ? 'single' : 'double'}.byte.sole`;
    for (const value of ['X', '#', '', 'many']) {
      const literal = `b${quote}${value}${quote}`;
      check(`value = ${literal} # comment`, [
        [literal, scope],
        [literal, 'string.quoted.single.python'],
        ['# comment', 'comment.line.number-sign.sole'],
      ]);
    }
  }
});

test('byte literals highlight only supported escapes and close after escaped quotes', () => {
  for (const quote of ["'", '"']) {
    const scope = `string.quoted.${quote === "'" ? 'single' : 'double'}.byte.sole`;
    for (const escape of [String.raw`\n`, String.raw`\r`, String.raw`\t`, String.raw`\0`,
      String.raw`\\`, String.raw`\'`, String.raw`\"`]) {
      const literal = `b${quote}${escape}${quote}`;
      check(`value = ${literal} + next`, [
        [literal, scope],
        [escape, 'constant.character.escape.sole'],
        [escape, 'constant.character.escape.python'],
        ['+', 'keyword.operator.sole'],
        ['next', 'variable.other.readwrite.sole'],
      ]);
    }
    for (const escape of [String.raw`\x41`, String.raw`\u0041`, String.raw`\1`, String.raw`\q`]) {
      const { tokens } = grammar.tokenizeLine(`b${quote}${escape}${quote}`);
      assert.ok(tokens.every(token => !token.scopes.includes('constant.character.escape.sole')));
    }
  }
});

test('byte prefixes are lowercase, separate from identifiers, and never triple quoted', () => {
  for (const quote of ["'", '"']) {
    for (const prefix of ['B', 'nameb', '_b', 'éb', '1b', 'rb']) {
      const { tokens } = grammar.tokenizeLine(`${prefix}${quote}X${quote}`);
      assert.ok(tokens.every(token => !token.scopes.some(scope => scope.includes('.byte.sole'))));
    }
    const triple = quote.repeat(3);
    check(`b${triple}X${triple}`, [
      ['b', 'variable.other.readwrite.sole'],
      ['X', `string.quoted.triple.${quote === "'" ? 'single' : 'double'}.sole`],
    ]);
    check(`${quote}b${quote}`, [['b', `string.quoted.${quote === "'" ? 'single' : 'double'}.sole`]]);
    check(`# b${quote}X${quote}`, [['b', 'comment.line.number-sign.sole']]);
  }
});

test('unterminated byte literals do not carry highlighting into the next line', () => {
  for (const quote of ["'", '"']) {
    for (const content of ['X', '\\']) {
      const { ruleStack } = grammar.tokenizeLine(`value = b${quote}${content}`);
      const next = grammar.tokenizeLine('return 0', ruleStack);
      assert.ok(next.tokens[0].scopes.includes('keyword.control.sole'));
      assert.equal(ruleStack.depth, 1);
    }
  }
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
  for (const line of ['def main() -> int32:', '    if true: # comment', 'else:', 'class Point:', 'while true:',
    'enum Kind:', 'union Item: # variants', 'match item:', '    case Item.Number(value):',
    '    case Kind.Number:', 'for i in range(stop):', 'for i in range(start, stop):']) {
    assert.ok(indent.test(line), line);
  }
  for (const line of ['value: int32 = 0', '# if true:', 'print("hello:")', 'extern def read() -> int32',
    '    Number(value: int64)', '    Empty()', 'Pair(second=2, first=1)', 'total += 1',
    '# match item:', '"case Kind.Number:"', 'format:', 'matches:']) {
    assert.ok(!indent.test(line), line);
  }
});
