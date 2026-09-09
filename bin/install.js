#!/usr/bin/env node
// 把 skill/ 安装到 agent 的 skills 目录下，默认 ~/.agents/skills/report-web-dashboard，
// 并把 scripts/webui 链到 ~/.local/bin/webui 上（webui 是用户直接敲的全局命令，
// 不是只被 SKILL.md 用全路径调一下的辅助脚本）。

const fs = require("fs");
const os = require("os");
const path = require("path");

const SKILL_NAME = "report-web-dashboard";
const SRC = path.join(__dirname, "..", "skill");
const HOME = os.homedir();

const args = process.argv.slice(2);
const has = (f) => args.includes(f);

if (has("-h") || has("--help")) {
  console.log(`
report-web-dashboard-skill — 安装 report-web-dashboard skill + webui 命令

  npx github:Realtyxxx/report-web-dashboard-skill              # 装到 ~/.agents/skills/${SKILL_NAME}
  npx github:Realtyxxx/report-web-dashboard-skill --claude     # 装到 ~/.claude/skills/${SKILL_NAME}
  npx github:Realtyxxx/report-web-dashboard-skill --dir <路径> # 装到指定 skills 根目录
  npx github:Realtyxxx/report-web-dashboard-skill --force      # 覆盖已存在的 skill 安装目录
  npx github:Realtyxxx/report-web-dashboard-skill --force-link # 抢占已被别的东西占用的 ~/.local/bin/webui
  npx github:Realtyxxx/report-web-dashboard-skill --no-link    # 只装 skill，不往 PATH 上放 webui
  npx github:Realtyxxx/report-web-dashboard-skill --no-completion # 跳过 Zsh 补全链接
  npx github:Realtyxxx/report-web-dashboard-skill --completion-dir <路径> # 默认 ~/.zsh/completion

--force 只管 skill 目录，不会顺手覆盖 PATH 上不认识的 webui —— 那需要单独的
--force-link。重装 skill 是日常操作，抢占别人的命令不是。
`);
  process.exit(0);
}

let root = path.join(HOME, ".agents", "skills");
const dirIdx = args.indexOf("--dir");
if (dirIdx !== -1) {
  if (!args[dirIdx + 1]) {
    console.error("--dir 需要一个路径参数");
    process.exit(1);
  }
  root = path.resolve(args[dirIdx + 1]);
} else if (has("--claude")) {
  root = path.join(HOME, ".claude", "skills");
}

const completionIdx = args.indexOf("--completion-dir");
if (
  completionIdx !== -1 &&
  (!args[completionIdx + 1] || args[completionIdx + 1].startsWith("--"))
) {
  console.error("--completion-dir 需要一个路径参数");
  process.exit(1);
}
const completionDir =
  completionIdx === -1
    ? path.join(HOME, ".zsh", "completion")
    : path.resolve(args[completionIdx + 1]);

const dest = path.join(root, SKILL_NAME);

if (fs.existsSync(dest) && !has("--force")) {
  console.error(`已存在：${dest}`);
  console.error("要覆盖请加 --force（会先删除该目录）。");
  process.exit(1);
}

fs.rmSync(dest, { recursive: true, force: true });
fs.mkdirSync(root, { recursive: true });
fs.cpSync(SRC, dest, { recursive: true });

// npm 打包会丢掉执行位，装完必须补回来。
const webuiPath = path.join(dest, "scripts", "webui");
const serverShPath = path.join(dest, "scripts", "server.sh");
for (const p of [webuiPath, serverShPath]) {
  if (fs.existsSync(p)) fs.chmodSync(p, 0o755);
}

console.log(`已安装 ${SKILL_NAME} skill → ${dest}`);

// --------------------------------------------------------------------------
// 把 webui 放到 PATH 上
// --------------------------------------------------------------------------

if (has("--no-link")) {
  console.log(
    `已跳过 PATH 链接（--no-link）。要手动装：ln -s ${webuiPath} ~/.local/bin/webui`,
  );
} else {
  const binDir = path.join(HOME, ".local", "bin");
  const link = path.join(binDir, "webui");

  // 只有当现存的 webui 确实是某个 report-web-dashboard skill 里的那份时才敢直接替换；
  // 别的东西占了这个名字就停手，除非 --force。
  let safeToReplace = true;
  let existingDesc = null;
  if (fs.existsSync(link) || fs.lstatSync(link, { throwIfNoEntry: false })) {
    try {
      const resolved = fs.realpathSync(link);
      existingDesc = resolved;
      safeToReplace = resolved.split(path.sep).includes(SKILL_NAME);
    } catch {
      // 断掉的软链：realpath 失败，直接替换即可。
      existingDesc = "(broken symlink)";
      safeToReplace = true;
    }
  }

  // 注意：这里刻意不认 --force。--force 的语义是"覆盖 skill 安装目录"，
  // 是个日常操作；把 PATH 上一个不认识的 webui 顶掉是另一回事，风险高得多，
  // 必须单独表态。两者共用一个 flag 会让重装 skill 顺手打掉别人的命令。
  if (!safeToReplace && !has("--force-link")) {
    console.warn("");
    console.warn(`⚠ ${link} 已被别的东西占用：${existingDesc}`);
    console.warn(
      "  没有覆盖它。确认要顶掉它请加 --force-link，或者自己手动建链接：",
    );
    console.warn(`    ln -sf ${webuiPath} ${link}`);
  } else {
    fs.mkdirSync(binDir, { recursive: true });
    fs.rmSync(link, { force: true });
    fs.symlinkSync(webuiPath, link);
    console.log(`已链接 webui → ${link}`);

    if (!has("--no-completion")) {
      const completionSource = path.join(dest, "completions", "_webui");
      const completionLink = path.join(completionDir, "_webui");
      const existing = fs.lstatSync(completionLink, { throwIfNoEntry: false });
      let owned = !existing;
      if (existing?.isSymbolicLink()) {
        try {
          owned = fs
            .realpathSync(completionLink)
            .split(path.sep)
            .includes(SKILL_NAME);
        } catch (error) {
          if (error.code !== "ENOENT") throw error;
          owned = true;
        }
      }
      if (!owned && !has("--force-link")) {
        console.warn(
          `未覆盖已有补全：${completionLink}；确认接管请加 --force-link。`,
        );
      } else {
        fs.mkdirSync(completionDir, { recursive: true });
        if (existing) fs.unlinkSync(completionLink);
        fs.symlinkSync(completionSource, completionLink);
        console.log(`已链接 Zsh 补全 → ${completionLink}`);
        console.log(
          "新开 Zsh 终端生效；当前终端运行：autoload -Uz _webui; compdef _webui webui",
        );
        console.log(
          `若补全目录尚未加入 fpath，在 compinit 之前加入：fpath=(${JSON.stringify(completionDir)} $fpath)`,
        );
        console.log(
          "未启用 Zsh 补全系统时，继续运行：autoload -Uz compinit; compinit",
        );
      }
    }

    const onPath = (process.env.PATH || "")
      .split(path.delimiter)
      .includes(binDir);
    if (!onPath) {
      console.warn("");
      console.warn(
        `⚠ ${binDir} 不在你的 PATH 上，webui 敲不到。加一行到 shell rc：`,
      );
      console.warn(`    export PATH="${binDir}:$PATH"`);
    }
  }
}

// --------------------------------------------------------------------------
// 守护进程可能正跑着旧版本
// --------------------------------------------------------------------------

const pidFile = path.join(HOME, ".local", "state", "webui", "webui.pid");
if (fs.existsSync(pidFile)) {
  const pid = parseInt(fs.readFileSync(pidFile, "utf8").trim(), 10);
  let alive = false;
  if (Number.isInteger(pid)) {
    try {
      process.kill(pid, 0);
      alive = true;
    } catch {
      alive = false;
    }
  }
  if (alive) {
    console.log("");
    console.log(
      `⚠ webui 守护进程正跑着旧版本（pid ${pid}）。装完新版要重启才生效：`,
    );
    console.log("    webui restart");
  }
}

console.log("");
console.log("下一步：webui --help");
