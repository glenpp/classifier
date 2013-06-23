#
#
# Copyright (C) 2011  Glen Pitt-Pladdy
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
# See: http://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
#

# based on: http://en.wikipedia.org/wiki/Bayesian_spam_filtering#Computing_the_probability_that_a_message_containing_a_given_word_is_spam

	package classifier;
	use strict;
	use warnings;
	sub new {
		my ( $class, $dbh, $text ) = @_;
		my $self = {};
		$self->{'dbh'} = $dbh;
		my @words = split /\W+/, lc ( $text );
		$self->{'words'} = \@words;
		$self->{'s'} = 3;
		$self->{'unbiased'} = 0;
		return bless $self, $class;
	}
	sub teach {
		my ( $self, $classification, $strength, $ordered ) = @_;	# eg. 1=>HAM 2=>SPAM
		if ( ! defined $strength ) { $strength = 1; }
		if ( ! defined $ordered ) { $ordered = 1; }
		my $st;
		my $prevwordid;
		$self->{'dbh'}->begin_work ();	# start transaction to avoid slow synchronous writes
		foreach my $word (@{$self->{'words'}}) {
			if ( $word eq '' ) { next; }
			# put the word in the classification as needed
			# never delete words so this should be race safe
			$st = $self->{'dbh'}->prepare ( 'SELECT id FROM ClassifierWords WHERE Word = :word' );
			$st->execute ( $word );
			my $result = $st->fetchrow_hashref ();
			my $wordid;
			if ( exists $$result{'id'} ) {
				# got it
				$wordid = $$result{'id'};
			} else {
				# oops - missing word - add it
				$st = $self->{'dbh'}->prepare ( 'INSERT INTO ClassifierWords (Word) VALUES (:word)' );
				$st->execute ( $word );
				$wordid = $self->{'dbh'}->last_insert_id ( '','','','' );
			}
			# SQLite has some limitations - work round them
			if ( $self->{'dbh'}->{'Driver'}->{'Name'} ne 'SQLite' ) {
				# insert or update this word frequency
				$st = $self->{'dbh'}->prepare ( 'INSERT INTO ClassifierFrequency (Word,Class,Frequency) Values (:wordid,:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
				$st->execute ( $wordid, $classification, $strength );
				# insert or update this word order frequency
				if ( $ordered ) {
					$st = $self->{'dbh'}->prepare ( 'INSERT INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (:wordid,:prevwordid,:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
					$st->execute ( $wordid, $prevwordid, $classification, $strength );
				}
			} else {
				# long way rount for SQLite
				# insert or update this word frequency
				$st = $self->{'dbh'}->prepare ( 'INSERT OR IGNORE INTO ClassifierFrequency (Word,Class,Frequency) Values (:wordid,:class,0)' );
				$st->execute ( $wordid, $classification );
				$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierFrequency SET Frequency = Frequency + :strength WHERE Word = :wordid AND Class = :class' );
				$st->execute ( $strength, $wordid, $classification );
				# insert or update this word order frequency
				if ( $ordered ) {
					$st = $self->{'dbh'}->prepare ( 'INSERT OR IGNORE INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (:wordid,:prevwordid,:class,0)' );
					$st->execute ( $wordid, $prevwordid, $classification );
					$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency + :strength WHERE Word = :wordid AND PrevWord = :prevwordid AND Class = :class' );
					$st->execute ( $strength, $wordid, $prevwordid, $classification );
				}
			}
			# set for next word
			$prevwordid = $wordid;
		}
		if ( $self->{'dbh'}->{'Driver'}->{'Name'} ne 'SQLite' ) {
			$st = $self->{'dbh'}->prepare ( 'INSERT INTO ClassifierClassSamples (Class,Frequency) VALUES (:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
			$st->execute ( $classification, $strength );
		} else {
			# long way rount for SQLite
			$st = $self->{'dbh'}->prepare ( 'INSERT OR IGNORE INTO ClassifierClassSamples (Class,Frequency) VALUES (:class,0)' );
			$st->execute ( $classification );
			$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency + :strength WHERE Class = :class' );
			$st->execute ( $strength, $classification );
		}
		$self->{'dbh'}->commit();	# finish transaction to avoid slow synchronous writes
	}
	sub classify {
		my ( $self, $classifications, $useorder ) = @_;	# $useorder = 0-1 for the factor of order information
		if ( ! defined $useorder ) { $useorder = 0; }
		my $qualityfactor = $#$classifications + 1;
		my $st;
		# we need to know how many samples of each class to level the instances
		my @messages;
		my $total = 0;
		my $bindclassifications = '';
		foreach my $class (@$classifications) {
			$st = $self->{'dbh'}->prepare ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = :class' );
			$st->execute ( $class );
			my $result = $st->fetchrow_hashref ();
			if ( ! defined $$result{'Frequency'} ) {
				# never seen this class before - can't classify
				return undef;
			}
			$messages[$class] = $$result{'Frequency'};
			$total += $$result{'Frequency'};
			if ( $bindclassifications ne '' ) { $bindclassifications .= ','; }
			$bindclassifications .= '?';
		}
		# work out overall probability of each class
		my @overallprob;
		foreach my $class (@$classifications) {
			$overallprob[$class] = $messages[$class] / $total;
		}
		# on with classification
		my $prevword;
		my @prob;
		my @proborder;
		foreach my $class (@$classifications) {
			$prob[$class] = 1;
			$proborder[$class] = 1;
		}
		foreach my $word (@{$self->{'words'}}) {
			if ( $word eq '' ) { next; }
			# word frequency
			$st = $self->{'dbh'}->prepare ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
			my $count = 1;
			$st->bind_param ( $count++, $word );
			foreach my $class (@$classifications) { $st->bind_param ( $count++, $class ); }
			$st->execute ();
			my $results = $st->fetchall_hashref ( 'Class' );
			my %wordfrequency;
			$total = 0;
			foreach my $class (@$classifications) {
				if ( defined $$results{$class}{'Frequency'} ) {
					$wordfrequency{$class} = $$results{$class}->{'Frequency'} / $messages[$class];
					$total += $$results{$class}->{'Frequency'};
				} else {
					# no occurences of this word
					$wordfrequency{$class} = 0;
				}
			}
			if ( $total > 0 ) {	# no point otherwise
				my $divisor = 0;
				my @topline;
				foreach my $class (@$classifications) {
						# could divide this by $total to give the prob per class, but it cancels anyway
						$topline[$class] = $wordfrequency{$class};
						if ( ! $self->{'unbiased'} ) { $topline[$class] *= $overallprob[$class]; }
						$divisor += $topline[$class];
				}
				foreach my $class (@$classifications) {
					my $probability = $topline[$class] / $divisor;
					# correct for few occurances
					$probability = $self->{'s'} * $overallprob[$class] + $total * $probability;
					$probability /= $self->{'s'} + $total;
					# account for word quality
					my $quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
					if ( $quality < 0.3 ) { next; }
					# combine
					$prob[$class] *= $probability;
				}
					# word order frequency
				my $count = 1;
				if ( ! defined $prevword ) {
					$st = $self->{'dbh'}->prepare ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord IS NULL AND Class IN ('.$bindclassifications.')' );
					$st->bind_param ( $count++, $word );
				} else {
					$st = $self->{'dbh'}->prepare ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
					$st->bind_param ( $count++, $word );
					$st->bind_param ( $count++, $prevword );
				}
				foreach my $class (@$classifications) { $st->bind_param ( $count++, $class ); }
				$st->execute ();
				my $results = $st->fetchall_hashref ( 'Class' );
				$total = 0;
				foreach my $class (@$classifications) {
					if ( defined $$results{$class}->{'Frequency'} ) {
						$wordfrequency{$class} = $$results{$class}->{'Frequency'} / $messages[$class];
						$total += $$results{$class}->{'Frequency'};
					} else {
						# no occurences of this word
						$wordfrequency{$class} = 0;
					}
				}
				if ( $total > 0 ) {	# no point otherwise
					$divisor = 0;
					foreach my $class (@$classifications) {
							$topline[$class] = $wordfrequency{$class};
							if ( ! $self->{'unbiased'} ) { $topline[$class] *= $overallprob[$class]; }
							$divisor += $topline[$class];
					}
					foreach my $class (keys %wordfrequency) {
						my $probability = $topline[$class] / $divisor;
						# correct for few occurances
						$probability = $self->{'s'} * $overallprob[$class] + $total * $probability;
						$probability /= $self->{'s'} + $total;
						# account for word quality
						my $quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
						if ( $quality < 0.3 ) { next; }
						# combine
						$proborder[$class] *= $probability;
					}
					# TODO normalise to avoid zeroing out (rounding) TODO
				}
			}
			# set for next word
			$prevword = $word;
		}
		# finish up
		$total = 0;
		my $totalorder = 0;
		foreach my $class (@$classifications) {
			$total += $prob[$class];
			$totalorder += $proborder[$class];
		}
		foreach my $class (@$classifications) {
			$prob[$class] /= $total;
			$proborder[$class] /= $totalorder;
		}
#foreach my $class (@$classifications) {
#	print STDERR "scores: $class => $prob[$class]\n";
#	print STDERR "scoresorder: $class => $proborder[$class]\n";
#}
		# combine
		if ( $useorder > 0 ) {
			my $usefreq = 1 - $useorder;
			foreach my $class (@$classifications) {
				my $probfreqweighted = $prob[$class]**$usefreq;
				my $proborderweighted = $proborder[$class]**$useorder;
				my $probcombined = $probfreqweighted * $proborderweighted;
				$prob[$class] = $probcombined / ( $probcombined + ( 1 - $prob[$class] )**$usefreq * ( 1 - $proborder[$class] )**$useorder );
			}
		}
#foreach my $class (@$classifications) {
#	print STDERR "finalscores: $class => $prob[$class]\n";
#}
		return @prob;
	}
	# do degrading of existing data so that fresh data takes prescedence
	sub degrade {
		my ( $self, $factor ) = @_;	# 0.9 would multiply everything by that
		my $st;
		$self->{'dbh'}->begin_work ();	# start transaction to avoid slow synchronous writes
		$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierFrequency SET Frequency = Frequency * :factor' );
		$st->execute ( $factor );
		$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency * :factor' );
		$st->execute ( $factor );
		$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency * :factor' );
		$st->execute ( $factor );
		$self->{'dbh'}->commit();	# finish transaction to avoid slow synchronous writes
	}
	# calculate quality factor for words
	sub updatequality {
		my ( $self, $limit ) = @_;	# how many words to process (oldest first)
		my $st;
		# get classes
		$st = $self->{'dbh'}->prepare ( 'SELECT DISTINCT Class FROM ClassifierFrequency' );
		$st->execute ();
		my $classifications = $st->fetchall_arrayref ();
		my $qualityfactor = $#$classifications + 1;
		# we need to know how many samples of each class to level the instances
		my @messages;
		my $total = 0;
		my $bindclassifications = '';
		foreach my $class (@$classifications) {
			$st = $self->{'dbh'}->prepare ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = :class' );
			$st->execute ( $$class[0] );
			my $result = $st->fetchrow_hashref ();
			if ( ! defined $$result{'Frequency'} ) {
				# never seen this class before - can't classify
				return undef;
			}
			$messages[$$class[0]] = $$result{'Frequency'};
			$total += $$result{'Frequency'};
			if ( $bindclassifications ne '' ) { $bindclassifications .= ','; }
			$bindclassifications .= '?';
		}
		# work out overall probability of each class
		my @overallprob;
		foreach my $class (@$classifications) {
			$overallprob[$$class[0]] = $messages[$$class[0]] / $total;
		}
		# get words
		if ( defined $limit ) {
			if ( $limit =~ /^\d+$/ ) {
				$st = $self->{'dbh'}->prepare ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated LIMIT '.$limit );
			} else {
				return undef;
			}
		} else {
			$st = $self->{'dbh'}->prepare ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated' );
		}
		$st->execute ();
		my $words = $st->fetchall_arrayref ();
		# process each word
		$self->{'dbh'}->begin_work ();	# start transaction to avoid slow synchronous writes
		foreach my $word (@$words) {
			# word frequency
			$st = $self->{'dbh'}->prepare ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
			my $count = 1;
			$st->bind_param ( $count++, $$word[0] );
			foreach my $class (@$classifications) { $st->bind_param ( $count++, $$class[0] ); }
			$st->execute ();
			my $results = $st->fetchall_hashref ( 'Class' );
			my %wordfrequency;
			$total = 0;
			foreach my $class (@$classifications) {
				if ( defined $$results{$$class[0]}{'Frequency'} ) {
					$wordfrequency{$$class[0]} = $$results{$$class[0]}->{'Frequency'} / $messages[$$class[0]];
					$total += $$results{$$class[0]}->{'Frequency'};
				} else {
					# no occurences of this word
					$wordfrequency{$$class[0]} = 0;
				}
			}
			my $divisor = 0;
			my @topline;
			foreach my $class (@$classifications) {
				$topline[$$class[0]] = $wordfrequency{$$class[0]};
				if ( ! $self->{'unbiased'} ) { $topline[$$class[0]] *= $overallprob[$$class[0]]; }
				$divisor += $topline[$$class[0]];
			}
			if ( $divisor > 0 ) {
				my $maxquality = 0;
				foreach my $class (@$classifications) {
					my $probability = $topline[$$class[0]] / $divisor;
					# correct for few occurances
					$probability = $self->{'s'} * $overallprob[$$class[0]] + $total * $probability;
					$probability /= $self->{'s'} + $total;
					# account for word quality
					my $quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
					if ( $quality > $maxquality ) { $maxquality = $quality; }
				}
				$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierWords SET Quality = :quality, LastUpdated = :time WHERE Word = :word' );
				$st->execute ( $maxquality, time(), $$word[0] );
			} else {
				print STDERR "WARNING - ".__FILE__." - no Frequency data for word \"$word\"\n";
				$st = $self->{'dbh'}->prepare ( 'UPDATE ClassifierWords SET LastUpdated = :time WHERE Word = :word' );
				$st->execute ( time(), $$word[0] );
			}
		}
		$self->{'dbh'}->commit();	# finish transaction to avoid slow synchronous writes
	}





1;
