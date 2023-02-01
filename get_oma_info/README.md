## get_oma_info

This perl script is intended to be used with [OpenMG/ATRAC3](https://en.wikipedia.org/wiki/OpenMG) formatted files,
to extract from them information regarding the track title, album, artist and other relevant information which
may be stored in the file.

OpenMG/ATRAC3 files from old Sony digital music content devices, are digitally protected with the
[DRM](https://en.wikipedia.org/wiki/Digital_rights_management) features of OpenMG and can only be played in
authorized devices (up to 3, but in some markets only 1) linked to the Sony account of the user. Sadly, this means
that while it is possible to retrieve the files from old devices into a new system, playback of the media is not
possible unless the files were previously imported into the old authorized device and exported from there as a
[WAV file](https://en.wikipedia.org/wiki/WAV) by using a valid
[SonicStage](https://en.wikipedia.org/wiki/SonicStage) product from Sony running in the old authorized device.

However, even though the DRM protection prevents the playback or conversion of the file, details about the track
are stored in the clear in the files, so this information can be retrieved. The idea behind this script is to extract
these details and print them to the standard output, to discover which tracks correspond to each file.

## Usage

### Synopsis

    get_oma_info [OPTIONS]

    Extract track information from OpenMG/ATRAC files and print it to stdout.

### Options

* `--file FILENAME`: Extract information from the given filename and print it to stdout.
* `--dir DIRECTORY`: Search files with .OMA or .OMG extensions in the supplied directory and extract
the information from them to print. In case both `--file` and `--dir` are supplied, `--file` will take precedence.
* `--csv`: If supplied, output will be printed in a comma separated values format for easier processing.

### Examples

To print the command line help do either:

```
./get_oma_info
```

Or

```
./get_oma_info --help
```

To get information from a specific file:

```
./get_oma_info --file 10000003.OMA 
$VAR1 = {
          'orig_file' => '10000003.OMA',
          'genre' => 'Alternative',
          'album' => 'Dosage',
          'artist' => 'Collective Soul',
          'title' => 'Tremble for My Beloved'
        };
```

To print the output as a CSV:

```
./get_oma_info --file 10000003.OMA --csv
Title,Artist,Album,Genre,Original File
Tremble for My Beloved,Collective Soul,Dosage,Alternative,10000003.OMA
```

Of course, you can redirect stdout to a file to save the CSV:

```
# ./get_oma_info --file 10000003.OMA --csv > tracks.csv
# ls tracks.csv
tracks.csv
```

To get the information from all OpenMG files in a directory:

```
./get_oma_info --dir /path/to/my/directory
```

Or save it as a CSV:

```
./get_oma_info --dir /path/to/my/directory --csv > tracks.csv

## Related Links

More information is available at:

* https://ubuntuforums.org/archive/index.php/t-1271969.html
* https://forums.sonyinsider.com/topic/30682-decryption-of-atrac3plus-oma-files-by-ffmpeg/
* https://forum.dbpoweramp.com/showthread.php?7532-Sony-OMA-OMG-File-Conversion-Some-actual-facts

