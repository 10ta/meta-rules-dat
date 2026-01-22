#!/bin/bash
set +e

# --- 1. 初始化 ---
is_debug=true
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null
mkdir -p rule/Clash

# --- 2. 资源同步 ---
[ "$is_debug" = true ] && echo "[LOG] Fetching resources..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：Classical 转 .yaml
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c"); base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖 (包含多级目录和多文件)
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 3. 处理逻辑 (以 YAML 文件为核心) ---
echo "[INFO] Processing Rules..."

# 递归寻找所有 .yaml 文件
find ./rule/Clash -type f -name "*.yaml" | while read yaml_file; do
    # 获取文件名（不含路径和后缀）作为规则名
    file_full_name=$(basename "$yaml_file")
    name="${file_full_name%.*}"
    
    # 排除一些明显的非规则文件
    [[ "$name" == "config" || "$name" == "README" ]] && continue
    # 排除小于 10 字节的文件
    [ $(stat -c%s "$yaml_file") -lt 10 ] && continue

    if [ "$is_debug" = true ]; then
        echo -e "\n--- DEBUG START: $name ---"
        echo "[LOG 1: File Path]: $yaml_file"
    fi

    mkdir -p "tmp_work/$name"

    # 【提取逻辑】
    extract_with_log() {
        local key=$1
        local file_out="tmp_work/$name/$2.txt"
        
        # 提取：匹配行首关键字 -> 删行首缩进 -> 删空格 -> 处理参数和注释
        grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" | \
        grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]-]*//' | \
        sed 's/[[:space:]]//g' | \
        cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 | \
        sort -u | sed '/^$/d' > "$file_out"

        if [ "$is_debug" = true ] && [ -s "$file_out" ]; then
            echo "[LOG 2: $key]: Found $(wc -l < "$file_out") items."
        fi
    }

    extract_with_log "DOMAIN-SUFFIX" "suffix"
    extract_with_log "DOMAIN" "domain"
    extract_with_log "DOMAIN-KEYWORD" "keyword"
    extract_with_log "IP-CIDR|IP-CIDR6" "ipcidr"

    build_json() {
        local mode=$1; local out_name=$2; local fields=()
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
            # 钉死 version: 2
            echo -n '{"version":2,"rules":[{' > "$out_name"
            (IFS=,; echo -n "${fields[*]}") >> "$out_name"
            echo '}]}' >> "$out_name"

            if [ "$is_debug" = true ] && [ "$mode" == "all" ]; then
                echo "[LOG 3: JSON Head]: $(head -c 100 "$out_name")..."
            fi

            ./sing-box rule-set compile "$out_name" -o "${out_name%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    # 执行生成
    if build_json "all" "${name}.json"; then
        [ "$is_debug" = true ] && echo "[RESULT] $name: SUCCESS."
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi
    
    [ "$is_debug" = true ] && echo "--- DEBUG END: $name ---"
done

# 依然保留 tmp_work 供你检查
# rm -rf tmp_work 2>/dev/null

echo -e "\n------------------------------------------------"
echo "[FINISH] Generated SRS files based on all YAML files."
exit 0
