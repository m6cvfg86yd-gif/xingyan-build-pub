(() => {
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
        { type: "incoming", sender: "星言官方", avatar: "星", tone: "gray", text: "这里是真实的深色交互页面。" },
        { type: "outgoing", text: "页面也可以直接操作。" },
      ],
    },
  };

  const messageList = document.querySelector("[data-preview-message-list]");
  const input = document.querySelector("[data-preview-input]");
  const status = document.querySelector(".preview-status");
  let activeChat = "design";

  const escapeHtml = (value) => String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#039;");

  const setStatus = (text) => {
    if (status) status.textContent = text;
  };

  const renderMessages = () => {
    const chat = previewChats[activeChat];
    messageList.innerHTML = chat.messages.map((message) => {
      if (message.type === "file") {
        const progress = message.progress ?? 100;
        const label = message.progress == null
          ? `${message.size} · 已发送`
          : `${message.size} · 上传中 ${message.progress}%`;
        return `<div class="preview-file" role="button" tabindex="0" aria-label="打开演示文件">
          <span class="preview-file-icon">PDF</span>
          <div><b>${escapeHtml(message.name)}</b><small>${label}</small><em><i style="width:${progress}%"></i></em></div>
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

  const selectChat = (key) => {
    const chat = previewChats[key];
    if (!chat) return;
    activeChat = key;
    document.querySelectorAll("[data-preview-chat]").forEach((row) => {
      row.classList.toggle("active", row.dataset.previewChat === key);
    });
    const avatar = document.querySelector("[data-preview-avatar]");
    avatar.textContent = chat.avatar;
    avatar.className = `preview-avatar ${chat.tone}`;
    document.querySelector("[data-preview-name]").textContent = chat.name;
    document.querySelector("[data-preview-status]").textContent = chat.status;
    renderMessages();
  };

  document.querySelectorAll("[data-preview-chat]").forEach((row) => {
    row.addEventListener("click", () => selectChat(row.dataset.previewChat));
  });
  document.querySelectorAll("[data-preview-rail]").forEach((button) => {
    button.addEventListener("click", () => {
      document.querySelectorAll("[data-preview-rail]").forEach((item) => {
        item.classList.toggle("active", item === button);
      });
      setStatus(`${button.getAttribute("aria-label")} 页面已接入演示`);
    });
  });

  let activeFilter = "all";
  const applyFilter = () => {
    const query = document.querySelector("[data-preview-search]").value.trim().toLowerCase();
    document.querySelectorAll("[data-preview-chat]").forEach((row) => {
      const matchesFilter =
        activeFilter === "all" ||
        (activeFilter === "unread" && Number(row.dataset.unread) > 0) ||
        (activeFilter === "group" && row.dataset.kind === "group") ||
        (activeFilter === "pinned" && row.dataset.pinned === "true");
      row.hidden = !(matchesFilter && (!query || row.textContent.toLowerCase().includes(query)));
    });
  };
  document.querySelectorAll("[data-preview-filter]").forEach((button) => {
    button.addEventListener("click", () => {
      activeFilter = button.dataset.previewFilter;
      document.querySelectorAll("[data-preview-filter]").forEach((item) => {
        item.setAttribute("aria-pressed", String(item === button));
      });
      applyFilter();
    });
  });
  document.querySelector("[data-preview-search]").addEventListener("input", applyFilter);

  const sendMessage = () => {
    const text = input.value.trim();
    if (!text) {
      setStatus("先输入一条消息再发送");
      return;
    }
    previewChats[activeChat].messages.push({ type: "outgoing", text });
    input.value = "";
    renderMessages();
    setStatus("消息已发送到深色预览");
  };

  document.querySelector("[data-preview-send]").addEventListener("click", sendMessage);
  input.addEventListener("keydown", (event) => {
    if (event.key === "Enter") sendMessage();
  });
  document.querySelector('[data-preview-action="emoji"]').addEventListener("click", () => {
    input.value += "🙂";
    input.focus();
  });
  document.querySelector('[data-preview-action="plus"]').addEventListener("click", () => {
    const file = { type: "file", name: "星言-共享文件.pdf", size: "8.4 MB", progress: 0 };
    previewChats[activeChat].messages.push(file);
    renderMessages();
    const timer = window.setInterval(() => {
      file.progress = Math.min(100, file.progress + 8);
      if (file.progress >= 100) {
        file.progress = null;
        window.clearInterval(timer);
      }
      if (previewChats[activeChat].messages.includes(file)) renderMessages();
    }, 110);
  });
  document.querySelectorAll("[data-preview-head]").forEach((item) => {
    item.addEventListener("click", () => {
      setStatus(`${item.getAttribute("aria-label")} 功能已接入演示`);
    });
  });
  messageList.addEventListener("click", (event) => {
    if (event.target.closest(".preview-file")) setStatus("文件已打开（交互演示）");
  });

  selectChat("design");
})();
