#!/usr/bin/php
<?php
/*
  Copyright (C) 2011  Glen Pitt-Pladdy

  This program is free software; you can redistribute it and/or
  modify it under the terms of the GNU General Public License
  as published by the Free Software Foundation; either version 2
  of the License, or (at your option) any later version.

  This program is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
  GNU General Public License for more details.

  You should have received a copy of the GNU General Public License
  along with this program; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.


  See: http://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
*/



require_once ( "classifier.php" );


if ( $argc >= 5 and $argv[2] == 'classify' and is_numeric ( $argv[3] ) and is_numeric ( $argv[4] ) ) {
	$dbh = new PDO ( "sqlite:$argv[1]" );
	$classifier = new classifier ( $dbh, file_get_contents ( 'php://stdin' ) );
	$classifier->unbiased = true;
	$classes = $argv;
	array_shift ( $classes ); array_shift ( $classes ); array_shift ( $classes );
	$prob = $classifier->classify ( $classes );
	for ( $i = 0; isset ( $classes[$i] ); ++$i ) {
		echo "class$classes[$i]: ".$prob[$classes[$i]]."\n";
	}
} elseif ( $argc >= 4 and $argc <= 5 and $argv[2] == 'teach' and is_numeric ( $argv[3] ) and ( $argc == 4 or is_numeric ( $argv[4] ) ) ) {
	$dbh = new PDO ( "sqlite:$argv[1]" );
	$classifier = new classifier ( $dbh, file_get_contents ( 'php://stdin' ) );
	if ( $argc == 4 ) {
		$classifier->teach ( $argv[3] );
	} else {
		$classifier->teach ( $argv[3], $argv[4] );
	}
} elseif ( $argc == 3 and $argv[2] == 'updatequality' ) {
	$dbh = new PDO ( "sqlite:$argv[1]" );
	$classifier = new classifier ( $dbh, '' );
	$classifier->unbiased = true;
	$classifier->updatequality ();
} elseif ( $argc == 4 and $argv[2] == 'degrade' and is_numeric ( $argv[3] ) ) {
	$dbh = new PDO ( "sqlite:$argv[1]" );
	$classifier = new classifier ( $dbh, '' );
	$classifier->degrade ( $argv[3] );
} else {
	die ( "Usage: $0 <sqlite file> [teach <classid> [weighting]|classify <classid> <classid> [classid] [...]|updatequality|degrade <factor>]\n\ttext on STDIN\n" );
}

?>
