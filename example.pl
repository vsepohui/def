say (123456+100);

my $i = "Hello SCALAR " . "World";
say $i;

$i .= " TEST!";
say $i;

if ($i) {
	if (1) {
		say 123;
	};
};

while (1) {
	if (123) {
		say "Hello World";
	};
	last;
};


my @list = (1,2,3, "Hello LIST");
say scalar @list;
say $list[3];
say $list[-1];
