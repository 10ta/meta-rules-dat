#!/bin/bash
set -euo pipefail

echo "========== STAGE 1: Fetch blackmatrix =========="

if [ ! -d rule ]; then
	git init
	git remote add origin https://github.com/blackmatrix7/ios_rule_script.git
	git config core.sparsecheckout true
	echo "rule/Clash" >> .git/info/sparse-checkout
	git pull --depth 1 origin master
	rm -rf .git
fi

echo "========== STAGE 2: Flatten rule/Clash =========="

mapfile -t NAMES < <(
	find ./rule/Clash -mindepth 2 -type d \
	| awk -F '/' '{print $5}' \
	| sed '/^$/d' \
	| sort -u
)

for name in "${NAMES[@]}"; do
	echo "[FLATTEN] $name"

	mapfile -t PATHS < <(
		find ./rule/Clash -mindepth 2 -type d -name "$name"
	)

	for src in "${PATHS[@]}"; do
		dst="./rule/Clash/$name"

		if [ "$src" = "$dst" ]; then
			continue
		fi

		if [ ! -d "$dst" ]; then
			echo "  mv   $src -> $dst"
			mv "$src" "$dst"
		else
			echo "  merge $src -> $dst"
			rsync -a "$src"/ "$dst"/
			rm -rf "$src"
		fi
	done
done

echo "========== STAGE 3: Cleanup empty dirs =========="

find ./rule/Clash -type d -empty -delete

echo "========== STAGE 4: Handle Classical =========="

mapfile -t RULES < <(find ./rule/Clash -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

for r in "${RULES[@]}"; do
	c="./rule/Clash/$r/${r}_Classical.yaml"
	n="./rule/Clash/$r/${r}.yaml"
	if [ -f "$c" ]; then
		echo "[CLASSICAL] $r"
		mv "$c" "$n"
	fi
done

echo "========== STAGE 5: Fetch Accademia =========="

git clone --depth 1 https://github.com/Accademia/Additional_Rule_For_Clash.git accademia_tmp
rm -rf accademia_tmp/.git

echo "========== STAGE 6: Accademia override =========="

rsync -a --delete accademia_tmp/ ./rule/Clash/
rm -rf accademia_tmp

echo "========== STAGE 7: Compile rule-sets =========="

mapfile -t RULES < <(find ./rule/Clash -mindepth 1 -maxdepth 1 -type d -printf "%f\n")

for r in "${RULES[@]}"; do
	echo "[COMPILE] $r"
	work="./_work_$r"
	mkdir "$work"

	yaml="./rule/Clash/$r/$r.yaml"
	[ -f "$yaml" ] || { echo "  skip (no yaml)"; rm -rf "$work"; continue; }

	grep -v '#' "$yaml" | grep 'DOMAIN-SUFFIX,' | sed 's/.*,//' > "$work/suffix"
	grep -v '#' "$yaml" | grep 'DOMAIN-KEYWORD,' | sed 's/.*,//' > "$work/keyword"
	grep -v '#' "$yaml" | grep 'DOMAIN,' | sed 's/.*,//' > "$work/domain"
	grep -v '#' "$yaml" | grep 'IP-CIDR' | sed 's/.*,//' > "$work/ipcidr"

	json="$r.json"
	echo '{ "version": 1, "rules": [ {' > "$json"

	for f in domain suffix keyword ipcidr; do
		if [ -s "$work/$f" ]; then
			echo "  \"$f\": [" >> "$json"
			sed 's/^/    "/; s/$/",/' "$work/$f" >> "$json"
			sed -i '$ s/,$//' "$json"
			echo "  ]," >> "$json"
		fi
	done

	sed -i '$ s/,$//' "$json"
	echo "} ] }" >> "$json"

	rm -rf "$work"

	./sing-box rule-set compile "$json" -o "$r.srs"
done

echo "========== ALL DONE =========="

