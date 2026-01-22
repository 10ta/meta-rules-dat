#!/bin/bash
set +e

# --- 1. 环境清理 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null

# --- 2. 资源拉取 ---
mkdir -p rule/Clash
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：确保每个目录都有一个跟目录同名的 .yaml
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c"); base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 3. 核心提取逻辑 ---
echo "[INFO] Processing Rules..."
mkdir -p tmp_work

for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    yaml_file="${dir}${name}.yaml"
    [ ! -f "$yaml_file" ] && yaml_file=$(ls "$dir"*.yaml 2>/dev/null | head -n 1)
    [ -z "$yaml_file" ] && continue

    mkdir -p "tmp_work/$name"

    # 【精准提取绝杀】
    # 1. grep 排除掉所有包含 # 的行（不管 # 在哪，只要被注释了就不要）
    # 2. 用 sed 删掉所有的空格、制表符、开头的横杠
    # 3. 此时行格式统一为: DOMAIN,apple.com 或 DOMAINSUFFIX,apple.com
    # 4. 用 cut 按逗号取第二列
    extract_simple() {
        grep "$1" "$yaml_file" | grep -v '#' | sed 's/[[:space:]-]//g' | cut -d',' -f2 | sort -u | sed '/^$/d'
    }

    extract_simple "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    extract_simple "DOMAIN," > "tmp_work/$name/domain.txt"
    extract_simple "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    extract_simple "IP-CIDR" > "tmp_work/$name/ipcidr.txt"

    build_json() {
        local mode=$1; local out=$2; local fields=()
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
            echo -n '{"version":2,"rules":[{' > "$out"
            (IFS=,; echo -n "${fields[*]}") >> "$out"
            echo '}]}' >> "$out"
            ./sing-box rule-set compile "$out" -o "${out%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    if build_json "all" "${name}.json"; then
        echo "  [SUCCESS] $name"
        build_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi
done

# --- 4. 验证 ---
echo "------------------------------------------------"
if [ -f "ChinaMax.json" ]; then
    echo "[VERIFY] ChinaMax.json found. Content check:"
    head -c 150 ChinaMax.json && echo "..."
fi
if [ -f "Apple.json" ]; then
    echo "[VERIFY] Apple.json found. Content check:"
    head -c 150 Apple.json && echo "..."
fi

# 只清理临时目录，绝不碰 rule 目录
rm -rf tmp_work 2>/dev/null
echo "------------------------------------------------"
exit 0
