---
name: oj-solver
description: >
  批量解决算法竞赛/OJ题目(C++)，由 Claude Code 单体完成：主 Claude 只读廉价映射、
  融合扇出派发多个 subagent 并行认领解题（每个 subagent 自己读图+解题，主线程不读截图；
  共享 oj_tasks 目录 + 认领锁防撞），自动编译测试、对拍纠错。支持从图片或文字提取题意。
  当用户提到刷题、做OJ、算法题、竞赛题、Codeforces、LeetCode、AtCoder、洛谷、
  牛客、ACM，给出题目截图/链接/题面，或要求"做 oj_tasks 里的题"、"批量解题"时，
  使用此 skill。
---

# OJ Batch Solver（Claude Code 并行 subagent 版）

解决批量算法题目：解析题意 -> 难度排序 -> 派发 subagent 并行认领 -> 编码实现 -> 编译测试 -> 纠错优化。

## 0. 总体流程（主 Claude 编排 + subagent 融合扇出解题）

全程由 Claude Code 一方完成。核心是**融合扇出**：读图与解题合并进同一个 subagent，主 Claude 不读重图。

| 角色 | 谁执行 | 做什么 |
|---|---|---|
| **编排/护栏** | 主 Claude（你自己） | 只读廉价映射（`pr.md` 等）拿「图↔题号」；派发；扫题意回述护栏；事后汇总 `queue.md` 与战报 |
| **融合解题** | 多个 solver subagent | 每个认领一道题：**自己读图**→写 `problem.md`+样例→独立攻克→跑测试/对拍→写状态→回报 |

关键点：
- 主 Claude 是**编排者**，**一张题面截图都不读**（避免串行 OCR 拖慢关键路径、撑爆上下文）；用一条消息 t=0 就**并行派发多个 subagent**。
- 所有 subagent 通过共享 `oj_tasks/` 目录协调，**互不通信、只看文件**，靠认领锁（`mkdir` 原子操作）防止两个 subagent 撞同一题。
- subagent 数量：一般每道题派一个，题量大时按可用并发分批派发（如一次 4~6 个），做完一批再派下一批处理剩余/挂起题。

```
主 Claude
 ├─ 只读 pr.md/消息 → 得「图片路径 ↔ 题号」映射（不读截图）
 └─ t=0 并行派发 subagent（各带自己题的图片路径）
     ├─ sub-A: claim A → 读图+写problem → 解 → test → ready → 回报(含题意回述)
     ├─ sub-B: claim B → 读图+写problem → 解 → test → ready → 回报
     └─ sub-C: claim C → 读图+写problem → 解 → 对拍 → ready → 回报
 ├─ 扫各回报的题意回述做护栏；事后按回报难度汇总 queue.md
 （收尾）扫描 suspended/WA 的题 → 再派 subagent 接手
```

## 1. 共享目录结构与状态约定

所有协作状态都落在 `./oj_tasks/` 下，**不依赖任何进程间通信**：

```
oj_tasks/
├── queue.md                 # 难度排序表（主 Claude 事后按 subagent 回报汇总；subagent 只读）
└── <题号>/                   # A/  B/  C/ ...
    ├── problem.md           # 题面 + 样例 + 数据范围 + 时空限制
    ├── .claim/owner         # 认领锁（mkdir 抢占），owner 文件内容: subagent 标识（如 sub-1）
    ├── status               # 单行状态（只有当前认领方可写）
    ├── attempts.md          # 思路与尝试记录（挂起时必写，供接手方阅读）
    ├── solution.cpp
    ├── test.sh
    └── 1.in 1.out 2.in 2.out ...
```

`status` 取值（单行纯文本）：

| 值 | 含义 | 谁来写 |
|---|---|---|
| `solving` | 已认领，正在解题 | 认领的 subagent（认领成功后立即写） |
| `ready` | 通过全部样例 + 检查清单，等待用户提交 | 认领的 subagent |
| `ac` | 用户反馈 AC | 主 Claude（收到反馈后） |
| `wa` / `tle` / `mle` / `re` | 用户反馈未过，待纠错 | 主 Claude（收到反馈后） |
| `suspended` | 已挂起、认领已释放，可被再次派发接手 | 挂起的 subagent |

`queue.md` 格式（主 Claude 事后按各 subagent 回报的难度/算法汇总写入，作副产物）：

```markdown
| 排名 | 题号 | 预估难度 | 算法标签 | 备注 |
|---|---|---|---|---|
| 1 | A | 签到 | 模拟 | |
| 2 | C | 简单 | 贪心 | 注意 long long |
| 3 | B | 中等 | DP | |
| 4 | D | 难 | 线段树/分治 | 数据范围 1e5 |
```

排名 1 = 最简单。排序仅用于派发优先级参考，并行解题时各题独立。

## 2. 题目解析与派发（融合扇出 —— 主 Claude 编排阶段）

启动后第一件事：检查 `oj_tasks/queue.md` 是否存在。

**情况一：queue.md 已存在** —— 跳过解析，直接进入 §3 派发解题。

**情况二：queue.md 不存在** —— 采用**融合扇出**：读图与解题合并进同一个 subagent，主 Claude **一张重图都不读**，从 t=0 就全部并行。

> **为什么**：主 Claude 在主线程里逐张读大截图，是串行的、在关键路径上、还把海量像素塞进主上下文——这是最大的可避免耗时。把"读图"和"解题"拆成两段（先全读完再派单）会白白拖慢墙钟。融合后，识图与解题重叠，识图彻底从关键路径消失，主上下文保持轻量。

```bash
mkdir -p oj_tasks
```

1. **主 Claude 只读廉价的映射信息**：读 `pr.md` / 用户消息等纯文本，拿到「图片路径 ↔ 题号」的对应关系。**不要**用 Read 打开题面截图本身。
2. **（可选，一次性）预压图**：截图常分辨率过高且带水印，`magick mogrify -resize 55% -quality 80 *.png` 压到一半以内，subagent 读得更快更省，不影响 OCR。（ImageMagick 7 起 `convert`/`mogrify` 为废弃旧名，须用 `magick` 子命令形式；Arch 上 `sudo pacman -S imagemagick`。缺失时跳过此步即可，不阻塞。）
3. **一个 subagent 全包一题，t=0 一次性并行派发**（题量大时按并发上限分批，一批 4~6 个）。给每个 subagent：它那道题的**图片路径**、唯一标识（`sub-A` 等）、认领协议（§3）、以及**判题机是 GCC 4.8.4、必须用 `-std=c++11` 本地验证**（§6，务必写进派发提示词——subagent 默认会按现代 C++ 写，不提醒必 CE）。每个 subagent 自己完成：
   - 读图 → 提取完整题面（原文+中文翻译）、**全部样例逐字符核对**、数据范围与时空限制 → 写 `oj_tasks/<题号>/problem.md`，样例拆成 `1.in`/`1.out`…
   - 选算法（§5）→ 编码（§6）→ 写 `test.sh` 跑样例（§7）→ 难题加对拍（§4.2 / §9）→ 过检查清单（§8）→ 写 `ready`。
   - **回报里必须含一句题意回述** + 预估难度 + 算法标签 + 数据范围（供护栏与事后排名）。
4. **准确性护栏**（融合方案唯一代价：没有中心审阅者兜底误读）：主 Claude 扫每个 subagent 的**题意回述**，只有回述可疑时才亲自补读**那一张**图核对；难题继续强制对拍，本身就能挡住误读。
5. **queue.md 是副产物**：用各 subagent 回报的难度/算法/数据范围事后汇总写入，**不作为解题的前置阻塞**。

> **何时退回两段式**：题量大且并发不够、又想"先出简单题的 AC"时，可先发一个轻量 triage subagent 只回 `{题号,难度,数据范围}`（不解题）用于排序，再按易→难派 solver。4~6 题这种规模无需排序，直接全扇出、靠并发上限排队即可。

> 全程在 Claude Code 内部完成：主 Claude 只做映射、护栏、汇总；读图与解题都在并行 subagent 内融合执行。

## 3. 认领协议（防 subagent 撞题）

核心：**`mkdir` 是原子操作**——两个 subagent 同时认领同一题，必然只有一方成功。每个解题 subagent 拿到一个唯一标识（如 `sub-1`、`sub-2`）后按此协议工作。

```bash
AGENT=sub-1   # 派发时告知每个 subagent 自己的唯一标识

# 认领题目 $1：成功返回 0（开始做题），失败返回 1（被别的 subagent 抢了，换下一题）
claim() {
    local p="oj_tasks/$1"
    if mkdir "$p/.claim" 2>/dev/null; then
        echo "$AGENT" > "$p/.claim/owner"
        echo "solving" > "$p/status"
        return 0
    fi
    return 1
}

# 挂起题目 $1：写完 attempts.md 交接笔记后再调用，释放认领权
suspend() {
    local p="oj_tasks/$1"
    echo "suspended" > "$p/status"
    rm -rf "$p/.claim"
}
```

铁律（每个 subagent 都必须遵守）：

1. **做任何一道题之前必须先 claim 成功**，claim 失败就立刻换下一道，绝不和别的 subagent 做同一道题。
2. **只写自己认领的题的文件**。未认领的题，所有文件一律只读。
3. **挂起前必须写 `attempts.md`**：尝试过的思路、为什么不对/过不了、卡在哪里、样例对拍结果。这是给接手方的交接笔记，质量直接决定接手效率。
4. queue.md 写入后不再修改；如对难度判断有异议，写在自己题目的 attempts.md 里，不要改公共文件。

## 4. 解题主循环（每个 solver subagent 执行）

### 4.1 取题

主 Claude 派发时可直接指定一道题给 subagent；若让 subagent 自行取题，则按 `queue.md` 顺序遍历，跳过满足任一条件的题：已有 `.claim/`、status 为 `ac` / `ready` / `solving`。对找到的题执行 `claim`；失败（恰好被别的 subagent 抢了）则继续找下一道。

### 4.2 单题攻克流程

**单点攻克**：每个 subagent 一次只做一题，做完（ready）或挂起后再取下一题（若被派发时只给一题，则做完即汇报返回）。

1. 读 `problem.md`（如是接手的题，先读 `attempts.md`）。
2. 按 §5 选算法，按 §6 编码，按 §7 写 test.sh 跑全部样例。
3. **难题加强项**：难题在样例通过后，默认再写暴力解 + 数据生成器对拍（§9 WA 流程前置），对拍 200+ 组无差异才算过。
4. 过样例后逐项核对 §8 检查清单。
5. 全部通过 → `echo ready > status`，向主 Claude 汇报（给出 solution.cpp 路径），由主 Claude **通知用户提交**。
6. 卡壳超过止损线（约 30~40 分钟）或同一思路连续两次失败 → 写 attempts.md → `suspend` → 汇报挂起原因后返回。

### 4.3 收尾（相遇 / 队列取空后）

当 queue.md 中已没有可认领的新题：

- 主 Claude 扫描所有 status 为 `suspended` / `wa` / `tle` / `mle` / `re` 且无 `.claim/` 的题，按"预估最有希望解出"排序，**再派新的 subagent 接手**（接手 = 重新 claim）。接手的 subagent **先读 attempts.md**，避免重走死路；倾向换思路而非修补旧代码。
- 用户反馈某题结果后：AC → 主 Claude `echo ac > status`；未过 → 写入对应状态（wa/tle/mle/re），按 §9 派 subagent 纠错。
- 全部题目 `ac` 或再无可推进的题 → 主 Claude 汇总战报：每题状态、用时、未解出题目的卡点分析。

## 5. 算法选择

根据数据范围选择合适的算法复杂度，这是避免 TLE 的第一道防线：

| 数据规模 N | 目标复杂度 | 典型算法 |
|---|---|---|
| N <= 10 | O(N!) | 全排列、暴搜 |
| N <= 20 | O(2^N) | 状压 DP、折半搜索 |
| N <= 500 | O(N^3) | Floyd、区间 DP |
| N <= 5000 | O(N^2) | 朴素 DP、枚举 |
| N <= 10^5 | O(N log N) | 排序、线段树、二分 |
| N <= 10^6 | O(N) | 双指针、单调栈/队列 |
| N <= 10^9 | O(log N) / O(sqrt N) | 二分答案、数学 |

## 6. 编码规范（判题机为 GCC 4.8.4 —— 不是现代编译器）

> **这是最容易白丢一次提交的地方。** 判题机是 **GCC 4.8.4**（2014 年），本地机器是 GCC 16。
> 按现代 C++ 写完本地编译通过、交上去 CE，是这个 skill 已经踩过的坑。

目标方言：**`-std=c++11`**（4.8.4 对 C++11 支持完整）。文件头：

```cpp
#pragma GCC optimize("O3,unroll-loops")   // 4.8.4 支持
#include <bits/stdc++.h>                  // 4.8.4 支持
using namespace std;

int main() {
    ios::sync_with_stdio(false);
    cin.tie(nullptr);
    // ...
}
```

### 禁用清单（C++14/17/20 特性，在 4.8.4 上一律 CE）

| 禁用 | 改写为 |
|---|---|
| 结构化绑定 `auto [x,y] = p;` | `int x = p.first, y = p.second;` |
| `std::gcd` / `std::lcm` | `__gcd(a,b)` |
| `std::optional` / `string_view` / `variant` / `any` | 手写等价物 |
| `std::clamp` | `max(lo, min(hi, x))` |
| `std::size(v)` | `v.size()` |
| 泛型 lambda `[](auto x){}` | 写死具体类型 |
| `if constexpr` / `if (init; cond)` | 拆成两句 |
| `std::make_unique` | `unique_ptr<T>(new T(...))` |
| 数字分隔符 `1'000'000` | `1000000` |
| `emplace_back` 的返回值 | C++11 里返回 `void`，别接收 |

### 4.8.4 的标准库地雷（能编译，但行为错误）

- **`std::regex` 在 4.8 是残缺实现**：能通过编译，运行时抛异常或静默匹配失败。**绝对不要用**，改手写解析。
- `std::to_string` / `std::stoi` / `unordered_map` / `array` / `tuple` / `mt19937` 均**可用**（C++11 特性）。

### 语言档歧义（重要）

该 OJ **有多个语言档**，其中一档是 **C++98**（默认 `-std=gnu++98`）。若 CE 信息里出现
`expected unqualified-id before '['`、`no matching function ... push_back(<brace-enclosed initializer list>)`，
说明提交进了 C++98 档。两种处理：**(a)** 改选 C++11 档重交；**(b)** 把代码降到 C++98 兼容 ——
`cin.tie(0)`、`vector<vector<int> >`（`>` 之间**必须**加空格）、`push_back(make_pair(x,y))`、
禁 `auto`/范围 for/lambda/`nullptr`/`unordered_map`。

> 想一劳永逸免疫，就写**同时通过 `-std=gnu++98` 和 `-std=c++11`** 的代码，代价只是放弃 `auto` 和范围 for。

### 提交前必须本地验证方言

```bash
# 快速档：本地 GCC 拦住语法层面的问题
g++ -O2 -std=c++11 -pedantic -Wall -Wextra -o solution solution.cpp

# 精确档（推荐，podman 已装）：真·GCC 4.8，连标准库差异一起复现
podman run --rm -v "$PWD":/w -w /w docker.io/library/gcc:4.8 \
    g++ -O2 -std=c++11 -Wall -o solution solution.cpp
```

本地 GCC 16 的 `-std=c++11` **只能挡语法**，挡不住 4.8 的库缺陷（如上述 regex）。
用到任何冷门标准库设施时，走 podman 精确档。

**其他注意事项：**
- 优先使用 `int` / `long long` 而非 `unsigned`，避免隐式转换陷阱。
- 数组开大 +5 的余量防止越界。
- 多组测试数据时注意初始化/清空状态。

## 7. 自动化测试

为每道题编写 `test.sh`，实现一键编译 + 运行 + 比对：

```bash
#!/bin/bash
set -e
g++ -O2 -std=c++11 -pedantic -Wall -o solution solution.cpp   # 判题机 GCC 4.8.4，见 §6
for i in *.in; do
    expected="${i%.in}.out"
    actual=$(timeout 3s ./solution < "$i")
    if diff -q <(echo "$actual") "$expected" > /dev/null 2>&1; then
        echo "PASS: $i"
    else
        echo "FAIL: $i"
        diff <(echo "$actual") "$expected"
    fi
done
```

样例已在解析阶段保存为 `1.in` / `1.out` 等，执行 `bash test.sh` 验证。

## 8. 提交前必看的避坑与检查清单 (Pre-submission Checklist)

通过样例测试后、写入 `ready` 状态前，**必须逐一核对以下检查点**，确保首发即 AC，避免罚时（ACM 规则一次错误提交 +20 分钟，CF 规则直接扣分）：

- [ ] **数据范围与整型溢出**：
  - 检查题目中最大可能的结果或累加过程是否会超过 `int` 的范围（约 2e9）。如果可能，必须使用 `long long`。
  - 特别注意：两个 `int` 相乘（如 `a * b`）可能在乘法过程中溢出，需要强制转换 `1LL * a * b`。
- [ ] **多组测试数据初始化**：
  - 题目是否包含多组测试数据（如输入第一行是 T）？如果是，**每次循环必须彻底初始化所有全局变量、数组、容器、图的邻接表**。
- [ ] **边界情况与特判**：
  - 极小值：N = 0, 1 或空输入时，是否会数组越界、除以零、死循环或输出错误？
  - 极大值：数组大小是否**至少**是最大 N + 5？多维数组是否会超出内存限制？
- [ ] **时间与空间限制估算**：
  - 复杂度乘以常数是否在时间限制（通常 1s 约 1e8 次基本运算）安全线内？
  - 不要在局部栈中分配巨大数组，应放到全局或使用 `vector`。
- [ ] **编译方言（判题机 GCC 4.8.4，见 §6）**：
  - 代码里有没有结构化绑定、`std::gcd`、`std::optional`、泛型 lambda、`if constexpr`、数字分隔符等 C++14/17/20 特性？有就会 CE。
  - 有没有用 `std::regex`？4.8 的实现是残缺的，能编译但运行错误。
  - **实际用 `-std=c++11 -pedantic` 编译过一遍**，而不是只用本地默认的现代方言编过。
- [ ] **输入输出格式**：
  - 严格核对空格、换行、大小写（如 `YES` / `Yes` / `yes`）。
  - 删除遗留的调试输出。

## 9. 纠错流程

收到 WA / TLE / MLE / RE 反馈时，按对应策略处理：

### WA - 答案错误

1. 编写暴力解 `brute.cpp`（正确性优先，不考虑效率）。
2. 编写数据生成器 `gen.cpp`，产出随机小规模数据。
3. 对拍脚本循环运行，找到第一组使两个解输出不同的数据：
   ```bash
   for ((i=1; ; i++)); do
       ./gen $i > test_in.txt
       ans1=$(./solution < test_in.txt)
       ans2=$(./brute < test_in.txt)
       if [ "$ans1" != "$ans2" ]; then
           echo "DIFF on seed $i"; cat test_in.txt
           echo "solution: $ans1"; echo "brute: $ans2"; break
       fi
   done
   ```
4. 用找到的数据调试，定位逻辑错误。

### TLE - 超时

1. 生成最大规模数据（`gen.cpp` 按题目上界生成）。
2. 本地计时：`/usr/bin/time -v ./solution < max_in.txt`
3. 优化方向：
   - 算法降阶（换更优复杂度的方案）
   - 减少常数：`__builtin_popcount`、位运算替代、cache-friendly 访存
   - 避免 `map`/`set`，改用 `unordered_map` 或数组
4. 优化后重新计时，确认耗时明显下降再提交。

### MLE - 超内存

- 滚动数组压缩 DP 维度。
- `short` / `bitset` 替代 `int` / `bool[]`。
- 邻接表代替邻接矩阵。

### RE - 运行错误

- 检查数组越界、栈溢出（递归深度）、除以零。
- 大数组放全局避免栈空间不足。

## 10. 工具速查

| 用途 | 命令 |
|---|---|
| 编译（本地快速档） | `g++ -O2 -std=c++11 -pedantic -Wall solution.cpp -o solution` |
| 编译（复现判题机 GCC 4.8） | `podman run --rm -v "$PWD":/w -w /w docker.io/library/gcc:4.8 g++ -O2 -std=c++11 -o solution solution.cpp` |
| 预压题面截图（IM7） | `magick mogrify -resize 55% -quality 80 *.png` |
| 计时 | `/usr/bin/time -v ./solution < input.txt` |
| 超时保护 | `timeout 3s ./solution < input.txt` |
| 对拍 | `diff <(./solution < t.txt) <(./brute < t.txt)` |
| 认领题目 | `mkdir oj_tasks/X/.claim`（成功=认领到） |
| 查看战况 | `for d in oj_tasks/*/; do echo "$d: $(cat $d/status 2>/dev/null) [$(cat $d/.claim/owner 2>/dev/null)]"; done` |
