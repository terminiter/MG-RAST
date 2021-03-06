#!/usr/bin/env perl

use strict;
use warnings;

use Data::Dumper;
use Getopt::Long;
use DBI;

my $job     = 0;
my $version = 1;
my $outdir  = "";
my $dbhost  = "";
my $dbname  = "";
my $dbuser  = "";
my $dbpass  = "";
my $dbcert  = "";
my $usage   = qq($0
  --job     ID of job to dump
  --version m5nr version #, default 1
  --outdir  output dir
  --dbhost  db host
  --dbname  db name
  --dbuser  db user
  --dbpass  db password
  --dbcert  db cert path
);

if ( (@ARGV > 0) && ($ARGV[0] =~ /-h/) ) { print STDERR $usage; exit 1; }
if ( ! GetOptions(
    'job:i'     => \$job,
    'version:i' => \$version,
    'outdir:s'  => \$outdir,
    'dbhost:s'  => \$dbhost,
	'dbname:s'  => \$dbname,
	'dbuser:s'  => \$dbuser,
	'dbpass:s'  => \$dbpass,
	'dbcert:s'  => \$dbcert
   ) ) {
  print STDERR $usage; exit 1;
}

unless ($job && $outdir) {
    print STDERR $usage; exit 1;
}

my $last_digit = 0;
if ($job =~ /^\d*(\d)$/) {
    $last_digit = $1;
    unless (-d "$outdir/$last_digit") {
        mkdir("$outdir/$last_digit");
    }
} else {
    print STDERR "Invalid job id"; exit 1;
}

my $dbh = DBI->connect(
    "DBI:Pg:dbname=$dbname;host=$dbhost;sslcert=$dbcert/postgresql.crt;sslkey=$dbcert/postgresql.key",
    $dbuser,
    $dbpass,
    {AutoCommit => 0}
);
unless ($dbh) { print STDERR "Error: " . $DBI::errstr . "\n"; exit 1; }
print STDERR "Export postgres tables for job $job\n";

print STDERR "md5 abundance data ... ";
my $query = "SELECT m.md5, j.abundance, j.exp_avg, j.ident_avg, j.len_avg, j.seek, j.length FROM job_md5s j, md5s m ".
            "WHERE j.version=$version AND j.job=$job AND j.md5=m._id AND j.exp_avg <= -3";
my $sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

my $md5num = 0;
open(MDUMP, ">$outdir/$last_digit/$job.job_md5s") or die "Couldn't open $outdir/$last_digit/$job.job_md5s for writing.\n";
while (my @row = $sth->fetchrow_array()) {
    my ($md5, $abund, $expa, $identa, $lena, $seek, $length) = @row;
    next unless ($md5 && $abund);
    my @out = (
        $version,
        $job,
        $md5,
        $abund,
        sprintf("%.3f", $expa),
        sprintf("%.3f", $identa),
        sprintf("%.3f", $lena),
        $seek || "",
        $length || ""
    );
    print MDUMP join(",", map { '"'.$_.'"' } @out)."\n";
    $md5num += 1;
}
print STDERR "$md5num md5 rows exported\n";
close(MDUMP);

print STDERR "lca abundance data ... ";
$query = "SELECT lca, abundance, exp_avg, ident_avg, len_avg, md5s, level FROM job_lcas WHERE version=$version AND job=$job AND exp_avg <= -3";
$sth = $dbh->prepare($query);
$sth->execute() or die "Couldn't execute statement: ".$sth->errstr;

my $lcanum = 0;
open(LDUMP, ">$outdir/$last_digit/$job.job_lcas") or die "Couldn't open $outdir/$last_digit/$job.job_lcas for writing.\n";
while (my @row = $sth->fetchrow_array()) {
    my ($lca, $abund, $expa, $identa, $lena, $md5s, $level) = @row;
    next unless ($lca && $abund);
    my @out = (
        $version,
        $job,
        $lca,
        $abund,
        sprintf("%.3f", $expa),
        sprintf("%.3f", $identa),
        sprintf("%.3f", $lena),
        $md5s || 0,
        $level || 0
    );
    print LDUMP join(",", map { '"'.$_.'"' } @out)."\n";
    $lcanum += 1;
}
print STDERR "$lcanum lca rows exported\n";
close(LDUMP);

print STDERR "job info ... ";
open(IDUMP, ">$outdir/$last_digit/$job.job_info") or die "Couldn't open $outdir/$last_digit/$job.job_info for writing.\n";
my $info = $dbh->selectrow_arrayref("SELECT updated_on FROM job_info WHERE version=$version AND job=$job");
if (@$info > 0) {
    print IDUMP join(",", map { '"'.$_.'"' } ($version, $job, $info->[0], $md5num, $lcanum, "true"))."\n";
}
print STDERR "exported\n";
close(IDUMP);

$dbh->disconnect;
