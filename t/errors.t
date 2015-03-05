use strict;
use warnings;

use Test::More;
use Test::Exception;

use FFI::Platypus;
use Errno qw(EINVAL);

use ZMQ::FFI;
use ZMQ::FFI::Constants qw(ZMQ_REQ);
use ZMQ::FFI::Util qw(zmq_soname);

subtest 'socket errors' => sub {
    $! = EINVAL;
    my $einval_str;

    {
        # get the EINVAL error string in a locale aware way
        use locale;
        use bytes;
        $einval_str = "$!";
    }

    my $ctx = ZMQ::FFI->new();

    throws_ok { $ctx->socket(-1) } qr/$einval_str/i,
        q(invalid socket type dies with EINVAL);


    my $socket = $ctx->socket(ZMQ_REQ);

    throws_ok { $socket->connect('foo') } qr/$einval_str/i,
        q(invalid endpoint dies with EINVAL);
};

subtest 'util errors' => sub {
    no warnings q/redefine/;

    local *FFI::Platypus::function = sub  { return; };

    throws_ok { zmq_soname(die => 1) } qr/Could not load libzmq/,
        q(zmq_soname dies when die => 1 and FFI::Platypus->function fails);

    lives_ok {
        ok !zmq_soname();
    } q(zmq_soname lives and returns undef when die => 0 and FFI::Platypus->function fails);
};

done_testing;
