bin/presubmit/

These presubmission review tools may help you organize your submission
    prior to sending it to SPEC.  They are intended
    primarily for use by SPEC OSG members, but others
    may try them out if you wish to.

    WARNING: the official status of these is experimental and support is NOT PROMISED.
        They may be subject to limitations / bugs.

        You are strongly encouraged to use subcheck on your results
        prior to running these presubmit tools
        https://www.spec.org/cpu2017/Docs/runcpu.html#subcheck

        If you run into problems, you may report them -
        see https://www.spec.org/cpu2017/Docs/techsupport.html

        If you are a SPEC OSG member you can check for updates
        to these tools by clicking the link PreSubmit next
        to the agenda page for the CPU subcommittee.

    Table of Contents
       mem4.pl          - checks syntax of hw_memory field
       dimm.pl          - compares hw_memory vs. dmidecode portion of sysinfo
       disk.pl          - checks hw_disk and compares sw_file vs Filesystem portion of sysinfo
       crosscompile.pl  - checks cross compile notes, sw_other, and notes about jemalloc
       bios.pl          - checks fw_bios and mitigation statements
       -----------------------------------------
       localreview.pl   - runs all of the above


       Other Perl code used by the above tools (these are included)
       ------------------------------------------------------------
       Review_util.pm   - utility routines 
       HTML             - HTML::Table module from metacpan.org 
       -------------------------------------------------------
       If you update any of the primary tools, you will probably also need to update Review_util.pm

    I/O
    The scripts read all the .rsf files in one input directory.
    Individual tools output to STDOUT, in HTML format, but
    localreview.pl outputs all the HTML reports to separate filenames in one output directory.

USAGE commands:
   Linux:   localreview.pl     -h
   Windows: localreview.pl.bat -h

