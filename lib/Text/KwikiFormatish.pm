package Text::KwikiFormatish;
use strict;
use warnings;

our $VERSION = '1.00';

use CGI::Util qw(escape unescape);

use vars qw($UPPER $LOWER $ALPHANUM $WORD $WIKIWORD);
$UPPER    = '\p{UppercaseLetter}';
$LOWER    = '\p{LowercaseLetter}';
$ALPHANUM = '\p{Letter}\p{Number}';
$WORD     = '\p{Letter}\p{Number}\p{ConnectorPunctuation}';
$WIKIWORD = "$UPPER$LOWER\\p{Number}\\p{ConnectorPunctuation}";

############# BEGIN USER FUNCTIONS ##############

sub user_functions {
    qw(
        icon
        img
        glyph
    );
}

sub icon {
    my ($self, $href) = @_;
    return qq( <img src="$href" class="icon" alt="(icon)" /> );
}

sub img {
    my ($self, $href, @title) = @_;
    my $title = join(' ',@title) || '';
    my $output = qq( <p style="text-align:center;"><img 
        src="$href" alt="(see caption below)" title="$title" 
        align="middle" border="0" /> );
    $output .= @title ? "<br/><small>$title</small>" : '';
    return $output . '</p>';
}

# FIXME - BROKEN! Plugins like to separate the paragraphs
sub glyph {
    my ($self, $href, @title) = @_;
    my $title = join(' ',@title) || '*';
    return qq( <img 
        src="$href" 
        alt="$title" title="$title" 
        align="middle" border="0" 
        /> );
}

############# END USER FUNCTIONS ##############

# Text::WikiFormat-compatible format class method
sub format {
    my ($raw, %args) = @_;

    # create instance of formatter
    my $f = __PACKAGE__->new();

    # translate Text::Wikiformat args to Kwiki formatter args
    $f->{_node_prefix} = $args{prefix} if exists $args{prefix};

    # do the deed
    return $f->process($raw);
}

sub new {
    my ($class, @args) = @_;
    my $self = {};
    bless $self, $class;
    $self->_init(@args) or return undef;
    return $self;
}

sub _init {
    my ($self, %args) = @_;
    my %defs = (    node_prefix     => './', );
    my %collated = (%defs, %args);
    foreach my $k (keys %defs) {
        $self->{"_".$k} = $collated{$k};
    }
    return $self;
}

sub process_order {
    return qw(
        function
        header_1 header_2 header_3 header_4 header_5 header_6 
        escape_html
        horizontal_line comment lists
        code paragraph 
        named_http_link no_http_link http_link
        no_mailto_link mailto_link
        no_wiki_link force_wiki_link wiki_link
        inline negation
        bold italic underscore
        mdash
        table
    );
}

sub process {
    my ($self, $wiki_text) = @_;
    my $array = [];
    push @$array, $wiki_text;
    for my $method ($self->process_order) {
        $array = $self->dispatch($array, $method);
    }
    return $self->combine_chunks($array);
}

sub dispatch {
    my ($self, $old_array, $method) = @_;
    return $old_array unless $self->can($method);
    my $new_array;
    for my $chunk (@$old_array) {
        if (ref $chunk eq 'ARRAY') {
            push @$new_array, $self->dispatch($chunk, $method);
        }
        else {
            if (ref $chunk) {
                push @$new_array, $chunk;
            }
            else {
                push @$new_array, $self->$method($chunk);
            }
        }
    }
    return $new_array;
}

sub combine_chunks {
    my ($self, $chunk_array) = @_;
    my $formatted_text = '';
    for my $chunk (@$chunk_array) {
        $formatted_text .= 
          (ref $chunk eq 'ARRAY') ? $self->combine_chunks($chunk) :
          (ref $chunk) ? $$chunk :
          $chunk
    }
    return $formatted_text;
}

sub split_method {
    my ($self, $text, $regexp, $method) = @_;
    my $i = 0;
    map {$i++ % 2 ? \ $self->$method($_) : $_} split $regexp, $text;
}

sub isa_function {
    my ($self, $function) = @_;
    defined { map { ($_, 1) } $self->user_functions }->{$function} and
    $self->can($function)
}

sub function {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{\[\&(\w+\b.*?)\]},
        'function_format',
    );
}

sub function_format {
    my ($self, $text) = @_;
    my ($method, @args) = split;
    $self->isa_function($method) 
      ? $self->$method(@args)
      : "<!-- Function not supported here: $text -->\n";
}

sub escape_html {
    my ($self, $text) = @_;
    $text =~ s/&/&amp;/g;
    $text =~ s/</&lt;/g;
    $text =~ s/>/&gt;/g;
    $text;
}

sub table {
    my ($self, $text) = @_;
    my @array;
    while ($text =~ /(.*?)(^\|[^\n]*\|\n.*)/ms) {
        push @array, $1;
        my $table;
        ($table, $text) = $self->parse_table($2);
        push @array, $table;
    }
    push @array, $text if length $text;
    return @array;
}

sub parse_table {
    my ($self, $text) = @_;
    my $error = '';
    my $rows;
    while ($text =~ s/^(\|(.*)\|\n)//) {
        $error .= $1;
        my $data = $2;
        my $row = [];
        for my $datum (split /\|/, $data) {
            $datum =~ s/^\s*(.*?)\s*$/$1/;
            if ($datum =~ s/^<<(\S+)$//) {
                my $marker = $1;
                while ($text =~ s/^(.*\n)//) {
                    my $line = $1;
                    $error .= $line;
                    if ($line eq "$marker\n") {
                        $marker = '';
                        last;
                    }
                    $datum .= $line;
                }
                if (length $marker) {
                    return ($error, $text);
                }
            }
            push @$row, $datum;
        }
        push @$rows, $row;
    }
    return ($self->format_table($rows), $text);
}

sub format_table {
    my ($self, $rows) = @_;
    my $cols = 0;
    for (@$rows) {
        $cols = @$_ if @$_ > $cols;
    }
    my $table = qq{<table border="1">\n};
    for my $row (@$rows) {
        $table .= qq{<tr valign="top">\n};
        for (my $i = 0; $i < @$row; $i++) {
            my $colspan = '';
            if ($i == $#{$row} and $cols - $i > 1) {
                $colspan = ' colspan="' . ($cols - $i) . '"';
            }
            my $cell = $self->escape_html($row->[$i]);
            $cell = qq{<pre>$cell</pre>\n}
              if $cell =~ /\n/;
            $cell = '&nbsp;' unless length $cell;
            $table .= qq{<td$colspan>$cell</td>\n};
        }
        $table .= qq{</tr>\n};
    }
    $table .= qq{</table>\n};
    return \$table;
}

sub no_wiki_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{!([$UPPER](?=[$WORD]*[$UPPER])(?=[$WORD]*[$LOWER])[$WORD]+)},
        'no_wiki_link_format',
    );
}

sub no_wiki_link_format {
    my ($self, $text) = @_;
    return $text;
}

sub wiki_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{([$UPPER](?=[$WORD]*[$UPPER])(?=[$WORD]*[$LOWER])[$WORD]+)},
        'wiki_link_format',
    );
}

sub force_wiki_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(?<!\!)\[([$ALPHANUM\-:]+)\]},
        'wiki_link_format',
    );
}

sub wiki_link_format {
    my ($self, $text) = @_;
    my $url = $self->escape($text);
    my $wiki_link = qq{<a href="./$url">$text</a>};
    return $wiki_link;
}

sub no_http_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(!(?:https?|ftp|irc):\S+?)}m,
        'no_http_link_format',
    );
}

sub no_http_link_format {
    my ($self, $text) = @_;
    $text =~ s#!##;
    return $text;
}

sub http_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{((?:https?|ftp|irc):\S+?(?=[),.:;]?\s|$))}m,
        'http_link_format',
    );
}

sub http_link_format {
    my ($self, $text) = @_;
    if ($text =~ /^http.*\.(?i:jpg|gif|jpeg|png)$/) {
        return $self->img_format($text);
    }
    else {
        return $self->link_format($text);
    }
}

sub no_mailto_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(![$ALPHANUM][$WORD\-\.]*@[$WORD][$WORD\-\.]+)}m,
        'no_mailto_link_format',
    );
}

sub no_mailto_link_format {
    my ($self, $text) = @_;
    $text =~ s#!##;
    return $text;
}

sub mailto_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{([$ALPHANUM][$WORD\-\.]*@[$WORD][$WORD\-\.]+)}m,
        'mailto_link_format',
    );
}

sub mailto_link_format {
    my ($self, $text) = @_;
    my $dot = ($text =~ s/\.$//) ? '.' : '';
    qq{<a href="mailto:$text">$text</a>$dot};
}

sub img_format {
    my ($self, $url) = @_;
    return qq{<img src="$url">};
}

sub link_format {
    my ($self, $text) = @_;
    $text =~ s/(^\s*|\s+(?=\s)|\s$)//g;
    my $url = $text;
    $url = $1 if $text =~ s/(.*?) +//;
    $url =~ s/https?:(?!\/\/)//;
    return qq{<a href="$url">$text</a>};
}

sub named_http_link {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(?<!\!)\[([^\[\]]*?(?:https?|ftp|irc):\S.*?)\]},
        'named_http_link_format',
    );
}

sub named_http_link_format {
    my ($self, $text) = @_;
    if ($text =~ m#(.*)((?:https?|ftp|irc):.*)#) {
        $text = "$2 $1";
    }
    return $self->link_format($text);
}

sub inline {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(?<!\!)\[=(.*?)(?<!\\)\]},
        'inline_format',
    );
}

sub inline_format {
    my ($self, $text) = @_;
    "<code>$text</code>";
}

sub negation {
    my ($self, $text) = @_;
    $text =~ s#\!(?=\[)##g;
    return $text;
}

sub bold {
    my ($self, $text) = @_;
    $text =~ s#(?<![$WORD])\*(\S.*?\S|\S)\*(?![$WORD])#<strong>$1</strong>#g;
    return $text;
}

sub italic {
    my ($self, $text) = @_;
    $text =~ s#(?<![$WORD<])//(\S.*?\S|\S)//(?![$WORD])#<em>$1</em>#g;
    return $text;
}

sub underscore {
    my ($self, $text) = @_;
    $text =~ s#(?<![$WORD])_(\S.*?\S)_(?![$WORD])#<u>$1</u>#g;
    return $text;
}

sub code {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{(^ +[^ \n].*?\n)(?-ms:(?=[^ \n]|$))}ms,
        'code_format',
    );
}

sub code_format {
    my ($self, $text) = @_;
    $self->code_postformat($self->code_preformat($text));
}

sub code_preformat {
    my ($self, $text) = @_;
    my ($indent) = sort { $a <=> $b } map { length } $text =~ /^( *)\S/mg;
    $text =~ s/^ {$indent}//gm;
    #return $self->escape_html($text); ## already done in process order
    return $text;
}

sub code_postformat {
    my ($self, $text) = @_;
    return "<pre>$text</pre>\n";
}

sub lists {
    my ($self, $text) = @_;
    my $switch = 0;
    return map {
        my $level = 0;
        my @tag_stack;
        if ($switch++ % 2) {
            my $text = '';
            my @lines = /(.*\n)/g;
            for my $line (@lines) {
                $line =~ s/^([0\*]+) //;
                my $new_level = length($1);
                my $tag = ($1 =~ /0/) ? 'ol' : 'ul';
                if ($new_level > $level) {
                    for (1..($new_level - $level)) {
                        push @tag_stack, $tag;
                        $text .= "<$tag>\n";
                    }
                    $level = $new_level;
                }
                elsif ($new_level < $level) {
                    for (1..($level - $new_level)) {
                        $tag = pop @tag_stack;
                        $text .= "</$tag>\n";
                    }
                    $level = $new_level;
                }
                $text .= "<li>$line</li>";
            }
            for (1..$level) {
                my $tag = pop @tag_stack;
                $text .= "</$tag>\n";
            }
            $_ = $self->lists_format($text);
        }
        $_;
    }
    split m!(^[0\*]+ .*?\n)(?=(?:[^0\*]|$))!ms, $text;
}

sub lists_format {
    my ($self, $text) = @_;
    return $text;
}

sub paragraph {
    my ($self, $text) = @_;
    my $switch = 0;
    return map {
        unless ($switch++ % 2) {
            $_ = $self->paragraph_format($_);
        }
        $_;
    }
    split m!(\n\s*\n)!ms, $text;
}

sub paragraph_format {
    my ($self, $text) = @_;
    return '' if $text =~ /^[\s\n]*$/;
    return $text if $text =~ /^<(o|u)l>/i;
    return "<p>\n$text\n</p>\n";
}

sub horizontal_line {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{^(----+)\s*$}m,
        'horizontal_line_format',
    );
}

sub horizontal_line_format {
    my ($self) = @_;
    my $text = "<hr/>\n";
    return $text;
}

sub mdash {
    my ($self, $text) = @_;
    $text =~ s/([$WORD])-{3}([$WORD])/$1&#151;$2/g;
    return $text;
}

sub comment {
    my ($self, $text) = @_;
    $self->split_method($text,
        qr{^\#\#(.*)$}m,
        'comment_line_format',
    );
}

sub comment_line_format {
    my ($self, $text) = @_;
    return "<!-- $text -->\n";
}

for my $num (1..6) {
    no strict 'refs';
    *{"header_$num"} = 
    sub {
        my ($self, $text) = @_;
        $self->split_method($text,
            qr#^={$num} (.*?)(?: =*)?\n#m,
            "header_${num}_format",
        );
    };
    *{"header_${num}_format"} = 
    sub {
        my ($self, $text) = @_;
        $text =~ s/=+\s*$//;
        return "<h$num>$text</h$num>\n";
    };
}

1;

__END__

=head1 NAME

Text::KwikiFormatish - convert Kwikitext into XML-compliant HTML

=head1 SYNOPSIS

  use Text::KwikiFormatish;
  my $xml = Text::KwikiFormatish::format($text);

=head1 DESCRIPTION

B<NOTE: This is a beta release.> Version 1.00 will be released by February, 2004 if not sooner.

L<CGI::Kwiki> includes a formatter (L<CGI::Kwiki::Formatter>) for converting Kwikitext (a nice form of wikitext) to HTML. Unfortunately, it isn't easy to use the formatter outside the L<CGI::Kwiki> environment. Additionally, the HTML produced by the formatter isn't XHTML-1 compliant. This module aims to fix both of these issues and provide an interface similar to L<Text::WikiFormat>.

Essentially, this module is the code from Brian Ingerson's L<CGI::Kwiki::Formatter> with a C<format> subroutine, code relating to slides removed, tweaked subroutinesa, and more. 

Since the wikitext spec for input wikitext for this module differs a little from the default Kwiki formatter, I thought it best to call it "Formatish" instead of *the* Kwiki Format.

=head2 format()

C<format()> takes one or two arguments, with the first always being the wikitext to translate. The second is a hash of options, but currently the only option supported is C<prefix> in case you want to prefix wiki links with sommething. For example,

  my $xml = Text::KwikiFormatish::format(
    $text,
    prefix => '/wiki/',
    );

=head2 Differences from the Kwiki Formatter

=over 4

=item * The output of the formatter is XML-compliant.

=item * Extra equal signs at the end of headings will be removed from the output for compatibility with other wikitext formats.

=item * Italicized text is marked up by two slashes instead of one. This is to prevent weirdness when writing filesystem paths in Kwikitext -- e.g., the text "Check /etc or /var or /usr/" will have unexpected results when formatted in a regular Kwiki.

=item * Horizontal rules, marked by four or more hyphens, may be followed by spaces. 

=item * Processing order of text segments has been changed (tables are processed last)

=item * Bold text is marked up as C<E<lt>strongE<gt>> instead of C<E<lt>bE<gt>>

=item * "Inline" is marked up as C<E<lt>codeE<gt>> instead of C<E<lt>ttE<gt>>

=item * mdashes (really long hyphens) are created with wikitext C<like---this>

=item * Tables and code sections are not indented with C<E<lt>blockquoteE<gt>> tags

=item * Comments do not have to have a space immediately following the hash

=item * Patch to named_link code

=item * All code pertaining to slides or Kwiki access control is removed, as neither are within the scope of this module

=head2 Plugins

I've included two plugins, C<img> and C<icon>, to do basic image support besides the standard operation of including an image when the URL ends with a common image extension.

=back

=head1 EXAMPLES

Here's some kwiki text:

    = Level 1 Header

    == Level 2 with optional trailing equals ==
    
    Kwikitext provides a bit more flexibility than regular wikitext.
    
    All HTML code is <escaped>. Horizontal rules are four or more hyphens:
    
    ----

    While you can add an mdash---like this.
    
    ##
    ## you can add comments in the kwikitext which appear as XML comments
    ##
    
    == Links
    
    === Itemized Lists
    
    * Fruit
    ** Oranges
    ** Apples
    * Eggs
    * Salad
    
    === Enumerated Lists
    
    ##
    ## below are zero's, not "oh's"
    ##
    
    0 One
    0 Two
    0 Three
    
    * Comments in the wikitext
    * Easier:
    ** Bold/strong
    ** Italic/emphasized
    
    == More Markup
    
    *strong or bold text*
    
    //emphasized or italic text//
    
      indented text is verbatim (good for code)
    
    == Links
    
    WikiLink
    
    !NotAWikiLink
    
    http://www.kwiki.org/
    
    [Kwiki named link http://www.kwiki.org/]

    == Images

    http://search.cpan.org/s/img/cpan_banner.png
    
    == KwikiFormatish plugins
    
    This inserts an image with the CSS class of "icon" -- good for inserting a right-aligned image for text to wrap around.
    
    [&icon /images/logo.gif]
    
    The following inserts an image with an optional caption:
    
    [&img /images/graph.gif Last Month's Earnings]

=head1 AUTHOR

Ian Langworth - ian[aught]cpan.org

=head1 SEE ALSO

L<CGI::Kwiki>, L<CGI::Kwiki::Formatter>, L<Text::WikiFormat>

=head1 LICENSE

This is free software. You may use it and redistribute it under the same terms as perl itself.

=cut
