#!/bin/bash

# --- 1. 环境清理 ---
rm -rf rule acca_temp tmp_work *.json *.srs
mkdir -p rule/Clash

# --- 2. 拉取资源 ---
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null

# --- 3. 规范化与强制覆盖 ---
# 先处理 Blackmatrix 可能存在的 Classical 文件名
find ./rule/Clash/ -maxdepth 2 -name "*_Classical.yaml" | while read c; do mv -f "$c" "${c%_Classical.yaml}.yaml"; done
# Accademia 覆盖
cp -af ./acca_temp/* ./rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 4. 核心提取逻辑 (锁定文件名) ---
echo "[INFO] Processing Rules..."
mkdir -p tmp_work

for dir in ./rule/Clash/*/ ; do
    name=$(basename "$dir")
    # 绝杀点：直接锁定 foo/foo.yaml，不找别的
    yaml_file="${dir}${name}.yaml"
    
    [ ! -f "$yaml_file" ] && continue

    mkdir -p "tmp_work/$name"
    
    # 提取函数：针对 Clash 各种奇葩缩进和注释的终极清理
    # 逻辑：只看包含关键词的行 -> 删掉所有空格和横杠 -> 取逗号后的内容 -> 删掉 # 后面的注释
    clean_extract() {
        grep "$1" "$yaml_file" | grep -v '^#' | sed 's/[[:space:]-]//g' | cut -d',' -f2 | cut -d'#' -f1 | sort -u | sed '/^$/d'
    }

    clean_extract "DOMAIN-SUFFIX," > "tmp_work/$name/suffix.txt"
    clean_extract "DOMAIN," > "tmp_work/$name/domain.txt"
    clean_extract "DOMAIN-KEYWORD," > "tmp_work/$name/keyword.txt"
    clean_extract "IP-CIDR," > "tmp_work/$name/ipcidr.txt"

    # JSON 组装函数
    make_json() {
        local mode=$1 # all | resolve
        local out_file=$2
        local fields=()
        
        build_array() {
            local f="tmp_work/$name/$1.txt"
            if [ -s "$f" ]; then
                local items=$(cat "$f" | sed 's/.*/"&"/' | paste -sd, -)
                echo "\"$2\":[$items]"
            fi
        }

        s=$(build_array "suffix" "domain_suffix"); [ -n "$s" ] && fields+=("$s")
        d=$(build_array "domain" "domain"); [ -n "$d" ] && fields+=("$d")
        k=$(build_array "keyword" "domain_keyword"); [ -n "$k" ] && fields+=("$k")
        if [ "$mode" == "all" ]; then
            i=$(build_array "ipcidr" "ip_cidr"); [ -n "$i" ] && fields+=("$i")
        fi

        if [ ${#fields[@]} -gt 0 ]; then
            echo -n '{"version":1,"rules":[{' > "$out_file"
            (IFS=,; echo -n "${fields[*]}") >> "$out_file"
            echo '}]}' >> "$out_file"
            # 编译 SRS
            ./sing-box rule-set compile "$out_file" -o "${out_file%.json}.srs" &>/dev/null
            return 0
        fi
        return 1
    }

    # 执行生成：双版本产出
    if make_json "all" "${name}.json"; then
        echo "  [SUCCESS] ${name}.srs & ${name}-Resolve.srs"
        make_json "resolve" "${name}-Resolve.json" &>/dev/null
    fi
    rm -rf "tmp_work/$name"
done

rm -rf tmp_work rule 2>/dev/null || true

echo "[FINISH] All rules processed successfully."
exit 0
