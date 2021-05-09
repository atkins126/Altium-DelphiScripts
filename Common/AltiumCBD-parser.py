#! /usr/bin/env python3

# AltiumCBD-parser.py
# parse compound binary doc (OLE) PcbDoc PcbLib & SchDoc for ascii text in header & streams

# olefile can also be used as a script from the command-line to display the structure of an OLE file and its metadata, for example:
# pip3 install -U olefile
# olefile my_Doc  
# can use the option -c to check that all streams can be read fully, and -d to generate very verbose debugging information.
# add the option -l debug to display debugging messages (very verbose).

## load module from specific location 
# import importlib.machinery
# modulename = importlib.machinery.SourceFileLoader('modulename','/Path/To/module.py').load_module()

import olefile
import argparse
import sys
import binascii
import re

# olefile.enable_logging()

inputfile  = ''
outputfile = ''
searchstring = ''
outfile = False

board_section = 'Board6'
altium_hint   = 'ExtendedPrimitiveInformation'

# boilerplate to only parse cmd options for top level module.
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument('-i', '--ifile', required=True)
    parser.add_argument('-o', '--ofile')
    parser.add_argument('-s', '--sstring', required=True)
    parser.add_argument('-v', dest='verbose', action='store_true')
    args = parser.parse_args()

    print(args)

    if args.ifile == None:
        sys.exit()
    if args.sstring == None:
        sys.exit()
    if args.ofile != None:
        outfile = True

    inputfile    = args.ifile
    outputfile   = args.ofile
    searchstring = args.sstring
#    print('Search string is ', searchstring)
print(outfile)

if outfile:
    try:
        # open file stream  write byte mode
        file = open(outputfile, "wb")   
    except IOError:
        print('There was an error writing to output file ', outputfile)
        sys.exit()

assert olefile.isOleFile(inputfile)

ole = olefile.OleFileIO(inputfile, raise_defects=olefile.DEFECT_INCORRECT)
print('Non-fatal issues raised during parsing:')
if ole.parsing_issues:
    for exctype, msg in ole.parsing_issues:
        print('- %s: %s' % (exctype.__name__, msg))
        if args.outfile:
            file.write('- %s: %s' % (exctype.__name__, msg))
            file.write(b'\r\n')

else:
    print('None')

# perform all operations on the ole object
# syntax error !!                        vv
# with olefile.OleFileIO(myfile_doc) as ole

# check if standard property streams exist, parse all the properties they contain, and return an olefile.OleFileIO.OleMetadata object with the found properties as attributes (new in v0.24).
meta = ole.get_metadata()
if args.verbose:
    print('Author:', meta.author)
    print('Title:', meta.title)
    print('Creation date:', meta.create_time)
# print all metadata:
    meta.dump()

if ole.exists(['FileVersionInfo', 'Data']):
    s = ole.get_size(['FileVersionInfo','Data'])
    if args.verbose:
        print("Fileversion size ", s)

# checks if a given stream or storage exists in the OLE file (new in v0.16). The provided path is case-insensitive.
if ole.exists(altium_hint):
    if args.verbose:
        print("This is a Altium doc")

if ole.exists([board_section,'Data']):
    if args.verbose:
        print("This document seems to contain PcbDoc Board info")
    s = ole.get_size([board_section,'Data'])
    if args.verbose:
        print("Board data size ", s)

section = 'FileHeader'
if ole.exists(section):
    board = ole.openstream(section)
    data = board.read()
    s  = data.decode('ascii','replace')
    ss = s.split('|')
    for line in ss:
        if args.verbose:
            print(section)
            print(line.encode('ascii', 'ignore'))
        if line.find(searchstring) != -1:
            print(section)
            print(line.strip(" \\r"))
            if outfile:
                s = line.strip(" \\r").encode('ascii', 'replace')
                file.write(s)
                file.write(b'\r\n')


# Two different syntaxes are allowed for methods that need or return the path of streams and storages:
# slash_path = '/'.join(list_path)
# list_path  = slash_path.split('/')

# ole.listdir (streams=False, storages=True)

# returns a list of all the streams contained in the OLE file, including those stored in storages.
# Each stream is listed itself as a list, as described above.

slist = ole.listdir()
if args.verbose:
    print(slist)

for section in slist:
    goodsection = False

# return the creation and modification timestamps of a stream/storage, as a Python datetime object with UTC timezone.
# these timestamps are only present if the application that created the OLE file explicitly stored them, which is rarely the case.
# When not present, these methods return None (new in v0.26).
    c = ole.getctime(section[0])
    m = ole.getmtime(section[0])

    if len(section) == 1:
        goodsection = True
    elif section[1] == 'Data':
        goodsection = True

    if goodsection:
        if args.verbose:
            print(section)

        if ole.exists([section[0], 'Data']):
            board = ole.openstream([section[0], 'Data'])
            data = board.read()

# clever print displays ascii for bytes as possible.. 
#        print(data)   
            s = data.decode('ascii', 'replace')
#            ss = s.split('|')

# regular expression module re.split
            ss = re.split('[|`]',s)

#        s = list(data) 
#        print (binascii.hexlify(data))

            for line in ss:
                if args.verbose:
                    print(line)
                    if outfile:
                        ascii = line.encode('ascii', 'replace')
                        file.write(ascii)
                        file.write(b'\r\n')

                if line.find(searchstring) != -1:
                    print(section)
                    print(line.strip(" \\r"))
                    if outfile:
                        s = line.strip(" \\r").encode('ascii', 'replace')
                        file.write(s)
                        file.write(b'\r\n')
if outfile:
    file.close()

#if ole.exists('Pictures'):
#    pics = ole.openstream('Pictures')
#    data = pics.read()

# returns the type of a stream/storage, as one of the following constants:
# - olefile.STGTY_STREAM for a stream,
# - olefile.STGTY_STORAGE for a storage,
# - olefile.STGTY_ROOT for the root entry,
# - False for a non existing path (new in v0.15).

# s = ole.get_size('Root Entry')
# t = ole.get_type(board_section)


# The root storage is a special case: You can get its creation and modification timestamps using the OleFileIO.root attribute (new in v0.26):
c = ole.root.getctime()
m = ole.root.getmtime()

# can be used to parse any property stream that is not handled by get_metadata.
# Returns a dictionary indexed by integers. Each integer is the index of the property, pointing to its value.
# For example in the standard property stream '\x05SummaryInformation', the document title is property #2, and the subject is #3.

# p = ole.getproperties('specialprops')

# By default as in the original PIL version, timestamp properties are converted into a number of seconds since Jan 1,1601.
# With the option convert_time, you can obtain more convenient Python datetime objects (UTC timezone).
# If some time properties should not be converted (such as total editing time in '\x05SummaryInformation'), the list of indexes can be passed as no_conversion (new in v0.25):
# p = ole.getproperties('specialprops', convert_time=True, no_conversion=[10])

ole.close()
#olefile.OleFileIO.close(self) 



