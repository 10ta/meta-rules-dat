#!/bin/bash
set +e

# --- 1. 初始化 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null
mkdir -p rule/Clash

# --- 2. 资源同步 ---
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：Classical 转 .yaml
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c"); base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 3. 处理逻辑与节点日志 ---
echo "[INFO] Processing Rules..."

for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    yaml_file="${dir}${name}.yaml"
    [ ! -f "$yaml_file" ] && continue

    # 只针对 ChinaMax 和 Apple 开启深度节点日志，避免日志爆炸
    is_debug=false
    if [[ "$name" == "ChinaMax" || "$name" == "Apple" ]]; then
        is_debug=true
        echo "------------------------------------------------"
        echo "[NODE 1: SOURCE] $name file found at: $yaml_file"
        echo "HEAD CONTENT:"
        head -n 15 "$yaml_file"
        echo "..."
    fi

    mkdir -p "tmp_work/$name"

    # 提取逻辑：删行首缩进，删行内空格，保留横杠，去行尾注释
    extract_final() {
        grep "$1" "$yaml_file" | grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]-]*//' | sed 's/[[:space:]]//g' | \
        cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 | \
        sort -u | sed '/^$/d'
    }

    extract_final "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    extract_final "DOMAIN," > "tmp_work/$name/domain.txt"
    extract_final "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    extract_final "IP-CIDR|IP-CIDR6," > "tmp_work/$name/ipcidr.txt"

    if [ "$is_debug" = true ]; then
        echo "[NODE 2: EXTRACTED] After cleaning (domain.txt head):"
        head -n 5 "tmp_work/$name/domain.txt" 2>/dev/null || echo "Empty"
    fi

    build_json() {
        local mode=$1; local out=$2; local fields=()
        gen_box() {
            if [ -s "tmp_work/$name/$1.txt" ]; then
                local items=$(cat "tmp_work/$name/$1.txt" | sed 's/.*/"&"/' | paste -sd, -)
                echo "\"$2\":[$items]"
            fi
        }
        s=$(gen_box "suffix" "domain_suffix"); [ -n "$s" ] && fields+=("$s")
        d=$(gen_box "domain" "domain"); [ -n "$d" ] && fields+=("$d")
        k=$(gen_box "keyword" "domain_keyword"); [ -n "$k" ] && fields+=("$k")
        [ "$mode" == "all" ] && { i=$(gen_box "ipcidr" "ip_cidr"); [ -n "$i" ] && fields+=("$i"); }

        if [ ${#fields[@]} -gt 0 ]; then
            echo -n '{"version":2,"rules":[{' > "$out"
            (IFS=,; echo -n "${fields[*]}") >> "$out"
            echo '}]}' >> "$out"

            if [ "$is_debug" = true ] && [ "$mode" == "all" ]; then
                echo "[NODE 3: JSON] Generated $out (Head):"
                head -c 150 "$out" && echo "..."
            fi

            ./sing-box rule-set compile "$out" -o "${out%.json}.srs" &>/dev/null

            if [ "$is_debug" = true ] && [ "$mode" == "all" ]; then
                echo "[NODE 4: SRS] Compiled ${out%.json}.srs (File Size):"
                du -sh "${out%.json}.srs"
            fi
            return 0
        fi
        return 1
    }

    if build_json "all" "${name}.json"; then
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi
done

echo "------------------------------------------------"
echo "[FINISH] Task complete."
exit 0
