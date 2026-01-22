#!/bin/bash

# 拉文件
if [ ! -d rule ]; then
	git init
	git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
	git config core.sparsecheckout true
	echo "rule/Clash" >>.git/info/sparse-checkout
	git pull --depth 1 origin master
	rm -rf .git
fi
# 移动文件/目录到同一文件夹
list=($(find ./rule/Clash/ | awk -F '/' '{print $5}' | sed '/^$/d' | grep -v '\.' | sort -u))
for ((i = 0; i < ${#list[@]}; i++)); do
	path=$(find ./rule/Clash/ -name ${list[i]})
	mv $path ./rule/Clash/
done

# --- 关键修改：增加 Accademia 详细日志与覆盖逻辑 ---
echo "------------------------------------------"
echo "[STEP] 准备获取 Accademia 额外规则..."

# 采样对比：覆盖前
if [ -f "./rule/Clash/ChinaMax/ChinaMax.yaml" ]; then
    echo "[LOG] 覆盖前 ChinaMax.yaml (前15行):"
    head -n 15 "./rule/Clash/ChinaMax/ChinaMax.yaml"
    echo "------------------------------------------"
else
    echo "[WARN] 覆盖前未找到 ChinaMax.yaml"
fi

mkdir -p temp_accademia
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git temp_accademia

if [ -d "temp_accademia" ]; then
    echo "[INFO] 开始逐文件夹合并 Accademia 规则..."
    # 遍历下载下来的文件夹
    cd temp_accademia
    # 获取当前目录下所有文件夹名
    dirs=$(find . -maxdepth 1 -type d ! -name ".")
    for d in $dirs; do
        folder_name=$(basename "$d")
        echo "[MERGE] 正在处理规则目录: $folder_name"
        
        # 确保目标目录存在
        mkdir -p "../rule/Clash/$folder_name"
        
        # 逐个移动文件并打印日志
        files=$(find "$d" -maxdepth 1 -type f)
        for f in $files; do
            file_name=$(basename "$f")
            cp -f "$f" "../rule/Clash/$folder_name/$file_name"
            echo "  └─ [OK] 已替换/新增文件: $folder_name/$file_name"
        done
    done
    cd ..
    rm -rf temp_accademia
else
    echo "[ERROR] 克隆 Accademia 仓库失败！"
fi

# 采样对比：覆盖后
echo "------------------------------------------"
if [ -f "./rule/Clash/ChinaMax/ChinaMax.yaml" ]; then
    echo "[LOG] 覆盖后 ChinaMax.yaml (前15行):"
    head -n 15 "./rule/Clash/ChinaMax/ChinaMax.yaml"
    echo "------------------------------------------"
else
    echo "[ERROR] 覆盖后未找到 ChinaMax.yaml"
fi

list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
	if [ -z "$(ls ./rule/Clash/${list[i]} | grep '.yaml')" ]; then
		directory=($(ls ./rule/Clash/${list[i]}))
		for ((x = 0; x < ${#directory[@]}; x++)); do
			mv ./rule/Clash/${list[i]}/${directory[x]} ./rule/Clash/${directory[x]}
		done
		rm -r ./rule/Clash/${list[i]}
	fi
done

list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
	if [ -f "./rule/Clash/${list[i]}/${list[i]}_Classical.yaml" ]; then
		mv ./rule/Clash/${list[i]}/${list[i]}_Classical.yaml ./rule/Clash/${list[i]}/${list[i]}.yaml
	fi
done

# 处理文件
list=($(ls ./rule/Clash/))
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
