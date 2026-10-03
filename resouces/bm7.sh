#!/bin/bash
set +e

# --- 1. 配置开关 ---
is_debug=false # 已关闭。如需排查，请手动改为 true

# --- 2. 环境初始化 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null
mkdir -p rule/Clash

# --- 3. 资源同步 ---
[ "$is_debug" = true ] && echo "[LOG] Fetching resources..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：BM7 Classical 文件预处理（确保主规则不被下划线逻辑过滤）
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c")
    base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 4. 核心处理逻辑 ---
[ "$is_debug" = true ] && echo "[INFO] Processing Rules..."

# 递归寻找所有 .yaml 文件
find ./rule/Clash -type f -name "*.yaml" | while read yaml_file; do
    file_full_name=$(basename "$yaml_file")
    name="${file_full_name%.*}"

    # 【最源头过滤】：直接忽略带 No_Resolve 或 NoResolve 的文件
    if [[ "$name" == *"No_Resolve"* ]] || [[ "$name" == *"NoResolve"* ]]; then
        [ "$is_debug" = true ] && echo "[LOG: SKIP] Skipping No_Resolve variant: $file_full_name"
        continue
    fi

    # 【处理逻辑】
    # 将带下划线的文件名去除下划线 (例如 A_1 转换为 A1)
    if [[ "$name" == *"_"* ]]; then
        name="${name//_/}"
        [ "$is_debug" = true ] && echo "[LOG: RENAME] Variant detected: $file_full_name -> processing as $name"
    fi

    # 忽略非规则文件
    [[ "$name" == "config" ]] && continue

    [ "$is_debug" = true ] && echo -e "\n--- DEBUG START: $name ---"

    mkdir -p "tmp_work/$name"

    # 【精准提取函数】
    extract_final() {
        local key=$1
        local file_out="tmp_work/$name/$2.txt"

        # 逻辑：匹配行首 -> 排除注释行 -> 删缩进 -> 删空格 -> 切分取值 -> 删行尾注释
        grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" |
            grep -v '^[[:space:]]*#' |
            sed 's/^[[:space:]-]*//' |
            sed 's/[[:space:]]//g' |
            cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 |
            sort -u | sed '/^$/d' >"$file_out"
    }

    extract_final "DOMAIN-SUFFIX" "suffix"
    extract_final "DOMAIN" "domain"
    extract_final "DOMAIN-KEYWORD" "keyword"
    extract_final "IP-CIDR|IP-CIDR6" "ipcidr"

    # 【JSON & SRS 构建】
    build_json() {
        local mode=$1
        local out_name=$2
        local fields=()
        gen_box() {
            if [ -s "tmp_work/$name/$1.txt" ]; then
                local items=$(cat "tmp_work/$name/$1.txt" | sed 's/.*/"&"/' | paste -sd, -)
                echo "\"$2\":[$items]"
            fi
        }

        s=$(gen_box "suffix" "domain_suffix")
        [ -n "$s" ] && fields+=("$s")
        d=$(gen_box "domain" "domain")
        [ -n "$d" ] && fields+=("$d")
        k=$(gen_box "keyword" "domain_keyword")
        [ -n "$k" ] && fields+=("$k")
        [ "$mode" == "all" ] && {
            i=$(gen_box "ipcidr" "ip_cidr")
            [ -n "$i" ] && fields+=("$i")
        }

        if [ ${#fields[@]} -gt 0 ]; then
            # 钉死 version: 4
            echo -n '{"version":4,"rules":[{' >"$out_name"
            (
                IFS=,
                echo -n "${fields[*]}"
            ) >>"$out_name"
            echo '}]}' >>"$out_name"

            ./sing-box rule-set compile "$out_name" -o "${out_name%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    if build_json "all" "${name}.json"; then
        [ "$is_debug" = true ] && echo "[RESULT] $name: SUCCESS."
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi

    [ "$is_debug" = true ] && echo "[INFO] --- DEBUG END: $name ---"
done

# --- 4.5 特殊规则处理 (AdGuard + Turtlecute + AWAvenue) ---
[ "$is_debug" = true ] && echo "[INFO] Processing AdGuard special rule..."
wget -q -O adg.txt https://raw.githubusercontent.com/ppfeufer/adguard-filter-list/refs/heads/master/blocklist
wget -q -O turtle.txt https://raw.githubusercontent.com/Turtlecute33/Toolz/master/src/d3host.adblock
wget -q -O awavenue.txt https://raw.githubusercontent.com/TG-Twilight/AWAvenue-Ads-Rule/main/AWAvenue-Ads-Rule.txt

if [ -f "adg.txt" ]; then
    # 将 Turtlecute 与 AWAvenue 列表合并到 adg.txt，并去重（保留原始顺序,空行剔除）
    tmp_merge="adg_merge.tmp"
    cat adg.txt \
        $( [ -f "turtle.txt" ] && echo "turtle.txt" ) \
        $( [ -f "awavenue.txt" ] && echo "awavenue.txt" ) \
        | sed '/^[[:space:]]*$/d' \
        | awk '!seen[$0]++' >"$tmp_merge"
    mv -f "$tmp_merge" adg.txt

    ./sing-box rule-set convert --type adguard --output adg.srs adg.txt &>/dev/null
    [ "$is_debug" = true ] && echo "[RESULT] adg.srs: SUCCESS."
fi

# --- 4.6 Claude 规则追加 claude.com ---
[ "$is_debug" = true ] && echo "[INFO] Patching Claude rule with claude.com..."
for f in Claude.json Claude-Resolve.json; do
    if [ -f "$f" ]; then
        jq -c '.rules[0].domain_suffix = ((.rules[0].domain_suffix // []) + (["claude.com"] - (.rules[0].domain_suffix // [])))' "$f" > "${f}.tmp" \
            && mv -f "${f}.tmp" "$f"
        ./sing-box rule-set compile "$f" -o "${f%.json}.srs" &>/dev/null
        [ "$is_debug" = true ] && echo "[RESULT] $f patched and recompiled."
    fi
done

# --- 4.7 Telegram 分区域 IP 规则合并 (SG / US / EU->NL) ---
# 规则：自定义列表与现有 TelegramSG / TelegramUS / TelegramNL 合并；
#       若同一 CIDR 在自定义列表中归属某区域，则从其他区域的现有规则里剔除（以自定义为准）。
[ "$is_debug" = true ] && echo "[INFO] Merging Telegram regional IP rules..."

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
        ' "$f" >"${f}.tmp" && mv -f "${f}.tmp" "$f"
    else
        jq -c . <<<"$2" >"$f"
    fi

    ./sing-box rule-set compile "$f" -o "${f%.json}.srs" &>/dev/null
    [ "$is_debug" = true ] && echo "[RESULT] $f merged and recompiled."
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