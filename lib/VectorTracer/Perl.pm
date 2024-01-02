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
	return "
#include <iostream>
using namespace std;

int main () {
$code
	return 0;
}
	";
}

sub _trace {
	my $self = shift;
	

	my $code = '';
	
	my $node = shift // $self->{node};


	
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
					push @code, "\tcout << " . $_->{call_function}->[1] . " << endl;";
				} elsif ($f eq 'print') {
					push @code, "\tcout << " . $_->{call_function}->[1] . ";";
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


sub parse {
	my $self = shift;
	my $str  = shift;
	my $node = [];
	
	$self->debug("Parse $str");
	
	my @s = map {s/^\s+//; s/\s+$//; $_} grep {$_} split /;/, $str;
	my $sl = scalar (@s);
	
	for (@s) {
		if (my ($method, $scope) = $_ =~ /([\w+\d+_]+)\s+(\S+)/) {
			$_ = "$method($scope)";
		}
	}
	
	my $function = '';
	my @expression = ();
	
	my $value = {};
	
	my $func;
	

	for (my $i = 0; $i < @s; $i++) {
		my $s = $s[$i];
		next if $s =~ /^\s+$/;
		next if $s eq '';
		$self->debug("Parse line: $s");
		if (my ($function) = $s =~ /^([a-zA-Z_][\w+\d+_]*)/) {
			# Function
			if (my ($param) = $s =~ /^$function\s*\((.*)\)$/) {
				my $p = $self->parse ($param);
				push @$node, {
					call_function => [$function => $p],
				};
			} else {
				die "Wrong syntax line: $s";
			}
		} elsif (my ($digit) = $s =~ /(\d+)/) {
			return $digit;		
		} else {
			die "Wrong syntax: $s";
		}
	}		
	return $node;
}

sub _parse_digit {
	my $self = shift;
	my $s = shift;
	my @s = @$s;
	
	my $i = 0;
	my $c = $s[0];
	
	my $node = [];
	
	$self->{digit} .= $c;
	my $j;
	my $buff = $self->{digit};
	my $had_non_digit = 0;
	for ($j = $i + 1; $j < @s ; $j ++) {
		my $o = $s[$j];
		if ($o =~ /[0-9\.]/) {
			$buff .= $o;
		} else {
			$had_non_digit = 1;
			last;
		}
	}
	
	if ($had_non_digit) {
		$i = $j - 1;
		$self->{digit} = substr($buff, 0, length ($buff) );
		$self->debug("Found digit = ".$self->{digit});
		push @$node, $self->{digit};
	} else {
		$i = $j;
		$self->{digit} = $buff;
		$self->debug("Found digit = ".$self->{digit});
		push @$node, $self->{digit};
	}
	return ($node, $i);
}

1;
