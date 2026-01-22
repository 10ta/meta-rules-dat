#!/bin/bash

# --- 1. 环境准备 ---
echo "[INFO] 清理旧环境..."
rm -rf rule temp_accademia rules_raw
mkdir -p ./rules_raw

# --- 2. 拉取 BlackMatrix (作为基础库) ---
echo "[INFO] 正在拉取 BlackMatrix 基础规则..."
git init tmp_git
cd tmp_git
git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
git config core.sparsecheckout true
echo "rule/Clash" >> .git/info/sparse-checkout
git pull --depth 1 origin master

# 提取所有深层嵌套的 YAML 到扁平目录 rules_raw
find rule/Clash -name "*.yaml" -exec cp {} ../rules_raw/ \;
cd ..
rm -rf tmp_git

# --- 3. 预处理：统一 BlackMatrix 的命名 (解决 Classical 冲突) ---
echo "[INFO] 正在对齐基础库命名 (Classical -> 标准)..."
cd rules_raw
for f in *_Classical.yaml; do
    [ -f "$f" ] || continue
    # 将 ChinaMax_Classical.yaml 重命名为 ChinaMax.yaml
    target_name="${f%_Classical.yaml}.yaml"
    mv -f "$f" "$target_name"
done
cd ..

# --- 4. 拉取 Accademia 并强制覆盖 (最高优先级) ---
echo "------------------------------------------"
echo "[STEP] 准备获取 Accademia 覆盖规则..."
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git temp_accademia

if [ -d "temp_accademia" ]; then
    echo "[INFO] 正在执行 Accademia 最终覆盖..."
    # 查找 Accademia 中所有的 YAML 文件
    find temp_accademia -name "*.yaml" -type f | while read -r src; do
        file_name=$(basename "$src")
        # 强制覆盖 rules_raw 里的同名文件
        cp -f "$src" "./rules_raw/$file_name"
        
        # 针对 ChinaMax 打印覆盖确认日志
        if [ "$file_name" == "ChinaMax.yaml" ]; then
            echo "  └─ [CRITICAL] ChinaMax.yaml 已替换为 Accademia 版本"
            echo "     (采样前5行):"
            head -n 5 "./rules_raw/ChinaMax.yaml"
        fi
    done
    rm -rf temp_accademia
else
    echo "[ERROR] 克隆 Accademia 失败！"
fi
echo "------------------------------------------"

# --- 5. 统一生成 sing-box 规则集 (.srs) ---
echo "[INFO] 开始转换并编译 sing-box 规则集..."

# 确保 sing-box 可执行
chmod +x ./sing-box 2>/dev/null

for yaml_path in ./rules_raw/*.yaml; do
    [ -f "$yaml_path" ] || continue
    
    file_name=$(basename "$yaml_path")
    rule_name="${file_name%.*}"
    
    # 过滤无关文件
    [[ "$rule_name" == "README" || "$rule_name" == "LICENSE" ]] && continue

    echo "[PROCESS] 正在转换: $rule_name"

    # 临时存放解析出的字段
    tmp_dir="./tmp_$rule_name"
    mkdir -p "$tmp_dir"

    # 提取字段 (去重、去空格、去注释)
    grep 'DOMAIN-SUFFIX,' "$yaml_path" | sed 's/.*DOMAIN-SUFFIX,//g' | tr -d ' ' | sort -u > "$tmp_dir/suffix.list"
    grep 'DOMAIN,' "$yaml_path" | sed 's/.*DOMAIN,//g' | tr -d ' ' | sort -u > "$tmp_dir/domain.list"
    grep 'DOMAIN-KEYWORD,' "$yaml_path" | sed 's/.*DOMAIN-KEYWORD,//g' | tr -d ' ' | sort -u > "$tmp_dir/keyword.list"
    grep 'IP-CIDR' "$yaml_path" | sed 's/.*IP-CIDR,//g' | sed 's/.*IP-CIDR6,//g' | tr -d ' ' | sort -u > "$tmp_dir/ipcidr.list"

    # JSON 生成函数
    generate_json() {
        local output=$1
        local is_resolve=$2
        
        echo "{" > "$output"
        echo "  \"version\": 1," >> "$output"
        echo "  \"rules\": [{" >> "$output"
        
        local first_item=true
        write_field() {
            local field_name=$1
            local list_file=$2
            if [ -s "$list_file" ]; then
                [ "$first_item" = false ] && echo "," >> "$output"
                echo "      \"$field_name\": [" >> "$output"
                sed 's/.*/        "&"/' "$list_file" | sed '$!s/$/,/' >> "$output"
                echo -n "      ]" >> "$output"
                first_item=false
            fi
        }

        write_field "domain" "$tmp_dir/domain.list"
        write_field "domain_suffix" "$tmp_dir/suffix.list"
        write_field "domain_keyword" "$tmp_dir/keyword.list"
        # 如果不是 Resolve 版本，则写入 IP
        if [ "$is_resolve" = false ]; then
            write_field "ip_cidr" "$tmp_dir/ipcidr.list"
        fi

        echo "" >> "$output"
        echo "    }]" >> "$output"
        echo "}" >> "$output"
    }

    # 1. 编译标准版
    generate_json "$rule_name.json" false
    ./sing-box rule-set compile "$rule_name.json" -o "$rule_name.srs"

    # 2. 编译 DNS-only 版 (不含 IP)
    generate_json "$rule_name-Resolve.json" true
    ./sing-box rule-set compile "$rule_name-Resolve.json" -o "$rule_name-Resolve.srs"

    # 清理临时 JSON 和文件夹
    rm -rf "$tmp_dir" "$rule_name.json" "$rule_name-Resolve.json"
done

# --- 6. 扫尾工作 ---
rm -rf rules_raw
echo "------------------------------------------"
echo "[SUCCESS] 全部流程处理完成！"
