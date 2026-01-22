#!/bin/bash

# --- 1. 环境清理 ---
echo "[INFO] Cleaning workspace..."
mkdir -p rule/Clash

# --- 2. 拉取 Blackmatrix ---
echo "[INFO] Cloning Blackmatrix..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# --- 3. 规范化 Blackmatrix (Classical 统一化) ---
echo "[INFO] Normalizing Blackmatrix..."
find ./rule/Clash/ -maxdepth 2 -name "*_Classical.yaml" | while read classical; do
    target="${classical%_Classical.yaml}.yaml"
    mv -f "$classical" "$target"
done

# --- 4. 拉取 Accademia 并强制覆盖 ---
echo "[INFO] Fetching Accademia rules..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp
echo "[INFO] Applying Accademia Overrides..."
# 使用 find 确保即使有隐藏目录也能找到
find ./acca_temp -maxdepth 1 -mindepth 1 -type d | while read acca_dir; do
    dir_name=$(basename "$acca_dir")
    mkdir -p "./rule/Clash/$dir_name"
    cp -af "$acca_dir"/. "./rule/Clash/$dir_name/"
    echo "  - Overriding: $dir_name"
done
rm -rf acca_temp

# --- 5. 核心处理逻辑 ---
echo "----------------------------------------------------------------"
echo "[INFO] Starting Rule Processing..."
mkdir -p tmp_work

# 遍历 rule/Clash 下的所有文件夹
for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    yaml_file="${dir}${name}.yaml"

    # 如果同名 yaml 不存在，尝试在该目录下找任何一个 yaml (兜底)
    if [ ! -f "$yaml_file" ]; then
        yaml_file=$(find "$dir" -maxdepth 1 -name "*.yaml" | head -n 1)
    fi

    # 如果还是找不到 yaml，报错并跳过
    if [ -z "$yaml_file" ] || [ ! -f "$yaml_file" ]; then
        echo "  [SKIP] $name: No yaml file found."
        continue
    fi

    # --- 提取字段 ---
    work_dir="tmp_work/$name"
    mkdir -p "$work_dir"
    
    # 提取并剔除末尾 # 注释、空格、no-resolve 等
    sed -n 's/.*DOMAIN-SUFFIX,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/suffix.txt"
    sed -n 's/.*DOMAIN,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/domain.txt"
    sed -n 's/.*DOMAIN-KEYWORD,\([^, #]*\).*/\1/p' "$yaml_file" | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/keyword.txt"
    grep 'IP-CIDR' "$yaml_file" | sed -n 's/.*IP-CIDR[6]*,\([^, #]*\).*/\1/p' | tr -d ' ' | sed 's/#.*//' | sort -u | sed '/^$/d' > "$work_dir/ipcidr.txt"

    # 数组转换函数
    json_arr() {
        local file=$1; local key=$2
        if [ -s "$file" ]; then
            local items=$(cat "$file" | sed 's/.*/"&"/' | paste -sd, -)
            echo -n "\"$key\":[$items]"
        fi
    }

    # 准备域名相关字段
    fields_domain=()
    s=$(json_arr "$work_dir/suffix.txt" "domain_suffix"); [ -n "$s" ] && fields_domain+=("$s")
    d=$(json_arr "$work_dir/domain.txt" "domain"); [ -n "$d" ] && fields_domain+=("$d")
    k=$(json_arr "$work_dir/keyword.txt" "domain_keyword"); [ -n "$k" ] && fields_domain+=("$k")

    # 只要有任何字段，就开始生成
    if [ ${#fields_domain[@]} -gt 0 ] || [ -s "$work_dir/ipcidr.txt" ]; then
        echo "  [PROCESS] $name"

        # --- Standard 版本 ---
        standard_json="${name}.json"
        echo -n '{"version":1,"rules":[{' > "$standard_json"
        fields_full=("${fields_domain[@]}")
        i=$(json_arr "$work_dir/ipcidr.txt" "ip_cidr")
        [ -n "$i" ] && fields_full+=("$i")
        (IFS=,; echo -n "${fields_full[*]}") >> "$standard_json"
        echo '}]}' >> "$standard_json"
        ./sing-box rule-set compile "$standard_json" -o "${name}.srs" &>/dev/null

        # --- Resolve 版本 ---
        if [ ${#fields_domain[@]} -gt 0 ]; then
            resolve_json="${name}-Resolve.json"
            echo -n '{"version":1,"rules":[{"' > "$resolve_json"
            (IFS=,; echo -n "${fields_domain[*]}") >> "$resolve_json"
            echo '}]}' >> "$resolve_json"
            ./sing-box rule-set compile "$resolve_json" -o "${name}-Resolve.srs" &>/dev/null
        fi
    else
        echo "  [EMPTY] $name: No valid rules extracted."
    fi
    rm -rf "$work_dir"
done

rm -rf tmp_work
echo "----------------------------------------------------------------"
echo "[SUCCESS] All tasks finished."
