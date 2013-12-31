#!/bin/bash
words=$@
if [ -z "$words" ]; then
    words='XXX FIXME KLUDGE WTF TODO'
fi
pattern="$(echo "$words" | perl -pe 's/ +/ /g' | tr ' ' '|')"

tempdir="$(mktemp -d)"
trap "rm -rf $tempdir" EXIT

# Get git commit -> tag mapping.
git show-ref --tags | sed -e 's,refs/tags/,,' | sort > "$tempdir/tags"

# Find interesting commits.
declare -A interesting
for commit in $(git log --reverse --pickaxe-regex -S"$pattern" --pretty="format:%H"); do
    interesting[$commit]=1
done

declare -A counts
for word in $words; do
    counts[$word]=0
done

# Loop over _all_ commits.
i=0
declare -A commitIndices
git log --oneline --no-abbrev-commit --reverse | \
    while read -r commit rest; do
        : $((i++))
        echo $commit $i >> "$tempdir/commit-indices"
        if [ "${interesting[$commit]}" = 1 ]; then
            git show $commit > "$tempdir/diff"
            for word in $(egrep '^\+' "$tempdir/diff" | egrep -v '^\+\+\+' | egrep -o "$pattern"); do
                : $((counts[$word]++))
            done
            for word in $(egrep '^\-' "$tempdir/diff" | egrep -v '^\-\-\-' | egrep -o "$pattern"); do
                : $((counts[$word]--))
            done
        fi
        for word in $words; do
            echo $word $i ${counts[$word]} >> "$tempdir/$word.dat"
        done
    done

(
    echo -n 'set xtics nomirror rotate by -45 font ",12" ("" 0'
    join <(sort "$tempdir/commit-indices") "$tempdir/tags" | while read -r commit index tag; do
        echo -n ", \"$tag\" $index"
    done
    echo ")"
) >> "$tempdir/plot.gp"

cmd=""
for word in $words; do
    cmd="$cmd \"$tempdir/$word.dat\" using 3 with lines title \"$word\", "
done

cat >> "$tempdir/plot.gp" <<EOF
set term pngcairo enhanced font "arial,10" size 1200,700
set output "vittugraph.png"

plot $(echo "$cmd" | sed -e 's/, $//')
EOF

gnuplot -persist "$tempdir/plot.gp"
xdg-open vittugraph.png
