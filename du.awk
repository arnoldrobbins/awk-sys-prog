#! /usr/local/bin/gawk -f

# du.awk --- write POSIX du utility in awk.
# See http://pubs.opengroup.org/onlinepubs/9699919799/utilities/du.html
#
# Most of the heavy lifting is done by the fts() function in the "filefuncs"
# extension.
#
# We think this conforms to POSIX, except for the default block size, which
# is set to 1024. Following GNU standards, set POSIXLY_CORRECT in the
# environment to force 512-byte blocks.
#
# Arnold Robbins
# arnold@skeeve.com

@include "getopt"
@load "filefuncs"

BEGIN {
	FALSE = 0
	TRUE = 1

	BLOCK_SIZE = 1024	# Sane default for the past 30 years
	if ("POSIXLY_CORRECT" in ENVIRON)
		BLOCK_SIZE = 512        # POSIX default

	compute_scale()

	fts_flags = FTS_PHYSICAL
	sum_only = FALSE
	all_files = FALSE

	while ((c = getopt(ARGC, ARGV, "aHkLsx")) != -1) {
		switch (c) {
		case "a":
			# report size of all files
			all_files = TRUE;
			break
		case "H":
			# follow symbolic links named on the command line
			fts_flags = or(fts_flags, FTS_COMFOLLOW)
			break
		case "k":
			BLOCK_SIZE = 1024       # 1K block size
			break
		case "L":
			# follow all symbolic links

			# fts_flags &= ~FTS_PHYSICAL
			fts_flags = and(fts_flags, compl(FTS_PHYSICAL))

			# fts_flags |= FTS_LOGICAL
			fts_flags = or(fts_flags, FTS_LOGICAL)
			break
		case "s":
			# do sums only
			sum_only = TRUE
			break
		case "x":
			# don't cross filesystems
			fts_flags = or(fts_flags, FTS_XDEV)
			break
		case "?":
		default:
			usage()
			break
		}
	}

	# if both -a and -s
	if (all_files && sum_only)
		usage()

	for (i = 0; i < Optind; i++)
		delete ARGV[i]

	if (Optind >= ARGC) {
		delete ARGV     # clear all, just to be safe
		ARGV[1] = "."   # default to current directory
	}

	fts(ARGV, fts_flags, filedata)	# all the magic happens here

	# now walk the trees
	if (sum_only)
		sum_walk(filedata)
	else if (all_files)
		all_walk(filedata)
	else
		top_walk(filedata)
}

# usage --- print a message and die

function usage()
{
	print "usage: du [-a|-s] [-kx] [-H|-L] [file] ..." > "/dev/stderr"
	exit 1
}

# compute_scale --- compute the scale factor for block size calculations

function compute_scale(		stat_info, blocksize)
{
	stat(".", stat_info)

	if (! ("devbsize" in stat_info)) {
		printf("du.awk: you must be using filefuncs extension from gawk 4.1.1 or later\n") > "/dev/stderr"
		exit 1
	}

	# Use "devbsize", which is the units for the count of blocks
	# in "blocks".
	blocksize = stat_info["devbsize"]
	if (blocksize > BLOCK_SIZE)
		SCALE = blocksize / BLOCK_SIZE
	else	# I can't really imagine this would be true
		SCALE = BLOCK_SIZE / blocksize
}

# islinked --- return true if a file has been seen already

function islinked(stat_info,		device, inode, ret)
{
	device = stat_info["dev"]
	inode = stat_info["ino"]

	ret = ((device, inode) in Files_seen)

	return ret
}

# file_blocks --- return number of blocks if a file has not been seen yet

function file_blocks(stat_info,		device, inode)
{
	if (islinked(stat_info))
		return 0

	device = stat_info["dev"]
	inode = stat_info["ino"]

	Files_seen[device, inode]++

	return block_count(stat_info)	# delegate actual counting
}

# block_count --- return number of blocks from a stat() result array

function block_count(stat_info,		result)
{
	if ("blocks" in stat_info)
		result = int(stat_info["blocks"] / SCALE)
	else
		# otherwise round up from size
		result = int((stat_info["size"] + (BLOCK_SIZE - 1)) / BLOCK_SIZE)

	return result
}

# sum_dir --- data on a single directory

function sum_dir(directory, do_print,	i, sum, count)
{
	for (i in directory) {
		if ("." in directory[i]) {	# directory
			count = sum_dir(directory[i], do_print)
			count += file_blocks(directory[i]["."])
			if (do_print)
				printf("%d\t%s\n", count, directory[i]["."]["path"])
		} else {			# regular file
			count = file_blocks(directory[i]["stat"])
		}
		sum += count
	}

	return sum
}

# simple_walk --- summarize directories --- print info per parameter

function simple_walk(filedata, do_print,	i, sum, path)
{
	for (i in filedata) {
		if ("." in filedata[i]) {	# directory
			sum = sum_dir(filedata[i], do_print)
			path = filedata[i]["."]["path"]
		} else {			# regular file
			sum = file_blocks(filedata[i]["stat"])
			path = filedata[i]["path"]
		}
		printf("%d\t%s\n", sum, path)
	}
}

# sum_walk --- summarize directories --- print info only for the top set of directories

function sum_walk(filedata)
{
	simple_walk(filedata, FALSE)
}

# top_walk --- data on the main arguments only

function top_walk(filedata)
{
	simple_walk(filedata, TRUE)
}

# all_walk --- data on every file

function all_walk(filedata,	i, sum, count)
{
	for (i in filedata) {
		if ("." in filedata[i]) {	# directory
			count = all_walk(filedata[i])
			sum += count
			printf("%s\t%s\n", count, filedata[i]["."]["path"])
		} else {			# regular file
			if (! islinked(filedata[i]["stat"])) {
				count = file_blocks(filedata[i]["stat"])
				sum += count
				if (i != ".")
					printf("%d\t%s\n", count, filedata[i]["path"])
			}
		}
	}
	return sum
}
