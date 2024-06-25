#!/usr/bin/perl
#
# dimm.pl
#
# Print report about comparing hw_memory versus sysinfo data about DIMMs
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Author: Julie Reilly
#
# $Id: dimm.pl 6548 2020-11-10 16:33:32Z CloyceS $ 
#
#    JL Reilly 2020 Jul creation (borrowing some from compare-dmidecode.pl)
#                   Aug remove template for reporting hw_memory syntax issues
#                          because those checks will stay in a separate report
#                       sort by submitter first
#                       add Id tag for svn
#                   Sep update CPU Max DDR speeds for newer CPUs
#                       use get_who()
#                       stop reading rsf after sysinfo
#                       update CPU max memory speeds
#                   Oct update CPU Max DDR speeds for newer CPUs
#
use strict;
use warnings;
use IO::Handle;
use v5.10 ; # say
use List::Util qw (min max) ;
use List::MoreUtils qw(uniq) ;
use Env qw(SUITE SPEC);

# avoid warnings from specperl about given/when and smartmatch
use feature qw( switch );
no if $] >= 5.018, warnings => qw( experimental::smartmatch );

# need this to locate Review_util and HTML::Table
use FindBin qw($Bin);
use lib $Bin, "$SPEC/bin/common";

use HTML::Table;
# Set several other globals via 'Review_util::init_review_tools' - see
# EXPORT list for the module.
use Review_util;
require 'util_common.pl';

sub build_mtables ;
sub build_ntables ;
sub build_stables ;
sub comp_dimm_speed ;
sub count_dimms ;
sub convert_to_gb ;
sub get_cpu_max_memspeed ;
sub read_rsf ;
sub read_sysinfo ;
sub write_preface_dimm ;
umask 0002 ;

#----------- globals -----------
our $suite = $SUITE ? $SUITE : "cpu2017" ;

# global data created as we read files, consumed by reporting routines
# 'who' is a composite key: sponsor / submitter, as in Acme / joe@acme.com
my @report ;
my $probno = 0 ;

use Text::Wrap qw($columns wrap);
$columns = 132;
my $style = 'text-align:left;white-space:nowrap;' ;
my $boldstyle = "$style;font-weight:bold;" ;
my $boxstyle = "$style;vertical-align:top;border:thin solid gray;" ;
my $boldbox = "$boxstyle;font-weight:bold;" ;
my $cstyle = 'vertical-align:top;font-family:courier new';

my $empty = "''" ;

my %pc3_speed = (
   3200  =>  400,
   4200  =>  533,
   5300  =>  667,
   6400  =>  800,
   8500  => 1066,
   10600 => 1333,
   12800 => 1600,
   14900 => 1866,
   17000 => 2133,
);

my %dmsg ; # DIMM messages
$dmsg{'badformat'} = 'hw_mem has unexpected format';
$dmsg{'differing'} = 'why dmidecode mentions dimms at allegedly differing speed combinations:' ;
$dmsg{'implies'}   = 'how fast the dimms are running. Please <a href="#howtocheck"> check the speeds' ;
$dmsg{'modules'} = 'why module counts do not match' ;
$dmsg{'multidimmunits'} = 'Sorry, but this report is too dumb to do unit conversions; please check by eye instead.' ;
$dmsg{'noconfigured'} = 'sysinfo did not report a "configured at" speed' ;
$dmsg{'nomax'} = 'the CPU max memory speed?' ;
$dmsg{'overclock'} = 'Why are DIMMS running faster than CPU max memory speed? Does this system support overcloking?' ;
$dmsg{'overmax'} = 'Why is hw_memory claiming to be faster than CPU max memory speed?' ;
$dmsg{'ranks'} = 'Can this really be true? dmidecode claims to have seen both' ;
$dmsg{'redundant'} = '<tt>running at</tt> clause is redundant with rated speed for the memory module' ;
$dmsg{'speedcheck'} = '<a href="#howtocheck">Please check the speeds</a>' ;
$dmsg{'total'} = "why total memory does not match" ;
$dmsg{'unlisted'} = 'DIMM with this rated speed is not mentioned in hw_memory' ;


init_review_tools;
$SIG{__DIE__}      = \&file_clean_at_fail;

#-----------------------------------------------------------------------------------------
# main code starts here
#-----------------------------------------------------------------------------------------

my $outdir = "$outroot/mem" ;

my %dimm_file = (
   "unpub" => "$outdir/dimm.unpub.html",
   "pub"   => "$outdir/dimm.pub.html"
) ;

common_usage ; # parse command line ; show usage if necessary

my $outfile = "STDOUT" ;
if ( ! $report_custom ) { # normal review operation, after submission

   if ($report_accepted) {
      $outfile         = $dimm_file{"pub"} ;
   } else {
      $outfile         = $dimm_file{"unpub"} ;
   }
}
my $fh = IO::Handle->new();
open_outfile $fh, $outfile ;

say $fh write_preface_dimm ;

push (@report, "<html><body>");

my %combo_ms ; # who/CPU max speed/memory/DIMM/SUT combo
my %combo_mn ; # who/CPU max speed/memory/DIMM/note combo

# get data
for my $dir ( dirs_to_report($outfile) ) {
   chomp $dir;
   say "$dir" if ($debug) ;

   # find and read result files
   my $ext = "rsf" ;
   my @files =  get_result_files($dir, $report_accepted, $ext) ;
   next if ! @files;

   for my $rsf (sort @files) {
      my $hw_memory = my $hw_cpu = my $mnotes = my $who = my $sysinfo = "" ;
      read_rsf($rsf, \$hw_memory, \$hw_cpu, \$who, \$mnotes, \$sysinfo) ;

      chomp $rsf;

      my $spec_disk ;
      my $sut = my $dmidecode = "" ;
      read_sysinfo ($rsf, $sysinfo, \$sut, \$dmidecode) ;

      my $result_link = result_link($dir,$rsf) ;
       
      my $cpu_max_memspeed = "(CPU Max DDR Speed = " . get_cpu_max_memspeed($hw_cpu) . ")" ;
      push ( @{$combo_ms{$who}{$cpu_max_memspeed}{$hw_memory}{$dmidecode}{$dir}}, "$result_link$sep$sut$sep$hw_cpu" ) ;

      foreach my $mnote ( split $sep, $mnotes ) {
         $combo_mn{$who}{$cpu_max_memspeed}{$hw_memory}{$dmidecode}{$mnote}{$dir} .= "$result_link " ;
      }
   }
}

# sort by submitter
for my $who (sort keys %combo_ms) {
   (my $sponsor, my $submitter) = split $sep, $who;

   # sort by CPU max memory speed
   for my $max_mspeed (sort keys %{$combo_ms{$who}}) {

      # sort by hw_memory
      my $wrow = 1;
      for my $hw_memory ( sort keys %{$combo_ms{$who}{$max_mspeed}} ) {

         push (@report, "<br>" ) ;
         if ($wrow == 1) {
            push (@report, "<p style=\"$boldstyle;font-size:125%\">
               $sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter
               </p>");
         } else {
            push (@report, "<p style=\"$boldstyle;\">
               $submitter continued...
               </p>" ) ;
         }

         foreach my $mtable ( build_mtables($who, $max_mspeed, $hw_memory, 
                           \%{$combo_ms{$who}{$max_mspeed}{$hw_memory}}, 
                           \%{$combo_mn{$who}{$max_mspeed}{$hw_memory}}) ) {
            push (@report, "$mtable<br>") ;
         }

         $wrow++;
      }
   }
}

push (@report, "$html_finish") ;

say $fh make_top ;

foreach (@report) {
   say $fh $_ ;
}

close ($fh) ;
exit_success;

#-------------------------------------------------------------------
# Populate DIMM note tables
#
sub build_ntables {

   my $submitter = shift ; # in 
   my $nparams = shift ; # in
   my %note_list = %$nparams ;

   my $ntable = new HTML::Table ; # note table
   my $nrow = 1 ;
   $ntable->addRow("Memory notes", "Results") ;
   $ntable->setRowHead($nrow) ;

   my @dirs ;
   foreach my $note ( sort keys %note_list ) {
      my @rlinks ;
      foreach my $dir ( sort keys %{$note_list{$note}} ) {
         push (@rlinks, "$dir\/ $note_list{$note}{$dir}") ;
         push (@dirs, $dir) ;
      }
      my $rlinks = join "\n<br>", @rlinks ;


      $nrow++ ;
      $ntable->addRow($note, $rlinks) ;
   }

   return $ntable ;
} # sub build_ntables

#-------------------------------------------------------------------
# Populate SUT table
#   Show results and the system each was tested on, with timestamp
#   Sort by submitter and dir
#
sub build_stables {

   my $who        = shift ; #  in: sponsor submitter
   my $max_mspeed = shift ; # in: CPU max memory speed
   my $bg         = shift ; #  in: background color
   my $flavor     = shift ; #  in: problem flavor
   my $dparams    = shift ; #  in
   my %dir_list   = %$dparams ;

   (my $sponsor, my $submitter) = split $sep, $who;

   my $stable = new HTML::Table ; # sut table
   my $srow = 1 ;
   $stable->addRow("Results","Systems Under Test", $max_mspeed) ;
   $stable->setRowHead($srow) ;

   foreach my $dir ( sort keys %dir_list ) {
      my $rrow = 0 ;
      foreach my $result ( @{$dir_list{$dir}} ) {
         my ($rlink, $sut, $cpu) = split $sep, $result ;
         $rrow++ ;
         $srow++ ;
         $stable->addRow("$dir\/$rlink", $sut, $cpu) ;
      }

      $probno++ ;
      my $id = add_prob($bg, $who, $flavor . "_$probno", $dir) ;
      $stable->setCellAttr(($srow - $rrow + 1), 1, $id) ;
   }

   return $stable ;
} # sub build_stables

#-------------------------------------------------------------------
# Populate hw_memory table
#
sub build_mtables {
   my $who        = shift ; # in: sponsor and submitter
   my $max_mspeed = shift ; # in: CPU max memory speed
   my $hw_memory  = shift ; # in: hw_memory

   my $dparams = shift ; # in
   my %dimm_list = %$dparams ;

   my $nparams = shift ; # in
   my %note_list = %$nparams ;

   (my $sponsor, my $submitter) = split $sep, $who;
   my @mtables ;
   my $mheader = new HTML::Table ; # hw_memory table
   my $mrow = 1 ;
   $mheader->addRow("hw_memory:") ;
   $mheader->setRCellsHead(1,1) ;

   $mrow++ ;
   $mheader->addRow("$hw_memory") ;
   $mheader->setRowStyle($mrow, $cstyle) ;
   push (@mtables, $mheader) ;

   foreach my $dimms ( sort keys %dimm_list ) {
      my $mtable = new HTML::Table ; # hw_memory table
      $mrow = 0 ;

      # DIMM speed checks
      my $speedcomplaint = comp_dimm_speed($max_mspeed, $hw_memory, $dimms) ;
      # DIMM count checks
      my $countcomplaint = count_dimms($hw_memory, $dimms) ;

      $mrow++ ;
      $mtable->addRow("DIMMS", join "<br>", (split /$sep/, $dimms)) ; 
      $mtable->setCellStyle($mrow, 2, $cstyle) ;

      
      my $bg = $successcolor ;
      if ( $speedcomplaint ne "" ) {
         $bg = choose_bg($speedcomplaint) ;

         $mrow++ ;
         $mtable->addRow("", $speedcomplaint) ; 
         $mtable->setCellBGColor($mrow, 1, $bg) ;

         $mrow++ ;
         $mtable->addRow("", build_stables($who, $max_mspeed, $bg, "DIMM_speed", $dimm_list{$dimms})) ;
         $mtable->setCellBGColor($mrow, 1, $bg) ;
         $mtable->setCellBGColor($mrow-1, 1, $bg) ;
      }
      if ( $countcomplaint ne "" ) {
         $bg = choose_bg($countcomplaint) ;

         $mrow++ ;
         $mtable->addRow("", $countcomplaint) ; 
         $mtable->setCellBGColor($mrow, 1, $bg) ;

         $mrow++ ;
         $mtable->addRow("", build_stables($who, $max_mspeed, $bg, "DIMM_count", $dimm_list{$dimms})) ;
         $mtable->setCellBGColor($mrow, 1, $bg) ;
         $mtable->setCellBGColor($mrow-1, 1, $bg) ;
      }

      # show related notes
      $mrow++ ;
      $mtable->addRow("", build_ntables($submitter, $note_list{$dimms}) . "<br>" ) ;

      # shall we highlight the notes ?
      if ( $speedcomplaint ne "" or $countcomplaint ne "" ) {
         $bg = choose_bg($speedcomplaint . $countcomplaint) ;
         $mtable->setCellBGColor($mrow, 1, $bg) ;
      }

      push (@mtables, "$mtable") ;
   }
   return @mtables ;
} # sub build_mtables


#-------------------------------------------------------------------
# Compare hw_memory speed vs. sysinfo dmidecode
#
sub comp_dimm_speed {
   my $max_mspeed   = shift ; #  in: CPU max memory speed
   my $hw_mem       = shift ; #  in: hw_memory
   my $dimms        = shift ; #  in: list of DIMMS seen by sysinfo

   my $complaint = my $detail = "" ;
   my @complaints ;

   my $max_mspeed_num = 0 ;
   $max_mspeed_num = $1 if ( $max_mspeed =~ /\s*(\d\d*)/ ) ;

   # ------------ Extract speed from the hw_mem field ------------
   my $module; 
   my $clock = my $speed = 0 ;
   my $speed1_deduced = 0 ;
   my @speeds ;
   my @module_names ;

   # 16 GB (2 x 8 GB 2Rx8 PC3-12800E-11, ECC)
   foreach my $mem (split ';', $hw_mem) {
      if ($hw_mem =~ m{(PC(\d)\S?-(\d+)\D+)}) {
         $module      = $1;
         my $ddr_generation = $2;
         my $a_number       = $3;
         if ($ddr_generation == 3) {
            # the number is bandwidth
            $speed         = $pc3_speed{$a_number};
         } else {
            # the number is frequency
            $speed         = $a_number;
         }
         push @speeds, $speed ;
         push @module_names, $module ;
      }
   }
   $speed = min ( uniq @speeds ) if scalar @speeds ; 
   my $module_list = join ' ', uniq @module_names ;

   if ($hw_mem =~ m{running at (\d+)}) {
      $clock = $1;
   }

   # ------------ Extract speed from dmidecode lines ------------
   my $sspeed = my $sclock = 0 ;
   my $prev_dimm_speed = 0 ;
   my $same_speed = 1 ;
   foreach my $dimm (split $sep, $dimms) {
      if ( $dimm =~ /rank\s*(\d+)/ ) {
         $sspeed = $1 ;
      }
      if ( $dimm =~ /configured at\s*(\d+)/ ) {
         $sclock = $1;

        # why are DIMMS running faster than CPU permits ?
         if ( $max_mspeed_num and ($sclock - $max_mspeed_num) > 1) {
            $detail = "$sclock > $max_mspeed_num" ;
            push (@complaints, complain($failcolor, $dmsg{'overclock'}, $detail)) ;
         }

      } else {
         $sclock = $sspeed;
      }

      my $this_dimm_speed = 0 ;
      if ( $dimm =~ /configured at\s*(\d+)/ ) {
         $this_dimm_speed = $1;
      } elsif ( $dimm =~ /rank\s*(\d+)/ ) {
         $this_dimm_speed = $1;
      }

      # are all the DIMMS rated at the same speed?
      if ($prev_dimm_speed && $this_dimm_speed && ($this_dimm_speed != $prev_dimm_speed)) {
         $detail = "Does the vendor support using these together: $prev_dimm_speed and $this_dimm_speed" ;
         push (@complaints, complain($warncolor, $dmsg{'differing'}, $detail) ) ;
         $same_speed = 0 ;
      } else {
         $prev_dimm_speed = $this_dimm_speed ;
      }

      # unless dmidecode found DIMMS of varying speed (which already yields a warning)
      # check whether the DIMMS are rated for the same speed as declared in hw_memory
      if ( $same_speed and $sspeed and abs ($speed - $sspeed) > 1 ) {
         $detail = "$sspeed != $speed" ;
         push (@complaints, complain($failcolor, $dmsg{'unlisted'}, $detail) ) ;
      }

   } # foreach dimm

   # check for redundant "running at" clause, unless dmidecode found DIMMS of varying speed
   if ( $clock and $same_speed and abs ($clock - $speed) < 2 ) {
      push (@complaints, complain($failcolor, $dmsg{'redundant'}, "") ) ;
   }

   # Speed match?
   # Sysinfo for CPU2017 no longer outputs a frequency unit, so don't suggest one
   $detail = "" ;
   if ($speed && $sspeed) {

      # this tool needs an update for this CPU; meanwhile reviewer must check DIMM speeds manually 
      if ( ! $max_mspeed_num ) {
         push (@complaints, complain($warncolor, $dmsg{'nomax'}, $detail)) ;

      # hw_memory claims to be faster than CPU permits
      } elsif ( $max_mspeed_num and ($speed - $max_mspeed_num) > 1 and ($clock - $max_mspeed_num) > 1) {
         $detail = "hw_memory has " ;
         if ( $clock ) {
            $detail .= $clock 
         } else {
            $detail .= $speed ;
         }
         
         if ( !$clock and $dimms !~ /configured/ ) {
            $detail .= '; is it missing this?<div style="font-family:monospace;">
               &nbsp", running at ' . $max_mspeed_num . '"</div>' ;
         }
         push (@complaints, complain($failcolor, $dmsg{'overmax'}, $detail)) ;

      # general case where a 'running at' clause may be missing
      } elsif (!$clock) {
         if (abs ($speed - $sclock) > 1) {
            $detail = <<EOF;
            <ul><li>hw_mem says "$module_list", which implies $speed </li>
                <li>dmidecode mentions $sclock </li>
                <li>After checking, if you believe that dmidecode is correct, then you may want to add this to the hw_mem field:
            <div style="font-family:monospace;font-weight:bold;margin-left:1em;">',&nbsp;running at $sclock '</div>
                </li>
             </ul>
EOF
            push ( @complaints, complain($warncolor, $dmsg{'implies'}, $detail) ) ;
         }


      # if we got here we did see 'running at' 
      #    is it's value correct?
      } elsif ( (abs ($clock - $sclock) > 1) ) {

         # 'running at' clock contradicts sysinfo configured memory speed
         if ( $dimms =~ /configured/ ) {
            $detail = $dmsg{'speedcheck'} ;
            push (@complaints,  complain($warncolor, 
               "why hw_mem has $clock but dmidecode mentions $sclock", $detail) ) ;

         # perhaps sysinfo did not parse dmidecode correctly?
         } else {
            $detail = "hw_mem has $clock" ;
            if ( abs ($clock - $max_mspeed_num) <= 1 ) {
               $detail .= " which matches CPU max memory speed" ;
            }

            push (@complaints,  complain($infocolor, 
               "dmidecode mentions $sclock but $dmsg{'noconfigured'}", $detail) ) ;

         }
      }

   }

   $complaint = join "<br>", (uniq @complaints) ;
   return $complaint ;
} # sub comp_dimm_speed

#-------------------------------------------------------------------
# Compare hw_memory size/count vs. sysinfo dmidecode
#
sub count_dimms {
   my $hw_mem       = shift ; #  in: hw_memory
   my $dimms        = shift ; #  in: list of DIMMS seen by sysinfo

   my $complaint = my $detail = "" ;
   my @complaints ;

   # ------------ Extract info from the hw_mem field ------------
   my $mem_count = 0 ;
   my $mem_total = 0 ;
   my $mem_unit = "" ;
   my $ranks = 0 ;
 
   # 16 GB (2 x 8 GB 2Rx8 PC3-12800E-11, ECC)
   if ( $hw_mem =~ /^\s*(\d+)\s*(KB|MB|GB|TB)/i ) {
      $mem_total = $1;
      $mem_unit  = $2;
   }

   # various DIMM types should be separated by ';'
   foreach my $mem (split ';', $hw_mem) {
      if ( $mem =~ /(\d+) x (\d+)\s/ ) {
         $mem_count += $1 ;
      }
   }
  
   if ($hw_mem =~ / (\d+)Rx\d+ /) {
      $ranks = $1;
   }

   # ------------ Extract info from the dmidecode lines ------------
   my $dimm_count2 = my $dimm_count3 = 0  ;
   my $mem_total2 = my $mem_total3 = 0 ;
   my $dimm_unit = "" ;
   my $dimm_ranks ;
   
   foreach my $dimm (split $sep, $dimms) {

      my $this_dimm_set = $1 if $dimm =~ /^(\d+)\s*x/ ;
      $dimm_count2 += $this_dimm_set ;
    
      if ( $dimm =~ /^$this_dimm_set\s*x.*\s+(\d+)\s*(KB|MB|GB|TB)/i ) {
         my $size = $1; 
         my $this_dimm_unit = $2 ;
         if ($dimm_unit && $dimm_unit ne $this_dimm_unit) {
            $detail = "dmidecode saw both |$dimm_unit| and |$this_dimm_unit|" ;
            push ( @complaints, complain($warncolor, $dmsg{'multidimmunits'}, $detail) ) ;

         } else {
            # sometimes dmidecode shows total memory before listing modules
            if ( $dimm =~ /^$this_dimm_set\s*x\s*(\d+)\s*(KB|MB|GB|TB)/i ) {
               $mem_total3 += $this_dimm_set * $size;
               $dimm_count2 -= $this_dimm_set;
               $dimm_count3 += $this_dimm_set;
            } else {
               $mem_total2 += $this_dimm_set * $size;
            }
            $dimm_unit = $this_dimm_unit;
         } # unit consistency


         # ranks
         $detail = "" ;
         my $this_dimm_ranks = 0 ;
         if ( $dimm =~ / (\d*) rank/ ) {
            $this_dimm_ranks = $1;
            if ($dimm_ranks && $dimm_ranks != $this_dimm_ranks) {
               $detail = "$dimm_ranks-rank and $this_dimm_ranks-rank dimms." ;
               push( @complaints, complain($warncolor, $dmsg{'ranks'}, $detail) ) ;

            } else {
               $dimm_ranks = $this_dimm_ranks;
            }
         } # rank consistency
      }
   } # foreach dimm

   # Counts match?
   #
   # If we assumed dmidecode showed a total memory prior to listing
   #  but these totals don't match, then our assumption is wrong
   if ( ($mem_total3 != 0 && $mem_total3 ne $mem_total2)
     || ($dimm_count3 != 0 && $dimm_count3 ne $dimm_count2)
   ) {
      $mem_total2 += $mem_total3 ;
      $dimm_count2 += $dimm_count3 ;
   }

   if ($mem_count ne '?' && $mem_count ne $dimm_count2) {
      $detail = "hw_mem says there are $mem_count memory modules; in <tt>$hw_mem</tt><br>" ;
      $detail .= "dmidecode may have seen $dimm_count2." ;
      push ( @complaints, complain($warncolor, $dmsg{'modules'}, $detail) ) ;
   }

   # Capacity match? 
   if (! abs ($mem_total - $mem_total2) < 1 or ! ($mem_unit eq $dimm_unit) ) {
      my $m1 = convert_to_gb ($mem_total, $mem_unit);
      my $m2 = convert_to_gb ($mem_total2, $dimm_unit);
      if (! $m1 || ! $m2 || abs ($m1 - $m2) > 1) {
         $detail = "hw_mem says the total memory is $mem_total $mem_unit; " ;
         $detail .= "dmidecode total might be $mem_total2 $dimm_unit." ;
         if ( $mem_unit !~ /kb/i and $dimm_unit =~ /kb/i ) {
            $detail .= "<br>Sysinfo may be reporting the wrong size" ;
            push ( @complaints, complain($warncolor, $dmsg{'total'}, $detail) ) ;
         } else {
            push ( @complaints, complain($warncolor, $dmsg{'total'}, $detail) ) ;
         }
      }
   }

   $complaint = join "<br>", (uniq @complaints) ;
   return $complaint ;
} # sub count_dimms

#-------------------------------------------------------------------
# convert size to GB
#    During 2020 most DIMMS are currently GB 
#    
sub convert_to_gb {
   my $amount = shift ;
   my $unit   = shift ; 
   my %gb = ( 
      KB => (1/1024) * (1/1024) ,
      MB => (1/1024) ,
      GB => 1 ,
      TB => 1024 ,
   ) ;
   if ( defined $gb{uc $unit} ) {
      return $amount * $gb{uc $unit} ;
   } else {
      return undef ;
   }
      
} # sub convert_to_gb

#-------------------------------------------------------------------
# Return max memory speed (MT/s) for the CPU
#    Read CPU vendor data sheets and hardcode the answers
#
sub get_cpu_max_memspeed {
   my $cpu     = shift ; # in : CPU name

   given ( $cpu ) {
      # 3rd Gen Intel Xeon Scalable Platform for servers
      when ( /xeon.*(platinum 835)/i ) { return "2933" } ;
      when ( /xeon.*(platinum 83)/i ) { return "3200" } ;
      when ( /xeon.*(gold 63)/i ) { return "2933" } ;
      when ( /xeon.*(gold 53)/i ) { return "2666" } ;

      # 2nd Gen Intel Xeon Scalable Platform for servers
      when ( /xeon.*(gold 6222|gold 6262v)/i ) { return "2400" } ;
      when ( /xeon.*(platinum 92|platinum 82|gold 62)/i ) { return "2933" } ;
      when ( /xeon.*(gold 5222)/i ) { return "2933" } ;
      when ( /xeon.*(gold 52)/i ) { return "2667" } ; # Remaining 52xx

      # 1st Gen Intel Xeon Scalable Platform for servers
      when ( /xeon.*(platinum 81|gold 61)/i ) { return "2666" } ;
      when ( /xeon.*(gold 5122)/i ) { return "2666" } ;
      when ( /xeon.*(silver|gold 51)/i ) { return "2400" } ; # Remaining 51xx
      when ( /xeon.*(bronze)/i ) { return "2133" } ;

      # Intel Xeon Scalable for Workstations
      when ( /xeon.*(e|w)-2(1|2)/i ) { return "2666" } ;

      # Intel Xeon Scalable Low-Power SoC
      when ( /xeon.*d-1571/i ) { return "2400" } ;
      when ( /xeon.*d-1541/i ) { return "2400" } ;
      when ( /xeon.*d-1521/i ) { return "2133" } ;

      # Intel Xeon Ivy Bridge 
      when ( /xeon.*e7-(8890|4850).*v(3|4)/i ) { return "1866" } ;
      when ( /xeon.*e5-26[5689]/i ) { return "2400" } ;
      when ( /xeon.*e5-26[234]/i ) { return "2133" } ;
      when ( /xeon.*e5-26[0]/i ) { return "1866" } ;
      when ( /xeon.*e3-12/i ) { return "2400" } ;

      # Intel Core Desktop
      when ( /core.*i\d-10\d\d\d/i ) { return "2933" } ;
      when ( /core.*i3-9/i ) { return "2400" } ;
      when ( /core.*i\d-9/i ) { return "2666" } ;
      when ( /core.*i(7|5)-8/i ) { return "2666" } ;
      when ( /(core.*i3-8|pentium gold g5| g49\d\d)/i ) { return "2400" } ;
      when ( /core.*i\d-7\d\d\du/i ) { return "2133" } ;
      when ( /core.*i\d-7/i ) { return "2400" } ;
      when ( /core.*i\d-6/i ) { return "2133" } ;

      # Intel Pentium
      when ( /intel.*g4560/i ) { return "2400" } ;
      when ( /intel.*g4400/i ) { return "2133" } ;

      # Intel Celeron
      when ( /intel.*g3930/i ) { return "2133" } ;
      
      # AMD
      when ( /epyc 7\w\d2/i ) { return "3200"  } ;
      when ( /epyc (7601|7551|7451|7371)/i ) { return "2666"  } ;
      when ( /epyc (7501|7401|7351|7301|7281|7261)/i ) { return "2666, 2400" } ;
      when ( /epyc (7251)/i ) { return "2400"  } ;

 
      # Huawai
      when ( /kunpeng/i ) { return "2933" } ;

      # IBM ?
      # Sparc ?
      
      default { return "unknown" } ;
   }

} # sub get_cpu_max_memspeed

#-------------------------------------------------------------------
#  Read the result's .rsf (raw) file, and tuck away data from some fields
#  editable by the submitter.
#
sub read_rsf {
   my $rsf                 = shift ; #  in:  file to read
   my $hw_mem_ref          = shift ; # out: contents of hw_memory
   my $cpu_ref             = shift ; # out: CPU vendor or architecture
   my $who_ref             = shift ; # out: sponsor[sep]submitter
   my $mnotes_ref          = shift ; # out: notes related to memory speed
   my $sysinfo_ref         = shift ; # out: sysinfo lines

   my $sponsor = my $submitter = "" ;
   my $hw_cpu_name = "" ;
   my @compnotes ;


   my $FILE ;
   open ($FILE, "<", $rsf) or say "Could nst open $rsf";
   while (my $rline = <$FILE>) {
      chomp $rline;
      last if $rline =~ /$suite\.results/ ;

      if ($rline =~ /hw_memory[^:]*:\s*(.*)/) {
         $$hw_mem_ref .= "$1 " ;
         
      } elsif ($rline =~ /hw_cpu_name[^:]*:\s*(.*)/) {
         $hw_cpu_name = $1  ;
         
      } elsif ($rline =~ /sponsor[^:]*:\s*(.*)/) {
         $sponsor .= "$1 ";
         $sponsor =~ s/\s*$//;

      } elsif ( $rline =~ /spec.$suite.(notes[^:]*):(.*)/ ) {
         my $note_section = $1 ;
         my $note = $2 ;
         $note =~ s/^\s*//;
         $note =~ s/\s*$//;

         if ( $note =~ /(memory|dimm|dmidecode|running at)/i ) {
            if ( $note =~ /(speed|freq|clock|interleav)/i or $note_section =~ /notes_plat_update/ ) {
               $$mnotes_ref .= "$note_section: $note$sep" ;
            }

         # Enforce POR (any overclocking?)
         } elsif ( $note =~ /force\s*por/i ) {
            $$mnotes_ref .= "$note_section: $note$sep" ;
         }

      } elsif ($rline =~ m{Submitted_by:\s*(.*)}) {
         $submitter = $1;
         $$who_ref = get_who($sponsor, $submitter) ;
       
      } elsif ($rline =~ m{compnotes_sysinfo(\d+):\s*(.*)}) {
         $compnotes[$1] = $2 ;
      
      }

   } # while
   close $FILE ;

   $$hw_mem_ref = "not found" if $$hw_mem_ref eq "" ;
   $$mnotes_ref = $empty if $$mnotes_ref eq "" ;


   $$sysinfo_ref = decode_decompress(join('', @compnotes)) ;
   $$sysinfo_ref =~ s/notes_plat_sysinfo_(\d+)://g ;

   # normalize whitespace 
   $hw_cpu_name =~ s/\h+/ /g;
   $hw_cpu_name =~ s/\s+$//; # no trailing space
   $$cpu_ref = $hw_cpu_name ; # until we write code to pick something shorter
   $$hw_mem_ref =~ s/\s+$//; # no trailing space


} # sub read_rsf

#-------------------------------------------------------------------
# Tuck away OS info from the result's Sysinfo data
#
sub read_sysinfo {
   my $rsf                  = shift ; #  in: result file
   my $sysinfo              = shift ; #  in: sysinfo data
   my $sut_ref              = shift ; # out: System Under Test, with timestamp
   my $dmidecode_ref        = shift ; # out: dmidecode lines

   my @sysinfo =  split /\n/, $sysinfo ;

   $$sut_ref = "unknown" ;
   my $mdata = "unknown" ;
   my $data_part1 = "" ;

   my $in_memlines = 0 ;

   foreach (@sysinfo) {

      if ( /running on\s(.*)/ ) {
         $$sut_ref = $1 ;
      }

      $in_memlines = 1 if /Additional information from dmidecode/ ;
      $in_memlines = 0 if /End of data from sysinfo/ ;

      next unless $in_memlines ;

      # notes_plat_sysinfo_245 =    32x Micron 36JSF1G72PZ-1G6M1 8 GB 1600 MHz 2 rank
      $mdata = $_ ;
      $mdata =~ s/^(?:#|not\S+\s*=)\s*// ;
      $mdata =~ s/^\s*// ;

      # sysinfo memory line was split before frequency value
      if ($mdata =~ m{configured\s*(at)?\s*$}) {
         chomp($mdata) ;
         $data_part1 = $mdata . " ";
         next ;
 
      } else {
         $mdata = $data_part1 . $mdata ;
         $data_part1 = "" ;
      }
 
      # Look for excuse to skip this line
      next unless $mdata  =~ m{^(\d+)\s*x};
      my $this_dimm_set     = $1;
      next if     $mdata  =~ m{^\d+x\s*(empty empty\s*)+$};
      next if     $mdata  =~ m{^\d+x\s*(not defineD\s*)+$}i;
      next if     $mdata  =~ m{^\d+x\s*NO DIMM\s*};
      next if     $mdata  =~ m{^\d+x\s*(UNKNOWN NOT AVAILABLE\s*)+$};
      next if     $mdata  =~ m{^\d+x\s*(UNKNOWN\s*UNKNOWN\s*)+$}i;
      next if     $mdata  =~ m{^\d+x\s*(Dimm.\d+_Manufacturer\s+Dimm.\d+_PartNum)+};
      next if     $mdata  =~ m{^\d+x\s*(Dimm\d+_Manufacturer\s+Dimm\d+_PartNum)+};
      next if     $mdata  =~ m{^\d+x\s*(None\s*)+$};
      next if     $mdata  =~ m{^\d+x\s*(\[Empty\]\s*)+$};
      next if     $mdata =~ m{^\d+x\s*Not\s+Specified\s+Not\s+Specified};

      $$dmidecode_ref      .= "$mdata$sep" ;

   } # while

   if ( $$sut_ref =~ /unknown/ ) {
      print "Did not find SUT: '$rsf $$sut_ref '\n";
   }
      
   if ( $$dmidecode_ref =~ /unknown/ ) {
      print "Did not find memory in dmidecode '$rsf $$dmidecode_ref '\n";
   }

} # sub read_sysinfo

#-------------------------------------------------------------------
# Write the report header
#
sub write_preface_dimm {
   my $title = "DIMM report" ;

   my $more_style = <<EOF;
.snugbot      { margin-bottom:0.1em; }
EOF

#     <li>Does hw_memory conform to SPEC's requirements for description of memory, 
#        from  <a href="https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat">
#        https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat ?</a></li>
   # purpose, explain the concepts and limitations
   my $html_top = <<EOF;

<table>
<tr>

   <td>
   <h3 style="margin-top:.1em;">Purpose of this report</h3>

   <p class="l1">This page shows the main memory for each system under test.
Submissions are sorted by sponsor / hw_memory / DIMMS found by dmidecode </p>

   <h3>How to read this report</h3>

      <p>Do speed and size of DIMMs match hw_memory?</p>

      <ul class="l1">
         <li>Please consider the <tt>dmidecode</tt> data carefully.</li>
         <li>If <tt>dmidecode</tt> appears to disagree with your memory
         information, form a hypothesis as to why.</li>
         <li>Is the information on this page reminding you of something?  ("Oh
         yes, right, this was the system that had 8 GB dimms, not 16 GB.")
         </li>
         <li>Or is the <tt>dmidecode</tt> data mistaken, redundant, buggy, or
         otherwise simply not useful?</li>
         <li>Make an intelligent decision as to whether or not your <tt>hw_memory</tt>
   needs to be changed or whether the result needs a <b>notes_plat_update</b></li>

      </ul>

   <h3 id="howtocheck">How to check memory information</h3>

   <p>You might find any of these useful:</p>
   <ul>
   <li>BIOS information screens</li>
   <li>The full output from dmidecode (instead of the subset in this report)</li>
   <li>The actual JEDEC number printed on the physical DIMM</li>
   <li>The "Part Number Decoder" from the DIMM Manufacturer</li>
   <li>The specifications for your CPU chip or motherboard</li>
   </ul>

   <h3>Limitations</h3>

   <p>These checks are not reliable if hw_memory is incorrectly formatted.</p>
   <p>It is understood that the information from <tt>dmidecode</tt> is, sometimes,
   unclear, buggy, or hard to interpret.   Therefore, it is not expected that
   <tt>hw_mem</tt> will always match. </p>

   <h3>Unpublished vs. published</h3>

</tr>
</table>
EOF

   $html_top .= available_reports(\%dimm_file) ;

   return( init_html_vars($title, $more_style, $html_top) ) ;

} # sub write_preface_dimm



