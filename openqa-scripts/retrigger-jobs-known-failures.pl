#!/usr/bin/perl

=head1 SYNOPSIS

    env config=/path/to/config/file.ini host=my.openqa.org exclude=SETTING:value,OTHER_SETTING:value /usr/share/openqa/script/retrigger-jobs-known-failures.pl JOBID

openQA job_done_hook script to restart failed jobs that match a criteria specified in a configuration file.

=head1 INSTALLATION

Clone this repository and copy the script and its configuration file in appropriate places. Since recent versions
of C<openQA-client> (at least on C<openQA-client-5.1758036156> and newer), script has to be located in the same
directory where C<openqa-cli> is located, usually C</usr/share/openqa/script>; otherwise it will fail to locate
some of the C<openQA-cient> assets which are usually installed under C</usr/share/openqa>.

If unsure where C<openqa-cli> is installed, this can be seen on the C<openQA-client> package information with
C<rpm -q -l openQA-client> or C<dpkg -L openqa-client> or with the command C<realpath $(which openqa-cli)>.

Configuration file can be installed anywhere where the openQA users can read the file, for example in
C</usr/local/share>.

After both script and configuration file are in their intended places, next step is to configure them in
C</etc/openqa/openqa.ini> as hooks. For example, by adding:

    job_done_hook_failed = env host=openqa.opensuse.org config=/usr/local/share/retrigger-jobs-known-failures.ini /usr/share/openqa/script/retrigger-jobs-known-failures.pl

=head1 OPTIONS

Script itself receives only one argument in the command line (the B<jobid>), but some options are available via
environment variables, as described below.

=over

=item B<config=/path/to/config/file.ini>

A configuration file with rules to determine which failed jobs are known and will require a restart. Currently there
are 3 types of rules, each corresponding to a section in the config file:

B<by_text>: job failed on a given test module, and the error text present in a failed detail matches the regular expression
defined in the configuration file.

B<by_text_all>: just like B<by_text> but it will attempt to match the regular expression in all detail screens, and not just
on failed ones. As such this option is slower, and more broad. Use with care.

B<by_number>: job failed on a given test module, and uploaded a specific number of test details. Can be a comma separated
list of values. As this option does not look for a specific error match, use with care.

For example, a configuration file would look like this:

    [by_number]
    some_test_module=21,23
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
use OpenQA::CLI;
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
        foreach my $confval (split(/,/, $config->{by_number}->{$testname})) {
            return 1 if ($screens == $confval);
        }
    }
    foreach my $type (qw(by_text by_text_all)) {
        if ($config->{$type}->{$testname}) {
            foreach my $i (@{$job->{details}}) {
                next if (($type eq 'by_text') and ($i->{result} ne 'fail'));
                return 1 if ($i->{text_data} && $i->{text_data} =~ /$config->{$type}->{$testname}/);
            }
        }
    }
    return 0;
}

sub usage {
    eval { require Pod::Usage; Pod::Usage::pod2usage(1); };
    die "cannot display help, install perl(Pod::Usage)\n" if $@;
}

# Main
my $api  = OpenQA::CLI->new() or die "Cannot instance OpenQA::CLI\n";
my $host = $ENV{host} ? $ENV{host} : 'openqa.opensuse.org';

usage unless ($jobid);

my @api_common = ('api', '--host', $host, '-X');
my ($stdout, $stderr, $retval) = capture { $api->run(@api_common, 'GET', '--pretty', "jobs/$jobid/details"); };
die "openqa-cli call failed with retval=[$retval] and err=[$stderr]\n" if ($retval || $stderr);
my $job = decode_json $stdout;
check_if_excluded($job->{job}->{settings}) if $ENV{exclude};
my $config = Config::Tiny->read($ENV{config}, 'utf8') if $ENV{config};
foreach my $t (@{$job->{job}->{testresults}}) {
    $api->run(@api_common, 'POST', "jobs/$jobid/restart") if (($t->{result} =~ /^(canceled|incomplete|failed)$/) && is_retriggerable($t, $config));
}

