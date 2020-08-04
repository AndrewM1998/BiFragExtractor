# !/usr/bin/env perl

# fragment_munteanu.pl: this script implements the parallel fragment extraction method
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

my (%opt); GetOptions(\%opt, 'llr_dir=s', 'len_limit=i', 'smooth_num=i', 'in_path=s', 'out_path=s');

my $llr_dir = $opt{llr_dir};
# shortest fragment length limitation
my $LEN_LIMIT = $opt{len_limit} ? $opt{len_limit} : 3;
# surrounding number for the smoothing filter
my $SURROUNDING_NUM = $opt{smooth_num} ? $opt{smooth_num} : 5;
my $in_path = $opt{in_path};
my $out_path = $opt{out_path};

&main();

sub main() {
    my @fr_sen_array = &read_file("$in_path/data.fr.ext");
    my @en_sen_array = &read_file("$in_path/data.en.ext");

    my $LLR_f2e_pos_hash = &read_LLR("$llr_dir/LLR.f2e.pos");
    my $LLR_f2e_neg_hash = &read_LLR("$llr_dir/LLR.f2e.neg");
    my $LLR_e2f_pos_hash = &read_LLR("$llr_dir/LLR.e2f.pos");
    my $LLR_e2f_neg_hash = &read_LLR("$llr_dir/LLR.e2f.neg");

    my (@fr_fragment_array) = &locate_fragment(\@fr_sen_array, \@en_sen_array, $LLR_f2e_pos_hash, $LLR_f2e_neg_hash, $LEN_LIMIT);
    my (@en_fragment_array) = &locate_fragment(\@en_sen_array, \@fr_sen_array, $LLR_e2f_pos_hash, $LLR_e2f_neg_hash, $LEN_LIMIT);

    my $out_fr_fragment_file = "$out_path/data.fr.frag";
    open(OUT_FR, ">:utf8", $out_fr_fragment_file);
    my $out_en_fragment_file = "$out_path/data.en.frag";
    open(OUT_EN, ">:utf8", $out_en_fragment_file);
    my $fragment_array_len = @fr_fragment_array;

    my $total_fr_num = 0;
    my $total_en_num = 0;
    my $ext_num = 0;
    for(my $i = 0; $i < $fragment_array_len; $i++) {
	my $fr_fragment = $fr_fragment_array[$i];
	my $en_fragment = $en_fragment_array[$i];
	if(($fr_fragment ne "N\/A") && ($en_fragment ne "N\/A")) {
	    my @fr_fragment_cand = split(/\=\|\=/, $fr_fragment);
	    my @en_fragment_cand = split(/\=\|\=/, $en_fragment);

	    $fr_fragment =~ s/\=\|\=/ /g;
	    $fr_fragment =~ s/ \Z//g;
	    $en_fragment =~ s/\=\|\=/ /g;
	    $en_fragment =~ s/ \Z//g;
	    print OUT_FR "$fr_fragment\n";
	    print OUT_EN "$en_fragment\n";

	    my @fr_word_array = split(/ /, $fr_fragment);
	    my $fr_word_num = @fr_word_array;
	    my @en_word_array = split(/ /, $en_fragment);
	    my $en_word_num = @en_word_array;

	    $total_fr_num += $fr_word_num;
	    $total_en_num += $en_word_num;
	    $ext_num++;
	}
    }
    close OUT_FR;
    close OUT_EN;

    my $avg_fr_num = $total_fr_num / $ext_num;
    my $avg_en_num = $total_en_num / $ext_num;
    print STDERR "ext_num:$ext_num, avg_fr_num:$avg_fr_num, avg_en_num:$avg_en_num\n";
}

sub read_LLR() {
    my ($LLR_dir) = @_;

    my %LLR_hash;

    my $LLR_file = $LLR_dir;
    open(IN_LLR, "<:utf8", $LLR_file);
    while(<IN_LLR>) {
	chomp;
	my ($token_1, $token_2, $prob) = split(/ /, $_);
	$LLR_hash{$token_2}{$token_1} = $prob;
    }
    close IN_LLR;

    return (\%LLR_hash);
}

sub locate_fragment() {
    my ($sen_array_1_var, $sen_array_2_var, $LLR_pos_hash_var, $LLR_neg_hash_var, $LEN_LIMIT) = @_;

    my @sen_array_1 = @$sen_array_1_var;
    my @sen_array_2 = @$sen_array_2_var;
    my %LLR_pos_hash = %$LLR_pos_hash_var;
    my %LLR_neg_hash = %$LLR_neg_hash_var;

    my @fragment_array;

    my $sen_array_len = @sen_array_1;
    for(my $i = 0; $i < $sen_array_len; $i++) {
	my $sen_1 = $sen_array_1[$i];
	my $sen_2 = $sen_array_2[$i];

	my @word_array_1 = split(/ /, $sen_1);
	my @word_array_2 = split(/ /, $sen_2);

	my @prob_array;
	my @best_word_array;
	foreach my $word_1 (@word_array_1) {
	    my $best_word_2;

	    my $max_pos_prob = 0;
	    # positive
	    foreach my $word_2 (@word_array_2) {
		if($LLR_pos_hash{$word_1}{$word_2} > $max_pos_prob) {
		    $max_pos_prob = $LLR_pos_hash{$word_1}{$word_2};
		    $best_word_2 = $word_2;
		}
	    }
	    # negative
	    my $max_neg_prob = 0;
	    if($max_pos_prob == 0) {
		foreach my $word_2 (@word_array_2) {
		    if($LLR_neg_hash{$word_1}{$word_2} > $max_neg_prob) {
			$max_neg_prob = $LLR_neg_hash{$word_1}{$word_2};
			$best_word_2 = $word_2;
		    }
		}
	    }
	    # choose probability
	    my $prob;
	    if($max_pos_prob != 0) {
		$prob = $max_pos_prob;
	    } elsif($max_neg_prob != 0) {
		$prob = $max_neg_prob*(-1);
	    } else {
		$prob = -1;
	    }
	    push(@prob_array, $prob);
	    push(@best_word_array, $best_word_2);
	}

	# filtering
	my $filterd_prob_array = &smoothing_filter(\@prob_array, $SURROUNDING_NUM);

	# for(my $i = 0; $i < scalar(@word_array_1); $i++) {
	#     print "$word_array_1[$i] ($best_word_array[$i], $prob_array[$i], $$filterd_prob_array[$i])\n";
	# }

 	my $continuous_positive_index_array = &get_continuous_positive($filterd_prob_array, $LEN_LIMIT);
	my $fragments;
	foreach my $continuous_positive_index (@$continuous_positive_index_array) {
	    my $fragment;
	    my @index_array = split(/ /, $continuous_positive_index);
	    foreach my $index (@index_array) {
		$fragment .= "$word_array_1[$index] ";
	    }
	    $fragment =~ s/ \Z//g;
	    $fragments .= "$fragment\=\|\=";
	}
	if($fragments eq '') {
	    push(@fragment_array, "N\/A");
	} else {
	    # for test
	    # my $sen_num = $i + 1;
	    # $fragments = $sen_num . "\t" . $fragments;

	    push(@fragment_array, $fragments);
	}
    }

    return (@fragment_array);
}

# surrounding_num should be odd number
sub smoothing_filter() {
    my ($prob_array_var, $surrounding_num) = @_;

    my @filterd_prob_array;

    my @prob_array = @$prob_array_var;
    my $prob_array_len = @prob_array;

    my $bias = ($surrounding_num-1) / 2;

    for(my $i = 0; $i < $prob_array_len; $i++) {
	my $filterd_prob = $prob_array[$i];
	for(my $j = $bias; $j > 0; $j--) {
	    if(($i-$j) >= 0) {
		$filterd_prob += $prob_array[$i-$j];
	    }
	    if(($i+$j) < $prob_array_len) {
		$filterd_prob += $prob_array[$i+$j];
	    }
	}
	$filterd_prob = $filterd_prob / $surrounding_num;
	push(@filterd_prob_array, $filterd_prob);
    }
    return (\@filterd_prob_array);
}

sub get_continuous_positive() {
    my ($prob_array_var, $limit_len) = @_;

    my @prob_array = @$prob_array_var;
    my $prob_array_len = @prob_array;

    my @continuous_positive_index_array;
    my $continuous_positive_index;
    my $continuous_positive_num = 0;
    for(my $i = 0; $i < $prob_array_len; $i++) {
	if($prob_array[$i] > 0) {
	    $continuous_positive_num++;
	    $continuous_positive_index .= "$i ";
	} else {
	    if($continuous_positive_num >= $limit_len) {
		$continuous_positive_index =~ s/ \Z//g;
		push(@continuous_positive_index_array, $continuous_positive_index);
	    }
	    $continuous_positive_num = 0;
	    $continuous_positive_index = "";
	}
    }
    # continuous positive till last element
    if($continuous_positive_num >= $limit_len) {
	$continuous_positive_index =~ s/ \Z//g;
	push(@continuous_positive_index_array, $continuous_positive_index);
    }

    return (\@continuous_positive_index_array);
}

sub read_file {
    my ($file) = @_;
    my @line_array;
    open(IN, "<:utf8", $file);
    while(<IN>) {
	chomp;
	push(@line_array, $_);
    }
    close IN;
    return @line_array;
}
