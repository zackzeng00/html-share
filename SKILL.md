---
name: html-share
description: 把 Markdown / HTML 一键发布成公开链接（托管在 Cloudflare R2），让它能在微信、飞书聊天框里点开渲染——原始 md/html 在聊天框里打不开。当用户说 发链接 / 分享 / 把这个 md(html) 发出去 / 传上去 / 生成可访问链接 / 生成可发布的网页 / publish / share link 时使用；生成将被分享或在手机/微信里打开的 HTML 时也按本技能的"自包含标准"产出。
---

# html-share

把 Markdown / HTML 变成一条 `https://<你的域名>/…` 公开链接，任何人点开即可看。
解决核心痛点：md/html 在微信、飞书聊天框里不渲染、没法直接分享。

底层是仓库里的 `publish.sh`（md 用 pandoc 转自包含 html、html 原样上传 Cloudflare R2，返回链接并复制到剪贴板）。
**脚本路径就在本技能目录下**（与本 SKILL.md 同级）；下文用 `<技能目录>/publish.sh` 指代。

## 何时触发

- 用户要把某个 md/html"发出去 / 分享 / 发个链接 / 传上去 / publish"
- 用户要"生成一个可访问链接 / 可发布的网页"
- 正在**生成将被分享或在手机/微信里打开的 HTML**——此时必须遵循下面的"生成标准"

## 一、先确认是否装好（首次使用）

发布前先看是否已配置：检查 `~/.html-share.env` 是否存在，且 `wrangler whoami` 能通。
若**没装好**，引导用户完成一次性安装——直接替他跑：

```bash
"<技能目录>/install.sh"
```

`install.sh` 会装 node/pandoc/wrangler、登录 Cloudflare、建桶、写配置、设 `pub` 命令。
其中两步需要用户本人参与，替他说明清楚即可：
1. **没有 Cloudflare 账号**：去 https://dash.cloudflare.com/sign-up 免费注册，并在左侧开通 R2（首次绑卡验证，免费额度内不扣费）。
2. **`wrangler login`** 会弹浏览器，让用户点 Allow 授权。

装好后继续发布。

## 二、发布流程（把文件变成链接）

```bash
"<技能目录>/publish.sh" <文件.md / 文件.html / 目录> [--slug 可读名] [--title 页面标题]
```

- `.md` → 自动用 pandoc 转成自包含 html 再发布
- `.html` → 原样发布
- **目录** → 整个文件夹发布（保留相对路径），见下方"多页站点"
- 成功后打印 `https://…/<slug>-<随机码>.html` 并复制到剪贴板
- `--slug` 给链接一个可读名字；不传则用文件名（纯中文名会退化为 `doc`）
- 随机码保证不覆盖，旧链接长期有效

**发布前的自包含检查**（仅对**单个** `.html` 输入；md 由 pandoc 自动内联）：

```bash
grep -oiE '(href|src)="[^"]+"' <文件.html> | grep -viE 'https?://|data:|^#|mailto:'
```

- 无输出（无外部相对引用）→ 直接发布
- 有输出（依赖相对 css/js/图片）→ 二选一：
  1. 按"生成标准"重写成单文件自包含再发（单页首选，微信兼容性最好）
  2. 整个目录一起发（多页站点首选，见下）

**多页站点 / 目录发布**：当确实是拆分的 css/js、互链的多个 html 时，直接把目录传给脚本：

```bash
"<技能目录>/publish.sh" <站点目录/> [--slug 可读名]
```

- 目录里**必须有 `index.html`** 作为入口（脚本会校验，没有则报错退出）
- 保留相对路径上传到 `<slug>-<随机码>/` 下，逐文件按扩展名设 content-type（html/css/js/json/svg/png/jpg/webp/woff2…，自动跳过 `.DS_Store`）
- 返回并复制 `…/<slug>-<随机码>/index.html` 链接；同源相对路径，微信内置浏览器能正常加载各页
- 每次发布是一份新快照（新随机码目录），改了内容要重发，旧链接仍指向旧快照

**发布后验证**（不要只信脚本回显）：

```bash
curl -sI "<返回的URL>" | grep -iE 'HTTP/|content-type'   # 期望 200 + text/html
```

目录发布时再抽查一个 css/js 子资源（期望 200 + 正确 content-type），确认整站能加载：

```bash
curl -sI "<…/slug-rand>/style.css" | grep -iE 'HTTP/|content-type'
```

最后把链接原样回给用户。

## 三、生成标准（生成 HTML 时就做成可发布的）

只要产出的 HTML 可能被分享或在微信里打开，**默认生成"单文件、自包含"的 HTML**：

1. **所有资源内联**——CSS 写进 `<style>`、JS 写进 `<script>`、图片用 base64 `data:` URI。不引用任何相对文件。
2. **零外部 CDN 依赖**——不用 `fonts.googleapis.com`、`cdn.jsdelivr.net`、`unpkg.com` 这类（国内/微信内置浏览器常拦截）。字体用系统字体栈（`-apple-system, "PingFang SC", "Microsoft YaHei", sans-serif`）。要用的库直接把压缩源码内联进 `<script>`。
3. **移动优先**——必须有 `<meta name="viewport" content="width=device-width, initial-scale=1">`，窄屏可读。
4. **正确头部**——`<meta charset="utf-8">` 和有意义的 `<title>`。
5. **验收**——断网后双击打开 html，样式、图片、交互都正常 = 合格。

生成结构性文档时不必手写 HTML——直接产出干净 md，发布时由 pandoc 转成统一风格的自包含 html（样式见同目录 `style.css`）。

## 四、国内访问的边界提示

链路是 Cloudflare R2 + r2.dev（或用户自绑的域名）。

- 受众是**自己 / 团队 / 飞书** → 完全够用，直接发。
- 受众是**大陆客户且要求每次秒开** → 主动提醒：这条 CF 链路在大陆"一般够用、偶尔慢"，要保证秒开需另走**备案 + 腾讯云 COS / 国内 CDN**。

## 配置速查

- 配置文件 `~/.html-share.env`：`BUCKET`、`PUBLIC_PREFIX` 两行（由 install.sh 写入，也可手改）
- 绑自定义域名（可选，链接更短更稳）：`wrangler r2 bucket domain add <桶名> --domain share.你的域名.com`，然后把 `PUBLIC_PREFIX` 改成该域名
