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

  var reduceMotion = window.matchMedia && window.matchMedia("(prefers-reduced-motion: reduce)").matches;

  // Esc closes the mobile menu and returns focus to the toggle; outside click closes it too.
  if (btn && nav) {
    document.addEventListener("keydown", function (e) {
      if (e.key === "Escape" && nav.classList.contains("open")) {
        nav.classList.remove("open");
        btn.setAttribute("aria-expanded", "false");
        btn.focus();
      }
    });
    document.addEventListener("click", function (e) {
      if (nav.classList.contains("open") && !nav.contains(e.target) && !btn.contains(e.target)) {
        nav.classList.remove("open");
        btn.setAttribute("aria-expanded", "false");
      }
    });
  }

  // Scroll spy: primary navigation sections and featured projects.
  function setCurrent(groups, id) {
    Object.keys(groups).forEach(function (k) {
      groups[k].forEach(function (el) {
        if (k === id) { el.setAttribute("aria-current", "true"); } else { el.removeAttribute("aria-current"); }
      });
    });
  }
  var navLinks = {};
  function atPageBottom() {
    var max = document.documentElement.scrollHeight - window.innerHeight;
    return max > 0 && (window.pageYOffset || document.documentElement.scrollTop) >= max - 4;
  }
  if ("IntersectionObserver" in window) {
    var band = { rootMargin: "-35% 0px -55% 0px" };

    document.querySelectorAll("#site-nav a[href^='#']").forEach(function (a) {
      var id = a.getAttribute("href").slice(1);
      (navLinks[id] = navLinks[id] || []).push(a);
    });
    // Track which elements currently cross the band, then pick the last one in document order.
    // This is independent of the order in which observer callbacks arrive.
    var sectionIds = ["top", "focus", "projects", "impact", "how", "about", "contact"];
    var sectionSeen = {};
    var sectionIo = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { sectionSeen[en.target.id] = en.isIntersecting; });
      var current = "";
      sectionIds.forEach(function (id) { if (sectionSeen[id]) current = id; });
      if (atPageBottom()) current = "contact";
      setCurrent(navLinks, current);
      syncProjects();
    }, band);
    sectionIds.forEach(function (id) {
      var s = document.getElementById(id);
      if (s) sectionIo.observe(s);
    });

    // Projects: sync the hero shortcuts, the sticky rail and the cards.
    var projGroups = {};
    var projCards = {};
    document.querySelectorAll(".project[id]").forEach(function (card) { projCards[card.id] = card; });
    document.querySelectorAll(".project-pill[href^='#'], .proj-rail a[href^='#']").forEach(function (a) {
      var id = a.getAttribute("href").slice(1);
      (projGroups[id] = projGroups[id] || []).push(a);
    });
    var projSeen = {};
    var lastProject = "";
    function syncProjects() {
      var current = "";
      Object.keys(projCards).forEach(function (id) { if (projSeen[id]) current = id; });
      // Keep the last project highlighted across the small gaps between cards,
      // and clear it once the reader has left the Featured Projects section.
      if (current) lastProject = current;
      var inProjects = !!sectionSeen.projects;
      var shown = inProjects ? lastProject : "";
      setCurrent(projGroups, shown);
      // Keep the active chip visible in the swipeable rail (horizontal only; never moves the page).
      var rail = document.querySelector(".proj-rail");
      var chip = rail && rail.querySelector("a[aria-current]");
      if (rail && chip && rail.scrollWidth > rail.clientWidth) {
        var target = chip.offsetLeft - (rail.clientWidth - chip.offsetWidth) / 2;
        rail.scrollTo({ left: Math.max(0, target), behavior: reduceMotion ? "auto" : "smooth" });
      }
      Object.keys(projCards).forEach(function (k) { projCards[k].classList.toggle("is-active", k === shown); });
    }
    var projIo = new IntersectionObserver(function (entries) {
      entries.forEach(function (en) { projSeen[en.target.id] = en.isIntersecting; });
      syncProjects();
    }, band);
    Object.keys(projCards).forEach(function (id) { projIo.observe(projCards[id]); });

    // Section reveal: subtle fade-up, once, never for reduced-motion users.
    if (!reduceMotion) {
      var targets = document.querySelectorAll("main section:not(.hero) h2, main section:not(.hero) .lead, #focus .card, #impact .stat, #how ol.steps li, #about .card, .project, #contact .actions");
      document.documentElement.classList.add("js-reveal");
      var revealIo = new IntersectionObserver(function (entries, obs) {
        entries.forEach(function (en) {
          if (en.isIntersecting) { en.target.classList.add("in"); obs.unobserve(en.target); }
        });
      }, { threshold: 0.04, rootMargin: "0px 0px -4% 0px" });
      targets.forEach(function (el) { el.classList.add("reveal"); revealIo.observe(el); });
    }
  }

  // Reading progress, header state and back-to-top (one rAF-throttled passive listener).
  var header = document.querySelector(".site-header");
  var bar = document.querySelector(".progress span");
  var toTop = document.querySelector(".to-top");
  document.documentElement.classList.add("js");
  var ticking = false;
  function onScroll() {
    ticking = false;
    var y = window.pageYOffset || document.documentElement.scrollTop;
    var max = document.documentElement.scrollHeight - window.innerHeight;
    if (bar && max > 0) bar.parentNode.style.setProperty("--progress", Math.min(1, Math.max(0, y / max)).toFixed(4));
    if (header) header.classList.toggle("is-scrolled", y > 8);
    if (toTop) toTop.classList.toggle("show", y > 900);
    // The short Contact section never reaches the observer band; treat page bottom as Contact.
    if (navLinks.contact && atPageBottom()) setCurrent(navLinks, "contact");
  }
  window.addEventListener("scroll", function () {
    if (!ticking) { ticking = true; window.requestAnimationFrame(onScroll); }
  }, { passive: true });
  window.addEventListener("resize", onScroll, { passive: true });
  onScroll();
  if (toTop) {
    toTop.addEventListener("click", function (e) {
      e.preventDefault();
      window.scrollTo({ top: 0, behavior: reduceMotion ? "auto" : "smooth" });
      var top = document.getElementById("top");
      if (top) { top.setAttribute("tabindex", "-1"); top.focus({ preventScroll: true }); }
    });
  }

  // Deep links: re-align once everything has loaded, so late layout shifts do not leave the target off-screen.
  window.addEventListener("load", function () {
    if (!location.hash || location.hash.length < 2) return;
    var t = null;
    try { t = document.getElementById(decodeURIComponent(location.hash.slice(1))); } catch (e) { t = null; }
    if (t) t.scrollIntoView({ behavior: "auto", block: "start" });
  });

  var y = document.getElementById("year");
  if (y) y.textContent = new Date().getFullYear();
})();
