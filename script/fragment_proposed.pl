# !/usr/bin/env perl

# fragment_proposed.pl: this script implements the parallel fragment extraction method
# described in the following paper

# Chenhui Chu, Toshiaki Nakazawa and Sadao Kurohashi:
# Accurate Parallel Fragment Extraction from Quasi–Comparable Corpora using 
# Alignment Model and Translation Lexicon
# Proceedings of the 6th International Joint Conference on Natural Language Processing 
# (IJCNLP2013, short paper), pp.1144-1150, Nagoya, Japan, (2013.10).

use strict;
use utf8;
use Getopt::Long;

binmode STDIN, ":utf8";
binmode STDOUT, ":utf8";
binmode STDERR, ":utf8";

my (%opt); GetOptions(\%opt, 'lex_type=s', 'lex_dir=s', 'len_limit=i', 'smooth_num=i', 'in_path=s', 'out_path=s');

my $lex_type = $opt{lex_type} ? $opt{lex_type} : 'LLR';
my $lex_dir = $opt{lex_dir};
# shortest fragment length limitation
my $LEN_LIMIT = $opt{len_limit} ? $opt{len_limit} : 3;
# surrounding number for the smoothing filter
my $SURROUNDING_NUM = $opt{smooth_num} ? $opt{smooth_num} : 5;
my $in_path = $opt{in_path};
my $out_path = $opt{out_path};

my $LEX_e2f_file;
my $LEX_f2e_file;
my $LEX_e2f_neg_file;
my $LEX_f2e_neg_file;

if($lex_type eq 'IBM') {
    $LEX_e2f_file = "$lex_dir/IBM.e2f";
    $LEX_f2e_file = "$lex_dir/IBM.f2e";
} elsif($lex_type eq 'LLR') {
    $LEX_e2f_file = "$lex_dir/LLR.e2f.pos";
    $LEX_f2e_file = "$lex_dir/LLR.f2e.pos";
    $LEX_e2f_neg_file = "$lex_dir/LLR.e2f.neg";
    $LEX_f2e_neg_file = "$lex_dir/LLR.f2e.neg";
} elsif($lex_type eq 'sampLex') {
    $LEX_e2f_file = "$lex_dir/sampLex.e2f";
    $LEX_f2e_file = "$lex_dir/sampLex.f2e";
}

my $LEX_PROB_THRESHOLD = 0;

&main();

sub main() {
    my @fr_array = &read_file("$in_path/data.fr.ext");
    my @en_array = &read_file("$in_path/data.en.ext");
    my @align_array = &read_file("$in_path/aligned.ext");

    my (%LEX_e2f_hash, %LEX_f2e_hash, %LEX_e2f_neg_hash, %LEX_f2e_neg_hash);
    &read_LEX($LEX_e2f_file, \%LEX_e2f_hash);
    &read_LEX($LEX_f2e_file, \%LEX_f2e_hash);
    &read_LEX($LEX_e2f_neg_file, \%LEX_e2f_neg_hash);
    &read_LEX($LEX_f2e_neg_file, \%LEX_f2e_neg_hash);

    my (@fr_fragments, @en_fragments, @sentence_nums);
    &extract_fragments(\@fr_array, \@en_array, \@align_array, \%LEX_e2f_hash, \%LEX_f2e_hash, \%LEX_e2f_neg_hash, \%LEX_f2e_neg_hash, \@fr_fragments, \@en_fragments, \@sentence_nums);

    my $fr_frag_file = "$out_path/data.fr.frag.$lex_type";
    my $en_frag_file = "$out_path/data.en.frag.$lex_type";
	my $sentence_num_file = "$out_path/sentence_ids.txt";
    open(OUT_FR, ">:utf8", $fr_frag_file);
    open(OUT_EN, ">:utf8", $en_frag_file);
	open(OUT_NUM, ">:utf8", $sentence_num_file);
    foreach my $fr_fragment (@fr_fragments) {
	print OUT_FR "$fr_fragment\n";
    }
    foreach my $en_fragment (@en_fragments) {
	print OUT_EN "$en_fragment\n";
    }
	foreach my $sentence_num (@sentence_nums) {
	print OUT_NUM "$sentence_num\n";
	}
    close OUT_FR;
    close OUT_EN;
}

sub extract_fragments {
    my ($fr_array, $en_array, $align_array, $LEX_e2f_hash, $LEX_f2e_hash, $LEX_e2f_neg_hash, $LEX_f2e_neg_hash, $fr_fragments, $en_fragments, $sentence_nums) = @_;
    my $sen_num = scalar(@$fr_array);

    my $total_fr_num = 0;
    my $total_en_num = 0;
    my $ext_num = 0;

    for(my $sen_i = 0; $sen_i < $sen_num; $sen_i++) {
	my $fr_sen = $$fr_array[$sen_i];
	my $en_sen = $$en_array[$sen_i];
	my $align_sen = $$align_array[$sen_i];

	my @fr_word_array = split(/ /, $fr_sen);
	my @en_word_array = split(/ /, $en_sen);

	my %conti_pair_hash;
	&get_monotonic_continuous_fragments($align_sen, \%conti_pair_hash);

	foreach my $i (sort {$a<=>$b} keys %conti_pair_hash) {
	    my $fr_fragment;
	    my $en_fragment;

	    # obtain fragments by smoothing none lexicon
	    my (@e2f_prob_array, @f2e_prob_array);
	    &lex_trans_prob($conti_pair_hash{$i}, \@fr_word_array, \@en_word_array, $LEX_e2f_hash, $LEX_f2e_hash, $LEX_e2f_neg_hash, $LEX_f2e_neg_hash, \@e2f_prob_array, \@f2e_prob_array);
	    my (@e2f_prob_array_filtered, @f2e_prob_array_filtered);
	    &smoothing_filter(\@e2f_prob_array, $SURROUNDING_NUM, \@e2f_prob_array_filtered, $conti_pair_hash{$i}, \@fr_word_array, \@en_word_array);
	    &smoothing_filter(\@f2e_prob_array, $SURROUNDING_NUM, \@f2e_prob_array_filtered, $conti_pair_hash{$i}, \@fr_word_array, \@en_word_array);
	    &lex_filter4smooth($conti_pair_hash{$i}, \@fr_word_array, \@en_word_array, \@e2f_prob_array_filtered, \@f2e_prob_array_filtered, \$fr_fragment, \$en_fragment);

	    # obtain fragments split by none lexicon separately
	    $fr_fragment =~ s/[\=\|\=]+/\=\|\=/g;
	    $en_fragment =~ s/[\=\|\=]+/\=\|\=/g;
	    my @fr_fragments_cand = split(/\=\|\=/, $fr_fragment);
	    my @en_fragments_cand = split(/\=\|\=/, $en_fragment);
   	    my $cand_num = scalar(@fr_fragments_cand);
    	    for(my $j = 0; $j < $cand_num; $j++) {
	    	&check_len_limit($fr_fragments_cand[$j], $en_fragments_cand[$j], $fr_fragments, $en_fragments, $sentence_nums, $sen_i, \$total_fr_num, \$total_en_num, \$ext_num);
    	    }
    	}
    }

    my $avg_fr_num = $total_fr_num / $ext_num;
    my $avg_en_num = $total_en_num / $ext_num;
    print STDERR "ext_num:$ext_num, avg_fr_num:$avg_fr_num, avg_en_num:$avg_en_num\n";
}

# initialize translation probability 
sub lex_trans_prob {
    my ($conti_pair_hash_i, $fr_word_array, $en_word_array, $LEX_e2f_hash, $LEX_f2e_hash, $LEX_e2f_neg_hash, $LEX_f2e_neg_hash, $e2f_prob_array, $f2e_prob_array) = @_;
    foreach my $j (sort {$a<=>$b} keys %$conti_pair_hash_i) {
	my $align_pair = $$conti_pair_hash_i{$j};
	my ($fr_index, $en_index) = split(/\-/, $align_pair);
	my $fr_word = $$fr_word_array[$fr_index];
	my $en_word = $$en_word_array[$en_index];
	# surface match entries, set to 1!!
	if($fr_word eq $en_word) {
	    $$e2f_prob_array[$j] = 1;
	} 
	elsif($$LEX_e2f_hash{$fr_word}{$en_word}) {
	    $$e2f_prob_array[$j] = $$LEX_e2f_hash{$fr_word}{$en_word};
	} elsif($$LEX_e2f_neg_hash{$fr_word}{$en_word}) {
	    $$e2f_prob_array[$j] = $$LEX_e2f_neg_hash{$fr_word}{$en_word} * (-1);
	} else {
	    $$e2f_prob_array[$j] = -1;
	}

	# surface match entries, set to 1!!
	if($fr_word eq $en_word) {
	    $$f2e_prob_array[$j] = 1;
	} 
	elsif($$LEX_f2e_hash{$en_word}{$fr_word}) {
	    $$f2e_prob_array[$j] = $$LEX_f2e_hash{$en_word}{$fr_word};
	} elsif($$LEX_f2e_neg_hash{$en_word}{$fr_word}) {
	    $$f2e_prob_array[$j] = $$LEX_f2e_neg_hash{$en_word}{$fr_word} * (-1);
	} else {
	    $$f2e_prob_array[$j] = -1;
	}
    }
}

sub lex_filter4smooth {
    my ($conti_pair_hash_i, $fr_word_array, $en_word_array, $e2f_prob_array, $f2e_prob_array, $fr_fragment, $en_fragment) = @_;
    my %fr_frag_hash;
    my %en_frag_hash;
    foreach my $j (sort {$a<=>$b} keys %$conti_pair_hash_i) {
	my $align_pair = $$conti_pair_hash_i{$j};
	my ($fr_index, $en_index) = split(/\-/, $align_pair);
	my $fr_word = $$fr_word_array[$fr_index];
	my $en_word = $$en_word_array[$en_index];

	if(($$e2f_prob_array[$j] > $LEX_PROB_THRESHOLD) && ($$f2e_prob_array[$j] > $LEX_PROB_THRESHOLD)) {
	    if(!$fr_frag_hash{$fr_index}) {
		$$fr_fragment .= $fr_word;
		$$fr_fragment .= ' ';
		$fr_frag_hash{$fr_index} = $fr_word;
	    }
	    if(!$en_frag_hash{$en_index}) {
		$$en_fragment .= $en_word;
		$$en_fragment .= ' ';
		$en_frag_hash{$en_index} = $en_word;
	    }
	} else {
	    $$fr_fragment .= "\=\|\=";
	    $$en_fragment .= "\=\|\=";
	}
    }
}

sub lex_filter {
    my ($conti_pair_hash_i, $fr_word_array, $en_word_array, $LEX_e2f_hash, $LEX_f2e_hash, $fr_fragment, $en_fragment) = @_;
    my %fr_frag_hash;
    my %en_frag_hash;
    foreach my $j (sort {$a<=>$b} keys %$conti_pair_hash_i) {
	my $align_pair = $$conti_pair_hash_i{$j};
	my ($fr_index, $en_index) = split(/\-/, $align_pair);
	my $fr_word = $$fr_word_array[$fr_index];
	my $en_word = $$en_word_array[$en_index];
	# use surface match
	if((($$LEX_e2f_hash{$fr_word}{$en_word} > $LEX_PROB_THRESHOLD) && ($$LEX_f2e_hash{$en_word}{$fr_word} > $LEX_PROB_THRESHOLD))
	    || ($fr_word eq $en_word)) {
        # Do not use surface match
#	if(($$LEX_e2f_hash{$fr_word}{$en_word} > $LEX_PROB_THRESHOLD) && ($$LEX_f2e_hash{$en_word}{$fr_word} > $LEX_PROB_THRESHOLD)) {
	    if(!$fr_frag_hash{$fr_index}) {
		$$fr_fragment .= $fr_word;
		$$fr_fragment .= ' ';
		$fr_frag_hash{$fr_index} = $fr_word;
	    }
	    if(!$en_frag_hash{$en_index}) {
		$$en_fragment .= $en_word;
		$$en_fragment .= ' ';
		$en_frag_hash{$en_index} = $en_word;
	    }
	} else {
	    $$fr_fragment .= "\=\|\=";
	    $$en_fragment .= "\=\|\=";
	}
    }
}

sub check_len_limit {
    my ($fr_fragment, $en_fragment, $fr_fragments, $en_fragments, $sentence_nums, $sen_i, $total_fr_num, $total_en_num, $ext_num) = @_;
    $fr_fragment =~ s/ \Z//g;
    $en_fragment =~ s/ \Z//g;
    my @fr_word_array = split(/ /, $fr_fragment);
    my $fr_word_num = scalar(@fr_word_array);
    my @en_word_array = split(/ /, $en_fragment);
    my $en_word_num = scalar(@en_word_array);

    if($fr_fragment ne '' && $en_fragment ne ''  && $fr_word_num >= $LEN_LIMIT && $en_word_num >= $LEN_LIMIT) {
	push(@$fr_fragments, $fr_fragment);
	push(@$en_fragments, $en_fragment);
	push(@$sentence_nums, $sen_i);

	$$total_fr_num += $fr_word_num;
	$$total_en_num += $en_word_num;
	$$ext_num++;
    }
}

sub get_monotonic_continuous_fragments {
    my ($align_sen, $conti_pair_hash) = @_;
    my @align_pair_array = split(/ /, $align_sen);
    my $pair_num = @align_pair_array;

    my $conti_index_i = 0;
    my $conti_index_j = 0;

    my $prev_fr_index = '';
    my $prev_en_index = '' ;
    for(my $i = 0; $i < $pair_num; $i++) {
    	my $align_pair = $align_pair_array[$i];
    	my ($fr_index, $en_index) = split(/\-/, $align_pair);

    	if($prev_fr_index eq '' && $prev_en_index eq '') {
    	    $$conti_pair_hash{$conti_index_i}{$conti_index_j} = $align_pair;
    	} elsif(($fr_index == $prev_fr_index || $fr_index == $prev_fr_index + 1) &&
    	   ($en_index == $prev_en_index || $en_index == $prev_en_index + 1)) {
	    $conti_index_j++;
    	    $$conti_pair_hash{$conti_index_i}{$conti_index_j} = $align_pair;
    	} else {
	    $conti_index_i++;
    	    $conti_index_j = 0;
    	    $$conti_pair_hash{$conti_index_i}{$conti_index_j} = $align_pair;
    	}

    	$prev_fr_index = $fr_index;
    	$prev_en_index = $en_index;
    }
}

sub read_LEX {
    my ($LEX_file, $LEX_hash) = @_;
    my @LEX_array = &read_file("$LEX_file");
    foreach my $LEX_sen (@LEX_array) {
	my ($word_1, $word_2, $prob) = split(/ /, $LEX_sen);
	$$LEX_hash{$word_1}{$word_2} = $prob;
    }
}

# surrounding_num should be odd number
sub smoothing_filter() {
    my ($prob_array, $surrounding_num, $prob_array_filterd, $conti_pair_hash_i, $fr_word_array, $en_word_array) = @_;

    my $prob_array_len = scalar(@$prob_array);
    my $bias = ($surrounding_num-1) / 2;

    for(my $i = 0; $i < $prob_array_len; $i++) {
	my $align_pair = $$conti_pair_hash_i{$i};
	my ($fr_index, $en_index) = split(/\-/, $align_pair);
	my $fr_word = $$fr_word_array[$fr_index];
	my $en_word = $$en_word_array[$en_index];

	my $filterd_prob = $$prob_array[$i];

	my $filterd_prob_prev = -1;
	if($i > 0) {
	    $filterd_prob_prev = $$prob_array[$i-1];
	}
	my $filterd_prob_post = -1;
	if($i < $prob_array_len) {
	    $filterd_prob_post = $$prob_array[$i+1];
	}

	# only filter for pairs do not exist in the lexicon
	# only filter +-+ element
	my $filter_flag = 0;
	if(($filterd_prob < 0) && ($filterd_prob_prev > 0) && ($filterd_prob_post > 0)) {
	    $filter_flag = 1;
	}

	if($filter_flag == 1) {
	    for(my $j = $bias; $j > 0; $j--) {
		if(($i-$j) >= 0) {
		    $filterd_prob += $$prob_array[$i-$j];
		}
		if(($i+$j) < $prob_array_len) {
		    $filterd_prob += $$prob_array[$i+$j];
		}
	    }
	    $filterd_prob = $filterd_prob / $surrounding_num;
	}
	push(@$prob_array_filterd, $filterd_prob);
    }
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
