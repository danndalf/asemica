#!/usr/bin/perl -w
use strict;

###
# Asemica -- An asemic Markov-chained cipher
# Copyright (c) 2011 by Danne Stayskal <danne@stayskal.com>
###

###
# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
###

our $VERSION = '1.0';

use Getopt::Long;

my $corpus_file = '';
my $input_file = '';
my $pin_num = '';
my $output_file = '';
my $verbose = 0;
my $format = '';
my $force = 0;
my $get_help = !scalar(@ARGV);
GetOptions (
	"c|corpus=s" => \$corpus_file,
	"i|input=s"  => \$input_file,
	"p|pin" => \$pin_num,
	"o|output=s" => \$output_file,
	"v|verbose+" => \$verbose,
	"f|format=s" => \$format,
	"force+"     => \$force,
	"h|help+"    => \$get_help,
);
my $operation = shift @ARGV;

if ($verbose) {
	print STDERR "Asemica version $VERSION running\n";
	print STDERR "   Corpus file: $corpus_file\n" if $corpus_file;
	print STDERR "   Input file: $input_file\n" if $input_file;
	print STDERR "   Pin number: $pin_num\n" if $pin_num;
	print STDERR "   Output file: $output_file\n" if $output_file;
	print STDERR "   Operation: $operation\n" if $operation;
	print STDERR "   Force: $force\n" if $force;
	print STDERR "   Help: $get_help\n" if $get_help;
	print STDERR "\n";
}

my $usage = "Usage: $0 (enc|dec) -c <corpus_file> [-i <input_file>] ".
			"[-o <output_file>] [-f <format>] [--force] [--help]\n";

###
# If all they want is help (or they ran this with no args), give them help
###
if ($get_help) {
	print STDERR <<__END_HELP__
Asemica: an asemic Markov-chained cipher, v. $VERSION
$usage
OPTIONS:
   -c/--corpus:  specify corpus filename or URL
   -i/--input:   specify input filename (defaults to STDIN)
   -p/--input2:  add custom pin number (optional - leave null for none)
   -o/--output:  specify output filename (defaults to STDOUT)
   -f/--format:  specify output format (defaults to none)
   --force:      forces runtime on an insufficiently complex corpus
   --help:       displays this message
   -v/--verbost: increments verbosity setting (used for debugging)
AVAILABLE FORMATS:
   none:         doesn't format output; returns only word list
   email:        formats output to look like an informal email
   poem:         if you want your output to look like poetry
EXAMPLES
   echo "message" | $0 enc -c corpus.txt -o asemic.txt
   $0 dec -c corpus.txt -i asemic.txt
__END_HELP__
;
exit 1;
}


###
# Make sure we have necessary and sufficient inputs (command line or STDIN)
###

unless ($operation) {
	print "No operation (encode or decode) specified.\n";
	print STDERR $usage;
	exit 1;
}

unless ($operation eq 'enc' || $operation eq 'dec') {
	print "Invalid operation specified: $operation\n";
	print STDERR $usage;
	exit 1;
}

my $input = '';
unless ($input_file) {
	if ($verbose) {
		print STDERR "No input file specified.  Reading from STDIN...\n";		
	}
	$input = join('',<STDIN>);
} else {
	open('INPUT', '<', $input_file) || die "Can't read $input_file";
	$input = join('',<INPUT>);
	close('INPUT');
}


###
# Load and verify corpus
###

my $corpus = '';
unless ($corpus_file) {
	print STDERR "No corpus specified.  Can't operate without a corpus.\n";
	print STDERR $usage;
	exit 1;
}
if (-f $corpus_file) {
	### It's a flat file.  Load and move on.
	open('CORPUS','<', $corpus_file) || die "Can't read $corpus_file";
	$corpus = join('',<CORPUS>);
	close('CORPUS');

} elsif ($corpus_file =~ m/^https?/) {
    ### It's a URI.  Try to download it.
	$corpus = `curl -s $corpus_file`;
	
	unless ($corpus) {
		print STDERR "Unable to load corpus from $corpus_file\nExiting.\n";
		exit 1;
	}

} else {
	print STDERR "Couldn't read corpus at $corpus_file\nExiting.\n";
	exit 1;
}



###
# Calculate and verify corpus tokens and transition matrix
###
my $tokens = tokenize_corpus($corpus);
my $transitions = generate_transitions(@$tokens);
unless (verify_exits($transitions)) {
	if ($force) {
		if ($verbose) {
			print STDERR "Insufficient number of nodes with sufficient exits ".
			  	  "to perform quality coding using the specified corpus file.".
				  "Proceeding due to use of --force.\n";
		}
	} else {
		print STDERR "Insufficient number of nodes with sufficient exits to ".
			  "perform quality coding using the specified corpus file. ".
		      "Use --force to override (which would likely generate an ".
		      "absurdly long output text).\n".
		      "Exiting.\n";
		exit 1;
	}
} else {
	if ($verbose) {
		print STDERR "Sufficient number of nodes with sufficient exits to ".
			  "perform quality coding using the specified corpus file.\n";
	}
}


###
# Run the actual encoding or decoding  procedure
###
my $output_text = '';
if ($operation eq 'enc') {
	
	$output_text = encode($input, $transitions, $tokens);
	
	if ($format) {
		$output_text = format_text($output_text, $format);
	}
	
} elsif ($operation eq 'dec') {

	$output_text = decode($input, $transitions, $tokens);
	
}


###
# Output the results
###
if ($output_file) {
	open('OUTPUT', '>', $output_file) || die "Can't write to $output_file.\n";
	print OUTPUT $output_text;
	close('OUTPUT');
} else {
	print $output_text;
}


###
# clean_input
# Removes all nonwords and HTML from input text
# 
# Takes:
#   - $input, a scalar containing the input to be cleaned
# Returns:
#   - $output, a scalar containing the cleaned data
# Note:
#   Yes, this is a silly thing to have isolated like this, but I'm doing so
#   because the cleaning procedures need to be identical for encoding and
#   decoding to work properly.  This approach saves time and repetition.
###
sub clean_input {
	my ($input) = @_;
	
	$input =~ s/\n/ /g;      ### Change newlines to spaces
	$input =~ s/\<[^>]*//g;  ### Strip out HTML (poorly -- we can't assume any
	 						 ### modules other than perl's core will be around)
	$input =~ s/[^\w\']/ /g; ### Change non-word characters to spaces
	$input =~ s/\d/ /g;      ### Change numbers to spaces
	$input =~ s/\s+/ /g;     ### Change sequences of spaces to a single space
	$input =~ s/^\s+//;      ### Trim leading whitespace
	$input =~ s/\s+$//;      ### Trim trailing whitespace
	
	return $input;
}


###
# tokenize_corpus
# Breaks the input corpus into a series of processable "tokens"
#
# Takes:
#   - $corpus, a scalar containing the complete input corpus
# Returns:
#   - $tokens, an array reference of tokens (most likely "words") present
# Output looks like:
#   ['The','Project','Gutenberg', ... ,'about','new','eBooks']
###
sub tokenize_corpus {
	my ($corpus) = @_;
	
	$corpus = clean_input($corpus);
	my @tokens = split(/\s/, $corpus);

	return \@tokens;
}


###
# generate_transitions
# Creates the primary transition matrix for use in coding
#
# Takes:
#   - @tokens, an array of tokens present, sequentially, in the corpus
# Returns:
#   - $transitions, the transition matrix
# Output looks like:
#    {
#   	'atlantic' => {                      ### Lowercase form
#                'seen' => 2,                ### How many fimes seen in corpus
#                'exits' => {                ### Which words follow it?
#                             'City' => 1,   ### One instance of this
#                             'and' => 1     ### One instance of that
#                           },               ### Exits not guaranteed unique
#                'door' => [                 ### Doors are guaranteed unique
#                            'City',         ### Following door number 1
#                            'and'           ### Following door number 2
#                          ],
#                'doors' => 2,               ### Cached count of doors
#                'token' => 'Atlantic'       ### Original form of the token
#              },
#    }
###
sub generate_transitions {
	my @tokens = @_;
	my $transitions = {};
	
	### Generate the initial transitions table
	foreach my $index (0..scalar(@tokens)){
		my $token = $tokens[$index-1];
		my $key = lc($token);
		
		$transitions->{$key}->{seen}++;
		$transitions->{$key}->{token} = $token;

		if ($tokens[$index+1]) {
			$transitions->{$key}->{exits}->{$tokens[$index+1]}++;
		}
	}

	### Calculate the exits and doors
	foreach my $transition (keys(%$transitions)){
		my @exits = keys(%{$transitions->{$transition}->{exits}});
		$transitions->{$transition}->{door} = [];
		my $found = {};
		foreach my $exit (sort(keys(%{$transitions->{$transition}->{exits}}))){
			unless ($found->{lc($exit)}) {
				push @{$transitions->{$transition}->{door}}, $exit;				
			}
			$found->{lc($exit)} = 1;
		}
		$transitions->{$transition}->{doors} = scalar(
			@{$transitions->{$transition}->{door}}
		);
		if ($transitions->{$transition}->{doors} > 15) {
			$transitions->{$transition}->{meaningful} = 1;
		}
	}

	return $transitions;
}


###
# verify_exits
# Returns whether this corpus will work well as an encoding or decoding medium
#
# Takes:
#   - $transitions, the calculated transition matrix
# Returns:
#   - 1 if it will suffice, 0 if it probably won't.
# Note:
#   We are looking for how many nodes in the transition matrix have more than
#   15 doors (as they'll need minimally 16 in order for the relationship 
#   between any node and its successor to be able to encode a binary nibble)
#   If there are fewer than 10 of these, chances are the encoding / decoding
#   is going to be of very low quality.
###
sub verify_exits {
	my ($transitions) = @_;
	my $count = 0;
	my @meaningful = ();
	foreach my $key (keys(%$transitions)){
		if ($transitions->{$key}->{doors} > 15){
			$count++;
			push @meaningful, $key;
		}
	}
	if ($verbose) {
		print STDERR "$count meaningful transitions (".
					 join(', ',@meaningful).")\n\n";
	}
	if ($count >=7) {
		return 1;
	} else {
		return;
	}
}

###
# encode
# Encodes an input file using the transition matrix calculated from the corpus
# Takes:
#   - $input, a scalar containing the input to be encoded
#   - $pin (optional), the user's pin number code
#   - $transitions, the transition matrix calculated from the corpus
#   - $tokens, an array reference of the token sequence from the key corpus
# Returns:
#   - $encoded_text, the encoded text
###
sub encode {
	my ($input, $transitions, $tokens) = @_;
	my $ruleset = ((), (), (), (), (), (), (), (), (), ())
	my $bits = unpack("b*", $input);
	my $nibbles;
	while (my $nibble = substr($bits,0,4,'')){
		push @$nibbles, bin2dec($nibble);
	}

	my $token = $tokens->[int(rand(scalar(@$tokens)))];
	my $encoded_text = '';
	my $last_token = $token; ### for debugging
	
	while (scalar(@$nibbles)){
		
		if ($transitions->{lc($token)}->{meaningful}){
			$encoded_text .= $token.' ';

			### This token means something.  Walk through the nibblth door.
			my $nibble = shift(@$nibbles);
			$token = $transitions->{lc($token)}->{door}->[$nibble];

		} else {
			$encoded_text .= $token.' ';

			### This token is irrelevant.  Stumble drunkenly through any door.
			$token = $transitions->{lc($token)}->{door}->[
						int(rand($transitions->{lc($token)}->{doors}))
					 ];
		}
		
		unless($token){
			use Data::Dumper;
			print "DEBUG:\ntoken = $token\n".
				  "Transitions:".Dumper($transitions->{lc($token)}).
				  "\nlast_token = $last_token\n".
				  "Transitions:".Dumper($transitions->{lc($last_token)});
			exit 1;
		}
		
		$last_token = $token;
	}
	$encoded_text .= $token.' ';

	return $encoded_text;
}

###
# decode
# Pieces an arbitrary binary sequence back together from ASCII input file
#
# Takes:
#   - $output_text, text originally output by an encoding pass of this script
#   - $transitions, the transition matrix generated from the key corpus
#   - $tokens, an array reference of the token sequence from the key corpus
# Returns:
#   - $reconstituted, the decoded text
###
sub decode {
	my ($input, $transitions, $tokens) = @_;

	my $decoded = '';
	
	$input = clean_input($input);
	
	my @words = split(/\s+/, $input);

	foreach my $i (0..scalar(@words)-2){
		if ($transitions->{lc($words[$i])}->{meaningful}){
			### We walked through a specific door.  Figure out which it was.
			my $num_doors = scalar(@{$transitions->{lc($words[$i])}->{door}});
			foreach my $j (0..$num_doors-1){
				my $on_door = lc($transitions->{lc($words[$i])}->{door}->[$j]);
				if ($on_door eq lc($words[$i+1])){
					my $binary = dec2bin($j);
					while (length($binary)<4){
						$binary = '0'.$binary;
					}
					$decoded .= $binary;
				}
			}
		}
		### TODO: a later version of this should use the less meaningful
		### nodes to encode information as well.  Really, any node with more
		### than one exit can be used to encode something (minimally, a single
		### bit), so in that sense any node with more than 2 exits /could/ be
		### a door.  We'd just have to modify the coders for variable lengths.
		### For right now, we're just using nodes with 16 or more exits (so
		### they can encode minimally a nibble), then only making use of the
		### first 16 doors from that node. This can be improved with variable-
		### length encoding.
	}

	my $decoded_text = pack('b*',$decoded);
	return $decoded_text;
}


###
# format_text
# Formats the output text to look like something human-created
#
# Takes:
#   - $input_text, a scalar containing the text to be formatted
#   - $format, a scalar specifying the desired format
# Returns:
#   - $output_text, a scalar containing the formatted text
# Supported formats: none, essay, poem, scripture, email
###
sub format_text {
	my ($input_text, $format) = @_;
	
	my $formats = {
		'none' => sub { return join(' ',@_); },
		
		'essay' => sub {
			my @words = @_;
			return join(' ',@words);
		},
		
		'textile' => sub {
			my @words = @_;
			return join(' ',@words);
		},
		
		###
		# Poem format
		###
		'poem' => sub {
			my @words = @_;
			
			### Form the words into sentences
			my @puncts = ('.',' ',' ',' ',',',',',',','!','?');
			my @sentences = ();
			while (scalar(@words)) {
				my $sentence_length = 6 + int(rand(3));
				if (scalar(@words) < $sentence_length) {
					$sentence_length = scalar(@words);
				}
				my $sentence = join(' ',splice(@words,0,$sentence_length,()));
				$sentence = ucfirst($sentence).$puncts[int(rand(@puncts))];
				push @sentences, $sentence;
			}
			
			### Form the sentences into stanzas
			my @stanzas = ();
			while (scalar(@sentences)) {
				my $stanza_length = 4 + int(rand(7));
				if (scalar(@sentences) < $stanza_length) {
					$stanza_length = scalar(@sentences);
				}
				my $stanza = join("\n",splice(@sentences,0,$stanza_length,()));
				push @stanzas, $stanza;
			}
			return join("\n\n",@stanzas);
		},
		
		###
		# Email format
		###
		'email' => sub {
			my @words = @_;
			
			my $greeting = ucfirst(shift(@words));
			my $name = ucfirst(pop(@words));
			my $thanks = pop(@words); 
			
			### Form the words into sentences
			my @puncts = qw/? . . . . . !/;
			my @sentences = ();
			while (scalar(@words)) {
				my $sentence_length = 7 + int(rand(10));
				if (scalar(@words) < $sentence_length) {
					$sentence_length = scalar(@words);
				}
				my $sentence = join(' ',splice(@words,0,$sentence_length,()));
				$sentence = ucfirst($sentence).$puncts[int(rand(@puncts))];
				push @sentences, $sentence;
			}
			
			### Form the sentences into paragraphs
			my @paragraphs = ();
			while (scalar(@sentences)) {
				my $paragraph_length = 4 + int(rand(7));
				if (scalar(@sentences) < $paragraph_length) {
					$paragraph_length = scalar(@sentences);
				}
				my $paragraph = join('  ',splice(@sentences,0,$paragraph_length,()));
				push @paragraphs, $paragraph;
			}
			my $body = join("\n\n   ",@paragraphs);
			return "$greeting,\n\n   $body\n\n$thanks,\n$name";
		},
	};
	if ($formats->{$format}) {
		return $formats->{$format}->(split(' ',$input_text));		
	} else {
		print STDERR "Unsupported format: $format\nExiting\n";
		exit 1;
	}
}


### 
# dec2bin
# Converts a decimal numeric expression to binary
#
# Takes:
#   - $decimal, a decimal expression of a number (e.g. '54')
# Returns:
#   - $binary, a binary expression of the same number (e.g. '110110')
# Note:
#   Sourced from Perl Cookbook (Christiansen & Torkington 1998), sec. 2.4
###
sub dec2bin {
	my $str = unpack("B32", pack("N", shift));
	$str =~ s/^0+(?=\d)//;
	return $str;
}


### 
# bin2dec
# Converts a binary numeric expression to decimal
#
# Takes:
#   - $binary, a binary expression of the same number (e.g. '110110')
# Returns:
#   - $decimal, a decimal expression of a number (e.g. '54')
# Note:
#   Sourced from Perl Cookbook (Christiansen & Torkington 1998), sec. 2.4
###
sub bin2dec {
	return unpack("N", pack("B32", substr("0" x 32 . shift, -32)));
}
