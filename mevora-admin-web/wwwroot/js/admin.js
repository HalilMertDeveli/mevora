// Mevora Trust & Safety console — progressive enhancement only.
// Every rule enforced here is also enforced on the server; this file just
// makes the safe path the easy one. No inline handlers (CSP script-src 'self').
(function () {
  "use strict";

  document.addEventListener("submit", function (event) {
    var form = event.target;
    if (!(form instanceof HTMLFormElement)) return;
    var message = form.getAttribute("data-confirm");
    if (message && !window.confirm(message)) {
      event.preventDefault();
      return;
    }
    // One click, one submission. The server's idempotency key covers the rest.
    var buttons = form.querySelectorAll("button[type=submit]");
    window.setTimeout(function () {
      buttons.forEach(function (b) { b.disabled = true; });
    }, 0);
  });

  // Suspension duration: reveal the custom-hours field only when chosen.
  document.querySelectorAll("select[data-custom-target]").forEach(function (select) {
    var target = document.getElementById(select.getAttribute("data-custom-target"));
    if (!target) return;
    var sync = function () { target.hidden = select.value !== "custom"; };
    select.addEventListener("change", sync);
    sync();
  });

  // Typed confirmation for irreversible actions (e.g. type BAN).
  document.querySelectorAll("input[data-confirm-word]").forEach(function (input) {
    var form = input.form;
    var word = input.getAttribute("data-confirm-word");
    var submit = form && form.querySelector("button[type=submit]");
    if (!submit) return;
    var sync = function () { submit.disabled = input.value.trim() !== word; };
    input.addEventListener("input", sync);
    sync();
  });

  // Reject needs a reason: keep the reject button disabled until one is picked.
  document.querySelectorAll("select[data-requires-for]").forEach(function (select) {
    var button = document.getElementById(select.getAttribute("data-requires-for"));
    if (!button) return;
    var sync = function () { button.disabled = !select.value; };
    select.addEventListener("change", sync);
    sync();
  });
})();
