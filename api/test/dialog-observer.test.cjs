const { test } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const vm = require('node:vm');
const path = require('node:path');

test('dialog observer skips ordinary updates and preserves modal focus', () => {
  const source = fs.readFileSync(path.join(__dirname, '../web/public/bootstrap.js'), 'utf8');
  const start = source.indexOf('// Keep keyboard focus inside open dialogs');
  const end = source.indexOf('// Warn on reload/close', start);
  let observe, scans = 0, dialogs = [], focused = null;
  const trigger = { isConnected: true, focus() { focused = this; } };
  const document = {
    body: {}, activeElement: trigger, addEventListener() {},
    querySelectorAll() { scans++; return dialogs; }
  };
  vm.runInNewContext(source.slice(start, end), {
    document,
    MutationObserver: class {
      constructor(callback) { observe = callback; }
      observe() {}
    }
  });
  const text = { nodeType: 3 };
  const row = { nodeType: 1, matches: () => false, querySelector: () => null };
  for (let i = 0; i < 100; i++) observe([{ addedNodes: [text, row], removedNodes: [] }]);
  assert.equal(scans, 0);
  const control = { focus() { focused = this; } };
  const dialog = { nodeType: 1, matches: () => true, querySelector: () => control };
  dialogs = [dialog];
  observe([{ addedNodes: [dialog], removedNodes: [] }]);
  assert.equal(scans, 1);
  assert.equal(focused, control);
  assert.equal(dialog.inert, false);
  dialogs = [];
  observe([{ addedNodes: [], removedNodes: [dialog] }]);
  assert.equal(scans, 2);
  assert.equal(focused, trigger);
});
