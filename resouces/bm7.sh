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

# 规范化：BM7 的 Classical 文件通常带下划线，我们先把它改名，确保主规则不被过滤
# 注意：这一步只针对 BM7 原始目录下的 Classical
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c"); base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 3. 处理逻辑 (精准过滤版) ---
echo "[INFO] Processing Rules..."

# 递归寻找所有的 .yaml 文件
find ./rule/Clash -type f -name "*.yaml" | while read yaml_file; do
    file_full_name=$(basename "$yaml_file")
    name="${file_full_name%.*}"
    
    # 【过滤逻辑核心】
    # 1. 如果文件名包含下划线 "_", 视为变体文件，忽略。
    if [[ "$name" == *"_"* ]]; then
        [ "$is_debug" = true ] && echo "[LOG: SKIP] Skipping variant: $file_full_name"
        continue
    fi
    
    # 2. 忽略 config 等非规则文件
    [[ "$name" == "config" ]] && continue

    if [ "$is_debug" = true ]; then
        echo -e "\n--- DEBUG START: $name ---"
        echo "[LOG 1: Target File]: $yaml_file"
    fi

    mkdir -p "tmp_work/$name"

    # 【提取逻辑】
    extract_final() {
        local key=$1
        local file_out="tmp_work/$name/$2.txt"
        
        grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" | \
        grep -v '^[[:space:]]*#' | \
        sed 's/^[[:space:]-]*//' | \
        sed 's/[[:space:]]//g' | \
        cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 | \
        sort -u | sed '/^$/d' > "$file_out"
    }

    extract_final "DOMAIN-SUFFIX" "suffix"
    extract_final "DOMAIN" "domain"
    extract_final "DOMAIN-KEYWORD" "keyword"
    extract_final "IP-CIDR|IP-CIDR6" "ipcidr"

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
            echo -n '{"version":2,"rules":[{' > "$out_name"
            (IFS=,; echo -n "${fields[*]}") >> "$out_name"
            echo '}]}' >> "$out_name"

            ./sing-box rule-set compile "$out_name" -o "${out_name%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    # 执行生成
    if build_json "all" "${name}.json"; then
        [ "$is_debug" = true ] && echo "[RESULT] $name: Generated SUCCESS."
        # 生成对应的 Resolve 版
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi
    
    [ "$is_debug" = true ] && echo "--- DEBUG END: $name ---"
done

# 依然保留临时目录供你最后一次核对
# rm -rf tmp_work 2>/dev/null

echo -e "\n------------------------------------------------"
echo "[FINISH] Clean run complete. No underscored variants processed."
exit 0
