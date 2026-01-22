#!/bin/bash

# --- 1. 环境清理 ---
echo "[INFO] Cleaning workspace..."
rm -rf rule acca_temp tmp_work *.json *.srs
mkdir -p rule/Clash

# --- 2. 拉取 Blackmatrix (基础库) ---
echo "[INFO] Cloning Blackmatrix..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp
mv git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# --- 3. 处理 Blackmatrix 的目录与 Classical 命名 ---
echo "[INFO] Normalizing Blackmatrix structure..."
find ./rule/Clash -mindepth 2 -type f -name "*.yaml" | while read yaml; do
    dir_name=$(basename "$(dirname "$yaml")")
    mkdir -p "./rule/Clash/$dir_name"
    mv -f "$yaml" "./rule/Clash/$dir_name/" 2>/dev/null
done

# 重命名 _Classical 文件 (确保基础文件名统一)
for dir in ./rule/Clash/*/; do
    name=$(basename "$dir")
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# --- 4. 拉取 Accademia 并覆盖 (优先级最高) ---
echo "[INFO] Merging Accademia (High Priority)..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp
# 使用 cp -Rf 确保 Accademia 的内容完全覆盖/合并入对应文件夹
cp -Rf ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 5. 核心处理函数 (修复 sed 报错与多文件合并) ---
process_rules() {
    local name=$1
    local dir=$2
    local output=$3
    local is_resolve=$4

    local work_dir="tmp_work/$name"
    mkdir -p "$work_dir"

    # 扫描目录下所有的 .yaml 文件 (解决 Accademia 文件名不标准问题)
    # 使用通配符合并处理该目录下所有内容
    for yaml_file in "$dir"/*.yaml; do
        [ -e "$yaml_file" ] || continue
        
        # 修复后的 sed 提取逻辑：删除 -E 并正确处理转义，或者使用基础正则
        sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/suffix_raw.txt"
        sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/domain_raw.txt"
        sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/keyword_raw.txt"
        
        if [ "$is_resolve" = "false" ]; then
            # 修复 IP-CIDR 的 sed 表达式
            grep 'IP-CIDR' "$yaml_file" | sed -n 's/.*IP-CIDR[6]*,\([^, #]*\).*/\1/p' | tr -d ' ' | sed 's/#.*//' >> "$work_dir/ipcidr_raw.txt"
        fi
    done

    # 去重并清理空行
    [ -f "$work_dir/suffix_raw.txt" ] && sort -u "$work_dir/suffix_raw.txt" | sed '/^$/d' > "$work_dir/suffix.txt"
    [ -f "$work_dir/domain_raw.txt" ] && sort -u "$work_dir/domain_raw.txt" | sed '/^$/d' > "$work_dir/domain.txt"
    [ -f "$work_dir/keyword_raw.txt" ] && sort -u "$work_dir/keyword_raw.txt" | sed '/^$/d' > "$work_dir/keyword.txt"
    [ -f "$work_dir/ipcidr_raw.txt" ] && sort -u "$work_dir/ipcidr_raw.txt" | sed '/^$/d' > "$work_dir/ipcidr.txt"

    # 检查内容是否为空
    if [ ! -s "$work_dir/suffix.txt" ] && [ ! -s "$work_dir/domain.txt" ] && \
       [ ! -s "$work_dir/keyword.txt" ] && [ ! -s "$work_dir/ipcidr.txt" ]; then
        rm -rf "$work_dir"
        return 1
    fi

    # 构造 JSON
    echo '{"version":1,"rules":[{"' > "$output"
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

    (IFS=,; echo "${fields[*]}") >> "$output"
    echo '}]}' >> "$output"
    
    rm -rf "$work_dir"
    return 0
}

# --- 6. 执行编译 ---
echo "[INFO] Processing all rules..."
mkdir -p tmp_work
list=($(ls ./rule/Clash/))

for name in "${list[@]}"; do
    dir="./rule/Clash/$name"
    [ ! -d "$dir" ] && continue

    # 1. 标准版 (传入目录而非单个文件，实现目录下所有 yaml 合并)
    if process_rules "$name" "$dir" "${name}.json" "false"; then
        ./sing-box rule-set compile "${name}.json" -o "${name}.srs" &>/dev/null
        echo "  - Created: ${name}.srs"
    fi

    # 2. Resolve 版
    if process_rules "${name}_res" "$dir" "${name}-Resolve.json" "true"; then
        ./sing-box rule-set compile "${name}-Resolve.json" -o "${name}-Resolve.srs" &>/dev/null
        echo "  - Created: ${name}-Resolve.srs"
    fi
done

rm -rf tmp_work
echo "[SUCCESS] All sing-box rules are ready."
