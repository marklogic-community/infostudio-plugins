collector-csv.xqy
===============================================

This collector uses infodev:filesystem-walk to process all the files in a directory.
In the callback function, the files are treated as csv, so its assumed that all files being processed are csv files.

You have the option of selecting ',' or '|' as your delimiter.  Feel free to add others as you see fit.

Also, if you choose to have the first row be used as element values, any whitespace in the value will be replaced with underscore ('_') and validation is performed to insure the element names are valid.  



collector-zip.xqy
===============================================
This collector uses infodev:filesystem-walk to process all the files in a directory.
In the callback function, the files are treated as zip, so its assumed that all files being processed are zip files.

As the files are unzipped, the number of files processed and loaded is updated accordingly.




collector-feed.xqy
===============================================
This collector will collect entries from an atom feed.  It is also an example of how to use infodev:transaction, to split loading of documents into multiple transactions.

Provide the URI for the atom feed, and optionally a 'since' date, to load entries since that date.



collector-twitter.xqy
===============================================
This collector makes 20 requests to the twitter public timeline and loads the collected tweets into the specified database.  Here is also another example of using infodev:transaction().

Up to 150 requests an hour can be made to the public timeline.  Also, you may want to update for search on specific topics.  For more information on the twitter APIs, please see twitter.com
