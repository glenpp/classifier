CREATE TABLE ClassifierWords (
	id INTEGER AUTOINCREMENT PRIMARY KEY,
	Word CHAR(40) NOT NULL UNIQUE,
	Quality FLOAT NOT NULL DEFAULT 1,
	LastUpdated INTEGER UNSIGNED NOT NULL DEFAULT 0
);
CREATE INDEX ClassifierWords_Word ON ClassifierWords(Word);
CREATE INDEX ClassifierWords_LastUpdated ON ClassifierWords(LastUpdated);
CREATE TABLE ClassifierClassSamples (
	id INTEGER AUTOINCREMENT PRIMARY KEY,
	Class INTEGER UNSIGNED NOT NULL UNIQUE,
	Frequency FLOAT NOT NULL
);
CREATE INDEX ClassifierClassSamples_Class ON ClassifierClassSamples(Class);
CREATE TABLE ClassifierFrequency (
	id INTEGER AUTOINCREMENT PRIMARY KEY,
	Word INTEGER UNSIGNED NOT NULL REFERENCES ClassifierWords(id),
	Class INTEGER UNSIGNED NOT NULL,
	Frequency FLOAT NOT NULL,
	UNIQUE (Word,Class)
);
CREATE INDEX ClassifierFrequency_Word ON ClassifierFrequency(Word);
CREATE INDEX ClassifierFrequency_Class ON ClassifierFrequency(Class);


CREATE TABLE ClassifierOrderFrequency (
	id INTEGER AUTOINCREMENT PRIMARY KEY,
	Word INTEGER UNSIGNED NOT NULL REFERENCES ClassifierWords(id),
	PrevWord INTEGER UNSIGNED REFERENCES ClassifierWords(id),
	Class INTEGER UNSIGNED NOT NULL,
	Frequency FLOAT NOT NULL,
	UNIQUE (Word,PrevWord,Class)
);
CREATE INDEX ClassifierOrderFrequency_Word ON ClassifierOrderFrequency(Word);
CREATE INDEX ClassifierOrderFrequency_PrevWord ON ClassifierOrderFrequency(PrevWord);
CREATE INDEX ClassifierOrderFrequency_Class ON ClassifierOrderFrequency(Class);

