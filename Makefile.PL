use inc::Module::Install;

name        ('Text-KwikiFormatish');
abstract    ('convert Kwikitext into XML-compliant HTML');
author      ('Ian Langworth <langworth.com>');
version_from('lib/Text/KwikiFormatish.pm');
license     ('perl');
requires    (qw(
    CGI::Util
));

WriteAll();
