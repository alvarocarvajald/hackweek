### Prometheus Installation

1. Add monitoring repository containing `prometheus` and `grafana` for the specific server OS. Check in `https://build.opensuse.org/project/packages_simple/server:monitoring` or use the `jcavalheiro:/monitoring` repositories from IBS which contain both `prometheus` and `grafana`. Examples (choose one):

```
zypper ar https://download.opensuse.org/repositories/server:/monitoring/SLE_12_SP3/server:monitoring.repo # Has prometheus, but not grafana
zypper ar http://download.suse.de/ibs/home:/jcavalheiro:/monitoring/SLE_12_SP3/home:jcavalheiro:monitoring.repo # Does not exists anymore
zypper ar http://download.suse.de/ibs/home:/jcavalheiro:/monitoring/SLE_12_SP4/home:jcavalheiro:monitoring.repo
zypper ar http://download.suse.de/ibs/home:/jcavalheiro:/monitoring/SLE_15/home:jcavalheiro:monitoring.repo
zypper ar http://download.suse.de/ibs/home:/jcavalheiro:/monitoring/openSUSE_Leap_42.3/home:jcavalheiro:monitoring.repo
```

On `gandalf.qa.suse.de`, initially the `jcavalheiro:/monitoring/SLE_12_SP3` repository was configured, and once that was removed, the repository was switched to `jcavalheiro:/monitoring/openSUSE_Leap_42.3`.

2. Install `prometheus` and `prometheus-node_exporter`:

```
zypper in golang-github-prometheus-prometheus
zypper in golang-github-prometheus-node_exporter
```

3. Configure prometheus storage in `/stats` and retention time:

```
mkdir -p /stats/prometheus
chown prometheus:prometheus /stats/prometheus
echo 'ARGS="--config.file=/etc/prometheus/prometheus.yml --storage.tsdb.path="/stats/prometheus/metrics/ --storage.tsdb.retention.time=365d"' > /etc/sysconfig/prometheus
```

4. Start `prometheus` and `prometheus-node_exporter`:

```
systemctl enable --now prometheus
systemctl enable --now prometheus-node_exporter
```

5. Configure local target by adding the following text to `/etc/prometheus/prometheus.yml`:

```yaml
  - job_name: 'gandalf'
    static_configs:
      - targets:
        - 'gandalf.qa.suse.de:9100'
```

6. Restart `prometheus`:

```
systemctl restart prometheus
```

7. Install and start `promethus-pushgateway`:

```
zypper in golang-github-prometheus-pushgateway
systemctl enable --now prometheus-pushgateway
```

8. Configure push gateway target by adding the following to `/etc/prometheus/prometheus.yml`:

```yaml
  - job_name: 'qacss-schwifty-sap_hana_pb_analize'
    honor_labels: true # ensure the original labels are not overwritten by Prometheus
    static_configs:
    - targets:
      - gandalf.qa.suse.de:9091
```

9. Restart `prometheus`:

```
systemctl restart prometheus
```

### Grafana Installation

1. Install `grafana` with:

```
zypper in grafana
```

2. Start `grafana`:

```
systemctl enable --now grafana-server
```

3. In order to allow access to the dashboards without authentication, modify the following in the `[auth.anonymous]` section of the  `/etc/grafana/grafana.ini` configuration file:

```
[auth.anonymous]
# enable anonymous access
enabled = true

# specify organization name that should be used for unauthenticated users
org_name = HANAonKVM
```

And then use the same organization name in *Configuration->Preferences* on the grafana UI.

### Script to push metrics

This directory also includes the `qacss-scwhifty-metrics.pl` perl script that can be used to explore recursively a directory and push the metrics found on `.csv` files to the prometheus push gateway. Before using the script, the following needs to be installed:

1. Add perl language repo for the OS version:

```
zypper ar https://download.opensuse.org/repositories/devel:/languages:/perl/SLE_12_SP3/devel:languages:perl.repo
```

2. Install perl modules required by `qacss-scwhifty-metrics.pl`:

```
zypper in perl-Mojolicious
zypper in perl-Text-CSV
```

3. Run the script without arguments for a quick help on how to use.

## Grafana Graphs

Start by creating a new dashboard.
Then create variables. Two types of variables are useful:

- Label variables: use any metric for the query (for example, loadtest_cputime), and then extract the label with a regexp. For example, hostname can be extracted with /host="([^"]+)"/, OS with /os="([^"]+)"/, HW Type with /hwtype="([^"]+)"/, etc.
- Metric variable: since the X axis for the graphs should contain the date of the test, which is being pushed as a metric label, the metrics themselves should be a variable to the graphs. The way to to this is to use Label Markers for the query, for example {host=~".+",os=~".+",numstreams=~".+",hwtype=~".+"}, and extract the metric name with a regexp as this one: /^([\w\_]+)/

For the graph:

1) The query must include the metric/testname as a variable, and any other variables that you'd like to match. For example:

{host=~".+",os=~".+",numstreams=~".+",hwtype=~".+",date=~".+",src_file=~"benchtpcds_[0-9]+"}

2) The query legend is the name that would appear in the X axis, so use {{date}}. This will group the metric values by date
3) The Min Time Interval should be set high to due to the use of the prometheus push gateway. Check with 1d, 1M or 1y

4) In Axes, X-Axis shoud be of Mode Series.
5) And then in Draw Modes, use Lines and Points instead of Bars, and Stack in Stacking & Null Value

6) Title of the graph should be the variable for the testname or metric name: $testname

Functions available: min, max, sum, count, last, median, diff, percent_diff, count_non_null
