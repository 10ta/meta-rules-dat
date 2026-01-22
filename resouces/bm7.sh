#!/bin/bash

set -e

# =======================
# 拉 blackmatrix 文件
# =======================
if [ ! -d rule ]; then
	git init
	git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
	git config core.sparsecheckout true
	echo "rule/Clash" >> .git/info/sparse-checkout
	git pull --depth 1 origin master
	rm -rf .git
fi

# =======================
# 整理 blackmatrix 目录
# =======================
list=($(find ./rule/Clash/ | awk -F '/' '{print $5}' | sed '/^$/d' | grep -v '\.' | sort -u))
for ((i = 0; i < ${#list[@]}; i++)); do
	path=$(find ./rule/Clash/ -name ${list[i]})
	mv $path ./rule/Clash/
done

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

# =======================
# 处理 Classical 命名
# =======================
list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
	if [ -f "./rule/Clash/${list[i]}/${list[i]}_Classical.yaml" ]; then
		mv ./rule/Clash/${list[i]}/${list[i]}_Classical.yaml ./rule/Clash/${list[i]}/${list[i]}.yaml
	fi
done

# =======================
# 拉 Accademia（最高优先级）
# =======================
if [ ! -d accademia_tmp ]; then
	git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git accademia_tmp
	rm -rf accademia_tmp/.git
fi

# 覆盖到 rule/Clash（防止 Classical 回魂）
list=($(find ./rule/Clash/ | awk -F '/' '{print $5}' | sed '/^$/d' | grep -v '\.' | sort -u))
for ((i = 0; i < ${#list[@]}; i++)); do
	paths=($(find ./rule/Clash/ -mindepth 2 -type d -name "${list[i]}"))
	for p in "${paths[@]}"; do
		target="./rule/Clash/${list[i]}"
		# 如果目标不存在，直接 mv
		if [ ! -d "$target" ]; then
			mv "$p" "$target"
		# 目标存在 → 合并目录
		elif [ "$p" != "$target" ]; then
			rsync -a "$p"/ "$target"/
			rm -rf "$p"
		fi
	done
done


# =======================
# 处理文件 → JSON → SRS
# =======================
list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
	mkdir -p ${list[i]}

	# domain suffix
	if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-SUFFIX,')" ]; then
		cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-SUFFIX,' | sed 's/  - DOMAIN-SUFFIX,//g' > ${list[i]}/suffix.json
	fi

	# domain
	if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN,')" ]; then
		cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN,' | sed 's/  - DOMAIN,//g' >> ${list[i]}/domain.json
	fi

	# keyword
	if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- DOMAIN-KEYWORD,')" ]; then
		cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- DOMAIN-KEYWORD,' | sed 's/  - DOMAIN-KEYWORD,//g' > ${list[i]}/keyword.json
	fi

	# ipcidr
	if [ -n "$(cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep '\- IP-CIDR')" ]; then
		cat ./rule/Clash/${list[i]}/${list[i]}.yaml | grep -v '#' | grep '\- IP-CIDR' | sed 's/  - IP-CIDR,//g' | sed 's/  - IP-CIDR6,//g' > ${list[i]}/ipcidr.json
	fi

	# 转 json
	for f in domain suffix keyword ipcidr; do
		if [ -f "${list[i]}/${f}.json" ]; then
			sed -i 's/^/        "/g' ${list[i]}/${f}.json
			sed -i 's/$/",/g' ${list[i]}/${f}.json
			sed -i "1s/^/      \"${f//_/-}\": [\n/g" ${list[i]}/${f}.json
			sed -i '$ s/,$/\n      ],/g' ${list[i]}/${f}.json
		fi
	done

	# 合并
	cat ${list[i]}/* >> ${list[i]}.json
	sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}.json
	sed -i '$ s/,$/\n    }\n  ]\n}/g' ${list[i]}.json

	rm -r ${list[i]}
	./sing-box rule-set compile ${list[i]}.json -o ${list[i]}.srs
done

# =======================
# DNS-only Start
# =======================
echo "------ DNS-only Start ------"

list=($(ls ./rule/Clash/))
for ((i = 0; i < ${#list[@]}; i++)); do
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

	cat ${list[i]}/* >> ${list[i]}-Resolve.json
	sed -i '1s/^/{\n  "version": 1,\n  "rules": [\n    {\n/g' ${list[i]}-Resolve.json
	sed -i '$ s/,$/\n    }\n  ]\n}/g' ${list[i]}-Resolve.json

	rm -r ${list[i]}
	./sing-box rule-set compile ${list[i]}-Resolve.json -o ${list[i]}-Resolve.srs
done

