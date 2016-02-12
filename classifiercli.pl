#!/usr/bin/perl
#
#
# Copyright (C) 2011  Glen Pitt-Pladdy
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
#
# See: https://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
#
use strict;
use warnings;
#BEGIN { unshift @INC, "/path/to/local/lib/perl/"; }
use classifier;
use DBI;

if ( $#ARGV >= 3 and $ARGV[1] eq 'classify' and $ARGV[2] =~ /^\d+$/ and $ARGV[3] =~ /^\d+$/ ) {
	my $dbh = DBI->connect ( "DBI:SQLite:dbname=$ARGV[0]",'','',{RaiseError=>+1,AutoCommit=>1} ) or die "Can't connect: ".$DBI::errstr;
	my $classifier = classifier->new ( $dbh, join ( '', <STDIN> ) );
	$classifier->{'unbiased'} = 1;
	my @classes = @ARGV;
	shift @classes; shift @classes;
	my @prob = $classifier->classify ( \@classes );
	for ( my $i = 0; defined $classes[$i]; ++$i ) {
		print "class$classes[$i]: ".$prob[$classes[$i]]."\n";
	}
} elsif ( $#ARGV >= 2 and $#ARGV <= 3 and $ARGV[1] eq 'teach' and $ARGV[2] =~ /^\d+$/ and ( $#ARGV == 2 or $ARGV[3] =~ /^[\d\.]+$/ ) ) {
	my $dbh = DBI->connect ( "DBI:SQLite:dbname=$ARGV[0]",'','',{RaiseError=>+1,AutoCommit=>1} ) or die "Can't connect: ".$DBI::errstr;
	my $classifier = classifier->new ( $dbh, join ( '', <STDIN> ) );
	if ( $#ARGV == 2 ) {
		$classifier->teach ( $ARGV[2] );
	} else {
		$classifier->teach ( $ARGV[2], $ARGV[3] );
	}
} elsif ( $#ARGV == 1 and $ARGV[1] eq 'updatequality' ) {
	my $dbh = DBI->connect ( "DBI:SQLite:dbname=$ARGV[0]",'','',{RaiseError=>+1,AutoCommit=>1} ) or die "Can't connect: ".$DBI::errstr;
	my $classifier = classifier->new ( $dbh, join ( '', '' ) );
	$classifier->{'unbiased'} = 1;
	$classifier->updatequality ();
} elsif ( $#ARGV == 2 and $ARGV[1] eq 'degrade' and $ARGV[2] =~ /^[\d\.]+$/ ) {
	my $dbh = DBI->connect ( "DBI:SQLite:dbname=$ARGV[0]",'','',{RaiseError=>+1,AutoCommit=>1} ) or die "Can't connect: ".$DBI::errstr;
	my $classifier = classifier->new ( $dbh, join ( '', '' ) );
	$classifier->degrade ( $ARGV[2] );
} elsif ( $#ARGV == 2 and $ARGV[1] eq 'cleanfrequency' and $ARGV[2] =~ /^[\d\.]+$/ ) {
	my $dbh = DBI->connect ( "DBI:SQLite:dbname=$ARGV[0]",'','',{RaiseError=>+1,AutoCommit=>1} ) or die "Can't connect: ".$DBI::errstr;
	my $classifier = classifier->new ( $dbh, join ( '', '' ) );
	$classifier->cleanfrequency ( $ARGV[2] );
} else {
	die "Usage: $0 <sqlite file> [teach <classid> [weighting]|classify <classid> <classid> [classid] [...]|updatequality|degrade <factor>]\n\ttext on STDIN\n";
}


