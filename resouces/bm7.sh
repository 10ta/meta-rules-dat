#!/bin/bash

# --- 1. 环境清理 ---
rm -rf rule acca_temp tmp_work *.json *.srs
mkdir -p rule/Clash

# --- 2. 拉取 Blackmatrix ---
echo "[INFO] Cloning Blackmatrix..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# --- 3. 规范化 Blackmatrix (处理 Classical) ---
for dir in ./rule/Clash/*/; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    if [ -f "${dir}${name}_Classical.yaml" ]; then
        mv -f "${dir}${name}_Classical.yaml" "${dir}${name}.yaml"
    fi
done

# --- 4. 拉取 Accademia 并覆盖 (确保主 yaml 是 Accademia 的) ---
echo "[INFO] Fetching Accademia rules..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp
for acca_dir in ./acca_temp/*/; do
    [ -d "$acca_dir" ] || continue
    dir_name=$(basename "$acca_dir")
    mkdir -p "./rule/Clash/$dir_name"
    # 这一步非常关键：Accademia 的 Apple.yaml 会直接覆盖 Blackmatrix 的 Apple.yaml
    cp -af "$acca_dir". "./rule/Clash/$dir_name/"
done
rm -rf acca_temp

# --- 5. 核心处理逻辑 ---
echo "[INFO] Compiling Standard & Resolve versions..."
mkdir -p tmp_work

list=($(ls ./rule/Clash/))
for name in "${list[@]}"; do
    dir="./rule/Clash/$name"
    [ -d "$dir" ] || continue

    # 锁定主 YAML 文件
    yaml_file="${dir}/${name}.yaml"
    [ ! -f "$yaml_file" ] && continue

    # --- 统一提取内容到临时文件 ---
    mkdir -p "tmp_work/$name"
    sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "tmp_work/$name/suffix.txt"
    sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "tmp_work/$name/domain.txt"
    sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "tmp_work/$name/keyword.txt"
    grep 'IP-CIDR' "$yaml_file" | sed -n 's/.*IP-CIDR[6]*,\([^, #]*\).*/\1/p' | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "tmp_work/$name/ipcidr.txt"

    # 提取公共域名数组逻辑
    json_arr() {
        local file=$1; local key=$2
        if [ -s "$file" ]; then
            local items=$(cat "$file" | sed 's/.*/"&"/' | paste -sd, -)
            echo "\"$key\":[$items]"
        fi
    }

    # 预准备域名相关的字段
    fields_domain=()
    s=$(json_arr "tmp_work/$name/suffix.txt" "domain_suffix"); [ -n "$s" ] && fields_domain+=("$s")
    d=$(json_arr "tmp_work/$name/domain.txt" "domain"); [ -n "$d" ] && fields_domain+=("$d")
    k=$(json_arr "tmp_work/$name/keyword.txt" "domain_keyword"); [ -n "$k" ] && fields_domain+=("$k")

    # 如果没有任何内容，跳过此规则
    if [ ${#fields_domain[@]} -eq 0 ] && [ ! -s "tmp_work/$name/ipcidr.txt" ]; then
        rm -rf "tmp_work/$name"
        continue
    fi

    # --- 版本 1: Standard (带有 IP-CIDR) ---
    standard_json="${name}.json"
    echo -n '{"version":1,"rules":[{"' > "$standard_json"
    
    fields_full=("${fields_domain[@]}")
    i=$(json_arr "tmp_work/$name/ipcidr.txt" "ip_cidr")
    [ -n "$i" ] && fields_full+=("$i")
    
    (IFS=,; echo -n "${fields_full[*]}") >> "$standard_json"
    echo '}]}' >> "$standard_json"
    ./sing-box rule-set compile "$standard_json" -o "${name}.srs" &>/dev/null

    # --- 版本 2: Resolve (只有域名，剔除 IP-CIDR) ---
    # 只有当存在域名规则时才生成 Resolve 版本
    if [ ${#fields_domain[@]} -gt 0 ]; then
        resolve_json="${name}-Resolve.json"
        echo -n '{"version":1,"rules":[{"' > "$resolve_json"
        (IFS=,; echo -n "${fields_domain[*]}") >> "$resolve_json"
        echo '}]}' >> "$resolve_json"
        ./sing-box rule-set compile "$resolve_json" -o "${name}-Resolve.srs" &>/dev/null
    fi

    rm -rf "tmp_work/$name"
done

rm -rf tmp_work
echo "[SUCCESS] Process finished. All Standard and Resolve rules are ready."
