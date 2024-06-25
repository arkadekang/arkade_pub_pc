#!/usr/bin/perl
#
# crosscompile.pl
# Print into about sw_other and cross-compiles
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Authors: J. Henning, Julie Reilly
#
# $Id: crosscompile.pl 6548 2020-11-10 16:33:32Z CloyceS $
#
# J.Henning
# mostly re-written 30 Mar 2012 to account for new rule 4.2.7
# JL Reilly 2016 Jun ignore more non-compile lines
#                    add debug command line option (not just a variable)
#                    add usage
# JL Reilly      Sep look at env variable $SUITE
#                    check for additional types of sw_other problems
#                    umask; move output
# JL Reilly      Dec also report on ReReview
# JL Reilly 2017 Jan use one or two words of sponsor name
# JL Reilly      Mar fixed bug reading sponsor name
#                Oct recognize jemalloc in sw_other
#           2018 Jan sort results by int/fp for each sw_other
#                Feb Mostly re-written to use Review_util and HTML::Table
#                    split Pending by date
#                    warn when cross-compile notes are missing
#                Apr released (replacing previous crosscompile tool)
#                May tweak parsing of sponsor names
#                Jun tweak parsing of notes
#                    highlight "avilable"
#                    check .txt to see whether jemalloc was actually used
#                Jul stop sorting published results by subdirectory
#                    don't complain about location of jemalloc notes in published results
#                    rsf_to_link() -> result_link()
#                    let module handle more of preface
#                Aug renamed a style
#                    sw_other should not say "see general notes"
#                Nov rewrote sw_other/jnotes error checking 
#                    adjusted preface 
#                Dec fixed sw_other/jnotes error checking bugs
#           2019 Feb use two-word sponsor name for Intel Corporation
#                Apr rewrote sw_other/jnotes error checking 
#                    redesigned sw_other/jnotes tables
#                    link to multiple sw_other/jnote errors in Table of Problems 
#                    debugged check for notes about jemalloc compile options
#                May remove a space from trademark
#                Aug tweaked sw_other complaints
#                Oct sw_other should not mention OS info
#                Dec jemalloc might be built with AOCC
#                    source for AOCC is not a cross-compiler note
#                    dirs_to_search is in Review_util.pm
#           2020 Feb sw_other field might not be numbered
#                    SmartHeap != None 
#                Mar improve parsing of sw_other
#                    complain about a particular nonexistent Intel CPUs in cross-compile notes
#                Apr complain if jemalloc notes mention a specific tar ball download that does not match sw_other
#                May added -i option, for which output is STDOUT
#                    use available_reports() and common_usage()
#                    suppress specperl warnings about experimental given/when and smartmatch
#                    read flags from .rsf instead of from .txt
#                    sort by dir last, or nearly last
#                Sep use get_who() ;
#                    change warning message for unrecognized software listed in sw_other 
#                Oct more modular
#                    notes_comp about IC -v issue no longer appear as part of cross-compile notes
#                    show General notes about binutils
#
use strict;
use warnings;
use IO::Handle;
use v5.10 ; # say, switch=>given/when
use Time::Piece ;
use List::MoreUtils ;
use Env qw(SUITE SPEC) ;

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

sub build_btables ;
sub build_ctables ;
sub build_etables ;
sub build_jtables ;
sub build_swtables ;
sub change_bg ;
sub sort_notes ;
sub seen_all_required_tokens ;
sub read_rsf ;
sub used_jemalloc ;
sub write_preface_cross  ;
umask 0002 ;

#----------- globals -----------
our $suite = $SUITE ? $SUITE : "cpu2017" ;
my $blank = "' '" ;

my $style = 'text-align:left;white-space:nowrap;' ;
my $ustyle = "$style;font-weight:bold;text-decoration: underline;" ;
my $jstyle = 'vertical-align:top;border:thin solid gray;';
my $boldstyle = "font-weight:bold;" ;
my $boxstyle = "$style;vertical-align:top;border:thin solid gray;" ;
my $boldbox = "$boxstyle;font-weight:bold;" ;

my $jemalloc_search_string  = '(jemalloc)';
my $compile_search_string   = '(compiler|compiled|cross-compile|cross compile|binutils)';
my $estimate_search_string  = '(estimate)';
my @compile_required_tokens = qw( system with (chip|CPU) memory using );
my $obviously_neither  = '(Submitted_by|equivalen|runspec|huge|page cache clear|attests|mitigated|sysinfo\.rev|SPEC is set to|LD_LIBRARY_PATH|KMP|NUM_THREADS|AOCC)';
my $wrong_notes = '(notes_os|notes_plat|notes_submit|submit)' ;

# global data created as we read files, consumed by reporting routines
# 'who' is a composite key: sponsor / submitter, as in Acme / joe@acme.com
my @report ;

use Text::Wrap qw($columns wrap);
$columns = 132;

init_review_tools;
$SIG{__DIE__}      = \&file_clean_at_fail;

my $outdir = "$outroot" ;
my %cross_file = (
   "unpub" => "$outdir/cross.unpub.html",
   "pub"   => "$outdir/cross.pub.html"
) ;


common_usage ; # parse command line ; show usage if necessary

my $outfile = "STDOUT" ;
if ( ! $report_custom ) { # normal review operation, after submission

   if ($report_accepted) {
      $outfile         = $cross_file{"pub"} ;
   } else {
      $outfile         = $cross_file{"unpub"} ;
   }
}
my $fh = IO::Handle->new();
open_outfile $fh, $outfile ;

say $fh write_preface_cross;

push (@report, "<html><body>");

my %combo_cw ; # compile note and submitter combos
my %combo_ew ; # estimate note and submitter combos
my %combo_sw ; # sw_other and submitter combos
my %combo_jw ; # jemalloc note and submitter combos
my %combo_bw ; # binutils note and submitter combos

# sort by directory when gathering data
for my $dir ( dirs_to_report($outfile) ) {
   chomp $dir;
   say "$dir" if ($debug) ;

   # find and read result files
   my @files = get_result_files($dir, $report_accepted, "rsf") ;
   next if ! @files;

   for my $rsf (sort @files) {
      my $ccnotes = my $jnotes = my $enotes = my $bnotes = my $sw_other = my $who = "" ;
      my %notes ;
      my $fp ;
      read_rsf($rsf, \$fp, \$sw_other, \$who, \%notes) ;
      sort_notes(\%notes, \$ccnotes, \$jnotes, \$enotes, \$bnotes) ;

      my $rlink = result_link($dir,$rsf) ;
      $combo_cw{$ccnotes}{$who}{$dir} .= "$rlink " ;

      $combo_ew{$who}{$dir} .= "$rlink " if $enotes ne "" ;

      $combo_sw{$sw_other}{$who}{$dir}{"$fp"} .= "$rlink " ;
      $combo_jw{$sw_other}{$jnotes}{$who}{$dir}{"$fp"} .= "$rlink " ;
      $combo_bw{$sw_other}{$bnotes}{$who}{$dir}{"$fp"} .= "$rlink " ;
   }
}

my $etable = build_etables( \%combo_ew ) ;
push (@report, $etable) if $etable =~ /$failcolor/ ;

my @ctables ; # tables of compiler notes
push (@ctables, "<h3>Cross-compile notes</h3>\n" ) ;
push (@ctables, build_ctables( \%combo_cw ) ) ;

foreach (@ctables) {
   push (@report, $_) ;
}

# tables of sw_other and jemalloc notes
my $probno = 0 ;
my @swtables = build_swtables( \%combo_sw, \%combo_jw, \%combo_bw ) ;

foreach (@swtables) {
   push (@report, $_) ;
}

push (@report, "$html_finish") ;

say $fh make_top ;

foreach (@report) {
   say $fh $_ ;
}

close ($fh) ;
exit_success;

#---------------------------------------------------------------------------
# Populate binutils note table
#
sub build_btables {
   my $sw_other = shift ; #  in: sw_other
   my $bparams  = shift ; #  
   my %bcombo = %$bparams ; 

   my @btables ; # returned tables

   my $fp = 1 ;
   my $int = $fp - 1 ;

   my %bmsg ;
   $bmsg{"MissingBnotes"} = 'Missing General notes about binutils.'  ;
   $bmsg{"NoBinutils"} = 'Why do General notes mention binutils?' ;
   foreach my $bnotes ( sort keys %{$bcombo{$sw_other}} ) {
      my %bwho_list = %{$bcombo{$sw_other}{$bnotes}} ;
      my $bcomplaint = "" ;
      my @bcomplaints ;
      my $detail = "" ;
      my $show_bnotes = 0 ;

      # check for errors:
      # if binutils was used, both sw_other and General notes should describe that;
      # otherwise neither should mention binutils
      # and check for a few other details commented on below

      # binutils was used
      if ( $sw_other =~ /binutils/ ) {
         $show_bnotes = 1 ;

         # binutils notes are missing
         if ( $bnotes !~ /binutils/ ) {
            push ( @bcomplaints, complain($failcolor, $bmsg{"MissingBnotes"}, "") ) ;
         }

      # binutils not used but notes mention binutils
      } elsif ( $bnotes =~ /binutils/ ) {
         $show_bnotes = 1 ;
         push ( @bcomplaints, complain($failcolor, $bmsg{"NoBinutils"}, "") ) ;
      }

      next if ! $show_bnotes ;

      my $complaint = "" ;
      foreach (@bcomplaints) {
         $complaint .= $_ ;
      }
      my $bbg = choose_bg($complaint) ;

      my $bheader = new HTML::Table( -style=>$boldbox) ;
      $bheader->addRow("General notes about binutils:<br> $bnotes $complaint") ;
      $bheader->setRowBGColor(1, $bbg);

      my $btable = new HTML::Table ;
      my $brow = 0 ;

      my $id ;
      for my $who (sort keys %bwho_list) {
         (my $sponsor, my $submitter) = split $sep, $who;

         my $rtable = new HTML::Table ;
         my $rrow = 0 ;
         foreach my $dir ( sort keys %{$bwho_list{$who}} ) {
            my $rlinks = "" ;
            $rlinks .= "int $bwho_list{$who}{$dir}{$int}" if defined $bwho_list{$who}{$dir}{$int} ;
            $rlinks .= " fp $bwho_list{$who}{$dir}{$fp}"  if defined $bwho_list{$who}{$dir}{$fp} ;
            $rrow++ ;
            $rtable->addRow( "$dir\/", $rlinks ) ;

            if ( $bbg ne $successcolor ) {
               $rtable->setRowBGColor($rrow, $bbg)  ;
               $probno++ ;
               my $id = add_prob($bbg, $who, "binutils_notes_$probno", $dir) ;
               $rtable->setRowAttr($rrow, $id) ;
            }
         }

         $brow++ ;
         $btable->addRow( $sponsor,  $submitter, $rtable ) ;
         $btable->setRowBGColor($brow, $bbg) ;
      }

      push ( @btables, "$bheader\n$btable" ) ;
   } # foreach bnotes

   return @btables ;
} # sub build_btables

#---------------------------------------------------------------------------
# Populate compiler note tables
#
sub build_ctables() {
   my $cparams    = shift ; # input

   my %combo_cw = %$cparams ;
   my @tables ;

   my %errmsg ;
   $errmsg{"badCPU"} = "non-existent Intel CPU" ;
   $errmsg{"NoNotes"} = "compile notes. Were binaries compiled on the SUT?" ;
   $errmsg{"MissingTokens"}      = "If this is a cross-compile note, it appears to be missing " .
                                "some required components (see list at top of page)";

   # sort by cross-compile note
   foreach my $ccnotes (sort keys %combo_cw) {

      my %who_list = %{$combo_cw{$ccnotes}} ;

      # check for errors (where practical)
      my $err = "" ; 
      my $bg = $successcolor ;
      my $ccomplaint = "" ;
      my $detail = "" ;
      my $newcolor ;
   
      if ($ccnotes =~ /None/) {
         $newcolor = change_bg($warncolor, $bg) ;
         $bg = $newcolor ;
         $ccomplaint = $errmsg{"NoNotes"} ;
   
      } elsif (!seen_all_required_tokens($ccnotes)) {
         $newcolor = change_bg($warncolor, $bg) ;
         $bg = $newcolor ;
         $ccomplaint = $errmsg{"MissingTokens"} ;

      # sometimes Intel-based results mention a non-existent Intel CPU in the compile notes
      } elsif ( $ccnotes =~ /i9\-(799X)/ ) { 
         $newcolor = change_bg($failcolor, $bg) ;
         $bg = $newcolor ;
         $ccomplaint = $errmsg{"badCPU"} ;
      }
   
      my $complaint = complain($bg, $ccomplaint, $detail) ;
   
      my $cheader = new HTML::Table( -style=>$boldbox ) ;
      $cheader->addRow( "$ccnotes $complaint" ) ;
      $cheader->setRowBGColor(1, $bg) ;
   
      my $ctable = new HTML::Table() ;
      my $crow = 0 ;
   
      for my $who (sort keys %who_list) {
         (my $sponsor, my $submitter) = split $sep, $who;

         foreach my $dir ( sort keys %{$who_list{$who}} ) {
            $crow++ ;
            $ctable->addRow( " $sponsor", " $submitter&nbsp;&nbsp;&nbsp; 
                                            $dir\/ $who_list{$who}{$dir}" ) ;
            $ctable->setRowBGColor($crow, $bg) ;

            if ($bg ne  $successcolor) {
               my $id = add_prob($bg, $who, "Cross-compile", $dir) ;
               $ctable->setCellAttr($crow, 1, $id) ;
            }
         }
      }
      
      push( @tables, "$cheader\n$ctable<br>" ) ;
   }

   return (@tables) ;
} # build_ctables

#---------------------------------------------------------------------------
# Populate jemalloc note table
#
sub build_jtables {
   my $sw_other = shift ; #  in: sw_other
   my $jparams  = shift ; #  
   my %jcombo = %$jparams ; 

   my @jtables ; # returned tables

   my $sw = my $flag_detail = "" ;
   ($sw, $flag_detail) = split $sep, $sw_other ;

   my $fp = 1 ;
   my $int = $fp - 1 ;

   my %jmsg ;
   $jmsg{"MissingJnotes"} = 'Missing General notes about jemalloc.'  ;
   $jmsg{"MissingJnotes"} .= '<br>Please specify jemalloc compile options and location source.' ;
   $jmsg{"MissingComp"} .= 'Please specify jemalloc compile options.' ;
   $jmsg{"MissingLocation"} .= 'Please specify jemalloc location source.' ;
   $jmsg{"gnNoJemallocFlag"} = 'Why do General notes mention jemalloc?' ;
   $jmsg{"Semicolon"} = 'Please remove the semicolon ";" from the URL?' ;
   $jmsg{"AOCC"} = 'Please move AOCC statements above jemalloc notes' ;
   $jmsg{"VersionMismatch"} = 'jemalloc version in sw_other does not match notes' ;

      foreach my $jnotes ( sort keys %{$jcombo{$sw_other}} ) {
         my %jwho_list = %{$jcombo{$sw_other}{$jnotes}} ;
         my $jcomplaint = "" ;
         my @jcomplaints ;
         my $detail = "" ;

         # check for errors:
         # if jemalloc was used, both sw_other and General notes should describe that;
         # otherwise neither should mention jemalloc
         # and check for a few other details commented on below

         # jmalloc was used
         if ( $flag_detail =~ /flags include/ ) {
 
            # jemalloc notes are missing
            if ( $jnotes !~ /jemalloc/ and $jnotes !~ /sw_other/ ) {
               push ( @jcomplaints, complain($failcolor, $jmsg{"MissingJnotes"}, $flag_detail) ) ;

            # are details about jemalloc correctly described?
            } else {
               # are details about jemalloc described? 
               if ( $jnotes !~ /built/ and $jnotes !~ /compil|default/i ) {
                  push ( @jcomplaints, complain($failcolor, $jmsg{"MissingComp"}, "") ) ;
               }
               if ( $jnotes !~ /(jemalloc\.net|github\.com)/ ) {
                  push ( @jcomplaints, complain($failcolor, $jmsg{"MissingLocation"}, "") ) ;
               }

               # broken URL ?
               if ($jnotes =~ /releases;|net;/ or $sw_other =~ /releases;|net;/ ) {
                  push ( @jcomplaints, complain($failcolor, $jmsg{"Semicolon"}, $detail ) ) ;
               }

               # includes comp notes ?
               if ($jnotes =~ /AOCC/ and $jnotes =~ /amd\.com/ ) {
                  push ( @jcomplaints, complain($failcolor, $jmsg{"AOCC"}, "" ) ) ;
               }

               # version matches version claimed in sw_other ?
               my $jversion = "undefined" ;
               if (  $sw =~ /(\d[\d\.]*)/ ) {
                  $jversion = $1 ;
               }
               if ( $jnotes =~ /\.tar\./ and $jnotes !~ /$jversion/ ) {
                  my $detail = "|$jversion| is not in the the tar ball" ;
                  push ( @jcomplaints, complain($failcolor, $jmsg{"VersionMismatch"}, $detail) ) ;
               }
            }

         # jemalloc was not used notes but mention jemalloc
         } elsif ($jnotes =~ /jemalloc/ ) {
            push ( @jcomplaints, complain($failcolor, $jmsg{"gnNoJemallocFlag"}, $flag_detail) ) ;
         }
   

         my $complaint = "" ;
         foreach (@jcomplaints) {
            $complaint .= $_ ;
         }
         my $jbg = choose_bg($complaint) ;

         my $jheader =  new HTML::Table( -style=>$boldbox ) ;
         $jheader->addRow( "General notes about jemalloc:<br> $jnotes $complaint" ) ;
         $jheader->setRowBGColor(1, $jbg) ;

         my $jtable = new HTML::Table() ;
         my $jrow = 0 ;

         my $id ;
         for my $who (sort keys %jwho_list) {
            (my $sponsor, my $submitter) = split $sep, $who;

            my $rtable = new HTML::Table ;
            my $rrow = 0 ;
            foreach my $dir ( sort keys %{$jwho_list{$who}} ) {
               my $rlinks = "" ;
               $rlinks .= "int $jwho_list{$who}{$dir}{$int}" if defined $jwho_list{$who}{$dir}{$int} ;
               $rlinks .= " fp $jwho_list{$who}{$dir}{$fp}"  if defined $jwho_list{$who}{$dir}{$fp} ;
               $rrow++ ;
               $rtable->addRow( "$dir\/", $rlinks ) ;

               if ( $jbg ne $successcolor ) {
                  $rtable->setRowBGColor($rrow, $jbg)  ;
                  $probno++ ;
                  my $id = add_prob($jbg, $who, "jemalloc_notes_$probno", $dir) ;
                  $rtable->setRowAttr($rrow, $id) ;
               }
            }

            $jrow++ ;
            $jtable->addRow( $sponsor,  $submitter, $rtable ) ;
            $jtable->setRowBGColor($jrow, $jbg) ;
         }

         push ( @jtables, "$jheader\n$jtable" ) ;
      } # foreach jnotes

   return @jtables ;
} # sub build_jtables 

#---------------------------------------------------------------------------
# Populate sw_other table
#
sub build_swtables {
   my $sparams = shift ; # input
   my $jparams = shift ; # input
   my $bparams = shift ; # input


   my %scombo = %$sparams ;
   my %jcombo = %$jparams ;
   my %bcombo = %$bparams ;

   my %swmsg ;
   $swmsg{"sortaNone"} = '<br>Did you mean "None" ? ' ;
   $swmsg{"MoveJnotes"} = 'Move most jemalloc details from sw_other to notes_jemalloc_NNN or notes_NNN'  ;
   $swmsg{"MissingJemalloc"} = '<br>Is sw_other missing jemalloc?' ;
   $swmsg{"swNoJemallocFlag"} = '<br>Why does sw_other mention jemalloc?' ;
   $swmsg{"MissingVersionJ"} = 'Missing jemalloc version number.'  ;
   $swmsg{"MissingVersionBU"} = 'Missing binutils version number.'  ;
   $swmsg{"ExcludeOS"} = 'sw_other should not include the OS' ;
   $swmsg{"ExtraChars"} = 'sw_other contains extra characters.' ;
   $swmsg{"Unknown"} = 'Software not used previously. Discuss within subcommittee?' ;
   my @swtables ;
   my $fp = 1 ;
   my $int = $fp - 1 ;
   
   foreach my $sw_other (sort keys %scombo) {
      my %swho_list = %{$scombo{$sw_other}} ;

      my $sw = my $complaint = my $flag_detail = "" ;
      my @swcomplaints ;
      my $sbg = $successcolor ;

      ($sw, $flag_detail) = split $sep, $sw_other ;

      # jmalloc was used
      if ( $flag_detail =~ /flags include/ ) {

         # sw_other does not say so
         if ( $sw !~ /jemalloc/i ) {
            $complaint = $swmsg{"MissingJemalloc"} ;
            push ( @swcomplaints, complain($failcolor, $complaint, $flag_detail)  ) ;

         # is sw_other correctly formatted?
         } else {
            if ($sw !~ /version\s*\d/i and $sw !~ /v\d/i) {
               $complaint = $swmsg{"MissingVersionJ"} ;
               push ( @swcomplaints, complain($failcolor, $complaint, "")  ) ;
            }
            if ($sw =~ /(built|jemalloc\.net|github\.com)/ ) {
               push ( @swcomplaints, complain($failcolor, $swmsg{"MoveJnotes"}, "") ) ;
            }
         }

      # jemalloc was not used but sw_other claims it was
      } elsif ( $sw =~ /jemalloc/ ) {
         $complaint = $swmsg{"swNoJemallocFlag"} ;
         push ( @swcomplaints, complain($failcolor, $complaint, $flag_detail)  ) ;

      # jemalloc was not used
      } else {
         # blank value is not allowed
         if ($sw =~ $blank) {
            $complaint = $swmsg{"sortaNone"} ;
            push ( @swcomplaints, complain($failcolor, $complaint, "") ) ;
         } elsif ($sw =~ /None\s*\S+/i) {
            $complaint = $swmsg{"ExtraChars"} ;
            push ( @swcomplaints, complain($failcolor, $complaint, "") ) ;

         } elsif ($sw !~ /None/i 
            and $sw !~ /SmartHeap|hpe foundation soft|fdprpro|binutils/i ) {

            $complaint = $swmsg{"Unknown"} ;
            push ( @swcomplaints, complain($warncolor, $complaint, "") ) ;
         }
      }

      # binutils
      if ( $sw =~ /binutils/ ) {
         if ( $sw !~ /(\s*|version|v)\d/i ) {
            $complaint = $swmsg{"MissingVersionBU"} ;
            push ( @swcomplaints, complain($failcolor, $complaint, "")  ) ;
         }
      }

      # sw_other should not include OS info
      if ( $sw =~ /ubuntu|suse|red hat/i ) {
         $complaint = $swmsg{"ExcludeOS"} ;
         push ( @swcomplaints, complain($failcolor, $complaint, "" ) ) ;
      }

      # unnecessary phrase ?
      if ( $sw =~ /v\S*\d(.*see general.*)/i) {
         $complaint = "why " . $swmsg{"ExtraChars"} ;
         my $sdetail = 'Please remove "' . $1 . '" from sw_other?' ;
         push ( @swcomplaints, complain($warncolor, $complaint, $sdetail ) ) ;
      }

      my $scomplaint = "" ;
      foreach (@swcomplaints) {
         $scomplaint .= "$_<br>" ;
      }

      my $sheader =  new HTML::Table( -style=>"$boldbox;background-color:$sbg" ) ;
      $sheader->addRow( "sw_other: $sw" ) ;
      push ( @swtables, "<br><br>$sheader" ) ;

      # only list results directly under sw_other if there is a problem with that field
      $sbg = choose_bg($scomplaint) ;
      if ( $sbg ne $successcolor ) {
         my $wcol = new HTML::Table ;
         my $wrow = 0 ;
         for my $who (sort keys %swho_list) {
            (my $sponsor, my $submitter) = split $sep, $who;

            my $rtable = new HTML::Table ;
            my $rrow = 0 ;
            foreach my $dir ( sort keys %{$swho_list{$who}} ) {
               my $rlinks = "" ;
               $rlinks .= "int $swho_list{$who}{$dir}{$int}" if defined $swho_list{$who}{$dir}{$int} ;
               $rlinks .= " fp $swho_list{$who}{$dir}{$fp}"  if defined $swho_list{$who}{$dir}{$fp} ;
               $rrow++ ;
               $rtable->addRow( "$dir\/", $rlinks ) ;
               if ( $sbg ne $successcolor ) {
                  $rtable->setRowBGColor($rrow, $sbg)  ;
                  $probno++ ;
                  my $id = add_prob($sbg, $who, "sw_other_$probno", $dir) ;
                  $rtable->setRowAttr($rrow, $id) ;
               }
            }

            $wrow++ ;
            $wcol->addRow( $sponsor,  $submitter, $rtable ) ;
            $wcol->setRowBGColor($wrow, $sbg)  ;
         }

         my $stable =  new HTML::Table() ;
         $stable->addRow( "$scomplaint" ) ;
         $stable->setColStyle(1, $boldbox) ;
         $stable->addCol($wcol) ;
         $stable->setRowBGColor(1, $sbg) ;

         push ( @swtables, $stable ) ;

      }

      push ( @swtables, build_jtables($sw_other, $jparams) ) ;
      push ( @swtables, build_btables($sw_other, $bparams) ) ;

   } # foreach sw_other

   return @swtables ;

} # build_swtables

#---------------------------------------------------------------------------
# Populate table of results claiming to be estimates
#
sub build_etables {
   my $eparams    = shift ; # input

   my %who_list = %$eparams ;
   my $estmsg = "ERROR: Notes claim each of these results is an estimate." ;

   my $eheader = "\n\n<h3 style=\"background-color:$failcolor;\">$estmsg</h3>\n";

   my $etable = new HTML::Table() ;
   my $erow = 0 ;

   
   for my $who (sort keys %who_list) {
      (my $sponsor, my $submitter) = split $sep, $who;

      foreach my $dir ( sort keys %{$who_list{$who}} ) {
         $erow++ ;
         $etable->addRow( " $sponsor ", "$submitter&nbsp;&nbsp;&nbsp;
                                         $dir\/ $who_list{$who}{$dir}" ) ;
         $etable->setRowBGColor($erow, $failcolor) ;
         my $id = add_prob($failcolor, $who, "Estimate", $dir) ;
         $etable->setCellAttr($erow, 1, $id) ;
      }
   }

   if ($erow) {
      return "$eheader\n$etable<br>" ;
   } else {
      return "" ;
   }

} # build_etables



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

#-------------------------------------------------------------------
# Are any there any compiler notes or sw_other notes ?
#-------------------------------------------------------------------
sub sort_notes {
   my $nparams             = shift ; # input
   my $ccnotes_ref         = shift ; # out: crosscompile_notes
   my $jnotes_ref          = shift ; # out: jemalloc notes
   my $enotes_ref          = shift ; # out: estimate notes
   my $bnotes_ref          = shift ; # out: binutils notes

   my %notes = %$nparams ; # note sections from an rsf

   $$ccnotes_ref = "" ;
   $$jnotes_ref = "" ;
   $$enotes_ref = "" ;
   $$bnotes_ref = "" ;

   my $in_jnotes = 0 ;
   my $in_ccnotes = 0 ;
   foreach my $section (sort keys %notes) {
      next if $section =~ ($wrong_notes) ;
      my @gen_notes = split (/$sep/, $notes{$section} ) ;
      foreach my $nline (@gen_notes) {

         $nline =~ s/avilable/<span style="background-color:$warncolor;">avilable<\/span>/ ;

         if ($section =~ /jemalloc/i) {
            $$jnotes_ref .= "$nline<br>" ;

         } elsif ($section =~ /(comp|cross)/i) {
            next if $nline =~ /compiler.*is.*available/i ;
            next if $nline =~ /http/ ;
            next if $nline =~ /inconsistent|correct version|discrepancy/i ; # notes_comp about IC -v issue
            $$ccnotes_ref .= "$nline<br>" ;

         } elsif ($section =~ /binutils/) {
            $$bnotes_ref .= "$nline<br>" ;

         } else {
            if ($nline =~ /$obviously_neither/i) {
               $in_jnotes = 0 ;
               $in_ccnotes = 0 ;
               next ;
            } 
   
            if ($nline =~ /$jemalloc_search_string/i ) {
               $$jnotes_ref .= "$nline<br>" ;
               $in_jnotes = 1 ;
               $in_ccnotes = 0 ;

            } elsif ($nline =~ /$compile_search_string/i ) {
               $$ccnotes_ref .= "$nline " ;
               $in_jnotes = 0 ;
               $in_ccnotes = 1 ;

            } elsif ($in_jnotes) {
               $$jnotes_ref .= "$nline<br>" ;

            } elsif ($in_ccnotes) {
               $$ccnotes_ref .= "$nline " ;
            } 

            if ($nline =~ /$estimate_search_string/i) {
               $$enotes_ref .= "$nline" ;
            } 

            $in_ccnotes = 0 if seen_all_required_tokens($$ccnotes_ref) ;
         }
      }
   }

   $$ccnotes_ref   =~ s/^\s+//;         # no trailing or leading blanks
   $$ccnotes_ref   =~ s/\s+$//;
   $$jnotes_ref   =~ s/^\s+//;     
   $$jnotes_ref   =~ s/\s+$//;
   $$enotes_ref   =~ s/^\s+//;     
   $$enotes_ref   =~ s/\s+$//;
   $$bnotes_ref   =~ s/^\s+//;     
   $$bnotes_ref   =~ s/\s+$//;

   $$ccnotes_ref = "None" if $$ccnotes_ref eq "" ;
   $$jnotes_ref = $blank if $$jnotes_ref eq "" ;
   $$bnotes_ref = $blank if $$bnotes_ref eq "" ;

} # sort_notes

# Read the result's .rsf (raw) file, and tuck away data from some fields 
# editable by the submitter. 
#
sub read_rsf {
   my $rsf                 = shift ; #  in:  file to read
   my $fp_ref              = shift ; # out:  FP result?
   my $sw_other_ref        = shift ; # out: value of sw_other
   my $who_ref             = shift ; # out: sponsor[sep]submitter
   my $notes_ref           = shift ; # out: crosscompile_notes

   (my $rnum) = $rsf =~ /(\d\d*)\.rsf/ ;
   my $first_jnote = "03104" ; # first unWithdrawn result when we expect jemalloc detail in General Notes
   my $sponsor = my $submitter = "" ;
   my $this_note_id     = "";
   my @compopts    ; # compiler options for one benchmark
   my $used_jemalloc = 0 ; # boolean: true if jemalloc is among compiler options
   $$fp_ref = 0  ;

   my $FILE ;
   open ($FILE, "<", $rsf) or say "Could not open $rsf";
   while (<$FILE>) {
      chomp ;

      my $this_note_text = "";
      if (/spec.$suite.sw_other[^:]*:\s*(\S+.*)/) {
         $$sw_other_ref .= "$1 ";
         next;

      } elsif (/test_sponsor[^:]*:\s*(.*)/) {
          $sponsor .= "$1 ";

      } elsif (/Submitted_by:\s*(.*)/) {
         $submitter = $1;

         $$who_ref = get_who($sponsor, $submitter) ;
         next;
     
      } elsif (/$suite\.metric: (\S+)/ ) {
         my $metric = $1 ;
         $$fp_ref   = $metric =~ /fp/i ? 1 : 0 ;

      # grab all consecutive lines
      } elsif (/compopts(\d+)[^:]*:\s*(.*)/) {
         $compopts[$1] = $2 ;

      # done reading compopts for one benchmark
      } elsif (/compvers(\d+)/) {
         my $opts = decode_decompress(join('',@compopts)) ;
         if ( $opts =~ /\-l\s*jemalloc/ ) {
            $used_jemalloc = 1 ;
            last ; # quit reading file if we find a jemalloc flag
         } else {
            undef @compopts ;
         }
      }

      # slurp notes 
      if (/spec.$suite.(notes\S*)_\d\d\d:\s*(.*)$/) {
         my $section = $1 ;
         my $nline = $2 ;
         next if $section =~ /sysinfo/i ;
         $$notes_ref{$section} .= "$nline$sep" ;
      }

   } # while
   close $FILE ;

   $$sw_other_ref   =~ s/^\s+//;         # no trailing or leading blanks
   $$sw_other_ref   =~ s/\s+$//;
   $$sw_other_ref = $blank if $$sw_other_ref eq "" ;

   # older results show jemalloc compile options and location source within sw_other 
   # instead of General Notes
   if ($rnum < $first_jnote and $$sw_other_ref =~ /built/ ) {
      (my $a, my $b) = split ";", $$sw_other_ref, 2 ;
       $$sw_other_ref = $a ;
       $$notes_ref{"notes_jemalloc"} .= "\[sw_other: \]$b" if defined $b ;
   }

   if ( $used_jemalloc ) {
      $$sw_other_ref .= $sep . "flags include -ljemalloc" ;
   } else {
      $$sw_other_ref .= $sep . "flags do not mention -ljemalloc" ;
   }

   return ;

} # sub read_rsf


#-------------------------------------------------------------------
# Check whether jemalloc is among the compiler options for any benchmark
sub used_jemalloc {
   my @compopts            = shift ; #  in: compiler options 

   foreach my $opts (@compopts) {
#     say $opts ;
   }
#     return(1) if ( index($line, "ljemalloc") != -1 ) ;
   return (0) ;
}

#-------------------------------------------------------------------
# Answer whether we have seen all the required tokens
# Uses global about what is required.
#
sub seen_all_required_tokens {
   my $checkme = shift;
   my $seen_all = 1;
   for my $token (@compile_required_tokens) {
      if (! ($checkme =~ m{$token}i)) {
         $seen_all = 0;
         last;
      }
   }
   return $seen_all;
}

#-------------------------------------------------------------------
# Write the report header
#
sub write_preface_cross {
   my $required_tokens = "'" . join($blank, @compile_required_tokens). "'";
   (my $obvious = $obviously_neither) =~ s/ /&nbsp;/g;

   my $runruleno = "4.9" ;
   my $runrule = "SPEC CPU 2017 V1 rule $runruleno" ;
   my $runruleurl = "https://www.spec.org/$suite/Docs/runrules.html#rule_$runruleno" ;
   my $notes_compurl = "https://www.spec.org/$suite/Docs/config.html#notes_comp" ;
   my $descjemallocurl = "https://pro.spec.org/private/wiki/CPU/MeetingMinutes23Jan2018#Describing_jmalloc" ;

   my $tagsurl = "https://www.spec.org/auto/$suite/Docs/config.html#sectionV.C.3" ;
#     <a href="$runruleurl">http://www.spec.org/$suite/Docs/runrules.html#rule_$runruleno</a></li>

   my $title = "Cross-compiles, binutils, etc" ;
   my $more_style = <<EOF;
.snugbot      { margin-bottom:0.1em; }
EOF

   # purpose, explain the concepts and limitations
   my $html_top = <<EOF;
   
<table>
<tr>

   <td>
   <h3 style="margin-top:.1em;">Purpose of this report</h3>
   <ol style="margin-top:.2em;">
      <li style="margin-top:.2em;">Identify results that claim to be an estimate.</li>
      <li style="margin-top:.2em;">Shows <tt>notes</tt> about cross-compiles, per $runrule: 
      <a href="$runruleurl">$runruleurl</a></li>
      <li style="margin-top:.2em;">Lists all the strings seen for <tt>sw_other</tt>, and tells you which result files use that
      string.</li>
      <li style="margin-top:.2em;">Shows jemalloc <tt>notes</tt>, per 
      <a href="$descjemallocurl">$descjemallocurl</a> <br></li>
      <li style="margin-top:.2em;">Shows binutils <tt>notes</tt>
   </ol>

   <h3>How to read this report</h3>
   <p>The Cross-compile section is sorted by cross-compile notes / submitter. The sw_other section is sorted by sw_other / General notes / submitter.</p>

<div style="font-size:90%;margin:1em 1em 1em 3em;background:#e8e8e8;"><p>
<p style="margin-bottom:.1em;">Since we do not have a field for cross-compiles, this procedure
<span style="text-decoration:line-through;">heroically</span>
tragically attempts to parse your notes.</p>
<ul style="margin-top:.1em;">
   <li style="margin-top:.1em;">A compile string is recognized by any occurrence of:
        <br />&nbsp;&nbsp;&nbsp;&nbsp;<tt>'$compile_search_string'</tt></li>
   <li style="margin-top:.9em;">All notes from the same section are appended, until:
      <ol>
         <li style="margin-bottom:.6em;margin-top:.6em;">We reach the end of this notes
             <a href="$notes_compurl">section</a> or find notes with a different
             <a href="$tagsurl">tag</a>, or</li>
         <li style="margin-bottom:.6em;">One of these strings is found, indicating a line that seems obviously to be not about cross compiles:
             <br />&nbsp;&nbsp;&nbsp;&nbsp;<tt>$obvious</tt>
             <br />(upper/lower case is fine) or </li>
         <li style="margin-bottom:.6em;">All of these strings from the run rule text have been found:
             <br />&nbsp;&nbsp;&nbsp;&nbsp; <tt>$required_tokens</tt><br />
             (upper/lower case is fine, plural is fine)</li>
      </ol></li>
</ul>

<p style="margin-bottom:.1em;">PLEASE put your general binutils notes in a section with a notes_binutils_nnn
<a href="$tagsurl">tag</a></p>
<p style="margin-bottom:.1em;">RECOMMENDATION: put your general jemalloc notes in a section with a unique jemalloc 
<a href="$tagsurl">tag</a>, for example:</p>
<pre style="margin-top:.3em;">   notes_jemalloc_005 = jemalloc, a general purpose malloc implementation
   notes_jemalloc_010 = built with the RedHat Enterprise 7.4, and the system compiler gcc 4.8.5
   notes_jemalloc_015 = sources available from jemalloc.net or https://github.com/jemalloc/jemalloc/releases
</pre>
</div>
<br />

   <h3>Limitations</h3>

   <ol class="l1">
      <li>Does not yet look for all required jemalloc tokens."</li>
   </ol>

   <h3>Unpublished vs. published</h3>

</tr>
</table>
EOF

# Maybe add this above ???
#<pre style="margin-top:.3em;">   notes_cross_100 = Binaries were compiled on a system with 2x Model 19 CPU
#   notes_cross_110 = chips + 3 TB Memory using AcmeOS V11
#   notes_cross_120 = (with binutils V99.97 and the Acme CPU Accelerator).
#</pre>

   $html_top .= available_reports(\%cross_file) ;

   return( init_html_vars($title, $more_style, $html_top) ) ;

} #  sub write_preface_cross
