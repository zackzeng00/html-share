# AGENTS.md — 给 AI 编程助手的说明（Codex / Cursor / WorkBuddy / 任意桌面 agent）

> 如果你是一个能跑命令的 AI 助手（Codex、Cursor、WorkBuddy、Claude Code 等），
> 用户把这个仓库交给你，目标是：**帮他把"md/html 一键发成微信能打开的公开链接"这套工具装好并用起来。**
> 按下面做即可，全程替用户执行命令，只在需要他本人操作时停下说明。

## 这套工具解决什么

Markdown / HTML 在微信、飞书聊天框里打不开、复制过去糊成一坨。
本工具把它们传到 Cloudflare R2，生成一条公开链接，对方点开就是干净的网页。

## 一、一次性安装（替用户执行）

直接运行仓库根目录的安装脚本：

```bash
./install.sh
```

它会：装 node + pandoc + wrangler → 登录 Cloudflare → 建桶并开公开访问 → 写配置 `~/.html-share.env` → 设 `pub` 快捷命令。

**有两步必须用户本人参与，请提前向他说明：**

1. **Cloudflare 账号**：没有就去 https://dash.cloudflare.com/sign-up 免费注册，并在控制台左侧开通 **R2**（首次需绑一张卡做验证，免费额度内不扣费）。
2. **`wrangler login`**：脚本会弹出浏览器，让用户点 **Allow** 授权，授权完回到终端。

> Windows 用户：请在 **Git Bash** 里运行（先装 [Git for Windows](https://gitforwindows.org/)），不要用 PowerShell / CMD。

## 二、日常使用（替用户执行）

```bash
./publish.sh 文件.md            # 或 pub 文件.md（安装脚本已设别名）
./publish.sh 文件.html
./publish.sh 站点目录/           # 多页站点：整个文件夹发布（需含 index.html）
./publish.sh 报告.md --slug q3-report   # 自定义链接里的可读名
```

- `.md` 自动用 pandoc 转成自包含 html 再发布；`.html` 原样发布。
- **目录** 整个文件夹按相对路径上传、逐文件设 content-type、返回 `index.html` 链接——多页站点 / 拆分 css/js 时用这个，不必硬塞进单文件。
- 成功后打印链接并复制到剪贴板；把链接原样回给用户，让他发微信。

## 三、发布 HTML 前务必检查自包含

只对 `.html` 输入：确认没有引用外部相对资源（否则单文件发出去会缺样式/缺图）。

```bash
grep -oiE '(href|src)="[^"]+"' 文件.html | grep -viE 'https?://|data:|^#|mailto:'
```

有输出 → 二选一：① 把 CSS/JS 内联、图片转 base64 重写成单文件再发；② 多页站点就把整个目录发布（`./publish.sh 目录/`，需含 `index.html`），保留相对路径。

## 四、你自己生成要分享的 HTML 时

单页：务必单文件自包含——CSS 进 `<style>`、JS 进 `<script>`、图片用 base64；**零外部 CDN**（微信内置浏览器常拦截）；字体用系统栈；带 `viewport` meta；窄屏可读。验收：断网双击能正常打开。
多页站点（拆分 css/js、互链多个 html）：可不必硬合成单文件，直接 `./publish.sh 目录/` 整目录发布（入口须为 `index.html`）。**零外部 CDN 仍是硬约束**。

## 五、发布后验证（别只信回显）

```bash
curl -sI "<返回的URL>" | grep -iE 'HTTP/|content-type'   # 期望 200 + text/html
```

## 边界提示

链路是 Cloudflare，受众是自己/团队/飞书够用；要让**大陆客户每次秒开**得另走"备案 + 国内 CDN（如腾讯云 COS）"，这条线解决不了，需提醒用户。
