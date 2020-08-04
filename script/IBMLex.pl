# !/usr/bin/env perl

# IBMLex.pl: this script extract IBM model 1 lexicon, see the following URL for detail.
# [http://www.statmt.org/moses/?n=FactoredTraining.GetLexicalTranslationTable]

use strict;
use utf8;
use Getopt::Long;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my (%opt); GetOptions(\%opt, 'in_path=s', 'out_path=s');

my $in_path = $opt{in_path};
my $out_path = $opt{out_path};

&main();

sub main {
    my (%co_fr_count_hash, %co_en_count_hash, %co_fr_en_hash);
    &get_lexical_counts($in_path, \%co_fr_count_hash, \%co_en_count_hash, \%co_fr_en_hash);

    my $out_f2e_file = "$out_path/IBM.f2e";
    my $out_e2f_file = "$out_path/IBM.e2f";

    open(F2E, ">:utf8", $out_f2e_file) or die "ERROR: Can't write $out_f2e_file";
    open(E2F, ">:utf8", $out_e2f_file) or die "ERROR: Can't write $out_e2f_file";
    foreach my $f (keys %co_fr_en_hash) {
	foreach my $e (keys %{$co_fr_en_hash{$f}}) {
	    printf F2E "%s %s %.7f\n",$e,$f,$co_fr_en_hash{$f}{$e}/$co_fr_count_hash{$f};
	    printf E2F "%s %s %.7f\n",$f,$e,$co_fr_en_hash{$f}{$e}/$co_en_count_hash{$e};
	}
    }
    close(E2F);
    close(F2E);
}

sub get_lexical_counts {
    my ($in_path, $co_fr_count_hash, $co_en_count_hash, $co_fr_en_hash) = @_;

    my $in_fr_file = "$in_path/data.fr";
    open(IN_FR, "<:utf8", $in_fr_file);
    my $in_en_file = "$in_path/data.en";
    open(IN_EN, "<:utf8", $in_en_file);
    my $in_align_file = "$in_path/aligned";
    open(IN_ALIGN, "<:utf8", $in_align_file);
    my $line_num = 0;
    while(my $fr_line = <IN_FR>) {
	chomp($fr_line);
	my $en_line = <IN_EN>;
	chomp($en_line);
	my $align_line = <IN_ALIGN>;
	chomp($align_line);

        if (($line_num++ % 1000) == 0) { print STDERR "!"; }

	my @fr_word_array = split(/ /, $fr_line);
	my @en_word_array = split(/ /, $en_line);

        my (%FOREIGN_ALIGNED, %ENGLISH_ALIGNED);
	
	my @align_co_array = split(/ /, $align_line);
	foreach my $align_co (@align_co_array) {
	    my ($fr_index, $en_index) = split(/\-/, $align_co);
	    my $fr_word = $fr_word_array[$fr_index];
	    my $en_word = $en_word_array[$en_index];

	    # local counts
	    $FOREIGN_ALIGNED{$fr_index}++;
	    $ENGLISH_ALIGNED{$en_index}++;

	    # global counts
	    $$co_fr_count_hash{$fr_word}++;
	    $$co_en_count_hash{$en_word}++;
	    $$co_fr_en_hash{$fr_word}{$en_word}++;
	}

        # unaligned words
        for(my $ei=0;$ei<scalar(@en_word_array);$ei++) {
	    next if defined($ENGLISH_ALIGNED{$ei});
	    my $en_word = $en_word_array[$ei];
	    $$co_fr_count_hash{"NULL"}++;
	    $$co_en_count_hash{$en_word}++;
	    $$co_fr_en_hash{"NULL"}{$en_word}++;
        }
        for(my $fi=0;$fi<scalar(@fr_word_array);$fi++) {
	    next if defined($FOREIGN_ALIGNED{$fi});
	    my $fr_word = $fr_word_array[$fi];
	    $$co_fr_count_hash{$fr_word}++;
	    $$co_en_count_hash{"NULL"}++;
	    $$co_fr_en_hash{$fr_word}{"NULL"}++;
        }
    }
    close IN_FR;
    close IN_EN;
    close IN_ALIGN;
}
