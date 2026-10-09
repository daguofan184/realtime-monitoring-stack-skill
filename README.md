# 实时监测展示类项目的 AI 技能包

一组**项目无关**的可复用技能，给 AI 编程代理用。适用于这一类项目：

> **设备/服务实时数据进来 → Web 端展示给人看 → 可能再叠一层本地模型做问答**

| 技能 | 什么时候读 | 内容 |
| --- | --- | --- |
| [`project-handover`](project-handover/SKILL.md) | **接手**已有系统、或要新建同类系统，**动手之前** | 该向人索取什么：数据源实测表、人工核对结论表、边界与验收表、协作偏好。**含可直接填空的模板** |
| [`new-project-kickoff`](new-project-kickoff/SKILL.md) | 起手/接手时 | 起手顺序、可复用架构骨架、验证方法论，**并标注哪些是当时的一次性选择** |
| [`windows-sandbox-hazards`](windows-sandbox-hazards/SKILL.md) | 在 Windows 上跑命令、写脚本、文件读写之前 | 会静默失败、或伪装成别的问题的环境陷阱，**分「跨环境通用」与「换环境需重验」两档** |

> **先读 `project-handover`。** 代码和架构都能重建，但设备真实行为、人对图纸/设备的核对结论、领域边界、委托方的协作习惯——**这几类 AI 自己拿不到**。缺了它们，会做出"看起来对、实际错"的东西。

---

## 安装

### 方式一：一条命令（不用先 clone）

**Windows**（PowerShell）：

```powershell
irm https://raw.githubusercontent.com/daguofan184/realtime-monitoring-stack-skill/main/install.ps1 | iex
```

**Linux / macOS / WSL**：

```sh
curl -fsSL https://raw.githubusercontent.com/daguofan184/realtime-monitoring-stack-skill/main/install.sh | sh
```

装到**用户级**发现根（`~/.dsh/skills`），任何项目里都能用。脚本会打印每一步结果并自动校验 frontmatter。

> 这种方式是**从网上直接执行脚本**。脚本很短，建议先看一眼再跑；不放心就用方式二。
> 国内访问 `raw.githubusercontent.com` 可能不通，那就走方式二。

### 方式二：clone 后本地执行

```sh
git clone https://github.com/daguofan184/realtime-monitoring-stack-skill.git
cd realtime-monitoring-stack-skill
```

```powershell
# Windows
powershell -ExecutionPolicy Bypass -File install.ps1
```
```sh
# Linux / macOS / WSL
sh install.sh
```

**常用参数**（两个脚本一致）：

| 参数 | 作用 |
| --- | --- |
| `-Scope user` / `--scope user` | 默认。装到 `~/.dsh/skills`，**任何项目**都能用 |
| `-Scope project` / `--scope project` | 装到 `./.dsh/skills`，只对**从这个目录启动**的会话生效 |
| `-Copy` / `--copy` | 复制而不是链接。链接不可用时（某些同步工具、容器）才需要，代价是更新要重跑 |
| `-Uninstall` / `--uninstall` | 卸载。**删链接时用非递归删除，绝不会碰到技能真身** |

**重复执行是安全的**，也是更新方式：`git pull` 之后再跑一次脚本。

### 方式三：手动（不想跑脚本）

技能必须位于 AI 工具的**发现根目录**里。每个技能要么复制进去，要么做一个链接指过去：

```powershell
# Windows
$root = "$env:USERPROFILE\.dsh\skills"
New-Item -ItemType Directory -Force -Path $root | Out-Null
foreach ($n in 'project-handover','new-project-kickoff','windows-sandbox-hazards') {
  New-Item -ItemType Junction -Path (Join-Path $root $n) -Target (Resolve-Path $n) | Out-Null
}
```
```sh
# Linux / macOS / WSL
mkdir -p ~/.dsh/skills
for n in project-handover new-project-kickoff windows-sandbox-hazards; do
  ln -s "$PWD/$n" ~/.dsh/skills/$n
done
```

**发现根目录一览**：

| 级别 | 路径 |
| --- | --- |
| 项目级（优先级高） | `<项目根>/.dsh/skills/` |
| 项目级 | `<项目根>/.agents/skills/` |
| 用户级（与 cwd 无关） | `~/.dsh/skills/` |
| 用户级 | `~/.agents/skills/` |

**项目级 vs 用户级**：项目级只在从那个项目启动会话时生效；想让**任何项目**都能用，装用户级。

**⚠ Windows 上删链接必须用非递归删除**——`Remove-Item -Recurse` 有跟随到目标、把技能真身一起删掉的风险：

```powershell
[System.IO.Directory]::Delete($link, $false)
```

### 方式四：让 AI 自己装

不想自己敲命令，就把这段连同本页地址丢给它：

> 从 `https://github.com/daguofan184/realtime-monitoring-stack-skill` 安装技能包：clone 下来，然后把每个含 `SKILL.md` 的子目录链接到 `~/.dsh/skills/`（Windows 用目录联接，删旧链接要用非递归删除）。装完起一个新会话，确认这三个出现在技能清单里：`project-handover`、`new-project-kickoff`、`windows-sandbox-hazards`。装不上就把每一步的实际输出告诉我。

---

## 验证装好了没有

**起一个新会话，看技能清单里有没有出现这三个条目。** 出现了就是装好了。

技能目录是每个 `agent/pre-step` 重新快照注入的，不需要重启。

没出现的话依次查：

1. 路径对不对（是不是漏了一层目录）
2. **加载技能的插件在不在**——DSH 的 `minimal` 预设**不带** `skill-filesystem` / `tool-skill`，用它会一个技能都看不到；`code` / `standard` / `cordis` 都带
3. 链接是不是断了：`Test-Path <root>\<name>\SKILL.md`
4. 项目级技能：会话的 cwd 能不能解析到仓库根

---

## 其他 AI 工具

`SKILL.md` + YAML frontmatter 是**跨工具约定**（"Agent Skills"），不是专有格式。把目录放到该工具自己的技能目录即可——各工具路径不同，**以它自己的文档为准**。

不支持技能的工具有个退路：正文就是普通 Markdown，贴进它的规则文件（`.cursorrules`、`.clinerules`、`copilot-instructions.md` 之类）也能用——只是失去"按需加载"，变成常驻上下文。

---

## 格式要求（硬性的）

1. 只能是 `<name>/SKILL.md` 或 `<name>.md`，**只认一层**——嵌套的 `**/SKILL.md` 会被忽略
2. frontmatter 必须有 `name`（**kebab-case**）和 `description`
3. **目录名必须和 `name` 一致**
4. **存成 UTF-8 无 BOM**——frontmatter 靠行首的 `---` 识别，BOM 会让第一行匹配不上
5. 行尾用 LF（本仓库已用 `.gitattributes` 强制）

可选的 frontmatter 字段：`whenToUse`、`metadata`、`disable-model-invocation`（禁止模型自动加载）、`user-invocable`（允许用户手动唤起）。

---

## 新增技能

放在仓库根，与现有三个平级：

```
<kebab-case-name>/SKILL.md
```

然后重新跑一次安装脚本。仓库根**本身就是一个合法的技能根**——`install.ps1` / `install.sh` 就是按"一级子目录里含 SKILL.md"来发现的，也正是因为这一点，脚本不需要知道技能列表。

## 写新技能的约定

- **`description` 写"什么时候该读"，不要写"里面有什么"**
  - 差：`解决 pip 卡死、中文乱码、EPERM 等问题` —— 出问题时你想不起来它
  - 好：`执行任何命令、写任何脚本之前先加载` —— 你在**动手前**就知道自己要做这件事，触发点是确定的
  - 原理：目录里只有 `name` + `description` 是常驻上下文，**它是唯一的匹配依据**
- **把"当时这么定的"标出来**，写成 `【一次性】`。一个项目的选择会被下一个项目照搬，那是错误的前提
- **换环境会失效的内容要标出来**（机器相关的沙箱边界、某个模型特有的提示词行为），当"待验证清单"用而不是"结论"
- **`.ps1` 保持纯 ASCII**——PowerShell 5.1 读无 BOM 的 UTF-8 会按 ANSI 解析，中文会乱码甚至错位执行

---

## 目录

```
.
├── install.ps1                  Windows 安装脚本（纯 ASCII）
├── install.sh                   Linux/macOS 安装脚本
├── README.md
├── project-handover/SKILL.md
├── new-project-kickoff/SKILL.md
└── windows-sandbox-hazards/SKILL.md
```

仓库根是合法技能根，所以也可以直接用工具的"自定义技能目录"配置指向 clone 下来的这个目录，一步到位。
