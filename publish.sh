#!/usr/bin/env bash
#
# html-share / pub —— 把 md / html 一键发布成公开链接（Cloudflare R2）
#
# 用法:
#   pub 报告.md                  # md 自动转成好看的独立网页再发布
#   pub page.html                # html 原样发布
#   pub 站点目录/                 # 整个文件夹发布（保留相对路径，需含 index.html，返回 index 链接）
#   pub 报告.md --slug q3-report  # 自定义链接里的可读名字
#   pub 报告.md --title "Q3 财报"  # 覆盖 md 转 html 的页面标题
#
# 发布后链接自动复制到剪贴板，直接粘进微信/飞书即可。
# md 用 pandoc --embed-resources 转成全内联、自包含的 html，不依赖任何外部 CDN，
# 这样微信内置浏览器也能完整渲染。
#
# 配置由 install.sh 写入 ~/.html-share.env（也可用环境变量 BUCKET / PUBLIC_PREFIX 覆盖）。
#
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---- 读配置 ----
CONF="${HTMLSHARE_CONFIG:-$HOME/.html-share.env}"
# shellcheck disable=SC1090
[[ -f "$CONF" ]] && source "$CONF"
: "${BUCKET:=}"; : "${PUBLIC_PREFIX:=}"

if [[ -z "$BUCKET" || -z "$PUBLIC_PREFIX" ]]; then
  cat >&2 <<EOF
⚠️  还没配置好。两种办法二选一：

  1) 跑一遍安装脚本（推荐）：
       "$SCRIPT_DIR/install.sh"

  2) 手动创建 ${CONF}，写入两行：
       BUCKET="你的桶名"
       PUBLIC_PREFIX="https://pub-xxxxxxxx.r2.dev"
EOF
  exit 1
fi

# ---- 复制到剪贴板（自动适配 Mac / Windows(Git Bash) / Linux）----
clip_copy() {
  if   command -v pbcopy  >/dev/null; then printf '%s' "$1" | pbcopy
  elif command -v clip    >/dev/null; then printf '%s' "$1" | clip
  elif command -v xclip   >/dev/null; then printf '%s' "$1" | xclip -selection clipboard
  elif command -v wl-copy >/dev/null; then printf '%s' "$1" | wl-copy
  else return 1; fi
}

# ---- 解析参数 ----
FILE=""; SLUG=""; TITLE=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --slug)  SLUG="${2:-}"; shift 2 ;;
    --title) TITLE="${2:-}"; shift 2 ;;
    -h|--help) sed -n '5,13p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "未知参数: $1" >&2; exit 1 ;;
    *) FILE="$1"; shift ;;
  esac
done

[[ -z "$FILE" ]] && { echo "用法: pub 文件.md/.html 或 目录/ [--slug 名字] [--title 标题]"; exit 1; }
[[ -e "$FILE" ]] || { echo "路径不存在: $FILE" >&2; exit 1; }
command -v wrangler >/dev/null || { echo "没装 wrangler，先跑 install.sh，或：npm install -g wrangler" >&2; exit 1; }

# ===== 文件夹发布模式：传入目录则保留相对路径整目录上传，返回 index.html 链接 =====
if [[ -d "$FILE" ]]; then
  DIR="${FILE%/}"
  [[ -f "$DIR/index.html" ]] || { echo "❌ 文件夹里没有 index.html，无法作为入口" >&2; exit 1; }
  slug="$(echo "${SLUG:-$(basename "$DIR")}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
  [[ -z "$slug" ]] && slug="site"
  rand="$(openssl rand -hex 3 2>/dev/null || printf '%06x' $((RANDOM*RANDOM)))"
  folder="${slug}-${rand}"

  echo "文件夹发布：$DIR → ${BUCKET}/${folder}/ ..."
  cnt=0; failed=0
  while IFS= read -r -d '' f; do
    rel="${f#"$DIR"/}"
    fext="$(echo "${f##*.}" | tr 'A-Z' 'a-z')"
    case "$fext" in
      html|htm) ct="text/html; charset=utf-8" ;;
      css)      ct="text/css; charset=utf-8" ;;
      js|mjs)   ct="application/javascript; charset=utf-8" ;;
      json)     ct="application/json; charset=utf-8" ;;
      svg)      ct="image/svg+xml" ;;
      png)      ct="image/png" ;;
      jpg|jpeg) ct="image/jpeg" ;;
      gif)      ct="image/gif" ;;
      webp)     ct="image/webp" ;;
      ico)      ct="image/x-icon" ;;
      woff2)    ct="font/woff2" ;;
      woff)     ct="font/woff" ;;
      ttf)      ct="font/ttf" ;;
      txt|md)   ct="text/plain; charset=utf-8" ;;
      *)        ct="application/octet-stream" ;;
    esac
    if wrangler r2 object put "${BUCKET}/${folder}/${rel}" --file "$f" \
         --content-type "$ct" --cache-control "public, max-age=3600" --remote >/dev/null 2>&1; then
      printf '  ✓ %s  [%s]\n' "$rel" "$ct"; cnt=$((cnt+1))
    else
      printf '  ✗ %s 上传失败\n' "$rel" >&2; failed=$((failed+1))
    fi
  done < <(find "$DIR" -type f ! -name '.DS_Store' -print0)

  [[ $failed -gt 0 ]] && { echo "❌ 有 $failed 个文件上传失败，请重试" >&2; exit 1; }
  url="${PUBLIC_PREFIX%/}/${folder}/index.html"
  clip_copy "$url" && copied="（已复制到剪贴板）" || copied="（手动复制下面这条）"
  echo ""
  echo "✅ 文件夹发布成功，共 $cnt 个文件 ${copied}"
  echo "   $url"
  exit 0
fi

[[ -f "$FILE" ]] || { echo "文件不存在: $FILE" >&2; exit 1; }

ext="$(echo "${FILE##*.}" | tr 'A-Z' 'a-z')"
base="$(basename "$FILE")"; base="${base%.*}"

# ---- 准备要上传的 html ----
TMP_HTML=""
cleanup() { [[ -n "$TMP_HTML" && -f "$TMP_HTML" ]] && rm -f "$TMP_HTML"; }
trap cleanup EXIT

case "$ext" in
  md|markdown)
    command -v pandoc >/dev/null || { echo "没装 pandoc，无法转换 md（install.sh 会装上）" >&2; exit 1; }
    [[ -z "$TITLE" ]] && TITLE="$base"
    TMP_HTML="$(mktemp).html"
    pandoc "$FILE" \
      --standalone --embed-resources \
      --metadata title="$TITLE" \
      --css "$SCRIPT_DIR/style.css" \
      --syntax-highlighting=tango \
      -f markdown+smart-yaml_metadata_block \
      -o "$TMP_HTML"
    UPLOAD="$TMP_HTML"
    echo "已转换 md → html（标题：${TITLE}）"
    ;;
  html|htm)
    UPLOAD="$FILE"
    ;;
  *)
    echo "不支持的类型: .${ext}（只支持 .md / .html）" >&2; exit 1 ;;
esac

# ---- 生成链接名：可读 slug + 随机短码，避免覆盖、旧链接长期有效 ----
slug="$(echo "${SLUG:-$base}" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9]+/-/g; s/^-+//; s/-+$//')"
[[ -z "$slug" ]] && slug="doc"   # 纯中文文件名时退化为 doc
rand="$(openssl rand -hex 3 2>/dev/null || printf '%06x' $((RANDOM*RANDOM)))"
key="${slug}-${rand}.html"

# ---- 上传到 R2 ----
echo "上传到 R2: ${BUCKET}/${key} ..."
if ! wrangler r2 object put "${BUCKET}/${key}" \
      --file "$UPLOAD" \
      --content-type "text/html; charset=utf-8" \
      --cache-control "public, max-age=3600" \
      --remote >/dev/null 2>&1; then
  echo "❌ 上传失败。常见原因：wrangler 没登录，或桶名写错。单独跑一次看报错：" >&2
  echo "   wrangler r2 object put ${BUCKET}/${key} --file \"$UPLOAD\" --remote" >&2
  exit 1
fi

url="${PUBLIC_PREFIX%/}/${key}"

# ---- 复制到剪贴板 ----
clip_copy "$url" && copied="（已复制到剪贴板）" || copied="（手动复制下面这条）"

echo ""
echo "✅ 发布成功 ${copied}"
echo "   $url"
