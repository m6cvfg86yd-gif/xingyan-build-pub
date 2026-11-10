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

  const previewChats = {
    design: {
      name: "设计协作",
      avatar: "设",
      tone: "blue",
      status: "8 位成员",
      messages: [
        { type: "incoming", sender: "林澈", avatar: "林", tone: "blue", text: "新的深色版本已经打包好了。" },
        { type: "outgoing", text: "收到，我正在电脑上检查。" },
        { type: "file", name: "Star-chat-设计稿.pdf", size: "12.8 MB", progress: 76 },
      ],
    },
    family: {
      name: "家人群",
      avatar: "家",
      tone: "green",
      status: "6 位成员",
      messages: [
        { type: "incoming", sender: "妈妈", avatar: "妈", tone: "green", text: "今晚早点回来。" },
        { type: "outgoing", text: "好，我收拾一下就走。" },
        { type: "incoming", sender: "爸爸", avatar: "爸", tone: "gray", text: "路上慢一点。" },
      ],
    },
    official: {
      name: "星言官方",
      avatar: "星",
      tone: "gray",
      status: "官方账号",
      messages: [
        { type: "incoming", sender: "星言官方", avatar: "星", tone: "gray", text: "欢迎来到 Star chat。" },
        { type: "incoming", sender: "星言官方", avatar: "星", tone: "gray", text: "这次官网已经换成星言深色版本。" },
        { type: "outgoing", text: "看到了，很干净。" },
      ],
    },
  };

  const previewRoot = document.querySelector(".app-shell");
  const previewList = document.querySelector("[data-preview-message-list]");
  const previewInput = document.querySelector("[data-preview-input]");
  const previewHint = document.querySelector(".preview-hint");
  let activePreviewChat = "design";

  const escapeHtml = (value) => String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

  const renderPreviewMessages = () => {
    if (!previewList) return;
    const chat = previewChats[activePreviewChat];
    previewList.innerHTML = chat.messages.map((message) => {
      if (message.type === "file") {
        const progress = message.progress ?? 100;
        const progressText = message.progress == null
          ? `${message.size} · 已发送`
          : `${message.size} · 上传中 ${message.progress}%`;
        return `<div class="preview-file" role="button" tabindex="0" aria-label="打开演示文件">
          <span class="preview-file-icon">PDF</span>
          <div><b>${escapeHtml(message.name)}</b><small>${progressText}</small><em><i style="width:${progress}%"></i></em></div>
          <strong>${message.progress == null ? "↓" : "↑"}</strong>
        </div>`;
      }
      if (message.type === "incoming") {
        return `<div class="preview-message incoming">
          <span class="preview-avatar ${message.tone}">${escapeHtml(message.avatar)}</span>
          <div><small>${escapeHtml(message.sender)}</small><p>${escapeHtml(message.text)}</p></div>
        </div>`;
      }
      return `<div class="preview-message outgoing"><p>${escapeHtml(message.text)}</p></div>`;
    }).join("");
  };

  const selectPreviewChat = (key) => {
    const chat = previewChats[key];
    if (!chat) return;
    activePreviewChat = key;
    document.querySelectorAll("[data-preview-chat]").forEach((row) => {
      row.classList.toggle("active", row.dataset.previewChat === key);
    });
    const avatar = document.querySelector("[data-preview-avatar]");
    avatar.textContent = chat.avatar;
    avatar.className = `preview-avatar ${chat.tone}`;
    document.querySelector("[data-preview-name]").textContent = chat.name;
    document.querySelector("[data-preview-status]").textContent = chat.status;
    renderPreviewMessages();
  };

  if (previewRoot) {
    document.querySelectorAll("[data-preview-rail]").forEach((button) => {
      button.addEventListener("click", () => {
        document.querySelectorAll("[data-preview-rail]").forEach((item) => {
          item.classList.toggle("active", item === button);
        });
        previewHint.textContent = `${button.getAttribute("aria-label")} 页面已接入交互演示`;
      });
    });

    document.querySelectorAll("[data-preview-chat]").forEach((row) => {
      row.addEventListener("click", () => selectPreviewChat(row.dataset.previewChat));
    });

    let activeFilter = "all";
    const applyPreviewFilter = () => {
      const query = document
        .querySelector("[data-preview-search]")
        ?.value.trim().toLowerCase() ?? "";
      document.querySelectorAll("[data-preview-chat]").forEach((row) => {
        const kind = row.dataset.kind;
        const unread = Number(row.dataset.unread || 0);
        const pinned = row.dataset.pinned === "true";
        const matchesFilter =
          activeFilter === "all" ||
          (activeFilter === "unread" && unread > 0) ||
          (activeFilter === "group" && kind === "group") ||
          (activeFilter === "pinned" && pinned);
        const matchesQuery = !query || row.textContent.toLowerCase().includes(query);
        row.hidden = !(matchesFilter && matchesQuery);
      });
    };

    document.querySelectorAll("[data-preview-filter]").forEach((button) => {
      button.addEventListener("click", () => {
        activeFilter = button.dataset.previewFilter;
        document.querySelectorAll("[data-preview-filter]").forEach((item) => {
          item.setAttribute("aria-pressed", String(item === button));
        });
        applyPreviewFilter();
      });
    });
    document
      .querySelector("[data-preview-search]")
      ?.addEventListener("input", applyPreviewFilter);

    const sendPreviewMessage = () => {
      const text = previewInput?.value.trim() ?? "";
      if (!text) {
        previewHint.textContent = "先输入一条消息再发送";
        return;
      }
      previewChats[activePreviewChat].messages.push({ type: "outgoing", text });
      previewInput.value = "";
      renderPreviewMessages();
      previewHint.textContent = "消息已发送到深色预览";
    };

    document.querySelector("[data-preview-send]")?.addEventListener("click", sendPreviewMessage);
    previewInput?.addEventListener("keydown", (event) => {
      if (event.key === "Enter") sendPreviewMessage();
    });
    document.querySelector('[data-preview-action="emoji"]')?.addEventListener("click", () => {
      if (!previewInput) return;
      previewInput.value += "🙂";
      previewInput.focus();
    });
    document.querySelector('[data-preview-action="plus"]')?.addEventListener("click", () => {
      const file = {
        type: "file",
        name: "星言-共享文件.pdf",
        size: "8.4 MB",
        progress: 0,
      };
      previewChats[activePreviewChat].messages.push(file);
      renderPreviewMessages();
      const timer = window.setInterval(() => {
        file.progress = Math.min(100, file.progress + 8);
        if (file.progress >= 100) {
          file.progress = null;
          window.clearInterval(timer);
        }
        if (activePreviewChat && previewChats[activePreviewChat].messages.includes(file)) {
          renderPreviewMessages();
        }
      }, 110);
    });

    previewList?.addEventListener("click", (event) => {
      if (event.target.closest(".preview-file")) {
        previewHint.textContent = "文件已打开（交互演示）";
      }
    });
    document.querySelectorAll("[data-preview-head]").forEach((item) => {
      item.addEventListener("click", () => {
        previewHint.textContent = `${item.getAttribute("aria-label")} 功能已接入演示`;
      });
    });
    selectPreviewChat("design");

    const productStage = document.querySelector(".product-stage");
    const appWindow = document.querySelector(".app-window");
    const reduceMotion = window.matchMedia("(prefers-reduced-motion: reduce)").matches;
    if (productStage && appWindow && !reduceMotion) {
      let pointerFrame = 0;
      productStage.addEventListener("pointermove", (event) => {
        if (pointerFrame) return;
        pointerFrame = requestAnimationFrame(() => {
          pointerFrame = 0;
          const rect = productStage.getBoundingClientRect();
          const x = (event.clientX - rect.left) / rect.width - 0.5;
          const y = (event.clientY - rect.top) / rect.height - 0.5;
          appWindow.style.setProperty("--preview-rotate-y", `${x * 2.2}deg`);
          appWindow.style.setProperty("--preview-rotate-x", `${1.2 - y * 1.8}deg`);
        });
      });
      productStage.addEventListener("pointerleave", () => {
        appWindow.style.setProperty("--preview-rotate-y", "0deg");
        appWindow.style.setProperty("--preview-rotate-x", "1.2deg");
      });

      const updatePreviewDepth = () => {
        const rect = productStage.getBoundingClientRect();
        const progress = Math.max(
          0,
          Math.min(1, (window.innerHeight - rect.top) / (window.innerHeight + rect.height)),
        );
        appWindow.style.setProperty("--preview-scale", String(.972 + progress * .038));
      };
      updatePreviewDepth();
      window.addEventListener("scroll", updatePreviewDepth, { passive: true });
    }
  }

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
