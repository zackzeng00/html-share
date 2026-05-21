#!/usr/bin/env bash
#
# html-share 一键安装
#
#   一条命令（联网自举）：
#     curl -fsSL https://raw.githubusercontent.com/zackzeng00/html-share/main/install.sh | bash
#
#   或先 clone 再本地跑：
#     git clone https://github.com/zackzeng00/html-share && cd html-share && ./install.sh
#
# 它会：装好 node + pandoc + wrangler → 登录 Cloudflare → 建桶并开公开访问
#       → 写配置 ~/.html-share.env → 设 `pub` 快捷命令。
# 之后任何地方： pub 文件.md  即可。
#
set -euo pipefail

REPO_URL="https://github.com/zackzeng00/html-share"
say()  { printf '\033[36m▸ %s\033[0m\n' "$*"; }
ok()   { printf '\033[32m✓ %s\033[0m\n' "$*"; }
warn() { printf '\033[33m! %s\033[0m\n' "$*"; }
die()  { printf '\033[31m✗ %s\033[0m\n' "$*" >&2; exit 1; }
ask()  { local p="$1" d="${2:-}" a; printf '\033[35m? %s\033[0m' "$p" >&2; read -r a </dev/tty || true; echo "${a:-$d}"; }

# ---- 0. 识别系统 ----
OS="unknown"
case "$(uname -s)" in
  Darwin*)            OS="mac" ;;
  MINGW*|MSYS*|CYGWIN*) OS="win" ;;
  Linux*)             OS="linux" ;;
esac
say "系统识别为：$OS"
[[ "$OS" == "unknown" ]] && die "认不出系统。Windows 请在 Git Bash 里运行本脚本。"

# ---- 1. 定位 / 自举仓库 ----
SELF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-$0}")" 2>/dev/null && pwd || echo "")"
if [[ -n "$SELF_DIR" && -f "$SELF_DIR/publish.sh" ]]; then
  REPO_DIR="$SELF_DIR"
  say "在仓库目录内运行：$REPO_DIR"
else
  REPO_DIR="$HOME/.html-share"
  if [[ -f "$REPO_DIR/publish.sh" ]]; then
    say "更新已有副本：$REPO_DIR"; git -C "$REPO_DIR" pull --ff-only >/dev/null 2>&1 || true
  else
    command -v git >/dev/null || die "需要 git。Mac: xcode-select --install；Windows: 装 Git for Windows。"
    say "下载工具到 $REPO_DIR ..."
    git clone --depth 1 "$REPO_URL" "$REPO_DIR" >/dev/null 2>&1 || die "git clone 失败，检查网络。"
  fi
fi
chmod +x "$REPO_DIR/publish.sh" 2>/dev/null || true

# ---- 2. 装依赖：node + pandoc ----
need_node=0;   command -v node    >/dev/null || need_node=1
need_pandoc=0; command -v pandoc  >/dev/null || need_pandoc=1

if [[ $need_node -eq 1 || $need_pandoc -eq 1 ]]; then
  say "安装缺失的依赖（node / pandoc）..."
  case "$OS" in
    mac)
      if ! command -v brew >/dev/null; then
        say "先装 Homebrew（Mac 软件管家，过程可能要输开机密码）..."
        NONINTERACTIVE=1 /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)" || die "Homebrew 安装失败"
        # 让当前进程能用到 brew
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
      fi
      pkgs=(); [[ $need_node -eq 1 ]] && pkgs+=(node); [[ $need_pandoc -eq 1 ]] && pkgs+=(pandoc)
      brew install "${pkgs[@]}" || die "brew install 失败"
      ;;
    win)
      command -v winget >/dev/null || die "找不到 winget。请到 nodejs.org / pandoc.org 手动安装 node 和 pandoc 后重跑。"
      [[ $need_node   -eq 1 ]] && winget install -e --id OpenJS.NodeJS.LTS --silent --accept-source-agreements --accept-package-agreements || true
      [[ $need_pandoc -eq 1 ]] && winget install -e --id JohnMacFarlane.Pandoc --silent --accept-source-agreements --accept-package-agreements || true
      warn "若下面提示找不到 node/pandoc，请关掉 Git Bash 重开一次再跑本脚本（让它读到新装的软件）。"
      ;;
    linux)
      if command -v apt-get >/dev/null; then
        sudo apt-get update -y && sudo apt-get install -y nodejs npm pandoc || die "apt 安装失败"
      elif command -v dnf >/dev/null; then
        sudo dnf install -y nodejs pandoc || die "dnf 安装失败"
      else
        die "请用你的包管理器装 node 和 pandoc 后重跑。"
      fi
      ;;
  esac
fi
command -v node   >/dev/null && ok "node：$(node -v)"     || die "node 仍不可用，重开终端再试"
command -v pandoc >/dev/null && ok "pandoc：$(pandoc --version | head -1)" || die "pandoc 仍不可用，重开终端再试"

# ---- 3. 装 wrangler ----
if ! command -v wrangler >/dev/null; then
  say "安装 wrangler（Cloudflare 命令行工具）..."
  npm install -g wrangler >/dev/null 2>&1 || die "wrangler 安装失败（Mac 报权限可试 sudo npm install -g wrangler）"
fi
ok "wrangler：$(wrangler --version 2>/dev/null | head -1)"

# ---- 4. 登录 Cloudflare ----
if ! wrangler whoami >/dev/null 2>&1; then
  say "登录 Cloudflare（会弹出浏览器，点 Allow 授权，完成后回到这里）..."
  warn "还没有 Cloudflare 账号？先去 https://dash.cloudflare.com/sign-up 免费注册，并在左侧开通 R2（首次需绑卡验证，免费额度内不扣费）。"
  wrangler login || die "登录失败，重跑本脚本再试"
fi
ok "已登录：$(wrangler whoami 2>/dev/null | grep -ioE '[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+' | head -1 || echo Cloudflare)"

# ---- 5. 建桶 + 开公开访问 ----
DEFAULT_BUCKET="my-share"
BUCKET="$(ask "给你的桶起个名（只用小写字母/数字/连字符）[默认 $DEFAULT_BUCKET]: " "$DEFAULT_BUCKET")"
BUCKET="$(echo "$BUCKET" | tr 'A-Z' 'a-z' | sed -E 's/[^a-z0-9-]+/-/g; s/^-+//; s/-+$//')"
[[ -z "$BUCKET" ]] && BUCKET="$DEFAULT_BUCKET"

say "建桶 $BUCKET（已存在则跳过）..."
wrangler r2 bucket create "$BUCKET" >/dev/null 2>&1 || warn "桶可能已存在，继续。"
say "开启公开访问..."
wrangler r2 bucket dev-url enable "$BUCKET" -y >/dev/null 2>&1 || warn "开启公开访问时有提示，继续。"

say "获取公开网址..."
RAW="$(wrangler r2 bucket dev-url get "$BUCKET" 2>/dev/null || true)"
PUBLIC_PREFIX="$(echo "$RAW" | grep -oiE 'https?://[a-z0-9.-]*r2\.dev' | head -1)"
[[ -z "$PUBLIC_PREFIX" ]] && PUBLIC_PREFIX="$(echo "$RAW" | grep -oiE 'pub-[a-z0-9]+\.r2\.dev' | head -1 | sed 's,^,https://,')"
[[ -z "$PUBLIC_PREFIX" ]] && PUBLIC_PREFIX="$(ask "没自动拿到公开网址，手动粘一下（形如 https://pub-xxxx.r2.dev）: " "")"
[[ -z "$PUBLIC_PREFIX" ]] && die "缺公开网址，无法继续。可稍后跑 wrangler r2 bucket dev-url get $BUCKET 拿到后写进 ~/.html-share.env"
ok "公开网址：$PUBLIC_PREFIX"

# ---- 6. 写配置 ----
CONF="$HOME/.html-share.env"
cat > "$CONF" <<EOF
BUCKET="$BUCKET"
PUBLIC_PREFIX="$PUBLIC_PREFIX"
EOF
ok "已写配置 $CONF"

# ---- 7. 设 pub 快捷命令 ----
ALIAS_LINE="alias pub=\"$REPO_DIR/publish.sh\""
RC="$HOME/.bashrc"; [[ "$OS" == "mac" ]] && RC="$HOME/.zshrc"
touch "$RC"
grep -qF "$ALIAS_LINE" "$RC" 2>/dev/null || printf '\n# html-share\n%s\n' "$ALIAS_LINE" >> "$RC"
ok "已把 pub 命令写进 $RC"

# ---- 完成 ----
printf '\n\033[32m🎉 全部搞定！\033[0m\n'
cat <<EOF

试一下（新开一个终端，或先跑 source "$RC"）：

    printf '# 你好\\n\\n我用 pub 发的第一篇文章。\\n' > ~/test.md
    pub ~/test.md

会打印一条 $PUBLIC_PREFIX/... 链接，并自动复制到剪贴板——发微信，点开就能读。

文档与更新：$REPO_URL
EOF
