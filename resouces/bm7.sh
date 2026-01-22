#!/bin/bash

# 1. 环境初始化
mkdir -p rule/Clash
[ -f "./sing-box" ] || echo "[WARN] sing-box binary not found in current directory!"

# 2. 拉取 Blackmatrix
if [ ! -d rule/.git ]; then
    echo "[INFO] Cloning Blackmatrix..."
    cd rule && git init && git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
    git config core.sparsecheckout true
    echo "rule/Clash" >> .git/info/sparse-checkout
    git pull --depth 1 origin master && cd ..
fi

# 3. 规范化结构 (处理 Apple/Apple/Apple.yaml 这种嵌套)
echo "[INFO] Normalizing structure..."
# 将嵌套的子文件夹内容移动到第一层
find ./rule/Clash -mindepth 2 -type f -name "*.yaml" | while read yaml; do
    dir_name=$(basename "$(dirname "$yaml")")
    mkdir -p "./rule/Clash/$dir_name"
    mv -f "$yaml" "./rule/Clash/$dir_name/" 2>/dev/null
done

# 4. Accademia 覆盖 (优先级最高)
echo "[INFO] Merging Accademia (Override)..."
rm -rf acca_temp && mkdir -p acca_temp
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git ./acca_temp
cp -Rf ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# 5. 统一重命名处理 (Classical -> Standard)
for dir in ./rule/Clash/*/; do
    name=$(basename "$dir")
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# 6. 核心 JSON 处理函数
process_to_json() {
    local name=$1
    local input=$2
    local output=$3
    local is_resolve=$4 # true or false

    # 提取字段到临时文件
    mkdir -p "tmp_$name"
    grep -v '^#' "$input" | grep 'DOMAIN-SUFFIX,' | awk -F',' '{print $2}' | tr -d ' ' | sed '/^$/d' > "tmp_$name/suffix.txt"
    grep -v '^#' "$input" | grep 'DOMAIN,' | awk -F',' '{print $2}' | tr -d ' ' | sed '/^$/d' > "tmp_$name/domain.txt"
    grep -v '^#' "$input" | grep 'DOMAIN-KEYWORD,' | awk -F',' '{print $2}' | tr -d ' ' | sed '/^$/d' > "tmp_$name/keyword.txt"
    
    if [ "$is_resolve" = false ]; then
        grep -v '^#' "$input" | grep 'IP-CIDR' | awk -F',' '{print $2}' | tr -d ' ' | sed '/^$/d' > "tmp_$name/ipcidr.txt"
    fi

    # 检查是否有内容
    if [ ! -s "tmp_$name/suffix.txt" ] && [ ! -s "tmp_$name/domain.txt" ] && [ ! -s "tmp_$name/keyword.txt" ] && [ ! -s "tmp_$name/ipcidr.txt" ]; then
        rm -rf "tmp_$name"
        return 1
    fi

    # 开始构建 JSON
    echo '{"version": 1, "rules": [{' > "$output"
    
    local first=true
    write_field() {
        local file=$1
        local key=$2
        if [ -s "$file" ]; then
            [ "$first" = false ] && echo ',' >> "$output"
            echo "      \"$key\": [" >> "$output"
            sed 's/.*/        "&"/' "$file" | paste -sd, - >> "$output"
            echo -n "      ]" >> "$output"
            first=false
        fi
    }

    write_field "tmp_$name/suffix.txt" "domain_suffix"
    write_field "tmp_$name/domain.txt" "domain"
    write_field "tmp_$name/keyword.txt" "domain_keyword"
    [ "$is_resolve" = false ] && write_field "tmp_$name/ipcidr.txt" "ip_cidr"

    echo -e '\n    }\n  ]\n}' >> "$output"
    rm -rf "tmp_$name"
    return 0
}

# 7. 遍历执行
echo "[INFO] Building SRS files..."
for dir in ./rule/Clash/*/; do
    name=$(basename "$dir")
    yaml="${dir}${name}.yaml"
    
    # 如果主 yaml 不存在，尝试找目录下任何一个 yaml
    [ ! -f "$yaml" ] && yaml=$(ls "$dir"*.yaml 2>/dev/null | head -n 1)
    [ -z "$yaml" ] && continue

    # 处理标准版
    if process_to_json "$name" "$yaml" "${name}.json" false; then
        ./sing-box rule-set compile "${name}.json" -o "${name}.srs" 2>/dev/null
    fi

    # 处理 DNS-Resolve 版
    if process_to_json "${name}_res" "$yaml" "${name}-Resolve.json" true; then
        ./sing-box rule-set compile "${name}-Resolve.json" -o "${name}-Resolve.srs" 2>/dev/null
    fi
done

echo "[SUCCESS] All tasks finished."
