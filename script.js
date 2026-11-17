(function () {
  "use strict";
  var cfg = window.SITE_CONFIG || {};

  function resolve(key) {
    var v = (cfg[key] || "").trim();
    if (!v) return "";
    if (key === "EMAIL_ADDRESS") return "mailto:" + v;
    return v;
  }

  // Links: show only when configured.
  document.querySelectorAll("[data-link]").forEach(function (a) {
    var href = resolve(a.getAttribute("data-link"));
    var soon = a.parentElement && a.parentElement.querySelector('[data-soon="' + a.getAttribute("data-link") + '"]');
    if (href) {
      a.setAttribute("href", href);
      a.hidden = false;
      if (/^https?:/i.test(href)) {
        a.setAttribute("target", "_blank");
        a.setAttribute("rel", "noopener noreferrer");
      }
      if (soon) soon.hidden = true;
    } else {
      a.hidden = true;
      if (soon) soon.hidden = false;
    }
  });

  // Hide containers whose buttons are all unconfigured.
  document.querySelectorAll("[data-hide-if-empty]").forEach(function (box) {
    var any = Array.prototype.some.call(box.querySelectorAll("[data-link]"), function (a) { return !a.hidden; });
    box.hidden = !any;
    var note = document.querySelector("[data-empty-note]");
    if (note) note.hidden = any;
  });

  // Plain-text contact values.
  document.querySelectorAll("[data-text]").forEach(function (el) {
    var v = (cfg[el.getAttribute("data-text")] || "").trim();
    if (v) { el.textContent = v; el.hidden = false; }
  });

  // External links that are written directly in the HTML.
  document.querySelectorAll('a[href^="http"]').forEach(function (a) {
    a.setAttribute("target", "_blank");
    a.setAttribute("rel", "noopener noreferrer");
  });

  // Mobile navigation toggle.
  var btn = document.getElementById("nav-toggle");
  var nav = document.getElementById("site-nav");
  if (btn && nav) {
    btn.addEventListener("click", function () {
      var open = nav.classList.toggle("open");
      btn.setAttribute("aria-expanded", open ? "true" : "false");
    });
    nav.addEventListener("click", function (e) {
      if (e.target.tagName === "A") { nav.classList.remove("open"); btn.setAttribute("aria-expanded", "false"); }
    });
  }

  // Highlight the current section in the navigation.
  if ("IntersectionObserver" in window) {
    var links = {};
    document.querySelectorAll("#site-nav a[href^='#']").forEach(function (a) { links[a.getAttribute("href").slice(1)] = a; });
    var io = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) {
        if (en.isIntersecting && links[en.target.id]) {
          Object.keys(links).forEach(function (k) { links[k].removeAttribute("aria-current"); });
          links[en.target.id].setAttribute("aria-current", "true");
        }
      });
    }, { rootMargin: "-40% 0px -55% 0px" });
    Object.keys(links).forEach(function (id) { var s = document.getElementById(id); if (s) io.observe(s); });
  }

  var y = document.getElementById("year");
  if (y) y.textContent = new Date().getFullYear();
})();
