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

# --- 3. 处理逻辑 ---
echo "[INFO] Processing Rules..."

for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    yaml_file="${dir}${name}.yaml"
    [ ! -f "$yaml_file" ] && continue

    # 针对 Apple 和 ChinaMax 开启地毯式日志
    is_debug=false
    if [[ "$name" == "Apple" || "$name" == "ChinaMax" ]]; then
        is_debug=true
    fi

    if [ "$is_debug" = true ]; then
        echo -e "\n--- DEBUG START: $name ---"
        echo "[LOG 1: Source File Path]: $yaml_file"
        echo "[LOG 2: Raw Sample (First 5 payload lines)]:"
        grep -A 5 "payload:" "$yaml_file"
    fi

    mkdir -p "tmp_work/$name"

    # 【提取逻辑】
    # 逻辑：找包含关键字的行 -> 排除注释 -> 删掉行首缩进 -> 删掉所有空格 -> 切分
    extract_with_log() {
        local key=$1
        local raw_grep=$(grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" | grep -v '^[[:space:]]*#' | head -n 3)
        
        if [ "$is_debug" = true ] && [ -n "$raw_grep" ]; then
            echo "[LOG 3: Grep Match for $key]: $raw_grep"
        fi

        # 核心提取
        grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" | \
        grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]-]*//' | \
        sed 's/[[:space:]]//g' | \
        cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 | \
        sort -u | sed '/^$/d' > "tmp_work/$name/$2.txt"

        if [ "$is_debug" = true ]; then
            echo "[LOG 4: Final Extracted for $key (Head 3)]: $(head -n 3 "tmp_work/$name/$2.txt")"
        fi
    }

    extract_with_log "DOMAIN-SUFFIX" "suffix"
    extract_with_log "DOMAIN" "domain"
    extract_with_log "DOMAIN-KEYWORD" "keyword"
    extract_with_log "IP-CIDR|IP-CIDR6" "ipcidr"

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
                echo "[LOG 5: JSON Preview]: $(head -c 200 "$out")..."
            fi

            ./sing-box rule-set compile "$out" -o "${out%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    if build_json "all" "${name}.json"; then
        echo "[RESULT] $name: SUCCESS"
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    else
        echo "[RESULT] $name: FAILED (Empty fields)"
    fi
    
    [ "$is_debug" = true ] && echo "--- DEBUG END: $name ---"
done

# 注意：为了让你能查看到 tmp_work 里的 txt，我这次注释掉 rm tmp_work
# rm -rf tmp_work 2>/dev/null

echo -e "\n[FINISH] All tasks completed."
exit 0
