### UCI Helpers START ###
sub uci_get_sectiontype_count()
{
    my ($config, $stype)=@_;
    my $cmd=sprintf('uci show %s|egrep vtun\.\@%s.*=%s|wc -l',$config,$stype,$stype);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

sub uci_get_indexed_option()
{
    my ($config,$stype,$index,$key)=@_;
    my $cmd=sprintf('uci get %s.@%s[%s].%s',$config,$stype,$index,$key);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

sub uci_get_indexed_sectiontype()
{
    my ($config,$stype,$index)=@_;
    my $cmd=sprintf('uci get %s.@%s[%s]',$config,$stype,$index);
    my @res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc, @res);
}

# RETURNS an array of hashes
sub uci_get_all_by_sectiontype()
{
    my ($config,$stype)=@_;
    my @sections=();

    my $cmd=sprintf('uci show %s|grep %s.@%s',$config,$config,$stype);
    my @lines=`$cmd`;
    my $lastindex=0;
    my $sect={};
    my @parts=();
    foreach $l (0..@lines-1) {
        @parts=();
        chomp(@lines[$l]);
        @parts = @lines[$l] =~ /^$config\.\@$stype\[(.*)\]\.(.*)\=(.*)/g;1;
        if (scalar(@parts) eq 3) {
            if (@parts[0] ne $lastindex) {
                push @sections, $sect;
                $sect={};
                $lastindex=@parts[0];
            }
            $sect->{@parts[1]} = @parts[2];
            next;
        }        
    }
    push (@sections, $sect); 
    return (@sections);
}

sub uci_add_sectiontype()
{
    my ($config,$stype)=@_;
    my $cmd=sprintf('uci add %s %s',$config,$stype);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

sub uci_delete_sectiontype()
{
    my ($config,$stype)=@_;
    my $cmd=sprintf('uci delete %s.%s',$config,$stype);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}
sub uci_set_indexed_option()
{
    my ($config,$stype,$index,$option,$val)=@_;
    my $cmd=sprintf('uci set %s.@%s[%s].%s=%s',$config,$stype,$index,$option,$val);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

sub uci_delete_indexed_type()
{
    my ($config,$stype,$index)=@_;
    my $cmd=sprintf('uci delete %s.@%s[%s]',$config,$stype,$index);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

sub uci_commit()
{
    my ($config)=@_;
    my $cmd=sprintf('uci commit %s',$config);
    my $res=`$cmd`;
    my $rc=$?;
    return ($rc);
}

sub uci_revert()
{
    my ($config)=@_;
    my $cmd=sprintf('uci revert %s',$config);
    my $res=`$cmd`;
    my $rc=$?;
    chomp($res);
    return ($rc,$res);
}

### UCI Helpers END ###
sub DEBUGEXIT()
{
    my ($text) = @_;
    http_header();
    html_header("$node setup", 1);
    print "DEBUG-";
    print $text;
    print "</body>";
    exit;
}


#weird uhttpd/busybox error requires a 1 at the end of this file
1

