#!/usr/bin/python
#
#
# Copyright (C) 2015  Glen Pitt-Pladdy
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
#TODO See: https://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
#

import classifier
import sqlite3
import sys
import re

if len(sys.argv) >= 5 and sys.argv[2] == 'classify' and sys.argv[3].isdigit() and sys.argv[4].isdigit():
	db = sqlite3.connect ( sys.argv[1] )
	classifier = classifier.classifier ( db, sys.stdin.read() )
	classifier.unbiased = True
	clases = [ int(x) for x in sys.argv[3:] ]
	prob = classifier.classify ( clases )
	for clas in clases:
		print "class%d: %f" % ( clas, prob[clas] )
elif len ( sys.argv ) >= 4 and len ( sys.argv ) <= 5 and sys.argv[2] == 'teach' and sys.argv[3].isdigit():
	db = sqlite3.connect ( sys.argv[1] )
	classifier = classifier.classifier ( db, sys.stdin.read() )
	if len ( sys.argv ) >= 4:
		classifier.teach ( int(sys.argv[3]) )
	else:
		classifier.teach ( int(sys.argv[3]), float ( sys.argv[4] ) )
elif len ( sys.argv ) == 2 and sys.argv[2] == 'updatequality':
	db = sqlite3.connect ( sys.argv[1] )
	classifier = classifier.classifier ( db, '' )
	classifier.unbiased = True
	classifier.updatequality ()
elif len ( sys.argv ) == 2 and sys.argv[2] == 'degrade' and re.match ( '^\d+(\.\d+)?$', sys.argv[3] ):
	db = sqlite3.connect ( sys.argv[1] )
	classifier = classifier.classifier ( db, '' )
	classifier.degrade ( sys.argv[3] )
else:
	sys.exit ( "Usage: %s <sqlite file> [teach <clasid> [weighting]|clasify <clasid> <clasid> [clasid] [...]|updatequality|degrade <factor>]\n\ttext on STDIN" % sys.argv[0] )


