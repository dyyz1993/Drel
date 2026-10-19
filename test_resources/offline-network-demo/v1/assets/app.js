(() => {
  const cacheKey = "drel.offline-network-demo.v1.snapshot";
  const ipURL = "https://api64.ipify.org?format=json";
  const weatherURL = "https://api.open-meteo.com/v1/forecast?latitude=22.5431&longitude=114.0579&current=temperature_2m,apparent_temperature,weather_code&timezone=Asia%2FShanghai";
  const elements = {
    button: document.getElementById("refresh"),
    dot: document.getElementById("network-dot"),
    network: document.getElementById("network-state"),
    runtime: document.getElementById("runtime-state"),
    ip: document.getElementById("ip-value"),
    ipSource: document.getElementById("ip-source"),
    weather: document.getElementById("weather-value"),
    weatherSource: document.getElementById("weather-source"),
    updatedAt: document.getElementById("updated-at")
  };

  const weatherLabel = code => ({ 0: "晴", 1: "大致晴", 2: "多云", 3: "阴", 45: "雾", 48: "雾凇", 51: "毛毛雨", 61: "小雨", 63: "中雨", 65: "大雨", 80: "阵雨", 95: "雷暴" }[code] || `天气代码 ${code}`);
  const when = iso => new Intl.DateTimeFormat("zh-CN", { dateStyle: "medium", timeStyle: "medium" }).format(new Date(iso));

  function setNetworkState() {
    const online = navigator.onLine;
    elements.dot.className = `dot ${online ? "online" : "offline"}`;
    elements.network.textContent = online ? "网络可用：可获取实时数据" : "当前离线：只使用本地包与缓存结果";
  }

  function render(snapshot, source) {
    if (!snapshot) {
      elements.ip.textContent = "—";
      elements.weather.textContent = "—";
      elements.ipSource.textContent = "离线且尚无缓存";
      elements.weatherSource.textContent = "离线且尚无缓存";
      elements.updatedAt.textContent = "尚未取得数据";
      return;
    }
    elements.ip.textContent = snapshot.ip || "—";
    elements.weather.textContent = snapshot.temperature == null ? "—" : `${Math.round(snapshot.temperature)}°`;
    const sourceLabel = source === "live" ? "实时网络数据" : "WebView 最近缓存";
    elements.ipSource.textContent = sourceLabel;
    elements.weatherSource.textContent = `${weatherLabel(snapshot.weatherCode)} · ${sourceLabel}`;
    elements.updatedAt.textContent = `${sourceLabel} · ${when(snapshot.updatedAt)}`;
  }

  function readCache() {
    try { return JSON.parse(localStorage.getItem(cacheKey) || "null"); } catch { return null; }
  }

  function saveCache(snapshot) {
    try { localStorage.setItem(cacheKey, JSON.stringify(snapshot)); } catch { /* Cache is optional, never block the app. */ }
  }

  async function refresh() {
    setNetworkState();
    elements.button.disabled = true;
    elements.button.textContent = "正在获取…";
    try {
      const [ipResponse, weatherResponse] = await Promise.all([
        fetch(ipURL, { cache: "no-store" }),
        fetch(weatherURL, { cache: "no-store" })
      ]);
      if (!ipResponse.ok || !weatherResponse.ok) throw new Error("接口响应失败");
      const [ip, weather] = await Promise.all([ipResponse.json(), weatherResponse.json()]);
      const snapshot = {
        ip: ip.ip,
        temperature: weather.current?.temperature_2m,
        weatherCode: weather.current?.weather_code,
        updatedAt: new Date().toISOString()
      };
      render(snapshot, "live");
      saveCache(snapshot);
    } catch {
      const cached = readCache();
      render(cached, "cache");
      elements.updatedAt.textContent = cached ? `网络请求失败，展示缓存 · ${when(cached.updatedAt)}` : "网络请求失败：请恢复网络后再试";
    } finally {
      elements.button.disabled = false;
      elements.button.textContent = "刷新实时数据";
    }
  }

  const runtime = window.DrelRuntime;
  elements.runtime.textContent = runtime?.isOfflinePackage
    ? `已从 Drel 离线包启动 · 包版本 ${runtime.offlinePackageVersion || "未知"}`
    : "当前为在线网页预览；安装离线包后会从本地资源启动";
  elements.button.addEventListener("click", refresh);
  window.addEventListener("online", () => { setNetworkState(); refresh(); });
  window.addEventListener("offline", () => { setNetworkState(); render(readCache(), "cache"); });
  setNetworkState();
  const cached = readCache();
  if (cached) render(cached, "cache");
  if (navigator.onLine) refresh();
})();
