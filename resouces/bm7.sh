#!/bin/bash
set +e # 忽略非致命错误

# --- 1. 环境初始化 ---
echo "[1/4] Initializing..."
rm -rf tmp_work *.json *.srs rule acca_temp git_temp 2>/dev/null
mkdir -p rule/Clash

# --- 2. 资源拉取与强制覆盖 ---
echo "[2/4] Fetching Repositories..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化 Blackmatrix 命名 (Classical -> .yaml)
find ./rule/Clash/ -maxdepth 2 -name "*_Classical.yaml" -exec bash -c 'mv "$1" "${1%_Classical.yaml}.yaml"' _ {} \;

git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 3. 核心提取与生成 ---
echo "[3/4] Processing Rules..."
mkdir -p tmp_work

for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    yaml_file="${dir}${name}.yaml"
    [ ! -f "$yaml_file" ] && continue

    mkdir -p "tmp_work/$name"

    # --- 统一提取逻辑：通杀空格、横杠、注释 ---
    # 逻辑：查找关键字 -> cut取逗号后内容 -> tr删除空格/单双引号/横杠 -> cut取#前内容
    extract_val() {
        grep -E "$1" "$yaml_file" | grep -v '^#' | cut -d',' -f2- | tr -d ' "\t-' | cut -d'#' -f1 | sort -u | sed '/^$/d'
    }

    extract_val "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    extract_val "DOMAIN," > "tmp_work/$name/domain.txt"
    extract_val "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    # 同时匹配 IP-CIDR 和 IP-CIDR6
    extract_val "IP-CIDR|IP-CIDR6," > "tmp_work/$name/ipcidr.txt"

    # --- 构造 JSON 函数 ---
    build_json() {
        local mode=$1 # all | resolve
        local target_json=$2
        local fields=()
        
        get_box() {
            if [ -s "tmp_work/$name/$1.txt" ]; then
                local items=$(cat "tmp_work/$name/$1.txt" | sed 's/.*/"&"/' | paste -sd, -)
                echo "\"$2\":[$items]"
            fi
        }

        s=$(get_box "suffix" "domain_suffix"); [ -n "$s" ] && fields+=("$s")
        d=$(get_box "domain" "domain"); [ -n "$d" ] && fields+=("$d")
        k=$(get_box "keyword" "domain_keyword"); [ -n "$k" ] && fields+=("$k")
        # 只有 Standard 模式添加 IP
        if [ "$mode" == "all" ]; then
            i=$(get_box "ipcidr" "ip_cidr"); [ -n "$i" ] && fields+=("$i")
        fi

        if [ ${#fields[@]} -gt 0 ]; then
            echo -n '{"version":2,"rules":[{' > "$target_json"
            (IFS=,; echo -n "${fields[*]}") >> "$target_json"
            echo '}]}' >> "$target_json"
            # 编译
            ./sing-box rule-set compile "$target_json" -o "${target_json%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    # 执行生成
    if build_json "all" "${name}.json"; then
        echo "  [OK] $name (Standard & Resolve)"
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    else
        echo "  [EMPTY] $name: No valid rules found."
    fi
    rm -rf "tmp_work/$name"
done

# --- 4. 验证与最终收工 ---
echo "[4/4] Final Verification..."
if [ -s "Apple.json" ]; then
    echo "  [VERIFY] Apple.json exists. Checking IP-CIDR..."
    grep -q "ip_cidr" Apple.json && echo "  [RESULT] IP-CIDR found in Apple.json." || echo "  [RESULT] IP-CIDR MISSING!"
else
    echo "  [RESULT] Apple.json is MISSING!"
fi

rm -rf tmp_work rule 2>/dev/null
echo "------------------------------------------------"
echo "[SUCCESS] Task completed."
exit 0
