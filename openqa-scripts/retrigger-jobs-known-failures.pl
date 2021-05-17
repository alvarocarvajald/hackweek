#!/usr/bin/perl

=head1 SYNOPSIS

    env config=/path/to/config/file.ini host=my.openqa.org exclude=SETTING:value,OTHER_SETTING:value retrigger-jobs-known-failures.pl JOBID

openQA job_done_hook script to restart failed jobs that match a criteria specified in a configuration file.

=head1 OPTIONS

Script itself receives only one argument in the command line (the B<jobid>), but some options are available via
environment variables, as described below.

=over 4

=item B<config=/path/to/config/file.ini>

A configuration file with rules to determine which failed jobs are known and will require to be restarted. Currently there
are 2 types of rules, each corresponding to a section in the config file:

B<by_number>: job failed on a given test module, and uploaded a specific number of test details.

B<by_text>: job failed on a given test module, and the error text present in a failed detail matches the regular expression
defined in the configuration file.

For example, a configuration file would look like this:

    [by_number]
    some_test_module=21
    some_test_module#1=19
    other_test_module=5

    [by_text]
    some_test_module=systemctl --no-pager status wicked.+failed
    other_test_module=cannot access.+No such file or directory
    yet_another_test_module=cannot access.+No such file or directory|cannot touch.+Permission denied

In the above example, tests will be restarted if any of the following conditions are met:

Job failed in B<some_test_module> and it uploaded 21 detail items.

Job failed in B<some_test_module> and the cause as reported in one of the failed detail items contains a text
matching C<systemctl --no-pager status wicked.+failed>. 

Job failed in B<some_test_module#1> and it uploaded 19 detail items.

Job failed in B<other_test_module> and it uploaded 5 detail items.

Job failed in B<other_test_module> and the cause as reported in one of the failed detail items contains a text
matching C<cannot access.+No such file or directory>

Job failed in B<yet_another_test_module> and the cause as reported in one of the failed detail items contains
a text matching C<cannot access.+No such file or directory|cannot touch.+Permission denied>

A failed detail item, is a detail item where the B<result> is B<fail>.

=item B<host=my.openqa.org>

By default the script is configured to search for jobs and attempt job restarts on B<openqa.opensuse.org>. This
can be changed via the B<host> environment variable.

=item B<exclude=SETTING:value,OTHER_SETTING:value>

Skip restart of jobs that match some settings criteria. For example to avoid restarting jobs that failed on
B<x86_64>, run the script with B<exclude=arch:x86_64>. Multiple settings can be used separated by comma, for example
B<exclude=arch:x86_64,arch:aarch64,arch:s390x> would skip jobs where B<ARCH> is B<x86_64>, B<aarch64> or B<s390x>;
or B<exclude=arch:x86_64,flavor:Online> would skip jobs where B<ARCH> is B<x86_64> or where B<FLAVOR> is B<Online>.

Any setting can be used to exclude jobs. Setting name is case insensitive, setting value is case sensitive.

=back

=cut

use strict;
use warnings;

# Find openQA
BEGIN {
    my $openQAlib = '/usr/share/openqa/lib';

    eval { require RPM2 };
    unless ($@) {
        my $rpmdb = RPM2->open_rpm_db();
        my $i     = $rpmdb->find_by_name_iter('openQA-client');
        while (my $pkg = $i->next) {
            foreach my $file ($pkg->files) {
                if ($file =~ /lib$/) {
                    $openQAlib = $file;
                    last;
                }
            }
        }
    }
    unshift @INC, $openQAlib;
}

use Capture::Tiny qw(capture);
use OpenQA::CLI::api;
use JSON;
use Config::Tiny;

# Global vars
my $jobid = shift;

# Subs

sub check_if_excluded {
    my $job = shift;

    foreach my $i (split(/,/, $ENV{exclude})) {
        $i =~ /^(\w+):(\w+)$/;
        my $var = uc($1);

        if ($job->{$var} && $job->{$var} eq $2) {
            print "Skipping job [$jobid] by [$var:$2]\n";
            exit 0;
        }
    }
}

sub is_retriggerable {
    my $job      = shift;
    my $config   = shift;
    my $testname = $job->{name};
    print "Job [$jobid] failed on module [$testname]\n";
    return 0 unless ($config);
    if ($config->{by_number}->{$testname}) {
        my $screens = @{$job->{details}};
        return 1 if ($screens == $config->{by_number}->{$testname});
    }
    if ($config->{by_text}->{$testname}) {
        foreach my $i (@{$job->{details}}) {
            next unless ($i->{result} eq 'fail');
            return 1 if ($i->{text_data} && $i->{text_data} =~ /$config->{by_text}->{$testname}/);
        }
    }
    return 0;
}

sub usage {
    eval { require Pod::Usage; Pod::Usage::pod2usage(1); };
    die "cannot display help, install perl(Pod::Usage)\n" if $@;
}

# Main
my $api  = OpenQA::CLI::api->new() or die "Cannot instance OpenQA::CLI::api\n";
my $host = $ENV{host} ? $ENV{host} : 'openqa.opensuse.org';

usage unless ($jobid);

my ($stdout, $stderr, $retval) = capture { $api->run('--host', $host, '-X', 'GET', '--pretty', "jobs/$jobid/details"); };
die "openqa-cli call failed with retval=[$retval] and err=[$stderr]\n" if ($retval || $stderr);
my $job = decode_json $stdout;
check_if_excluded($job->{job}->{settings}) if $ENV{exclude};
my $config = Config::Tiny->read($ENV{config}, 'utf8') if $ENV{config};
foreach my $t (@{$job->{job}->{testresults}}) {
    $api->run('--host', $host, '-X', 'POST', "jobs/$jobid/restart") if ($t->{result} eq 'failed' && is_retriggerable($t, $config));
}

