### UCI Helpers START ###
sub uci_get_type_count()
{
    my ($config, $stype)=@_;
    my $cmd=sprintf('uci show %s|egrep vtun\.\@%s.*=%s|wc -l',$config,$stype,$stype);
    my $rc=`$cmd`;
    chomp($rc);
    return $rc;
}

sub uci_get_indexed_item()
{
    my ($config,$stype,$index,$key)=@_;
    my $cmd=sprintf('uci get %s.@%s[%s].%s',$config,$stype,$index,$key);
    $e=`$cmd`;
    chomp($e);
    return $e;
}

sub uci_set_indexed_option()
{
    my ($config,$stype,$index,$option,$val)=@_;
    my $cmd=sprintf('uci set %s.@%s[%s].%s=%s',$config,$stype,$index,$option,$val);
    $e=`$cmd`;
    #return $cmd;
    return $?;
}

sub uci_delete_indexed_type()
{
    my ($config,$stype,$index)=@_;
    my $cmd=sprintf('uci delete %s.@%s[%s]',$config,$stype,$index);

    $e=`$cmd`;
    print $?;
    return $?;
}
### UCI Helpers END ###

#weird uhttpd/busybox error requires a 1 at the end of this file
1

