#!/bin/bash

# --- 前置拉取与覆盖逻辑保持不变 ---
# (此处省略拉取 Blackmatrix 和 Accademia 的代码，直接进入核心处理函数)

process_to_json() {
    local name=$1
    local input=$2
    local output=$3
    local is_resolve=$4

    mkdir -p "tmp_$name"

    # 核心修复：精准提取并剔除注释
    # 逻辑：匹配关键字后的第一个逗号，取之后的内容，直到遇到第二个逗号或空格或换行，并删除所有 # 之后的内容
    sed -n 's/.*DOMAIN-SUFFIX,\([^, ]*\).*/\1/p' "$input" | sed 's/#.*//' | tr -d ' ' | sed '/^$/d' > "tmp_$name/suffix.txt"
    sed -n 's/.*DOMAIN,\([^, ]*\).*/\1/p' "$input" | sed 's/#.*//' | tr -d ' ' | sed '/^$/d' > "tmp_$name/domain.txt"
    sed -n 's/.*DOMAIN-KEYWORD,\([^, ]*\).*/\1/p' "$input" | sed 's/#.*//' | tr -d ' ' | sed '/^$/d' > "tmp_$name/keyword.txt"
    
    if [ "$is_resolve" = false ]; then
        # 针对 IP-CIDR，处理可能存在的 IP-CIDR6 和末尾的 no-resolve
        grep 'IP-CIDR' "$input" | sed -E 's/.*IP-CIDR[6]?,\([^, ]*\).*/\1/' | sed 's/#.*//' | tr -d ' ' | sed '/^$/d' > "tmp_$name/ipcidr.txt"
    fi

    # 检查是否有内容 (如果没有提取到，说明该 YAML 可能不是 Classical 格式，尝试兜底提取)
    if [ ! -s "tmp_$name/suffix.txt" ] && [ ! -s "tmp_$name/domain.txt" ] && [ ! -s "tmp_$name/keyword.txt" ] && [ ! -s "tmp_$name/ipcidr.txt" ]; then
        # 简单提取逻辑：如果上述正则没匹配到，尝试直接匹配每一行非注释的包含关键词的内容
        grep "DOMAIN-SUFFIX" "$input" | grep -v "^#" | cut -d, -f2 | sed 's/#.*//' | tr -d ' ' >> "tmp_$name/suffix.txt"
    fi

    # 再次检查，若依然全空，则放弃
    if [ ! -s "tmp_$name/suffix.txt" ] && [ ! -s "tmp_$name/domain.txt" ] && [ ! -s "tmp_$name/keyword.txt" ] && [ ! -s "tmp_$name/ipcidr.txt" ]; then
        rm -rf "tmp_$name"
        return 1
    fi

    # --- 构建 JSON 逻辑 ---
    # 使用以下更健壮的拼接方式
    echo '{"version": 1, "rules": [{' > "$output"
    
    local fields=()
    
    # 辅助函数：将 txt 转为引号包裹的行
    format_field() {
        local file=$1
        local key=$2
        if [ -s "$file" ]; then
            local content=$(cat "$file" | sort -u | sed 's/.*/"&"/' | paste -sd, -)
            echo "      \"$key\": [$content]"
        fi
    }

    # 收集所有非空字段
    local s=$(format_field "tmp_$name/suffix.txt" "domain_suffix")
    [ -n "$s" ] && fields+=("$s")
    local d=$(format_field "tmp_$name/domain.txt" "domain")
    [ -n "$d" ] && fields+=("$d")
    local k=$(format_field "tmp_$name/keyword.txt" "domain_keyword")
    [ -n "$k" ] && fields+=("$k")
    if [ "$is_resolve" = false ]; then
        local i=$(format_field "tmp_$name/ipcidr.txt" "ip_cidr")
        [ -n "$i" ] && fields+=("$i")
    fi

    # 用逗号连接所有字段
    (IFS=$',\n'; echo "${fields[*]}") >> "$output"

    echo -e '    }\n  ]\n}' >> "$output"
    rm -rf "tmp_$name"
    return 0
}

# --- 遍历逻辑保持不变 ---
