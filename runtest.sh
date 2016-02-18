#!/bin/sh

runtest() {	# arg: test script
	# generate test database
	echo "Build database"
	sqlite3 _test_${1}.sqlite3 <classifier_sqlite3.sql
	# ingest text
	echo Teach 1
	./$1 _test_${1}.sqlite3 teach 1 <<TEXT1
Lorem ipsum dolor sit amet, consectetur adipiscing elit. Nam vestibulum ipsum feugiat orci convallis mollis. Ut finibus ligula vel elit pulvinar, quis pellentesque eros suscipit. Praesent at rutrum ligula. Duis varius erat nec felis tempus, vel ultrices elit ultricies. In rutrum, velit ut congue aliquam, enim neque suscipit augue, quis interdum dui felis vel mauris. Curabitur at bibendum diam. Nullam egestas augue id fermentum gravida.
stopwordstart and meanwhile stopwordsend
TEXT1
	echo Teach 2
	./$1 _test_${1}.sqlite3 teach 2 <<TEXT2
Curabitur ac metus diam. Maecenas laoreet massa et sodales rhoncus. Proin cursus sed sem at volutpat. Suspendisse id sapien augue. Pellentesque habitant morbi tristique senectus et netus et malesuada fames ac turpis egestas. Donec condimentum nisi vitae iaculis tincidunt. Vivamus nec tellus vel dolor dignissim pretium at non purus. Donec quis neque velit. Vivamus arcu nibh, aliquet sed lorem vitae, tincidunt varius dolor. Nullam commodo mauris dapibus velit gravida, et placerat diam congue. Nam at fermentum urna. Suspendisse sollicitudin erat non sapien ornare scelerisque. Maecenas sit amet imperdiet turpis. Integer euismod dolor at ipsum viverra ultricies. Aenean purus eros, finibus consequat quam at, suscipit posuere mauris.
stopwordstart and meanwhile stopwordsend
TEXT2
	echo Teach 3
	./$1 _test_${1}.sqlite3 teach 1 <<TEXT3
Quisque eget molestie urna, eu molestie lorem. Integer dapibus, metus ac imperdiet mattis, orci arcu imperdiet mi, vitae dapibus massa ante at eros. Sed gravida lacinia ornare. Proin nec scelerisque arcu. Ut pretium lacus nec euismod tristique. Nulla et est porta, ornare lorem ac, molestie tellus. Aliquam malesuada egestas enim id efficitur. Sed ultrices, est eu semper eleifend, nisl diam convallis lacus, sit amet dictum felis arcu ornare arcu. Morbi sed blandit nibh. Cras quis diam condimentum, tincidunt metus sit amet, mattis leo. Ut sollicitudin sodales tincidunt. Fusce ac enim quis nisi aliquam ornare. Vivamus egestas eros vel laoreet gravida. Curabitur dictum est urna, nec dictum ante faucibus vel. Etiam ultricies, libero eget mollis pellentesque, elit magna pharetra mauris, eget placerat metus ex convallis mauris. Aenean eget pretium elit.
stopwordstart and meanwhile stopwordsend
TEXT3
	./$1 _test_${1}.sqlite3 teach 2 <<TEXT4
Proin ipsum ipsum, malesuada nec dui id, gravida sollicitudin turpis. Donec scelerisque blandit lectus, a finibus felis. Fusce quis sollicitudin ligula. Vestibulum tincidunt, velit nec porttitor lobortis, ipsum risus tincidunt dolor, ut pretium odio nulla sit amet purus. Nulla dignissim a ex at ultricies. Vestibulum ex orci, egestas vitae facilisis et, mollis ornare enim. In non massa sit amet leo sollicitudin cursus accumsan eu elit. Donec ultrices erat vitae quam consequat venenatis.
stopwordstart and meanwhile stopwordsend
TEXT4
	echo Classify 5
	./$1 _test_${1}.sqlite3 classify 1 2 <<TEXT5
Aliquam bibendum purus in eleifend iaculis. Vestibulum sodales vestibulum orci nec sodales. Curabitur a sapien ac nulla hendrerit pellentesque. Integer ipsum lectus, accumsan nec urna tincidunt, ornare pretium mauris. Praesent at imperdiet dolor. Nulla dictum condimentum dui, at hendrerit magna congue luctus. Proin semper lacinia ante eget volutpat. Integer id sem non nunc eleifend fermentum. Cras cursus eros non odio venenatis dignissim.
stopwordstart and meanwhile stopwordsend
TEXT5
	echo Classify 6
	./$1 _test_${1}.sqlite3 classify 1 2 <<TEXT6
Etiam egestas aliquet lacus eu dignissim. Mauris magna purus, consequat non dictum vel, scelerisque id velit. Donec consectetur neque odio, ut vulputate odio ullamcorper sed. Morbi sodales sagittis lectus vel tristique. Nullam id arcu nisi. Nunc suscipit felis id sem pellentesque, et gravida neque eleifend. Vestibulum ante ipsum primis in faucibus orci luctus et ultrices posuere cubilia Curae; Fusce porta, diam at vestibulum rutrum, libero quam elementum sapien, iaculis commodo enim sapien in lectus. Quisque eget turpis maximus, commodo ex ullamcorper, tincidunt risus. Aenean vehicula ipsum nisl, ut mattis sem finibus eu. Proin faucibus tincidunt mi eget imperdiet. Phasellus vel sagittis magna, eu dapibus quam. Sed sit amet odio imperdiet, sodales diam in, dignissim ligula. Nullam tempus varius massa non mollis.
stopwordstart and meanwhile stopwordsend
TEXT6
	echo Classify 7
	./$1 _test_${1}.sqlite3 classify 1 2 <<TEXT7
Mauris congue leo risus, quis maximus ex pellentesque et. Donec eget nunc et eros facilisis scelerisque. Pellentesque bibendum accumsan nisl, a ornare eros semper at. Aliquam scelerisque felis sit amet volutpat vestibulum. Morbi arcu mauris, imperdiet id porttitor eget, interdum ut ex. Nam lobortis magna at finibus aliquet. Phasellus ornare suscipit malesuada.
stopwordstart and meanwhile stopwordsend
TEXT7
	echo Data 1 ClassifierWords
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierWords' | sed 's/|[0-9]\+$/|_timeremoved_/' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierWords' | sed 's/|[0-9]\+$/|_timeremoved_/' | md5sum
	echo Data 2 ClassifierClassSamples
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierClassSamples' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierClassSamples' | md5sum
	echo Data 3 ClassifierFrequency
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierFrequency' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierFrequency' | md5sum
	echo Data 4 ClassifierOrderFrequency
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierOrderFrequency' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierOrderFrequency' | md5sum
	echo Updatequality
	./$1 _test_${1}.sqlite3 updatequality
	echo Degrade
	./$1 _test_${1}.sqlite3 degrade 0.8
	echo Cleanfrequency
	./$1 _test_${1}.sqlite3 cleanfrequency 0.85
	echo Data 1 ClassifierWords
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierWords' | wc -l
	# remove quality update time, truncate quality decimal places
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierWords' | sed 's/|\([0-9]\+\(\.[0-9]\{0,6\}\)\?\)[0-9]*|[0-9]\+$/|\1|_timeremoved_/' | md5sum
	echo Data 2 ClassifierClassSamples
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierClassSamples' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierClassSamples' | md5sum
	echo Data 3 ClassifierFrequency
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierFrequency' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierFrequency' | md5sum
	echo Data 4 ClassifierOrderFrequency
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierOrderFrequency' | wc -l
	sqlite3 _test_${1}.sqlite3 'SELECT * FROM ClassifierOrderFrequency' | md5sum
	# cleanup
	echo Cleanup
	rm _test_${1}.sqlite3
}

if [ $# -ne 1 -o ! -f "$1" ]; then
	echo "Usage: $0 <classifier cli prog to use>" >&2
	exit 1
fi
runtest $1


