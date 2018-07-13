#!/bin/bash

set -e

function error()
{
    echo "$@"
    exit 42
}

function cleanup()
{
    rm -f "$1-"*"-$$"
}

function split_into_tables()
{
    local INSFILE="$1.$$-tmp"
    grep INSERT "$1" | egrep -v 'dbix_class_deploymenthandler_versions|users_temp_alter' > "$INSFILE"
    awk '{print $3}' "$INSFILE" | uniq | while read i; do
        grep $i "$INSFILE" > "$1-$(echo $i|sed 's/\"//g')-$$"
    done
    verify_files "$INSFILE" "$1"
    rm "$1-job_module_needles-$$"
    rm -f "$INSFILE"
}

function verify_files()
{
   sort "$1" > check1.$$
   cat "$2-"*"-$$" | sort > check2.$$
   diff check1.$$ check2.$$
   rm check1.$$ check2.$$
}

function report_num_rows()
{
    echo -n "Rows from imported file: "
    wc -l "$1"
    psql -U postgres -d openqa -c "select count(*) from $(echo $1 | sed -r -e 's/^.+\-([^\-]+)\-.+/\1/')"
}

function process_file()
{
    echo "Processing file [$1]"
    cat "$1" | while read s; do
        psql -U postgres -d openqa -c "$s"
    done
}

function process_all_tables()
{
    for file in "$1-"*"-$$"; do
        process_file "$file"
        tail -1 "$file" >> $SEQSFILE
    done
}

function process_users_table()
{
    local FILE="$1-users-$$"
    echo "Processing file [$FILE]"
    egrep -v 'noemail@open.qa|admin@example.com' "$FILE" | sed -r -e 's/VALUES\(([0-9]+)/VALUES\(\1+1/' | while read s; do
        psql -U postgres -d openqa -c "$s"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_assets_table()
{
    local FILE="$1-assets-$$"
    echo "Processing file [$FILE]"
    sed -r -e 's/.+\(//' -e 's/\);//' "$FILE" | awk -F, 'BEGIN {OFS=","} ($5=$5",NULL,FALSE") { print $0 }' | while read i; do
        psql -U postgres -d openqa -c "INSERT INTO \"assets\" VALUES($i)"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_table()
{
    local FILE="$2-$1-$$"
    process_file "$FILE"
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_jobs_table()
{
    local FILE="$1-jobs-$$"
    echo "Processing file [$FILE]"
    tac "$FILE" | sed -r -e 's/.+\(//' -e 's/\);//' -e "s/',1,'/',TRUE,'/" -e "s/',0,'/',FALSE,'/" |
      awk -F, '{print $1FS$2FS$3FS$4FS$5FS$6FS"NULL"FS$8FS$9FS$10FS$11FS$12FS$13FS$14FS$15FS$16FS$17FS$18FS$19FS$20FS$21FS$24FS$25FS$26FS$27FS$22FS$23}' | while read s; do
        psql -U postgres -d openqa -c "INSERT INTO \"jobs\" VALUES($s)"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_job_groups_table()
{
    local FILE="$1-job_groups-$$"
    echo "Processing file [$FILE]"
    awk -F, 'BEGIN {OFS=","} ; ($12 == "1") { $12="TRUE" }; ($12 == "0") { $12="FALSE"}; ($5="NULL,"$5) {print $0}' "$FILE" | while read s; do
        psql -U postgres -d openqa -c "$s"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_needles_table()
{
    local FILE="$1-needle_dirs-$$"
    process_file "$FILE"
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
    FILE="$1-needles-$$"
    echo "Processing file [$FILE]"
    sed -r -e 's/.+\(//' -e 's/\);//' "$FILE" |
      awk -F, 'BEGIN {OFS=","} ($7 == "1") { $7="TRUE" }; ($7 == "0") { $7="FALSE" }; { $6="NULL,"$6 }; ($4="NULL") {print $0",NULL,current_date,current_date"}' | while read s; do
        psql -U postgres -d openqa -c "INSERT INTO \"needles\" VALUES($s)"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"

}

function process_screenshots_table()
{
    for FILE in "$1-screenshots-$$" "$1-screenshot_links-$$"; do
        process_file "$FILE"
        tail -1 "$FILE" >> $SEQSFILE
        report_num_rows "$FILE"
        rm "$FILE"
    done
}

function process_api_keys_table()
{
    local FILE="$1-api_keys-$$"
    grep -v 1234567890ABCDEF "$FILE" | while read s; do
        psql -U postgres -d openqa -c "$s"
    done
    tail -1 "$FILE" >> $SEQSFILE
    report_num_rows "$FILE"
    rm "$FILE"
}

function process_sequences()
{
    set +e
    sed -r -e 's/INSERT INTO \"([^\"]+)\" VALUES\(([0-9]+).+/alter sequence \1_id_seq restart with \2/' $SEQSFILE |
      awk '($NF++) {print $0";"}' | while read s; do
        psql -U postgres -d openqa -c "$s"
    done
    set -e
    rm $SEQSFILE
}

### Main

if [ -z "$1" ]; then
    error "Syntax: $(basename $0) import-file.db"
fi

SQLFILE="$1"
SEQSFILE="seqs.$$"

test -f "$SQLFILE" || error "File [$SQLFILE] does not exist"
split_into_tables "$SQLFILE"
process_users_table "$SQLFILE"
process_assets_table "$SQLFILE"
process_table "workers" "$SQLFILE"
process_jobs_table "$SQLFILE"
process_job_groups_table "$SQLFILE"
process_table "job_modules" "$SQLFILE"
process_needles_table "$SQLFILE"
process_screenshots_table "$SQLFILE"
process_api_keys_table "$SQLFILE"
set +e
process_table "audit_events" "$SQLFILE"
process_table "secrets" "$SQLFILE"
set -e
process_all_tables "$SQLFILE"
process_sequences
cleanup "$SQLFILE"
echo "DONE!"

