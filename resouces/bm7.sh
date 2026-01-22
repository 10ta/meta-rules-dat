#!/bin/bash

# --- 1. 环境清理 ---
echo "[INFO] Cleaning workspace..."
rm -rf rule acca_temp tmp_work *.json *.srs
mkdir -p rule/Clash

# --- 2. 拉取 Blackmatrix (基础库) ---
echo "[INFO] Cloning Blackmatrix..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp
# 只要 Clash 目录下的内容
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# --- 3. 规范化 Blackmatrix 结构 ---
echo "[INFO] Normalizing Blackmatrix structure..."
# 统一重命名 _Classical 文件，确保基础文件名在 Accademia 覆盖前已经就绪
for dir in ./rule/Clash/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# --- 4. 拉取 Accademia 并覆盖 (最高优先级) ---
echo "[INFO] Fetching Accademia rules..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp

echo "[INFO] Merging Accademia (Priority: High)..."
# 遍历 Accademia 的所有目录并强制覆盖 rule/Clash 对应的目录
for acca_dir in ./acca_temp/*/; do
    [ -d "$acca_dir" ] || continue
    dir_name=$(basename "$acca_dir")
    mkdir -p "./rule/Clash/$dir_name"
    # 强制同步内容：-a 保持属性，-v 显示覆盖
    cp -af "$acca_dir". "./rule/Clash/$dir_name/"
    echo "  - Applied Accademia Override: $dir_name"
done
rm -rf acca_temp

# --- 5. 核心处理函数 ---
process_rules() {
    local name=$1
    local dir=$2
    local output=$3
    local is_resolve=$4

    local work_dir="tmp_work/$name"
    mkdir -p "$work_dir"

    # 扫描该目录下所有 yaml，提取规则
    for yaml_file in "$dir"/*.yaml; do
        [ -f "$yaml_file" ] || continue
        
        # 提取逻辑：剔除注释，提取关键字段
        sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/suffix_raw.txt"
        sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/domain_raw.txt"
        sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' >> "$work_dir/keyword_raw.txt"
        
        if [ "$is_resolve" = "false" ]; then
            grep 'IP-CIDR' "$yaml_file" | sed -n 's/.*IP-CIDR[6]*,\([^, #]*\).*/\1/p' | tr -d ' ' | sed 's/#.*//' >> "$work_dir/ipcidr_raw.txt"
        fi
    done

    # 清理与去重
    [ -f "$work_dir/suffix_raw.txt" ] && sort -u "$work_dir/suffix_raw.txt" | sed '/^$/d' > "$work_dir/suffix.txt"
    [ -f "$work_dir/domain_raw.txt" ] && sort -u "$work_dir/domain_raw.txt" | sed '/^$/d' > "$work_dir/domain.txt"
    [ -f "$work_dir/keyword_raw.txt" ] && sort -u "$work_dir/keyword_raw.txt" | sed '/^$/d' > "$work_dir/keyword.txt"
    [ -f "$work_dir/ipcidr_raw.txt" ] && sort -u "$work_dir/ipcidr_raw.txt" | sed '/^$/d' > "$work_dir/ipcidr.txt"

    # 判空
    if [ ! -s "$work_dir/suffix.txt" ] && [ ! -s "$work_dir/domain.txt" ] && \
       [ ! -s "$work_dir/keyword.txt" ] && [ ! -s "$work_dir/ipcidr.txt" ]; then
        rm -rf "$work_dir"
        return 1
    fi

    # --- 构造 JSON (修正双引号问题) ---
    # 头部：注意这里的引号闭合
    echo -n '{"version":1,"rules":[{' > "$output"
    local fields=()
    json_arr() {
        local file=$1; local key=$2
        if [ -s "$file" ]; then
            # 将每一行转为 "item" 并用逗号连接
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

    # 用逗号连接所有字段并写入
    local final_fields=$(IFS=,; echo "${fields[*]}")
    echo -n "$final_fields" >> "$output"
    
    # 尾部
    echo '}]}' >> "$output"
    
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

    # 1. 标准版
    if process_rules "$name" "$dir" "${name}.json" "false"; then
        ./sing-box rule-set compile "${name}.json" -o "${name}.srs" &>/dev/null
    fi

    # 2. Resolve 版
    if process_rules "${name}_res" "$dir" "${name}-Resolve.json" "true"; then
        ./sing-box rule-set compile "${name}-Resolve.json" -o "${name}-Resolve.srs" &>/dev/null
    fi
done

rm -rf tmp_work
echo "[SUCCESS] All tasks completed."
