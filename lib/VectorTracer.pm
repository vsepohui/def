package VectorTracer;

# Recode from math phases vecror tracer

use strict;
use warnings;
use 5.038;
no warnings 'deprecated::smartmatch';

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
		functions => {map {$_ => 1} qw/print say sin cos/},
		cases	  => {map {$_ => 1} 'if'},
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
	
	my $code = $self->_trace;
	
	return "
#include <iostream>
#include <math.h>

using namespace std;

int main () {
	$code
}

";
}

sub _trace {
	my $self = shift;
	my $node = shift // $self->{node};
	
	if (ref $node eq 'HASH') {
		my ($key, $value) = each %$node;
		$key =~ s/\^s+//;
		$key =~ s/\s+$//;
		if ($self->{functions}->{$key}) {
			my $a = $self->_trace($value);
			$a =~ s/;$//;
			return "sin(".$a.");" if ($key eq 'sin');
			return "cos(".$a.");" if ($key eq 'cos');
			return "cout << ".$a.";" if ($key eq 'print');
			return "cout << ".$a." << endl;" if ($key eq 'say');
		} elsif ($self->{cases}->{$key}) {
			my $a = $self->_trace($value->[0]);
			my $b = $self->_trace($value->[1]->{sub});
			return "if (". $a . ") {\n". $b . "\n}\n";
		} elsif ($self->{operators}->{$key}) {
			my ($a, $b) = @$value;
			$a = $self->_trace($a);
			$b = $self->_trace($b);
			return "$a + $b" if ($key eq '+');
			return "$a - $b" if ($key eq '-');
			return "$a * $b" if ($key eq '*');
			return "$a / $b" if ($key eq '/');
			return "$a ** $b" if ($key eq '**');
		} else {
			die $key;
			die Dumper $node;
		}
	} elsif (ref $node eq 'ARRAY') {
		my $s = '';
		for (@$node) {
			$s .= $self->_trace($_) . "\n";
		}
		return $s;
	} elsif (!ref $node) {
		return $node;
	} else {
		die Dumper $node;
	}
	return $node;
}

# Hack method for fix math priority: setup brackets to multi and div
sub prepare_multi_and_div {
	my $self = shift;
	my $str = shift;

	my @s = split //, $str;
	my $l = scalar (@s);
		
	for (my $i = 0 ; $i < $l ; $i ++) {
		my $c = $s[$i];
		if ($c ~~ ['*', '/']) {
			my $op = $c;
			$op = '**' if $s[$i+1] eq '*';
			# Go back
			for (my $j = $i - 1; $j >= 0 ; $j --) {
				my $cnt = 0;
				if ($j eq ')') {
					$cnt ++;
					next;
				} 
				if ($j eq '(') {
					$cnt --;
				}
				last if $cnt == -1;
				#warn "j==$j";
				if (($j == 0) || $self->{operators}->{$c}) {
					# Setup brackets
					# Go backward
					for (my $k = $j -1 ; $k >= 0 ; $k --) {
						if ($k == 0) {
							@s = ('(', @s);
							$i ++;
							$j ++;
							$k ++;
							$l ++;
							last;
						} 
						
						if ($self->{operators}->{$s[$k]}) {
							my @s1 = splice(@s, 0, $k+1);
							@s = (@s1, '(', @s);
							$i ++;
							$j ++;
							$k ++;
							$l ++;
							last;
						}
					}
					# Go forward
					$j ++ if $op eq '**';
					for (my $k = $j + 2 ; $k < $l ; $k ++) {
						#warn $k;
						if ($self->{operators}->{$s[$k]}) {
							my @s1 = splice(@s, 0, $k);
							@s = (@s1, ')', @s);
							$i ++;
							$j ++;
							$k ++;
							$l ++;
							last;
						}
						if ($k == $l - 1) {
							push @s, ')';
							$i ++;
							$j ++;
							$k ++;
							$l ++;
							last;
						} 

					}
					
					last;
				}
			}
		}
	}
	
	return (scalar (@s) >= length ($str)) ? join '', @s : $str;
}


sub prepare_cases {
	my $self = shift;
	my $str = shift;
	
	# need to recode
	$str =~ s/if\s*(\(.*?\))\s*(\{.*?\})/if ($1, $2);/gms;
	
	return $str;
}

sub parse {
	my $self = shift;
	my $str  = shift;
	$self->{digit} = '';
	$self->{node} = undef;
	$self->debug("Parse string original = $str");
	$str = $self->prepare_multi_and_div($str);
	$str = $self->prepare_cases($str);
	$self->debug("Parse string prepared = $str");
	my $node = $self->_depack($self->_parse ($str));
	$self->{node} = $node;
	return $node;
}

sub _depack {
	my $self = shift;
	my $node = shift;
	if (ref $node eq 'HASH') {
		my ($key, $value) = each %$node;
		$node = {$key => $self->_depack ($value)};
	} elsif (ref $node eq 'ARRAY') {
		if (scalar (@$node) == 1) {
			$node = $node->[0];
			return $self->_depack($node) ;
		} else {
			for (@$node) {
				$_ = $self->_depack ($_);
			}
		}
	} 
	return $node;
}

sub _parse {
	my $self = shift;
	my $str  = shift;
	my $node = [];
	
	$self->debug("Parse $str");
	
	my @s = split //, $str;
	my $sl = scalar (@s);
	
	my $function = '';
	my @expression = ();
	
	my $value = {};
	
	my $func;
	
	for (my $i = 0; $i < @s; $i++) {
		my $c = $s[$i];
		#$self->debug($c);
		if ($self->{operators}->{$c}) {
			my $op = $c;
			if ($op eq '*' && $s[$i+1] eq '*') {
				$op = '**';
				$i ++;
			}
			$self->debug("op = $op");
			if ($self->{digit}) {
				push @expression, $self->{digit};
				$self->{digit} = '';
			}
			if (ref $node eq 'ARRAY' && @$node) {
				$node = {$op => $node};
			} elsif (ref $node eq 'HASH') {
				$node = {$op => $node};
			} else {
				if ($op ~~ ['+', '-']) {
					
					my ($n, $idx) = $self->_parse_digit([@s[$i..$sl - 1]]);
					#push @$node, $n;
					$self->{digit} = $n;
					#push @expression, $self->{digit};
					
					push @$node, $self->{digit};
					$self->{digit} = '';
					$i = $i + $idx;
					
					#die $i;
					next;
					
				}
			}
			#push @$node, {$op => [@expression]};
			
			my $j;
			my $buff = '';
			my $cnt = 0;
			
			for ($j = $i + 1; $j < @s ; $j ++) {
				my $o = $s[$j];
				if ($o eq '(') {
					$cnt ++;
					#next;
				}
				if ($o eq ')') {
					$cnt --;
				} 
				
				
				
				$buff .= $o;
				$self->debug("$cnt, $buff");
				
				if ($cnt < 0 || $j == ($sl-1)) {
					#die $buff;
					#push @{$node->[-1]->{$op}}, $self->_parse ($buff);
					#warn Dumper $node->{$op};
					if (ref $node->{$op} eq 'HASH') {
						#warn Dumper $node;
						$node = {
							$op => [
								$node->{$op},
								$self->_parse ($buff),
							],
						};
					} else {
						push @{$node->{$op}}, $self->_parse ($buff);
					}
					last;
				} 
			}
			$i = $j;
			
			#@expression = ();
		} elsif ($c eq '(') {
			my $j;
			my $buff = '';
			for ($j = $i + 0; $j < @s ; $j ++) {
				my $o = $s[$j];
				$self->debug($o);
				$buff .= $o;
				my $cnt = 0;
				if ($o eq '(') {
					$cnt ++;
					next;
				}
				if ($o eq ')' || $j == scalar (@s) - 1) {
					$self->debug("$cnt , cnt00");
					$cnt --;
					if ($cnt == -1) {
						$self->debug("Buff sub = $buff");
						#die $function;
						push @$node, $self->_parse(substr($buff,1));
						#$node->{$function} = $self->_parse($buff);
						last;
					}
				}
			}
			$i = $j;
			$function = '';
			next;
		} elsif ($c eq '{') {
			
			my $j;
			my $buff = '';
			for ($j = $i + 0; $j < @s ; $j ++) {
				my $o = $s[$j];
				$self->debug($o);
				$buff .= $o;
				my $cnt = 0;
				if ($o eq '{') {
					$cnt ++;
					next;
				}
				if ($o eq '}' || $j == scalar (@s) - 1) {
					$self->debug("$cnt , cnt00");
					$cnt --;
					if ($cnt == -1) {
						$self->debug("Buff sub = $buff");
						#die $function;
						push @$node, {sub => $self->_parse(substr($buff,1))};
						#$node->{$function} = $self->_parse($buff);
						last;
					}
				}
			}
			$i = $j;
			$function = '';
		} elsif ($c =~ /[a-z]/) { # fuction processiong
			my $j;
			my $func_end = 0;
			my $buff = '';
			
			for ($j = $i; $j < @s ; $j ++) {
				
				my $o = $s[$j];
				if ($o eq '(') {
					$func_end = 1;
					my $j2;
					
					my $cnt = 1;
					for ($j2 = $j + 1; $j2 < @s ; $j2 ++) {
						my $o = $s[$j2];
						$buff .= $o;
						if ($o eq '(') {
							$cnt ++;
							next;
						}
						if ($o eq ')') {
							$cnt --;
							if ($cnt == 0) {
								last;
							}
						}
						
					}
					#$buff =~ s/^(.+).$/$1/;
					#warn $buff;
					$j = $j2;
					last;
				} elsif ($func_end == 0) {
					$func .= $o;
				}
				
				
			}
			$i = $j;	
			
			$self->debug("Found function = $func, buff = $buff");
			push @$node, {$func => $self->_parse($buff)};
			$func = '';
		} elsif ($c =~ /[0-9\.]/) {
			my @l = @s;
			@l = splice(@l, $i, $sl - 1);
			#warn Dumper \@l;
			$self->{digit} = '';
			my ($n, $idx) = $self->_parse_digit([@l]);
			$i = $idx + $i;
			push @$node, $n;
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
