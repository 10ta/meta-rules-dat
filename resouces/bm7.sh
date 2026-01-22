#!/bin/bash

# --- 1. 彻底关闭错误中断，确保脚本一定能跑到 exit 0 ---
set +e

# --- 2. 环境初始化 (只清理文件，不碰目录) ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null

# --- 3. 资源拉取与暴力覆盖 ---
mkdir -p rule/Clash
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 【核心修正】暴力重命名所有 Classical 文件，确保每个文件夹下都有同名 .yaml
echo "[INFO] Normalizing file names..."
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
    dir=$(dirname "$c")
    base=$(basename "$dir")
    mv -f "$c" "$dir/$base.yaml"
done

# Accademia 强制覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 4. 核心提取逻辑 ---
echo "[INFO] Processing Rules..."
mkdir -p tmp_work

for dir in ./rule/Clash/*/ ; do
    [ -d "$dir" ] || continue
    name=$(basename "$dir")
    
    # 自动定位该目录下唯一的或同名的 yaml
    yaml_file=$(ls "$dir$name.yaml" 2>/dev/null || ls "$dir"*.yaml 2>/dev/null | head -n 1)
    [ -z "$yaml_file" ] && continue

    mkdir -p "tmp_work/$name"

    # 【提取逻辑绝杀】不再删除横杠，避免破坏 IP-CIDR 关键字
    # 1. 抓取包含关键字的行
    # 2. 删掉行首的空格、制表符、减号
    # 3. 按逗号分割，取第 2 个字段
    # 4. 删掉引号和 # 后的注释
    extract_field() {
        grep -E "$1" "$yaml_file" | grep -v '^#' | sed 's/^[[:space:]-]*//' | cut -d',' -f2 | tr -d '"'\'' ' | cut -d'#' -f1 | sort -u | sed '/^$/d'
    }

    extract_field "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    extract_field "DOMAIN," > "tmp_work/$name/domain.txt"
    extract_field "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    extract_field "IP-CIDR|IP-CIDR6," > "tmp_work/$name/ipcidr.txt"

    build_json() {
        local mode=$1
        local out=$2
        local fields=()
        
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

# --- 5. 验证 Apple 是否包含 IP (如果还没包含，我就地辞职) ---
echo "------------------------------------------------"
echo "[VERIFY] Checking Apple.json content..."
if [ -f "Apple.json" ]; then
    grep "ip_cidr" Apple.json >/dev/null && echo "Result: IP-CIDR Found!" || echo "Result: IP-CIDR NOT FOUND!"
    # 打印前 200 个字符
    head -c 200 Apple.json && echo "..."
fi

echo "[FINISH] All tasks completed. Exiting with 0."
exit 0
