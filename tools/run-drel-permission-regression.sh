#!/usr/bin/env bash
# Drel 权限三档 / PWA 能力回归 + 可视化证据门（2026-10-22 沉淀）
#
# 一键跑完「服务 → 模拟器 → 构建 → 跑权限/能力 UI 测试 → 全程录像 → 生成
# 可视化证据」：
#   1. 本地服务（8080/8081/8083）+ 模拟器定位预设与系统权限预授
#   2. build-for-testing + test-without-building（PWAPermissionFlowTests +
#      PWAPermissionTests，即三档授权面板、允许一次重复弹窗、始终允许快路径、
#      权限中心列表/撤销/空状态、半屏主屏幕引导弹窗、面板快捷入口）
#   3. 全程 simctl 录屏 → 抽取关键帧/合成动画 → **自动删除 MP4**
#      （录屏仅用于抽帧；成品只保留关键帧 PNG 与 WebP 动画，体积 ~MB 级。
#       需要保留 MP4 时传 WBK_KEEP_VIDEO=1）
#   4. 从 MP4 抽取关键帧 + 用例截图 → 动画 WebP（gif 兜底）
#   5. 崩溃扫描；产物全部落在 tools/../build/reports/drel-permission-regression/
#
# 用法：
#   bash tools/run-drel-permission-regression.sh                 # 完整跑
#   WBK_SKIP_BUILD=1 bash tools/run-drel-permission-regression.sh # 复用已构建产物
#   WBK_SKIP_VIDEO=1 bash tools/run-drel-permission-regression.sh # 不录屏（快）
#   bash tools/run-drel-permission-regression.sh --analyze-only  # 只用已有产物合成
set -uo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

UDID="${WBK_REG_SIM:-6EDF218F-03A2-47BB-9515-068EA8C7475D}"
SIM_NAME="${WBK_REG_SIM_NAME:-Drel-Flow-Verify}"
DD="${WBK_REG_DD:-/tmp/wbk-dd-perm-reg}"
WORK="/tmp/wbk-perm-reg"
OUT="$ROOT/build/reports/drel-permission-regression"
XCRESULT="$WORK/DrelPermissionRegression.xcresult"
VIDEO="$OUT/drel-permission-regression.mp4"
ANALYZE_ONLY=0
SKIP_BUILD="${WBK_SKIP_BUILD:-0}"
SKIP_VIDEO="${WBK_SKIP_VIDEO:-0}"
[[ "${1:-}" == "--analyze-only" ]] && ANALYZE_ONLY=1

# 测试列表：这是「新功能回归」的权威集合，新增授权/能力相关 UI 测试必须加进来。
TESTS=(
  "DrelUITests/PWAPermissionFlowTests/test01PhoneShortcutEntryOpensGuidePopup"
  "DrelUITests/PWAPermissionFlowTests/test02OnceScopeRepromptsAndCenterStaysEmpty"
  "DrelUITests/PWAPermissionFlowTests/test03AlwaysScopeFastPathAndCenterRevoke"
  "DrelUITests/PWAPermissionFlowTests/test04PromptEntryOpensFullscreenPermissionCenter"
  "DrelUITests/PWAPermissionFlowTests/test05AlwaysGrantSurvivesAppRelaunch"
  "DrelUITests/ClipboardReopenTests"
  "DrelUITests/PWAPermissionTests"
)
ONLY_TESTING=()
for t in "${TESTS[@]}"; do ONLY_TESTING+=("-only-testing:$t"); done

PASS=0; FAIL=0

say()  { printf '\n\033[0;34m== %s ==\033[0m\n' "$*"; }
ok()   { printf '\033[0;32m[OK]\033[0m %s\n' "$*"; }
bad()  { printf '\033[0;31m[FAIL]\033[0m %s\n' "$*"; }

mkdir -p "$OUT" "$WORK"

if [[ $ANALYZE_ONLY -eq 0 ]]; then
  # ── 1. 服务 ────────────────────────────────────────────────────────────────
  say "本地服务"
  bash scripts/services.sh start >/dev/null 2>&1 || true
  bash scripts/services.sh verify >/dev/null 2>&1 && ok "三个服务就绪" || bad "服务未就绪（8080/8081/8083）"

  # ── 2. 模拟器 ──────────────────────────────────────────────────────────────
  say "模拟器 $SIM_NAME ($UDID)"
  xcrun simctl boot "$UDID" >/dev/null 2>&1 || true
  xcrun simctl bootstatus "$UDID" -b >/dev/null 2>&1
  xcrun simctl location "$UDID" set 31.2304,121.4737
  xcrun simctl privacy "$UDID" grant location com.webbridgekit.superapp
  ok "已启动，定位预设 31.2304,121.4737，定位权限已预授"

  # ── 3. 构建 ────────────────────────────────────────────────────────────────
  if [[ $SKIP_BUILD == "1" ]]; then
    ok "跳过构建（WBK_SKIP_BUILD=1）"
  else
    say "构建测试产物"
    if xcodebuild build-for-testing -workspace Drel.xcworkspace -scheme Drel \
        -derivedDataPath "$DD" -destination "platform=iOS Simulator,id=$UDID" \
        2>&1 | grep -qE "\*\* TEST BUILD (SUCCEEDED|FAILED) \*\*"; then
      ok "TEST BUILD SUCCEEDED"
    else
      bad "构建失败，退出"; exit 1
    fi
  fi

  # ── 4. 跑测试 + 全程录屏 ───────────────────────────────────────────────────
  say "跑权限/能力回归并录屏"
  rm -rf "$XCRESULT"
  if [[ $SKIP_VIDEO != "1" ]]; then
    rm -f "$VIDEO"
    xcrun simctl io "$UDID" recordVideo --force "$VIDEO" >"$WORK/record.log" 2>&1 &
    REC_PID=$!
    sleep 2
  fi

  xcodebuild test-without-building -workspace Drel.xcworkspace -scheme Drel \
    -derivedDataPath "$DD" -destination "platform=iOS Simulator,id=$UDID" \
    "${ONLY_TESTING[@]}" -resultBundlePath "$XCRESULT" >"$WORK/test-output.log" 2>&1
  TEST_RC=$?

  if [[ $SKIP_VIDEO != "1" ]]; then
    kill -INT "$REC_PID" 2>/dev/null
    sleep 3
  fi

  grep -E "Test Case.*(passed|failed)" "$WORK/test-output.log" | sed 's/^ *//' | tee "$OUT/test-cases.txt"
  PASS=$(grep -cE "Test Case.*passed" "$WORK/test-output.log")
  FAIL=$(grep -cE "Test Case.*failed" "$WORK/test-output.log")

  if [[ $TEST_RC -eq 0 ]]; then ok "回归通过：$PASS passed, 0 failed"
  else bad "回归失败：$PASS passed, $FAIL failed（详见 $OUT/test-cases.txt）"; fi

  # ── 5. 崩溃扫描 ────────────────────────────────────────────────────────────
  say "崩溃扫描"
  CRASH=$(bash scripts/scan-crash-logs.sh --json 2>/dev/null | python3 -c "import json,sys; print(json.load(sys.stdin).get('total',0))" 2>/dev/null || echo "?")
  if [[ "$CRASH" == "0" ]]; then ok "崩溃 0"; else bad "崩溃 $CRASH 条"; fi
fi

# ── 6. 可视化证据：截图 + 关键帧 + 动画 WebP ──────────────────────────────────
say "生成可视化证据"
python3 - "$OUT" "$XCRESULT" "$VIDEO" <<'PYEOF'
import json, os, shutil, subprocess, sys

OUT, XCRESULT, VIDEO = sys.argv[1], sys.argv[2], sys.argv[3]
SHOTS = os.path.join(OUT, "screenshots")
FRAMES = os.path.join(OUT, "frames")
os.makedirs(SHOTS, exist_ok=True)
os.makedirs(FRAMES, exist_ok=True)

def run(cmd, **kw):
    return subprocess.run(cmd, capture_output=True, text=True, **kw)

# 6.1 从 xcresult 导出每用例截图（含测试失败时自动抓的现场）
if os.path.isdir(XCRESULT):
    tmp = os.path.join(OUT, ".attachments")
    shutil.rmtree(tmp, ignore_errors=True)
    os.makedirs(tmp, exist_ok=True)
    run(["xcrun", "xcresulttool", "export", "attachments", "--path", XCRESULT,
         "--output-path", tmp])
    manifest = os.path.join(tmp, "manifest.json")
    count = 0
    if os.path.exists(manifest):
        for node in json.load(open(manifest)):
            test = node.get("testIdentifier", "unknown")
            short = test.rsplit("/", 1)[-1].split("(")[0] or test
            for a in node.get("attachments", []):
                name = (a.get("suggestedHumanReadableName") or "").strip()
                fn = a.get("exportedFileName", "")
                if not fn.endswith(".png"):
                    continue
                label = name.split("_")[0] if name else "screenshot"
                dest = os.path.join(SHOTS, f"{short}_{label}.png")
                src = os.path.join(tmp, fn)
                if os.path.exists(src):
                    shutil.copy(src, dest)
                    count += 1
    shutil.rmtree(tmp, ignore_errors=True)
    print(f"  screenshots: {count} 张 -> {SHOTS}")

# 6.2 从 MP4 抽关键帧（首帧/中段/尾帧）——录像无法播放时的静态取证
if os.path.exists(VIDEO) and os.path.getsize(VIDEO) > 0:
    dur = run(["ffprobe", "-v", "error", "-show_entries", "format=duration",
               "-of", "default=nw=1:nk=1", VIDEO]).stdout.strip()
    try:
        total = float(dur)
    except ValueError:
        total = 0.0
    if total > 0:
        for pct, tag in ((0.02, "start"), (0.5, "middle"), (0.98, "end")):
            run(["ffmpeg", "-y", "-v", "error", "-ss", f"{total*pct:.2f}",
                 "-i", VIDEO, "-frames:v", "1",
                 os.path.join(FRAMES, f"video-{tag}.png")])
        print(f"  video frames: 3 张（时长 {total:.1f}s）-> {FRAMES}")
else:
    print("  video: 未生成（WBK_SKIP_VIDEO=1 或录制失败）")

# 6.3 每用例截图序列 → 动画 WebP（Pillow 写 WebP，gif 兜底）
def make_anim(files, out_webp, out_gif, fps=2):
    if len(files) < 2:
        return False
    frames = []
    from PIL import Image
    for f in files:
        im = Image.open(f).convert("RGB")
        im.thumbnail((360, 360 * 2))
        frames.append(im)
    duration = int(1000 / fps)
    ok_webp = True
    try:
        frames[0].save(out_webp, save_all=True, append_images=frames[1:],
                       duration=duration, loop=0, method=6)
    except Exception:
        ok_webp = False
    try:
        frames[0].save(out_gif, save_all=True, append_images=frames[1:],
                       duration=duration, loop=0)
    except Exception:
        pass
    return ok_webp

made = 0
groups = {}
for fn in sorted(os.listdir(SHOTS)):
    if not fn.endswith(".png"):
        continue
    groups.setdefault(fn.split("_")[0], []).append(os.path.join(SHOTS, fn))
for test, files in groups.items():
    if len(files) < 2:
        continue
    webp = os.path.join(OUT, "animations", f"{test}.webp")
    gif = os.path.join(OUT, "animations", f"{test}.gif")
    os.makedirs(os.path.dirname(webp), exist_ok=True)
    if make_anim(files, webp, gif):
        made += 1
        print(f"  animation: {os.path.basename(webp)}（{len(files)} 帧）")

# 6.4 视频本身也转一个动画 WebP（改动的关键帧串）；抽帧完成后删除 MP4
# ——录屏只是抽帧的中间产物，成品只留关键帧/动画（2026-10-22 用户决策：
#   全程 MP4 上百 MB 无保留价值；需要时传 WBK_KEEP_VIDEO=1）
if os.path.exists(VIDEO) and os.path.getsize(VIDEO) > 0:
    seqdir = os.path.join(OUT, "frames", "seq")
    os.makedirs(seqdir, exist_ok=True)
    run(["ffmpeg", "-y", "-v", "error", "-i", VIDEO, "-vf", "fps=1,scale=320:-1",
         os.path.join(seqdir, "f_%04d.png")])
    seq = [os.path.join(seqdir, f) for f in sorted(os.listdir(seqdir)) if f.endswith(".png")]
    if len(seq) >= 2:
        from PIL import Image
        frames = [Image.open(f).convert("RGB") for f in seq]
        os.makedirs(os.path.join(OUT, "animations"), exist_ok=True)
        frames[0].save(os.path.join(OUT, "animations", "full-run.webp"),
                       save_all=True, append_images=frames[1:],
                       duration=400, loop=0, method=6)
        print(f"  animation: full-run.webp（{len(frames)} 帧，1fps 抽样）")
    if os.environ.get("WBK_KEEP_VIDEO") != "1":
        size_mb = os.path.getsize(VIDEO) / 1024 / 1024
        os.remove(VIDEO)
        print(f"  video: MP4 已在抽帧后删除（{size_mb:.0f}MB；保留请传 WBK_KEEP_VIDEO=1）")

print(f"  animations: {made} 个用例动画 -> {OUT}/animations")
PYEOF

# ── 7. 汇总报告 ──────────────────────────────────────────────────────────────
say "产物清单"
{
  echo "# Drel 权限/能力回归（$(date '+%Y-%m-%d %H:%M')）"
  echo
  echo "- 模拟器：${SIM_NAME:-（未运行）}（${UDID:-?}）"
  echo "- 结果：**${PASS:-0} passed / ${FAIL:-0} failed**"
  echo "- 崩溃：${CRASH:-未扫描}"
  echo
  echo "## 用例"
  echo '```'
  cat "$OUT/test-cases.txt" 2>/dev/null || echo "（--analyze-only 模式：无本轮记录）"
  echo '```'
  echo "## 可视化证据"
  echo "- \`animations/<用例名>.webp\`：每用例截图序列动画"
  echo "- \`animations/full-run.webp\`：全程 1fps 抽样动画"
  echo "- \`screenshots/\`：全部原始截图"
  echo "- \`frames/\`：视频关键帧（首/中/尾）"
  echo "- MP4 录屏默认抽帧后删除（保留传 WBK_KEEP_VIDEO=1）"
} > "$OUT/REPORT.md"
ok "报告：$OUT/REPORT.md"

[[ $FAIL -eq 0 && $ANALYZE_ONLY -eq 0 ]] && exit 0 || { [[ $FAIL -gt 0 ]] && exit 1; exit 0; }
