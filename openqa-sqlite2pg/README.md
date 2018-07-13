## How to migrate an openqa instance from sqlite to postgres

Currently [openQA](http://open.qa) supports only postgresql as its database backend, but originally sqlite was also supported. This means there are probably openQA instances in the wild requiring migration to postgresql.

The official documentation of openQA provides a [small guide](http://open.qa/docs/#db-migration) on how to migrate from sqlite to postgresql, however this is very basic and does not provide a step-by-step procedure if one requires to perform a full migration of all data stored in sqlite to postgresql; the documented procedure includes only migration of API keys, job groups and templates.

However, it is indeed possible to migrate all the data in the sqlite database file to the postgresql database as shown in this document.

### Disclaimer

The procedure described in this document was tested with openQA version 4.6.1531161673. Newer versions could feature different (more/fewer) columns in some of the tables, so it is recommended to verify the structure of the tables both on the original sqlite and on the postgresql databases before importing the data by any automated tool, including the [script](sqlite2pg.sh) in this directory.

### Preparation

#### Dump sqlite data

Create a text file with a dump of all the data stored in the sqlite file by executing the following command as the openQA administrator:

```
sqlite3 ./db/db.sqlite .dump > /var/tmp/oqa.dump
```

In this case `./db/db.sqlite` points to the location of the sqlite file. Check `/etc/openqa/database.ini` for the proper location of your sqlite file. The content of the file should be something like this:

```
[test]
dsn = dbi:SQLite:dbname=:memory:
on_connect_call = use_foreign_keys
on_connect_do = PRAGMA synchronous = OFF
sqlite_unicode = 1

[production]
dsn = dbi:SQLite:dbname=/var/lib/openqa/db/db.sqlite
on_connect_call = use_foreign_keys
on_connect_do = PRAGMA synchronous = OFF
sqlite_unicode = 1
```

In the example above, the sqlite .db file is located in `/var/lib/openqa/db/db.sqlite`.

The file `/var/tmp/oqa.dump` is the generated dump file, and it will be used on the import steps below. It contains SQL statements.

#### Stop openQA services

Stop all openQA services that depend on the database, for example with these commands:

```
systemctl stop openqa-worker@\*
systemctl stop openqa-scheduler
systemctl stop openqa-websockets
systemctl stop openqa-webui
systemctl stop openqa-gru
```

#### postgres

Install and configure postgres according to [these specifications](http://open.qa/docs/#setup-postgresql).

#### Restart openqa: Initial posgresql setup

Once the configuration of openQA in `/etc/openqa/database.ini` is configured with postgresql as its backend, and postgresql has been started, restart the openqa services:

```
systemctl start openqa-worker@\*
systemctl start openqa-scheduler
systemctl start openqa-websockets
systemctl start openqa-webui
systemctl start openqa-gru
```

At this time you should be able to connect to the web UI of the openQA instance, but it should show no job results, job groups, templates, etc. It has basically an empty openqa database schema in postgresql.

### Data Import

#### Identify insert sentences and tables

Starting from the dump file (Ex: `/var/lib/oqa.dump`), most INSERT statements need to be imported to the postgresql database. Extract them to another file by running:

```
grep INSERT oqa.dump | egrep -v 'dbix_class_deploymenthandler_versions|users_temp_alter' > all-import-inserts
```

This creates the text file `all-import-inserts` which contains all the INSERT statements that need to be executed in postgresql, however some of these sentences require some syntax adjustments before attempting to run them on postgresql. The mismatch are basically of two kinds:

* sqlite has booleans as 0/1 integer values, so those need to be replace with TRUE and FALSE as needed.
* Some tables in postgresql has different number of columns than in sqlite.

Additionally, the order of the INSERT sentences is very important, as some foreign key relationships prevent the insertions of new rows in tables (for example, any table that has references to jobs, such as job_modules, will require the referenced job row to be already in the jobs table)

Next step is to split the `all-import-inserts` file into several files, one for each table, so as to more easily process the order of the insertions, and the syntax corrections on the SQL sentences. The following command does the split per tables:

```
awk '{print $3}' < all-import-inserts | uniq | while read i; do grep $i all-import-inserts > all-import-inserts.$(echo $i|sed 's/\"//g'); done
```

This is not the most efficient way as we are running a grep on the file for each table, in essence reading the `all-import-inserts` file as many times as there are tables defined in the database, plus one to get the initial list of tables. A more efficient way would be to process the file in a proper scripting language (perl or python, for example).

After splitting the file, check that the content of the original file is fully present and not duplicated in the new files.

One way to do this is to count the lines on both sets of files and see if the numbers match:

```
wc -l all-import-inserts
wc -l all-import-inserts.*
```

Another, more proper way is to compare the contents of the files:

```
sort all-import-inserts > check1
cat all-import-inserts.* | sort > check2
diff check1 check2
rm check1 check2
```

#### Import sqlite data to postgresql

With all the insert sentences divided in several files per table, all that is needed now is to identify which tables have changed between sqlite and postgresql and run the insert sentences, and to run the inserts in the proper order. In most cases, all that is needed is this:

```
for file in all-import-inserts.*; do
cat $file | while read i; do psql -U postgres -d openqa -c "$i"; done
done
```

Exceptions being:

* *users* table:

```
egrep -v 'noemail@open.qa|admin@example.com' all-import-inserts.users | sed -r 's/VALUES\(([0-9]+)/VALUES\(\1+1/' | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.users >> seqs
rm all-import-inserts.users
```

* *assets* table:

The *assets* table has some extra columns, so that needs to be taken into account:

```
sed 's/NULL,NULL/NULL,NULL,NULL,FALSE/' all-import-inserts.assets | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.assets >> seqs
rm all-import-inserts.assets
```

* *jobs* table:

The *jobs* table needs to be processed after the *workers* table. Also, the *jobs* table has a boolean value represented in sqlite as 0 or 1, that needs to be rewritten as TRUE or FALSE for postgresql:

```
cat all-import-inserts.workers | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.workers >> seqs
rm all-import-inserts.workers

tac all-import-inserts.jobs | sed -r -e 's/.+\(//' -e 's/\);//' -e "s/',1,'/',TRUE,'/" -e "s/',0,'/',FALSE,'/" | awk -F, '{print $1FS$2FS$3FS$4FS$5FS$6FS"NULL"FS$8FS$9FS$10FS$11FS$12FS$13FS$14FS$15FS$16FS$17FS$18FS$19FS$20FS$21FS$24FS$25FS$26FS$27FS$22FS$23}' | while read i; do psql -U postgres -d openqa -c "INSERT INTO \"jobs\" VALUES($i)"; done
```

To check wether all the content of the file has been succesfully inserted into the table, you can use the following commands:

```
wc -l all-import-inserts.jobs
psql -U postgres -d openqa -c 'select count(*) from jobs'
```

After that, you can remove all-import-inserts.jobs. Remember to save the last line into the file `seqs` to process the sequences later.

* *job_groups* table:

```
awk -F, 'BEGIN {OFS=","} ; ($12 == "1") { $12="TRUE" }; ($12 == "0") { $12="FALSE"}; ($5="NULL,"$5) {print $0}' all-import-inserts.job_groups | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.job_groups >> seqs
rm all-import-inserts.job_groups
```

* *job_module_needles* table:

This table does not exist anymore, so this file can be safely removed.

```
rm all-import-inserts.job_module_needles
```

* *needles* table:

The *needles* table has several new columns, as well as a column dropped since the move from sqlite to postgresql, so it needs further processing like this:

```
sed -r -e 's/.+\(//' -e 's/\);//' all-import-inserts.needles | awk -F, 'BEGIN {OFS=","} ($7 == "1") { $7="TRUE" }; ($7 == "0") { $7="FALSE" }; { $6="NULL,"$6 }; ($4="NULL") {print $0",NULL,current_date,current_date"}' | while read i; do psql -U postgres -d openqa -c "INSERT INTO \"needles\" VALUES($i)"; done
tail -1 all-import-inserts.needles >> seqs
rm all-import-inserts.needles
```

* *screenshots* table:

The inserts for the *screenshots* table need to be processed before those from the *screenshot_links* table:

```
cat all-import-inserts.screenshots | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.screenshots >> seqs
rm all-import-inserts.screenshots
cat all-import-inserts.screenshot_links | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 all-import-inserts.screenshot_links >> seqs
rm all-import-inserts.screenshot_links
```

* *api_keys* table:

The key `1234567890ABCDEF` should not be imported to the new database, so skip that one with this command:

```
grep -v 1234567890ABCDEF all-import-insers.api_keys | while read s; do psql -U postgres -d openqa -c "$s"; done
tail -1 all-import-insers.api_keys >> seqs
rm all-import-insers.api_keys

```

With all exceptions processed, the rest of the tables can be processed with:

```
for file in all-import-inserts.*; do
cat $file | while read i; do psql -U postgres -d openqa -c "$i"; done
tail -1 $file >> seqs
done
rm all-import-inserts.*
```

#### Update values of sequences

Finally, the `last_value` of the defined sequences needs to be updated to a number that is superior to the last id recorded in the tables.

For this we will use the `seqs` file created before:

```
sed -r -e 's/INSERT INTO \"([^\"]+)\" VALUES\(([0-9]+).+/alter sequence \1_id_seq restart with \2/' seqs | awk '($NF++) {print $0";"}' | while read i; do psql -U postgres -d openqa -c "$i"; done
rm seqs
```

The following commands are helpful when dealing with postgresql sequences:

* Get the current last value of a sequence:

```
select last_value from jobs_id_seq;
```

* Update the last value of a sequence:

```
alter sequence jobs_id_seq restart with 364;
```

* List all sequences:

```
select relname from pg_class where relkind = 'S';
```

### Restart

To complete the procedure, restart openqa.
