use Test::More;
use strict;
use warnings;

use ZMQ::FFI;
use ZMQ::FFI::ZMQ2::Context;
use ZMQ::FFI::ZMQ2::Socket;

use ZMQ::FFI::Constants qw(ZMQ_REQ);

my @gc_stack;

usesocket();

is_deeply
    \@gc_stack,
    ['socket', 'ctx'],
    q(socket reaped before context);

sub usesocket {
    my $s = mksocket();

    # socket should get reaped, then ctx
    return;
}

sub mksocket {
    no warnings q/redefine/;

    my $ctx = ZMQ::FFI->new();
    *ZMQ::FFI::ZMQ2::Context::DEMOLISH = sub { push @gc_stack, 'ctx' };

    my $s = $ctx->socket(ZMQ_REQ);
    *ZMQ::FFI::ZMQ2::Socket::DEMOLISH = sub { push @gc_stack, 'socket' };

    # ctx should not get reaped
    return $s;
}

done_testing;
