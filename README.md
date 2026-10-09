# 实时监测展示类项目的 AI 技能包

一组**项目无关**的可复用技能，给 AI 编程代理用。适用于这一类项目：

> **设备/服务实时数据进来 → Web 端展示给人看 → 可能再叠一层本地模型做问答**

三个技能按"什么时候读"排：

| 技能 | 什么时候读 | 内容 |
| --- | --- | --- |
| `project-handover` | **接手**已有系统、或要新建同类系统，**动手之前** | 该向人索取什么：数据源实测表、人工核对结论表、边界与验收表、协作偏好。**含可直接填空的模板** |
| `new-project-kickoff` | 起手/接手时 | 起手顺序、可复用架构骨架、验证方法论，**并标注哪些是当时的一次性选择** |
| `windows-sandbox-hazards` | 在 Windows 上跑命令、写脚本、文件读写之前 | 会静默失败、或伪装成别的问题的环境陷阱，**分「跨环境通用」与「换环境需重验」两档** |

> **先读 `project-handover`。** 代码和架构都能重建，但设备真实行为、人对图纸/设备的核对结论、领域边界、委托方的协作习惯——**这几类 AI 自己拿不到**。缺了它们，会做出"看起来对、实际错"的东西。

---

## 安装

**克隆下来是"不能直接用"的。** 技能必须位于 AI 工具的**发现根目录**里，而这个仓库的目录布局不是。装一次即可。

### DSH

发现根目录（按优先级）：

| 级别 | 路径 |
| --- | --- |
| 项目级（优先级高） | `<项目根>\.dsh\skills\` |
| 项目级 | `<项目根>\.agents\skills\` |
| 用户级（与 cwd 无关） | `~\.dsh\skills\` |
| 用户级 | `~\.agents\skills\` |

每个技能要么**复制进去**，要么**做一个链接指过去**（推荐，改一处两边同步）。

Windows，在仓库根执行：

```powershell
$root = "$env:USERPROFILE\.dsh\skills"
New-Item -ItemType Directory -Force -Path $root | Out-Null
foreach ($n in 'project-handover','new-project-kickoff','windows-sandbox-hazards') {
  New-Item -ItemType Junction -Path (Join-Path $root $n) -Target (Resolve-Path "realtime-monitoring-stack\$n") | Out-Null
}
```

Linux / macOS：

```bash
mkdir -p ~/.dsh/skills
for n in project-handover new-project-kickoff windows-sandbox-hazards; do
  ln -s "$PWD/realtime-monitoring-stack/$n" ~/.dsh/skills/$n
done
```

**注意两点：**

1. **项目级 vs 用户级**：项目级只在从那个项目启动会话时生效。想让**任何项目**都能用，装到用户级。
2. **Windows 上删链接要用非递归删除**——`Remove-Item -Recurse` 有跟随到目标、把真实内容一起删掉的风险：
   ```powershell
   [System.IO.Directory]::Delete($link, $false)
   ```

### 其他 AI 工具

`SKILL.md` + YAML frontmatter 是**跨工具约定**（"Agent Skills"），不走专有格式。把目录放到该工具自己的技能目录即可，各工具路径不同，**以它自己的文档为准**。

不支持技能的工具有个退路：正文就是普通 Markdown，贴进它的规则文件（`.cursorrules`、`.clinerules`、`copilot-instructions.md` 之类）也能用——只是失去"按需加载"，变成常驻上下文。

---

## 验证装好了没有

**起一个新会话，看技能清单里有没有出现这三个条目。** 出现了就是装好了。

DSH 的技能目录是每个 `agent/pre-step` 重新快照注入的，不需要重启。

没出现的话依次查：

1. 路径对不对（是不是漏了一层目录）
2. **加载技能的插件在不在**——DSH 的 `minimal` 预设**不带** `skill-filesystem` / `tool-skill`，用它会一个技能都看不到；`code` / `standard` / `cordis` 都带
3. 链接是不是断了（`Test-Path <root>\<name>\SKILL.md`）
4. 项目级技能：会话的 cwd 能不能解析到仓库根

---

## 格式要求（硬性的）

1. 只能是 `<name>/SKILL.md` 或 `<name>.md`，**只认一层**——嵌套的 `**/SKILL.md` 会被忽略
2. frontmatter 必须有 `name`（**kebab-case**）和 `description`
3. **目录名必须和 `name` 一致**
4. **存成 UTF-8 无 BOM**——frontmatter 靠行首的 `---` 识别，BOM 会让第一行匹配不上
5. 行尾用 LF（本仓库已用 `.gitattributes` 强制）

可选的 frontmatter 字段：`whenToUse`、`metadata`、`disable-model-invocation`（禁止模型自动加载）、`user-invocable`（允许用户手动唤起）。

---

## 写新技能的约定

- **`description` 写"什么时候该读"，不要写"里面有什么"**
  - 差：`解决 pip 卡死、中文乱码、EPERM 等问题` —— 出问题时你想不起来它
  - 好：`执行任何命令、写任何脚本之前先加载` —— 你在**动手前**就知道自己要做这件事，触发点是确定的
  - 原理：目录里只有 `name` + `description` 是常驻上下文，**它是唯一的匹配依据**
- **把"当时这么定的"标出来**，写成 `【一次性】`。一个项目的选择会被下一个项目照搬，那是错误的前提
- **换环境会失效的内容要标出来**（机器相关的沙箱边界、某个模型特有的提示词行为），当"待验证清单"用而不是"结论"

---

## 新增技能

放在 `realtime-monitoring-stack/` 下，与现有三个平级：

```
realtime-monitoring-stack/
  <kebab-case-name>/SKILL.md
```

然后按上面的「安装」重新链接一次。

---

## 目录

```
realtime-monitoring-stack/
  project-handover/SKILL.md
  new-project-kickoff/SKILL.md
  windows-sandbox-hazards/SKILL.md
```

仓库外还有一份本机备份，不在 git 里。
