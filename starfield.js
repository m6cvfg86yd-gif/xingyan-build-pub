(() => {
  const canvas = document.querySelector("#starfield");
  if (!canvas) return;

  const context = canvas.getContext("2d", { alpha: true });
  if (!context) return;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let width = 0;
  let height = 0;
  let stars = [];
  let frameId = 0;
  let lastFrame = 0;

  const makeStars = () => {
    const count = Math.max(45, Math.min(150, Math.round((width * height) / 15000)));
    stars = Array.from({ length: count }, (_, index) => ({
      x: Math.random() * width,
      y: Math.random() * height,
      radius: 0.35 + Math.random() * 1.15,
      alpha: 0.18 + Math.random() * 0.68,
      phase: Math.random() * Math.PI * 2,
      speed: 0.00045 + Math.random() * 0.0011,
      drift: (Math.random() - 0.5) * 0.012,
      tint: index % 11 === 0 ? "176, 214, 255" : index % 17 === 0 ? "174, 255, 215" : "255, 255, 255",
    }));
  };

  const resize = () => {
    const ratio = Math.min(window.devicePixelRatio || 1, 1.6);
    width = window.innerWidth;
    height = window.innerHeight;
    canvas.width = Math.round(width * ratio);
    canvas.height = Math.round(height * ratio);
    canvas.style.width = `${width}px`;
    canvas.style.height = `${height}px`;
    context.setTransform(ratio, 0, 0, ratio, 0, 0);
    makeStars();
    if (reduceMotion) draw(0, true);
  };

  const draw = (time, staticFrame = false) => {
    context.clearRect(0, 0, width, height);
    context.globalCompositeOperation = "lighter";

    for (const star of stars) {
      const pulse = 0.58 + Math.sin(time * star.speed + star.phase) * 0.42;
      const alpha = Math.max(0.06, star.alpha * pulse);
      if (!staticFrame) {
        star.x += star.drift;
        if (star.x < -2) star.x = width + 2;
        if (star.x > width + 2) star.x = -2;
      }
      context.beginPath();
      context.fillStyle = `rgba(${star.tint}, ${alpha})`;
      context.arc(star.x, star.y, star.radius, 0, Math.PI * 2);
      context.fill();

      if (star.radius > 1.18) {
        context.beginPath();
        context.fillStyle = `rgba(${star.tint}, ${alpha * 0.12})`;
        context.arc(star.x, star.y, star.radius * 3.4, 0, Math.PI * 2);
        context.fill();
      }
    }
  };

  const animate = (time) => {
    if (document.hidden) {
      frameId = 0;
      return;
    }
    if (time - lastFrame >= 1000 / 30) {
      lastFrame = time;
      draw(time);
    }
    frameId = requestAnimationFrame(animate);
  };

  const start = () => {
    cancelAnimationFrame(frameId);
    frameId = 0;
    if (reduceMotion) {
      draw(0, true);
      return;
    }
    lastFrame = performance.now();
    frameId = requestAnimationFrame(animate);
  };

  resize();
  start();
  window.addEventListener("resize", resize, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      cancelAnimationFrame(frameId);
      frameId = 0;
    } else {
      start();
    }
  });
})();
