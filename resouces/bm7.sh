#!/bin/bash

# ========================================================
# 第一阶段：拉取 Blackmatrix 基础库
# ========================================================
if [ ! -d rule ]; then
    echo "[INFO] Initializing Blackmatrix repository..."
    mkdir -p rule/Clash
    git init
    git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
    git config core.sparsecheckout true
    echo "rule/Clash" >>.git/info/sparse-checkout
    git pull --depth 1 origin master
    rm -rf .git
fi

# ========================================================
# 第二阶段：预处理 Blackmatrix 目录结构 (平铺并规范化)
# ========================================================
echo "[INFO] Normalizing Blackmatrix structure..."
# 提取所有嵌套的子目录到 rule/Clash 第一层，避免 mv 冲突
find ./rule/Clash/ -mindepth 2 -maxdepth 2 -type d | while read dir; do
    target="./rule/Clash/$(basename "$dir")"
    if [ "$dir" != "$target" ]; then
        cp -rf "$dir/." "$target/" 2>/dev/null
    fi
done

# 统一重命名 Classical 文件为标准名称
list_pre=($(ls ./rule/Clash/))
for name in "${list_pre[@]}"; do
    dir="./rule/Clash/$name"
    if [ -d "$dir" ]; then
        if [ -f "$dir/${name}_Classical.yaml" ]; then
            mv -f "$dir/${name}_Classical.yaml" "$dir/${name}.yaml"
        fi
    fi
done

# ========================================================
# 第三阶段：拉取 Accademia 并强制覆盖 (最高优先级)
# ========================================================
echo "[INFO] Fetching Accademia rules for override..."
rm -rf acca_temp
mkdir -p acca_temp
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git ./acca_temp

echo "[INFO] Merging Accademia (High Priority Override)..."
acca_list=($(ls ./acca_temp))
for rule_name in "${acca_list[@]}"; do
    if [ -d "./acca_temp/$rule_name" ]; then
        # 即使 Blackmatrix 没有该规则，也创建目录以支持 Accademia 特有规则
        mkdir -p "./rule/Clash/$rule_name"
        
        if [ -f "./rule/Clash/$rule_name/$rule_name.yaml" ]; then
            echo "  - [OVERWRITE] $rule_name"
        else
            echo "  - [MERGE NEW] $rule_name"
        fi
        
        # 强制覆盖 rule/Clash 下的对应文件夹内容
        cp -Rf ./acca_temp/"$rule_name"/* ./rule/Clash/"$rule_name"/
    fi
done
rm -rf acca_temp

# ========================================================
# 第四阶段：核心处理逻辑 (保持原脚本逻辑一行不动)
# ========================================================
echo "[INFO] Starting core processing..."

# 重新获取最终合并后的列表
list=($(ls ./rule/Clash/))

for ((i = 0; i < ${#list[@]}; i++)); do
    # 防御性判断：确保目标 yaml 存在，否则跳过该循环
    if [ ! -f "./rule/Clash/${list[i]}/${list[i]}.yaml" ]; then
        continue
    fi

    mkdir -p ${list[i]}
    # 归类
    # # android package
    # if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS | grep -v '\.exe' | grep -v '/' | grep '\.')" ]; then
    #     cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' |  grep PROCESS | grep -v '\.exe' | grep -v '/' | grep '\.' | sed 's/  - PROCESS-NAME,//g' > ${list[i]}/package.json
    # fi
    # # process name
    # if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS | grep -v '/' | grep -v '\.')" ]; then
    #     cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep -v '#' | grep PROCESS | grep -v '/' | grep -v '\.' | sed 's/  - PROCESS-NAME,//g' > ${list[i]}/process.json
    # fi
    # if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS |  grep '\.exe')" ]; then
    #     cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep -v '#' | grep PROCESS |  grep '\.exe' | sed 's/  - PROCESS-NAME,//g' >> ${list[i]}/process.json
    # fi
    # domain
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-SUFFIX,')" ]; then
        # cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-SUFFIX,' | sed 's/  - DOMAIN-SUFFIX,//g' > ${list[i]}/domain.json
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-SUFFIX,' | sed 's/  - DOMAIN-SUFFIX,//g' > ${list[i]}/suffix.json
    fi
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN,')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN,' | sed 's/  - DOMAIN,//g' >> ${list[i]}/domain.json
    fi
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-KEYWORD,')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-KEYWORD,' | sed 's/  - DOMAIN-KEYWORD,//g' > ${list[i]}/keyword.json
    fi
    # ipcidr
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- IP-CIDR')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- IP-CIDR' | sed 's/  - IP-CIDR,//g' | sed 's/  - IP-CIDR6,//g' > ${list[i]}/ipcidr.json
    fi
    # 转成json格式
    # domain
    if [ -f "${list[i]}/domain.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/domain.json
        sed -i 's/$/",/g' ${list[i]}/domain.json
        sed -i '1s/^/      "domain": [\n/g' ${list[i]}/domain.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/domain.json
    fi
    if [ -f "${list[i]}/suffix.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/suffix.json
        sed -i 's/$/",/g' ${list[i]}/suffix.json
        sed -i '1s/^/      "domain_suffix": [\n/g' ${list[i]}/suffix.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/suffix.json
    fi
    if [ -f "${list[i]}/keyword.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/keyword.json
        sed -i 's/$/",/g' ${list[i]}/keyword.json
        sed -i '1s/^/      "domain_keyword": [\n/g' ${list[i]}/keyword.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/keyword.json
    fi
    # ipcidr
    if [ -f "${list[i]}/ipcidr.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/ipcidr.json
        sed -i 's/$/",/g' ${list[i]}/ipcidr.json
        sed -i '1s/^/      "ip_cidr": [\n/g' ${list[i]}/ipcidr.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/ipcidr.json
    fi

    if [ "$(ls ${list[i]})" = "" ]; then
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}.json
    elif [ -f "${list[i]}.json" ]; then
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}.json
        sed -i '$ s/,$/\n    },\n    {/g' ${list[i]}.json
        cat ${list[i]}/* >> ${list[i]}.json
    else
        cat ${list[i]}/* >> ${list[i]}.json
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}.json
    fi
    sed -i '$ s/,$/\n    }\n  ]\n}/g' ${list[i]}.json
    rm -r ${list[i]}
    ./sing-box rule-set compile ${list[i]}.json -o ${list[i]}.srs
done

echo "------ DNS-only Start ------"
# 下面处理 DNS-only (Resolve) 逻辑，同样保持你原来的脚本内容
list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
    if [ ! -f "./rule/Clash/${list[i]}/${list[i]}.yaml" ]; then
        continue
    fi
    mkdir -p ${list[i]}
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-SUFFIX,')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-SUFFIX,' | sed 's/  - DOMAIN-SUFFIX,//g' > ${list[i]}/suffix.json
    fi
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN,')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN,' | sed 's/  - DOMAIN,//g' >> ${list[i]}/domain.json
    fi
    if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-KEYWORD,')" ]; then
        cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-KEYWORD,' | sed 's/  - DOMAIN-KEYWORD,//g' > ${list[i]}/keyword.json
    fi

    if [ -f "${list[i]}/domain.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/domain.json
        sed -i 's/$/",/g' ${list[i]}/domain.json
        sed -i '1s/^/      "domain": [\n/g' ${list[i]}/domain.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/domain.json
    fi
    if [ -f "${list[i]}/suffix.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/suffix.json
        sed -i 's/$/",/g' ${list[i]}/suffix.json
        sed -i '1s/^/      "domain_suffix": [\n/g' ${list[i]}/suffix.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/suffix.json
    fi
    if [ -f "${list[i]}/keyword.json" ]; then
        sed -i 's/^/        "/g' ${list[i]}/keyword.json
        sed -i 's/$/",/g' ${list[i]}/keyword.json
        sed -i '1s/^/      "domain_keyword": [\n/g' ${list[i]}/keyword.json
        sed -i '$ s/,$/\n      ],/g' ${list[i]}/keyword.json
    fi

    if [ "$(ls ${list[i]})" = "" ]; then
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
    elif [ -f "${list[i]}-Resolve.json" ]; then
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
        sed -i '$ s/,$/\n    },\n    {/g' ${list[i]}-Resolve.json
        cat ${list[i]}/* >> ${list[i]}-Resolve.json
    else
        cat ${list[i]}/* >> ${list[i]}-Resolve.json
        sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
    fi
    sed -i '$ s/,$/\n    }\n  ]\n}/g' ${list[i]}-Resolve.json
    rm -r ${list[i]}
    ./sing-box rule-set compile ${list[i]}-Resolve.json -o ${list[i]}-Resolve.srs
done
