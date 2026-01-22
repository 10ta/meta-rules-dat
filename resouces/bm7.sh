#!/bin/bash

# 1. 拉取 Blackmatrix (基础库)
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

# 2. 规范化 Blackmatrix 目录结构 (解决 "Directory not empty" 报错)
echo "[INFO] Normalizing directory structure..."
# 找到所有包含 .yaml 的深度目录，并尝试将其移动到 Clash 根目录下
find ./rule/Clash -mindepth 2 -type d -exec cp -rf {}/. ./rule/Clash/ \; 2>/dev/null
# 清理空目录和多余层级，只保留 Clash/规则名/规则.yaml 这种结构
find ./rule/Clash -mindepth 1 -maxdepth 1 -type d | while read dir; do
    # 如果目录下还有子目录，把子目录里的 yaml 提到当前目录下
    find "$dir" -mindepth 2 -name "*.yaml" -exec mv -f {} "$dir/" \; 2>/dev/null
done

# 3. 【关键步骤】先统一重命名 Blackmatrix 的 Classical 文件
echo "[INFO] Renaming Classical files to standard name..."
list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
    target_dir="./rule/Clash/${list[i]}"
    if [ -d "$target_dir" ]; then
        if [ -f "$target_dir/${list[i]}_Classical.yaml" ]; then
            mv -f "$target_dir/${list[i]}_Classical.yaml" "$target_dir/${list[i]}.yaml"
            echo "  - Processed: ${list[i]}_Classical -> ${list[i]}.yaml"
        fi
    fi
done

# 4. 【高优先级】拉取 Accademia 并覆盖，打印详细 Log
echo "[INFO] Fetching Accademia rules for override..."
mkdir -p acca_temp
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git ./acca_temp

echo "[INFO] Merging Accademia rules into Blackmatrix..."
# 遍历 Accademia 下的所有文件夹
ls ./acca_temp | while read rule_name; do
    if [ -d "./acca_temp/$rule_name" ]; then
        if [ -d "./rule/Clash/$rule_name" ]; then
            echo "  - [OVERWRITE] $rule_name (Accademia version taking priority)"
        else
            echo "  - [MERGE NEW] $rule_name (Accademia specific rule)"
            mkdir -p "./rule/Clash/$rule_name"
        fi
        # 强制覆盖：-f 保证不提示，-v 显示过程
        cp -Rf ./acca_temp/"$rule_name"/* ./rule/Clash/"$rule_name"/
    fi
done
rm -rf ./acca_temp
echo "[INFO] Merge complete."

# --- 以下部分完全衔接你的原始脚本逻辑，确保 ${list[i]} 变量定义正确 ---
echo "[INFO] Starting core processing (JSON conversion & Sing-box compilation)..."
list=($(ls ./rule/Clash/))

# 这里开始接你原来的 for ((i = 0; i < ${#list[@]}; i++)); do ... 逻辑
for ((i = 0; i < ${#list[@]}; i++)); do
	mkdir -p ${list[i]}
	# 归类
	# # android package
	# if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS | grep -v '\.exe' | grep -v '/' | grep '\.')" ]; then
	# 	cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' |  grep PROCESS | grep -v '\.exe' | grep -v '/' | grep '\.' | sed 's/  - PROCESS-NAME,//g' > ${list[i]}/package.json
	# fi
	# # process name
	# if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS | grep -v '/' | grep -v '\.')" ]; then
	# 	cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep -v '#' | grep PROCESS | grep -v '/' | grep -v '\.' | sed 's/  - PROCESS-NAME,//g' > ${list[i]}/process.json
	# fi
	# if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep PROCESS |  grep '\.exe')" ]; then
	# 	cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep -v '#' | grep PROCESS |  grep '\.exe' | sed 's/  - PROCESS-NAME,//g' >> ${list[i]}/process.json
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
	# # android package
	# if [ -f "${list[i]}/package.json" ]; then
	# 	sed -i 's/^/        "/g' ${list[i]}/package.json
	# 	sed -i 's/$/",/g' ${list[i]}/package.json
	# 	sed -i '1s/^/      "package_name": [\n/g' ${list[i]}/package.json
	# 	sed -i '$ s/,$/\n      ],/g' ${list[i]}/package.json
	# fi
	# # process name
	# if [ -f "${list[i]}/process.json" ]; then
	# 	sed -i 's/^/        "/g' ${list[i]}/process.json
	# 	sed -i 's/$/",/g' ${list[i]}/process.json
	# 	sed -i '1s/^/      "process_name": [\n/g' ${list[i]}/process.json
	# 	sed -i '$ s/,$/\n      ],/g' ${list[i]}/process.json
	# fi
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
	# 合并文件
	# if [ -f "${list[i]}/package.json" -a -f "${list[i]}/process.json" ]; then
	# 	mv ${list[i]}/package.json ${list[i]}.json
	# 	sed -i '$ s/,$/\n    },\n    {/g' ${list[i]}.json
	# 	cat ${list[i]}/process.json >> ${list[i]}.json
	# 	rm ${list[i]}/process.json
	# elif [ -f "${list[i]}/package.json" ]; then
	# 	mv ${list[i]}/package.json ${list[i]}.json
	# elif [ -f "${list[i]}/process.json" ]; then
	# 	mv ${list[i]}/process.json ${list[i]}.json
	# fi

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
# 处理文件
list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
	mkdir -p ${list[i]}
	# 归类
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

# echo "------ 转成json格式 Start ------"
	# 转成json格式
	# android package
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

# echo "------ 合并文件 Start------"
	if [ "$(ls ${list[i]})" = "" ]; then
		# echo "${list[i]}: void"
		sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
	elif [ -f "${list[i]}-Resolve.json" ]; then
		# echo "${list[i]}": "exists"
		sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
		sed -i '$ s/,$/\n    },\n    {/g' ${list[i]}-Resolve.json
		cat ${list[i]}/* >> ${list[i]}-Resolve.json
	else
		# echo "${list[i]}: final"
		cat ${list[i]}/* >> ${list[i]}-Resolve.json
		sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
	fi
	# echo "final merge"
	sed -i '$ s/,$/\n    }\n  ]\n}/g' ${list[i]}-Resolve.json
	rm -r ${list[i]}
	./sing-box rule-set compile ${list[i]}-Resolve.json -o ${list[i]}-Resolve.srs
done
