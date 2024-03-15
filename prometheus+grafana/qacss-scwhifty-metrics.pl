#!/usr/bin/perl

use Getopt::Long;
use File::Basename;
use Sys::Hostname;
use IO::Dir;
use Mojo::UserAgent;
use Text::CSV;
use constant PUSH_PATH => '/metrics/job/batch/worker/';
use strict;

### Subs

sub syntax {
    my $name = basename($0);
    print <<EOF
Syntax: $name [--remove-metrics | --dir /path/to/results/directory] [--host prometheus_host]

Examples:

  - $name --remove-metrics --host some.host.local:
	removes all metrics submitted by this script in the current host in the host some.host.local

  - $name --dir /path/to/results/directory --host some.host.local:
	process files under /path/to/results/directory for metrics, and push those metrics to some.host.local

  - $name --dir /path/to/results/directory:
	same as previous command, but metrics are sent to the default host [gandalf.qa.suse.de]
EOF
;
    exit 0;
}

sub remove_metrics {
    my $pushgw   = shift;
    my $hostname = hostname;

    my $url = $pushgw . PUSH_PATH() . $hostname;
    my $ua  = Mojo::UserAgent->new or die "Cannot create Mojo::UserAgent instance: $!\n";
    my $tx  = $ua->delete($url);

    if (my $res = $tx->result) {
        die "Could not remove metrics for $hostname in $url: " . $res->code . ' ' . $res->message if $res->is_error;
    }
    exit 0;
}

sub push_metrics {
    my $pushgw   = shift;
    my $metric   = shift;
    my $hostname = hostname;
    my $data     = '';

    # $data should contain lines with "metric_name metric_value\n", otherwise post will fail
    if (ref $metric eq 'HASH') {
        foreach my $key (keys %$metric) {
            my ($file, $mname) = split('___', $key);
            $data .= "$mname $metric->{$key}\n";
        }
    }
    else {
        $data = $metric;
    }

    my $url = $pushgw . PUSH_PATH() . $hostname;
    my $ua  = Mojo::UserAgent->new or die "Cannot create Mojo::UserAgent instance: $!\n";
    my $tx  = $ua->post($url, {'Content-Type' => 'application/octet-stream'}, $data);

    if (my $res = $tx->result) {
        die "Could not push metrics for $hostname in $url: " . $res->code . ' ' . $res->message if $res->is_error;
    }
}

sub process_dir {
    my $path    = shift;
    my $metrics = shift;

    die "process_dir(): metrics must be HASHREF\n" unless (ref $metrics eq 'HASH');

    my %dir;
    tie %dir, 'IO::Dir', $path or die "cannot open [$path] directory: $!\n";

    foreach my $file (keys %dir) {
        next if $file eq '.' or $file eq '..';

        # Process CSV files or recurse into subdirectories. Skip everything else
        process_csv($path, $file, $metrics) if ($file =~ m/\.csv$/i);
        process_dir("$path/$file", $metrics) if (-d "$path/$file");
    }
}

sub process_csv {
    my ($path, $file, $metrics) = @_;

    # HASH to store metrics
    my %labels  = ();

    # Will need filename as part of the key for the metrics hash to avoid
    # overriding keys with the same names from different files
    my $tag = lc($file);
    $tag    =~ s/\.csv$//;
    $tag    =~ s/[^\w]/_/g;

    # Get test start date and host from path
    my ($year, $month, $day, $start_time, $host) = split('_', basename($path));
    my $hwtype = basename(dirname("/prometheus/BARE_METAL_12SP2/2018_09_12_0100_kvmhost2"));
    $hwtype =~ s/_([^_]+)$//;
    $labels{os}       = uc($1);
    $labels{date}     = $year . $month . $day . $start_time;
    $labels{host}     = $host;
    $labels{src_file} = $tag;
    $labels{hwtype}   = $hwtype;

    my $csv = Text::CSV->new({sep_char=> ";"}) or die "cannot create csv instance: $!\n";
    my $fh  = new IO::File "$path/$file" or die "cannot open file $path/$file: $!\n";

    if ($file =~ /^benchTP/) {
        metrics_from_chart($csv, $fh, $tag, test_labels(\%labels), 'benchtpcds', $metrics);
    }
    elsif ($file =~ /^SoltpBarrier/) {
        metrics_from_chart($csv, $fh, $tag, test_labels(\%labels), 'soltpbarrier', $metrics);
    }
    elsif ($file =~ /^VdmSingleQueries/) {
        metrics_from_vdm_single_query_fiile($csv, $fh, $tag, test_labels(\%labels), $metrics);
    }
    elsif ($file =~ /^VDM/) {
        metrics_from_chart($csv, $fh, $tag, test_labels(\%labels), 'vdm', $metrics);
    }
    elsif ($file =~ /^TPCDS/) {
        metrics_from_chart($csv, $fh, $tag, test_labels(\%labels), 'tpcds', $metrics);
    }
    else {
        die "Unrecognized file type: [$file]\n";
    }

    $fh->close();
}

sub test_labels {
    my $labels = shift;
    my $resp   = '';

    if (ref $labels eq 'HASH') {
        foreach my $key (keys %$labels) {
            $resp .= "$key=\"$labels->{$key}\",";
        }
        $resp =~ s/,$//;    # Strip last comma
    }

    return $resp;
}

sub quote_value {
    my ($key, $val) = split('=', $_[0]);
    return "$key=\"$val\"";
}

sub metrics_from_vdm_single_query_fiile {
    my ($csv, $fh, $tag, $labels, $metric) = @_;

    # First few lines of the file have control information. Will skip until chart starts
    my $in_chart = 0;

    while (my $row = $csv->getline($fh)) {
        next unless ($row->[0]);
        if ($row->[0] eq 'isBarrier') {
            $in_chart = 1;
            next;
        }
        next unless $in_chart;
        my $is_barrier     = lc($row->[0]);
        my $less_is_better = lc($row->[1]);
        my $category       = lc($row->[2]);
        $category          =~ s/[^\w]/_/g;
        my $profiler       = lc($row->[4]);
        my $profiler_path  = lc($row->[5]);
        my $config         = lc($row->[7]);
        my $script         = lc($row->[8]);
        my $metric_name    = join('_', lc($row->[10]), $category);
        $metric_name       = join('___', $tag, $metric_name);
        $metric_name .= "\{$labels,is_barrier=\"$is_barrier\",less_is_better=\"$less_is_better\",units=\"$row->[3]\",";
        $metric_name .= "profiler=\"$profiler\",profiler_path=\"$profiler_path\",config=\"$config\",script=\"$script\"\}";
        $metric->{$metric_name} = $row->[6];
    }
}

sub metrics_from_chart {
    my ($csv, $fh, $tag, $labels, $type, $metric) = @_;

    # First few lines of the file have control information. Will skip until chart starts
    my $in_chart = 0;

    while (my $row = $csv->getline($fh)) {
        next unless ($row->[0]);
        if ($row->[0] eq 'Chart') {
            $in_chart = 1;
            next;
        }
        next unless $in_chart;
        my $key = '';
        $key = benchtpcds_key($row, $labels) if $type eq 'benchtpcds';
        $key = vdm_key($row, $labels)        if $type eq 'vdm';
        $key = tpcds_key($row, $labels)      if $type eq 'tpcds';
        $key = soltp_key($row, $labels)      if $type eq 'soltpbarrier';

        $metric->{join('___', $tag, $key)} = $row->[2] if $key;
    }
}

sub benchtpcds_key {
    my ($row, $labels) = @_;

    my $metric_name = lc($row->[0]);
    $metric_name    =~ s/[^\w]/_/;
    my @params      = split(',', lc($row->[1]));
    $params[0]      = quote_value($params[0]);
    $params[1]      = quote_value($params[1]);
    $params[2]      = "type=\"$params[2]\"";
    return "$metric_name\{$labels," . join(',', @params) . "\}";
}

sub vdm_key {
    my ($row, $labels) = @_;

    my @xvalues     = split('_', lc($row->[1]));
    my $metric_name = $xvalues[0] eq 'query' ? join('_', $xvalues[0], $xvalues[1]) : $xvalues[0];
    $metric_name    = join('_', lc($row->[0]), $metric_name);
    return "$metric_name\{$labels,$xvalues[$#xvalues]=\"$xvalues[$#xvalues - 1]\"\}";
}

sub tpcds_key {
    my ($row, $labels) = @_;

    my $metric_name = '';
    if ($row->[0] =~ s/^TPCDS-//i) {
        $metric_name = lc($row->[1]);
        $metric_name =~ /_q(.+)/;
        my $qnum = $1;
        my @extra_labels = split(' ', lc($row->[0]));
        if (@extra_labels == 2) {
            $labels .= ",$extra_labels[0]=\"$extra_labels[1]\",class=\"none\"";
        }
        else {
            $labels .= ",$extra_labels[0]=\"$extra_labels[1]\",class=\"$extra_labels[2]\"";
        }
        $labels .= ",querynum=\"$qnum\"" if $qnum;
    }
    else {
        $metric_name = lc($row->[0]);
    }
    $metric_name =~ s/[^\w]/_/g;
    return "$metric_name\{$labels\}";
}

sub soltp_key {
    my ($row, $labels) = @_;

    my $desc        = $row->[1];
    my @metric_name = split(':', lc($row->[0]));
    $metric_name[0] =~ s/[^\w]/_/g;
    $metric_name[0] =~ s/___/_/;
    $metric_name[1] =~ s/^\s+//;
    return "$metric_name[0]\{$labels,desc=\"$desc\",details=\"$metric_name[1]\"\}";
}

### Main

my $host = 'gandalf.qa.suse.de';
my $port = '9091';
my $dir;
my $rm_metrics;

GetOptions("remove-metrics!" => \$rm_metrics, "dir=s" => \$dir, "host=s" => \$host, "port=s" => \$port) or syntax;

my $pushgw = "http://$host:$port";

remove_metrics $pushgw if $rm_metrics;

syntax unless $dir;

my %metrics = ();
process_dir $dir, \%metrics;    # Get metrics from dir
push_metrics $pushgw, \%metrics;

exit 0;

