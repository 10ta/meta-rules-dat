#!/bin/bash

# --- 1. 环境清理 ---
rm -rf rule acca_temp tmp_work *.json *.srs
mkdir -p rule/Clash

# --- 2. 拉取 Blackmatrix (基础库) ---
echo "[INFO] Cloning Blackmatrix..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# --- 3. 规范化 Blackmatrix (前置 Classical 处理) ---
echo "[INFO] Normalizing Blackmatrix..."
for dir in ./rule/Clash/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    # 如果有 Classical，先转成标准名，准备迎接 Accademia 的覆盖
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# --- 4. 拉取 Accademia 并覆盖 ---
echo "[INFO] Fetching Accademia rules..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp

echo "----------------------------------------------------------------"
echo "[DEBUG NODE 1] Accademia Overriding Process:"
for acca_dir in ./acca_temp/*/; do
    [ -d "$acca_dir" ] || continue
    dir_name=$(basename "$acca_dir")
    mkdir -p "./rule/Clash/$dir_name"
    # 强制覆盖：Accademia 的内容会替换掉同名的 Blackmatrix 文件
    cp -afv "$acca_dir". "./rule/Clash/$dir_name/" | sed 's/^/  /'
done
echo "----------------------------------------------------------------"
rm -rf acca_temp

# --- 5. 核心处理函数 (锁定 foo/foo.yaml 逻辑) ---
process_rules() {
    local name=$1
    local dir=$2
    local output=$3
    local is_resolve=$4

    # 锁定唯一主文件：foo/foo.yaml
    # 此时的 foo.yaml 如果被 Accademia 覆盖了，就是 Accademia 的内容
    local yaml_file="${dir}/${name}.yaml"

    # 如果主文件不存在，则直接退出
    if [ ! -f "$yaml_file" ]; then
        return 1
    fi

    # 调试监控 NODE 2
    if [ "$name" == "Apple" ] || [ "$name" == "apple" ]; then
        echo "----------------------------------------------------------------"
        echo "[DEBUG NODE 2] File content of $yaml_file (Top 20 lines):"
        head -n 20 "$yaml_file"
        echo "----------------------------------------------------------------"
    fi

    local work_dir="tmp_work/$name"
    mkdir -p "$work_dir"

    # 提取逻辑 (只针对单一 yaml_file)
    sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/suffix.txt"
    sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/domain.txt"
    sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/keyword.txt"
    
    if [ "$is_resolve" = "false" ]; then
        grep 'IP-CIDR' "$yaml_file" | sed -n 's/.*IP-CIDR[6]*,\([^, #]*\).*/\1/p' | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/ipcidr.txt"
    fi

    # 判空
    if [ ! -s "$work_dir/suffix.txt" ] && [ ! -s "$work_dir/domain.txt" ] && \
       [ ! -s "$work_dir/keyword.txt" ] && [ ! -s "$work_dir/ipcidr.txt" ]; then
        rm -rf "$work_dir"
        return 1
    fi

    # 构造 JSON (修正头部引号)
    echo -n '{"version":1,"rules":[{' > "$output"
    local fields=()
    json_arr() {
        local file=$1; local key=$2
        if [ -s "$file" ]; then
            local items=$(cat "$file" | sed 's/.*/"&"/' | paste -sd, -)
            echo "\"$key\":[$items]"
        fi
    }

    local s=$(json_arr "$work_dir/suffix.txt" "domain_suffix")
    [ -n "$s" ] && fields+=("$s")
    local d=$(json_arr "$work_dir/domain.txt" "domain")
    [ -n "$d" ] && fields+=("$d")
    local k=$(json_arr "$work_dir/keyword.txt" "domain_keyword")
    [ -n "$k" ] && fields+=("$k")
    if [ "$is_resolve" = "false" ]; then
        local i=$(json_arr "$work_dir/ipcidr.txt" "ip_cidr")
        [ -n "$i" ] && fields+=("$i")
    fi

    local final_fields=$(IFS=,; echo "${fields[*]}")
    echo -n "$final_fields" >> "$output"
    echo '}]}' >> "$output"

    # 调试监控 NODE 3
    if [ "$name" == "Apple" ] || [ "$name" == "apple" ]; then
        echo "[DEBUG NODE 3] JSON content BEFORE compiling (Top 150 chars):"
        head -c 150 "$output"
        echo -e "\n----------------------------------------------------------------"
    fi
    
    rm -rf "$work_dir"
    return 0
}

# --- 6. 执行编译 ---
echo "[INFO] Compiling SRS files..."
mkdir -p tmp_work
list=($(ls ./rule/Clash/))

for name in "${list[@]}"; do
    dir="./rule/Clash/$name"
    [ -d "$dir" ] || continue

    # 标准版
    if process_rules "$name" "$dir" "${name}.json" "false"; then
        ./sing-box rule-set compile "${name}.json" -o "${name}.srs" &>/dev/null
    fi

    # Resolve 版
    if process_rules "${name}_res" "$dir" "${name}-Resolve.json" "true"; then
        ./sing-box rule-set compile "${name}-Resolve.json" -o "${name}-Resolve.srs" &>/dev/null
    fi
done

rm -rf tmp_work
echo "[SUCCESS] Process finished."
