#
#
# Copyright (C) 2015  Glen Pitt-Pladdy
#
# This library is free software; you can redistribute it and/or
# modify it under the terms of the GNU Lesser General Public
# License as published by the Free Software Foundation; either
# version 2.1 of the License, or (at your option) any later version.
#
# This library is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
# Lesser General Public License for more details.
#
# You should have received a copy of the GNU Lesser General Public
# License along with this library; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA
#
#
# See: https://www.pitt-pladdy.com/blog/_20150707-214047_0100_Bayesian_Classifier_Classes_for_Python/
# Previously: https://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
#

# based on: http://en.wikipedia.org/wiki/Bayesian_spam_filtering#Computing_the_probability_that_a_message_containing_a_given_word_is_spam

import re
import time

class classifier:
	def __init__ ( self, db, text ):
		self.db = db;
		self.db.isolation_level = "DEFERRED"
		self.words = [ s[:40] for s in re.split ( '\W+', text.lower() ) ]	# TODO limit lengths in other flavours TODO
		self.s = 3
		self.unbiased = 0	# give even odds for all clases
		if str(type(self.db)) == "<class 'MySQLdb.connections.Connection'>":
			self.dbtype = 'MySQL'
		elif str(type(self.db)) == "<type 'sqlite3.Connection'>":
			self.dbtype = 'sqlite3'
	def teach ( self, classification, strength=None, ordered=None ):	# eg. 1=>HAM 2=>SPAM
		if strength == None: strength = 1.0
		if ordered == None: ordered = True
		prevwordid = None
		dbcur = self.db.cursor()
		# start transaction to avoid slow synchronous writes implied by isolation_level (above)
		for word in self.words:
			if word == '': continue
			# put the word in the classification as needed
			# never delete words so this should be race safe
			if self.dbtype == 'MySQL':
				dbcur.execute ( 'SELECT id FROM ClassifierWords WHERE Word = %s', [ word ] )
			else:
				dbcur.execute ( 'SELECT id FROM ClassifierWords WHERE Word = ?', [ word ] )
			result = dbcur.fetchone()
#			my $wordid;
			if result != None:
				# got it
				wordid = result[0]
			else:
				# oops - missing word - add it
				if self.dbtype == 'MySQL':
					dbcur.execute ( 'INSERT INTO ClassifierWords (Word) VALUES (%s) ON DUPLICATE KEY UPDATE Word=Word', [ word ] )
				else:
					dbcur.execute ( 'INSERT INTO ClassifierWords (Word) VALUES (?)', [ word ] )
				wordid = dbcur.lastrowid
			# SQLite has some limitations - work round them
			if self.dbtype == 'MySQL':
				# insert or update this word frequency
				dbcur.execute ( 'INSERT INTO ClassifierFrequency (Word,Class,Frequency) Values (%s,%s,%s) ON DUPLICATE KEY UPDATE Frequency = Frequency + %s', [ wordid, classification, strength, strength ] )
				# insert or update this word order frequency
				if ordered:
					dbcur.execute ( 'INSERT INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (%s,%s,%s,%s) ON DUPLICATE KEY UPDATE Frequency = Frequency + %s', [ wordid, prevwordid, classification, strength, strength ] )
			else:
				# long way rount for SQLite
				# insert or update this word frequency
				dbcur.execute ( 'INSERT OR IGNORE INTO ClassifierFrequency (Word,Class,Frequency) Values (?,?,0)', [ wordid, classification ] )
				dbcur.execute ( 'UPDATE ClassifierFrequency SET Frequency = Frequency + ? WHERE Word = ? AND Class = ?', [ strength, wordid, classification ] )
				# insert or update this word order frequency
				if ordered:
					dbcur.execute ( 'INSERT OR IGNORE INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (?,?,?,0)', [ wordid, prevwordid, classification ] )
					dbcur.execute ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency + ? WHERE Word = ? AND PrevWord = ? AND Class = ?', [ strength, wordid, prevwordid, classification ] )
			# set for next word
			prevwordid = wordid;
		if self.dbtype == 'MySQL':
			dbcur.execute ( 'INSERT INTO ClassifierClassSamples (Class,Frequency) VALUES (%s,%s) ON DUPLICATE KEY UPDATE Frequency = Frequency + %s', [ classification, strength, strength ] )
		else:
			# long way rount for SQLite
			dbcur.execute ( 'INSERT OR IGNORE INTO ClassifierClassSamples (Class,Frequency) VALUES (?,0)', [ classification ] );
			dbcur.execute ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency + ? WHERE Class = ?', [ strength, classification ] );
		self.db.commit()	# finish transaction to avoid slow synchronous writes
	def classify ( self, classifications, useorder=None ):	# $useorder = 0.0-1.0 for the factor of order information
		if useorder == None: useorder = 0.0
		qualityfactor = len( classifications )
		# we need to know how many samples of each clas to level the instances
		messages = {}
		total = 0
		bindclassifications = ''
		dbcur = self.db.cursor()
		for clas in classifications:
			if self.dbtype == 'MySQL':
				dbcur.execute ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = %s', [ clas ] )
			else:
				dbcur.execute ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = ?', [ clas ] )
			result = dbcur.fetchone()
			if result == None:
				# never seen this clas before - can't clasify
				return None
			messages[clas] = result[0]
			if messages[clas] == 0.0: messages[clas] = 1e-12	# use a safe tiny value so the math works
			total += messages[clas]
			if bindclassifications != '': bindclassifications += ','
			if self.dbtype == 'MySQL':
				bindclassifications += '%s';
			else:
				bindclassifications += '?';
		# work out overall probability of each clas
		overallprob = {}
		for clas in classifications:
			overallprob[clas] = messages[clas] / total
		# on with classification
		prevword = None
		prob = {}
		proborder = {}
		for clas in classifications:
			prob[clas] = 1
			proborder[clas] = 1
		for word in self.words:
			if word == '': continue
			# word frequency
			parameters = [ word ]
			parameters.extend ( classifications )
			if self.dbtype == 'MySQL':
				dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = %s) AND Class IN ('+bindclassifications+')', parameters )
			else:
				dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('+bindclassifications+')', parameters )
			results = dbcur.fetchall()
			wordfrequency = {}
			total = 0
			for result in results:
				wordfrequency[result[0]] = result[1] / messages[clas]
				total += result[1]
			for clas in classifications:
				if not clas in wordfrequency: wordfrequency[clas] = 0.0
			if total > 0:	# no point otherwise
				divisor = 0.0
				topline = {}
				for clas in classifications:
						# could divide this by $total to give the prob per clas, but it cancels anyway
						topline[clas] = wordfrequency[clas]
						if not self.unbiased: topline[clas] *= overallprob[clas]
						divisor += topline[clas]
				zerorisk = False	# flag if we have a risk of zeroing out
				for clas in classifications:
					probability = topline[clas] / divisor
					# correct for few occurances
					probability = self.s * overallprob[clas] + total * probability
					probability /= self.s + total
					# account for word quality
					quality = abs ( probability - 1.0/qualityfactor ) * qualityfactor
					if quality < 0.3: continue
					# combine
					prob[clas] *= probability
					# check risk of zeroing out
					if prob[clas] <= 1e-200: zerorisk = True
				# if needed normalise to avoid zeroing out (rounding)
				if zerorisk:
					ntotal = 0.0
					for clas in classifications:
						ntotal += prob[clas]
					# avoid divide by Zero - we have probably rounded if this happens
					if ntotal == 0: ntotal = 1.0
					# convert to normal probabilities
					for clas in classifications:
						prob[clas] /= ntotal
				# word order frequency
				count = 1
				parameters = [ word ]
				if prevword == None:
					parameters.extend ( classifications )
					if self.dbtype == 'MySQL':
						dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = %s) AND PrevWord IS NULL AND Class IN ('+bindclassifications+')', parameters )
					else:
						dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord IS NULL AND Class IN ('+bindclassifications+')', parameters )
				else:
					parameters.append ( prevword )
					parameters.extend ( classifications )
					if self.dbtype == 'MySQL':
						dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = %s) AND PrevWord = (SELECT id FROM ClassifierWords WHERE Word = %s) AND Class IN ('+bindclassifications+')', parameters )
					else:
						dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('+bindclassifications+')', parameters )
				results = dbcur.fetchall()
				total = 0
				for result in results:
					wordfrequency[result[0]] = result[1] / messages[clas]
					total += result[1]
				for clas in classifications:
					if not clas in wordfrequency: wordfrequency[clas] = 0.0
				if total > 0:	# no point otherwise
					divisor = 0.0
					for clas in classifications:
							topline[clas] = wordfrequency[clas]
							if not self.unbiased: topline[clas] *= overallprob[clas]
							divisor += topline[clas]
					zerorisk = False	# flag if we have a risk of zeroing out
					for clas in classifications:
						probability = topline[clas] / divisor
						# correct for few occurances
						probability = self.s * overallprob[clas] + total * probability
						probability /= self.s + total
						# account for word quality
						quality = abs ( probability - 1.0/qualityfactor ) * qualityfactor
						if quality < 0.3: continue
						# combine
						proborder[clas] *= probability
						# check risk of zeroing out
						if proborder[clas] <= 1e-200: zerorisk = True
					# if needed normalise to avoid zeroing out (rounding)
					if zerorisk:
						ntotal = 0.0
						for clas in classifications:
							ntotal += prob[clas]
						# avoid divide by Zero - we have probably rounded if this happens
						if ntotal == 0: ntotal = 1.0
						# convert to normal probabilities
						for clas in classifications:
							prob[clas] /= ntotal
			# set for next word
			prevword = word
		# finish up
		total = 0.0
		totalorder = 0.0
		for clas in classifications:
			total += prob[clas]
			totalorder += proborder[clas]
		# avoid divide by Zero - we have probably rounded if this happens
		if total == 0: total = 1.0
		if totalorder == 0: totalorder = 1.0
		# convert to normal probabilities
		for clas in classifications:
			prob[clas] /= total
			proborder[clas] /= totalorder
#		for clas in classifications:
#			print STDERR "scores: $clas => $prob[$clas]\n";
#			print STDERR "scoresorder: $clas => $proborder[$clas]\n";
		# combine
		if useorder > 0:
			usefreq = 1.0 - useorder
			for clas in classifications:
				probfreqweighted = prob[clas]**usefreq
				proborderweighted = proborder[clas]**useorder
				probcombined = probfreqweighted * proborderweighted
				prob[clas] = probcombined / ( probcombined + ( 1.0 - prob[clas] )**usefreq * ( 1.0 - proborder[clas] )**useorder )
#		for clas in classifications:
#			print STDERR "finalscores: $clas => $prob[$clas]\n";
		return prob
	# do degrading of existing data so that fresh data takes prescedence
	def degrade ( self, factor ):	# 0.9 would multiply everything by that
		dbcur = self.db.cursor()
		if self.dbtype == 'MySQL':
			dbcur.execute ( 'UPDATE ClassifierFrequency SET Frequency = Frequency * %s', [ factor ] )
			dbcur.execute ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency * %s', [ factor ] )
			dbcur.execute ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency * %s', [ factor ] )
		else:
			dbcur.execute ( 'UPDATE ClassifierFrequency SET Frequency = Frequency * :factor', [ factor ] )
			dbcur.execute ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency * :factor', [ factor ] )
			dbcur.execute ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency * :factor', [ factor ] )
		self.db.commit()	# finish transaction to avoid slow synchronous writes
	# remove words below a certain frequency (unlikely to be of value)
	def cleanfrequency ( self, threshold ):
		dbcur = self.db.cursor()
		if self.dbtype == 'MySQL':
			dbcur.execute ( 'DELETE FROM ClassifierFrequency WHERE Frequency < %s', [ threshold ] )
			dbcur.execute ( 'DELETE FROM ClassifierOrderFrequency WHERE Frequency < %s', [ threshold ] )
		else:
			dbcur.execute ( 'DELETE FROM ClassifierFrequency WHERE Frequency < :threshold', [ threshold ] )
			dbcur.execute ( 'DELETE FROM ClassifierOrderFrequency WHERE Frequency < :threshold', [ threshold ] )
		dbcur.execute ( 'DELETE FROM ClassifierWords WHERE id NOT IN (SELECT Word FROM ClassifierFrequency) AND id NOT IN (SELECT Word FROM ClassifierOrderFrequency) AND id NOT IN (SELECT PrevWord FROM ClassifierOrderFrequency WHERE PrevWord IS NOT NULL)' )
		self.db.commit()	# finish transaction to avoid slow synchronous writes
	# remove words below a certain quality (unlikely to be of value) TODO this is tricky since they may just be new ones
	# calculate quality factor for words
	def updatequality ( self, limit=None ):	# how many words to process (oldest first)
		dbcur = self.db.cursor()
		# get clases
		dbcur.execute ( 'SELECT DISTINCT Class FROM ClassifierFrequency' );
		classifications = [ row[0] for row in dbcur.fetchall() ]
		qualityfactor = len( classifications )
		# we need to know how many samples of each clas to level the instances
		messages = {}
		total = 0.0
		bindclassifications = ''
		for clas in classifications:
			if self.dbtype == 'MySQL':
				dbcur.execute ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = %s', [ clas ] );
			else:
				dbcur.execute ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = ?', [ clas ] );
			result = dbcur.fetchone ()
			if result == None:
				# never seen this clas before - can't clasify
				return None
			messages[clas] = result[0]
			total += result[0]
			if bindclassifications != '': bindclassifications += ','
			if self.dbtype == 'MySQL':
				bindclassifications += '%s'
			else:
				bindclassifications += '?'
		# work out overall probability of each clas
		overallprob = {}
		for clas in classifications:
			overallprob[clas] = messages[clas] / total
		# get words
		if limit != None:
			if limit.isdigit():
				dbcur.execute ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated LIMIT %d' % limit )
			else:
				return None
		else:
			dbcur.execute ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated' );
		words = [ row[0] for row in dbcur.fetchall() ]
		# process each word
		for word in words:
			# word frequency
			parameters = [ word ]
			parameters.extend ( classifications )
			if self.dbtype == 'MySQL':
				dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = %s) AND Class IN ('+bindclassifications+')', parameters );
			else:
				dbcur.execute ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('+bindclassifications+')', parameters );
			results = dbcur.fetchall()
			wordfrequency = {}
			total = 0.0
			for result in results:
				wordfrequency[result[0]] = result[1] / messages[result[0]]
				total += result[1]
			for clas in classifications:
				if not clas in wordfrequency:
					# no occurences of this word
					wordfrequency[clas] = 0.0
			divisor = 0.0
			topline = {}
			for clas in classifications:
				topline[clas] = wordfrequency[clas]
				if not self.unbiased: topline[clas] *= overallprob[clas]
				divisor += topline[clas]
			if divisor > 0.0:
				maxquality = 0.0
				for clas in classifications:
					probability = topline[clas] / divisor
					# correct for few occurances
					probability = self.s * overallprob[clas] + total * probability
					probability /= self.s + total
					# account for word quality
					quality = abs ( probability - 1.0/qualityfactor ) * qualityfactor
					if quality > maxquality: maxquality = quality
				if self.dbtype == 'MySQL':
					dbcur.execute ( 'UPDATE ClassifierWords SET Quality = %s, LastUpdated = %s WHERE Word = %s', [ maxquality, int(time.time()), word ] )
				else:
					dbcur.execute ( 'UPDATE ClassifierWords SET Quality = :quality, LastUpdated = :time WHERE Word = :word', [ maxquality, int(time.time()), word ] )
			else:
# TODO				print STDERR "WARNING - ".__FILE__." - no Frequency data for word \"$word\"\n";
				if self.dbtype == 'MySQL':
					dbcur.execute ( 'UPDATE ClassifierWords SET LastUpdated = %s WHERE Word = %s', [ int(time.time()), word ] )
				else:
					dbcur.execute ( 'UPDATE ClassifierWords SET LastUpdated = :time WHERE Word = :word', [ int(time.time()), word ] )
		self.db.commit()	# finish transaction to avoid slow synchronous writes


