## retrigger-jobs-known-failures.pl

This perl script can be used together with openQA's `job_done_hook_failed` hook in `openqa.ini` to configure
automatic restart of jobs that fail on known issues.

Use requires 2 files:

* `retrigger-jobs-known-failures.pl`: the perl script itself. It should be installed in the same directory
where `openqa-cli` is installed, usually in `/usr/share/openqa/script`. It should be executable.
* `retrigger-jobs-known-failures.ini`: the configuration file. It should be readable by the openQA users
`geekotest` and `_openqa-worker`.

If installed in the openQA instance itself (where webUI and scheduler are located) all script dependencies
should already present. Otherwise, make sure script is installed in a system with openQA-client.

Other perl dependencies used are:

* RPM2
* Capture::Tiny
* JSON
* Config::Tiny

Script must be configured in `openqa.ini` under the `hooks` section in the `job_done_hook_failed` setting.
Below is an example of how it would look:
```
[hooks]
# Specify custom hook scripts format `job_done_hook_$result` to be called when
# a job is done. Any executable specified in the variable as absolute path or
# executable name in `$PATH` is called with the job ID as first and only
# parameter corresponding to the `$result`, for example
job_done_hook_failed = env host=openqa.opensuse.org config=/usr/local/share/retrigger-jobs-known-failures.ini /usr/share/openqa/script/retrigger-jobs-known-failures.pl
```
For more information, run `perldoc -U retrigger-jobs-known-failures.pl`.

## pvm_hmc-blocked-jobs.pl

Script to search for blocked jobs and stop and restart them.

This script must be added to the crontab of a system where openQA-worker and openQA-client are installed, where
once run it will determine the list of workers and check each workers' `autoinst-log.txt` for the date of the
last logged message; if the worker's last logged message is greater than a given time, it will consider the job
blocked, in which case it will send SIGTERM to the `os-autoinst` process associated to the job to terminate it,
and restart the job.

For more information, run `perldoc -U pvm_hmc-blocked-jobs.pl`.

