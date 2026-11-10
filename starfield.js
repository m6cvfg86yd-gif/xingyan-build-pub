(() => {
  const canvas = document.querySelector("#starfield");
  if (!canvas) return;

  const context = canvas.getContext("2d", { alpha: true });
  if (!context) return;

  const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
  let width = 0;
  let height = 0;
  let stars = [];
  let shootingStars = [];
  let frameId = 0;
  let lastFrame = 0;
  let nextShootingStar = Number.POSITIVE_INFINITY;
  let pointerTargetX = 0;
  let pointerTargetY = 0;
  let pointerX = 0;
  let pointerY = 0;

  const makeStars = () => {
    const count = Math.max(52, Math.min(280, Math.round((width * height) / 9000)));
    stars = Array.from({ length: count }, (_, index) => ({
      x: Math.random() * width,
      y: Math.random() * height,
      depth: 0.22 + Math.random() * 0.78,
      radius: 0.35 + Math.random() * 1.4,
      alpha: 0.22 + Math.random() * 0.76,
      phase: Math.random() * Math.PI * 2,
      speed: 0.00045 + Math.random() * 0.0011,
      drift: (Math.random() - 0.5) * 0.018,
      tint: index % 9 === 0 ? "220, 220, 220" : "255, 255, 255",
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
    pointerX += (pointerTargetX - pointerX) * 0.035;
    pointerY += (pointerTargetY - pointerY) * 0.035;

    for (const star of stars) {
      const pulse = 0.58 + Math.sin(time * star.speed + star.phase) * 0.42;
      const alpha = Math.max(0.06, star.alpha * pulse);
      if (!staticFrame) {
        star.x += star.drift * star.depth;
        if (star.x < -2) star.x = width + 2;
        if (star.x > width + 2) star.x = -2;
      }
      const drawX = star.x + pointerX * star.depth * 17;
      const drawY = star.y + pointerY * star.depth * 12;
      context.beginPath();
      context.fillStyle = `rgba(${star.tint}, ${alpha})`;
      context.arc(drawX, drawY, star.radius * (.72 + star.depth * .42), 0, Math.PI * 2);
      context.fill();

    }

    if (!staticFrame && time > nextShootingStar) {
      const fromLeft = Math.random() > 0.45;
      shootingStars.push({
        x: fromLeft ? width * (0.05 + Math.random() * 0.28) : width * (0.62 + Math.random() * 0.24),
        y: height * (0.08 + Math.random() * 0.24),
        vx: (fromLeft ? 1 : -1) * (7 + Math.random() * 3.5),
        vy: 3.4 + Math.random() * 1.8,
        life: 0,
        maxLife: 48 + Math.random() * 18,
      });
      nextShootingStar = time + 8500 + Math.random() * 7500;
    }

    for (const meteor of shootingStars) {
      const opacity = Math.max(0, 1 - meteor.life / meteor.maxLife) * .72;
      const gradient = context.createLinearGradient(
        meteor.x,
        meteor.y,
        meteor.x - meteor.vx * 12,
        meteor.y - meteor.vy * 12,
      );
      gradient.addColorStop(0, `rgba(255,255,255,${opacity})`);
      gradient.addColorStop(.28, `rgba(220,220,220,${opacity * .52})`);
      gradient.addColorStop(1, "rgba(255,255,255,0)");
      context.beginPath();
      context.strokeStyle = gradient;
      context.lineWidth = 1;
      context.moveTo(meteor.x, meteor.y);
      context.lineTo(meteor.x - meteor.vx * 12, meteor.y - meteor.vy * 12);
      context.stroke();
      meteor.x += meteor.vx;
      meteor.y += meteor.vy;
      meteor.life += 1;
    }
    shootingStars = shootingStars.filter((meteor) => meteor.life < meteor.maxLife);
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
  window.addEventListener("pointermove", (event) => {
    pointerTargetX = (event.clientX / Math.max(1, width) - .5) * 2;
    pointerTargetY = (event.clientY / Math.max(1, height) - .5) * 2;
  }, { passive: true });
  document.addEventListener("visibilitychange", () => {
    if (document.hidden) {
      cancelAnimationFrame(frameId);
      frameId = 0;
    } else {
      start();
    }
  });
})();
