/* Drel site interactions: copy-to-clipboard buttons and inline playgrounds. */
(function () {
  "use strict";

  /* ── Copy buttons ─────────────────────────────────────────────────── */
  function fallbackCopy(text) {
    const field = document.createElement("textarea");
    field.value = text;
    field.setAttribute("readonly", "");
    field.style.position = "fixed";
    field.style.opacity = "0";
    document.body.appendChild(field);
    field.select();
    try {
      document.execCommand("copy");
    } finally {
      field.remove();
    }
  }

  async function copyText(text) {
    try {
      await navigator.clipboard.writeText(text);
    } catch (error) {
      fallbackCopy(text);
    }
  }

  function initCopyButtons() {
    document.querySelectorAll("[data-copy-command]").forEach(function (button) {
      button.addEventListener("click", async function () {
        const command = button.dataset.copyCommand;
        const status = button.nextElementSibling;
        const originalText = button.textContent;
        await copyText(command);
        button.textContent = "✓ Copied!";
        button.classList.add("copied");
        if (status) {
          status.textContent = "Copied to clipboard — paste it wherever you need.";
        }
        window.setTimeout(function () {
          button.textContent = originalText;
          button.classList.remove("copied");
          if (status) status.textContent = "";
        }, 2200);
      });
    });
  }

  /* ── Push playground ──────────────────────────────────────────────── */
  // A small client-side request builder. The device key never leaves the
  // page: the request is sent straight from the browser to the relay.
  //
  // Two ways to name a destination:
  //   * a key      — the official relay is assumed
  //   * an address — a full push address, self-hosted or not
  // Templates are grouped by what the sender is trying to do, so the right
  // one is obvious from its title and description rather than from a flat
  // list of eight equal chips.
  const TEMPLATE_GROUPS = [
    {
      title: "Just send a message",
      description: "A title and a body. Nothing opens when it is tapped.",
      templates: [
        {
          key: "plain",
          label: "Plain text",
          hint: "The simplest possible notification.",
          fields: { title: "Build complete", body: "Open the report" },
        },
        {
          key: "badge",
          label: "With a badge and sound",
          hint: "Sets an app badge and a named notification sound.",
          fields: {
            title: "Unread messages",
            body: "You have 3 new messages",
            badge: 3,
            sound: "alarm.caf",
          },
        },
      ],
    },
    {
      title: "Open a web page",
      description: "Tapping the notification opens an exact HTTPS destination.",
      templates: [
        {
          key: "url",
          label: "Open a URL",
          hint: "The destination opens as a normal page.",
          fields: {
            title: "Build complete",
            body: "Open the release report",
            url: "https://tools.example/release/42",
          },
        },
        {
          key: "immersive",
          label: "Open fullscreen",
          hint: "The destination opens in the immersive container.",
          fields: {
            title: "Build complete",
            body: "Open the release report",
            url: "https://tools.example/release/42",
            display: "full",
          },
        },
        {
          key: "sheet",
          label: "Open as a sheet",
          hint: "The destination opens as a sheet instead of a full page.",
          fields: {
            title: "New order",
            body: "Order 1024 is ready",
            url: "https://tools.example/orders/1024",
            display: "sheet",
          },
        },
      ],
    },
    {
      title: "Open a screen inside an app",
      description: "Routes into a registered web app at an exact route.",
      templates: [
        {
          key: "route",
          label: "App route",
          hint: "The route must be listed in the app's signed manifest.",
          fields: {
            title: "New order",
            body: "Order 1024 is ready",
            appId: "com.example.orders",
            route: "/app/orders/1024",
          },
        },
      ],
    },
    {
      title: "Rich content",
      description: "Renders a structured card in the Inbox instead of plain text.",
      templates: [
        {
          key: "otp",
          label: "Verification code",
          hint: "Shows a copyable code card, with an optional expiry.",
          fields: {
            title: "Login code",
            body: "Code 482 901, valid for 5 minutes",
            contentType: "otp",
            verificationCode: "482 901",
            copy: "482901",
          },
        },
        {
          key: "markdown",
          label: "Markdown body",
          hint: "Renders formatted content in the message detail.",
          fields: {
            title: "Release notes",
            body: "**Build 98** is live\n\n- Offline packages\n- Native actions",
            contentType: "markdown",
          },
        },
        {
          key: "qr",
          label: "QR code",
          hint: "The host generates the QR image from the payload.",
          fields: {
            title: "Scan to sign in",
            body: "Open your camera and scan this code",
            contentType: "qr",
            qrPayload: "https://drel.app/signin?ticket=abc123",
          },
        },
      ],
    },
  ];

  // A flat lookup so the renderer does not have to walk the groups.
  const TEMPLATES = {};
  TEMPLATE_GROUPS.forEach(function (group) {
    group.templates.forEach(function (template) {
      TEMPLATES[template.key] = template;
    });
  });

  const DISPLAY_OPTIONS = [
    { value: "", label: "Default (normal page)" },
    { value: "full", label: "Fullscreen (immersive)" },
    { value: "sheet", label: "Sheet" },
  ];

  const FIELD_LABELS = {
    title: "Title",
    body: "Body",
    url: "Destination URL",
    appId: "App ID",
    route: "Route",
    contentType: "Content type",
    verificationCode: "Verification code",
    copy: "Copy value",
    badge: "Badge",
    sound: "Sound",
  };

  function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
  }

  function buildPlayground(root) {
    const officialBase = root.dataset.official || "https://api.drel.app";

    const addressHost = el("div", "playground-address");
    const templateHost = el("div", "playground-fields");
    const form = el("div", "playground-form");
    const picker = el("div", "playground-groups");

    let active = "plain";

    // -- The push address, first -----------------------------------------
    // One field covers every destination: the official relay and any
    // self-hosted relay use the same <base>/<key> shape, so pasting the
    // address the user copied out of Drel is always enough.
    const addressField = el("label", "playground-field");
    addressField.appendChild(el("span", "playground-field-label", "Push address"));
    const addressInput = el("input", "playground-input playground-input-lg");
    addressInput.type = "text";
    addressInput.placeholder = "https://api.drel.app/YOUR_KEY";
    addressInput.autocomplete = "off";
    addressInput.spellcheck = false;
    addressField.appendChild(addressInput);
    addressHost.appendChild(addressField);
    addressHost.appendChild(el("p", "playground-hint",
      "Copy it from Drel. The official address starts with " + officialBase +
      "; your own relay starts with its own hostname. The key is the last path segment."));

    // -- Template picker, grouped by intent -------------------------------
    function renderTemplateFields() {
      const template = TEMPLATES[active];
      templateHost.innerHTML = "";
      Object.keys(template.fields).forEach(function (key) {
        const row = el("label", "playground-field");
        row.appendChild(el("span", "playground-field-label", FIELD_LABELS[key] || key));
        const input = el("input", "playground-input");
        input.type = "text";
        input.name = key;
        input.value = template.fields[key];
        row.appendChild(input);
        templateHost.appendChild(row);
      });

      // The display choice is a clickable segmented control, not a <select>.
      const displayRow = el("div", "playground-field");
      displayRow.appendChild(el("span", "playground-field-label", "Presentation"));
      const segment = el("div", "playground-segment");
      DISPLAY_OPTIONS.forEach(function (option) {
        const chip = el("button", "playground-chip", option.label);
        chip.type = "button";
        chip.dataset.value = option.value;
        if (String(template.fields.display || "") === option.value) {
          chip.classList.add("active");
        }
        chip.addEventListener("click", function () {
          segment.querySelectorAll(".playground-chip").forEach(function (node) {
            node.classList.remove("active");
          });
          chip.classList.add("active");
          const target = templateHost.querySelector('[name="display"]');
          if (target) target.value = option.value;
        });
        segment.appendChild(chip);
      });
      displayRow.appendChild(segment);
      templateHost.appendChild(displayRow);

      templateHost.appendChild(el("p", "playground-hint", template.hint));
    }

    TEMPLATE_GROUPS.forEach(function (group) {
      const groupEl = el("div", "playground-group");
      const heading = el("div", "playground-group-head");
      heading.appendChild(el("span", "playground-group-title", group.title));
      heading.appendChild(el("span", "playground-group-desc", group.description));
      groupEl.appendChild(heading);

      const chips = el("div", "playground-group-chips");
      group.templates.forEach(function (template) {
        const chip = el("button", "playground-chip", template.label);
        chip.type = "button";
        chip.dataset.template = template.key;
        chip.title = template.hint;
        if (template.key === active) chip.classList.add("active");
        chip.addEventListener("click", function () {
          active = template.key;
          picker.querySelectorAll(".playground-chip").forEach(function (node) {
            node.classList.remove("active");
          });
          chip.classList.add("active");
          renderTemplateFields();
          updatePreview();
        });
        chips.appendChild(chip);
      });
      groupEl.appendChild(chips);
      picker.appendChild(groupEl);
    });

    // -- Request preview --------------------------------------------------
    const preview = el("pre", "playground-preview");
    const sendButton = el("button", "playground-send", "Send test push");
    sendButton.type = "button";
    const result = el("p", "playground-result");

    /* Resolve the pasted address into a request.
     *
     * The address already names the host, the path and the key, so the
     * request is built from it rather than from the key alone.
     */
    function resolveTarget() {
      const raw = addressInput.value.trim();
      if (!raw) {
        return { error: "Paste the push address from Drel first." };
      }
      let parsed;
      try {
        parsed = new URL(raw);
      } catch (error) {
        return { error: "That is not a valid address." };
      }
      if (parsed.protocol !== "https:" && parsed.protocol !== "http:") {
        return { error: "The address must use http or https." };
      }
      const segments = parsed.pathname.split("/").filter(Boolean);
      if (!segments.length) {
        return { error: "The address is missing a device key." };
      }
      const key = segments[segments.length - 1];
      const base = parsed.origin + "/" + segments.slice(0, -1).join("/");
      return {
        mode: "address",
        key: key,
        base: base.replace(/\/$/, ""),
        url: parsed.origin + parsed.pathname,
      };
    }

    function collectFields() {
      const fields = {};
      templateHost.querySelectorAll(".playground-input").forEach(function (input) {
        if (!input.value) return;
        let value = input.value;
        if (input.name === "badge") {
          const parsed = Number(value);
          value = Number.isNaN(parsed) ? value : parsed;
        }
        fields[input.name] = value;
      });
      return fields;
    }

    function buildUrl(target, fields) {
      const query = [];
      // Every documented field is accepted as a query parameter by both the
      // official relay and the self-hosted Go relay.
      const QUERY_FIELDS = [
        "url", "display", "mode", "appId", "route", "contentType",
        "verificationCode", "copy", "sound", "badge", "group", "threadId",
        "level", "id", "revision", "delete", "expiresAt", "ttl",
        "actionState", "requestId", "qrPayload", "statePath", "markdown",
        "isArchive", "autoCopy", "params",
      ];
      QUERY_FIELDS.forEach(function (name) {
        const value = fields[name];
        if (value === undefined || value === null || value === "") return;
        query.push(name + "=" + encodeURIComponent(value));
      });
      const title = fields.title ? "/" + encodeURIComponent(fields.title) : "";
      const body = fields.body ? "/" + encodeURIComponent(fields.body) : "";
      const suffix = query.length ? "?" + query.join("&") : "";
      return target.base + "/" + target.key + title + body + suffix;
    }

    function updatePreview() {
      const target = resolveTarget();
      if (target.error) {
        preview.textContent = target.error;
        return;
      }
      const url = buildUrl(target, collectFields());
      preview.textContent = "curl '" + url + "'";
    }

    sendButton.addEventListener("click", async function () {
      const target = resolveTarget();
      if (target.error) {
        result.textContent = target.error;
        result.className = "playground-result error";
        return;
      }
      const url = buildUrl(target, collectFields());

      sendButton.disabled = true;
      sendButton.textContent = "Sending…";
      result.textContent = "";
      result.className = "playground-result";
      try {
        const response = await fetch(url, { method: "GET" });
        const text = await response.text();
        result.textContent = "HTTP " + response.status + " — " + text.slice(0, 400);
        result.className = response.ok
          ? "playground-result success"
          : "playground-result error";
      } catch (error) {
        result.textContent = "Request failed: " + error.message;
        result.className = "playground-result error";
        if (/Failed to fetch|NetworkError|Load failed/i.test(error.message || "")) {
          result.textContent +=
            " — the server may have blocked the request because it does not allow " +
            "cross-origin requests from this page. A self-hosted relay needs the " +
            "browser origin added to its CORS allowlist, or use the curl command above.";
        }
      } finally {
        sendButton.disabled = false;
        sendButton.textContent = "Send test push";
        updatePreview();
      }
    });

    addressInput.addEventListener("input", updatePreview);
    templateHost.addEventListener("input", updatePreview);

    root.appendChild(el("h3", "playground-heading", "Try a push"));
    root.appendChild(el("p", "playground-lede",
      "Paste your push address, pick what to send, and try it. The request goes " +
      "from your browser straight to the server in that address."));
    root.appendChild(addressHost);
    root.appendChild(el("h4", "playground-subheading", "What to send"));
    root.appendChild(picker);
    root.appendChild(templateHost);
    root.appendChild(form);
    root.appendChild(el("h4", "playground-subheading", "Request preview"));
    root.appendChild(preview);
    root.appendChild(sendButton);
    root.appendChild(result);

    renderTemplateFields();
    updatePreview();
  }

  function initPlaygrounds() {
    document.querySelectorAll("[data-playground]").forEach(function (root) {
      buildPlayground(root);
    });
  }

  function init() {
    initCopyButtons();
    initPlaygrounds();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
