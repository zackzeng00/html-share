# html-share · 把 md / html 一键发成微信能点开的链接

> 你让 AI 整理了一份图文攻略 / 报告，最合适的载体是网页（HTML）或 Markdown。
> 可它们发进微信、飞书——**打不开、不渲染、复制过去糊成一坨。**
> 这个小工具让你**一行命令**把 md / html 变成一条公开链接，对方一点，就是干干净净一篇文章。

```
pub 旅行攻略.md
✅ 发布成功（已复制到剪贴板）
   https://pub-xxxx.r2.dev/lv-xing-gong-lue-a3f9c1.html   ← 发微信，点开就能读
```

全程免费（用 Cloudflare 免费额度），不用买服务器。Mac / Windows / Linux 都能用。

---

## 三种装法，挑你顺手的

### 🟢 方式 A：你有 AI 助手（Claude Code / Codex / Cursor / WorkBuddy…）—— 最省事

不用懂命令行，让你的桌面 AI 替你装：

**Claude Code** —— 直接 clone 成一个技能，重启后跟它说话即可：
```bash
git clone https://github.com/zackzeng00/html-share ~/.claude/skills/html-share
```
重启 Claude Code，然后对它说：「**帮我把 html-share 装好**」，再之后任何时候说「**把这个 md 发出去**」就行。

**其它 agent（Codex / Cursor / WorkBuddy 等）** —— clone 下来，把仓库丢给它：
```bash
git clone https://github.com/zackzeng00/html-share && cd html-share
```
然后对它说：「**读一下 AGENTS.md，帮我把这套工具装好、然后把 xxx.md 发出去**」。
它会照着 [`AGENTS.md`](./AGENTS.md) 替你跑完所有命令。

### 🔵 方式 B：一条命令安装（命令行党）

Mac / Linux，复制粘贴回车：
```bash
curl -fsSL https://raw.githubusercontent.com/zackzeng00/html-share/main/install.sh | bash
```
> Windows：先装 [Git for Windows](https://gitforwindows.org/)，在 **Git Bash** 里把上面那条粘进去（不要用 PowerShell / CMD）。

脚本会自动装好 node + pandoc + wrangler，引导你登录 Cloudflare、建桶，并设好 `pub` 命令。

### ⚪ 方式 C：手动 clone

```bash
git clone https://github.com/zackzeng00/html-share && cd html-share
./install.sh        # 一次性安装与配置
```

---

## 用法

```bash
pub 报告.md                  # md 自动转成好看的独立网页再发布
pub page.html                # html 原样发布
pub 站点目录/                 # 整个文件夹发布（多页站点，需含 index.html，返回 index 链接）
pub 报告.md --slug q3-report  # 自定义链接里的可读名字
pub 报告.md --title "Q3 财报"  # 覆盖 md 转 html 的网页标题
```

链接发布后自动复制到剪贴板，直接粘进微信 / 飞书即可。

## 它做了什么

- **md** → 用 pandoc `--embed-resources` 转成**全内联、自包含**的 html（CSS 直接嵌进文件，不依赖任何外部 CDN）。这点对微信很关键：微信内置浏览器加载外部 JS/CSS 常被拦，自包含才能完整渲染。
- **html** → 原样上传。
- **目录** → 整个文件夹按相对路径上传（拆分的 css/js、互链的多页 html、本地图片都保留），逐文件自动设 content-type，返回入口 `index.html` 的链接。适合多页站点 / 交互应用，不必硬塞进单文件。
- 上传到 Cloudflare R2，对象名形如 `<可读名>-<随机码>.html`（目录则放在 `<可读名>-<随机码>/` 下）——随机码保证不覆盖、**旧链接长期有效**。

## 配置

安装脚本会写到 `~/.html-share.env`：

```bash
BUCKET="my-share"                          # 你的 R2 桶名
PUBLIC_PREFIX="https://pub-xxxxxxxx.r2.dev" # 公开访问地址
```

**绑自己的域名**（可选，链接更短更稳、微信更信任）——前提是有个域名且 DNS 托管在 Cloudflare：
```bash
wrangler r2 bucket domain add my-share --domain share.你的域名.com
```
绑好后把 `PUBLIC_PREFIX` 改成 `https://share.你的域名.com`。

## 关于国内访问

链路是 Cloudflare R2 + r2.dev（或你自绑的域名）。

- **自己 / 团队 / 飞书** → 够用，直接发。
- **大陆客户要求每次秒开** → Cloudflare 这条线偶尔慢；要保证秒开得另走**备案 + 腾讯云 COS / 国内 CDN**。

## 常见问题

- **`command not found: pub`** → 关掉终端重开一个新窗口（alias 要新窗口才生效）。
- **npm 装 wrangler 报权限错（Mac）** → `sudo npm install -g wrangler`。
- **上传失败 / 要登录** → `wrangler login` 重新授权；多账号时选开了 R2 的那个。
- **中文文件名链接变成 `doc-xxxx`** → 正常，链接名只能英文/数字；加 `--slug 英文名` 自定义。
- **Windows 报一堆错** → 必须在 **Git Bash** 里跑，不是 PowerShell / CMD。
- **安全？** → 桶是公开读取，拿到完整链接的人都能看（链接带随机码、外人猜不到但能转发）。别用它发隐私内容。

## 依赖

`git`、`node`（含 npm）、`pandoc`、`wrangler` —— 安装脚本会自动装好。

## License

MIT
