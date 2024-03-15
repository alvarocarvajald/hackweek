#!/bin/bash -e
#
# qacss-scwhifty-metrics.sh - send PBO-styled results as metrics to prometheus push gateway

error()
{
    echo "ERROR: $@" >&2
    echo "Exiting..." >&2
    exit 1
}

syntax()
{
    echo "Syntax: $(basename $0) <--remove-metrics | /path/to/results/directory> [prometheus_host]

Examples:

  - $(basename $0) --remove-metrics some.host.local:
	removes all metrics submitted by this script in the current host in the host some.host.local

  - $(basename $0) /path/to/results/directory some.host.local:
	process files under /path/to/results/directory for metrics, and push those metrics to some.host.local

  - $(basename $0) /path/to/results/directory:
	same as previous command, but metrics are sent to the default host [gandalf.qa.suse.de]"
       
    exit 0
}

process_dir()
{
    cd $1
    for file in */*.csv; do
        local prefix=$(echo $file|sed -r -e 's@/@_@' -e 's/^[0-9]{4}_[0-9]{2}_[0-9]{2}_[0-9]{4}_//' -e 's/.csv$//' | tr 'A-Z' 'a-z')
        # Skip VdmSingleQueries for now as it's a special case
        echo $file | grep -q VdmSingleQueries && continue
        echo "process_file $file $prefix"
        process_file "$file" "$prefix"
    done
}

process_file()
{
    local FILE="$1"
    local PREFIX="$2"

    # Compose metrics
    tail -n +6 "$FILE" | sed -r -n -e 's/^/'$PREFIX'_/' -e 's/;/_/' -e 's/[,=@: \*\|\(\)\#\-]/_/g' -e 's/[A-Z]/\L&/g' -e 's/;/ /p' |
        curl -f --data-binary @- $PUSHGATEWAY_URL/metrics/job/batch/worker/$(hostname) || error "unable to update live metrics for file: $FILE"
}

remove_metrics()
{
    curl -X DELETE $PUSHGATEWAY_URL/metrics/job/batch/worker/$(hostname) || error "unable to remove metrics"
    exit 0
}

### Main

test $# -eq 1 -o $# -eq 2 || syntax

DIR="$1"
HOST=${2:-"gandalf.qa.suse.de"}

host "$HOST" >/dev/null 2>&1 || error "Cannot resolve push gateway host: $HOST"
PUSHGATEWAY_URL="http://$HOST:9091"

test "x$1" == "x--remove-metrics" && remove_metrics

test -d "$DIR" || error "$DIR is not a directory"

process_dir "$DIR"
exit 0
