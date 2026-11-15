# AGENTS.md

本仓库的工作约定。**改脚本、改 CI、改文档前先读完这份。**

最后更新：2026-11-14（修复指南结项时整理）

---

## 一句话规则

**任何脚本改动，本地必须用 `bash -e` 验证，不能只用 `bash`。**

```bash
# ❌ 不够 —— 会漏掉 CI 的 errexit / pipefail 行为
bash scripts/test-cleanup.sh

# ✅ 和 CI 一致
bash -e scripts/test-cleanup.sh
```

CI 的 `shell: bash` 实际执行的是：

```
bash --noprofile --norc -e -o pipefail {0}
```

`-e`（errexit）和 `-o pipefail` 都会生效，即使脚本里写了 `set -uo pipefail`（没写 `-e`）也拦不住。

---

## 提交前检查清单

### 改脚本 / 改测试

- [ ] `bash -e <脚本>` 本地跑通（不是 `bash`）
- [ ] 如果脚本里调 `node`，Windows 上是否做了路径转换？见下文「路径」一节
- [ ] 如果脚本里用 `grep`，失败时会不会因 `pipefail` + `-e` 让整段退出？
- [ ] 如果脚本里用 `$!`，Windows Git Bash 上拿到的是 wrapper PID，不是真实 PID
- [ ] 如果脚本里用 `pkill -f`，会匹配到自己，导致自杀/死循环
- [ ] 如果脚本里有「预期失败」的命令，用 `set +e` / `set -e` 包住，或用 `|| true`

### 改 .ps1 文件

- [ ] 文件必须是 **UTF-8 with BOM**（`EF BB BF`）
  ```bash
  # 检查
  xxd -l 3 -p script.ps1     # 应输出 efbbbf
  # 加 BOM
  printf '\xef\xbb\xbf' | cat - script.ps1 > tmp && mv tmp script.ps1
  ```
  没有 BOM 时，Windows PowerShell 5.1 会按 ANSI(CP936) 解码，中文注释变乱码 → 引号配对错乱 → 语法错误。**本地用 `pwsh 7` 测不出来**（它默认 UTF-8）。

- [ ] 优先用 `pwsh`（PowerShell 7），回退到 `powershell`（5.1）
- [ ] 语法检查用 `[System.Management.Automation.Language.Parser]::ParseFile()`

### 改 .github/workflows/

- [ ] YAML 缩进：`paths:` 下的条目是 **6 空格**（不是 8）
  ```yaml
      paths:              # 4 空格
        - "install.sh"    # 6 空格 ← 容易写成 8
  ```
- [ ] 改完用 `ruby -ryaml -e 'YAML.load_file(".github/workflows/e2e.yml")'` 验证
- [ ] `shell: bash` 的 step 里，「预期失败」的命令必须 `set +e` 包住
- [ ] `if [ 条件 ]; then exit 1; fi` 而不是 `[ 条件 ] && exit 1`（后者在 `-e` 下会误退）
- [ ] 改 `on.push.paths` 后，确认新增的目录真的在里面，否则 CI 不会触发

### 改文档

- [ ] 文档引用的脚本 URL 是否固定在**包含最终版本**的 commit SHA？
  ```bash
  # 验证：文档引用的 SHA 是否包含 scripts/ 的最后一次修改
  # DOC_SHA 换成你文档里写的那个 40 位 SHA
  DOC_SHA=xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
  git merge-base --is-ancestor "$(git log -1 --format=%H -- scripts/)" "$DOC_SHA"
  ```
- [ ] 改完文档后，`scripts/` 没有新改动 → 文档 SHA 不用变
- [ ] 如果 `scripts/` 有新改动 → 文档 SHA 必须同步更新，否则用户下载的脚本 ≠ CI 验证的脚本
- [ ] 验证所有 URL 可访问（HTTP 200）

---

## 环境差异速查

本地（macOS）和 CI 的差异，每一条都真实踩过：

| # | 差异点 | 本地 | CI / Windows | 应对 |
|---|---|---|---|---|
| 1 | bash 选项 | `bash` | `bash -e -o pipefail` | 本地一律 `bash -e` |
| 2 | 哈希命令 | `md5 -q` | `sha256sum` / 无 | 写 `hash_file()` 按序回退 |
| 3 | `md5sum \| cut` 退出码 | — | 取 `cut` 的（0），`\|\|` 不触发 | 别用管道兜底，用 if 判断 |
| 4 | `ps -eo pid=,command=` | 支持 | Git Bash 不支持 | Windows 走 PowerShell |
| 5 | `$!` 的 PID | 真实 PID | **wrapper PID** | 从输出按路径反查 |
| 6 | `pkill -f "$路径"` | 会匹配自己 | 同 | 只用反查到的 PID |
| 7 | PowerShell 可执行文件 | `pwsh` | `powershell` 5.1 | 优先 `pwsh`，回退 `powershell` |
| 8 | `.ps1` 编码 | `pwsh` 默认 UTF-8 | PS 5.1 无 BOM 按 ANSI | **加 BOM** |
| 9 | 路径风格 | `/Users/...` | Git Bash `/d/a/...` 给原生工具要 `D:\a\...` | `cygpath -w` |
| 10 | YAML `paths:` 缩进 | — | — | 6 空格 |

---

## 路径转换：只在这一个边界做

**规则**：只有「Git Bash 调用原生 Windows 程序」时才需要转换。

```bash
# 变量命名区分用途
DSH="${DSH_HOME:-$HOME/.dsh}"     # 给 bash 的文件操作用（/tmp/xxx）
DSH_NODE="$DSH"                    # 给 node / powershell 用
case "$(uname -s 2>/dev/null)" in
  MINGW*|MSYS*|CYGWIN*)
    command -v cygpath >/dev/null 2>&1 && \
      DSH_NODE="$(cygpath -w "$DSH" 2>/dev/null)" || DSH_NODE="$DSH"
    ;;
esac
```

**macOS / Linux 上 `DSH_NODE === DSH`，行为完全不变。** 不要在非 Windows 分支做任何转换。

---

## 排查原则

### 第一件事：让错误原样透出

**不要**：

```bash
command 2>/dev/null                        # 错误被吞
head -40 file | sed 's/^/  /'              # 文件为空时什么都不显示
```

**要**：

```bash
OUT="$(command 2>&1)"; RC=$?
echo "退出码: $RC"
echo "输出: $OUT"
```

### 第二件事：`bash -x`

猜不出来时直接上 `bash -x`，它会打印每一行的执行过程：

```bash
bash -x script.sh 2>&1 | head -60
```

**实测：`bash -x` 一次性暴露了「`✗ package.json 解析失败`」，抵得上之前 4 轮加诊断的往返。**

### 第三件事：本地复现 CI

```bash
# YAML 的 run 块可以直接提取出来跑
ruby -ryaml -e '
d = YAML.load_file(".github/workflows/e2e.yml")
d["jobs"]["<job>"]["steps"].each do |s|
  if s["name"] == "<step名>"
    File.write("/tmp/step.sh", s["run"])
  end
end
'
bash -e /tmp/step.sh
```

---

## 禁止事项

- ❌ 在承载当前会话的机器上跑 `pkill -f "dsh"` / `kill <DSH进程>` —— 会杀掉自己，任务中断
- ❌ 在测试脚本里调 `list-dsh-procs.sh --kill` —— 同上
- ❌ 用 `git push -f` 覆盖 `main` / `master`
- ❌ 文档引用 `master` 分支做脚本 URL —— 必须固定到 commit SHA
- ❌ 在 `.ps1` 里写中文但不加 BOM

---

## 相关文档

- `docs/开发笔记-跨平台脚本测试.md` —— 本清单的完整版，含 9 个真实故障的复现和修法
- `scripts/test-cleanup.sh` —— 清理逻辑回归测试，22 项断言
- `scripts/check-scripts.mjs` —— 静态检查（变量边界 / `--force` / 版本一致性）
- `.github/workflows/e2e.yml` —— CI 定义，`cleanup-tests` job 是跨平台测试的范例
