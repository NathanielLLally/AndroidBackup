#!/usr/bin/perl

use warnings;
use strict;
use lib '/home/nate/lib';
use Archive::AndroidBackup;
use Getopt::Std;

my %o;
getopts('c:tvx', \%o);

sub printUsage
{
  print <<EOL
    $0 -[ctvx] file
      -c create
      -t table of contents
      -v verbose
      -x extract

EOL

}

my $ab = new Archive::AndroidBackup;
my $file;
if (defined $ARGV[0] and -e $ARGV[0]) {
  $file = $ARGV[0];
}

if (exists $o{x}) {
  $ab->read($file);
  $ab->extract;
} elsif (exists $o{t}) {
  $ab->read($file);
  foreach ($ab->list_files) {
    print "$_\n";
  }
} elsif (exists $o{c}) {
  my $dir = $file;
  $file = $o{c};
  $ab->add_dir($dir);
  if (exists $o{v}) {
    foreach ($ab->list_files) {
      print "$_\n";
    }
  }
  $ab->write($file);
} else {
  printUsage;
}

