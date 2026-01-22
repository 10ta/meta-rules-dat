#!/bin/bash
set +e

# --- 1. 环境清理 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null

# --- 2. 资源同步 ---
mkdir -p rule/Clash
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化文件名
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c"); base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 强制覆盖
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

    # 【逻辑对齐】
    # 1. grep "$1"：锁定关键字行
    # 2. grep -v '^[[:space:]]*#'：排除掉真正被注释掉的行
    # 3. sed 's/[[:space:]-]//g'：删掉所有空格、制表符、横杠，格式化为 KEYWORD,VALUE#COMMENT
    # 4. cut -d',' -f2：拿 VALUE#COMMENT
    # 5. cut -d'#' -f1：彻底删掉行尾的注释部分，保留有效 VALUE
    extract_correct() {
        grep "$1" "$yaml_file" | grep -v '^[[:space:]]*#' | sed 's/[[:space:]-]//g' | cut -d',' -f2 | cut -d'#' -f1 | sort -u | sed '/^$/d'
    }

    extract_correct "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    extract_correct "DOMAIN," > "tmp_work/$name/domain.txt"
    extract_correct "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    extract_correct "IP-CIDR" > "tmp_work/$name/ipcidr.txt"

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
check_file() {
    if [ -f "$1" ]; then
        echo "[VERIFY] $1 content check:"
        # 检查是否包含关键字和内容
        grep -q "domain" "$1" && echo "  - Domain fields: OK" || echo "  - Domain fields: EMPTY"
        grep -q "ip_cidr" "$1" && echo "  - IP fields: OK" || echo "  - IP fields: EMPTY"
        echo "  Preview: $(head -c 100 "$1")..."
    fi
}

check_file "Apple.json"
check_file "ChinaMax.json"

rm -rf tmp_work 2>/dev/null
echo "------------------------------------------------"
exit 0
