<?php
/*
  Copyright (C) 2011  Glen Pitt-Pladdy

  This library is free software; you can redistribute it and/or
  modify it under the terms of the GNU Lesser General Public
  License as published by the Free Software Foundation; either
  version 2.1 of the License, or (at your option) any later version.

  This library is distributed in the hope that it will be useful,
  but WITHOUT ANY WARRANTY; without even the implied warranty of
  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
  Lesser General Public License for more details.

  You should have received a copy of the GNU Lesser General Public
  License along with this library; if not, write to the Free Software
  Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301  USA


  See: http://www.pitt-pladdy.com/blog/_20111229-214727_0000_Bayesian_Classifier_Classes_for_Perl_and_PHP/
*/

// based on: http://en.wikipedia.org/wiki/Bayesian_spam_filtering#Computing_the_probability_that_a_message_containing_a_given_word_is_spam

class classifier {
	private $dbh;
	private $words;
	private $driverclass;
	public $s = 3;
	public $unbiased = false;	// give even odds for all classes
	function classifier ( $dbh, $text ) {
		$this->dbh = $dbh;
		if ( strstr ( $dbh->getAttribute ( PDO::ATTR_DRIVER_NAME ), 'sqlite' ) === 0 ) {
			$this->driverclass = 'sqlite';
		} else {
			$this->driverclass = $dbh->getAttribute ( PDO::ATTR_DRIVER_NAME );
		}
		$this->words = preg_split ( '/\W+/', strtolower ( $text ) );
	}
	function teach ( $classification, $strength=1, $ordered=true ) {	// eg. 1=>HAM 2=>SPAM
		$prevwordid = NULL;
		$this->dbh->beginTransaction ();	// start transaction to avoid slow synchronous writes
		foreach ( $this->words as $word ) {
			if ( $word == '' ) { continue; }
			// put the word in the classification as needed
			// never delete words so this should be race safe
			$st = $this->dbh->prepare ( 'SELECT id FROM ClassifierWords WHERE Word = :word' );
			$st->execute ( array ( ':word'=>$word ) );
			$result = $st->fetch ();
			if ( isset ( $result['id'] ) ) {
				// got it
				$wordid = $result['id'];
			} else {
				// oops - missing word - add it
				$st = $this->dbh->prepare ( 'INSERT INTO ClassifierWords (Word) VALUES (:word)' );
				$st->execute ( array ( ':word'=>$word ) );
				$wordid = $this->dbh->lastInsertId ();
			}
			// SQLite has some limitations - work round them
			if ( $this->driverclass != 'sqlite' ) {
				// insert or update this word frequency
				$st = $this->dbh->prepare ( 'INSERT INTO ClassifierFrequency (Word,Class,Frequency) Values (:wordid,:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
				$st->execute ( array ( ':wordid'=>$wordid, ':class'=>$classification, ':strength'=>$strength ) );
				// insert or update this word order frequency
				if ( $ordered ) {
					$st = $this->dbh->prepare ( 'INSERT INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (:wordid,:prevwordid,:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
					$st->execute ( array ( ':wordid'=>$wordid, ':prevwordid'=>$prevwordid, ':class'=>$classification, ':strength'=>$strength ) );
				}
			} else {
				// long way rount for SQLite
				// insert or update this word frequency
				$st = $this->dbh->prepare ( 'INSERT OR IGNORE INTO ClassifierFrequency (Word,Class,Frequency) Values (:wordid,:class,0)' );
				$st->execute ( array ( ':wordid'=>$wordid, ':class'=>$classification ) );
				$st = $this->dbh->prepare ( 'UPDATE ClassifierFrequency SET Frequency = Frequency + :strength WHERE Word = :wordid AND Class = :class' );
				$st->execute ( array ( ':strength'=>$strength, ':wordid'=>$wordid, ':class'=>$classification ) );
				// insert or update this word order frequency
				if ( $ordered ) {
					$st = $this->dbh->prepare ( 'INSERT OR IGNORE INTO ClassifierOrderFrequency (Word,PrevWord,Class,Frequency) VALUES (:wordid,:prevwordid,:class,0)' );
					$st->execute ( array ( ':wordid'=>$wordid, ':prevwordid'=>$prevwordid, ':class'=>$classification ) );
					$st = $this->dbh->prepare ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency + :strength WHERE Word = :wordid AND PrevWord = :prevwordid AND Class = :class' );
					$st->execute ( array ( ':strength'=>$strength, ':wordid'=>$wordid, ':prevwordid'=>$prevwordid, ':class'=>$classification ) );
				}
			}
			// set for next word
			$prevwordid = $wordid;
		}
		// count classes
		if ( $this->driverclass != 'sqlite' ) {
			$st = $this->dbh->prepare ( 'INSERT INTO ClassifierClassSamples (Class,Frequency) VALUES (:class,:strength) ON DUPLICATE KEY UPDATE Frequency = Frequency + :strength' );
			$st->execute ( array ( ':class'=>$classification, ':strength'=>$strength ) );
		} else {
			// long way rount for SQLite
			$st = $this->dbh->prepare ( 'INSERT OR IGNORE INTO ClassifierClassSamples (Class,Frequency) VALUES (:class,0)' );
			$st->execute ( array ( ':class'=>$classification ) );
			$st = $this->dbh->prepare ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency + :strength WHERE Class = :class' );
			$st->execute ( array ( ':strength'=>$strength, ':class'=>$classification ) );
		}
		$this->dbh->commit ();	// finish transaction to avoid slow synchronous writes
	}
	function classify ( $classifications, $useorder=0 ) {	// $useorder = 0-1 for the factor of order information
		$qualityfactor = count ( $classifications );
		// we need to know how many samples of each class to level the instances
		$messages = array ();
		$total = 0;
		$bindclassifications = implode ( ',', array_fill ( 0, count($classifications), '?' ) );
		foreach ( $classifications as $class ) {
			$st = $this->dbh->prepare ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = :class' );
			$st->execute ( array ( ':class'=>$class ) );
			$result = $st->fetch();
			if ( ! isset ( $result['Frequency'] ) ) {
				// never seen this class before - can't classify
				return false;
			}
			$messages[$class] = $result['Frequency'];
			$total += $result['Frequency'];
		}
		// work out overall probability of each class
		$overallprob = array ();
		foreach ( $classifications as $class ) {
			$overallprob[$class] = $messages[$class] / $total;
		}
		// on with classification
		$prevword = NULL;
		$prob = array ();
		$proborder = array ();
		foreach ( $classifications as $class ) {
			$prob[$class] = 1;
			$proborder[$class] = 1;
		}
		foreach ( $this->words as $word ) {
			if ( $word == '' ) { continue; }
			// word frequency
			$st = $this->dbh->prepare ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
			$count = 1;
			$st->bindValue ( $count++, $word );
			foreach ( $classifications as $class ) { $st->bindValue ( $count++, $class ); }
			$st->execute ();
			$results = $st->fetchAll ( PDO::FETCH_GROUP );
			$wordfrequency = array ();
			$total = 0;
			foreach ( $classifications as $class ) {
				if ( isset ( $results[$class][0]['Frequency'] ) ) {
					$wordfrequency[$class] = $results[$class][0]['Frequency'] / $messages[$class];
					$total += $results[$class][0]['Frequency'];
				} else {
					// no occurences of this word
					$wordfrequency[$class] = 0;
				}
			}
			if ( $total > 0 ) {	// no point otherwise
				$divisor = 0;
				$topline = array();
				foreach ( $classifications as $class ) {
						// could divide this by $total to give the prob per class, but it cancels anyway
						$topline[$class] = $wordfrequency[$class];
						if ( ! $this->unbiased ) { $topline[$class] *= $overallprob[$class]; }
						$divisor += $topline[$class];
				}
				foreach ( $classifications as $class ) {
					$probability = $topline[$class] / $divisor;
					// correct for few occurances
					$probability = $this->s * $overallprob[$class] + $total * $probability;
					$probability /= $this->s + $total;
					// account for word quality
					$quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
					if ( $quality < 0.3 ) { continue; }
					// combine
					$prob[$class] *= $probability;
				}
				// word order frequency
				$count = 1;
				if ( $prevword === NULL ) {
					$st = $this->dbh->prepare ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord IS NULL AND Class IN ('.$bindclassifications.')' );
					$st->bindValue ( $count++, $word );
				} else {
					$st = $this->dbh->prepare ( 'SELECT Class,Frequency FROM ClassifierOrderFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND PrevWord = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
					$st->bindValue ( $count++, $word );
					$st->bindValue ( $count++, $prevword );
				}
				foreach ( $classifications as $class ) { $st->bindValue ( $count++, $class ); }
				$st->execute ();
				$results = $st->fetchAll ( PDO::FETCH_GROUP );
				$total = 0;
				foreach ( $classifications as $class ) {
					if ( isset ( $results[$class][0]['Frequency'] ) ) {
						$wordfrequency[$class] = $results[$class][0]['Frequency'] / $messages[$class];
						$total += $results[$class][0]['Frequency'];
					} else {
						// no occurences of this word
						$wordfrequency[$class] = 0;
					}
				}
				if ( $total > 0 ) {	// no point otherwise
					$divisor = 0;
					foreach ( $classifications as $class ) {
							$topline[$class] = $wordfrequency[$class];
							if ( ! $this->unbiased ) { $topline[$class] *= $overallprob[$class]; }
							$divisor += $topline[$class];
					}
					foreach ( $classifications as $class ) {
						$probability = $topline[$class] / $divisor;
						// correct for few occurances
						$probability = $this->s * $overallprob[$class] + $total * $probability;
						$probability /= $this->s + $total;
						// account for word quality
						$quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
						if ( $quality < 0.3 ) { continue; }
						// combine
						$proborder[$class] *= $probability;
					}
				}
			}
			// set for next word
			$prevword = $word;
		}
		// finish up
		$total = 0;
		$totalorder = 0;
		foreach ( $classifications as $class ) {
			$total += $prob[$class];
			$totalorder += $proborder[$class];
		}
		foreach ( $classifications as $class ) {
			$prob[$class] /= $total;
			$proborder[$class] /= $totalorder;
		}
#error_log ( "scores:".var_export( $prob, true ) );
#error_log ( "scoresorder:".var_export( $proborder, true ) );
		// combine
		if ( $useorder > 0 ) {
			$usefreq = 1 - $useorder;
			foreach ( $classifications as $class ) {
				$probfreqweighted = pow ( $prob[$class], $usefreq );
				$proborderweighted = pow ( $proborder[$class], $useorder );
				$probcombined = $probfreqweighted * $proborderweighted;
				$prob[$class] = $probcombined / ( $probcombined + pow ( 1 - $prob[$class], $usefreq ) * pow ( 1 - $proborder[$class], $useorder ) );
			}
		}
#error_log ( "scoresfinal:".var_export( $prob, true ) );
		return $prob;
	}
	// do degrading of existing data so that fresh data takes prescedence
	function degrade ( $factor ) {	// 0.9 would multiply everything by that
		$this->dbh->beginTransaction ();	// start transaction to avoid slow synchronous writes
		$st = $this->dbh->prepare ( 'UPDATE ClassifierFrequency SET Frequency = Frequency * :factor' );
		$st->execute ( array ( ':factor'=>$factor ) );
		$st = $this->dbh->prepare ( 'UPDATE ClassifierOrderFrequency SET Frequency = Frequency * :factor' );
		$st->execute ( array ( ':factor'=>$factor ) );
		$st = $this->dbh->prepare ( 'UPDATE ClassifierClassSamples SET Frequency = Frequency * :factor' );
		$st->execute ( array ( ':factor'=>$factor ) );
		$this->dbh->commit ();	// finish transaction to avoid slow synchronous writes
	}
	// calculate quality factor for words
	function updatequality ( $limit=NULL ) {
		// get classes
		$st = $this->dbh->prepare ( 'SELECT DISTINCT Class FROM ClassifierFrequency' );
		$st->execute ();
		$classifications = $st->fetchAll ( PDO::FETCH_COLUMN );
		$qualityfactor = count ( $classifications );
		// we need to know how many samples of each class to level the instances
		$messages = array ();
		$total = 0;
		$bindclassifications = implode ( ',', array_fill ( 0, count($classifications), '?' ) );
		foreach ( $classifications as $class ) {
			$st = $this->dbh->prepare ( 'SELECT Frequency FROM ClassifierClassSamples WHERE Class = :class' );
			$st->execute ( array ( ':class'=>$class ) );
			$result = $st->fetch();
			if ( ! isset ( $result['Frequency'] ) ) {
				// never seen this class before - can't classify
				return false;
			}
			$messages[$class] = $result['Frequency'];
			$total += $result['Frequency'];
		}
		// work out overall probability of each class
		$overallprob = array ();
		foreach ( $classifications as $class ) {
			$overallprob[$class] = $messages[$class] / $total;
		}
		// get words
		if ( $limit !== NULL ) {
			if ( is_integer ( $limit ) ) {
				$st = $this->dbh->prepare ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated LIMIT '.$limit );
			} else {
				return false;
			}
		} else {
			$st = $this->dbh->prepare ( 'SELECT Word FROM ClassifierWords ORDER BY LastUpdated' );
		}
		$st->execute ();
		$words = $st->fetchAll ( PDO::FETCH_COLUMN );
		// process each word
		$this->dbh->beginTransaction ();	// start transaction to avoid slow synchronous writes
		foreach ( $words as $word ) {
			// word frequency
			$st = $this->dbh->prepare ( 'SELECT Class,Frequency FROM ClassifierFrequency WHERE Word = (SELECT id FROM ClassifierWords WHERE Word = ?) AND Class IN ('.$bindclassifications.')' );
			$count = 1;
			$st->bindValue ( $count++, $word );
			foreach ( $classifications as $class ) { $st->bindValue ( $count++, $class ); }
			$st->execute ();
			$results = $st->fetchAll ( PDO::FETCH_GROUP );
			$wordfrequency = array ();
			$total = 0;
			foreach ( $classifications as $class ) {
				if ( isset ( $results[$class][0]['Frequency'] ) ) {
					$wordfrequency[$class] = $results[$class][0]['Frequency'] / $messages[$class];
					$total += $results[$class][0]['Frequency'];
				} else {
					// no occurences of this word
					$wordfrequency[$class] = 0;
				}
			}
			$divisor = 0;
			$topline = array();
			foreach ( $classifications as $class ) {
				$topline[$class] = $wordfrequency[$class];
				if ( ! $this->unbiased ) { $topline[$class] *= $overallprob[$class]; }
				$divisor += $topline[$class];
			}
			if ( $divisor > 0 ) {
				$maxquality = 0;
				foreach ( $classifications as $class ) {
					$probability = $topline[$class] / $divisor;
					// correct for few occurances
					$probability = $this->s * $overallprob[$class] + $total * $probability;
					$probability /= $this->s + $total;
					// account for word quality
					$quality = abs ( $probability - 1/$qualityfactor ) * $qualityfactor;
					if ( $quality > $maxquality ) { $maxquality = $quality; }
				}
				$st = $this->dbh->prepare ( 'UPDATE ClassifierWords SET Quality = :quality, LastUpdated = :time WHERE Word = :word' );
				$st->execute ( array ( ':quality'=>$maxquality, ':time'=>time(), ':word'=>$word ) );
			} else {
				error_log ( "WARNING - ".__FILE__." - no Frequency data for word \"$word\"" );
				$st = $this->dbh->prepare ( 'UPDATE ClassifierWords SET LastUpdated = :time WHERE Word = :word' );
				$st->execute ( array ( ':time'=>time(), ':word'=>$word ) );
			}
		}
		$this->dbh->commit ();	// finish transaction to avoid slow synchronous writes
	}
}





?>
