#!/bin/bash
# bm7.sh — 把 blackmatrix7/ios_rule_script (+ Accademia 覆盖) 的 Clash 规则转成 sing-box 规则集 (.json / .srs)
# 依赖：当前目录下有可执行的 ./sing-box；系统有 git curl jq python3 xargs
set +e

# --- 1. 配置开关 ---
is_debug=false # 已关闭。如需排查，请手动改为 true
MIN_RULES=${MIN_RULES:-300}     # 生成的 .json 少于该数量，视为上游抓取/解析失败
MAX_FAIL_PCT=${MAX_FAIL_PCT:-2} # 编译失败的文件占比超过该百分比，视为失败
JOBS=${JOBS:-$(nproc 2>/dev/null || echo 2)}

die() {
    echo "::error::$*"
    exit 1
}
warn() { echo "::warning::$*"; }
log() {
    [ "$is_debug" = true ] && echo "$@"
    return 0
}
# 带重试的下载；失败时不留下半截文件
dl() {
    curl -fsSL --retry 3 --retry-all-errors --connect-timeout 10 -o "$2" "$1" || {
        rm -f "$2"
        return 1
    }
}
compile_one() { ./sing-box rule-set compile "$1" -o "${1%.json}.srs" >/dev/null 2>&1; }

work=$(mktemp -d) || die "mktemp 失败"
trap 'rm -rf "$work"' EXIT

{ [ -x ./sing-box ] && ./sing-box version >/dev/null 2>&1; } || die "当前目录缺少可执行的 sing-box"

# --- 2. 环境初始化 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work git_temp acca_temp 2>/dev/null
mkdir -p rule/Clash

# 并行预取 AdGuard 相关列表（第 4.5 段才使用）
dl "https://raw.githubusercontent.com/ppfeufer/adguard-filter-list/refs/heads/master/blocklist" adg.txt &
pid_adg=$!
dl "https://raw.githubusercontent.com/Turtlecute33/Toolz/master/src/d3host.adblock" turtle.txt &
pid_turtle=$!
dl "https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt" awavenue.txt &
pid_awa=$!

# --- 3. 资源同步 ---
log "[LOG] Fetching resources..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null &
pid_acca=$!

# 只需要 rule/Clash：稀疏 + 部分克隆；失败则退回普通浅克隆
if ! {
    git clone --depth 1 --filter=blob:none --sparse https://github.com/blackmatrix7/ios_rule_script.git git_temp &&
        git -C git_temp sparse-checkout set rule/Clash
} &>/dev/null; then
    rm -rf git_temp
    git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
fi
[ -d git_temp/rule/Clash ] || die "获取 blackmatrix7/ios_rule_script 失败"
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：BM7 Classical 文件预处理（确保主规则不被下划线逻辑过滤）
while IFS= read -r -d '' c; do
    dir=${c%/*}
    base=${dir##*/}
    mv -f "$c" "$dir/$base.yaml"
done < <(find ./rule/Clash/ -type f -name '*_Classical.yaml' -print0)

# Accademia 覆盖
wait "$pid_acca"
[ -d acca_temp ] || die "获取 Accademia/Additional_Rule_For_Clash 失败（不发布缺少覆盖规则的结果）"
cp -af ./acca_temp/* rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 4. 核心处理逻辑 ---
# 一次 Python 进程完成：遍历 yaml → 提取 → 生成 json（逻辑与原 shell 版逐条对应，见注释）
log "[INFO] Processing Rules..."
find ./rule/Clash -type f -name '*.yaml' -print0 >"$work/yaml.list"

python3 - "$work/yaml.list" "$work" "$is_debug" <<'PY' || die "规则解析失败"
import json
import os
import re
import sys

list_file, work, debug = sys.argv[1], sys.argv[2], sys.argv[3] == "true"

# 原：grep -iE "^[[:space:]]*- KEY([[:space:]]*,|$)"（KEY 之后只能是空白+逗号 或 行尾）
LINE = re.compile(
    rb"^[ \t\r\f\v]*- (DOMAIN-SUFFIX|DOMAIN-KEYWORD|DOMAIN|IP-CIDR6|IP-CIDR)[ \t\r\f\v]*(?:,|$)",
    re.I,
)
LEAD = re.compile(rb"^[\s-]*")  # 原：sed 's/^[[:space:]-]*//'
WS = re.compile(rb"\s")  # 原：sed 's/[[:space:]]//g'
FIELD = {
    b"DOMAIN-SUFFIX": "suffix",
    b"DOMAIN": "domain",
    b"DOMAIN-KEYWORD": "keyword",
    b"IP-CIDR": "ip",
    b"IP-CIDR6": "ip",
}


def quote(v):
    return json.dumps(v.decode("utf-8", "replace"), ensure_ascii=False)


def render(fields):
    body = ",".join(
        '"%s":[%s]' % (k, ",".join(quote(x) for x in vals)) for k, vals in fields
    )
    return '{"version":4,"rules":[{' + body + "}]}\n"  # 钉死 version: 4


with open(list_file, "rb") as f:
    paths = [p for p in f.read().split(b"\0") if p]

files = {}  # 文件名 -> 内容；与原脚本一样，同名时后处理的覆盖先处理的
n_skip = 0
for p in paths:
    base = os.path.basename(p).decode("utf-8", "surrogateescape")
    name = base[: base.rindex(".")]

    # 最源头过滤：忽略 No_Resolve / NoResolve 变体
    if "No_Resolve" in name or "NoResolve" in name:
        n_skip += 1
        if debug:
            print("[LOG: SKIP] Skipping No_Resolve variant: %s" % base)
        continue
    # 带下划线的文件名去除下划线 (A_1 -> A1)
    if "_" in name:
        if debug:
            print("[LOG: RENAME] Variant detected: %s -> processing as %s" % (base, name.replace("_", "")))
        name = name.replace("_", "")
    if name == "config":  # 忽略非规则文件
        continue

    sets = {"suffix": set(), "domain": set(), "keyword": set(), "ip": set()}
    with open(p, "rb") as fh:
        data = fh.read()
    for line in data.split(b"\n"):
        m = LINE.match(line)
        if not m:
            continue
        s = WS.sub(b"", LEAD.sub(b"", line, 1))
        parts = s.split(b",")
        # 原：cut -d',' -f2（无逗号时 cut 原样输出整行）| cut -d'#' -f1
        v = (parts[1] if len(parts) > 1 else s).split(b"#")[0]
        if v:
            sets[FIELD[m.group(1).upper()]].add(v)

    if debug:  # 保留与原版一致的调试产物 tmp_work/<name>/*.txt
        d = os.path.join("tmp_work", name)
        os.makedirs(d, exist_ok=True)
        for key, vals in sets.items():
            with open(os.path.join(d, key + ("cidr" if key == "ip" else "") + ".txt"), "wb") as fh:
                fh.write(b"".join(x + b"\n" for x in sorted(vals)))

    dom = [
        (k, sorted(sets[s]))
        for s, k in (("suffix", "domain_suffix"), ("domain", "domain"), ("keyword", "domain_keyword"))
        if sets[s]
    ]
    ip = [("ip_cidr", sorted(sets["ip"]))] if sets["ip"] else []
    if not dom and not ip:
        continue  # 原 build_json 返回 1：不写任何文件
    files[name + ".json"] = render(dom + ip)
    if dom:  # 原：仅当 all 构建成功才构建 Resolve，且 Resolve 只含域名类字段
        files[name + "-Resolve.json"] = render(dom)

compile_list, copies = [], []
for fn, content in files.items():
    with open(fn, "w", encoding="utf-8") as fh:
        fh.write(content)
    if fn.endswith("-Resolve.json") and files.get(fn[: -len("-Resolve.json")] + ".json") == content:
        # 没有 IP 段时 X-Resolve 与 X 内容完全相同：只编译一次，再复制 .srs
        copies.append((fn[: -len("-Resolve.json")] + ".srs", fn[: -len(".json")] + ".srs"))
    else:
        compile_list.append(fn)

with open(os.path.join(work, "compile.list"), "wb") as fh:
    fh.write(b"".join(x.encode("utf-8") + b"\0" for x in compile_list))
with open(os.path.join(work, "copies.list"), "w", encoding="utf-8") as fh:
    fh.write("".join("%s\t%s\n" % c for c in copies))

print("[INFO] yaml: %d, skipped: %d, json: %d, compile: %d, reuse: %d"
      % (len(paths), n_skip, len(files), len(compile_list), len(copies)))
PY

# 并行编译 .srs
: >"$work/compile_failed.list"
export work
xargs -0 -a "$work/compile.list" -P "$JOBS" -n 1 sh -c \
    './sing-box rule-set compile "$1" -o "${1%.json}.srs" >/dev/null 2>&1 || echo "$1" >>"$work/compile_failed.list"' _

while IFS=$'\t' read -r src dst; do
    if [ -s "$src" ]; then
        cp -f "$src" "$dst"
    else
        echo "${dst%.srs}.json" >>"$work/compile_failed.list"
    fi
done <"$work/copies.list"

total_json=$(find . -maxdepth 1 -name '*.json' | wc -l)
failed=$(wc -l <"$work/compile_failed.list")
log "[RESULT] json: $total_json, compile failed: $failed"
[ "$total_json" -ge "$MIN_RULES" ] || die "只生成了 $total_json 个规则（预期至少 $MIN_RULES），上游可能异常，终止发布"
if [ "$failed" -gt 0 ]; then
    warn "$failed 个规则集编译失败：$(head -n 20 "$work/compile_failed.list" | tr '\n' ' ')"
    [ $((failed * 100)) -le $((MAX_FAIL_PCT * total_json)) ] || die "编译失败占比过高（$failed / $total_json），终止发布"
fi

# --- 4.5 特殊规则处理 (AdGuard + Turtlecute + AWAvenue) ---
log "[INFO] Processing AdGuard special rule..."
wait "$pid_adg"
wait "$pid_turtle"
wait "$pid_awa"
[ -s adg.txt ] || die "adg.txt 下载失败或为空，终止发布"
[ -s turtle.txt ] || warn "turtle.txt 下载失败，本次不合并"
[ -s awavenue.txt ] || warn "awavenue.txt 下载失败，本次不合并"

# 将 Turtlecute 与 AWAvenue 列表合并到 adg.txt，并去重（保留原始顺序,空行剔除）
tmp_merge="adg_merge.tmp"
cat adg.txt \
    $([ -s turtle.txt ] && echo "turtle.txt") \
    $([ -s awavenue.txt ] && echo "awavenue.txt") |
    sed '/^[[:space:]]*$/d' |
    awk '!seen[$0]++' >"$tmp_merge"
mv -f "$tmp_merge" adg.txt

./sing-box rule-set convert --type adguard --output adg.srs adg.txt &>/dev/null
[ -s adg.srs ] || die "adg.srs 生成失败"
log "[RESULT] adg.srs: SUCCESS."

# --- 4.6 Claude 规则追加 claude.com ---
log "[INFO] Patching Claude rule with claude.com..."
for f in Claude.json Claude-Resolve.json; do
    if [ -f "$f" ]; then
        jq -c '.rules[0].domain_suffix = ((.rules[0].domain_suffix // []) + (["claude.com"] - (.rules[0].domain_suffix // [])))' "$f" >"${f}.tmp" &&
            mv -f "${f}.tmp" "$f" || die "$f 追加 claude.com 失败"
        compile_one "$f" || die "$f 重新编译失败"
        log "[RESULT] $f patched and recompiled."
    else
        warn "$f 不存在，未追加 claude.com（BM7 是否改名？）"
    fi
done

# --- 4.7 Telegram 分区域 IP 规则合并 (SG / US / EU->NL) ---
# 规则：自定义列表与现有 TelegramSG / TelegramUS / TelegramNL 合并；
#       若同一 CIDR 在自定义列表中归属某区域，则从其他区域的现有规则里剔除（以自定义为准）。
log "[INFO] Merging Telegram regional IP rules..."

# 以下三段即 sing-box 规则集源文件格式，可直接复制为 inline rule-set（取其中 rules 部分）或保存为 .json
TG_SG_RS='{
  "version": 4,
  "rules": [
    {
      "ip_cidr": [
        "91.108.16.0/22",
        "91.108.20.0/22",
        "91.108.56.0/23",
        "149.154.168.0/22",
        "2001:b28:f23c::/48",
        "2001:b28:f23f::/48"
      ]
    }
  ]
}'

TG_US_RS='{
  "version": 4,
  "rules": [
    {
      "ip_cidr": [
        "91.108.12.0/22",
        "149.154.172.0/22",
        "2001:b28:f23d::/48"
      ]
    }
  ]
}'

TG_EU_RS='{
  "version": 4,
  "rules": [
    {
      "ip_cidr": [
        "91.105.192.0/23",
        "91.108.4.0/22",
        "91.108.8.0/22",
        "91.108.58.0/23",
        "95.161.64.0/20",
        "149.154.160.0/21",
        "185.76.151.0/24",
        "2001:67c:4e8::/48",
        "2a0a:f280:203::/48"
      ]
    }
  ]
}'

# 所有自定义 CIDR 的并集（用于冲突剔除）
ALL_JSON=$(jq -c -n --argjson a "$TG_SG_RS" --argjson b "$TG_US_RS" --argjson c "$TG_EU_RS" \
    '[$a,$b,$c] | map(.rules[0].ip_cidr) | add')

# merge_tg <目标规则名> <自有规则集JSON>
merge_tg() {
    local target=$1
    local own
    own=$(jq -c '.rules[0].ip_cidr' <<<"$2")
    local f="${target}.json"

    if [ -f "$f" ]; then
        jq -c --argjson own "$own" --argjson all "$ALL_JSON" '
            .rules[0].ip_cidr = ((((.rules[0].ip_cidr // []) - $all) + $own) | unique)
        ' "$f" >"${f}.tmp" && mv -f "${f}.tmp" "$f" || die "$f 合并失败"
    else
        jq -c . <<<"$2" >"$f"
    fi

    compile_one "$f" || die "$f 重新编译失败"
    log "[RESULT] $f merged and recompiled."
}

merge_tg "TelegramSG" "$TG_SG_RS"
merge_tg "TelegramUS" "$TG_US_RS"
merge_tg "TelegramNL" "$TG_EU_RS"

# --- 5. 结尾清理 ---
if [ "$is_debug" = false ]; then
    rm -rf tmp_work 2>/dev/null
    rm -f adg.txt turtle.txt awavenue.txt 2>/dev/null
    echo "[INFO] Run complete. Cleanup finished."
else
    echo "[INFO] Debug mode on. tmp_work, adg.txt and turtle.txt preserved."
fi

echo "------------------------------------------------"
echo "[FINISH] All tasks completed successfully."
exit 0