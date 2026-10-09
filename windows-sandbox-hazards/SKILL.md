---
name: windows-sandbox-hazards
description: 在 Windows 上用 AI 代理跑命令、写脚本、做文件读写、文本编码处理或用 git 之前加载。列出会静默失败、或伪装成别的问题的环境陷阱，分「跨环境通用」与「换环境需重验」两档。
---

# Windows 上跑 AI 代理的环境陷阱

**什么时候读这份**：准备敲第一条命令、写第一个脚本、做第一次文件读写之前。

**为什么不靠"出问题再查"**：下面这些坑的共同点是——**失败时的样子和你以为的原因不是一回事**。你会去修一个不存在的问题，或者得出一个错误结论。所以**触发条件写成"我即将执行某个动作"，而不是"我遇到了某个症状"**。

**怎么用这份清单**：

- **第一节跨环境通用**（PowerShell / Node / Python 本身的性质），换机器依然成立
- **第二节大部分也通用**（Git for Windows 的固有行为），但"受限环境里推不上去"那一条随环境变化
- **第三、四节随环境和项目变化**，换电脑、换 AI 平台、换项目后**必须重新验证**——它们是"待验项"，不是结论
- 每条都标了「**会被误判成什么**」，那是它真正费时间的地方

---

## 一、跨环境通用：会静默给出错误结果

> 这一节是 Windows + PowerShell 本身的性质，换任何机器都成立。最危险的一类——**不报错，但答案是错的**。

### 1.1 PowerShell 5.1 把 UTF-8 响应按 ANSI 解码

`Invoke-WebRequest -UseBasicParsing` 拿回来的 `.Content` **不一定是 UTF-8 解码的**。服务端明确发了 `charset=utf-8`，PowerShell 5.1 仍可能按当前 ANSI 代码页解。

```powershell
# 错：中文匹配会静默失败
$js = (Invoke-WebRequest $u -UseBasicParsing).Content
if ($js -match '关键字') { "命中" } else { "没命中" }     # 中文永远走到 else

# 对：拿到字节自己解码
$bytes = $r.RawContentStream.ToArray()
$html = [System.Text.Encoding]::UTF8.GetString($bytes)
```

**会被误判成**：「改动没生效」「文件没更新」「服务端发的是旧版」——于是去重启服务、清缓存、查构建，全都白做。
**识别特征**：`-match` 中文永远为假，但同一份内容里的 **ASCII 片段能匹配上**。

> 顺带：PowerShell 5.1 的 `Invoke-WebRequest` 对部分外部站点还会直接 TLS 失败。抓外网用 Node 或 Python，别用它。

### 1.2 `$pid` 是 PowerShell 保留变量

```powershell
$pid = (netstat -ano | Select-String ':8080' | ...)   # 赋值失败，只警告不中断
"进程 $pid"                                            # 打印的是当前 shell 自己的 PID
```

**会被误判成**：拿到一个**格式正常、但不相关**的 PID，再拿它判断"进程什么时候启动的"，结论全错。
**做法**：用 `$bePid` 这类名字；取进程信息后先打印出来核对一眼。

### 1.3 读别的进程正打开的文件：`ReadAllLines` 会被拒

长期运行的程序（服务、采集器）对日志/索引持有追加句柄，`[System.IO.File]::ReadAllLines()` 申请的是**独占读**，直接抛 `IOException: being used by another process`。

```powershell
# 关键：ReadWrite 共享，而不是默认的独占
$fs = [System.IO.File]::Open($path, 'Open', 'Read', 'ReadWrite')
$sr = New-Object System.IO.StreamReader($fs)
while ($null -ne ($l = $sr.ReadLine())) { ... }
$sr.Close(); $fs.Close()
```

**会被误判成**：「文件坏了」「权限不够」。
> 附带好处：这个写法是**流式**的，读几十 MB 的日志也不会把内存打满。

### 1.4 Python stdout 在中文 Windows 上是 GBK

`print` 中文会崩或乱码。**脚本里的 print 一律只用 ASCII**；要输出中文就写进文件再读，或显式设 `PYTHONIOENCODING=utf-8`。

### 1.5 `.bat` / `.ps1` 的编码陷阱

| 文件 | 规则 |
| --- | --- |
| `.bat` | **内容必须纯 ASCII**。`cmd.exe` 按当前代码页逐行解析，含中文会乱码并**错位执行**，`chcp 65001` 救不了。中文只能出现在**文件名**上 |
| `.ps1` | 无 BOM 的 UTF-8 会被 PowerShell 5.1 按 ANSI 解析。要么存成带 BOM，要么保持纯 ASCII。中文路径**由脚本自身位置推导**，不要硬编码 |

### 1.6 内联 `node -e` 里的全角引号会被 shell 吃掉

```powershell
node -e "const a=['不能说“正常”']; ..."    # 全角引号把命令截断
```

报错长这样，看着像自己写错了语法：

```
['引述·正常性',   '不能说
              ^^^^
Expected ',', got '<eof>'
```

**做法**：只要脚本里要出现中文全角引号（`“”`、`「」`）或复杂转义，**写成 `.mjs` 文件再 `node 文件.mjs`**，不要内联。

### 1.7 `import()` 传 Windows 绝对路径必须先转 URL

```
Error [ERR_UNSUPPORTED_ESM_URL_SCHEME]: Received protocol 'e:'
```

```javascript
const { pathToFileURL } = await import('node:url');
const m = await import(pathToFileURL('E:/x/lib/mod.mjs').href);
```

### 1.8 Node 的 zstd 不支持「拼接帧」

- `zlib.zstdDecompressSync(buf)` **只解第一帧**——遇到多帧文件会返回一个很小的结果，容易误以为"文件坏了"或"文件是空的"
- `createZstdDecompress()` 流式遇到第二帧就报 `ZSTD_error_prefix_unknown`

**做法**：逐帧解。扫魔数 `28 B5 2F FD`，对每个候选偏移单独 `zstdDecompressSync`，成功的即一帧；压缩数据内部可能偶然出现同样字节，所以再按业务主键去重兜底。
（DSH 的 `session.jsonl.zstd` 就是这种格式，第一帧只有一百多字节的会话头。）

---

## 二、用 git 的时候

> 这一节大半是 **Git for Windows 的固有行为**，换机器依然成立；只有 2.2 那一条随环境变化。

### 2.1 schannel TLS 后端会直接失效——**还没发 HTTP 请求就挂**

```
schannel: AcquireCredentialsHandle failed: SEC_E_NO_CREDENTIALS (0x8009030e)
```

`git clone` / `ls-remote` / `push` 一律失败，**但失败在 TLS 层，根本没走到 HTTP**。

```bash
# Git for Windows 同时带 openssl 后端，换过去
git config http.sslBackend openssl          # 加 --global 或只配本仓库
# 或临时验证
git -c http.sslBackend=openssl ls-remote origin
```

**会被误判成**：认证失败、token 过期、代理配置错、网络不通。
**识别特征**：报错里出现 `schannel` / `AcquireCredentialsHandle` 字样，且 **`git config --get http.sslBackend` 返回 `schannel`**。
**代价**：会在反复重配凭据、查代理、换网络里绕很久——而那些全都不是原因。

### 2.2 凭据助手依赖 MSYS2 的 `sh.exe` → 受限沙箱里推不上去

```
sh.exe: *** fatal error - couldn't create signal pipe, Win32 error 5
fatal: unable to get password from user
```

Git for Windows 在凭据助手的部分路径上会拉起 MSYS2 的 `sh.exe`，而**受限沙箱禁止程序打开命名管道**（和无头浏览器 `mojo platform_channel: 拒绝访问` 是同一类边界）。

表现很有迷惑性：

| 操作 | 受限环境下 |
| --- | --- |
| `git add` / `commit` / `log` | ✓ 正常 |
| `git ls-remote`（公开仓库匿名读） | ✓ 正常 |
| `git push`（要凭据） | ✗ signal pipe |

**做法**：受限环境里**只做本地提交**，把推送留给不受限的普通终端。
**会被误判成**：凭据没配好、token 无效——于是反复登录，而根本没走到认证那一步。

### 2.3 推送前先 `git ls-remote`

一条命令拿到三样信息，比直接 push 再猜错误强得多：

```bash
git ls-remote origin                    # 远程有哪些引用
git -c credential.helper= ls-remote origin   # 强制匿名读：能读到 = 公开仓库
```

1. **远程是空仓库还是已有提交** → 决定敢不敢直接 `push`、会不会 non-fast-forward
2. **推送之前就暴露 TLS 问题**（见 2.1），省得在 push 里混看好几种错误
3. **推送后核对**：`git rev-parse main` 与远程 ref 是否一致

### 2.4 防挂起的开关会连正常读凭据一起挡掉

想让可能卡住的命令**快速失败**而不是挂在那里等输入，很容易顺手关太多：

| 开关 | 效果 |
| --- | --- |
| `GIT_TERMINAL_PROMPT=0` | 只挡终端提示 —— **推荐，够用** |
| `GCM_INTERACTIVE=never` | **连 GCM 读已缓存凭据也一起挡掉**：`Cannot prompt because user interactivity has been disabled` |

**结论**：只关前者。关掉后者会把本来能成功的路径也堵死。

另外，跑可能等输入的命令**一定要设超时**（如 100~180 秒），否则一次凭据提示就能把整轮卡死，而且看不出卡在哪。

---

## 三、随环境变化，用前先验证

> **换电脑 / 换 AI 平台 / 换托管方式后，这一节必须重验。** 不同沙箱的边界不一样，照搬会误判。

### 3.1 某些操作会被直接拒绝（EPERM / 拒绝访问）

| 操作 | 现象 | 替代做法 |
| --- | --- | --- |
| 子进程用**管道 stdio**（Node `spawn`/`exec` 默认 `pipe`） | `EPERM` | 用 `stdio: 'ignore'` 或 `'inherit'`；或改用 shell 自己的管道 |
| `fs.ftruncateSync` 动**追加句柄** | `EPERM` | 分块拷到临时文件再 rename 覆盖 |
| 无头浏览器（Chrome / Chromium） | `mojo platform_channel: 拒绝访问` | 多进程架构依赖命名管道。改用 resvg 之类的单进程渲染器，或不渲染 |
| WMI（`Get-CimInstance`） | 被拒 | 用 `netstat -ano` + `Get-Process` |

**共同点**：这些通常**不是"配置不对"，而是沙箱的既定边界**。不要换个写法反复重试，直接换方案。

### 3.2 临时目录被拒 → 表现为"网络问题"

pip 的临时目录、缓存目录如果落在被禁写的位置，**进程会无限卡住**，看起来完全像网络慢或源不可用。

```powershell
$env:TMP = "<工作区>\.tmp"
$env:TEMP = $env:TMP
$env:PIP_CACHE_DIR = "$env:TMP\pipcache"
# pip 另需 --no-cache-dir
```

**会被误判成**：网络问题、镜像源挂了、包太大。**这是排查顺序上最该先排掉的一项。**

### 3.3 管道截断会杀掉上游进程

`Select-Object -First N` / `head` 会让上游误以为"消费完了"。这会把**没下完的文件当成完整文件**搬走。

- 长任务写成**后台作业**，输出重定向到日志文件，再读日志
- 完成后**校验产物**（文件数、大小、sha256）
- **退出码 0 不等于成功**

---

## 四、项目/仓库约定（按项目重定）

> 这一节是**某一个仓库**的规矩。换项目要看目标仓库自己的 `AGENTS.md` 或等价规则文件，不要照搬。

- **没有版本控制时**：改文件前先备份（`xxx.bak-YYYYMMDD`），改完**回读校验**引用是否失效、数字是否一致，并**列出改动的文件清单**
- **大文件禁止整读**：中文文本约 **1.85 字符 / token**，即 **1 KB ≈ 320 token**。一个几百 KB 的文件整读一次就吃掉一个数量级的上下文预算 → 一律 `offset`/`limit` 定向读
- **路径不要硬编码层数**：用"从脚本位置逐级向上找仓库根"，不要用 `dirname(dirname(__file__))`。后者在脚本被移动后会**静默写错位置**（建目录不会报错）
- **临时文件集中放一个可随时清空的目录**，不要散落

---

## 用之前先自检

- [ ] 命令里有中文匹配吗？→ 自己解码字节，别用 `.Content`
- [ ] 要读的文件正在被别的进程写吗？→ `FileShare.ReadWrite`
- [ ] 脚本里有全角引号吗？→ 落成 `.mjs` 再跑，别内联
- [ ] 要截断长输出吗？→ 改后台作业 + 日志文件
- [ ] 改文件前备份了吗？改完列清单了吗？
- [ ] 要读的文件多大？→ 超过几十 KB 就定向读
- [ ] **要跑 git 吗？** → 先 `ls-remote`；报错含 `schannel` 就换 openssl 后端；可能要等输入的命令**设超时**
- [ ] **在受限沙箱里推送失败？** → 不是凭据问题，改到普通终端做（见 2.2）
- [ ] **换环境了？** → 第三节全部重验

## 来源

第一、二节提炼自一次完整的 Windows + AI 代理开发会话（2026-10-09 ~ 10-10），其中第二节（Git）来自一次真实推送排障：先撞 schannel、再撞命名管道、最后卡在凭据交互，四个坑串在一起。

第三节标的是**当时那台机器**的沙箱边界，**换环境请重验**。第四节是项目约定，按目标项目自己的规则文件重定。

凡标注「会被误判成什么」的条目，都是实际浪费掉的时间换来的。
