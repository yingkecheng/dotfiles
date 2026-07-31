---
name: grove-capture
description: >-
  跨项目把当前对话蒸馏成一页 seedling，写进 Grove 知识库 inbox。当用户说
  「存进 grove / 捕获到 grove / 沉淀进 grove」或调用 /grove-capture 时触发；
  仅用户主动开口才触发，绝不自动运行或主动建议捕获。
---

# grove-capture：把对话蒸馏成种子，落回 Grove inbox

## 它是什么

Grove 是用户的「LLM 写、人读」持久知识库（一个 Obsidian vault，位于
`~/Documents/Grove`）。它有两条入流，其中一条是**直接捕获**：工作中踩的坑、
命令速查、交接心得、配置过程、有价值的问题综合——这些没经过任何书 wiki，
直接成页。

但这些有价值的对话往往发生在**别的项目**里（写代码、配机器、调环境），那边的
Claude Code 不知道 Grove 的约定。这个 skill 就是那座桥：在远端把一次对话的常青
价值，蒸馏成一页**合规的 seedling**，直接写进 Grove 的 `inbox/`。

## 唯一职责与边界（先读这条，再动手）

职责很窄、很清楚：**读 Grove 的约定 → 把对话蒸馏成一颗合规种子 → 写进 inbox。**

**只做这些：**

- 读 Grove 的方法论真源（见下「步骤 1」），据此成页。
- 判断这次对话有没有常青价值；没有就直说、停手。
- 蒸馏（提炼不照抄）成一或多页，套 Grove 的 frontmatter 与命名约定。
- 直接写进 `~/Documents/Grove/inbox/`。

**绝不做这些（重要，别越界）：**

- 不写 `notes/`、不更新 `index.md` / `log.md`、不挂 MOC、不跑 git / prettier。
  这些「编织」动作需要 Grove 的完整上下文（读已有页、查重、连链），留给用户
  下次在 Grove 里干 capture / lint 时做。你人在远端，做不了，也不该做。
- 不读取、不依赖**当前项目**的 CLAUDE.md——那是别的仓库的约定，与 Grove 无关。
- 不自动触发、不批量灌、不存 raw transcript（聊天记录原文）。inbox 是中转不是
  剪贴板，把它当垃圾场会直接毁掉这个库（上一个库就是这么死的）。

## 步骤

### 1. 现读 Grove 约定（真源不内嵌）

用 Read 读这两个文件，按它们来，别凭记忆：

- `~/Documents/Grove/CLAUDE.md` —— 重点看「七、工作流 · Capture」和
  「八、约定细则」（语言、slug、缩写大小写、不用 emoji）。
- `~/Documents/Grove/meta/note-template.md` —— 页面模板与 frontmatter 形状。

把 Grove 的 CLAUDE.md 当唯一方法论真源。如果它和本 skill 的描述有出入，**以
Grove 的 CLAUDE.md 为准**——本 skill 只是把你带到那里、给出边界，不复制它的规则。

### 2. 判断价值（价值闸门）

回看当前对话，问自己：**这里有没有值得变成常青页的东西？**

值得的信号：踩过并解决了一个真实的坑；一段可复用的 howto / 命令速查；一个配置
或排障过程的心得；一个有价值的问题综合或结论。

不值得就**停手**，直接告诉用户「这次对话没什么值得沉淀进 Grove 的——都是
一次性的操作 / 没有可复用结论」，不要硬凑一页塞进 inbox。宁可不写，也不让
inbox 退化成剪贴板。这正是用户痛点（输入多沉淀少）的解法所在。

### 3. 蒸馏成页

**提炼，不照抄。** 去掉对话噪音（试错过程、来回确认、与主题无关的支线），
留下沉淀下来的结论与可复用的知识。一个概念 / 一件事一页，原子化；内容够独立的
话可拆成多页。

每页套 Grove 的模板：

- frontmatter：`status: seedling`、合规的 `tags`（按 Grove 的 tag-conventions，
  如 `domain/tools`、`kind/howto`）、`aliases`（别名/同义词，方便日后链接与搜索）、
  `source: "对话整理（YYYY-MM-DD，<一句话上下文>）"`、`updated: <今天>`。
- 正文：`**一句话**:` 开头点明是什么，再分节写核心内容；有命令/出处就带上。
- **不用 emoji**——状态与语义靠文字词和 frontmatter 承载。
- 文件名 = 自然概念名，小写 kebab-case（`openwrt-uci.md`、`ssh-over-443.md`）。
  领域能一眼归类时可加前缀助扫描（`kernel-page-tables.md`），非强制。
- 页面间宁可多写 `[[wikilink]]`：链到一个还不存在的 `[[page]]` 没关系，它标记了
  之后要补的页，lint 会捡起来。

### 4. 写入 inbox

用 Write 把每页写到 `~/Documents/Grove/inbox/<slug>.md`。仅此目录，别处不碰。

### 5. 收尾（只在末尾，一行）

写完后给用户一行回执：写入了哪个（些）文件 + 一句提醒「下次在 Grove 里干
capture / lint 时，把它编织进 notes（补链、查重、挂 MOC、更新 index）」。
不要在这里替用户做编织，也不要更新 index / log。

## 一句话总览

值得的对话 → 现读 Grove 约定 → 蒸馏成合规 seedling → 直接落 inbox →
重活留给用户回 Grove 时做。你只负责在远端产一颗干净的种子。
