# !/usr/bin/env perl

# combLex.pl: combine all sampLex iterations

use strict;
use utf8;
use POSIX;
use Getopt::Long;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my (%opt); GetOptions(\%opt, 'in_path=s', 'out_path=s', 'iters=i');

my $in_path = $opt{in_path};
my $out_path = $opt{out_path};
my $ITERS = $opt{iters} ? $opt{iters} : 10;

&main();

sub main {
    my %lexicon;
    my %total_fr;
    my %total_en;

    for(my $i = 1; $i <= $ITERS; $i++) {
	print STDERR "reading $in_path/lex.$i\n";
	open(LEX, "<:utf8", "$in_path/lex.$i");
	while(<LEX>) {
	    chomp;
	    my ($we, $wf, $prob) = split(/ /, $_);
	    $lexicon{$wf}{$we} += $prob;
	    $total_fr{$wf} += $prob;
	    $total_en{$we} += $prob;
	}
	close LEX;
    }

    # calculate average number
    my $fr_num;
    my $trans_num;
    open(F2E, ">:utf8", "$out_path/sampLex.f2e");
    open(E2F, ">:utf8", "$out_path/sampLex.e2f");
    foreach my $wf (keys %lexicon) {
	$fr_num++;
	foreach my $we (keys %{$lexicon{$wf}}) {
	    $trans_num++;
	    printf F2E "%s %s %.7f\n",$we, $wf, $lexicon{$wf}{$we}/$total_fr{$wf};
	    printf E2F "%s %s %.7f\n",$wf, $we, $lexicon{$wf}{$we}/$total_en{$we};
	}
    }
    printf STDERR "Average translation number: %.1f\n", $trans_num/$fr_num;
}
