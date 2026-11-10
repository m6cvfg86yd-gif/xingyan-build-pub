(() => {
  document.documentElement.classList.add("js-ready");

  const year = document.querySelector("#year");
  if (year) year.textContent = String(new Date().getFullYear());

  const revealItems = document.querySelectorAll(".reveal");
  document.querySelector(".hero")?.classList.add("is-visible");

  const revealVisibleItems = () => {
    const limit = window.innerHeight * 0.96;
    revealItems.forEach((item) => {
      if (item.getBoundingClientRect().top < limit) {
        item.classList.add("is-visible");
      }
    });
  };

  if ("IntersectionObserver" in window) {
    const observer = new IntersectionObserver(
      (entries) => {
        for (const entry of entries) {
          if (!entry.isIntersecting) continue;
          entry.target.classList.add("is-visible");
          observer.unobserve(entry.target);
        }
      },
      { rootMargin: "0px 0px -8% 0px", threshold: 0.08 },
    );
    revealItems.forEach((item) => observer.observe(item));
  } else {
    revealItems.forEach((item) => item.classList.add("is-visible"));
  }
  requestAnimationFrame(revealVisibleItems);
  window.addEventListener("load", revealVisibleItems, { once: true });

  const header = document.querySelector(".site-header");
  const updateHeader = () => {
    if (!header) return;
    header.style.background = window.scrollY > 24
      ? "rgba(0,0,0,.88)"
      : "rgba(0,0,0,.72)";
  };
  updateHeader();
  window.addEventListener("scroll", updateHeader, { passive: true });
})();
