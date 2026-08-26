(() => {
  const root = document.documentElement;
  const stored = localStorage.getItem("mevora-theme");
  const prefersDark = window.matchMedia("(prefers-color-scheme: dark)").matches;
  root.setAttribute("data-theme", stored || (prefersDark ? "dark" : "light"));

  const themeToggle = document.getElementById("themeToggle");
  themeToggle?.addEventListener("click", () => {
    const next = root.getAttribute("data-theme") === "dark" ? "light" : "dark";
    root.setAttribute("data-theme", next);
    localStorage.setItem("mevora-theme", next);
  });

  const navToggle = document.getElementById("navToggle");
  const mobileNav = document.getElementById("mobileNav");
  navToggle?.addEventListener("click", () => {
    const open = navToggle.getAttribute("aria-expanded") === "true";
    navToggle.setAttribute("aria-expanded", String(!open));
    navToggle.setAttribute("aria-label", open ? "Menüyü aç" : "Menüyü kapat");
    if (mobileNav) {
      mobileNav.hidden = open;
    }
  });

  mobileNav?.querySelectorAll("a").forEach((link) => {
    link.addEventListener("click", () => {
      if (navToggle && mobileNav) {
        navToggle.setAttribute("aria-expanded", "false");
        navToggle.setAttribute("aria-label", "Menüyü aç");
        mobileNav.hidden = true;
      }
    });
  });

  document.querySelectorAll(".support-chip").forEach((chip) => {
    chip.addEventListener("click", () => {
      const value = chip.getAttribute("data-category");
      const select = document.getElementById("supportCategory");
      if (select && value) {
        select.value = value;
        select.dispatchEvent(new Event("change", { bubbles: true }));
      }
      document.querySelectorAll(".support-chip").forEach((c) => c.classList.remove("is-active"));
      chip.classList.add("is-active");
    });
  });

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        entries.forEach((entry) => {
          if (entry.isIntersecting) {
            entry.target.classList.add("is-visible");
            observer.unobserve(entry.target);
          }
        });
      },
      { threshold: 0.12 }
    );
    document.querySelectorAll(".reveal").forEach((el) => observer.observe(el));
  } else {
    document.querySelectorAll(".reveal").forEach((el) => el.classList.add("is-visible"));
  }
})();
