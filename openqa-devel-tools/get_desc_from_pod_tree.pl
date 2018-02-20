use Pod::Tree;
$tree = Pod::Tree->new or die "cannot create object: $!\n";
$tree->load_file(shift) or die "cannot read file: $!\n";
$tree->get_root->set_filename('feature');
our %api_descriptions;
if ($tree->loaded() and $tree->has_pod()) {
    $tree->walk(\&_itemize);
    #    print $tree->dump, "\n";
}
else {
    print "fuck\n";
}
foreach $d (keys %api_descriptions) {
    print "Method: [$d]; Desc: [$api_descriptions{$d}]\n";
}

### Subs

sub _itemize {
    if (ref($_[0]) ne 'Pod::Tree::Node') {
        warn("_itemize() expected Pod::Tree::Node arg. Got " . ref($_[0]));
        return 0;    # Stop walking the tree
    }
    if ($_[0]->is_item()) {
        $filename   = $_[0]->get_filename;
        $methodname = _get_pod_text($_[0]);
        $methodname =~ s/\s+//g;
        $methodname =~ s/\(\)//;
        $a    = $_[0]->get_siblings();
        $desc = '';
        foreach $i (@$a) {
            unless ($desc) {
                $desc = $i->get_text()    if $i->is_text();
                $desc = _get_pod_text($i) if $i->is_ordinary();
            }
        }
        $api_descriptions{$filename . '#' . $methodname} = $desc;
    }
    else {
        return 1;    # Keep walking the tree
    }
}

sub _get_pod_text {
    my $retval = '';
    if (ref($_[0]) ne 'Pod::Tree::Node') {
        warn("_get_pod_text() expected Pod::Tree::Node arg. Got " . ref($_[0]));
    }
    else {
        my $argtype = $_[0]->get_type();
        unless ($argtype eq 'item' or $argtype eq 'ordinary') {
            warn("_get_pod_test() Pod::Tree::Node arg should be of type item or ordinary. Got [$argtype]");
        }
        my $children = $_[0]->get_children();
        if (defined $children->[0] and ref($children->[0]) eq 'Pod::Tree::Node') {
            if ($children->[0]->is_text) {
                $retval = $children->[0]->get_text();
                $retval =~ s/[\r\n]/ /g;
            }
            if ($children->[0]->is_sequence) {
                my $seqs = $children->[0]->get_children();
                if (defined $seqs->[0] and ref($seqs->[0]) eq 'Pod::Tree::Node' and $seqs->[0]->is_text) {
                    $retval = $seqs->[0]->get_text();
                }
            }
        }
    }
    return $retval;
}

