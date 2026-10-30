package VectorTracer::Perl;

use strict;
use warnings;
use 5.022;
use experimental 'smartmatch';

use Data::Dumper;

sub new {
	my $class = shift;
	my %opts  = (
		debug => 0,
		@_,
	);
	
	my $self = {
		node	=> undef,
		digit 	=> '',
		debug   => $opts{debug},
		functions => {map {$_ => 1} qw/say/},
		operators => {map {$_ => 1} ('+', '-', '*', '/', '**')},
	};
	
	return bless $self, $class;
}


sub debug {
	my $self = shift;
	my $msg  = shift;
	
	if ($self->{debug}) {
		warn '['.scalar(localtime).'] '. $msg . "\n";
	}
	return;
}

sub trace {
	my $self = shift;
	my $node = shift;
	my $code = $self->_trace($node);
	return "#include <iostream>
#include <math.h>
#include <string>
using namespace std;

class Scalar {
	bool is_undef = true;
	std::string string;
	Scalar () {
		;
	}
	
	Scalar (char * str) {
		is_undef = false;
		string = str;
	}
	Scalar (int i) {
		is_undef = false;
		string = i;
	}

	Scalar (float f) {
		is_undef = false;
		string = f;
	}
	
	
	operator std::string () {
		return this->string;
	}
	
	
	operator int () {
		return stoi(this->string);
	}
	
	operator float () {
		return stof(this->string);
	}	
	
	operator bool () {
		if (this->is_undef) {
			return false;
		}
		if (this->string == \"\") {
			return false;
		}
		if (this->string == \"0\" ) {
			return false;
		}
		
		return true;
	}
	
};

int main () {
	$code
	return 0;
}
	";
}

sub _trace {
	my $self = shift;
	my $node = shift;
	my %opts = (
		depth => 0,
		@_,
	);

	my $code = '';
	
	if (ref $node eq 'HASH') {
		my ($key, $value) = each %$node;
		if ($self->{functions}->{$key}) {
			my $a = $self->trace($value);
			return sin($a) if ($key eq 'sin');
			return cos($a) if ($key eq 'cos');
		} elsif ($self->{operators}->{$key}) {
			my ($a, $b) = @$value;
			$a = $self->trace($a);
			$b = $self->trace($b);
			return $a + $b if ($key eq '+');
			return $a - $b if ($key eq '-');
			return $a * $b if ($key eq '*');
			return $a / $b if ($key eq '/');
			return $a ** $b if ($key eq '**');
		}
	} elsif (ref $node eq 'ARRAY') {
		my @code; 
		for (@$node) {
			if (my $f = $_->{call_function}->[0]) {
				if ($f eq 'say') {
					push @code, "cout << " . $self->_trace($_->{call_function}->[1], depth => 1) . " << endl;";
				} elsif ($f eq 'print') {				
					push @code, "cout << " . $self->_trace($_->{call_function}->[1], depth => 1) . ";";
				} elsif ($f eq 'sin') {				
					push @code, "sin(" . $self->_trace($_->{call_function}->[1], depth => 1) . ")" . ($opts{depth} == 0 ? ';' : '');
				} elsif ($f eq 'cos') {				
					push @code, "cos(" . $self->_trace($_->{call_function}->[1], depth => 1) . ")". ($opts{depth} == 0 ? ';' : '');
				} elsif ($f eq 'if') {
					push @code, "if(" . $self->_trace($_->{call_function}->[1], depth => 1). ") {" . $self->_trace($_->{call_function}->[2]) . '}';
				} elsif ($f eq 'while') {
					push @code, "while(" . $self->_trace($_->{call_function}->[1], depth => 1). ") {" . $self->_trace($_->{call_function}->[2]) . '}';					
				} elsif ($f eq 'break' ) {
					push @code, 'break;';
				} elsif ($f eq '+') {
					push @code, $self->_trace($_->{call_function}->[1]). '+'. $self->_trace($_->{call_function}->[2])."";
				} elsif ($f eq '-') {
					push @code, $self->_trace($_->{call_function}->[1]). '-'. $self->_trace($_->{call_function}->[2])."";
				} elsif ($f eq '*') {
					push @code, $self->_trace($_->{call_function}->[1]). '-'. $self->_trace($_->{call_function}->[2])."";
				} elsif ($f eq '/') {
					push @code, $self->_trace($_->{call_function}->[1]). '-'. $self->_trace($_->{call_function}->[2])."";
				} else {
					die "Unsupported func: " . Dumper $f;
				}
			} else {
				die "Unsupported node";
			}
		}
		return join "\n", @code;
	}
	return $node;
}

sub _blocks {
	my $s = shift;
	my $n = shift;
	die $s;
	return split (/\}/, $s) == $n + 1;
}

sub parse {
	my $self = shift;
	my $str  = shift;
	my $node = [];
	

	
	$str =~ s/;+\s*$//;
	
	$self->debug("Parse $str");
	
	my @s;
	if ($str =~ /;/) {
		@s = map {s/^\s+//; s/\s+$//; $_ . ';'} grep {defined $_} split /;/, $str;
	} else {
		$str =~ s/^\s+//;
		$str =~ s/\s+$//;
		push @s, $str;
	}

	
	my $sl = scalar (@s);
	
	for (@s) {
		if (my ($method, $scope) = $_ =~ /^([\w+\d+_]+)\s+(\S+)$/) {

		}
	}
	
	my $function = '';
	my @expression = ();
	
	my $value = {};
	
	my $func;
	

	my $buff;
	my $blocks = 0;
	for (my $i = 0; $i < @s; $i++) {
		my $s = $s[$i];
		$buff .= $s;
		$s = $buff;
		$self->debug("Parse line: $s");
		
		if ($s =~ /^\s*\((.+)\)\s*/) {
			$s = $1;
		}
		
		next if ($s =~ /^\s*$/);
		
		if (my ($function) = $s =~ /^([a-zA-Z_][\w+\d+_]*)/) {
			# Function
			$s  =~ s/;$//;
			if ($s =~ /^if\s*\((.*)\)/) {
				unless ($s =~ /^if\s*\((.*?)\)\s*\{(.*)\}/s) {
					next;	
				}
				my $case = $1;
				my $code = $2;
				if (scalar split (/\{/, $code) != scalar split (/\}/, $code)) {
					next;
				}
				push @$node, {
					call_function => ['if' => $self->parse($case), $self->parse($code)],
				};
			} elsif ($s =~ /^while\s*\((.*)\)/) {
				unless ($s =~ /^while\s*\((.*?)\)\s*\{(.*)\}/s) {
					next;	
				}
				my $case = $1;
				my $code = $2;
				if (scalar split (/\{/, $code) != scalar split (/\}/, $code)) {
					next;
				}
				push @$node, {
					call_function => ['while' => $self->parse($case), $self->parse($code)],
				};
			} elsif ($s =~ /^$function\s*\((.*)\)$/) {
				push @$node, {
						call_function => [$function => $self->parse($1)],
				};
			} elsif ($s =~ /^$function\s+(.*)\s*$/) {
				push @$node, {
						call_function => [$function => $self->parse($1)],
				};	
			} elsif ($s eq 'last' ) {
				push @$node, {
						call_function => ['break'],
				};					
			} else {
				die "Wrong syntax line: $s";
			}
		} else {
			warn "Parse $s";
			my ($digit) = $s =~ /^\(?(\d+)\)?$/;
			if (defined $digit) {
				return $digit;
			} elsif ($s =~ /^\"(.*)\"$/ ) {
				return qq["$1"];
			} elsif ($s =~ /^(.+)\s*\+\s*(.+)/) {
				push @$node, {
					call_function => ['+' => $self->parse($1), $self->parse($2)],
				};
			} elsif ($s =~ /^(.+)\s*\-\s*(.+)/) {
				push @$node, {
					call_function => ['-' => $self->parse($1), $self->parse($2)],
				};
			} elsif ($s =~ /^(.+)\s*\*\s*(.+)/) {
				push @$node, {
					call_function => ['*' => $self->parse($1), $self->parse($2)],
				};
			} elsif ($s =~ /^(.+)\s*\-\s*(.+)/) {
				push @$node, {
					
					call_function => ['/' => $self->parse($1), $self->parse($2)],
				};
			} else {
				die "Wrong syntax: $s";
			}
		}
		$buff = '';
	}	
	return $node;
}

1;
