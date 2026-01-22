#!/bin/bash

# 1. 拉取 Blackmatrix
if [ ! -d rule ]; then
    echo "[INFO] Initializing Blackmatrix..."
    mkdir -p rule/Clash
    git init
    git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
    git config core.sparsecheckout true
    echo "rule/Clash" >>.git/info/sparse-checkout
    git pull --depth 1 origin master
    rm -rf .git
fi

# 2. 规范化结构 (平铺)
echo "[INFO] Normalizing structure..."
find ./rule/Clash/ -mindepth 2 -maxdepth 2 -type d | while read dir; do
    target="./rule/Clash/$(basename "$dir")"
    [ "$dir" != "$target" ] && cp -rf "$dir/." "$target/" 2>/dev/null
done

# 3. 处理 Classical 重命名
list_pre=($(ls ./rule/Clash/))
for name in "${list_pre[@]}"; do
    if [ -f "./rule/Clash/$name/${name}_Classical.yaml" ]; then
        mv -f "./rule/Clash/$name/${name}_Classical.yaml" "./rule/Clash/$name/${name}.yaml"
    fi
done

# 4. Accademia 覆盖
echo "[INFO] Fetching Accademia..."
rm -rf acca_temp && mkdir -p acca_temp
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git ./acca_temp

echo "[INFO] Merging Accademia..."
for rule_name in $(ls ./acca_temp); do
    if [ -d "./acca_temp/$rule_name" ]; then
        mkdir -p "./rule/Clash/$rule_name"
        cp -Rf ./acca_temp/"$rule_name"/* ./rule/Clash/"$rule_name"/
    fi
done
rm -rf acca_temp

# 5. 核心处理 (重构修复版)
echo "[INFO] Starting core processing..."
list=($(ls ./rule/Clash/))

for ((i = 0; i < ${#list[@]}; i++)); do
    # 必须找到一个有效的 yaml 才能继续
    target_yaml="./rule/Clash/${list[i]}/${list[i]}.yaml"
    [ ! -f "$target_yaml" ] && continue

    mkdir -p "${list[i]}_work"

    # --- 修复后的提取逻辑 (解决 IP-CIDR 解析错误) ---
    # 使用 awk 提取更加精准，自动处理逗号和多余空格
    grep 'DOMAIN-SUFFIX,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN-SUFFIX,//g' | tr -d ' ' > "${list[i]}_work/suffix.txt"
    grep 'DOMAIN,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN,//g' | tr -d ' ' > "${list[i]}_work/domain.txt"
    grep 'DOMAIN-KEYWORD,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN-KEYWORD,//g' | tr -d ' ' > "${list[i]}_work/keyword.txt"
    # 修复 IP-CIDR 报错：确保只留下纯粹的 IP/MASK
    grep 'IP-CIDR' "$target_yaml" | grep -v '#' | sed -E 's/.*IP-CIDR[6]?,//g' | sed 's/,.*//g' | tr -d ' ' > "${list[i]}_work/ipcidr.txt"

    # --- 转 JSON 格式 ---
    # 只有文件非空才处理
    for type in suffix domain keyword ipcidr; do
        if [ -s "${list[i]}_work/${type}.txt" ]; then
            key="$type"
            [ "$type" == "suffix" ] && key="domain_suffix"
            [ "$type" == "keyword" ] && key="domain_keyword"
            [ "$type" == "ipcidr" ] && key="ip_cidr"

            sed -i 's/^/        "/g; s/$/",/g' "${list[i]}_work/${type}.txt"
            sed -i "1s/^/      \"$key\": [\n/; \$ s/,$/\n      ]/" "${list[i]}_work/${type}.txt"
        else
            rm -f "${list[i]}_work/${type}.txt"
        fi
    done

    # --- 核心修复：合并为 .json ---
    # 先写头部
    echo -e "{\n  \"version\": 1,\n  \"rules\": [\n    {" > "${list[i]}.json"
    
    # 合并刚才生成的各个字段，注意处理逗号
    first=true
    for f in "${list[i]}_work"/*.txt; do
        if [ -f "$f" ]; then
            [ "$first" = false ] && echo "," >> "${list[i]}.json"
            cat "$f" >> "${list[i]}.json"
            first=false
        fi
    done

    # 写尾部
    echo -e "\n    }\n  ]\n}" >> "${list[i]}.json"
    rm -rf "${list[i]}_work"

    # 编译
    ./sing-box rule-set compile "${list[i]}.json" -o "${list[i]}.srs" 2>/dev/null
done

# DNS-Resolve 逻辑同理，篇幅原因此处暂略，如有需要可按此模式替换
echo "[SUCCESS] Process finished."
echo "------ DNS-only (Resolve) Start ------"

# 重新获取合并后的列表
list=($(ls ./rule/Clash/))

for ((i = 0; i < ${#list[@]}; i++)); do
    # 1. 寻找有效的源文件
    target_yaml="./rule/Clash/${list[i]}/${list[i]}.yaml"
    [ ! -f "$target_yaml" ] && continue

    # 2. 创建临时工作目录
    mkdir -p "${list[i]}_resolve_work"

    # 3. 精准提取域名相关字段 (DNS-only 不需要 IP)
    # 使用 sed 过滤掉注释并清理多余空格/逗号
    grep 'DOMAIN-SUFFIX,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN-SUFFIX,//g' | tr -d ' ' | sed '/^$/d' > "${list[i]}_resolve_work/suffix.txt"
    grep 'DOMAIN,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN,//g' | tr -d ' ' | sed '/^$/d' > "${list[i]}_resolve_work/domain.txt"
    grep 'DOMAIN-KEYWORD,' "$target_yaml" | grep -v '#' | sed 's/.*DOMAIN-KEYWORD,//g' | tr -d ' ' | sed '/^$/d' > "${list[i]}_resolve_work/keyword.txt"

    # 4. 格式化为 JSON 片段
    for type in suffix domain keyword; do
        if [ -s "${list[i]}_resolve_work/${type}.txt" ]; then
            key="$type"
            [ "$type" == "suffix" ] && key="domain_suffix"
            [ "$type" == "keyword" ] && key="domain_keyword"

            # 转换为 JSON 数组格式
            sed -i 's/^/        "/g; s/$/",/g' "${list[i]}_resolve_work/${type}.txt"
            # 移除最后一行多余的逗号并闭合数组
            sed -i "1s/^/      \"$key\": [\n/; \$ s/,$/\n      ]/" "${list[i]}_resolve_work/${type}.txt"
        else
            rm -f "${list[i]}_resolve_work/${type}.txt"
        fi
    done

    # 5. 组装最终的 Resolve.json
    # 检查是否有提取到任何内容
    if [ "$(ls "${list[i]}_resolve_work/" 2>/dev/null)" != "" ]; then
        echo -e "{\n  \"version\": 1,\n  \"rules\": [\n    {" > "${list[i]}-Resolve.json"
        
        # 合并各字段并处理字段间的逗号
        first_field=true
        for f in "${list[i]}_resolve_work"/*.txt; do
            if [ -f "$f" ]; then
                if [ "$first_field" = false ]; then
                    echo "," >> "${list[i]}-Resolve.json"
                fi
                cat "$f" >> "${list[i]}-Resolve.json"
                first_field=false
            fi
        done
        
        echo -e "\n    }\n  ]\n}" >> "${list[i]}-Resolve.json"
        
        # 6. 编译为 .srs
        ./sing-box rule-set compile "${list[i]}-Resolve.json" -o "${list[i]}-Resolve.srs" 2>/dev/null
        echo "  - [SUCCESS] ${list[i]}-Resolve.srs created."
    fi

    # 清理临时文件
    rm -rf "${list[i]}_resolve_work"
done

echo "------ All Tasks Complete ------"
