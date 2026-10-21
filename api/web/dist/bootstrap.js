(function () {
  'use strict';
  localStorage.removeItem('ecc-token');
  var app = Elm.Main.init({ node: document.getElementById('app') });
  window.ECCReports(app);
  // Authentication lives in a same-origin HttpOnly cookie, never web storage.
  app.ports.loadToken.send('');
  app.ports.loadDark.send(localStorage.getItem('ecc-dark') === '1');
  app.ports.saveToken.subscribe(function () {});
  app.ports.focusFeatureForm.subscribe(function () {
    requestAnimationFrame(function () {
      var editor = document.querySelector('.feature-editor');
      if (!editor) return;
      editor.scrollIntoView({ block: 'center', behavior: 'smooth' });
      var control = editor.querySelector('input:not(:disabled),select:not(:disabled),textarea:not(:disabled)');
      if (control) control.focus({ preventScroll: true });
    });
  });
  app.ports.unsavedChanges.subscribe(function (dirty) {
    document.dispatchEvent(new CustomEvent('ecc-unsaved-changes', { detail: dirty }));
  });
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

// Warn on reload/close without storing CRM fields or credentials in the browser.
(function () {
  var dirty = false;
  // Only a boolean leaves Elm here; no form values or credentials are stored.
  window.addEventListener('beforeunload', function (event) {
    if (!dirty) return;
    event.preventDefault();
    event.returnValue = '';
  });
  document.addEventListener('ecc-unsaved-changes', function (event) { dirty = event.detail; });
})();

// Install controls are progressive enhancement; Safari uses Add to Home Screen.
(function () {
  if (!('serviceWorker' in navigator) || !window.isSecureContext) return;
  window.addEventListener('load', function () {
    navigator.serviceWorker.register('/sw.js').catch(function () {
      // A failed registration must never interrupt the CRM.
    });
  });
  var promptEvent;
  var install = document.createElement('button');
  install.type = 'button';
  install.className = 'pwa-install btn btn-primary';
  install.textContent = 'Install ECC app';
  install.hidden = true;
  document.body.appendChild(install);
  window.addEventListener('beforeinstallprompt', function (event) {
    event.preventDefault();
    promptEvent = event;
    install.hidden = false;
  });
  install.addEventListener('click', async function () {
    if (!promptEvent) return;
    install.hidden = true;
    var pending = promptEvent;
    promptEvent = null;
    await pending.prompt();
  });
  window.addEventListener('appinstalled', function () {
    install.hidden = true;
    promptEvent = null;
  });
})();

(function () {
  function menu() { return document.querySelector('.mobile-more[open]'); }
  document.addEventListener('click', function (event) {
    var open = menu();
    if (!open) return;
    if (!open.contains(event.target) || event.target.closest('a,button')) open.open = false;
  });
  document.addEventListener('keydown', function (event) {
    var open = menu();
    if (event.key === 'Escape' && open) {
      open.open = false;
      open.querySelector('summary').focus();
      event.preventDefault();
    }
  });
})();
