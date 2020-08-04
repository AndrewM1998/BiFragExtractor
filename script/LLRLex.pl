# !/usr/bin/env perl

# LLRLex.pl: this script implements the Log-Likelihood-Ratio (LLR) lexicon extraction method
# described in the following paper

# Dragos Stefan Munteanu and Daniel Marcu
# Extracting parallel sub-sentential fragments from non-parallel corpora. 
# In Proceedings of the 21st International Conference on Computational Linguistics (ACL 2006)

use strict;
use utf8;
use Getopt::Long;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my $THRESHOLD = 0.0000001;

my (%opt); GetOptions(\%opt, 'in_path=s', 'out_path=s');

my $in_path = $opt{in_path};
my $out_path = $opt{out_path};

&main();

sub main {
    my ($fr_line_array, $en_line_array, $align_line_array) = &read_input($in_path);
    my ($co_fr_count_hash, $co_en_count_hash, $co_fr_en_hash, $co_en_fr_hash) = &memorize($fr_line_array, $en_line_array, $align_line_array);

    my ($f2e_pos_pair_array, $f2e_pos_score_array, $f2e_neg_pair_array, $f2e_neg_score_array) = &calc_LLR($co_fr_count_hash, $co_en_count_hash, $co_fr_en_hash);
    my ($e2f_pos_pair_array, $e2f_pos_score_array, $e2f_neg_pair_array, $e2f_neg_score_array) = &calc_LLR($co_en_count_hash, $co_fr_count_hash, $co_en_fr_hash);

    my ($norm_f2e_pos_pair_array, $norm_f2e_pos_res_hash) = &normalize($f2e_pos_pair_array, $f2e_pos_score_array);
    my ($norm_f2e_neg_pair_array, $norm_f2e_neg_res_hash) = &normalize($f2e_neg_pair_array, $f2e_neg_score_array);
    my ($norm_e2f_pos_pair_array, $norm_e2f_pos_res_hash) = &normalize($e2f_pos_pair_array, $e2f_pos_score_array);
    my ($norm_e2f_neg_pair_array, $norm_e2f_neg_res_hash) = &normalize($e2f_neg_pair_array, $e2f_neg_score_array);

    my $out_f2e_pos_file = "$out_path/LLR.f2e.pos";
    &output($out_f2e_pos_file, $norm_f2e_pos_pair_array, $norm_f2e_pos_res_hash, 'f2e');
    my $out_f2e_neg_file = "$out_path/LLR.f2e.neg";
    &output($out_f2e_neg_file, $norm_f2e_neg_pair_array, $norm_f2e_neg_res_hash, 'f2e');
    my $out_e2f_pos_file = "$out_path/LLR.e2f.pos";
    &output($out_e2f_pos_file, $norm_f2e_pos_pair_array, $norm_e2f_pos_res_hash, 'e2f');
    my $out_e2f_neg_file = "$out_path/LLR.e2f.neg";
    &output($out_e2f_neg_file, $norm_f2e_neg_pair_array, $norm_e2f_neg_res_hash, 'e2f');
}

sub read_input {
    my ($in_path) = @_;

    my @fr_line_array;
    my @en_line_array;
    my @align_line_array;

    # reading GIZA++ alignment results
    my $in_fr_file = "$in_path/data.fr";
    open(IN_FR, "<:utf8", $in_fr_file);
    while(<IN_FR>) {
	chomp;
	my $fr_line = $_;
	push(@fr_line_array, $fr_line);
    }
    close IN_FR;

    my $in_en_file = "$in_path/data.en";
    open(IN_EN, "<:utf8", $in_en_file);
    while(<IN_EN>) {
	chomp;
	my $en_line = $_;
	push(@en_line_array, $en_line);
    }
    close IN_EN;

    my $in_align_file = "$in_path/aligned";
    open(IN_ALIGN, "<:utf8", $in_align_file);
    while(<IN_ALIGN>) {
	chomp;
	my $align_line = $_;
	push(@align_line_array, $align_line);
    }
    close IN_ALIGN;

    return (\@fr_line_array, \@en_line_array, \@align_line_array);
}

# memorize count and co-occurence info
sub memorize {
    my ($fr_line_array_var, $en_line_array_var, $align_line_array_var) = @_;

    my @fr_line_array = @$fr_line_array_var;
    my @en_line_array = @$en_line_array_var;
    my @align_line_array = @$align_line_array_var;

    my $line_num = @align_line_array;

    my %co_fr_count_hash;
    my %co_en_count_hash;
    my %co_fr_en_hash;
    my %co_en_fr_hash;
    for(my $line_i = 0; $line_i < $line_num; $line_i++) {
        if (($line_i % 1000) == 0) { print STDERR "!"; }

	my $fr_line = $fr_line_array[$line_i];
	my $en_line = $en_line_array[$line_i];
	my $align_line = $align_line_array[$line_i];

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
	    $co_fr_count_hash{$fr_word}++;
	    $co_en_count_hash{$en_word}++;

	    $co_fr_en_hash{$fr_word}{$en_word}++;
	    $co_en_fr_hash{$en_word}{$fr_word}++;
	}

        # unaligned words
        for(my $ei=0;$ei<scalar(@en_word_array);$ei++) {
	    next if defined($ENGLISH_ALIGNED{$ei});
	    my $en_word = $en_word_array[$ei];
	    $co_fr_count_hash{"NULL"}++;
	    $co_en_count_hash{$en_word}++;
	    $co_fr_en_hash{"NULL"}{$en_word}++;
	    $co_en_fr_hash{$en_word}{"NULL"}++;
        }
        for(my $fi=0;$fi<scalar(@fr_word_array);$fi++) {
	    next if defined($FOREIGN_ALIGNED{$fi});
	    my $fr_word = $fr_word_array[$fi];
	    $co_fr_count_hash{$fr_word}++;
	    $co_en_count_hash{"NULL"}++;
	    $co_fr_en_hash{$fr_word}{"NULL"}++;
	    $co_en_fr_hash{"NULL"}{$fr_word}++;
        }

    }

    return (\%co_fr_count_hash, \%co_en_count_hash, \%co_fr_en_hash, \%co_en_fr_hash);
}

sub calc_LLR {
    my ($co_fr_count_hash_var, $co_en_count_hash_var, $co_fr_en_hash_var) = @_;

    my %co_fr_count_hash = %$co_fr_count_hash_var;
    my %co_en_count_hash = %$co_en_count_hash_var;
    my %co_fr_en_hash = %$co_fr_en_hash_var;

    my $co_pair_count_sum = &calc_count_hash_sum(\%co_fr_en_hash);

    my @pos_pair_array;
    my @pos_score_array;

    my @neg_pair_array;
    my @neg_score_array;

    # calculate LLR(fr, en)
    my $i_pos = 0;
    my $i_neg = 0;
    foreach my $fr_word (keys %co_fr_en_hash) {

	my $j_pos = 0;
	my $j_neg = 0;

	foreach my $en_word (keys %{$co_fr_en_hash{$fr_word}}) {

	    my $co_fr_count = $co_fr_count_hash{$fr_word};
	    my $co_en_count = $co_en_count_hash{$en_word};

	    # a: cooc(fr, en)
	    my $co_fr_en_count = $co_fr_en_hash{$fr_word}{$en_word};
	    # b: cooc(non_fr, en)
	    my $co_non_fr_en_count = $co_en_count - $co_fr_en_count;

	    # c: cooc(fr, non_en)
	    my $co_fr_non_en_count = $co_fr_count - $co_fr_en_count;
	    # d: cooc(non_fr, non_en)
	    my $co_non_fr_non_en_count = $co_pair_count_sum - $co_fr_en_count - $co_non_fr_en_count -$co_fr_non_en_count;

	    # p(fr|en) = a/a+b
	    my $co_fr_en_prob = $co_fr_en_count / $co_en_count;
	    my $co_non_fr_en_prob = 1 - $co_fr_en_prob;

	    # p(fr|non_en) = c/c+d
	    my $co_fr_non_en_prob = $co_fr_non_en_count / ($co_fr_non_en_count + $co_non_fr_non_en_count);
	    my $co_non_fr_non_en_prob = 1 - $co_fr_non_en_prob;

	    # p(fr) = a+c/a+b+c+d
	    my $co_fr_prob = $co_fr_count / $co_pair_count_sum;
	    my $co_non_fr_prob = 1 - $co_fr_prob;

	    my $LLR_part_1 = $co_fr_en_count * log($co_fr_en_prob / $co_fr_prob);
	    my $LLR_part_2 = 0;
	    if($co_non_fr_en_count != 0) {
		$LLR_part_2 = $co_non_fr_en_count * log($co_non_fr_en_prob / $co_non_fr_prob);
	    }
	    my $LLR_part_3 = 0;
	    if($co_fr_non_en_count != 0) {
		$LLR_part_3 = $co_fr_non_en_count * log($co_fr_non_en_prob / $co_fr_prob);
	    }
	    my $LLR_part_4 = $co_non_fr_non_en_count * log($co_non_fr_non_en_prob / $co_non_fr_prob);

	    my $LLR = 2 * ($LLR_part_1 + $LLR_part_2 + $LLR_part_3 + $LLR_part_4);

	    my $pair = $en_word . " " . $fr_word;

	    # p(fr|en) > p(fr) <=> p(fr, en) > p(fr)*p(en)
	    if($co_fr_en_prob > $co_fr_prob) {
	    	$pos_pair_array[$i_pos][$j_pos] = $pair;
	    	$pos_score_array[$i_pos][$j_pos] = $LLR;
	    	$j_pos++;
	    } else {
	    	$neg_pair_array[$i_neg][$j_neg] = $pair;
	    	$neg_score_array[$i_neg][$j_neg] = $LLR;
	    	$j_neg++;
	    }
	}
	$i_pos++;
	$i_neg++;
    }
    return (\@pos_pair_array, \@pos_score_array, \@neg_pair_array, \@neg_score_array);
}

# calculate the summation of count in count hash
sub calc_count_hash_sum {
    my ($count_hash_var) = @_;
    my %count_hash = %$count_hash_var;

    my $count_sum = 0;
    foreach my $key_i (keys %count_hash) {
    	foreach my $key_j (keys %{$count_hash{$key_i}}) {
    	    my $count = $count_hash{$key_i}{$key_j};
    	    $count_sum += $count;
    	}
    }

    return $count_sum;
}

# calculate the summation of elements in array
sub normalize {
    my ($pair_array_var, $score_array_var) = @_;
    my @pair_array = @$pair_array_var;
    my @score_array = @$score_array_var;

    my @norm_pair_array;
    my %res_hash;

    my $len = @pair_array;
    for(my $i = 0; $i < $len; $i++) {
	my @sub_pair_array;
	if($pair_array[$i]) {
	    @sub_pair_array = @{$pair_array[$i]};
	}
	my @sub_score_array;
	if($score_array[$i]) {
	    @sub_score_array = @{$score_array[$i]};
	}

	my $sub_len = @sub_pair_array;

	my $sub_score_sum = 0;
	for(my $j = 0; $j < $sub_len; $j++) {
	    $sub_score_sum += $sub_score_array[$j];
	}
	for(my $j = 0; $j < $sub_len; $j++) {
	    my $norm_score = $sub_score_array[$j] / $sub_score_sum;
		push(@norm_pair_array, $sub_pair_array[$j]);
		$res_hash{$sub_pair_array[$j]} = $norm_score;
	}
    }
    return (\@norm_pair_array, \%res_hash);
}

sub output {
    my ($out_file, $norm_pair_array_val, $norm_res_hash_val, $flag) = @_;

    open(OUT, ">:utf8", $out_file);
    my @norm_pair_array = @$norm_pair_array_val;
    my %norm_res_hash = %$norm_res_hash_val;
    my $len = @norm_pair_array;
    for(my $i = 0; $i < $len; $i++) {
	my $norm_pair = $norm_pair_array[$i];
	if($flag eq 'e2f') {
	    my ($en, $fr) = split(/ /, $norm_pair);
	    $norm_pair = $fr . ' ' . $en;
	}
	my $norm_score = $norm_res_hash{$norm_pair};
	if($norm_score > $THRESHOLD) {
	    printf OUT "%s %.7f\n", $norm_pair, $norm_res_hash{$norm_pair};
	}
    }
    close OUT;
}
