CREATE TABLE IF NOT EXISTS `ClassifierWords` (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	Word CHAR(40) NOT NULL UNIQUE,
	Quality FLOAT NOT NULL DEFAULT 1,
	LastUpdated INT UNSIGNED NOT NULL DEFAULT 0
);
CREATE INDEX ClassifierWords_Word ON ClassifierWords(Word);
CREATE INDEX ClassifierWords_LastUpdated ON ClassifierWords(LastUpdated);
CREATE TABLE IF NOT EXISTS `ClassifierClassSamples` (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	Class INT UNSIGNED NOT NULL UNIQUE,
	Frequency FLOAT NOT NULL
);
CREATE INDEX ClassifierClassSamples_Class ON ClassifierClassSamples(Class);
CREATE TABLE IF NOT EXISTS `ClassifierFrequency` (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	Word INT UNSIGNED NOT NULL REFERENCES ClassifierWords(id),
	Class INT UNSIGNED NOT NULL,
	Frequency FLOAT NOT NULL,
	UNIQUE (Word,Class)
);
CREATE INDEX ClassifierFrequency_Word ON ClassifierFrequency(Word);
CREATE INDEX ClassifierFrequency_Class ON ClassifierFrequency(Class);


CREATE TABLE IF NOT EXISTS `ClassifierOrderFrequency` (
	id INTEGER PRIMARY KEY AUTOINCREMENT,
	Word INT UNSIGNED NOT NULL REFERENCES ClassifierWords(id),
	PrevWord INT UNSIGNED REFERENCES ClassifierWords(id),
	Class INT UNSIGNED NOT NULL,
	Frequency FLOAT NOT NULL,
	UNIQUE (Word,PrevWord,Class)
);
CREATE INDEX ClassifierOrderFrequency_Word ON ClassifierOrderFrequency(Word);
CREATE INDEX ClassifierOrderFrequency_PrevWord ON ClassifierOrderFrequency(PrevWord);
CREATE INDEX ClassifierOrderFrequency_Class ON ClassifierOrderFrequency(Class);

