/* Formular für die Vorgabe (Server und RemoteApps) einer Lizenz. */
(function () {
  function uuid() {
    if (window.crypto && crypto.randomUUID) return crypto.randomUUID();
    return 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'.replace(/[xy]/g, function (c) {
      var r = Math.random() * 16 | 0, v = c === 'x' ? r : (r & 0x3 | 0x8);
      return v.toString(16);
    });
  }

  function nextIndex(container) {
    var n = 0;
    container.querySelectorAll(':scope > div').forEach(function (row) {
      var input = row.querySelector('input[name]');
      if (!input) return;
      var m = input.name.match(/\[(\d+)\]/);
      if (m && parseInt(m[1], 10) >= n) n = parseInt(m[1], 10) + 1;
    });
    return n;
  }

  function cloneTemplate(templateId, container) {
    var tpl = document.getElementById(templateId);
    if (!tpl) return null;
    var html = tpl.innerHTML.replace(/__INDEX__/g, String(nextIndex(container)));
    var wrapper = document.createElement('div');
    wrapper.innerHTML = html.trim();
    var row = wrapper.firstElementChild;
    container.appendChild(row);
    return row;
  }

  function refreshServerOptions() {
    var servers = [];
    document.querySelectorAll('#multirdp-servers .multirdp-server-row').forEach(function (row) {
      servers.push({ id: row.querySelector('.multirdp-server-id').value,
                     name: row.querySelector('.multirdp-server-name').value || '(?)' });
    });
    document.querySelectorAll('#multirdp-apps .multirdp-app-server').forEach(function (select) {
      var current = select.value || select.getAttribute('data-selected') || '';
      select.innerHTML = '';
      servers.forEach(function (s) {
        var opt = document.createElement('option');
        opt.value = s.id; opt.textContent = s.name;
        if (s.id === current) opt.selected = true;
        select.appendChild(opt);
      });
    });
  }

  document.addEventListener('DOMContentLoaded', function () {
    var form = document.getElementById('multirdp-license-form');
    if (!form) return;

    form.addEventListener('click', function (e) {
      var btn = e.target.closest('button');
      if (!btn) return;
      if (btn.classList.contains('multirdp-add-server')) {
        e.preventDefault();
        var row = cloneTemplate('multirdp-server-template', document.getElementById('multirdp-servers'));
        if (row) row.querySelector('.multirdp-server-id').value = uuid();
        refreshServerOptions();
      } else if (btn.classList.contains('multirdp-add-app')) {
        e.preventDefault();
        var appRow = cloneTemplate('multirdp-app-template', document.getElementById('multirdp-apps'));
        if (appRow) appRow.querySelector('input[type=hidden]').value = uuid();
        refreshServerOptions();
      } else if (btn.classList.contains('multirdp-remove-row')) {
        e.preventDefault();
        var target = btn.closest('.multirdp-server-row, .multirdp-app-row');
        if (target) target.remove();
        refreshServerOptions();
      }
    });

    form.addEventListener('input', function (e) {
      if (e.target.classList.contains('multirdp-server-name')) refreshServerOptions();
    });

    refreshServerOptions();
  });
})();
