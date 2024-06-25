#!/usr/bin/perl -w
# Attempt to whine about non-standard memory descriptions
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Authors: J. Henning, Julie Reilly
#
# $Id: mem4.pl 6540 2020-09-24 13:56:59Z CloyceS $
#
# usage: (this proc) *rsf
# j.henning 2010 Oct updated 2011 Nov 
# JL Reilly 2015 May attempt to recognize POWER8 memory format (this comment added in 08/2015)
# JL Reilly      Oct modified the POWER8 format
# JL Reilly 2016 Mar added T speed bin list for DDR4
# JL Reilly      Sep look at $SUITE environment variable
# JL Reilly      Oct moved output
# JL Reilly      Dec also report on ReReview
# JL Reilly 2017 Jun unknown speed bin is now a warning rather than a failure
#                    added V speed bin for DDR4
#                Oct never allow 'running at nnnn ?Hz' for DDR4
#                    stop printing EOR
#           2018 Jul CPU2017 is now the default SUITE
#                Aug show sponsor names in Table of Contents if not ok
#           2019 Mar use Review_util.pm 
#                    make Table of Problems instead of Table of Contents
#                    recognize speed bins W, Y, AA, AC
#                    make code more modular
#                    PC4 speed bin was ignoring second char
#                Jul Do not stop reading the .rsf lines too early!
#                Dec added -i option, for which output is STDOUT
#           2020 Apr use global $reviewhost rather than local $host
#                May tweaked code for opening output files
#                    use available_reports(), common_usage(), and global $rindir
#                Sep use get_who()

use strict;
use warnings;
use v5.10.1 ; # say
use IO::Handle;
use List::MoreUtils qw(any uniq) ;
use Env qw($SUITE) ;

# need this to locate Review_util
use FindBin qw($Bin);
use lib $Bin;

# Set several other globals via 'Review_util::init_review_tools' - see
# EXPORT list for the module.
use Review_util;

sub read_rsf ;
sub write_preface_mem ;
umask 0002 ;

# globals
our $suite = $SUITE ? $SUITE : "cpu2017" ;

# global data created as we read files, consumed by reporting routines
# 'who' is a composite key: sponsor / submitter, as in Acme / joe@acme.com
my @report ;

init_review_tools;
$SIG{__DIE__}      = \&file_clean_at_fail;

#-----------------------------------------------------------------------------------------
# main code starts here
#-----------------------------------------------------------------------------------------

my $outdir = "$outroot/mem" ;
my %mem_file = (
   "unpub" => "$outdir/mem.unpub.html",
   "pub"   => "$outdir/mem.pub.html",
) ;

common_usage ; # parse command line ; show usage if necessary

my $outfile = "STDOUT" ; 
if ( ! $report_custom ) { # normal review operation, after submission

   if ($report_accepted) {
      $outfile         = $mem_file{"pub"} ;
   } else {
      $outfile         = $mem_file{"unpub"} ;
   }
}
my $fh = IO::Handle->new();
open_outfile $fh, $outfile ; 

say $fh write_preface_mem ;

push (@report, "<html><body>");

my $rsfcommonpart  = "/spec/pro/osg/submit/$suite/";
my $resulturlstart = "https://pro.spec.org/private/osg/submit/$suite/";

# report parts
my $header;
my $issue_report = "";
my $ok_report = "";
my $eor       = "<div id=\"EOR\"></div>" ; # separator between report dirs

# tables built for each directory
my %bad;
my %questions;
my %ok;

my @bad_sponsors ;
my @quest_sponsors ;
for my $dir ( dirs_to_report($outfile) ) {
   chomp $dir;

   # find and read result files
   my @files =  get_result_files($dir, $report_accepted, "rsf") ;
   next if ! @files;

#  push (@report, "\n\n<h2 style=\"border-top:medium solid black;\">$dir</h2>\n");

   my $fileno;
   my $dotfreq = 25;
   if ($debug) {
      my $nfiles = scalar @files;
      print "found $nfiles files in $dir\n";
      print "printing one dot for every $dotfreq files" if $nfiles > $dotfreq;
      $fileno = 0;
   }

   (my $anchor = $dir) =~ s{$rsfcommonpart}{};
   $anchor =~ s{/}{_}g;
   for my $rsf (sort @files) {
      
      my $cpu_name = my $hw_memory = my $who = "" ;
      read_rsf($rsf, $dotfreq, \$fileno, \$cpu_name, \$hw_memory, \$who) ;
      (my $sponsor, my $submitter) = split $sep, $who;
      
      my $outline = "" ;
      my ($failed, $questioned) = (0, 0);

      # ------------------ what it should look like -----------
      # 256 GB (16 x 16 GB 2Rx4 PC3-14900R-13, ECC)
      # 256 GB (16 x 16 GB 2Rx4 PC4-2133P-R) 
      # -------------------------------------------------------

      #
      # Start with various localized tests
      # 
      $outline = <<EOF;
         <span style="white-space:nowrap;font-family:monospace;">"$hw_memory"</span>
EOF
      # If two complete strings, wrap on them
      if (length($outline) > 40 && $outline =~ m{(.*)\)\s+(\d+\s?.B.*)}) {
         $outline = "$1)</span><br /> <span style=\"white-space:nowrap;font-family:monospace;\">$2</span>";
      }
      my $start = '^\d+ (KB|MB|GB|TB)';

      # Is this memory described as it can be ordered from IBM for POWER8, per (osgcpu-39861) ? 
      if ($hw_memory =~ m{$start \(\d+ x \d+ (KB|MB|GB|TB) (DIMMs|CDIMMs)\) DDR(3|4) \d+ MHz}
        and $cpu_name eq "POWER8"
      ) {
         $outline .= "<br />POWER8 format tentatively recognized as orderable from IBM; Please check manually\n";
         $questioned = 1;
         goto FILEIT ; # using goto so this special case interferes as little as possible with tests
      }

      if ($hw_memory =~ m{\b(\d+(K|M|G|T)B)}) {
         $outline .= "<br />Please use a space in between size and unit, instead of '$1'\n";
         $failed = 1;
      }
      if ($hw_memory !~ /$start/) {
         $outline .= "<br />Should start with size and unit, as in \"<tt>512 KB</tt>\"\n";
         $failed = 1;
      }
      if ($hw_memory !~ /$start \(.*\)\s*$/) {
         $outline .= "<br />Lead with total and units, then parens around all else: <tt>\"128 KB (4 x 32 KB etc etc)</tt>\"";
         $failed = 1;
      }
      my $ndimm = '\(\d+ x \d+ (KB|MB|GB|TB)';
      if ($hw_memory !~ / $ndimm/) {
         $outline .= "<br />Need # dimms and size for each, as in <tt>\"(768 x 1 KB\"</tt>\n";
         $failed = 1;
      }
      if ($hw_memory =~ /DDR/) {
         $outline .= "<br />DDR found; use PCn-nnnn instead.\n";
         $failed = 1;
      } 
      my $rankbitwidth = '\d+(D|Q|S[248])?Rx\d+'; 
      if ($hw_memory !~ / $rankbitwidth /) {
         $outline .= "<br />Did not find rank and bit width\n";
         $failed = 1;
      }
      if ($hw_memory =~ m{PC4\S?-\d+.*ECC}) {
         $outline .= "<br />For DDR4, don't say 'ECC'.  Its presence or absence is encoded in the 'type' designation\n";
         $failed = 1;
      }
      #
      # PC3-14900R-13
      # PC4-2133P-R 
      #
      my $pc3n                   =  '(?:PC|EP)3\S?-\d+([A-Z])(-\d+)';   # what we want
      my $pc4                    =  'PC4\S?-(\d+)(\S\S?)-(\S)';       # what we want
      #
      my $pc3n_WAS_optional_cl   =  '(?:PC|EP)3\S?-\d+([A-Z])';         # starts out ok for PC3, missing some stuff
      my $pc3n_noCLcl            = '((?:PC|EP)3\S?-\d+[A-Z](-CL\d+))';  # don't say 'CL' in main part of field
      my $pc3n_no_p3mtype        =  '(?:PC|EP)3\S?-\d+-\d+';            # missing module type 
      my $pc4_start              =  'PC4\S?-(\d+)';                     # starts out ok for PC4, missing some stuff
      my $pc4_dash_nn            =  'PC4\S?-\d+(\S)?-\d\d';             # two digits at end is wrong format for CAS
      my $pc4_Hz                 =  'PC4.*Hz' ;                         # ends in ?Hz 
      #
      my $cl_at_max_op_freq  = "";
      my $p3mtype            = "";
      my $p4speed            = 0;
      my $p4speedbin         = "";
      my $p4type             = "";
      if ($hw_memory =~ / $pc3n/) { # DDR3
         $p3mtype           = $1;
         $cl_at_max_op_freq = $2;
      } elsif ($hw_memory =~ / $pc4\b/) { # DDR4
         $p4speed     = $1;
         $p4speedbin  = $2;
         $p4type      = $3;
         #
         # It matches PC4, but do the values make sense?
         #
         # Maintainability note: the close checking here is because of the expected-to-be-rough transition from PC3 to PC4,
         # and could be relaxed later.  That is part of why all the messages in this section are dated. 
         my $p4thresh = 5000;
         my $p4binRE  = '^[JKLMNPRTUVWY]|AA|AC$';
         my $p4typeRE = '^[ABCELNRSTUW]$';
         if ($p4speed > $p4thresh) {
            $failed = 1;
            $outline .= "<br />Found alleged PC4 speed of '$p4speed'.  This seems unlikely, considering that in "
            . "Sep-2014, the fastest target mentioned by JEDEC seems to be 4266.";
         } elsif ($p4speedbin !~ m{$p4binRE}o) {
            $questioned = 1;
            $outline .= "<br />Found alleged PC4 speed bin '$p4speedbin'.   This seems unlikely to be correct because as of "
            . "Jun-2017, the speed bins mentioned in JEDEC 79-4 would match '$p4binRE'";
         } elsif ($p4type !~ m{$p4typeRE}o) {
            $failed = 1;
            $outline .= "<br />Found alleged PC4 module type '$p4type'.    This seems unlikely to be correct because as of " 
            . "Sep-2014, the types mentioned in JEDEC 4_20_25 and 26 would match '$p4typeRE'";
         }
      } else {
         # Neither pc3 nor pc4 match... can we provide some hints about common errors?
         $failed = 1;
         if ($hw_memory =~ /$pc3n_noCLcl/) {
            my $PCnn = $1;
            my $CLcl = $2;
            (my $cl  = $CLcl) =~ s{CL}{};
            $outline .= "<br />In the string '<tt>$PCnn</tt>', the '<tt>$CLcl</tt>' should be just '<tt>$cl</tt>'\n";
         } elsif ($hw_memory =~ /$pc3n_WAS_optional_cl/) {
            $outline .= "<br />CAS latency at max op frequency is required (see minutes 11 Jan 2011)\n";
         } elsif ($hw_memory =~ /$pc3n_no_p3mtype/) {
            $outline .= "<br />It looks like you forgot the \"Module Type\" letter\n";
         } elsif ($hw_memory =~ /$pc4_dash_nn/) {
            $outline .= "<br />DDR4 is <a "
            . "href=\"https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat\"> described </a> "
            . "using letters for speed bins, not with numeric CAS latencies\n";
         } elsif ($hw_memory =~ /$pc4_start/) {
            $outline .= "<br />For DDR4, please see the <a "
            . "href=\"https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat\"> MemoryDescriptionFormat</a> "
            . "wiki page.\n";
         } else {
            $outline .= "<br />Did not find PCn-bandwidth\n";
         }
      }
      my $running1 = ', running at \d+(\s[\S+z|MT/s])?'; # require space before optional units
      my $running2 = 'and CL\d+';
      if ($hw_memory =~ /downclock.*Hz/) {
         $outline .= "<br />Don't say downclock.  The phrase you are looking for is \"running at\"\n";
         $failed = 1;
      }
      if ($hw_memory =~ /running/i) { 
         if ($hw_memory !~ /$running1/) {
            $outline .= "<br />For non-std speed, say <tt>\", running at nnnn\"</tt>\n";
            $failed = 1;

         } elsif ($hw_memory =~ /$pc4_Hz/i) {
            $outline .= "<br />Omit frequency units; say <tt>\", running at nnnn\"</tt>\n";
            $failed = 1;
         }

         $outline .= "<br />Reminder: all adjustments to memory timings must be documented.<br />(It's not just frequency).  See 
         <a href=\"https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat#Reminders\">reminders</a> on the
         memory page";
      }
      #
      # If individual tests ok, try full string
      #
      if (!$failed) { 
         if (
            ($hw_memory =~ /$start $ndimm $rankbitwidth $pc3n(, ECC)?(, per node)?($running1 $running2)?/) ||
            ($hw_memory =~ /$start $ndimm $rankbitwidth $pc4(, per node)?($running1 $running2)?/) 
         ) {
            # $outline .= "OK!";
         } else {
            $outline .= sprintf "<br />Match failure";
            $failed = 1;
         }
      }
      # p4speed 0 means DDR3.  We don't look for 'ECC' with ddr4
      if (!$failed && ($p4speed == 0)  && ($outline !~ /ECC/) && ($p3mtype ne "U")) {
         $outline .= "<br />No ECC mentioned; is that intentional?";
         $questioned = 1;
      }

      # ---------------------------------------------
      # All testing done.  File it into correct group
      # ---------------------------------------------
FILEIT: my $short_sponsor = substr($sponsor, 0, 10); 
      my $result_link = result_link($dir,$rsf) ;
      if ($failed) {
         $bad{$who}{$outline} .= "$result_link\n";
         push(@bad_sponsors, $who) ;

      } elsif ($questioned) {
         $questions{$who}{$outline} .= "$result_link\n";
         push(@quest_sponsors, $who) ;

      } else {
         $ok{$who}{$outline} .= "$result_link\n";
      }
   }

   # Assemble some reportage.
   @bad_sponsors = uniq @bad_sponsors ;
   @quest_sponsors = uniq @quest_sponsors ;
   if (%bad) {
      my $bg = $failcolor ;

      $issue_report .= <<EOF;
      <div style=\"background:$bg;\">
      <h3 id="${anchor}_issues">$dir Results that did not match requested format </h3>
EOF
      for my $who (sort keys %bad) {
         (my $sponsor, my $submitter) = split $sep, $who;
         $issue_report .= <<EOF;
         <p style="margin:1em 0 .1em;"><b>$sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter</b></p>
         <table style="margin-left:2em;">
         <tr>
             <th>Memory String</th>
             <th>Results</th>
         </tr>
EOF

         for my $line (sort keys %{$bad{$who}}) {
            my $id = add_prob($bg, $who, "memory", $dir) ;
            my $rsfs = split_pile_of_rsfs ($bad{$who}{$line});
            $issue_report .= <<EOF;
            <tr>
               <td bgcolor=$failcolor $id class="bad">$line</td>
               <td bgcolor=$failcolor class="bad">$rsfs</td>
            </tr>
EOF
         }
         $issue_report .= "</table>\n";
      }
      $issue_report .= "</div>\n";
   }
   #
   #
   #
   if (%questions) {
      my $bg = $warncolor ;

      $issue_report .= <<EOF;
      <div style=\"background:$bg;\"> 
      <h3 id="${anchor}_questions">$dir results match the format, but have questions</h3>
EOF
      for my $who (sort keys %questions) {
         (my $sponsor, my $submitter) = split $sep, $who;
         $issue_report .= <<EOF;
         <p style="margin:1em 0 .1em;"><b>$sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter</b></p>
         <table style="margin-left:2em;">
         <tr>
             <th>Memory String</th>
             <th>Results</th>
         </tr>
EOF
         for my $line (sort keys %{$questions{$who}}) {
            my $id = add_prob($bg, $who, "memory", $dir) ;
            my $rsfs = split_pile_of_rsfs ($questions{$who}{$line});
            $issue_report .= <<EOF;
            <tr>
               <td bgcolor=$warncolor $id class="quest">$line</td>
               <td bgcolor=$warncolor class="quest">$rsfs</td>
            </tr>
EOF
         }
         $issue_report .= "</table>\n";
      }
      $issue_report .= "</div>\n";
   }
   #
   #
   #
   if (%ok) {
      my $bg = "#e0ffe0" ; # green
      $ok_report .= <<EOF;
      <div style=\"background:$bg;\">  
      <h3 id="${anchor}_ok"> $dir ok results </h3>
EOF
      for my $who (sort keys %ok) {
         (my $sponsor, my $submitter) = split $sep, $who;
         $ok_report .= <<EOF;
            <p style="margin:1em 0 .1em;"><b>$sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter</b></p>
            <table style="margin-left:2em;">
            <tr>
                <th>Memory String</th>
                <th>Results</th>
            </tr>
EOF
         for my $line (sort keys %{$ok{$who}}) {
            my $rsfs = split_pile_of_rsfs ($ok{$who}{$line});
            $ok_report .= <<EOF;
            <tr>
               <td bgcolor=$bg class="ok">$line</td>
               <td bgcolor=$bg class="ok">$rsfs</td>
            </tr>
EOF
         }
         $ok_report .= "</table>\n";
      }
      $ok_report .= "</div>\n";
   }
   undef %bad;
   undef %questions;
   undef %ok;
   
}

push (@report, $issue_report) ;
push (@report, $ok_report) ;
push (@report, $html_finish) ;

say $fh make_top ;
foreach (@report) {
   say $fh $_ ;
}

close ($fh) ;
exit_success;

#--------------------------------------------------------------------------------
# Read the result's .rsf (raw) file, and tuck away data from some fields
# editable by the submitter.
#
sub read_rsf {
   my $rsf                 = shift ; #  in: file to read
   my $dotfreq             = shift ; #  in: frequency of dots printed while reading rsfs
   my $fileno_ref          = shift ; # out: rsf file count
   my $cpu_name_ref        = shift ; # out: contents of cpu_name 
   my $hw_memory_ref       = shift ; # out: contents of hw_memory
   my $who_ref             = shift ; # out: sponsor[sep]submitter

   my $sponsor = my $submitter = "";

   if ($debug) {
      $$fileno_ref++;
      print "." if ($$fileno_ref % $dotfreq) == 0;
   }

   if (! open FILE, "<$rsf") {
      warn "cannot open $rsf $!\n";
      next;
   }

   while (<FILE>) {
      if (/sponsor: (.*)/) {
         $sponsor = $1;

      } elsif (/hw_memory\d*:\s+(.*)/) {
         $$hw_memory_ref .= "$1 ";

      } elsif (/hw_cpu_name: (.*)/) {
         $$cpu_name_ref = $1 ;

      } elsif (/Submitted_by:\s*(.*)/) {
         $submitter = $1;
         last ;
      }
   }

   close FILE ;

   $$hw_memory_ref =~ s/\s+$//; # no trailing space
   $$hw_memory_ref =~ s/^\s+//; # no starting space
   $$who_ref =  get_who($sponsor, $submitter) ;

} # sub read_rsf 

#--------------------------------------------------------------------------------
sub split_pile_of_rsfs 
{
   my $rlimit = 7; # max number rsf to print on a line
   my @rsfs = split "\n", shift;
   my $outbuf = "";
   my $n = 0;
   for my $rsf (@rsfs) {
      $outbuf .= "<br />" if ($n > 0 && ($n % $rlimit) == 0);
      $outbuf .= "$rsf\n";
      $n++;
   }
   return $outbuf;
}

#--------------------------------------------------------------------------------
sub write_preface_mem {
   my $title = uc($suite) . " Memory descriptions" ;
   my $more_style = <<EOF;
.snugbot      { margin-bottom:0.1em; }
EOF

   # purpose, explain the concepts and limitations
   my $html_top    = <<EOF;

<table>
<tr>

   <td>
   <h3 style="margin-top:.1em;">Purpose of this report</h3>
   <p class="snugbot">This report helps you verify whether unpublished results match SPEC's requirements 
      for description of memory, from 
      <a href="https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat">
https://pro.spec.org/private/wiki/bin/view/CPU/MemoryDescriptionFormat</a>
   </p>

   <h3>How to read this report</h3>
   <p>Submissions are sorted by issues (if any) / directory / submitter</p>

   <h3>Unpublished vs. published</h3>
</tr>
</table>
EOF

   $html_top .= available_reports(\%mem_file) ;

   return( init_html_vars($title, $more_style, $html_top) ) ;

} # sub write_preface_mem

