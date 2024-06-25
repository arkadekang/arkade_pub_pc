#!/usr/bin/perl
# localreview.pl
# Wrapper for pre-submission review tools:
#    Read all results in a specified directory (default is ./) 
#    and run a subset of editorial reviews on them
# Output html files are show up in specified output directory (default is ./)
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Author: Julie Reilly
#
# $Id: localreview.pl 6548 2020-11-10 16:33:32Z CloyceS $
#
# JL Reilly 2019 Nov created
#           2020 May read $SPEC to find other tools; bin = 
#                       "." when testing with standard review environment
#                       $SPEC/bin when testing with pre-submission environment
#                    added to svn
#                Jul added dimm.pl
#
#
use strict;
use warnings;
use v5.10 ; # say
use File::Path;
use Getopt::Long;
use Env qw($SUITE $SPEC $SPECPERLLIB) ;
use List::Util qw(sum) ;
use FindBin qw($Bin);
use lib $Bin;
use Review_util ;

#-------------------------------- Usage --------------------------------

my $extended_usage = <<EOF;
Usage: $0 [--input[=directorya]] [--output[=directoryb]] [--debug] [--help]
        --input|-i=directory     Which results? (default is ./)
        --output|-o=directory    Which output directory? (default is ./)
        --debug|-d               debug mode 
        --help|-h                This message
EOF

my $indir  = "./" ;
my $outdir = "." ;
my $debug  = 0 ;
my $show_usage = 0 ;

# Process command line options
 my $rc = GetOptions (
         'input:s'       => \$indir,        # ./ or elsewhere?
         'output:s'      => \$outdir,       # ./ or elsewhere?
         'debug'         => \$debug,        # boolean: are we printing in debug mode today?
         'help'          => \$show_usage ) ;

if ($show_usage) {
   print $extended_usage;
   exit ;
}

# defaults
my $suite  = $SUITE ? $SUITE : "cpu2017" ;
my $binpath  = ($SPEC and $SPECPERLLIB) ? "specperl $Bin" : "." ;
say "binpath is $binpath" if $debug ;

mkpath $outdir if (! -d $outdir) ; # Does output directory exist yet?
say "Searching $indir for results." ;

say "... Checking Memory format; output is $outdir/mem.html" ;
system ("$binpath/mem4.pl -i $indir > $outdir/mem.html") ;

say "... Checking Cross compile notes and sw_other ; output is $outdir/cross.html" ;
system ("$binpath/crosscompile.pl -i $indir > $outdir/cross.html") ;

say "... Checking Disk subsystem ; output is $outdir/disk.html" ;
system ("$binpath/disk.pl -i $indir > $outdir/disk.html") ;

say "... Checking BIOS ; output is $outdir/bios.html" ;
system ("$binpath/bios.pl -i $indir > $outdir/bios.html") ;

# one tool not ready yet
#say "... Checking ptrsizes and compiler ; output is $outdir/ptrsize.html" ;
#system ("$binpath/ptrsize.pl -i $indir > $outdir/ptrsize.html") ;

say "... Checking DIMM sizes and speed; output is $outdir/dimm.html" ;
system ("$binpath/dimm.pl -i $indir > $outdir/dimm.html") ;
