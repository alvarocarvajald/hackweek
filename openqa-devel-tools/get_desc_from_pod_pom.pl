use Pod::POM;
$parser = Pod::POM->new()            or die "cannot create object: $!\n";
$tree   = $parser->parse_file(shift) or die "cannot read file: " . $parser->error();
my %methods_description;
_itemize($tree, 'feature');
foreach $i (keys %methods_description) {
    print "Method: [$i]; Desc: [$methods_description{$i}]\n";
}

sub _itemize {
    my $node = shift;
    if (ref($node) !~ /^Pod::POM::Node/) {
        log_warning("_itemize() expected Pod::POM::Node::* arg. Got " . ref($node));
        return 0;    # Stop walking the tree
    }
    my $controller = shift;

    foreach my $s ($node->content()) {
        my $type = $s->type();
        if ($type eq 'item') {
            _set_pod_desc($s, $controller);
        }
        else {
            foreach my $ss ($s->content()) {
                $type = $ss->type();
                if ($type eq 'item') {
                    _set_pod_desc($ss, $controller);
                }
                else {
                    foreach my $sss ($ss->content()) {
                        $type = $sss->type;
                        _set_pod_desc($sss, $controller) if ($type eq 'item');
                    }
                }
            }
            # _itemize($s, $controller);
        }
    }
}

sub _set_pod_desc {
    my $node = shift;
    if (ref($node) ne 'Pod::POM::Node::Item') {
        warn "_set_pod_desc() expected Pod::POM::Node::Item arg. Got " . ref($node) . "\n";
        return 0;    # Stop walking the tree
    }
    my $controller = shift;
    my $methodname = '';
    my $desc       = '';
    $methodname = $node->title;
    $desc       = $node->text;
    $methodname =~ s/\s+//g;
    $methodname =~ s/\(\)//;
    $desc =~ s/[\r\n]//g;
    my $key = $controller . '#' . $methodname;
    $methods_description{$key} = $desc;
}
