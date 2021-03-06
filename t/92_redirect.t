
use strict;
use Plack::Test;
use Test::More tests => 8;
use MyApp;

# 
test_psgi
    app => MyApp->handler,
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => 'http://localhost/redirect' );
        my $res = $cb->( $req );
        is $res->code, '302';
        is $res->headers->header('Location'), 'http://localhost/';

    } ;

test_psgi
    app => MyApp->handler,
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => 'http://localhost/redirect?foo=bar' );
        my $res = $cb->( $req );
        is $res->code, '302';
        is $res->headers->header('Location'), 'http://localhost/';

    } ;

test_psgi
    app => MyApp->handler,
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => 'http://localhost/redirect2?foo=bar' );
        my $res = $cb->( $req );
        is $res->code, '302';
        is $res->headers->header('Location'), 'http://search.cpan.org/';

    } ;

test_psgi
    app => MyApp->handler,
    client => sub {
        my $cb = shift;
        my $req = HTTP::Request->new( GET => 'http://localhost/redirect_and_abort' );
        my $res = $cb->( $req );
        is $res->code, '302';
        is $res->headers->header('Location'), 'http://www.livedoor.com/';

    } ;


