(function () {
  'use strict';
  localStorage.removeItem('ecc-token');
  var app = Elm.Main.init({ node: document.getElementById('app') });
  // Authentication lives in a same-origin HttpOnly cookie, never web storage.
  app.ports.loadToken.send('');
  app.ports.loadDark.send(localStorage.getItem('ecc-dark') === '1');
  app.ports.saveToken.subscribe(function () {});
  app.ports.saveDark.subscribe(function (flag) {
    localStorage.setItem('ecc-dark', flag ? '1' : '0');
  });
})();
// Keep keyboard focus inside open dialogs and return it to the trigger on close.
(function () {
  var dialog = null;
  var previousFocus = null;
  new MutationObserver(function () {
    var dialogs = Array.from(document.querySelectorAll('[role="dialog"]'));
    var current = dialogs.length ? dialogs[dialogs.length - 1] : null;
    dialogs.forEach(function (item) { item.inert = item !== current; });
    if (current && current !== dialog) {
      previousFocus = document.activeElement;
      dialog = current;
      var first = dialog.querySelector('input,select,textarea,button,a[href]');
      (first || dialog).focus();
    } else if (!current && dialog) {
      dialog = null;
      if (previousFocus && previousFocus.isConnected) previousFocus.focus();
    }
  }).observe(document.body, { childList: true, subtree: true });
  document.addEventListener('keydown', function (event) {
    if (event.key === 'Escape' && dialog) {
      var dismiss = Array.from(dialog.querySelectorAll('button')).find(function (item) { return /^(Cancel|Close|Keep reviewing later)$/.test(item.textContent.trim()); });
      if (dismiss) { event.preventDefault(); dismiss.click(); }
      return;
    }
    if (event.key !== 'Tab' || !dialog) return;
    var controls = Array.from(dialog.querySelectorAll('input,select,textarea,button,a[href]')).filter(function (el) { return !el.disabled && el.offsetParent !== null; });
    if (!controls.length) { event.preventDefault(); dialog.focus(); return; }
    var first = controls[0], last = controls[controls.length - 1];
    if (event.shiftKey && document.activeElement === first) { event.preventDefault(); last.focus(); }
    if (!event.shiftKey && document.activeElement === last) { event.preventDefault(); first.focus(); }
  });
})();
