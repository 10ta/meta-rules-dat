#!/bin/bash

# --- 1. 环境清理与准备 ---
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
# 将嵌套的子目录提取到根层级
find ./rule/Clash -mindepth 2 -type f -name "*.yaml" | while read yaml; do
    dir_name=$(basename "$(dirname "$yaml")")
    mkdir -p "./rule/Clash/$dir_name"
    mv -f "$yaml" "./rule/Clash/$dir_name/" 2>/dev/null
done

# 重命名 _Classical 文件
for dir in ./rule/Clash/*/; do
    name=$(basename "$dir")
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# --- 4. 拉取 Accademia 并强制覆盖 (优先级最高) ---
echo "[INFO] Merging Accademia (High Priority)..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp
cp -Rf ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 5. 核心处理函数 (解决注释与 JSON 错误) ---
process_rules() {
    local name=$1
    local input=$2
    local output=$3
    local is_resolve=$4

    local work_dir="tmp_work/$name"
    mkdir -p "$work_dir"

    # 精准提取：取第一个逗号后、第二个逗号或空格或#之前的内容
    sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$input" | tr -d ' ' | sed '/^$/d' | sort -u > "$work_dir/suffix.txt"
    sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$input" | tr -d ' ' | sed '/^$/d' | sort -u > "$work_dir/domain.txt"
    sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$input" | tr -d ' ' | sed '/^$/d' | sort -u > "$work_dir/keyword.txt"
    
    if [ "$is_resolve" = "false" ]; then
        grep 'IP-CIDR' "$input" | sed -E 's/.*IP-CIDR[6]?,\([^, #]*\).*/\1/' | tr -d ' ' | sed '/^$/d' | sort -u > "$work_dir/ipcidr.txt"
    fi

    # 检查内容是否为空
    if [ ! -s "$work_dir/suffix.txt" ] && [ ! -s "$work_dir/domain.txt" ] && \
       [ ! -s "$work_dir/keyword.txt" ] && [ ! -s "$work_dir/ipcidr.txt" ]; then
        rm -rf "$work_dir"
        return 1
    fi

    # 构造 JSON
    echo '{"version":1,"rules":[{"' > "$output"
    
    local fields=()
    
    # 辅助：转为 JSON 数组
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

    # 使用逗号合并字段
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
    yaml="./rule/Clash/$name/$name.yaml"
    [ ! -f "$yaml" ] && yaml=$(ls ./rule/Clash/$name/*.yaml 2>/dev/null | head -n 1)
    [ -z "$yaml" ] && continue

    # 1. 标准版
    if process_rules "$name" "$yaml" "${name}.json" "false"; then
        ./sing-box rule-set compile "${name}.json" -o "${name}.srs" &>/dev/null
        echo "  - Created: ${name}.srs"
    fi

    # 2. Resolve 版
    if process_rules "${name}_res" "$yaml" "${name}-Resolve.json" "true"; then
        ./sing-box rule-set compile "${name}-Resolve.json" -o "${name}-Resolve.srs" &>/dev/null
        echo "  - Created: ${name}-Resolve.srs"
    fi
done

# 清理
rm -rf tmp_work
echo "[SUCCESS] All sing-box rules are ready."
