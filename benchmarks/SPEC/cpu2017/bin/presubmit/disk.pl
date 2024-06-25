#!/usr/bin/perl
#
# Print report about the disks subsystem for the SPEC run directories
#
#  Copyright 2020 Standard Performance Evaluation Corporation
#
# No support is provided for this script.
#
#  Author: Julie Reilly
#
# $Id: disk.pl 6548 2020-11-10 16:33:32Z CloyceS $
#
#    JL Reilly 2019 Nov creation (borrowing some from a j.henning prototype)
#                   Dec dirs_to_search is in Review_util.pm
#              2020 Jan use get_result_files()
#                   May use available_reports() and common_usage()
#                       read sysinfo data from .rsf instead of .orig.cfg
#                       sort by dir last instead of first
#                   Jun ^^^^was harder to implement correctly than I thought. 
#                          Bug fix was needed:
#                          it is straightforward to report result numbers, 
#                          but for some nested table layouts there are not enough cells to assign problem ids
#                          unless one creates extra blank cells to accommodate some of the ids
#                   Sep use get_who()
#                       stop reading rsf after sysinfo
#                        
#
use strict;
use warnings;
use IO::Handle;
use v5.10 ; # say
use List::MoreUtils ;
use Env qw(SUITE SPEC);

# need this to locate Review_util and HTML::Table
use FindBin qw($Bin);
use lib $Bin, "$SPEC/bin/common";

use HTML::Table;
# Set several other globals via 'Review_util::init_review_tools' - see
# EXPORT list for the module.
use Review_util;
require 'util_common.pl';

sub build_hwtables ;
sub build_swtables ;
sub gb_capacity ; 
sub read_rsf ;
sub read_sysinfo ;
sub write_preface_disk ;
umask 0002 ;

#----------- globals -----------
our $suite = $SUITE ? $SUITE : "cpu2017" ;

# global data created as we read files, consumed by reporting routines
# 'who' is a composite key: sponsor / submitter, as in Acme / joe@acme.com
my @report ;

use Text::Wrap qw($columns wrap);
$columns = 132;
my $style = 'text-align:left;white-space:nowrap;' ;
my $boldstyle = "$style;font-weight:bold;" ;
my $boxstyle = "$style;vertical-align:top;border:thin solid gray;" ;
my $boldbox = "$boxstyle;font-weight:bold;" ;

my %diskmsg ; # messages
$diskmsg{"capacity"} = 'why size of $SPEC exceeds size of hw_disk' ;
$diskmsg{"notype"} = 'sysinfo filesystem type. Please check manually.' ;
$diskmsg{"rpm"} = 'HDD is missing RPM' ;
$diskmsg{"sata"} = 'Is this SSD or HDD? And if HDD, what is the RPM?' ;
$diskmsg{"type"} = 'sw_file contradicts filesystem type seen by sysinfo' ;
$diskmsg{"units"} = 'Missing units' ;

init_review_tools;
$SIG{__DIE__}      = \&file_clean_at_fail;

#-----------------------------------------------------------------------------------------
# main code starts here
#-----------------------------------------------------------------------------------------

my $outdir = "$outroot/sysinfo" ;

my %disk_file = (
   "unpub" => "$outdir/disk.unpub.html",
   "pub"   => "$outdir/disk.pub.html"
) ;

common_usage ; # parse command line ; show usage if necessary

my $outfile = "STDOUT" ;
if ( ! $report_custom ) { # normal review operation, after submission

   if ($report_accepted) {
      $outfile         = $disk_file{"pub"} ;
   } else {
      $outfile         = $disk_file{"unpub"} ;
   }
}
my $fh = IO::Handle->new();
open_outfile $fh, $outfile ;

say $fh write_preface_disk ;

push (@report, "<html><body>");

my %combo_hw ; # hw_disk
my %combo_sw ; # hw_disk, sw_file, sfilesystem combos

# get data
for my $dir ( dirs_to_report($outfile) ) {
   chomp $dir;
   say "$dir" if ($debug) ;

   # find and read result files
   my $ext = "rsf" ;
   my @files =  get_result_files($dir, $report_accepted, $ext) ;
   next if ! @files;

   for my $rsf (sort @files) {
      my $hw_disk = my $sw_file = my $who = my $sysinfo = "" ;
      read_rsf($rsf, \$hw_disk, \$sw_file, \$who, \$sysinfo) ;

      chomp $rsf;

      my $spec_disk ;
      my $sfilesystem = my $spec_size = "unknown" ;
      read_sysinfo ($rsf, $sysinfo, \$spec_disk) ;
      ($sfilesystem, $spec_size) = split $sep, $spec_disk ;

      my $result_link = result_link($dir,$rsf) ;
      $combo_hw{$who}{$hw_disk}{$dir} .= "$result_link " ;
      $combo_sw{$who}{$hw_disk}{$sw_file}{$sfilesystem}{$spec_size}{$dir}.= "$result_link " ;
   }
}

# sort by submitter
for my $who (sort keys %combo_hw) {
   (my $sponsor, my $submitter) = split $sep, $who;

   # sort by hw_disk
   my $who_row = 1;
   for my $hw_disk ( sort keys %{$combo_hw{$who}} ) {

      push (@report, "<br>" ) ;
      if ($who_row == 1) {
         push (@report, "<p style=\"$boldstyle;font-size:125%\">
         $sponsor&nbsp;&nbsp;&nbsp;Submitter: $submitter
            </p>" ) ;
      } else {
         push (@report, "<p style=\"$boldstyle;\">
            $submitter continued...
            </p>" ) ;
      }

      push ( @report, build_hwtables($who, $hw_disk, $combo_hw{$who}{$hw_disk} ) ) ;
      push ( @report, build_swtables($who, $hw_disk, \%{$combo_sw{$who}{$hw_disk}} ) ) ;
      $who_row++;
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
# Populate hw_disk table
#
sub build_hwtables {
   my $who       = shift ; # input: sponsor and submitter
   my $hw_disk   = shift ; # input: hw_disk

   my $params = shift ; # input 
   my %dir_list = %$params ; # directories
  
   my @complaints ; 
   my $bg = $successcolor ;
   my $detail = ""  ;

   $hw_disk =~ s/\s*$//;

   if ( $hw_disk !~ /gb/i and $hw_disk !~ /tb/i) {
      push(@complaints,  complain($failcolor, $diskmsg{"units"}, $detail))  ;
   }

   if ( $hw_disk =~ /sata/i and $hw_disk !~ /hdd|ssd|rpm|m\.2/i ) {
      push(@complaints,  complain($failcolor, $diskmsg{"sata"}, $detail))  ;
   }

   if ( $hw_disk =~ /hdd/i and $hw_disk !~ /rpm|\d\s*k/i ) {
      push(@complaints,  complain($failcolor, $diskmsg{"rpm"}, $detail))  ;
   }

   my $complaint = "" ;
   foreach (@complaints) {
      $complaint .= $_ ;
   }
   $bg = choose_bg($complaint) ;

   my $htable = new HTML::Table ; # hw table
   my $hrow = 1 ;
   $htable->addRow( "hw_disk: $hw_disk" ) ;
   $htable->setRCellsHead(1, 1) ;

   if ($bg ne $successcolor) {
      my $rtable = new HTML::Table() ; # results table
      my $rrow = 0 ;
      foreach my $dir ( sort keys %dir_list ) {
         $rrow++ ;
         $rtable->addRow("$dir\/", $dir_list{$dir}) ;
   
         my $id = add_prob($bg, $who, "hw_disk_syntax", $dir) ;
         $rtable->setCellAttr($rrow, 1, $id) ;

      }
      $hrow++ ;
      $htable->addRow( $complaint, $rtable) ;
      $htable->setRowBGColor($hrow, $bg) ;
   }
      
   return "$htable" ;
} # sub build_hwtables


#-------------------------------------------------------------------
# Populate sw_file table
#
sub build_swtables {
   my $who       = shift ; # input: sponsor and submitter
   my $hw_disk   = shift ; # input: hw_disk

   my $params = shift ; # input
   my %sw_file_list = %$params ; # filesystem list
  
   my $ftable = new HTML::Table ; # filesystem table
   my $frow = 1 ;
   $ftable->addRow( 'sw_file', 'Filesystem seen by sysinfo') ;
   $ftable->setCellStyle($frow,1, $boldbox) ;
   $ftable->setCellStyle($frow,2, $boldbox) ;

   for my $sw_file (sort keys %sw_file_list) {
    
      my $ttable = new HTML::Table() ; # sysinfo filesystem type table
      my $trow = 0 ;
      for my $sfilesystem ( sort keys %{$sw_file_list{$sw_file}} ) {

         my @dirs ;
         my $stable = new HTML::Table() ; # $SPEC size table
         my $srow = 1 ;
         $stable->addRow( '$SPEC size','Results' ) ;
         $stable->setColNoWrap(1, 1) ;
         for my $spec_size (sort keys %{$sw_file_list{$sw_file}{$sfilesystem}} ) {
            my $bg = $successcolor ;
            my $complaint = my $detail = "" ;
      
            if ( gb_capacity($spec_size) > gb_capacity($hw_disk) ) {
               $detail = "Please check manually." ;
               $complaint = complain($warncolor, $diskmsg{"capacity"}, $detail)  ;
            }
            $bg = choose_bg($complaint) ;

            my $rtable = new HTML::Table() ; # results table
            my $rrow = 0 ;
            foreach my $dir (sort keys %{$sw_file_list{$sw_file}{$sfilesystem}{$spec_size}}) {
               push (@dirs, $dir) ; # save the list to re-use outside the loop, for the extra id table
               $rrow++ ;
               $rtable->addRow("$dir\/", "$sw_file_list{$sw_file}{$sfilesystem}{$spec_size}{$dir}") ;

               if ( $bg ne $successcolor ) {
                  my $id = add_prob($bg, $who, "hw_disk_capacity", $dir) ;
                  $rtable->setCellAttr($rrow, 1, $id) ;
               }
            }

            $srow++ ;
            $stable->addRow("$spec_size $complaint", $rtable) ;
            $stable->setRowBGColor($srow, $bg) ;
            $stable->setCellStyle($srow, 1, $style) ;

         }

         my $bg = $successcolor ;
         my $complaint = my $detail = "" ;
         my $stype = "unknown type" ;
         if ( $sfilesystem =~ /.*\s+(\S*)/ ) {
            $stype = $1; 
            $sfilesystem =~ s/ $stype// ;

            if ( $stype !~ /$sw_file/ ) {
               $detail = "|$sw_file| is not in |$sfilesystem|" if $debug ;
               $complaint = complain($failcolor, $diskmsg{"type"}, $detail) ;
            }

         } else {
            $complaint = complain($warncolor, $diskmsg{"notype"}, $detail) ;
         }

           
         $bg = choose_bg($complaint) ;

         $trow++ ;
         $ttable->addRow( "$sfilesystem<br>$stype $complaint", $stable ) ;

         # assume we have already assigned id to the cell containing dir name
         #    for a different flavor of complaint, so
         #    since we do not want to reprint the result lists here, 
         #    add a new table of blank cells to accommodate new ids
         #    and append it the sysinfo filesystem table
         if ($bg ne $successcolor) {
            my $itable = new HTML::Table() ; 
            $itable->addRow("") ;
            $itable->setRowBGColor(1, $bg) ;
            my $icol = 1 ;

            foreach my $dir ( @dirs ) {
               my $id = add_prob($bg, $who, "sw_file", $dir) ;
               $itable->setCellAttr(1, $icol, $id) ;

               $icol++ ;
               $itable->addCol("") ;
            }

            $ttable->addCol($itable) ;
            $ttable->setRowBGColor($trow, $bg) ;
         }

      } # for $sfilesystem

      $frow++ ;
      $ftable->addRow($sw_file, $ttable) ;
      my $fstyle = 'vertical-align:top;border:thin solid gray;';
      $ftable->setCellStyle($frow, 1, $fstyle) ;
   } # for sw_file
   

   return "$ftable" ;

} # sub build_swtables

#-------------------------------------------------------------------
# Return numerical size of GB on a disk, converting from TB if necessary,
# and accounting for  RAID.
# Reference used for understanding RAID:
#    https://www.microsemi.com/product-directory/raid-controllers/4047-raid-levels
#
sub gb_capacity {
   my $disk       = shift ; # in: size of disk, including units
   my $size_in_gb = 0 ; # number of GB in $disk_size

   if ($disk =~ /([\.\d]+)\s*(G|T)/i) {
      $size_in_gb = $1 ;
      $size_in_gb *= 1000 if $2 eq "T" ;
   }

   if ( $disk =~ /([\.\d]+)\s*x.*raid.*(\d)/i ) {
      my $n = $1 ;
      my $raid = $2 ;
      $size_in_gb *= $n if ($raid == 0) ;
#     $size_in_gb *= $n if ($raid == 5 and $n >= 3 and $n <= 16) ;
#     $size_in_gb *= $n if ($raid == 6 and $n >= 4 and $n <= 32) ;
   }

   return $size_in_gb ;
} # gb_capacity

#-------------------------------------------------------------------
#  Read the result's .rsf (raw) file, and tuck away data from some fields
#  editable by the submitter.
#
sub read_rsf {
   my $rsf                 = shift ; #  in:  file to read
   my $disk_ref            = shift ; # out: contents of hw_disk
   my $sw_file_ref         = shift ; # out: contents of sw_file
   my $who_ref             = shift ; # out: sponsor[sep]submitter
   my $sysinfo_ref         = shift ; # out: sysinfo lines

   my $sponsor = my $submitter = "" ;
   my @compnotes ;

   my $FILE ;
   open ($FILE, "<", $rsf) or say "Could nst open $rsf";
   while (my $rline = <$FILE>) {
      chomp $rline;
      last if $rline =~ /$suite\.results/ ;

      if ($rline =~ /hw_disk[^:]*:\s*(.*)/) {
         $$disk_ref .= "$1 " ;
         
      } elsif ($rline =~ /sw_file[^:]*:\s*(.*)/) {
         $$sw_file_ref .= "$1 " ;
         
      } elsif ($rline =~ /sponsor[^:]*:\s*(.*)/) {
         $sponsor .= "$1 ";
         $sponsor =~ s/\s*$//;
         next;

      } elsif ($rline =~ m{Submitted_by:\s*(.*)}) {
         $submitter = $1;
         $$who_ref = get_who($sponsor, $submitter) ;
       
      } elsif ($rline =~ m{compnotes_sysinfo(\d+):\s*(.*)}) {
         $compnotes[$1] = $2 ;

      }

   } # while
   close $FILE ;

   $$sysinfo_ref = decode_decompress(join('', @compnotes)) ;
   $$sysinfo_ref =~ s/notes_plat_sysinfo_(\d+)://g ;

   # normalize whitespace 
   $$disk_ref =~ s/\h+/ /g;
   $$sw_file_ref =~ s/\h+/ /g;
   $$sw_file_ref =~ s/\s+$// ;

# say "DISK is $$disk_ref" ;

} # sub read_rsf

#-------------------------------------------------------------------
# Tuck away OS info from the result's Sysinfo data
#
sub read_sysinfo {
   my $rsf                  = shift ; #  in: result file
   my $sysinfo              = shift ; #  in: sysinfo data
   my $sysinfo_disk_ref     = shift ; # out: filesystem seen by sysinfo

   my @sysinfo =  split /\n/, $sysinfo ;

   my $in_filesystem = 0 ;
   my @col_headers ;
   my $filesystem = my $size = "unknown" ;
   $$sysinfo_disk_ref = "unknown$sep" . "unknown" ;

   foreach (@sysinfo) {

      $in_filesystem = 1 if /filesystem.*size/i ;
      $in_filesystem = 0 if /Additional information/;

      next unless $in_filesystem ;

      my $sysinfo_disk_line ;

      if ( /(filesystem.*size)/i ) {
         $sysinfo_disk_line = $1 ;
         $sysinfo_disk_line =~ s/\h+/ /g;
         @col_headers = split ' ', $sysinfo_disk_line ;
         next ;

      # for some results the column headers wrap
      } elsif ( /mounted on/i ) {
         next ;

      } elsif ( /\s*(.*)/ and @col_headers) {
         $sysinfo_disk_line = $1 ;
         $sysinfo_disk_line =~ s/\h+/ /g;
         my @data = split ' ', $sysinfo_disk_line ;

         for ( my $i=0; $i< scalar @col_headers; $i++ ) {
            $filesystem = $data[$i] if $col_headers[$i] =~ /filesystem/i ;
            $filesystem .= " &nbsp;&nbsp;&nbsp; $data[$i]" if $col_headers[$i] =~ /type/i ;
            $size = $data[$i] if $col_headers[$i] =~ /size/i ;
            last if $col_headers[$i] =~ /size/i ;
         }
         $$sysinfo_disk_ref = $filesystem . $sep . $size ;
         if ( $$sysinfo_disk_ref =~ /unknown/ ) {
            print "unexpected format: '$rsf $$sysinfo_disk_ref $sysinfo_disk_line'\n";
         }

         last ;
      }

      
   } # while

} # sub read_sysinfo

#-------------------------------------------------------------------
# Write the report header
#
sub write_preface_disk {
   my $title = "Run-time Disk subsystem" ;

   my $more_style = <<EOF;
.snugbot      { margin-bottom:0.1em; }
EOF

   # purpose, explain the concepts and limitations
   my $html_top = <<EOF;

<table>
<tr>

   <td>
   <h3 style="margin-top:.1em;">Purpose of this report</h3>

   <p class="l1">This page shows the disk subsystem for each system under test.
Submissions are sorted by sponsor / hw_disk / sw_file </p>

   <h3>How to read this report</h3>

   <ol class="l1snugbot">
      <li>Does hw_disk include all necessary info?</li>
      <li>Does size of SPEC seen by sysinfo exceed size of hw_disk?</li>
      <li>Is sw_file consistent with File system type seen by sysinfo?</li>
   </ol>

   <h3>Limitations</h3>


   <h3>Unpublished vs. published</h3>

</tr>
</table>
EOF

   $html_top .= available_reports(\%disk_file) ;

   return( init_html_vars($title, $more_style, $html_top) ) ;

} # sub write_preface_disk



