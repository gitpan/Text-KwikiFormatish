use warnings;
use strict;
use Test::More tests => 2;

package My::Formatter;
use base 'Text::KwikiFormatish';
sub format { __PACKAGE__->new->process(@_) }
sub bold { 'HONK' }

package main;
my $out = My::Formatter::format('*test*');
like $out, qr/HONK/;
unlike $out, qr/<b>/;

