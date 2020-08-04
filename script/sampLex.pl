# !/usr/bin/env perl

# sampLex.pl: this script implements the sub-corpora sampling lexicon (SampLEX) 
# extraction method described in the following paper

# Ivan Vulic ́ and Marie-Francine Moens. 
# Sub-corpora sampling with an application to bilingual lexicon extraction. 
# In Proceedings of COLING 2012

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

my $Mf = 0;
my $Mi = 0;

&main();

sub main {

    my @fr_array = &read_file("$in_path/data.fr");
    my @en_array = &read_file("$in_path/data.en");

    my $N = scalar(@fr_array);

    my %lexicon;

    # iteration
    for(my $i = 1; $i <= $ITERS; $i++) {
	print "iteration $i\n";
	open(OUT, ">:utf8", "$out_path/lex.$i");
	&iteration($N, \@fr_array, \@en_array, \%lexicon);
	foreach my $wf (keys %lexicon) {
	    foreach my $we (keys %{$lexicon{$wf}}) {
		printf OUT "%s %s %.7f\n", $we, $wf, $lexicon{$wf}{$we};
	    }
	}
	close OUT;
    }
}

sub iteration {
    my ($N, $fr_array, $en_array, $lexicon) = @_;
    my $K = $N;

    while($K > 0) {
	my $weight_k = $K/$N;

	my $sub_num = ceil($N/$K);
	print STDERR "K:$K, sub_num:$sub_num\n";
	my @sub_corpora = &sampling_round($N, $K);
	for(my $sub_i = 1; $sub_i <= $sub_num; $sub_i++) {
	    my (%cand_f2e_hash, %cand_e2f_hash);
	    &criteria($sub_corpora[$sub_i], $fr_array, $en_array, \%cand_f2e_hash, \%cand_e2f_hash);

	    foreach my $wf (keys %cand_f2e_hash) {
		foreach my $we (keys %{$cand_f2e_hash{$wf}}) {
		    if($cand_e2f_hash{$we}{$wf}) {
			$$lexicon{$wf}{$we} += $weight_k;
		    }
		}
	    }
	}
	$K = floor($K/2);
    }
}

sub criteria {
     my ($sub_corpora, $fr_array, $en_array, $cand_f2e_hash, $cand_e2f_hash) = @_;

     my %wf_count_hash;
     my %we_count_hash;

     foreach my $i (@{$sub_corpora}) {
	 my @wf_array = split(/ /, $$fr_array[$i]);
	 my @we_array = split(/ /, $$en_array[$i]);
	 my %wf_hash;
	 my %we_hash;
	 # count
	 foreach my $wf (@wf_array) {
	     $wf_hash{$wf}++;
	     $wf_count_hash{$wf}++;
	 }
	 foreach my $we (@we_array) {
	     $we_hash{$we}++;
	     $we_count_hash{$we}++;
	 }
	 # f2e cooccur
	 &criteria_cooccur(\%wf_hash, \%we_hash, $cand_f2e_hash);
	 # e2f cooccur
	 &criteria_cooccur(\%we_hash, \%wf_hash, $cand_e2f_hash);
     }
     # only keep cands with freq above Mf, co-occur above Mi & same overall freq
     &criteria_freq($cand_f2e_hash, \%wf_count_hash, \%we_count_hash);
     &criteria_freq($cand_e2f_hash, \%we_count_hash, \%wf_count_hash);
     
     # only keep unique cand
     &criteria_unique($cand_f2e_hash);
     &criteria_unique($cand_e2f_hash);
}

sub criteria_cooccur {
    my ($wf_hash, $we_hash, $cand_f2e_hash) = @_;
    foreach my $wf (keys %$wf_hash) {
	my $freq_wf = $$wf_hash{$wf};
	if($$cand_f2e_hash{$wf}) {
	    foreach my $we (keys %{$$cand_f2e_hash{$wf}}) {
		my $freq_we = $$we_hash{$we};
		if($freq_we == $freq_wf) {
		    $$cand_f2e_hash{$wf}{$we}++;
		} else {
		    delete $$cand_f2e_hash{$wf}{$we};
		}
	    }
	} else {
	    foreach my $we (keys %$we_hash) {
		my $freq_we = $$we_hash{$we};
		if($freq_we == $freq_wf) {
		    $$cand_f2e_hash{$wf}{$we}++;
		}
	    }
	}
    }
}

sub criteria_freq {
    my ($cand_f2e_hash, $wf_count_hash, $we_count_hash) = @_;
    foreach my $wf (keys %$cand_f2e_hash) {
	foreach my $we (keys %{$$cand_f2e_hash{$wf}}) {
	    # only keep cands with freq above Mf, co-occur above Mi & same overall freq
	    if(($$wf_count_hash{$wf} < $Mf) || ($$cand_f2e_hash{$wf}{$we} < $Mi) || ($$wf_count_hash{$wf} != $$we_count_hash{$we})) {
		delete $$cand_f2e_hash{$wf}{$we};
	    }
	}
    }
}

sub criteria_unique {
    my ($cand_f2e_hash) = @_;
    foreach my $wf (keys %$cand_f2e_hash) {
	if(scalar(keys %{$$cand_f2e_hash{$wf}}) != 1) {
	    foreach my $we (keys %{$$cand_f2e_hash{$wf}}) {
		delete $$cand_f2e_hash{$wf}{$we};
	    }
	}
    }
}

sub sampling_round {
    my ($N, $K) = @_;
    my @rand_array = &random($N, $N);

    my @sub_corpora;
    my $sub_num = ceil($N/$K);

    for(my $i = 1; $i <= ($sub_num-1); $i++) {
	my $k = 0;
    	for(my $j = ($i-1)*$K+1; $j <= $i*$K; $j++) {
    	    $sub_corpora[$i][$k++] = $rand_array[$j-1];
    	}
    }
    my $k = 0;
    for(my $j = ($sub_num-1)*$K+1; $j <= $N; $j++) {
    	$sub_corpora[$sub_num][$k++] = $rand_array[$j-1];
    }
    return @sub_corpora;
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

sub random {
    my ($threshold, $generate_num) = @_;

    my %rand_hash;
    while(scalar(keys %rand_hash) < $generate_num) {
	my $rand_num = int(rand($threshold));
	$rand_hash{$rand_num}++;
    }

    return %rand_hash;
}
