use strict ;
use File::Find::Object::Rule;
use DBI;

my $filename;
my $af_vrf;
my $dbh_search;
my $config_line;
my $subconfig_line;
my $ios_flag;
my $nexus_flag;
my $neighbor_address;
my $bgp_as;
my $bgp_flag;
my $dbh;
my $neighbor_as;
my $hostname;
my $vrf_flag;
my $old_neighbor_address;
our $neighbor_hostname;
our $neighbor_interface;
my $shut;
my $description;
my $neighbor_vrf_name;
my $neighbor_ip_address;
my $subnet;
my @vrf_line;
my @input_files;
my @config_input;
my @bgp_line;
my @hostname_line;
my @searchrow;
my %bgpmatrix;
my $old_vrf;

my $ip_table_name = 'idc_ip_mappings';
my $table_name = 'idc_bgp_matrix';

my $config_directory = "../input_files/rancid_configs/";
@input_files = File::Find::Object::Rule->not_name('rancid_configs')->in($config_directory);

connect_to_database();
table_creation();


foreach my $filename (@input_files)  {

	$ios_flag = undef;
	$nexus_flag = undef;
	$bgp_flag = undef;
	$hostname = undef;
	$bgp_as = undef;
	$af_vrf = undef;
	$vrf_flag = undef;
	
#	$filename =~ s/\.\.\\input_files\\configuration_files\\//;
#	print "$filename\n";
	open (INPUTFILE, "<$filename") || die " Can't Open File: $filename $!\n";
	@config_input = <INPUTFILE> ;
	foreach $config_line (@config_input)  {
	
	$subconfig_line = $config_line;
	if ($subconfig_line =~ m/^(no service pad).*$/) {$ios_flag = 1}
	if ($subconfig_line =~ m/^(feature).*$/) {$nexus_flag = 1}
	if ($ios_flag eq 1)  {ios($subconfig_line)}
	if ($nexus_flag eq 1)  {nexus($subconfig_line)}
	}
	}
	
disconnect_from_database();

### If IOS
sub ios  {

	if ($subconfig_line=~ m/^(hostname).*$/)  {
		(@hostname_line)=split(' ',$subconfig_line)  ;
		$hostname = $hostname_line[1];
		}
		ios_pull_bgp ();
}

sub nexus  {
	if ($subconfig_line=~ m/^(hostname).*$/)  {
		(@hostname_line)=split(' ',$subconfig_line)  ;
		$hostname = $hostname_line[1];
		}
		nexus_pull_bgp ();
}


sub nexus_pull_bgp ($)  {
	$subconfig_line =~ s/\s+$//;
	$subconfig_line =~ s/^\s+//;
	
	if ($subconfig_line =~ m/^(router bgp).*$/)  {
		$bgp_flag = 1;
		(@bgp_line)=split(' ', $subconfig_line);
		$bgp_as = $bgp_line[2];
		print "$bgp_as\n";
	}
	if ($subconfig_line =~ m/^vrf\s.*$/)  {

		$vrf_flag = 1;
		(@vrf_line)=split(' ', $subconfig_line);

		$af_vrf = $vrf_line[1];

	} 
	if ($subconfig_line=~m/^.*neighbor\s([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\sremote-as\s([\d]+)/ && $bgp_flag eq 1)  {
		(@bgp_line)=split(' ', $subconfig_line);
		$neighbor_address = $bgp_line[1];
		$neighbor_as = $bgp_line[3];
		chomp $neighbor_address;
		chomp $neighbor_as;
		$bgpmatrix{$af_vrf}{ 'Neighbor_Address' } = $neighbor_address;
		$bgpmatrix{$af_vrf}{ 'Neighbor_AS' } = $neighbor_as;
		lookup_interface();
	}
	
	if (($neighbor_address ne $old_neighbor_address or $af_vrf ne $old_vrf)  && ($bgp_flag eq 1 && $vrf_flag eq 1)){
	$old_neighbor_address = $neighbor_address;
	$old_vrf = $af_vrf;
	
	write_to_database ();
	}
	
	if ($config_line=~ m/^(\!).*$/ && $vrf_flag eq 1)  {$vrf_flag = undef}
}

sub ios_pull_bgp ($)  {

	$subconfig_line =~ s/\s+$//;
	$subconfig_line =~ s/^\s+//;	
	if ($subconfig_line =~ m/^(router bgp).*$/)  {
		$bgp_flag = 1;
		(@bgp_line)=split(' ', $subconfig_line);
		$bgp_as = $bgp_line[2];
	}
	if ($subconfig_line =~  m/^address-family ipv4 vrf\s.*/)  {
		$vrf_flag = 1;
		(@vrf_line)=split(' ', $subconfig_line);
		$af_vrf = $vrf_line[3];
	} 
	if ($subconfig_line=~m/^.*neighbor\s([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\.([0-9]{1,3})\sremote-as\s([\d]+)/ && $bgp_flag eq 1)  {
	(@bgp_line)=split(' ', $subconfig_line);
	$neighbor_address = $bgp_line[1];
	$neighbor_as = $bgp_line[3];
	chomp $neighbor_address;
	chomp $neighbor_as;
	
	$bgpmatrix{$af_vrf}{ 'Neighbor_Address' } = $neighbor_address;
	$bgpmatrix{$af_vrf}{ 'Neighbor_AS' } = $neighbor_as;
	
	lookup_interface();
	}
	if ($neighbor_address ne $old_neighbor_address && $bgp_flag eq 1 && $vrf_flag  eq 1){
	$old_neighbor_address = $neighbor_address;
	write_to_database ();
	}
	
	if ($config_line=~ m/^(\!).*$/ && $vrf_flag eq 1)  {$vrf_flag = undef}
}


sub lookup_interface  {

	my $sql_search = "select DISTINCT * from $ip_table_name WHERE ip_address RLIKE '$neighbor_address' ";
	my $sth_search = $dbh_search->prepare($sql_search);
	$sth_search->execute or die "SQL Error: $DBI::errstr\n";
	$sth_search->bind_columns(\$neighbor_hostname,\$neighbor_interface,\$shut,\$description,\$neighbor_vrf_name,\$neighbor_ip_address,\$subnet);
	
	while (@searchrow = $sth_search->fetchrow_array)  {
	}

}

sub write_to_database   {

#	print "$hostname $bgp_as ";
	my $bgpmatrix = \%bgpmatrix;
	for $af_vrf (keys  %$bgpmatrix  )   {
	my $neighbor_address = $bgpmatrix->{$af_vrf}{ 'Neighbor_Address' };
	my $neighbor_as = $bgpmatrix->{$af_vrf}{ 'Neighbor_AS' };
	}
	print "$af_vrf $neighbor_address $neighbor_as $neighbor_hostname $neighbor_interface \n";
	
	print "Inserting data into table for $hostname\n";
	my $table_insert = $dbh->prepare ("INSERT INTO $table_name(hostname,local_as,vrf,neighbor_ip,neighbor_as,neighbor_switch,neighbor_int)
	VALUES ('$hostname','$bgp_as','$af_vrf','$neighbor_address','$neighbor_as','$neighbor_hostname','$neighbor_interface')");	

	$table_insert->execute(); 
	
	$neighbor_hostname = undef;
	$neighbor_interface = undef;
	$shut =undef;
	$description = undef;
	$neighbor_vrf_name = undef;
	$neighbor_ip_address = undef;
	$subnet = undef;
	
	
	}

 sub table_creation {

	my $sth=$dbh->table_info("", "", $table_name, "TABLE");

	if ($sth->fetch) {
		print "Table Exists\n";
		my $sql = "drop table $table_name";
		my $sth = $dbh->prepare($sql);
		$sth->execute ;
		print "Table Removed\n";
	}
		print "Need to Create Table\n";
		my $sql = "CREATE TABLE $table_name (hostname VARCHAR(40),local_as VARCHAR(10),vrf VARCHAR(20),neighbor_ip VARCHAR(20),
		neighbor_as VARCHAR(20),neighbor_switch VARCHAR(20),neighbor_int VARCHAR(40));";
		my $sth = $dbh->prepare($sql);
		$sth->execute ;
		
		print "Table Created\n";
	
}

sub connect_to_database  {

	$dbh = DBI->connect('DBI:mysql:mysql:172.27.144.8','remoteuser', 'password'
	           ) || die "Could not connect to database: $DBI::errstr";
	$dbh_search = DBI->connect('DBI:mysql:mysql:172.27.144.8','remoteuser', 'password'
	           ) || die "Could not connect to database: $DBI::errstr";

}

sub disconnect_from_database()  {

	$dbh->disconnect();
	$dbh_search->disconnect();
}