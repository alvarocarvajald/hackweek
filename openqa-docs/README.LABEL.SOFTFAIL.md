# SUMMARY

Let's assume that for some reason, it is necessary to do a mass labeling of jobs to force some result into them; usually this would mean to force a `softfail` result on jobs that have failed.

Due to the nature of HA and SAP HanaSR jobs which rely on openQA's Multi-Machine testing, we would end up with some jobs with a failure, and the parallel jobs with the `parallel_failed` status.

We can use `openqa-cli` to push a comment into the job and force a result as follows:

```
openqa-cli api --osd -X POST jobs/$job_id/comments "text=label:force_result:softfailed:poo#1234567890"
```

So the problem to solve is how to feed the list of jobs to update to the `openqa-cli` call.

One approach is to collect openQA results URLs into a plain file, and process it with a pipeline. These openQA URLs would follow a format such as

```
https://openqa.suse.de/tests/overview?version=$VERSION&groupid=$GROUP&flavor=$FLAVOR&distri=sle&build=$SOMEBUILD
```

Once this are collected on a file (for example, `results-from-osd`), we can use a combination of `curl`, `openqa-cli` and a helper Perl script `get-parallel_failed-jobs.pl` (located also in this folder) to perform the mass update of the jobs.

## Example: iscsi_client failures tracked in poo#134282

The ticket poo#134282 describes an ongoing issue in osd where Multi-Machine jobs' networks are failing, causing HA and SAP HanaSR jobs to fail in the `iscsi_client` module (this is the first module in the test that attempts to connect to a service - iSCSI - in the support server).

The first step would be to filter out the `iscsi_client` failures from the result, and then force the `softfail` status to those tests. We can do this using the following command:

```
# for result in $(cat results-from-osd); do for job in $(curl --silent "$result" | grep modules/iscsi_client | cut -d/ -f3); do openqa-cli api --osd -X POST jobs/$job/comments "text=label:force_result:softfailed:poo#134282"; done; done
```

* Each result URL is downloaded with `curl`.
* Results which show `modules/iscsi_client` failing are filtered with `grep` and the job id is extracted from the line using `cut`. The result is place in the shell variable `$job`
* Finally, `$job` is updated using `openqa-cli`

But the previous action would only update the status of the failing jobs, leaving related jobs with `parallel_fail` status still present. We can also update these with the following command:

```
for res in $(cat results-from-osd); do for job in $(curl --silent "$res" | ./get-parallel_failed-jobs.pl); do openqa-cli api --osd -X POST jobs/$job/comments "text=label:force_result:softfailed:poo#134282"; done; done
```

