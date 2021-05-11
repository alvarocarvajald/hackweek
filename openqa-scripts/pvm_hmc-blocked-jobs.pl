#!/usr/bin/perl

=head1 SYNOPSIS

pvm_hmc-blocked-jobs.pl [OPTIONS]

Search for jobs on local pvm_hmc workers that have no activity for the past TIME
seconds, and cancel and restart them.

=head1 OPTIONS

=over 4

=item B<--host> HOST

Use HOST as the openQA WebUI where tests are scheduled from. This is used to
restart jobs automatically. If not specified, script will pick a host from
the system's C<client.conf> file or use B<localhost>.

=item B<--time> TIME

Time in seconds to determine when a job is considered blocked. Defaults to 900
seconds. If a job that matches the criteria has not logged messages for over TIME
seconds, it is considered blocked and will be canceled and restarted.

=item B<--pool> /path/to/pool

Specifies the location of the workers base pool directory. This is usually
extracted from information from the B<openQA-worker> RPM package, but this
command line option is supplied in case this is not possible and the pool
is not located in the default directory of C</var/lib/openqa/pool>.

=item B<--config> /path/to/workers.ini

Specifies the location of the workers.ini configuration file. This is usually
extraceted from information from the B<openQA-worker> RPM package, but this
command line option is supplied in case this is not possible and the file
is not located in the default location of C</etc/openqa/workers.ini>.

=item B<--quiet>

By default information messages are printed on STDOUT. This option disables them.

=cut

use strict;
use warnings;

my $openqaconfig;
my $clientconfig;
my $workers_basepath;
my $verbose = 1;

# Find openQA
BEGIN {
    my $openQAlib = '/usr/share/openqa/lib';

    eval { require RPM2; };
    unless ($@) {
        my $rpmdb = RPM2->open_rpm_db();
        my $i = $rpmdb->find_by_name_iter('openQA-client');
        while (my $pkg = $i->next) {
            foreach my $file ($pkg->files) {
                if ($file =~ /lib$/) {
                    $openQAlib = $file;
                    last;
                }
            }
        }
        my $is_worker = 0;
        $i = $rpmdb->find_by_name_iter('openQA-worker');
        while (my $pkg = $i->next) {
            $is_worker = 1;
            foreach my $file ($pkg->files) {
                $openqaconfig     = $file if ($file =~ /workers.ini$/);
                $workers_basepath = $file if ($file =~ /pool$/);
                $clientconfig     = $file if ($file =~ /client.conf$/);
            }
        }
        die "It seems this system does not have openQA-worker installed. Will not know what to look for" unless $is_worker;
        undef $i;
        undef $rpmdb;
    }
    unshift @INC, $openQAlib;
}

use Tie::File;
use Time::ParseDate;
use JSON;
use Config::Tiny;
use Mojo::File qw(path);
use OpenQA::CLI::api;
use Getopt::Long;
Getopt::Long::Configure("no_ignore_case");

# Default values
$workers_basepath //= '/var/lib/openqa/pool';
$openqaconfig     //= '/etc/openqa/workers.ini';
$clientconfig     //= '/etc/openqa/client.conf';
my $timetowait = 900;
my $api        = OpenQA::CLI::api->new() or die "Cannot instance OpenQA::CLI::api\n";
use constant logfile => 'autoinst-log.txt';

# Subs

sub log_msg {
    return unless $verbose;
    print "[", scalar(localtime), "] - ", join(' ', @_), "\n";
}

sub get_job_id {
    my $worker   = shift;
    my $jsontext = path($workers_basepath, $worker, 'job.json')->slurp;
    my $json     = decode_json $jsontext;
    return $json->{id};
}

sub get_pid {
    my $worker = shift;
    my $pid    = path($workers_basepath, $worker, 'os-autoinst.pid')->slurp;
    chomp $pid;
    return $pid;
}

sub cancel_job {
    my $pid = shift;
    return if ($pid == 1 or $pid == $$);
    log_msg "Killing os-autoinst process [$pid]";
    kill 'TERM', $pid;
}

sub restart_job {
    my $jobid = shift;
    my $host  = shift;
    return if ($jobid < 0);
    return unless $host;
    log_msg "Restarting job with id [$jobid]";
    $api->run('--host', $host, '-X', 'POST', "jobs/$jobid/restart")
}

sub usage {
    eval { require Pod::Usage; Pod::Usage::pod2usage(1); };
    die "cannot display help, install perl(Pod::Usage)\n" if $@;
}

# Main

my %options;

GetOptions(\%options, 'host=s', 'time=s', 'quiet|q', 'help|h|?', 'pool=s', 'config=s') or usage;
usage if $options{help};
$timetowait       = $options{time}   if $options{time};
$verbose          = 0                if $options{quiet};
$workers_basepath = $options{pool}   if $options{pool};
$openqaconfig     = $options{config} if $options{config};
unless ($options{host}) {
    my $config = Config::Tiny->read($clientconfig, 'utf8');
    $options{host} = (keys %$config)[0] || 'localhost';
    warn "WARN: No host specified with --host. Will use [$options{host}] to restart jobs";
}

log_msg "Starting";

my @ppc_workers = ();
my $config = Config::Tiny->read($openqaconfig, 'utf8');
foreach (keys %$config) {
    push @ppc_workers, $_ if ($config->{$_}->{LPAR_ID} && $config->{$_}->{WORKER_CLASS} eq 'hmc_ppc64le');
}

log_msg "Will check workers: [" . join('|', @ppc_workers) . "]";

# Todo:
# supply %text_to_match from config file or from command line

my %text_to_match = (
    'tests/installation/partitioning_finish.pm' => 'testapi::wait_still_screen'
);
my @lines;

foreach my $worker (@ppc_workers) {
    my $file = "$workers_basepath/$worker/" . logfile;
    next unless (-f $file);
    tie(@lines, 'Tie::File', $file);

    # Skip empty files
    next if ($#lines == -1);

    my $currenttime = time();
    # Skip jobs that don't have a proper time in the log's last line
    next unless ($lines[-1] =~ /^\[(\d{4}\-\d{2}\-\d{2}[A-Z]\d{2}:\d{2}\:\d{2}\.\d+ \w+)\]/);
    my $lastlogtime = parsedate($1);
    # Skip jobs with recent activity
    next unless (($currenttime - $lastlogtime) > $timetowait);

    while (my ($k, $v) = each %text_to_match) {
        if ($lines[-1] =~ /$v/ && $lines[-2] =~ /$k/) {
            my $jobid = get_job_id($worker);
            my $pid   = get_pid($worker);
            log_msg "Worker [$worker] working on job [$jobid] is stuck on [$k -> $v] for longer than $timetowait seconds";
            log_msg "Canceling and re-triggering job [$jobid]; os-autoinst PID: [$pid]";
	    cancel_job($pid);
            # wait some seconds for job to be canceled and restart
            sleep 5;
            restart_job($jobid, $options{host});
        }
    }
    untie @lines;
}

log_msg 'Done';

