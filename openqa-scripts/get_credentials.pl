#!/usr/bin/perl

use strict;
use Mojo::URL;
use Mojo::UserAgent;
use Mojo::URL;
use Data::Dumper;

my $base_url = 'PUBLIC_CLOUD_CREDENTIALS_URL';
my $namespace = 'PUBLIC_CLOUD_NAMESPACE';
my $user = 'SECRET_PUBLIC_CLOUD_CREDENTIALS_USER';
my $pwd = 'SECRET_PUBLIC_CLOUD_CREDENTIALS_PWD';
my $url_sufix = shift . '.json'; # Can be aws, azure or gce
die "Syntax: $0 [azure|aws|gce]\n" if ($url_sufix eq '.json');
my $url = $base_url . '/' . $namespace . '/' . $url_sufix;

my $url_auth = Mojo::URL->new($url)->userinfo("$user:$pwd");
my $ua = Mojo::UserAgent->new;
$ua->insecure(1);
my $tx = $ua->get($url_auth);

die("Fetching CSP credentials failed: " . $tx->result->message) unless eval { $tx->result->is_success };
my $data_structure = $tx->res->json;

print Dumper $data_structure;

