#!/bin/bash
set +e

# --- 1. 配置开关 ---
is_debug=false # 已关闭。如需排查，请手动改为 true

# --- 2. 环境初始化 ---
rm -f *.json *.srs 2>/dev/null
rm -rf tmp_work 2>/dev/null
mkdir -p rule/Clash

# --- 3. 资源同步 ---
[ "$is_debug" = true ] && echo "[LOG] Fetching resources..."
git clone --depth 1 https://github.com/blackmatrix7/ios_rule_script.git git_temp &>/dev/null
cp -rf git_temp/rule/Clash/* rule/Clash/
rm -rf git_temp

# 规范化：BM7 Classical 文件预处理（确保主规则不被下划线逻辑过滤）
find ./rule/Clash/ -type f -name "*_Classical.yaml" | while read c; do
	dir=$(dirname "$c")
	base=$(basename "$dir")
	mv -f "$c" "$dir/$base.yaml"
done

# Accademia 覆盖
git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git acca_temp &>/dev/null
cp -af ./acca_temp/* rule/Clash/ 2>/dev/null
rm -rf acca_temp

# --- 4. 核心处理逻辑 ---
[ "$is_debug" = true ] && echo "[INFO] Processing Rules..."

# 递归寻找所有 .yaml 文件
find ./rule/Clash -type f -name "*.yaml" | while read yaml_file; do
	file_full_name=$(basename "$yaml_file")
	name="${file_full_name%.*}"

	# 【处理逻辑】
	# 将带下划线的文件名去除下划线 (例如 A_1 转换为 A1)
	if [[ "$name" == *"_"* ]]; then
		name="${name//_/}"
		[ "$is_debug" = true ] && echo "[LOG: RENAME] Variant detected: $file_full_name -> processing as $name"
	fi

	# 忽略非规则文件
	[[ "$name" == "config" ]] && continue

	[ "$is_debug" = true ] && echo -e "\n--- DEBUG START: $name ---"

	mkdir -p "tmp_work/$name"

	# 【精准提取函数】
	extract_final() {
		local key=$1
		local file_out="tmp_work/$name/$2.txt"

		# 逻辑：匹配行首 -> 排除注释行 -> 删缩进 -> 删空格 -> 切分取值 -> 删行尾注释
		grep -iE "^[[:space:]]*- $key([[:space:]]*,|$)" "$yaml_file" |
			grep -v '^[[:space:]]*#' |
			sed 's/^[[:space:]-]*//' |
			sed 's/[[:space:]]//g' |
			cut -d',' -f2 | cut -d',' -f1 | cut -d'#' -f1 |
			sort -u | sed '/^$/d' >"$file_out"
	}

	extract_final "DOMAIN-SUFFIX" "suffix"
	extract_final "DOMAIN" "domain"
	extract_final "DOMAIN-KEYWORD" "keyword"
	extract_final "IP-CIDR|IP-CIDR6" "ipcidr"

	# 【JSON & SRS 构建】
	build_json() {
		local mode=$1
		local out_name=$2
		local fields=()
		gen_box() {
			if [ -s "tmp_work/$name/$1.txt" ]; then
				local items=$(cat "tmp_work/$name/$1.txt" | sed 's/.*/"&"/' | paste -sd, -)
				echo "\"$2\":[$items]"
			fi
		}

		s=$(gen_box "suffix" "domain_suffix")
		[ -n "$s" ] && fields+=("$s")
		d=$(gen_box "domain" "domain")
		[ -n "$d" ] && fields+=("$d")
		k=$(gen_box "keyword" "domain_keyword")
		[ -n "$k" ] && fields+=("$k")
		[ "$mode" == "all" ] && {
			i=$(gen_box "ipcidr" "ip_cidr")
			[ -n "$i" ] && fields+=("$i")
		}

		if [ ${#fields[@]} -gt 0 ]; then
			# 钉死 version: 2
			echo -n '{"version":2,"rules":[{' >"$out_name"
			(
				IFS=,
				echo -n "${fields[*]}"
			) >>"$out_name"
			echo '}]}' >>"$out_name"

			./sing-box rule-set compile "$out_name" -o "${out_name%.json}.srs" &>/dev/null
			return 0
		fi
		return 1
	}

	if build_json "all" "${name}.json"; then
		[ "$is_debug" = true ] && echo "[RESULT] $name: SUCCESS."
		build_json "resolve" "${name}-Resolve.json" &>/dev/null
	fi

	[ "$is_debug" = true ] && echo "--- DEBUG END: $name ---"
done

# --- 5. 结尾清理 ---
if [ "$is_debug" = false ]; then
	rm -rf tmp_work 2>/dev/null
	[ "$is_debug" = false ] && echo "[INFO] Run complete. Cleanup finished."
else
	echo "[INFO] Debug mode on. tmp_work preserved."
fi

echo "------------------------------------------------"
echo "[FINISH] All tasks completed successfully."
exit 0
