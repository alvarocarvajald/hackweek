What I did?

## In WebUI Server

1) Add into /etc/rsync.conf:

[tests]
gid = nobody
uid = nobody
hosts allow = 10.162.2.79, 10.162.6.225, 10.162.6.226, 10.161.32.73, 10.162.31.142, 10.161.155.158, 10.161.155.159
path = /var/lib/openqa/share/tests
comment = OpenQA Test Distributions

And start rsyncd server with systemctl enable --now rsyncd

## In worker Server:

1) mkdir -p /var/lib/openqa/mango

2) Add into /etc/openqa/client.conf the API keys for the webui server

3) Add into /etc/openqa/workers.conf:

[mango.suse.de]
TESTPOOLSERVER = rsync://mango.suse.de/tests
SHARE_DIRECTORY = /var/lib/openqa/mango

4) Also edit in /etc/openqa/workers/conf in the list of hosts using the global cache

5) Restart workers

More info in: https://github.com/os-autoinst/openQA/blob/master/docs/Installing.asciidoc#configuring-worker-to-use-more-than-one-openqa-server
