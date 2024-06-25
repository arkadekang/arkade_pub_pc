#!/usr/bin/perl
#
# Review_util.pm
#
# Handy utility routines for review tools
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Authors: J. Henning, Julie Reilly
#
# $Id: Review_util.pm 6548 2020-11-10 16:33:32Z CloyceS $
#
#     
# when you muck with this, change both file name and package name
#package Review_util_debug;
package Review_util;
#
# SYNOPSIS

#      use strict;
#      use warnings;
#      BEGIN {
#         if (! defined $ENV{"SPEC"}) {
#            die "please define \$SPEC\n";
#         }
#      }
#      BEGIN {
#         use File::Basename;
#         use File::Spec::Functions qw(rel2abs);
#         use IO::Handle;
#         use FindBin qw($Bin);
#         use lib $Bin;
#         use Review_util;         
#         # use Review_util_debug;  
#      }

#      # optional - if not set, defaults will be chosen
#      [ our $debug      = [0|1];                   ]
#      [ our $debug_ext  = "string";                ]
#      [ our $report_accepted = [0|1];              ]
#      [ our $report_custom   = [0|1];              ]
#      [ our $rindir     = "string";                ]
#      [ our $start_time = localtime() | "string";  ]
#      [ our $suite      = "string";                ]
#      [ our $tmp_ext    = "string";                ]

#      init_review_tools;
#      $SIG{__DIE__}      = \&file_clean_at_fail;

#
# If desired, can mention specific routines
#      use Review_util(
#           add_prob
#           available_reports
#           border
#           byid           
#           by_sut_and_time
#           choose_bg
#           common_usage
#           complain
#           date_compare
#           dirs_to_report
#           eval_date
#           exit_fail 
#           exit_success 
#           file_clean_at_fail
#           get_result_files
#           init_html_vars
#           init_review_tools
#           Log
#           make_top
#           numerically 
#           open_outfile 
#           result_link
#      );
#
# BRIEF DESCRIPTION
# -----> For more details:
#     ---->  about variables:   search for 'GLOBALS', below.
#     ---->  about routines:    see comments at top of each.

# Globals - out/defaulted: $BASE0, $debug, $debug_ext, $report_accepted, $report_custom, 
#                          $rindir, $start_time, $suite, $tmp_ext, $TMPDIR

#         - out: $html_finish, $outroot, $outurlroot, $pub_dir,
#                $report_title, $report_start, $reviewhost, $submittop, $submiturlroot, $make_changes_unpub,
#                $make_changes_accepted, $unpub_dirs, $failcolor, $warncolor,
#                $infocolor, $goodcolor, $successcolor, $sep, %problems

#
# Functions
# 
#    add_prob       - record a problem in %problems, and generate an id we can link to
#                     (via make_top) for one or more problems in that section for that submitter
#
#    available_reports - returns HTML for preface section about available reports
#   
#    border         - returns markup for border strings
#   
#    byid           - a sorting method, as in:
#                         sort byid (@rsf)
#
#    by_sut_and_time - sorts lines of form 
#                         running on altosr380f2-2 Sat May 25 23:50:19 2013 
#
#    choose_bg      - returns appropriate background color, according to the contents of a complaint string
#
#    common_usage   - parse command line / show usage (many review tools have an identical usage)
#
#    complain       - returns a table error/warning message for a particular problem
#
#    date_compare - compare two dates and whine when necessary
#
#    dirs_to_report - returns array of directories containing results
#
#    eval_date - check date format
#
#    exit_fail      - calls file_clean_at_fail then actually exits
#
#    exit_success   - close output files; rename to get rid of .$tmp_ext
#
#    file_clean_at_fail - preserve evidence if debug; used as DIE handler
#
#    get_result_files - returns an array of results files
#
#    init_html_vars - create top of report in J.Reilly desired fashion
#
#    init_review_tools - set the globals as described above.  Call this 
#                        before using them. :-)
#                      - If you do not call this before first call to 
#                        other routines in this package, then it will 
#                        be called automatically.  
#
#    Log            - logs messages ; needed by util_common.pl
#
#    make_top       - generate a table of problems found in %problems
#
#    numerically    - a sorting method, as in
#                         sort numerically (@numbers)
#
#    open_outfile   - opens a file, adjusts name if $debug set, 
#                     appends $tmp_ext, and keeps track of 
#                     all open files for later exits
#
#    short_company  -  normalize/shorten test_sponsor 
#
#    get_who        -  combine test_sponsor with submitter's email
#
#    rsfnum         - abbreviate an rsf file name 
#
#    result_link    - generate a link to a result file
#
# PREREQUISITE
#     perl (or specperl) needs to be 5.10 or later for the '//' operator
#
# AUTHOR
# j.henning 2013 Jun create
# JL Reilly 2016 Nov added TOE functions (adapted from compare-demidecode.pl)
# JL Reilly 2017 Mar changed Table of Errors header
#                    changed default behavior for rsfnum()
# JL Reilly 2018 Feb move toe subs back to compare-dmidecode.pl
#                    added rsf_to_link() choose_bg() and global colors
#                    added $sep, %problems
#                    added add_prob make_top() and complain()
#                Jul added get_result_files() and updated rsf_to_link() to adapt
#                    rsf_to_link() -> result_link() 
#                    now complain() understands INFO
#                    expand preface handling
#                Dec Table of Problems shows submitters or only the sponsors 
#                    use HTML::Table in case .pl file does not
#           2019 Mar Cross-compile report TOP may show multiple similar problems per submitter;
#                    make $report_title global so sub make_top() can read it
#                Apr CPU/Threads report TOP may show multiple similar problems per submitter
#                Jun a review tool might provide an alternate (2nd) list of problems for the TOP
#                Aug Recognize duplicates report
#                Dec added dirs_to_report() 
#                       tools calling it will NOT process cpu2006 results < res2011q4 anymore
#                    support custom input directory, for which output is STDOUT
#           2020 Jan adjust get_result_files() to work properly with dirs_to_report() output
#                    now info color is blue and green is a "good" color
#                Apr for unsubmitted results, print result filenames rather than links
#                    added reviewhost
#                May suppress specperl warnings about experimental given/when and smartmatch
#                    tweaked code for opening output files
#                    added available_reports() and $rindir
#                    added common_usage()
#                    added stub Log function
#               Jun  added date_compare(), eval_date() (moved from os_proc.pl)
#                    wrap long lists of problem id links in TOP
#               Aug  use FindBin
#               Sep  added Copyright and $Id: Review_util.pm 6548 2020-11-10 16:33:32Z CloyceS $
#                    added get_who(), short_company() 
#                    fix bug when exiting after 0 results found
#                    better error checking for directories
#               Oct  improve robustness of eval_date() 
#                    
#                    

use strict;
use warnings;
use v5.10 ; # say

use Getopt::Long;
use File::Basename;
use Sys::Hostname;
use File::Path;
use HTML::Table ;
use Time::Piece ; # strptime()
use Time::Seconds ; # constants such as ONE_MONTH
use Text::Wrap qw (&wrap $columns);
use Date::Parse; # str2time()
$columns = 132;
$Text::Wrap::unexpand = 0;  # no tab characters plese

# avoid warnings from specperl about given/when and smartmatch
use feature qw( switch );
no if $] >= 5.018, warnings => qw( experimental::smartmatch );

use Exporter();
our (@ISA, @EXPORT);
@ISA    = qw(Exporter);

# Overview of functions is above; for description of data, search for 'GLOBALS', below
@EXPORT = qw(
   &add_prob
   &available_reports 
   &border 
   &byid 
   &by_sut_and_time
   &choose_bg
   &common_usage
   &complain
   &date_compare
   &dirs_to_report
   &eval_date
   &exit_fail 
   &exit_success 
   &file_clean_at_fail
   &get_result_files
   &init_html_vars
   &init_review_tools
   &Log
   &make_top
   &numerically 
   &open_outfile
   &get_who
   &rsfnum
   &result_link
   &short_company

   $BASE0
   $debug
   $debug_ext
   $report_accepted
   $report_custom
   $rindir 
   $start_time
   $suite
   $tmp_ext
   $TMPDIR

   $outroot
   $outurlroot  
   $pub_dir 
   $reviewhost
   $submittop
   $submiturlroot
   $unpub_dirs

   $html_finish
   $report_title
   $report_start
   $make_changes_unpub
   $make_changes_accepted
   $failcolor
   $warncolor
   $infocolor
   $goodcolor
   $successcolor
   $sep

   %problems

);

#----------------------------------------------------------------
# GLOBALS communicating with package user

our ( # set by init_review_tools (d) = defaulted if not set
   $BASE0,          # out(d)   basename of caller
   $debug,          # out(d)   default: true if script name contains debug
   $debug_ext,      # out(d)
   $report_accepted,# out(d)   default: true if reporting on published
   $report_custom  ,# out(d)   default: true if reporting on custom input
   $rindir,         # out(d)   directory containing results
   $start_time,     # out(d)   localtime at beginning
   $suite,          # out(d)
   $tmp_ext,        # out(d)
   $TMPDIR,         # out(d)

   $outroot,        # out     report outdir tree, as file sys
   $outurlroot,     # out     same, as html
   $pub_dir,        # out     directory name for published results
   $reviewhost,     # out     hostname running review tool
   $submittop,      # out     submit directory tree, as file sys 
   $submiturlroot,  # out     same, as html
   $unpub_dirs,     # out     directory names for unpublished results
   $failcolor,      # out     a shade of pink
   $warncolor,      # out     a shade of yellow
   $infocolor,      # out     a light shade of blue
   $goodcolor,      # out     a light shade of green
   $successcolor,   # out     white
   $sep,            # out     separator between portions of composite keys
   %problems,       # out     modified by add_prob function
);

our ( # set by init_html_vars
   $html_finish,           # out     bottom of document </body> etc
   $report_title,          # out     "title of review report"
   $report_start,          # out     "report starts here:"
   $make_changes_unpub,    # out     reminders about submitter guide & alias
   $make_changes_accepted, # out     reminders about submitter guide & alias
);

#----------------------------------------------------------------
# package globals

my $pkg_initialized = 0;
my ( 
   @files_written,  # actual names used in open 
   %fh_written      # key: actual name at open, content: handle
);


#----------------------------------------------------------------------------------------
# Append the list of problems which will be output in the Table of Problems
sub add_prob {
   my $bg      = shift ; #  in: background color
   my $who     = shift ; #  in
   my $flavor  = shift ; #  in
   my $dir     = shift ; #  in
   my $altproblems_ref ; #  in: optional second problem list
   my $id ;              # out: HTML id for this problem
  
   my $prob = $bg . $sep . $flavor ;

   # use default problems list
   if ( scalar @_ == 0 ) { 
      if (!defined $problems{$who}{$dir}) {
         $problems{$who}{$dir}  = "$prob " ;
      } else {
         $problems{$who}{$dir} .= "$prob " unless ($problems{$who}{$dir} =~ "$prob") ;
      }

   # use an alternate problem list
   } else { 
      ($altproblems_ref) = shift ;
      if (!defined $$altproblems_ref{$who}{$dir}) {
         $$altproblems_ref{$who}{$dir}  = "$prob " ;
      } else {
         $$altproblems_ref{$who}{$dir} .= "$prob " unless ($$altproblems_ref{$who}{$dir} =~ "$prob") ;
      }

   }


   (my $sponsor, my $submitter) = split $sep, $who;
   $submitter = $sponsor if ! defined $submitter ;
   $id = 'id="' . $submitter . "_$dir" . "_$flavor" ; # output
   given ($bg) {
      when ($failcolor) { $id .= '_err"' }
      when ($warncolor) { $id .= '_warn"' }
      when ($infocolor) { $id .= '_info"' }
      when ($goodcolor) { $id .= '_good"' }
      default { $id .= '"' }
   }

   return $id ;

} # add_prob

#----------------------------------------------------------------------------------------
# Generate body of "Unpublished vs. published" section of the preface
#    Most reports will have unpublished and published reports
#
sub available_reports {
   my $oparams = shift ; # input 
   my %outfile = %{$oparams} ; # names of available output reports

   my ($uloc, $ploc) = "undefined" ;
   $uloc = $outfile{"unpub"} if defined $outfile{"unpub"};
   $ploc = $outfile{"pub"}   if defined $outfile{"pub"};

   if ($debug) {
      $uloc =~ s{.html$}{.$debug_ext.html};
      $ploc =~ s{.html$}{.$debug_ext.html};
   }

   my $rtype_text ;
   if ( $report_custom ) {
      $rtype_text = "\n<br>results found in $rindir " ;

   } elsif ($report_accepted) {
      $rtype_text = "the Accepted results, full report";

   } else {
      $rtype_text = "the unpublished results";
   }

   my $html    .= <<EOF;
   <p class="l1snugbot">This report is available for
       <a href="$uloc">unpublished</a> and
       <a href="$ploc">accepted </a>results. You are looking at the report for $rtype_text .
   </p>

EOF

  return $html ;

} # available_reports

#----------------------------------------------------------------------------------------
sub border              # I am tired of making mistakes with these.  
{                       # returns: 'border:style:x x x x;' where x=[solid|none]
   my $where = shift;   # input:   [tlrb]... any order 
   #
   if ($where =~ m{[^trlb]}) {
      die "incorrect argument: use only trlb, as in top, right, left, bottom";
   }
   my $border_string = "border-style:";
   for my $place (qw(t r b l)) {
      if ($where =~ m{$place}) {
         $border_string .= "solid ";
      } else {
         $border_string .= "none  ";
      }
   }
   $border_string .= ";";
   return $border_string;
}

#----------------------------------------------------------------
sub byid                 # numeric sort, by SPEC result number
{
# presumes caller is in main !
# Example: for cpu2006-20101207-13913.rsf, sort key is "13913".
#
#   Uses global $suite
#
   my $anum;
   my $bnum;
   my $start;
   { no warnings; $start = $suite || '[a-z]+\d{4}'; } # default, match mumble2015
   my $exts = 
      '(cfg|csv|flags.html|gif|html|orig.cfg|pdf|ps|rsf|sub|txt|xml)';
   if ($::a =~ m{$start-(\d){8}-(\d+)\.$exts}) {
      $anum = $2;
      if ($::b =~  m{$start-(\d){8}-(\d+)\.$exts}) {
         $bnum = $2;
         return $anum <=> $bnum;
      }  
   }
   return $::a cmp $::b;
}

#----------------------------------------------------------------
sub by_sut_and_time      # sort lines of form: 
{            # running on altosr380f2-2 Sat May 25 23:50:19 2013 
   #
# presumes caller is in main !
# Example: for cpu2006-20101207-13913.rsf, sort key is "13913".
   #
   if ($::a =~ m{running on\s*(\S+)\s(.*)}) {
      my $asut  = $1;
      my $atime = str2time $2;
      if ($::b =~ m{running on\s*(\S+)\s(.*)}) {
         my $bsut  = $1;
         my $btime = str2time $2;
         #
         if ($asut ne $bsut) {             # key #1 - hostname
            return ($asut cmp $bsut)       
         } elsif (
            defined $atime && 
            defined $btime && 
            $atime ne $btime)               # key #2 - date
         {
            return $atime <=> $btime;       
         }
      }
   }
   # The final fallback, if others not found or others are equal
   return $::a cmp $::b;
}

#----------------------------------------------------------------
# Not all review tools share this Usage, but many do
#   define the usage statement
#   parse the command line 
#      most options set global variables
#   omit some options when running offline (not on pro.spec.org)
#   some tools get ONE extra, non-global variable set via an optional pair of arguments 
sub common_usage {

   # does this tool need one extra option set?
   my $extra_name = my $extra_option_ref = "" ;
   $extra_name       = shift if @_ ; #  in: name of extra option
   $extra_option_ref = shift if @_ ; # out: value of extra setting

   # initialize options ;
   my $u_line = "Usage: $0 [--debug] [--indir dir] [--accepted] [--help]" ;
   my $d_line = "--debug|-d       just testing; output files are named xxx.debug.html" ;
   my $i_line = "--indir|-i dir   location of results; default is all unpublished" ;
   my $a_line = "--accepted|-a    test only published results (supercedes -i)" ;
   my $v_line = "" ;
   my $r_line = "" ;
   my $o_line = "Output goes to STDOUT when -i is used" ;
   my $show_usage = 0 ;

   # ignore most options if running offline
   if ( $reviewhost !~ /^pro.spec.org/ ) {
      $d_line = $a_line = "" ;
      $u_line =~ s/\S*debug\S*// ;
      $u_line =~ s/\S*accepted\S*// ;
      $i_line =~ s/all unpublished/\'$rindir\'/ ;
      $o_line =~ s/STDOUT.*/STDOUT/ ;
      $extra_name = "" ; 

   } elsif ( $extra_name eq "verbose" ) {
      $u_line .= ' [--verbose]' ;
      $v_line = "--verbose|-v     print extra portability reference stuff to terminal" ;

   } elsif ( $extra_name eq "references" ) {
      $u_line .= ' [--references]' ;
      $r_line = "--references|-r  save copy of sw_avail references to pro.spec.org" ;
   } 

   my $extended_usage ;
   $extended_usage = <<EOF;
$u_line 
        $d_line 
        $v_line
        $r_line 
        $i_line
        $a_line 
        --help|-h:       This message
        $o_line 
EOF
   $extended_usage =~ s/^\s*\n//mg ; # remove all extra blank lines


   # Process command line options
   my $rc ;
   if ( $reviewhost !~ /^pro.spec.org/ ) {
      $rc = GetOptions (
                        'indir:s'   => \$rindir,          # location of results
                        'help'      => \$show_usage );

   } elsif ( $extra_name eq "" ) {
      $rc = GetOptions ('debug'     => \$debug,           # boolean: are we in debug mode ?
                        'accepted'  => \$report_accepted, # boolean: are we doing Accepted today?
                        'indir:s'   => \$rindir,          # location of results
                        'help'      => \$show_usage );

   } else {
      $rc = GetOptions ('debug'     => \$debug,           # boolean: are we in debug mode ?
                        'accepted'  => \$report_accepted, # boolean: are we doing Accepted today?
                        $extra_name => \$$extra_option_ref, # boolean: print extra stuff?
                        'indir:s'   => \$rindir,          # location of results
                        'help'      => \$show_usage );
   }

   if ($show_usage) {
      print $extended_usage ;
      exit ;
   }


   # always custom when running offline
   if ( $reviewhost !~ /^pro.spec.org/ ) {
      $report_custom = 1 ;
      $debug = 0 ; # override

   # running on pro.spec.org but requesting custom input set anyway
   } elsif ( $rindir ne "" ) {
      if ( $report_accepted ) {
         say STDERR "\tWARNING: -a supercedes -i; ignoring $rindir" ;
      } else {
         $report_custom = 1 ;
      }
   }

} # common_usage

#----------------------------------------------------------------
# Return the background color which has precedent, according to the contents of the msg
sub choose_bg {
   my $msg = shift; # in: message, which might be empty

   given ($msg) {
      when (/error/i) {return $failcolor} ;
      when (/warn/i) {return $warncolor} ;
      when (/info/i) {return $infocolor} ;
      when (/good/i) {return $goodcolor} ;
      default { return $successcolor } ;
   }
}

#-----------------------------------------------------------------------------
# Report problems
sub complain {
   my $bgcolor = shift ; # in:  warning, error, or OK ?
   my $flavor  = shift ; # in:  flavor text of the error message
   my $detail  = shift ; # in:  detail of error message
   my $out ;             # out: complete error message

   my $comtable = new HTML::Table() ;
   my $comstyle = "margin-left:2em;background-color:$bgcolor;font-family:serif;" ;
   $comtable->setStyle($comstyle);

   given ($bgcolor) {
      when (/$failcolor/) {
         $comtable->addRow("ERROR: $flavor");
         $comtable->addRow("$detail") if $detail ne "" ;
         $out = $comtable ;
      }

      when (/$warncolor/) {
         $comtable->addRow("WARNING: Automatic methods could not detect") ;
         $comtable->addRow("$flavor");
         $comtable->addRow("$detail") if $detail ne "" ;
         $out = $comtable ;
      }

      when (/$infocolor/) {
         $comtable->addRow("INFO: $flavor");
         $comtable->addRow("$detail") if $detail ne "" ;
         $out = $comtable ;
      }

      when (/$goodcolor/) {
         $comtable->addRow("$flavor");
         $comtable->addRow("$detail") if $detail ne "" ;
         $out = $comtable ;
      }

      default {$out = ""}
   }

   return $out;
} # sub complain

#-------------------------------------------------------------------
# Complain if a date field value is earlier/later than a reference date
#    Both dates should be provided in the form bbb-yyyy ; e.g. Apr-2020
#    Order of the dates provided as arguments list does not matter
#    If the reference date is not part of the result, report a URL for its source, if provided
#
#    Example: date field is sw_avail
#    then the reference date might be an OS or compiler release date
#    and the source might be a webpage URL
#
#    Example: date field is test_date
#    then the reference date might be sw_avail or some other data from the same result
#
sub date_compare {
   my $date1      = shift ; #  in: a date
   my $name1      = shift ; #  in: name/field for date1
   my $date2      = shift ; #  in: a date
   my $name2      = shift ; #  in: name/field for date2
   my $bg_ref     = shift ; # out: background color

   my $url = "" ;
   $url = shift if @_ ;

   my $complaint  = ""    ; # returned

   $$bg_ref = $successcolor ;
   my $errmsg = my $detail = "" ;

   if ( $date1 =~ /not found/ or $date1 eq "" ) {
      $$bg_ref = $warncolor ;
      $errmsg = "whether $date2 is correct for unknown $name1" ;
      return ( complain($$bg_ref, $errmsg, "") ) ;

   } elsif ( $date2 =~ /not found/ or $date2 eq "" ) {
      $$bg_ref = $warncolor ;
      $errmsg = "whether $date1 is correct for unknown $name2" ;
      return ( complain($$bg_ref, $errmsg, "") ) ;
   }

   my $date_format = '%b-%Y' ;
   my %d ; # save date and corresponding timestamp
   $d{$name1}{'date'} = $date1 ;
   $d{$name2}{'date'} = $date2 ;
   $d{$name1}{'tm'}  = Time::Piece->strptime($date1, $date_format) ;
   $d{$name2}{'tm'}  = Time::Piece->strptime($date2, $date_format) ;

   my $avail = "unknown" ;
   # we will never compare sw_avail to hw_avail, so only one of these could be true
   if ( $name1 =~ /(\ww_avail)/ ) {
      $avail = $1;
   } elsif ( $name2 =~ /(\ww_avail)/ ) {
      $avail = $1;
   }

   my $otherkey = "" ;
   my $span_cap = 0 ;

   # are we checking either of sw_avail or hw_avail ?
   if ( defined $d{$avail}{'tm'} ) {
      $otherkey = $name1 eq $avail ? $name2 : $name1 ;

      # compared only vs sw_avail
      if ( $otherkey =~ /(build|release|compiler)/i
           and $d{$avail}{'tm'} < $d{$otherkey}{'tm'} ) {
         $$bg_ref = $failcolor ;
         $errmsg = "$avail is earlier than $otherkey" ;
         $detail = "$d{$avail}{'date'} is earlier than" ;

         # reference date has a URL
         if ( $url =~ /http/ ) {
            my $link = "<a href=\"$url\">$d{$otherkey}{'date'}<\/a>" ;
            $detail .= " $link" ;
         } else {
            $detail .= " $d{$otherkey}{'date'}" ;
         }

      # compared vs both sw_avail and hw_avail
      } elsif ( $otherkey =~ /test_date/ ) {
         $span_cap = ONE_MONTH + ONE_MONTH + ONE_MONTH ;

         # could be OK if SUT was run using pre-release software, but that occurs rarely
         if ( $d{'test_date'}{'tm'} < $d{$avail}{'tm'} - $span_cap ) {
            $$bg_ref = $warncolor ;
            $errmsg = "why test_date is earlier than $avail" ;
            $detail = "$d{'test_date'}{'date'} is earlier than $d{$avail}{'date'}" ;
         }
      }

   # all remaining test_date comparisions
   } elsif ( defined $d{'test_date'}{'tm'} ) {
      $otherkey = $name1 eq 'test_date' ? $name2 : $name1 ;

      if ( $otherkey =~ /submission/ ) {
         $span_cap = ONE_DAY + ONE_DAY ; # allow for timezone differences
         if ( $d{$otherkey}{'tm'} < $d{'test_date'}{'tm'} - $span_cap ) {
            $$bg_ref = $failcolor ;
            $errmsg = "$otherkey is earlier than test_date" ;
            $detail = "$d{$otherkey}{'date'} is earlier than $d{'test_date'}{'date'}" ;
         }
      }
   }

   if ( $$bg_ref ne $successcolor ) {
      $complaint =  complain($$bg_ref, $errmsg, $detail) ;
   }
   return $complaint ;

} # sub date_compare

#----------------------------------------------------------------
# Return array of directories that contain the results we will report about
sub dirs_to_report {
   my $outfile  = shift ; # in: pathname of output file

   my @unpub_dirs = qw{UnderReview PreReview ReReview Pending/2* };
   my @pub_dirs ;
   my @dirs_to_search ;
   
   # normal operation, after submission
   if ( ! $report_custom ) {
      chdir  $submittop or die "huh?";

      if ($suite eq "cpu2006") {  # late 2011 is the beginning of sysinfo records
         @pub_dirs = qx{ls -d Accepted/res2011q4 Accepted/res201[2-9]*} ;
#        @pub_dirs = qw{Accepted/res2013*} ; # small accepted set, for debugging
      } else {
         @pub_dirs = qw{Accepted} ;
#        @pub_dirs = qw{Accepted/res*} ; # for debugging
      }

      if ( $outfile =~ /all/ ) {
         @dirs_to_search = (@unpub_dirs, @pub_dirs) ;
      } elsif ($report_accepted) {
         @dirs_to_search  = @pub_dirs ;
      } else {
         @dirs_to_search  = @unpub_dirs ;
      }

   # override if we are using a special input set
   } else {
      @dirs_to_search = $rindir ;
      if ( -e $rindir ) {
         say STDERR 'Searching ' . $rindir . ' for results' if $debug ;
      } else {
         say STDERR 'Directory '. $rindir . ' does not exist.' ;
      }
   
      if ( $report_accepted and $rindir !~ /$submittop\/Accepted/ ) {
         say STDERR $rindir . ' does not contain Published results => Ignoring -a' ;
         $report_accepted = 0 ;
      }
   }

   # since Pending may be multiple dirs, put them last
   # use glob rather than ls; the latter would complain if empty
   my @dirs_to_report = () ;
   foreach ( @dirs_to_search ) {
      foreach ( glob "$_" ) {
         push (@dirs_to_report, $_ ) if (-d $_) ;
      }
   }

   return @dirs_to_report ;
} # sub dirs_to_report

#-------------------------------------------------------------------
# Check date format. We do not want strptime to throw an exception later in the code
#    Return empty string if date does not conform to a recognized format
#
sub eval_date {
   my $date = shift ;
   return "" if !defined $date or $date eq "" ;
   my $date_format = $date =~ /\w\w\w-/ ? '%b-%Y' : '%m-%Y' ;

   eval {
      my $tp = Time::Piece->strptime($date, $date_format);
      $date = $tp->monname . "-" . $tp->year ;
      1 ;
   } or do {
      my $error = $@ || 'Unknown failure';
      warn "could not parse '$date' - $error" if $debug ;
      $date = "" ; # date was not valid
   };

   return $date ;
} # sub eval_date

#----------------------------------------------------------------
sub exit_fail       # exit, *maybe* removing crud
{
   file_clean_at_fail();
   exit 1;
}

#----------------------------------------------------------------
sub exit_success   # move files into place and exit
{
# uses globals debug, debug_ext, files_written, fh_written, tmp_ext
   #
   init_review_tools();          # no-op if already done
   #
   print "\nExiting $BASE0\n" if $debug; 
   for my $file (@files_written) {

      exit 0 if $file =~ /STDOUT/ ; # custom output
      close $fh_written{$file} if defined $fh_written{$file};
      print "Closed $file\n" if $debug;
      (my $notmp = $file) =~ s{.$tmp_ext$}{};
      if ($notmp ne $file) {
         my $cmd = "mv $file $notmp";
         if ($debug) {
            my $tmp_columns = $columns;
            my $initial     = "   Moving it:  ";
            my $li          = length $initial;
            my $subsequent  = " "x$li;
            if (($li + 2 + length $cmd) > $columns) {
               $columns = $li + 2 + length $file;
            }
            print wrap($initial, $subsequent, $cmd), "\n";
            $columns = $tmp_columns;
         }
         system $cmd;
      }
   }
   exit 0;
}

#----------------------------------------------------------------
sub file_clean_at_fail       # *maybe* remove crud
#      Usage: 
#            $SIG{__DIE__}      = \&file_clean_at_fail;
{
   #
   init_review_tools();          # no-op if already done
   #
   print "\nFatal error, exiting $BASE0..."; 
   if ($debug) {
      if (@files_written) { 
         exit 1 if $files_written[0] =~ /STDOUT/ ; # custom output
         print "files left behind are:\n   ", join ("\n   ", @files_written), "\n";
         for my $file (@files_written) {
            close $fh_written{$file} if defined $fh_written{$file};
         }
      }
      print "\n";
   } else {
      if (@files_written) {
         exit 1 if $files_written[0] =~ /STDOUT/ ; # custom output
         print "removing temporaries; set \$debug to keep them";
      }
      print "\n";
      for my $file (@files_written) {
         close $fh_written{$file} if defined $fh_written{$file};
         system "rm -f '$file'";
      }
   }
}

#----------------------------------------------------------------
sub get_result_files # return array of result files with desired extension
{
   my $dir             = shift ; # in: directory we are searching
   my $report_accepted = shift ; # in: are we looking for published results?
   my $ext             = shift ; # in: file extension

   my @files ;
   my $dest ;

   # are we checking submitted results ?
   if ( ! $report_custom ) {
      $dir = "$submittop/$dir" ;
   }

   if ( ! $report_accepted ) {
      $dest  = "$dir";
      die "Oh! $dest $!" unless(chdir($dest)) ;
      @files = glob "*$ext";

   # do not sort published by subdirectory
   } else {
      # all cpu2017 dirs need this res* appended,
      # but for cpu2006 sometimes this sub will be called 
      # to run on only a subset of Accepted/res dirs 
      # (e.g. only those results that include sysinfo output)
      # and each dir in such a list will already include "res" .
      $dir .= "/res\*/" if $dir !~ /res/i ; 

      foreach my $subdir ( glob "$dir/a*" ) {
         $dest  = "$subdir";
         die "Oh! $subdir: $!" unless(chdir($dest)) ;
         my @subfiles = glob "*$ext";
         foreach (@subfiles) {
            push ( @files, "$subdir/$_" ) ;
         }
      }
   }
   say STDERR "Did not find any results in $reviewhost\/$dir" if ( ! scalar @files and $report_custom ) ;
   return @files ;
} # get_result_files

#----------------------------------------------------------------
sub init_review_tools  # If you undef any of these, forces re-init of all.
{
   return if
   ( $pkg_initialized == 1
      #
      && defined ( $BASE0         ) &&  $BASE0          ne ""
      && defined ( $debug         ) &&  $debug          ne ""
      && defined ( $debug_ext     ) &&  $debug_ext      ne ""
      && defined ( $report_accepted ) &&  $report_accepted  ne ""
      && defined ( $report_custom ) &&  $report_custom  ne ""
      && defined ( $start_time    ) &&  $start_time     ne ""
      && defined ( $suite         ) &&  $suite          ne ""
      && defined ( $tmp_ext       ) &&  $tmp_ext        ne ""
      && defined ( $TMPDIR        ) &&  $TMPDIR         ne ""
      #
      && defined ( $outroot       ) &&  $outroot        ne ""
      && defined ( $outurlroot    ) &&  $outurlroot     ne ""
      && defined ( $pub_dir       ) &&  $pub_dir        ne ""
      && defined ( $reviewhost    ) &&  $reviewhost     ne ""
      && defined ( $rindir        ) &&  $rindir         ne ""
      && defined ( $submittop     ) &&  $submittop      ne ""
      && defined ( $submiturlroot ) &&  $submiturlroot  ne ""
      && defined ( $unpub_dirs    ) &&  $unpub_dirs     ne ""
      && defined ( $failcolor     ) &&  $failcolor      ne ""
      && defined ( $warncolor     ) &&  $warncolor      ne ""
      && defined ( $infocolor     ) &&  $infocolor      ne ""
      && defined ( $goodcolor     ) &&  $goodcolor      ne ""
      && defined ( $successcolor  ) &&  $successcolor   ne ""
      && defined ( $sep           ) &&  $sep            ne ""
   );
   #
   $BASE0           = eval('$' . caller() . "::BASE0")      || basename $0;
   $debug           = eval('$' . caller() . "::debug")      || ($BASE0 =~ m{debug});  
   $debug_ext       = eval('$' . caller() . "::debug_ext")  || "debug";
   $report_accepted = eval('$' . caller() . "::report_accepted")  || 0 ;
   $report_custom   = eval('$' . caller() . "::report_custom")    || 0 ;
   $start_time      = eval('$' . caller() . "::start_time") || localtime();
   $suite           = eval('$' . caller() . "::suite")      || "cpu2017";
   $tmp_ext         = eval('$' . caller() . "::tmp_ext")    || "tmp";
   $TMPDIR          = eval('$' . caller() . "::tmp_ext")    
                      || defined($ENV{"TMPDIR"}) ? $ENV{"TMPDIR"} : "/tmp" . getlogin();
   mkpath $TMPDIR;
   #
   $outroot         = "/spec/pro/osg/cpu/$suite/review";
   $submittop       = "/spec/pro/osg/submit/$suite";
   $reviewhost      = hostname() ;
   $rindir          = eval('$' . caller() . "::rindir") || ($reviewhost =~ /^pro.spec.org/ ? "" : ".") ;
   #
   my @rsfurlfixup  = ("/spec/pro/", 
                      "https://pro.spec.org/private/");
   ($outurlroot     = $outroot)   =~ s{$rsfurlfixup[0]}{$rsfurlfixup[1]};
   ($submiturlroot  = $submittop) =~ s{$rsfurlfixup[0]}{$rsfurlfixup[1]};
   $pub_dir         = "Accepted";
   $unpub_dirs      = "UnderReview Pending ReReview PreReview";
   $failcolor       = "#fdb0b0"; # pink
   $warncolor       = "#f5f292"; # yellow
   $infocolor       = "#c6e2ff"; # blue
   $goodcolor       = "#98e598"; # green
   $successcolor    = "white";   # white
   $sep             = "____";    # series of underscores
   #
   $pkg_initialized = 1;
}

#----------------------------------------------------------------
# Log messages
#
sub Log {

  my ($lvl, @msgs) = @_;

  print @msgs;

}

#----------------------------------------------------------------
# read %problems, and generate Table of Problems
sub make_top {
   my $altproblems_ref  ; # in: optionals alternate list of problems

   my %contents ; # data to include in the TOP
   if ( scalar @_ == 0 ) {
      %contents = %problems ;
   } else {
      ($altproblems_ref) = shift ;
      %contents = %$altproblems_ref ;
   }
   my $out ; # will be output
   my $style = 'text-align:left;white-space;nowrap;' ;
   my $boxstyle = "$style;vertical-align:top;border:thin solid gray;" ;
 
   $out = "<h3>Table of Problems</h3><br>\n" ;

   if (! %contents) {
      $out .= "<p>No problems seen by automatic methods, but please use the human eye to check these!</p>\n" ;
   } else {

      my $ttable = new HTML::Table( -style=>"$boxstyle; table-layout: fixed" ) ; # table of problems
      my $trow = 1 ;
      my $detail ;

      # reports sorted by dir/some field/who submitted
      if ( $report_title =~ /cross|thread|main memory/i ) {
         $detail = "Directory (Links go problems with results submitted by that sponsor.)" ;

      # reports sorted by dir/who submitted/some field
      } else {
         $detail = "Directory (Links go to _first_ problem in a section for that sponsor.)" ;
      }

      $ttable->addRow("Sponsor", "Submitter", $detail ) ;
      $ttable->setRowStyle($trow, "font-weight: bold;") ;

      foreach my $who ( sort keys %contents ) {
         (my $sponsor, my $submitter) = split $sep, $who;
         $submitter = $sponsor if ! defined $submitter ;
         $trow++ ;
         my $ptable = new HTML::Table ; # table of problems within a section
         my $prow = 0 ;
         foreach my $dir ( sort keys %{$contents{$who}} ) {
            my @probs = split( / /, $contents{$who}{$dir} ) ;

            $prow++ ;
            my $pcol = 1 ;
            $ptable->addRow($dir, "", "", "") ;
            foreach my $prob (@probs) {
                $pcol++ ;
               (my $bg, my $flavor) = split (/$sep/, $prob) ;

               # link to first occurence
               my $idlink = '<a href="#' . $submitter . "_$dir" . "_$flavor" ;
               given ($bg) {
                  when ($failcolor) { $idlink .= '_err">' }
                  when ($warncolor) { $idlink .= '_warn">' }
                  when ($infocolor) { $idlink .= '_info">' }
                  when ($goodcolor) { $idlink .= '_good">' }
                  default { $idlink .= '">' }
               }

               # must put each link on a new line so reviewmap tool can see color for each
               $idlink .= $flavor . '</a>' . "\n" ; 

                
               # table cell will not wrap when list of links is long, so force a new row
               if ( $pcol % 7 == 0 ) {
                  $prow++ ;
                  $pcol = 2 ;
                  $ptable->addRow("", $idlink) ;

               } else {
                  $ptable->setCell($prow, $pcol, $idlink) ;
               }
               $ptable->setCellBGColor($prow, $pcol, $bg) ;
            }
         }

         $trow++ ;
         $ttable->addRow($sponsor, $submitter, $ptable) ;
         $ttable->setColClass(1, "name") ;
         $ttable->setColClass(2, "name") ;
      }
      $out .= "$ttable" ;
   }

   $out .= "<div id=\"ETOP\"></div>" ; # mark end of Table of Problems for reviewmap tool
   return $out ;
} # make_top

#----------------------------------------------------------------
# numeric sort
# presumes caller is in main !
sub numerically { $::a <=> $::b; }

#----------------------------------------------------------------
sub open_outfile  # open, adjusting name; create outdir if needed
{
#
# Synopsis
#             use IO::Handle;
#             my $fh             = IO::Handle->new();
#             my $filename       = "/mumble/foo/mumble";
#             my $adjusted_name;
#             $adjusted_name     = open_outfile($fh, $filename);
#
#  Returns 
#      adjusted name with 'debug' if needed, '.tmp' while in progress
#
   my $fh    = shift;   # in: caller creates handle with 
                        #     my $handle = IO::Handle->new();
   my $fname = shift;   # in: requested name;  we will add to it.

   my $new_name; 

   init_review_tools();          # no-op if already done

   # normal operation, after submission
   if ( $fname !~ /STDOUT/ ) {
      my $dirname = dirname($fname);
      mkpath $dirname if (! -d $dirname);

      my $add = $debug ? ".$debug_ext" : "";
      if ($fname =~ m{^(.*)\.(\S+)}) { # has a dot and extension?
         $new_name = "$1$add.$2";      # mumble.debug.html
      } else {
         $new_name = "$fname$add";     # mumble.debug
      }

      $new_name .= ".$tmp_ext" if $tmp_ext;
      print "Opening $new_name for output\n" if $debug;
      open $fh, ">$new_name" or die "Cannot open $new_name:\n$!\n";

   # override if we are using a special input set
   } else {
      $report_custom = 1 ;
      open($fh, '>&', \*STDOUT) or die;
      $new_name = $fname ;
   }

   push @files_written, $new_name;
   $fh_written{$new_name} = $fh;
   return $new_name;
}

#----------------------------------------------------------------
sub get_who  # combine test_sponsor with submitter's email
{
   my $sponsor    = shift ; # test_sponsor
   my $submitter  = shift ; # result submitter

   # shorten if the important part is present in between angle brackets
   # "Wangbo (tody, ITAppServerProduct&IntegrationDevelopment)" <tody.wang@huawei.com>
   if ($submitter =~ m{<(\S+\@\S+)>}) {
            $submitter = $1;
   }

   return short_company($sponsor) . "$sep$submitter";
}

#----------------------------------------------------------------
sub rsfnum  # return abbreviated rsf number 
# Arguments:  file  - string of form [dir/]...mumble-nnnnn.rsf
#             when  - (optional) truncate dirstrings: 
#
#                     "always"  - chops dirs
#                     "never"   - keeps dirs
#                     "default" - keeps dirs
#
# examples of default:
#       For: PreReview/cpu2006-20130421-25691
#   Returns: PreReview/25691
#
#       For: Pending/20130507/cpu2006-20130421-25691.rsf
#   Returns: Pending/20130507/25691
#
#       For: UnderReview/cpu2006-20130421-25691.rsf
#   Returns: UnderReview/25691
#
{
   my $rsf   = shift;
   my $when  = "default";
   $when     = shift if @_;
   my $start;
   { no warnings; $start = $suite || '[a-z]+\d{4}'; } # default, match mumble2015
   
   if ($rsf =~ m{^(.*(Accepted|Pending|PreReview|ReReview|UnderReview|Withdrawn).*)/$start-\d{8}-(\d+).rsf$}) {
      my $dir_path = $1;
      my $key_dir  = $2;
      my $num      = $3;
      if ($when eq "always") {
         return $num;
      } elsif ($when eq "never") {
         return "$dir_path/$num";
      } elsif ($when eq "default") {
         return "$dir_path/$num";
      }
   }
   # the only path leading here should be when we fail to recognize our inputs
   return $rsf;
}

#-------------------------------------------------------------------
# Generate a link to a submitted SPEC result's html file
# For a local file, just print the filename instead
# BROKEN if custom input diretory = a submitted directory
#
sub result_link {
   my $dir    = shift ; # in: directory
   my $result = shift ; # in: result file

   my $result_num = "" ;
   my $ext = "" ;
   if ($result =~ m/$suite-\d{8}-(\d+).(\w+)$/) {
      $result_num = $1;
      $ext = $2 ;
   } 

   (my $html = $result) =~ s/.$ext/.html/ ;
   my $link ;
   if ( $reviewhost !~ /^pro\.spec\.org/ ) {
      $link = "$dir\/$result<br>" ;

   } elsif ( $html !~ /$submittop/ ) {
      
      $link =  "<a href=\"$submiturlroot/$dir/$html\">$result_num&nbsp;</a>" ;

   } else {
      $link =  "<a href=\"$html\">$result_num</a>&nbsp;" ;
      $link =~ s/$submittop/$submiturlroot/ ;
   } 
   return ($link) ;
}

#----------------------------------------------------------------
# abbreviate test_sponsor, vendor, etc.
sub short_company  
{
   my $sponsor = shift ;

   # examples: New H3C, Intel Corporation
   if ($sponsor =~ /(new|intel|hitachi|china|peng)\s*(\S+)/i ) {
     $sponsor = "$1 $2" ;

   } elsif ( $sponsor =~ /^\s*(\S+)/ ) {
      $sponsor = $1 ;
   }

   $sponsor =~ s/Corporation/Corp/ ;
   $sponsor =~ s/Academy/Acad/ ;

   return $sponsor ;
}


#----------------------------------------------------------------
sub init_html_vars # Setup Jeff-Reilly-requested style elements
{
# This is last to make it easy to search for
#
# SYNOPSIS
#   init_html_vars($report_title, $additional_styles, $more_preface);
#
#  Parameters
#      $report_title      input
#      $additional_styles input, optional
#      $more_preface      input, optional
#  Returns
#      text from top of document through <h1>
# Globals out
#      $html_finish,      bottom of document </body> etc
#      $report_title,     title of review report
#      $report_start,     "report starts here:"
#      $make_changes_unpub     how to fix
#      $make_changes_accepted  ditto
#  Globals in
#      $debug         in
#      $debug_ext     in
#      $suite         in
#      $start_time    in
#
   $report_title = shift;
   my $additional_styles = "";;
   my $more_preface      = "";
   $additional_styles = shift if @_;
   $more_preface      = shift if @_; 
   #
   init_review_tools();          # no-op if already done
   #
   my $body_color  = "background:white;";
   my $body_border = "";
   if ($debug) {
      $body_color  = "background:#ffffec;";
      $body_border = "border-right:10px yellow solid;";
   }

   my $report_url; # for pointing out location of many reports
   (my $allcaps_suite = $suite) =~ s/cpu/CPU/ ;

   if ($suite =~ /cpu20\d\d/) { 
      # cpu2017 has a wiki page that is an index
      $report_url = "https://pro.spec.org/private/wiki/bin/view/CPU/ReviewReports";
   } else {
      # fallback: the report rootdir 
      $report_url = $outurlroot;
   }

   $make_changes_accepted = <<EOF;
<p>Because these results have been Accepted, any updates must be reviewed by the CPU subcommittee, and, if
approved, would be implemented by the SPEC Editorial staff</p>   
EOF
   $make_changes_unpub = <<EOF;
   <h3>If You Need to Make Changes</h3>

   <ul> 
      <li class="snugbot">If you have result submissions on this page that
      need to be edited, please see the <a
      href="https://pro.spec.org/private/wiki/bin/view/CPU/SubmitterGuide">SubmitterGuide</a>
      to learn how to edit them. </li> 

      <li class="snugtop"><span style="color:red;"><b>ATTENTION: Do not
      </b></span> send your result file to the SPEC CPU subcommittee alias;
      use the alias described in the SubmitterGuide!</li>
   </ul>
EOF

   if ( $report_title =~ /cpu names/i or $report_title =~ /duplicates/i or $report_title =~ /equiv/i) {
      $make_changes_unpub =~ s/Make Changes/Make Changes to Unpublished results/ ;
   }

   $report_start = <<EOF;
   <p style="margin-top:3em; border:solid gray; border-width:thin 0em;">
   Report starts here:</p>

EOF

   # fix pathnames
   $more_preface =~ s{$outroot}{$outurlroot}g ;

   # enhance title + how to fix results
   $report_title .= " ($allcaps_suite" ;

   if ( $more_preface =~ /(results found in\s*\S*)/ ) { # custom
      $report_title .= " $1)" ;

   } elsif ( $more_preface =~ /you have selected:\s*(.*)/i) {
      $report_title .= " $1)" ;

   } elsif ( $more_preface =~ /report includes:\s*(.*)/i ) {
      $report_title .= " $1)" ;

   } elsif ($report_accepted) {
      $report_title .= " published)" ;

   } else {
      $report_title .= " unpublished)";
   }

   if ($report_accepted and $report_title !~ /cpu names/i ) {
      $more_preface .= $make_changes_accepted;
   } else {
      $more_preface .= $make_changes_unpub;
   }

   (my $nohtml_title = $report_title) =~ s{<[^>]+>}{}g;

   if ($debug) {
      $report_title = '<h1 style="color:red;">' . "$report_title debug</h1>" ;
   } else {
      $report_title = "<h1>$report_title</h1>" ;
   }

   my $page_header = <<EOF;
<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN"
    "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">
    <html xmlns="http://www.w3.org/1999/xhtml" xml:lang="en" lang="en">
<head>
<title>$nohtml_title</title>

<link rel="STYLESHEET" href="$outurlroot/css/review-style.css" type="text/css" />

<style type="text/css">
$additional_styles
</style>

</head>

<body style="$body_color $body_border">

<p class="preface">Updated: $start_time (SPEC server timezone, east coast USA, 
same as Washington, DC)
<br />This is one of several 
<a href="$report_url"
target="_blank">Review Reports</a> which are intended to assist both 
submitters and reviewers for $suite by making it easier to spot 
unexpected differences or unusual fields.
</p> 

$report_title

$more_preface

EOF

   $html_finish = <<EOF;

<!-- Improve probability that using the table of contents will cause the
     desired item to be at the top, even if using tall windows -->
   <p style="margin:40em 2em;">This space intentionally left blank.</p>
   <p>&nbsp;</p>

</body>
</html>
EOF

   return $page_header . $report_start ;
}

#-------------------------------------------------------
1;
