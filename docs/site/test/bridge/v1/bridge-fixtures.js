(function () {
  "use strict";

  var requests = [];
  var sequence = 0;
  var container = document.getElementById("logContainer");

  function safeValue(value) {
    if (value instanceof Error) {
      return { name: value.name, message: value.message };
    }
    try {
      return JSON.parse(JSON.stringify(value === undefined ? null : value));
    } catch (error) {
      return { serializationError: String(error) };
    }
  }

  function displayValue(value) {
    try {
      return JSON.stringify(safeValue(value), null, 2);
    } catch (error) {
      return String(value);
    }
  }

  function logEntry(record) {
    var item = document.createElement("article");
    item.className = "log-item " + record.state;
    item.dataset.requestId = record.id;

    var head = document.createElement("div");
    head.className = "log-item-head";

    var title = document.createElement("strong");
    title.textContent = "#" + record.id + " " + record.action;

    var state = document.createElement("span");
    state.className = "log-state";
    state.textContent = stateText(record);

    var copy = document.createElement("button");
    copy.type = "button";
    copy.className = "log-copy";
    copy.textContent = "复制 JSON";
    copy.onclick = function () { copyText(displayValue(record)); };

    head.appendChild(title);
    head.appendChild(state);
    head.appendChild(copy);
    item.appendChild(head);
    item.appendChild(field("入参", record.params));
    item.appendChild(field(record.state === "error" ? "错误" : "出参", record.response));
    return item;
  }

  function stateText(record) {
    if (record.state === "success") return "成功 " + record.durationMs + "ms";
    if (record.state === "error") return "失败 " + record.durationMs + "ms";
    if (record.state === "sent") return "已发出 · 待返回";
    return "待发送";
  }

  function field(label, value) {
    var wrapper = document.createElement("div");
    wrapper.className = "log-field";
    var name = document.createElement("span");
    name.textContent = label;
    var pre = document.createElement("pre");
    pre.textContent = displayValue(value);
    wrapper.appendChild(name);
    wrapper.appendChild(pre);
    return wrapper;
  }

  function render(record) {
    if (!container) return;
    var old = container.querySelector('[data-request-id="' + record.id + '"]');
    var entry = logEntry(record);
    if (old) {
      container.replaceChild(entry, old);
    } else {
      container.insertBefore(entry, container.firstChild);
    }
    while (container.children.length > 100) {
      container.removeChild(container.lastChild);
    }
  }

  function newRequest(action, params, transport) {
    sequence += 1;
    var record = {
      id: sequence,
      action: action,
      params: safeValue(params || {}),
      transport: transport,
      state: "pending",
      startedAt: new Date().toISOString()
    };
    requests.push(record);
    render(record);
    return record;
  }

  function complete(record, state, response) {
    record.finishedAt = new Date().toISOString();
    record.durationMs = Date.now() - Date.parse(record.startedAt);
    record.state = state;
    record.response = safeValue(response);
    render(record);
  }

  function firstPending(action) {
    for (var i = requests.length - 1; i >= 0; i -= 1) {
      if (requests[i].state === "sent" && (!action || requests[i].action === action)) {
        return requests[i];
      }
    }
    return null;
  }

  function checkBridge() {
    var webkitBridge = window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.BarkBridge;
    var jsBridge = window.BarkBridge && typeof window.BarkBridge.callNative === "function"
      ? window.BarkBridge.callNative
      : null;
    var status = document.getElementById("statusBar");
    if (status) {
      status.className = "status-bar " + (webkitBridge || jsBridge ? "ok" : "error");
      status.textContent = webkitBridge ? "✅ JS Bridge 可用" : jsBridge ? "✅ BarkBridge 可用" : "❌ JS Bridge 不可用";
    }
    return { webkitBridge: webkitBridge, jsBridge: jsBridge };
  }

  window.callNative = function (action, params) {
    var bridges = checkBridge();
    if (!bridges.webkitBridge && !bridges.jsBridge) {
      var unavailable = newRequest(action, params, "none");
      complete(unavailable, "error", { message: "Bridge 不可用" });
      return;
    }

    if (bridges.webkitBridge) {
      var sent = newRequest(action, params, "webkit.messageHandlers");
      sent.state = "sent";
      render(sent);
      try {
        bridges.webkitBridge.postMessage({ action: action, params: params || {} });
      } catch (error) {
        complete(sent, "error", error);
      }
      return;
    }

    var promiseRequest = newRequest(action, params, "BarkBridge.callNative");
    promiseRequest.state = "sent";
    render(promiseRequest);
    try {
      Promise.resolve(bridges.jsBridge(action, params || {})).then(function (result) {
        complete(promiseRequest, "success", result);
      }).catch(function (error) {
        complete(promiseRequest, "error", error);
      });
    } catch (error) {
      complete(promiseRequest, "error", error);
    }
  };

  window.BarkBridge = window.BarkBridge || {};
  window.BarkBridge.receiveResult = function (result) {
    var payload = safeValue(result);
    var record = firstPending(payload && payload.action) || firstPending();
    if (!record) {
      record = newRequest("native callback", payload, "BarkBridge.receiveResult");
      record.state = "sent";
    }
    if (!payload || payload.success === false) {
      complete(record, "error", payload && (payload.error || payload));
    } else {
      complete(record, "success", payload && "data" in payload ? payload.data : payload);
    }
  };

  function copyText(text) {
    if (navigator.clipboard && window.isSecureContext) {
      return navigator.clipboard.writeText(text).catch(function () {
        legacyCopy(text);
      });
    }
    return legacyCopy(text);
  }

  function legacyCopy(text) {
    var input = document.createElement("textarea");
    input.value = text;
    input.setAttribute("readonly", "");
    input.className = "copy-helper";
    document.body.appendChild(input);
    input.select();
    document.execCommand("copy");
    document.body.removeChild(input);
  }

  function toolbar() {
    if (!container) return;
    var parent = container.parentNode;
    var bar = document.createElement("div");
    bar.className = "log-toolbar";

    var copyAll = document.createElement("button");
    copyAll.type = "button";
    copyAll.textContent = "复制全部 JSON";
    copyAll.onclick = function () { copyText(displayValue(requests)); };

    var clear = document.createElement("button");
    clear.type = "button";
    clear.textContent = "清空日志";
    clear.onclick = function () {
      requests.length = 0;
      container.textContent = "";
    };

    bar.appendChild(copyAll);
    bar.appendChild(clear);
    parent.insertBefore(bar, container);
  }

  window.DrelFixtureDebug = {
    requests: requests,
    copyAll: function () { return copyText(displayValue(requests)); },
    checkBridge: checkBridge
  };

  toolbar();
  setTimeout(checkBridge, 100);
})();
