#!perl -w

use Test::More tests => 32;

use_ok( 'Text::KwikiFormatish' );

my ( $i, $o ); # output and input

my $link       = q(http://www.domain.com/dir/page.html);
my $link_regex = q(http://www\.domain\.com/dir/page\.html);

$i = <<_EOF;
= Header 1
== Header 2
=== Header 3
==== Header 4
===== Header 5
====== Header 6
= Header T1 =
= Header T2 ============
<escapeme>
----
##comment1
## comment2
* itemized
0 enumerated
  code
*strong*
//emphasized//
SomePage
negated !SomePage
$link
[testlink $link]
user\@domain.com
http://domain.com/image.png
| bacon | eggs |

para

[&icon test1.png]

[&img test2.png] [&img test3.png named image]

A [&glyph test4.png] B
C [&glyph test5.png named glyph] D

_EOF

# sanity check
eval {
    $o = Text::KwikiFormatish::format( $i );
    #open(FH,">temp"); print FH $o; close FH; #XXX
};
is( $@, '', 'format subroutine' );
isnt( length($o), 0, 'output produced' );

# link tests
like( $o, qr#<a[^>]+>SomePage</a>#, "link" );
like( $o, qr#<a[^>]+$link_regex[^>]+>$link_regex</a>#, "auto link" );
like( $o, qr#<a[^>]+$link_regex[^>]+>testlink</a>#, "named link" );
like( $o, qr#negated\s+SomePage#, "negated link" );

# markup tests
like( $o, qr#<img src="http://domain\.com/image\.png"#, "image href" );
foreach ( 1 .. 6 ) {
    like( $o, qr#<h$_>Header $_</h$_>#, "heading $_" );
}
foreach ( 1 .. 2 ) {
    like( $o, qr#<h1>Header T$_</h1>#, "heading 1 test $_, trailing '='" );
}
like( $o, qr#&lt;escapeme&gt;#, "escape_html" );
like( $o, qr#<hr/>#, "horizontal_line" );
foreach ( 1 .. 2 ) {
    like( $o, qr/<!--\s*comment$_\s*-->/, "comment $_" );
}
foreach ( qw( itemized enumerated ) ) {
    like( $o, qr#<li>$_#, $_ );
}
like( $o, qr#<pre>code#, "code" );
like( $o, qr#<strong>strong</strong>#, "strong" );
like( $o, qr#<em>emphasized</em>#, "emphasized" );
like( $o, qr#<p>\npara\n</p>#, "paragraph" );
like( $o, qr#<td>bacon</td>\s*<td>eggs</td>#, "table" );

# plugins
like( $o, qr#<img src="test1.png"#, "icon" );
like( $o, qr#<img\s+src="test2.png"#, "img" );
like( $o, qr#<img\s+src="test3.png"\s+alt="[^"]+"\s+title="named image"#, "named img" );
TODO: {
    local $TODO = 'glyph plugin not finished';
    like( $o, qr#A <img\s+src="test4.png"\s+alt="\*"[^>]*> B#, "glyph" );
    like( $o, qr#C <img\s+src="test5.png"\s+alt="named glyph"[^>]*> B#, "named glyph" );
}

