use ExtUtils::MakeMaker;

WriteMakefile(
    'NAME'          => 'Text::KwikiFormatish',
    'ABSTRACT_FROM' => 'lib/Text/KwikiFormatish.pm',
    'VERSION_FROM'  => 'lib/Text/KwikiFormatish.pm',
    'AUTHOR'        => 'Ian Langworth <ian@langworth.com>',
    dist => {
        'PREOP'     => 'pod2text lib/Text/KwikiFormatish.pm >README',
    },
    'PREREQ_PM'     => { 
        'CGI::Util',
    },
);
