#!/bin/bash
words=$@
if [ -z "$words" ]; then
    words='XXX FIXME KLUDGE WTF TODO'
fi
pattern="$(echo "$words" | perl -pe 's/ +/ /g' | tr ' ' '|')"

tempdir="$(mktemp -d)"
trap "rm -rf $tempdir" EXIT

# Generate AWK script.
for word in $words; do
    echo "BEGIN { counts[\"$word\"] = 0; }"     >> "$tempdir/process.awk"
done
cat >> "$tempdir/process.awk" <<'EOF'
{
    if ($1 == "additions") {
        mult = +1;
    } else if ($1 == "deletions") {
        mult = -1;
    } else if ($1 == "end") {
        i += 1;
        for (word in counts)
            print $2, i, counts[word] >> word ".dat"
    } else {
        counts[$2] += mult * $1;
    }
}
EOF

# Find interesting commits.
declare -A interesting
for commit in $(git log --reverse --pickaxe-regex -S"$pattern" --pretty="format:%H"); do
    interesting[$commit]=1
done

# Get git commit -> tag mapping.
git show-ref --tags | sed -e 's,refs/tags/,,' | sort > "$tempdir/tags"

# Loop over _all_ commits.
git log --oneline --no-abbrev-commit --reverse | \
    while read -r commit rest; do
        if [ "${interesting[$commit]}" = 1 ]; then
            git show $commit > "$tempdir/diff"
            echo additions $commit
            egrep '^\+' "$tempdir/diff" | egrep -v '^\+\+\+' | egrep -o "$pattern" | sort | uniq -c
            echo deletions $commit
            egrep '^\-' "$tempdir/diff" | egrep -v '^\-\-\-' | egrep -o "$pattern" | sort | uniq -c
        fi
        echo end $commit
    done | (
    cd "$tempdir"
    awk -f process.awk

    cat *.dat | cut -d' ' -f1,2 | sort -u > commit-indices
    (
        echo -n 'set xtics nomirror rotate by -45 font ",12" ("" 0'
        join commit-indices tags | while read -r commit index tag; do
            echo -n ", \"$tag\" $index"
        done
        echo ")"
    ) >> plot.gp

    cmd=""
    for word in $words; do
        cmd="$cmd \"$word.dat\" using 3 with lines title \"$word\", "
    done

    cat >> "plot.gp" <<EOF
set term pngcairo enhanced font "arial,10" size 1200,700
set output "vittugraph.png"

plot $(echo "$cmd" | sed -e 's/, $//')
EOF

    gnuplot -persist plot.gp
    xdg-open vittugraph.png
)

cp "$tempdir/vittugraph.png" .
