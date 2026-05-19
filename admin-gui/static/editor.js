(() => {
  const editables = Array.from(document.querySelectorAll("[data-edit-source][data-edit-field]"));
  const startButton = document.querySelector("[data-edit-start]");
  const saveButton = document.querySelector("[data-edit-save]");
  const cancelButton = document.querySelector("[data-edit-cancel]");
  const status = document.querySelector(".config-status");

  if (!startButton || !saveButton || !cancelButton) {
    return;
  }

  if (editables.length === 0) {
    startButton.hidden = true;
    return;
  }

  const originalHtml = new Map();
  const originalText = new Map();

  function setEditing(enabled) {
    document.body.classList.toggle("text-editing", enabled);
    startButton.hidden = enabled;
    saveButton.hidden = !enabled;
    cancelButton.hidden = !enabled;
    if (status) {
      status.hidden = enabled;
    }

    for (const element of editables) {
      if (enabled) {
        originalHtml.set(element, element.innerHTML);
        originalText.set(element, editableValue(element));
        element.setAttribute("contenteditable", "true");
        element.setAttribute("spellcheck", "true");
      } else {
        element.removeAttribute("contenteditable");
        element.removeAttribute("spellcheck");
      }
    }

    if (enabled && editables[0]) {
      editables[0].focus();
    }
  }

  function restoreOriginals() {
    for (const element of editables) {
      if (originalHtml.has(element)) {
        element.innerHTML = originalHtml.get(element);
      }
    }
  }

  function editableValue(element) {
    if (element.dataset.editList === "true") {
      const items = Array.from(element.querySelectorAll("li"))
        .map((item) => item.innerText.trim())
        .filter(Boolean);
      return items.join("\n");
    }
    return element.innerText.trim();
  }

  function collectItems() {
    const byKey = new Map();
    for (const element of editables) {
      const source = element.dataset.editSource || "";
      const id = element.dataset.editId || "";
      const field = element.dataset.editField || "";
      if (!source || !field) {
        continue;
      }
      const key = `${source}\u0000${id}\u0000${field}`;
      const value = editableValue(element);
      const changed = value !== (originalText.get(element) || "");
      const existing = byKey.get(key);
      if (existing && existing.changed && !changed) {
        continue;
      }
      byKey.set(key, {
        changed,
        item: {
          source,
          id,
          field,
          value,
        },
      });
    }
    return Array.from(byKey.values()).map((entry) => entry.item);
  }

  startButton.addEventListener("click", () => {
    setEditing(true);
  });

  cancelButton.addEventListener("click", () => {
    restoreOriginals();
    setEditing(false);
  });

  saveButton.addEventListener("click", async () => {
    saveButton.disabled = true;
    cancelButton.disabled = true;
    const oldText = saveButton.textContent;
    saveButton.textContent = "Speichere...";

    try {
      const response = await fetch("/save-inline-texts", {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
        },
        body: JSON.stringify({ items: collectItems() }),
      });
      if (!response.ok) {
        const text = await response.text();
        throw new Error(text || `HTTP ${response.status}`);
      }
      window.location.reload();
    } catch (error) {
      alert(`Speichern fehlgeschlagen:\n${error.message}`);
      saveButton.disabled = false;
      cancelButton.disabled = false;
      saveButton.textContent = oldText;
    }
  });
})();
