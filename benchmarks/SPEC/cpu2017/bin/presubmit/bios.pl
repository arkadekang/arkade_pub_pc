#!/usr/bin/perl
#
# Print report of BIOS version and mitigation notes for each directory / submitter 
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Author: Julie Reilly
#
# $Id: bios.pl 7909 2020-10-20 18:10:33Z JulieReilly $
#
# JL Reilly 2018 Jan creation
#                Feb parse and report on cve mitigation notes
#                    modularize this code
#                    partial support for CPU2006
#                    rsf_to_link() and colors are now in Review_util.pm
#                    $sep and choose_bg() and complain() are in Review_util.pm
#                    includes Table of problems
#                    paint successful mitigation statements green
#                Mar skip fewer lines when searching for sysinfo BIOS
#                    accept alternate date format in fw_bios, after "tested as", as part of BIOS version
#                Apr fixed bug reading sysinfo BIOS date on "next" line
#                    fixed bug parsing "tested as" clauses
#                    adjustment to parsing of fw_bios version name
#                    BIOS version name may include a date
#                    stop accepting alternate date format after "tested as"
#                    refer to wiki BIOSexamples
#                Jun List CPUs. AMD EPYC CPUs are immune from Meltdown (may show NA for mitigation)
#                Jul Don't show mitigation for earliest results, which did not require them
#                    rsf_to_link() -> result_link()
#                    let module handle more of preface
#                Aug sort Accepted results by quarter rather than by pub date
#                    renamed some styles
#                    no platform flags error msg if notes_plat_NNN specifically says BIOS is at default
#           2019 Feb Some Intel BIOS version numbers can be called by a shorter name
#                Mar parse fw_bios date more carefully
#                Apr Change color scheme: now required mitigation is not highlighted, extra is green
#                May sysinfo may use a variety of date formats
#                    begin parsing Kernel self-reported vulnerability status from sysinfo
#                    - Sysinfo may mention CVE immunity (e.g. "not affected" ) explicitly
#                    fix bugs comparing dates
#                Jul AOCC flags file is not a platform flags file
#                    Intel Xeon "Cascade Lake" CPUs should also show NA for Meltdown mitigation
#                    Better algorithm for checking Meltdown immunity 
#                    For hardware mitigation, answer should be NA even if Kernel vulnerability status is unknown
#                       or a software mitigation patch is applied 
#                Aug fix bugs parsing sysinfo BIOS version and processing sysinfo BIOS date
#                    refine parsing of flagsurl fields
#                Sep tweaked fw_bios whitespace in report
#                Oct fw_bios might contain more detail than sysinfo shows about BIOS
#                Nov more CPUs are immune from Meltdown
#                Dec sample in preface mitigation statements now use a fixed-width font
#                    more detailed error messages for whitespace variations in mitigation statements
#                    check whether BIOS settings appear in the platform flags file
#                    dirs_to_search is in Review_util.pm
#           2020 Jan use get_result_files()
#                    green is now goodcolor instead of infocolor
#                    BIOS setting list at bottom or report is sorted
#                Feb rewrote comparison of fw_bios vs. sysinfo versions
#                    update conditional to determine date reporting required mitigation notes
#                    report all descriptions missing from flags file, not merely the last one
#                Mar Stop showing BIOS settings; they were moved to another report
#                Apr complain when systems vulnerable to a CVE claim they are mitigated
#                May use available_reports() and common_usage()
#                    suppress specperl warnings about experimental given/when and smartmatch
#                    flags files not shown as links in custom reports
#                Sep use get_who() and FindBin
#                    read sysinfo data from .rsf instead of .orig.cfg
#                    Intel Coffee Refresh and Cooper Lake are immune from Meltdown
#

use strict; use warnings; use IO::Handle; 
use v5.10 ; # say, ~~
use Time::Piece ; use File::Basename ; use List::MoreUtils ;
use List::MoreUtils qw(uniq first_index);
use Env qw($SUITE SPEC) ;

use feature qw( switch ); # avoid warnings from specperl about given/when and smartmatch
no if $] >= 5.018, warnings => qw( experimental::smartmatch );

# need this to locate Review_util and HTML::Table
use FindBin qw($Bin);
use lib $Bin, "$SPEC/bin/common";

use HTML::Table;
# Set several other globals via 'Review_util::init_review_tools' - see
# EXPORT list for the module.
use Review_util;
require 'util_common.pl';

sub write_preface_bios  ;
sub read_rsf ;
sub read_sysinfo ;
sub build_btables ;
sub build_mtables ;
sub build_ftables ;
sub change_bg ;
sub check_mnote ;
sub compare_bversions ;
sub immune_from_Meltdown ;
sub igspace ;

umask 0002 ;

#----------- globals -----------
our $suite = $SUITE ? $SUITE : "cpu2017" ;
my $empty = "''" ;

 
my $style = 'text-align:left;white-space:nowrap;' ;
my $boldstyle = "$style;font-weight:bold;" ;
my $boxstyle = "$style;vertical-align:top;border:thin solid gray;" ;
my $boldbox = "$boxstyle;font-weight:bold;" ;
my $fstyle .= 'vertical-align:top;border:thin solid gray;';
my $mstyle .= 'vertical-align:top;font-family:courier new';
my $pstyle .= 'vertical-align:top;font-family:courier new';

my @setting_list ; # list of all BIOS settings found


# These are the security concerns for which SPEC requires documentatio of mitigation
my %cve_nicknames ; # unique CVE numbers, with their nicknames
$cve_nicknames{'CVE-2017-5754'} = "(Meltdown)" ;
$cve_nicknames{'CVE-2017-5753'} = "(Spectre variant 1)" ;
$cve_nicknames{'CVE-2017-5715'} = "(Spectre variant 2)" ;
my @cve_numbers = sort keys %cve_nicknames ;

my $mit_search_string1 = "(attests)" ;
my $mit_search_string2 = "(tested and documented)" ;
my $valid_mit_syntax1 = "The test sponsor attests, as of date of publication, that ";
my $cve_format = 'CVE-\d\d\d\d-\d\d\d\d' ;
my $valid_mit_syntax2 = " is mitigated in the system as tested and documented." ;
my $valid_mit_answers = "(Yes|No|NA)" ;
my $before_mit_dates = "res2016|res2017|appr201801" ;

my %mitmsg ;
$mitmsg{"InvalidAnswer"} = "<br>Invalid answer in mitigation note. Choose one of $valid_mit_answers " ;
$mitmsg{"No"} = "whether system is supported" ;
$mitmsg{"NA"} = "whether system is vulnerable" ;
$mitmsg{"Immune"} = "why systems immune from this CVE do not say NA" ;
$mitmsg{"Vulnerable"} = "Systems vulnerable to this CVE should say No" ;
$mitmsg{"UnknownCVE"} = "<br>CVE number does not match any of: @cve_numbers" ;
$mitmsg{"NotReq"} = "SPEC CPU does not require mitigation of this CVE" ;
$mitmsg{"MissingAllMit"} = "Missing all required mitigation notes (see list at top of page)" ;
$mitmsg{"Components"} = "<br>Mitigation note is missing some required components" ;
$mitmsg{"SeeFormat"} = "<br>Mitigation note is missing some required components (see format at top of page)" ;
$mitmsg{"MissingCVE"} = "<br>Could not find mitigation note for " ;
$mitmsg{"Whitespace"} = "<br>Whitespace issue " ;


# global data created as we read files, consumed by reporting routines
# 'who' is a composite key: sponsor / submitter, as in Acme / joe@acme.com
my @report ;

use Text::Wrap qw($columns wrap);
$columns = 132;

init_review_tools;
$SIG{__DIE__}      = \&file_clean_at_fail;

#-----------------------------------------------------------------------------------------
# main code starts here
#-----------------------------------------------------------------------------------------

my $outdir = "$outroot/sysinfo" ;
my %bios_file = (
   "unpub" => "$outdir/bios.unpub.html",
   "pub"   => "$outdir/bios.pub.html"
) ;

common_usage ; # parse command line ; show usage if necessary

my $outfile = "STDOUT" ;
if ( ! $report_custom ) { # normal review operation, after submission

   if ($report_accepted) {
      $outfile         = $bios_file{"pub"} ;
   } else {
      $outfile         = $bios_file{"unpub"} ;
   }
}
my $fh = IO::Handle->new();
open_outfile $fh, $outfile ;

say $fh write_preface_bios;

push (@report, "<html><body>");

my $flagurl = "http://pro.spec.org/private/osg/submit/$suite/flags/" ;
my $flagpath = "$submittop/flags" ;

# sort by directory
for my $dir ( dirs_to_report($outfile) ) {
   chomp $dir;
   say "$dir" if ($debug) ;

   my %combo_wb ; # who and fw_bios combos with attempts at mitigation notes
   my %combo_bb ; # fw_bios and Sysinfo BIOS combos
   my %combo_bc ; # fw_bios and CPU combos
   my %combo_m  ; # mitigation note combos
   my %combo_fp ; # flag filename and platform note combos

   # find and read result files
   my $ext = "rsf" ;
   my @files =  get_result_files($dir, $report_accepted, $ext) ;
   next if ! @files;

   push (@report, "\n\n<h2 style=\"border-top:medium solid black;\">$dir</h2>\n") ;
   for my $rsf (sort @files) {
      my $hw_cpu = my $fw_bios = my $flags = my $mnotes = my $who = "" ;
      my $sysinfo = my $sysbios = "" ;
      my %sysvstatus ;
      my $rate = 0 ;

      my $result_link = result_link($dir,$rsf) ;

      $rate = read_rsf ($rsf, \$hw_cpu, \$fw_bios, \$flags, \$mnotes, \$who, \$sysinfo) ;
      read_sysinfo ($sysinfo, \$sysbios, \%sysvstatus) ;

      $combo_wb{$who}{$fw_bios} .=  "$result_link$sep" unless ($mnotes eq $empty) ;


      $combo_bb{$who}{$fw_bios}{$sysbios} .= "$result_link " ;
      $combo_bc{$who}{$fw_bios}{$hw_cpu} .= "$result_link " ;
      $combo_fp{$who}{$fw_bios}{$flags} .= "$result_link " ;

      foreach my $note ( split /$sep/, $mnotes ) {
         (my $cve) = $note =~ /($cve_format)/ ;
         $cve = $empty if not defined $cve ;

         my $vstatus ; 
         # Kernel said the system is not affected by this CVE
         if ( defined $sysvstatus{$cve} and $sysvstatus{$cve} =~ /not affected/i ) {
            $vstatus = $sysvstatus{$cve} ;

         # Kernel said the system is vulnerable to this CVE
         } elsif ( defined $sysvstatus{$cve} and $sysvstatus{$cve} =~ /(vulnerable)/i ) {
            $vstatus = $sysvstatus{$cve} ;

         # redundant software patch for Meltdown for a system with hardware mitigation?
         } elsif ( $note =~ /Meltdown/i and immune_from_Meltdown($hw_cpu) ne $empty ) {
            $vstatus = "Immune" ;
 
         # ignore other mitigation status reports for now
         } else {
            $vstatus = $empty ;

         }
         if ( $result_link !~ /$before_mit_dates/ ) {
            $combo_m{$who}{$fw_bios}{$note}{$vstatus} .= "$result_link " ;
         }
      }

   }


   # sort by submitter
   for my $who (sort keys %combo_bb) {
      (my $sponsor, my $submitter) = split $sep, $who;

      # sort by bios
      my $who_row = 1;
      for my $fw_bios (sort keys %{$combo_bb{$who}} ) {

         push (@report, "<br>");
         if ($who_row == 1) {
            push (@report, "<p style=\"$boldstyle;font-size:125%\">
               $sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter
               </p>");
         } else {
            push(@report, "<p style=\"$boldstyle;\">
               $submitter continued...
               </p>");
         }

         push (@report, build_btables( $dir, $who, $fw_bios, \%{$combo_bb{$who}{$fw_bios}} ));
         push (@report, build_mtables( $dir, $who, $fw_bios, $combo_wb{$who}{$fw_bios}, 
                                       \%{$combo_m{$who}{$fw_bios}},
                                       \%{$combo_bc{$who}{$fw_bios}} ));
         push (@report, build_ftables( $dir, $who, $fw_bios, \%{$combo_fp{$who}{$fw_bios}} )) if $suite ne "cpu2006";

         $who_row++;
      }
   }

} # for $dir

# case-insensitive sorted list
if (@setting_list) {
   my $setting_list = "BIOS settings found today: <br>" ;
   foreach ( sort {uc($a) cmp uc($b)}uniq @setting_list) {
      $setting_list .= "$_ <br>" ;
   }
   push (@report, "------------------------<br>$setting_list") ;
#  say $setting_list if $debug ;
}

push (@report, "$html_finish") ;

say $fh make_top ;
foreach (@report) {
   say $fh $_ ;
}

close ($fh) ;
exit_success;

#---------------------------------------------------------------------------
# Populate BIOS comparison table
#    Always use Time::Piece when comparing dates. You cannot directly compare strings mmm-yyyy; 
#    e.g. Feb-2019 computes as "less than" Mar-2018 even though Feb-2019 is later
#
sub build_btables() {
   my $dir        = shift ; # input
   my $who        = shift ; # input sponsor and submitter
   my $bios       = shift ; # input fw_bios
   my $oparams    = shift ;

   my %sysbios_list  = %$oparams ; # list of BIOS seen by sysinfo

   my $os_release ;  
   my $os_codename="" ; 
   my $os_kernel = "" ;

   my $bios_version = my $bios_strdate = my $bios_moyr = "" ;
   my $month = "Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec" ;

   # parse bios
   my $btime ;
   if ( $bios =~ /version\s*(.*\S+)\s*released\s*(\w\w\w-20\d\d)/i ) {
      $bios_version = $1 ;
      $bios_strdate = $2 ;

      # sometimes Fujitsu ends version with a ".", but sysinfo does not include "."
      $bios_version =~ s/\.$// ; 

      if ( $bios =~ /tested as\s*(.*)/i ) {
         my $tbios = $1 ;

         my $tbios_strdate = my $tbios_version = "" ;
         if ($tbios =~ /\s*($month)(-20\d\d)/ ) {
           $tbios_strdate .= $1 .$2 ;
           ($tbios_version) .= $tbios =~ /\s*(.*)\s+$tbios_strdate/ ;
         } else {
           $tbios_version .= $tbios ;
         }

        say "\ttested as $tbios_version dated $tbios_strdate" if $debug ;
        
        $bios_version = $tbios_version if ($tbios_version ne "") ;
        $bios_strdate = $tbios_strdate if ($tbios_strdate ne "") ;
      }

      $btime = Time::Piece->strptime($bios_strdate, '%b-%Y');
      $bios_moyr = $btime->strftime("%m") . $btime->strftime("%Y") ;
   }

   my $bheader = new HTML::Table( -style=>$boldbox ) ;
   $bheader->addRow( "fw_bios: $bios" ) ;

   my $otable = new HTML::Table() ;
   my $orow = 0 ;

   # is fw_bios consistent with BIOS found by sysinfo ?
   for my $sysbios (sort keys %sysbios_list ) {

      my $bg = my $newcolor = $successcolor ;
      my $complaint = my $detail = "" ;
      my $bios_complaint  = "fw_bios contradicts BIOS info seen by sysinfo" ;
      my $bios_dcomplaint  = "fw_bios release date contradicts BIOS release date seen by sysinfo" ;

      if ($sysbios =~ /not find/) { 
         $newcolor = change_bg($warncolor, $bg) ;
         $bg = $newcolor ;
         $detail .= "Could not detect sysinfo BIOS" ;

      # compare to sysinfo BIOS
      } elsif ($suite ne "cpu2006") {
    
         my $sysbios_date = my $version_bg = "" ;
         $detail .= compare_bversions($bios_version, $sysbios, \$sysbios_date, \$version_bg) ;
         $newcolor = change_bg($version_bg, $bg) ;
         $bg = $newcolor ;

         # this will break in the 22nd century
         my $systime ;
         my $sysbios_moyr = "" ;
         if ( $sysbios_date =~ /(\d\d\/\d\d\/20\d\d)/ ) {
            $systime = Time::Piece->strptime($sysbios_date, '%m/%d/%Y');
            $sysbios_moyr = $systime->strftime("%m") . $systime->strftime("%Y") ;

         } elsif ( $sysbios_date =~ /(20\d\d\/\d\d\/\d\d)/ ) {
            $systime = Time::Piece->strptime($sysbios_date, '%Y/%m/%d');
            $sysbios_moyr = $systime->strftime("%m") . $systime->strftime("%Y") ;
         }
           
         # found a sysinfo bios date, so compare dates 
         if ($sysbios_moyr ne "") {
            # sysinfo BIOS date is part of its version name
            if ( $bios_version =~ /(\d\d\/\d\d\/20\d\d)/ ) {
               my $bios_vdate = $1 ;
               my $bvtime = Time::Piece->strptime($bios_vdate, '%m/%d/%Y');
               my $bv_moyr = $bvtime->strftime("%m") . $bvtime->strftime("%Y") ;
               
               if ( $bvtime != $systime ) {
                  $newcolor = change_bg($failcolor, $bg) ;
                  $detail .= "dates do not match\.<br>" ;
                  $detail .= "|$bios_vdate| vs |$sysbios_date|<br>" ;

               } elsif ( $bvtime < $systime ) { 
                  $newcolor = change_bg($failcolor, $bg) ;
                  $detail .= "|$bios_vdate| is earlier than |$sysbios_date|" ;
               }

            } elsif ( $bios =~ /test.*with/i ) {
               $newcolor = change_bg($warncolor, $bg) ;
               $detail .= "Please say <b>tested as</b> instead" ;

            # fw_bios for some early CPU2017 results does not contain "released MMM-YYYY"
            } elsif ( $bios_strdate eq "" ) {
               $newcolor = change_bg($warncolor, $bg) ;
               $bg = $newcolor ;
               $detail .= "Cannot compare BIOS dates. " ;

            # sysinfo BIOS date is a release date; i.e. not part of its version name 
            # so we should only compare year and month, ignoring day of month
            } else {

               if ( $btime->year < $systime->year ) {
                  $newcolor = change_bg($failcolor, $bg) ;
                  $detail .= "|$bios_strdate| is earlier than |$sysbios_date|" ;

               } elsif ( $btime->year > $systime->year ) {
                  $newcolor = change_bg($warncolor, $bg) ;
                  $detail .= "|$bios_strdate| is later than |$sysbios_date|" ;

               # years match so check months
               } else {
                  if ( $btime->strftime("%m") lt $systime->strftime("%m") ) {
                     $newcolor = change_bg($failcolor, $bg) ;
                     $detail .= "|$bios_strdate| is earlier than |$sysbios_date|" ;

                  } elsif ( $btime->strftime("%m") gt $systime->strftime("%m") ) {
                     $newcolor = change_bg($warncolor, $bg) ;
                     $detail .= "|$bios_strdate| is later than |$sysbios_date|" ;
                  }
               }
            }
            $bg = $newcolor ;

         } else {
            $newcolor = change_bg($warncolor, $bg) ;
            $bg = $newcolor ;
            $detail .= "Cannot compare BIOS dates. " ;
         }  
      }

      $bios_complaint = "whether " . $bios_complaint if ($bg eq $warncolor) ;
      $complaint = complain($bg, $bios_complaint, $detail) ;

      $orow++ ;
      $otable->addRow( " $sysbios $complaint", " $sysbios_list{$sysbios}" ) ;
      $otable->setRowBGColor($orow, $bg) ;
      $otable->setCellStyle($orow, 1, $style) ;

      if ($bg ne $successcolor) {
         my $id = add_prob($bg, $who, "fw_bios", $dir) ;
         $otable->setCellAttr($orow, 1, $id) ;
      }

   } # for sysbios

   return "$bheader\n$otable" ;

} # build_btables()


#---------------------------------------------------------------------------
# Populate mitigation table
#
sub build_mtables() {
   my $dir          = shift ; # input
   my $who          = shift ; # input sponsor and submitter
   my $bios         = shift ; # input
   my $attempt_list = shift ; # input list of results that might contain mitigation notes
   my $mparams      = shift ; # input
   my $cparams      = shift ; # input

   my %mit_list     = %$mparams ;
   my %cpu_list     = %$cparams ;
   my $bg, my $complaint ;

   # initialize lists for results for which submitters tried to include mitigation notes
   my %incomplete_mit ;
   $attempt_list = "" if not defined $attempt_list ;
   foreach ( split (/$sep/, $attempt_list) ) {
      if ( $_ =~ /(\d+)\.html/ ) {
         my $rsfnum = $1 ;
         $incomplete_mit{$rsfnum} = join(" ", @cve_numbers) ;
      }
   }

   my $cheader = new HTML::Table( -style=>$boldbox ) ;
   $cheader->addRow( "CPU: " ) ;

   my @immunity_list ;
   my $ctable = new HTML::Table() ;
   my $crow = 0 ;
   for my $cpu ( sort keys %cpu_list ) {
      $crow++ ;
      $ctable->addRow( $cpu, "$cpu_list{$cpu}" ) ;
      push ( @immunity_list, immune_from_Meltdown($cpu) ) ; 
   }

   for my $msg ( uniq @immunity_list ) {
      $ctable->addRow( $msg ) ;
   }

   my $mheader = new HTML::Table( -style=>$boldbox ) ;
   $mheader->addRow( "Mitigation notes: " ) ;

   # list of mitigation notes
   my $mtable = new HTML::Table() ;
   $mtable = "" if ( !%mit_list ) ; # for early results, which did not require mitigation notes
   my $mrow = 0 ;
   for my $mnote (sort keys %mit_list) {

      for my $vstatus ( sort keys %{$mit_list{$mnote}} ) {
         my @mcomplaints ;
         my $detail = "" ;
         my $cve = my $answer = "" ;

         if ( $mnote eq $empty ) {
            push(@mcomplaints, complain($failcolor, $mitmsg{"MissingAllMit"}, $detail)) ;
            
         } else {
            @mcomplaints = check_mnote( $mnote, $vstatus, \$cve, \$answer ) ;
         }

         $complaint = "" ;
         foreach (@mcomplaints) {
           $complaint .= $_ ;
         }
         $bg = choose_bg($complaint) ;
         
         # shrink incomplete lists for each valid CVE note that was discovered
         if ($bg ne $failcolor) {

            foreach my $rsfnum (sort keys %incomplete_mit) {
               if ( $mit_list{$mnote}{$vstatus} =~ /$rsfnum\.html/ ) {
                  $incomplete_mit{$rsfnum} =~ s/$cve\s*// ;
   
                  # last one?
                  delete $incomplete_mit{$rsfnum} if $incomplete_mit{$rsfnum} !~ /CVE/;
               }
            }
         }

         $mrow++ ;
         $mtable->addRow( "$mnote $complaint", "$vstatus\: $mit_list{$mnote}{$vstatus}" ) ;
         $mtable->setCellStyle($mrow, 1, $mstyle) ;
         $mtable->setRowBGColor($mrow, $bg) ;
         
         if ($bg ne $successcolor) {
            my $id = add_prob($bg, $who, "mitigation", $dir) ;
            $mtable->setCellAttr($mrow, 1, $id) ;
         }
      }
   }

   # complain about incomplete lists that are not empty
   foreach my $cve (@cve_numbers) {
      my $cve_not_found = "" ;
      foreach my $rsfnum (sort keys %incomplete_mit) {
         
         if ( $incomplete_mit{$rsfnum} =~ /$cve/ ) {
            foreach my $result_link (split ( /$sep/, $attempt_list)) {
               $cve_not_found .= "$result_link " if $result_link =~ /$rsfnum/ ;
            }
         }
      }

      # some results are missing the mitigation note for this CVE
      # results with no attempt at mitigation notes are handled elsewhere; not repeated here
      my $detail = "" ;
      if ($cve_not_found ne "") {
         $complaint = complain($failcolor, $mitmsg{"MissingCVE"} . $cve, $detail) ;
         $bg = choose_bg($complaint) ;

         $mrow++ ;
         $mtable->addRow( "$complaint", "$cve_not_found" ) ;
         $mtable->setCellStyle($mrow, 1, $mstyle) ;
         $mtable->setRowBGColor($mrow, $bg) ;

         if ($bg ne $successcolor) {
            my $id = add_prob($bg, $who, "mitigation", $dir) ;
            $mtable->setCellAttr($mrow, 1, $id) ;
         }
      }
   }
 
   return "$cheader\n$ctable\n$mheader\n$mtable" ;

} # build_mtables()

#---------------------------------------------------------------------------
# Populate platform table
#
sub build_ftables() {
   my $dir          = shift ; # input
   my $who          = shift ; # input sponsor and submitter
   my $bios         = shift ; # input
   my $fparams      = shift ; # input

   my %flag_list    = %$fparams ; # list of platform flags files
   my $flags_complaint = "A vendor-specific platform flags file is required<br>if any BIOS settings are not at default" ;
   my $setting_complaint = "why these settings are not mentioned in the platform flags file" ;

   my $fheader = new HTML::Table( -style=>$boldbox ) ;
   $fheader->addRow( "Platform flags file:" ) ;

   # platform flags file, plus all platform notes
   my $ftable = new HTML::Table() ;
   my $frow = 0 ;

#  say $who if $debug ;
   for my $flags (sort keys %flag_list) {

      my @flags ; # in case there are ever multiple platform flags files?
      if ( $flags =~ /html \S.*html/ ) {
         @flags = split / /, $flags ;
      } else {
         push ( @flags, $flags ) ;
         (my $f = $flags) =~ s/\s*$// ; 
      }
      my $flink ;
      foreach my $f ( @ flags ) {
         if ( $report_custom or $f eq "None " ) {
            $flink .= $f ;
         } else {
            $flink .= "<a href=\"$flagurl/$f\">$f&nbsp;</a> " ;
         }
      }

      my $rsf_list ;
      my $rate = '1' ;
      my $speed = '0' ;

      my $ptable = new HTML::Table() ; # table of BIOS settings
      my $prow = 0 ;
      my $complaint = my $detail = "" ;
      my $bg = $successcolor;

               # save a global list of all BIOS settings we find
               # and append it to final report
               # so that we might notice if this tool searched for unimportant words,
               # in which case we should tweak this portion of the tool
#              push (@setting_list, $stmp) ;

      $frow++ ;
      $ftable->addRow( "$flink $complaint", $flag_list{$flags} ) ;
      $ftable->setCellStyle($frow, 1, $fstyle) ;
      $ftable->setCellBGColor($frow, 1, $bg) ;

   } # for flags pparams

   return "$fheader\n$ftable" ;

} # build_ftables()

#-----------------------------------------------------------------------------
# Parse a mitigation note and find out
#  - whether the submitter claims the result is mitigated for this CVE 
#  - whether or not the result is immune from this CVE
# and return any complaints about syntax or otherwise invalid answers.
#-----------------------------------------------------------------------------
sub check_mnote {
   my $mnote           = shift ; #  in: a mitigation note
   my $vstatus         = shift ; #  in: vulnerability status in sysinfo
   my $cve_ref         = shift ; # out: CVE identifier
   my $answer_ref      = shift ; # out: Yes/No/NA

   my @mcomplaints ; # return
   my $detail = "" ;
   $$cve_ref = "" ;
   
   # try really hard to match pieces of the note
   if ( $mnote =~ /^(.*):\s*(.*)($cve_format)(\s*)\((.*)\)(.*) / ) {
      $$answer_ref = $1 ;
      my $syntax1 = $2 ;
      $$cve_ref = $3 ;
      my $whitespace = $4 ;
      my $nickname = $5 ;
      my $syntax2 = $6 ;

      my $correct_format = 1 ;

      if ( $whitespace ne " " ) {
         push(@mcomplaints, complain($failcolor, $mitmsg{"Whitespace"}, "before CVE nickname" )) ;
      }

      if ( $$answer_ref !~ /^$valid_mit_answers/i ) {
         push(@mcomplaints, complain($failcolor, $mitmsg{"InvalidAnswer"}, $detail)) ;

      } elsif ( $$answer_ref =~ /no/i ) {
         push(@mcomplaints, complain($warncolor, $mitmsg{"No"}, $detail)) ;

      } elsif ( $$answer_ref =~ /na/i ) {
         if ( $vstatus =~ /not affected|immune/i ) {
            ; # do not complain about answer
         } else {
            push(@mcomplaints, complain($warncolor, $mitmsg{"NA"}, $detail)) ;
         }

      } else { # yes
         if ( $vstatus =~ /not affected|immune/i ) {
            push(@mcomplaints, complain($warncolor, $mitmsg{"Immune"}, $detail)) ;
         } elsif ( $vstatus =~ /vulnerable/i ) {
            push(@mcomplaints, complain($failcolor, $mitmsg{"Vulnerable"}, $detail)) ;
         }
      } 


      # this mitigation is not required by SPEC
      if ( ! defined $cve_nicknames{$$cve_ref} ) {
            push(@mcomplaints, complain($goodcolor, $mitmsg{"NotReq"}, "")) ;
      }

      if ( $syntax1 ne $valid_mit_syntax1 or $syntax2 ne $valid_mit_syntax2 ) {

            if ( $syntax1 ne $valid_mit_syntax1 ) {
               if ( igspace($syntax1, $valid_mit_syntax1) ) {
                  $detail .= "whitespace issue in $syntax1" ;
               } else {
                  $detail .= "does not contain |$valid_mit_syntax1|<br>" ;
               }
            }
            if ( $syntax2 ne $valid_mit_syntax2 ) {
               if ( igspace($syntax2, $valid_mit_syntax2) ) {
                  $detail .= "whitespace issue in $syntax2" ;
               } else {
                  $detail .= "does not contain |$valid_mit_syntax2|<br>" ;
               }
            }

            push(@mcomplaints, complain($failcolor, $mitmsg{"Components"}, $detail)) ;
            $detail = "" ;
      }

   # give up
   } else {
      push(@mcomplaints, complain($failcolor, $mitmsg{"SeeFormat"}, $detail)) ;
   }

   return @mcomplaints ;
} # sub check_mnote 


#-----------------------------------------------------------------------------
# Assign new background without overwriting higher priority color
#-----------------------------------------------------------------------------
sub change_bg(){
   my ($bg, $oldbg) = @_ ;

   $oldbg = "" if (! $oldbg) ;
   given ($bg) {
      when ($failcolor) {return $failcolor} ;
      when ($warncolor) {
         return $failcolor if ($oldbg eq $failcolor) ;
         return $warncolor ;
      }
      default { return $successcolor } ;
   }
}

#-----------------------------------------------------------------------------
# Compare BIOS version numbers. Get sysinfo BIOS date. Complain about mismatches.
#---------------------------------------------------------------------------
sub compare_bversions(){
   my $fver        = shift ; #     in: fw_bios BIOS version
   my $sysbios     = shift ; #     in: sysinfo BIOS 
   my $sdate_ref   = shift ; #    out: sysinfo BIOS date
   my $bg_ref      = shift ; # in/out: background color
   my $detail      = "" ; # out: whine if BIOS versions do not match


   # remove some punctuation
   $fver =~ s/\(|\)//g ; 
   $fver =~ s/\[|\]//g ; 
   $sysbios =~ s/\[|\]//g ; 
   $fver =~ s/-/ /g ;
   $sysbios =~ s/-/ /g ;

   # remove some grammar
   $fver =~ s/BIOS\s*//i ;
   $fver =~ s/\s+for\s+/ /i ;
   $sysbios =~ s/\s+for\s+/ /i ;

   # store dates and then filter them out
   # because all date comparisons occur in a different subroutine
   my $fdate = "" ;
   if ( $fver =~ /(\d\d\/\d\d\/20\d\d)/ ) {
      $fdate = $1 ;
      $fver =~ s/$fdate// ;
   }

   $$sdate_ref = "" ;
   if ( $sysbios =~ /(\d\d\/\d\d\/20\d\d)/ ) {
      $$sdate_ref = $1 ;
   } elsif ( $sysbios =~ /(20\d\d\/\d\d\/\d\d)/ ) {
      $$sdate_ref = $1 ;
   }

   # begin error checking
   $$bg_ref = $successcolor ;

   # compare dates if name of BIOS version contains a date
   if ( $fdate ne "" and $$sdate_ref ne "" ) {
      if ( $fdate ne $$sdate_ref ) {
# The check is done in build_btables()
#        $$bg_ref = $failcolor ;
#        $detail .=  "|$fdate| vs. |$$sdate_ref|\n" ;
      }
   }
   $sysbios =~ s/$$sdate_ref// ;

   # look at the remaining pieces, which are not dates
   my @f ; # pieces of fw_bios version 
   @f = split / /, $fver ;

   my @s ; # pieces of sysinfo version 
   foreach my $piece ( split / /, $sysbios ) {
      if ( $piece =~ /\d/ ) { # skip name of BIOS
         push (@s, $piece) ;
      }
   }

   # use arrays rather than hashes to avoid re-ordering remaining pieces
   # using copies of the arrays to compare elements,
   # discard matched pairs from original arrays
   # i.e. avoid splicing the same arrays we are looping through
   my @fcopy = @f ;
   while ( @fcopy ) {
      my $f = shift @fcopy ;

      if ( $sysbios =~ /$f/ ) {
         my @scopy = @s ;
         while ( @scopy ) {
            my $s = shift @scopy ;
            if ( $s =~ /$f/ ) {
               my $findex = first_index{$_ eq $f} @f ;
               my $sindex = first_index{$_ eq $s} @s ;
               splice @f, $findex, 1 ;
               splice @s, $sindex, 1 ;
               last ; 

            } else {
               ;
            }
         } # while
      }
   } # while

   # are we done?
   return $detail if scalar @s == 0 or scalar @f == 0 ;

   my $remainingf = join " ", @f ;
   my $remainings = join " ", @s ;
   $detail .= "|$remainingf| is not in $remainings<br>" ;

   $$bg_ref = $warncolor if $$bg_ref eq $successcolor ;

   return $detail ;
} # compare_bversions

#---------------------------------------------------------------------------
# Recognize whether a CPU is immune from Meltdown (hardware mitigation)
#
sub immune_from_Meltdown() {
   my $cpu                 = shift ; #  in: a CPU
   my $immunity = $empty ;           # out: return an immunity statement if CPU is immune

   if ( $cpu =~ /amd.*epyc/i ) {
      $immunity = 'AMD EPYC' ;

   } elsif ( $cpu =~ /intel.*xeon/i and $cpu =~ / \d2\d\d/ ) {
      $immunity = 'Intel "Cascade Lake"' ;

   } elsif ( $cpu =~ /intel.*xeon/i and $cpu =~ / \d3\d\d/ ) {
      $immunity = 'Intel "Cooper Lake"' ;

   } elsif ( $cpu =~ /intel.*core/i and $cpu =~ /9(1|5|7)00\S*E/ ) {
      $immunity = 'Intel "Coffee Refresh"' ;

   } elsif ( $cpu =~ /intel.*xeon/i and $cpu =~ /E-22\d8/ ) {
      $immunity = '8-core Intel Xeon E-2200 series' ;
   }

   $immunity .= ' processors are immune from Meltdown' if $immunity ne $empty ;
   return $immunity ;

} # sub immune_from_Meltdown 


#-------------------------------------------------------------------
# Read the result's .rsf (raw) file, and tuck away data from some fields 
# editable by the submitter. 
#
sub read_rsf {
   my $rsf                 = shift ; #  in:  file to read
   my $cpu_ref             = shift ; # out: contents of hw_cpu
   my $fw_bios_ref         = shift ; # out: contents of fw_bios
   my $flags_ref           = shift ; # out: filename of platform flags file
   my $mnotes_ref          = shift ; # out: list of mitigation notes
   my $who_ref             = shift ; # out: sponsor[sep]submitter
   my $sysinfo_ref         = shift ; # out: sysinfo lines


   my $sponsor = my $submitter = "" ;
   my @compnotes ;
   my $runmode = 0 ;
   my $rate = 0 ;
   my $mit_note ;

   $$cpu_ref = "" ;
   $$fw_bios_ref = "" ;
   $$flags_ref = "" ;
   $$mnotes_ref = "" ;
   $$sysinfo_ref = "" ;

   my $FILE ;
   open ($FILE, "<", $rsf) or say "Could not open $rsf";
   while (my $rline = <$FILE>) {
      chomp $rline;
      last if $rline =~ /$suite\.results/ ;
 
      if ($rline =~ /fw_bios.*:\s*(.*)/) {
         $$fw_bios_ref .= "$1 ";
#        say "$$fw_bios_ref" if $debug ;
         next;

      } elsif ($rline =~ /hw_cpu_name.*:\s*(.*)/) {
         $$cpu_ref .= "$1 ";
         $$cpu_ref =~ s/\s*$//;
#        say "$$cpu_ref" if $debug ;
         next ;

      # end of a mitigation note
      } elsif ( $rline =~ /spec.$suite.(notes\S+):\s*(.*$mit_search_string2.*)/i ) {
         $mit_note = $2 ;
         $mit_note =~ s/^\s+//;         # no trailing or leading blanks
         $mit_note =~ s/\s+$//;
         $$mnotes_ref .= "$mit_note " . $sep ;
         next ;

      # mitigation note might use two lines
      } elsif ( $rline =~ /spec.$suite.(notes\S+):\s*(.*$mit_search_string1.*)/i ) {
         $mit_note = $2 ;
         $mit_note =~ s/^\s+//;         # no trailing or leading blanks
         $mit_note =~ s/\s+$//;
         $$mnotes_ref .= "$mit_note " ;
         next ;

      # platform flags file
      } elsif ( $rline =~ /flagsurl.*:.*flags\/(.*xml)/ ) {
         (my $html = $1) =~ s/xml$/html/ ;

         if ( $html =~ /platform/i ) {
            $$flags_ref .= "$html " ;

         # not all filenames contain "platform" 
         # but try to skip compiler flags files
         } elsif (  $html =~ /ic\d\d.*linux/ or $html =~ /gcc/i or $html =~ /aocc/i 
                 or $html =~ /official/i or $html =~ /developer/i ) {
            next ;

         } else {
            $$flags_ref .= "$html " ;
         }

      } elsif ($rline =~ /sponsor[^:]*:\s*(.*)/) {
         $sponsor .= "$1 ";
         $sponsor =~ s/\s*$//;
         next;

      } elsif ($rline =~ m{Submitted_by:\s*(.*)}) {
         $submitter = $1;
         next;
     
      } elsif ($rline =~ m{compnotes_sysinfo(\d+):\s*(.*)}) {
         $compnotes[$1] = $2 ;

      } elsif ($rline =~ /$suite\.runmode: (\S+)/ ) {
         $runmode = $1 ;
         $rate  = $runmode =~ /rate/ ? 1 : 0 ;

      }
  
   } # while

   close $FILE ;
   $$fw_bios_ref =~ s/,//;
   $$fw_bios_ref =~ s/\h+/ /g; # canonicalize horizontal whitespace
   $$fw_bios_ref = "undefined" if $$fw_bios_ref eq "" ;
   $$fw_bios_ref = "None" if $suite eq "cpu2006" ;

   $$flags_ref  = "None" if ($$flags_ref eq "") ;
#  say "platform flags file: $$flags_ref" if $debug ;

   $$mnotes_ref =~ s/\h+/ /g;
   $$mnotes_ref = $empty if ($$mnotes_ref eq "") ;


   $$sysinfo_ref = decode_decompress(join('', @compnotes)) ;
   $$sysinfo_ref =~ s/notes_plat_sysinfo_(\d+)://g ;

   $$who_ref =  get_who($sponsor, $submitter) ;

   return $rate  ;
} # sub read_rsf

#-------------------------------------------------------------------
# Tuck away BIOS info from the result's Sysinfo data
#
sub read_sysinfo {
   my $sysinfo       = shift ; #  in: sysinfo data
   my $sysbios_ref   = shift ; # out: BIOS seen by sysinfo
   my $vstatus_ref   = shift ; # out: Kernel self reported vulnerability status for each CVE

   my @sysinfo =  split /\n/, $sysinfo ;
   my $some_sysinfo_found = 0;
   my $missing_section   = "[Did not find sysinfo section]";
   my $missing_field     = "[Found sysinfo, but did not find runtime BIOS version]";
   my $bios_ver = $missing_field ;

   foreach (@sysinfo) { 
      $some_sysinfo_found = 1;

      # vulnerability status lines
      if ( /($cve_format)[^:]*\:\s*(.*\S)/ ) {
         my $cve = $1 ;
         $vstatus_ref->{$cve} = $2 ;

      # look for BIOS, but ignore the line that says 'and the "DMTF SMBIOS" standard'
      } elsif (/ BIOS:?\s*(\S+.*)/ and not /standard/) {
         $bios_ver = $1 ;

      # is the BIOS date on the following line?
      } elsif ( /(.*20\d\d.*)/ ) {
         my $dateline = $1 ;
         if ( $bios_ver ne $missing_field and $bios_ver !~ /(\/|\s)20\d\d/ ) {
            $bios_ver .= " $1" ;
         }
      }

   } # foreach

   if (! $some_sysinfo_found) {
      $bios_ver = $missing_section ;
   }

   # normalize white space
   chomp $bios_ver ;
   $bios_ver =~ s/,//;
   $bios_ver =~ s/\h+/ /g;
   $$sysbios_ref = $bios_ver ;

} # sub read_sysinfo

#-------------------------------------------------------------------
# Compare two strings ignoring all whitespace
#
sub igspace {
   my ($s1, $s2) = @_ ;
   (my $temp1 = $s1) =~ s/\s+//g ;
   (my $temp2 = $s2) =~ s/\s+//g ;

   $temp1 eq $temp2 ;
}

#-------------------------------------------------------------------
# Write the report header
#
sub write_preface_bios {

   my $title = "Run-time BIOS report" ;
   my $more_style = <<EOF;
.snugbot      { margin-bottom:0.1em; }
howtoread > h3 { display: inline-block; }
EOF

   my $fw_bios_def = 'https://www.spec.org/' . $suite. '/Docs/config.html#fw_bios' ;
   my $fw_bios_ex = 'https://pro.spec.org/private/wiki/bin/view/CPU/BIOSexamples' ;

   my $cve_list = "" ;
   foreach my $cve (sort keys %cve_nicknames) {
      $cve_list .= '<li style="margin-top:.2em; font-family:courier new; font-size: 8.5pt">' ;
      $cve_list .= "Yes/No/NA: The test sponsor attests, as of date of publication, that $cve $cve_nicknames{$cve} is mitigated in the system as tested and documented. " ;
      $cve_list .= '</li>' ;
   }

   my $html_top = <<EOF;
    <style type="text/css">
    .flavor {margin-left:5em;font-size:90%;}
    </style>
EOF

   # purpose, explain the concepts and limitations
   $html_top    .= <<EOF;
   
<table>
<tr>

   <td>
   <h3 style="margin-top:.1em;">Purpose of this report</h3>

   <p class="l1">This page shows the run-time BIOS version and mitigation notes for each result, as well as the platform flags file associated with the result (if any).</p>

   <howtoread>
      <h3>How to read this report</h3>
      <span>&nbsp;Submissions sorted by directory / submitter / BIOS version or platform flags file</span>
   </howtoread>
   <p>See definition of <b>fw_bios</b> at <a href="https://www.spec.org/cpu2017/Docs/config.html#fw_bios">https://www.spec.org/cpu2017/Docs/config.html#fw_bios</a>. See valid formats and specific examples at  <a href="$fw_bios_ex">$fw_bios_ex</a>.
   <ol class="l1">
      <li>Do the BIOS version and date match the BIOS info found by sysinfo? Sometimes reviewers may need to check the release date manually via vendor (e.g. IBM) support documentation.</li>
      <br>
      <li>Using this format, within General Notes, did the result document whether each of these security concerns is mitigated or not?
         <ul style="margin-top:.2em;">$cve_list</ul>
      </li>
      <br>
      <li>Given the BIOS Date, do the mitigation statements seem plausible? Please check manually.</li>
         <ol type="a">
            <li>Earliest Accepted results, through 2018 Jan, did not require any mitigation notes.</li>
            <li>Required statements with correct syntax are not highlighted.</li>
            <li>Missing statements or those with errors are highlighted in red.</li>
            <li>Some statements that claim NA are highlighted in yellow (warning) and probably need further discussion . The tool avoids highlighting others because it recognizes when the Kernel self-reports that the SUT is "not affected" by a CVE. It also knows that particular CPUs are NA for Meltdown:
            <ul>
               <li>AMD EPYC
               <li>Intel Xeon "Cascade Lake" "Cooper Lake" 
               <li>Intel Core "Coffee Refresh" 
               <li>8-core Intel Xeon E-2200 series
            </ul>
            <li>for your convenience, CPUs are listed just above the mitigation statements.</li>
            <li>Extra mitigation statements with correct syntax are highlighted in green. This tool does not attempt to verify whether their CVE numbers or nicknames are accurate.</li>
         </ol>
      <br>
      <li>Are mitigation statements consistent with sw_avail? Please check manually.</li>
      <br>
      <li>Names of platform flags files are shown, but BIOS settings are now listed in the Runtime notes report.</li>
   </ol>

   <h3>Unpublished vs. published</h3>

</tr>
</table>
EOF
#     <li>BIOS settings are listed with associated results. ' ' means no BIOS settings are mentioned.
#        <ol type="a">
#           <li>Do results with BIOS settings include a platform flags file?</li>
#           <li>If yes, please manually check that each note is fully described?</li> 
#           <li>For each submitter's set of results, are settings spelled consistently?</li> 
#        </ol>
#     </li>

#  Move this into $html_top if applicable
#  <h3>Limitations</h3>
#  <ol class="l1">
#  </ol>

   $html_top .= available_reports(\%bios_file) ;

   return( init_html_vars($title, $more_style, $html_top) ) ;

} #  sub write_preface_bios
